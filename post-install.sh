#!/bin/bash

# ===================================================================================
#
#          FILE:  post-install.sh
#
#         USAGE:  ./post-install.sh
#
#   DESCRIPTION:  Script para automatizar a instalação e configuração de
#                 programas em uma nova instalação do Fedora.
#
#       OPTIONS:  ---
#  REQUIREMENTS:  Acesso à internet e privilégios de superusuário (sudo).
#          BUGS:  ---
#         NOTES:  Execute este script como um usuário normal. Ele solicitará
#                 a senha de administrador (sudo) quando necessário.
#        AUTHOR:  Henrique Bissoli Malaman Alonso
#       VERSION:  2.4
#
# ===================================================================================

# Encerra o script imediatamente se um comando falhar.
set -e
# Garante que o status de saída de um pipeline seja o do último comando a falhar.
set -o pipefail

# --- Definição de Cores ---
CYAN='\e[0;36m'
BLUE='\e[0;34m'
GREEN='\e[0;32m'
RED='\e[0;31m'
YELLOW='\e[0;33m'
MAGENTA='\e[0;35m'
BOLD_GREEN='\e[1;32m'
NC='\e[0m' # No Color (Reset)

# Função para imprimir um cabeçalho de seção formatado.
print_header() {
    printf "\n${CYAN}======================================================================${NC}\n"
    printf "${CYAN}  %s${NC}\n" "$1"
    printf "${CYAN}======================================================================${NC}\n"
}

# --- Funções de Instalação ---

# 1. Atualiza o sistema
update_system() {
    print_header "Atualizando o sistema com DNF"
    sudo dnf upgrade -y
}

# 2. Instala RPM Fusion, Java e Codecs Multimídia
setup_multimedia_and_java() {
    print_header "Instalando RPM Fusion, Java e Codecs Multimídia"

    echo -e "${MAGENTA}--> Adicionando repositórios RPM Fusion (free e non-free)...${NC}"
    sudo dnf install -y \
      https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
      https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm

    echo -e "${BLUE}--> Atualizando o grupo de pacotes 'core'...${NC}"
    sudo dnf group upgrade -y core

    echo -e "${BLUE}--> Instalando Java, pacotes multimídia e codecs...${NC}"
    sudo dnf group install -y multimedia
    sudo dnf install -y \
      java-latest-openjdk.x86_64 \
      gstreamer1-plugin-openh264 \
      mozilla-openh264 \
      dnf5-plugins \
      dnf-plugins-core
}

# 3. Instala o Oh My Bash
install_oh_my_bash() {
    print_header "Instalando o Oh My Bash"
    if [ -d "$HOME/.oh-my-bash" ]; then
        echo -e "${YELLOW}--> Oh My Bash já está instalado. Pulando.${NC}"
    else
        echo -e "${BLUE}--> Instalando Oh My Bash...${NC}"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" "" --unattended
    fi
}

# 4. Configura o Flatpak e instala os aplicativos
setup_flatpak() {
    print_header "Configurando o Flatpak e instalando aplicativos"
    sudo dnf install -y flatpak

    echo -e "${MAGENTA}--> Adicionando e habilitando o repositório Flathub...${NC}"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    flatpak remote-modify --enable flathub

    # Lista de aplicativos Flatpak para instalar
    local FLATPAK_APPS=(
        com.spotify.Client com.usebruno.Bruno com.discordapp.Discord
        com.github.tchx84.Flatseal it.mijorus.gearlever
        com.mattjakeman.ExtensionManager com.heroicgameslauncher.hgl
        com.github.PintaProject.Pinta app.zen_browser.zen
        io.github.flattool.Warehouse io.podman_desktop.PodmanDesktop
    )

    echo -e "${BLUE}--> Instalando aplicativos via Flatpak...${NC}"
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info "$app" > /dev/null 2>&1; then
            echo -e "${YELLOW}--> O aplicativo '$app' já está instalado. Pulando.${NC}"
        else
            echo -e "${BLUE}--> Instalando: $app${NC}"
            flatpak install -y flathub "$app"
        fi
    done
}

# 5. Instala ferramentas de desenvolvimento (VS Code, GitHub CLI, Docker, Podman)
install_dev_tools() {
    print_header "Instalando Ferramentas de Desenvolvimento"

    # --- Adiciona repositórios de terceiros ---
    echo -e "${MAGENTA}--> Adicionando repositórios necessários...${NC}"

    if [ ! -f "/etc/yum.repos.d/gh-cli.repo" ]; then
        echo -e "${MAGENTA}--> Adicionando repositório do GitHub CLI...${NC}"
        sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
    else
        echo -e "${YELLOW}--> Repositório do GitHub CLI já existe. Pulando.${NC}"
    fi
    sudo dnf install -y gh --repo gh-cli

    if [ ! -f "/etc/yum.repos.d/vscode.repo" ]; then
        echo -e "${MAGENTA}--> Adicionando repositório do Visual Studio Code...${NC}"
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null    
    else
        echo -e "${YELLOW}--> Repositório do Visual Studio Code já existe. Pulando.${NC}"
    fi

    if [ ! -f "/etc/yum.repos.d/docker-ce.repo" ]; then
        echo -e "${MAGENTA}--> Adicionando repositório do Docker...${NC}"
        sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    else
        echo -e "${YELLOW}--> Repositório do Docker já existe. Pulando.${NC}"
    fi
    
    # --- Instala pacotes via DNF ---
    echo -e "${BLUE}--> Instalando pacotes: gh, code, podman, docker e dependências...${NC}"
    sudo dnf install -y \
      code podman podman-machine docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin fastfetch
}

# 6. Instala NVM, Node.js, PHP e Composer
install_web_dev_stack() {
    print_header "Instalando Stack de Desenvolvimento Web (NVM, Node.js, PHP, Composer)"

    # --- Instala NVM e Node.js ---
    echo -e "${GREEN}--> Baixando e instalando o NVM (Node Version Manager)...${NC}"

    if [ ! -d "$HOME/.nvm" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

        echo -e "${BLUE}--> Instalando a versão 22 do Node.js...${NC}"
        nvm install 22
        nvm use 22
        nvm alias default 22

        echo -e "${BLUE}--> Atualizando o npm para a versão mais recente...${NC}"
        npm install -g npm@latest

        # --- Instala pnpm ---
        echo -e "${BLUE}--> Instalando pnpm...${NC}"
        npm install -g pnpm@latest-10
    else
        echo -e "${YELLOW}--> NVM já está instalado. Pulando download.${NC}"
    fi

    # --- Instala PHP e extensões ---
    echo -e "${BLUE}--> Instalando PHP e extensões via DNF...${NC}"
    
    sudo dnf install -y \
      php php-cli php-fpm php-mysqlnd php-gd php-intl php-mbstring php-pdo \
      php-xml php-pecl-zip php-bcmath php-sodium php-opcache php-devel php-common

    # --- Instala Composer e Laravel Installer ---
    echo -e "${BLUE}--> Instalando o Composer...${NC}"
    if ! command -v composer &> /dev/null; then
        cd /tmp
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        local EXPECTED_SIGNATURE=$(curl -s https://composer.github.io/installer.sig)
        local ACTUAL_SIGNATURE=$(php -r "echo hash_file('sha384', 'composer-setup.php');")
        if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
            >&2 echo '${RED}ERRO: Assinatura do instalador do Composer é inválida.${NC}'
            rm composer-setup.php
            exit 1
        fi
        php composer-setup.php
        php -r "unlink('composer-setup.php');"
        sudo mv composer.phar /usr/local/bin/composer
        cd - > /dev/null
    else
        echo -e "${YELLOW}--> Composer já está instalado. Pulando.${NC}"
    fi
    
    local COMPOSER_VENDOR_PATH="$HOME/.config/composer/vendor/bin"
    if ! grep -q "$COMPOSER_VENDOR_PATH" "$HOME/.bash_profile"; then
      echo -e '\n# Add Composer global bin to PATH\nexport PATH="$PATH:'"$COMPOSER_VENDOR_PATH"'"' >> "$HOME/.bash_profile"
    fi
    export PATH="$PATH:$COMPOSER_VENDOR_PATH"

    echo -e "${BLUE}--> Instalando o Laravel Installer globalmente...${NC}"
    composer global require laravel/installer
}

# 7. Instala pnpm e fontes customizadas
install_fonts() {
    print_header "Instalando fontes (JetBrains Mono, Nerd Fonts)"

    # --- Instala Fontes ---
    local DOWNLOAD_DIR="$HOME/Downloads"
    mkdir -p "$DOWNLOAD_DIR"

    # --- JetBrains Mono (Regular) ---
    local JB_FONT_INSTALL_DIR="/usr/local/share/fonts/JetBrainsMono"

    if [ ! -d "$JB_FONT_INSTALL_DIR" ]; then
        echo -e "${GREEN}--> Baixando e instalando a fonte JetBrains Mono...${NC}"
        local JB_FONT_URL="https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip"
        local JB_FONT_ZIP="$DOWNLOAD_DIR/JetBrainsMono.zip"
        local JB_FONT_EXTRACT_DIR="$DOWNLOAD_DIR/jetbrains-mono-extracted"

        curl -L "$JB_FONT_URL" -o "$JB_FONT_ZIP"
        unzip -o "$JB_FONT_ZIP" -d "$JB_FONT_EXTRACT_DIR"
        sudo mkdir -p "$JB_FONT_INSTALL_DIR"
        sudo cp -f "$JB_FONT_EXTRACT_DIR"/fonts/ttf/*.ttf "$JB_FONT_INSTALL_DIR/"

        rm -rf "$JB_FONT_ZIP"
        rm -rf "$JB_FONT_EXTRACT_DIR"
    else
        echo -e "${YELLOW}--> Fonte JetBrains Mono já está instalada. Pulando.${NC}"
    fi

    # --- JetBrains Mono (Nerd Font) ---
    local NF_FONT_INSTALL_DIR="/usr/local/share/fonts/JetBrainsMonoNF"

    if [ ! -d "$JB_FONT_INSTALL_DIR" ]; then
        echo -e "${GREEN}--> Baixando e instalando a fonte JetBrains Mono Nerd Font...${NC}"
        local NF_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"
        local NF_FONT_ZIP="$DOWNLOAD_DIR/JetBrainsMonoNF.zip"
        local NF_FONT_EXTRACT_DIR="$DOWNLOAD_DIR/jetbrains-mono-nf-extracted"

        curl -L "$NF_FONT_URL" -o "$NF_FONT_ZIP"
        unzip -o "$NF_FONT_ZIP" -d "$NF_FONT_EXTRACT_DIR"
        sudo mkdir -p "$NF_FONT_INSTALL_DIR"
        sudo cp -f "$NF_FONT_EXTRACT_DIR"/*.ttf "$NF_FONT_INSTALL_DIR/"

        rm -rf "$NF_FONT_ZIP"
        rm -rf "$NF_FONT_EXTRACT_DIR"
    else
        echo -e "${YELLOW}--> Fonte JetBrains Mono Nerd Font já está instalada. Pulando.${NC}"
    fi

    # --- Configura permissões e atualiza cache de fontes ---
    echo -e "${BLUE}--> Configurando permissões e atualizando o cache de fontes do sistema...${NC}"
    if [ -d "$JB_FONT_INSTALL_DIR" ] && [ -d "$NF_FONT_INSTALL_DIR" ]; then
        sudo chown -R root: "$JB_FONT_INSTALL_DIR" "$NF_FONT_INSTALL_DIR"
        sudo chmod 644 "$JB_FONT_INSTALL_DIR"/* "$NF_FONT_INSTALL_DIR"/*
        sudo restorecon -vFr "$JB_FONT_INSTALL_DIR" "$NF_FONT_INSTALL_DIR"
    fi
    sudo fc-cache -fv
}


# 8. Instala dependências, Flutter e JetBrains Toolbox
install_flutter_and_jetbrains() {
    print_header "Instalando Flutter, JetBrains Toolbox e dependências"

    echo -e "${BLUE}--> Instalando dependências de compilação e do Flutter...${NC}"
    sudo dnf install -y \
      curl git unzip xz zip ninja-build cmake clang meson systemd-devel \
      pkg-config dbus-devel inih-devel fuse fuse-libs gtk3-devel egl-utils

    # --- Cria diretórios de trabalho ---
    local DEV_DIR="$HOME/development"
    local DOWNLOAD_DIR="$HOME/Downloads"
    mkdir -p "$DEV_DIR" "$DOWNLOAD_DIR"

    # --- Instala Flutter ---
    local FLUTTER_DIR="$DEV_DIR/flutter"
    if [ ! -d "$FLUTTER_DIR" ]; then
        echo -e "${GREEN}--> Baixando o Flutter SDK...${NC}"
        local FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.22.2-stable.tar.xz"
        local FLUTTER_ARCHIVE="$DOWNLOAD_DIR/flutter.tar.xz"
    
        curl -L "$FLUTTER_URL" -o "$FLUTTER_ARCHIVE"
        tar -xf "$FLUTTER_ARCHIVE" -C "$DEV_DIR"
        
        rm "$FLUTTER_ARCHIVE"
    else
        echo -e "${YELLOW}--> Flutter SDK já encontrado em '$FLUTTER_DIR'. Pulando.${NC}"
    fi
    
    
    if ! grep -q 'development/flutter/bin' "$HOME/.bash_profile"; then
      echo -e '\n# Add Flutter to PATH\nexport PATH="$PATH:$HOME/development/flutter/bin"' >> "$HOME/.bash_profile"
    fi
    
    # --- Instala JetBrains Toolbox ---
    if ! find "$DEV_DIR" -maxdepth 1 -type d -name "jetbrains-toolbox-*" | grep -q .; then
        echo -e "${GREEN}--> Baixando o JetBrains Toolbox...${NC}"
        local JETBRAINS_URL="https://data.services.jetbrains.com/products/download?code=TBA&platform=linux&type=release"
        local JETBRAINS_ARCHIVE="$DOWNLOAD_DIR/jetbrains-toolbox.tar.gz"
        
        curl -L "$JETBRAINS_URL" -o "$JETBRAINS_ARCHIVE"
        
        tar -xzf "$JETBRAINS_ARCHIVE" -C "$DEV_DIR"
        local TOOLBOX_DIR=$(find "$DEV_DIR" -maxdepth 1 -type d -name "jetbrains-toolbox-*")
        
        if [ -d "$TOOLBOX_DIR" ]; then
            nohup "$TOOLBOX_DIR/jetbrains-toolbox" > /dev/null 2>&1 &
        else
            echo -e "${RED}ERRO: Não foi possível encontrar o diretório do JetBrains Toolbox.${NC}"
        fi

        rm "$JETBRAINS_ARCHIVE"
    else
      echo -e "${YELLOW}--> JetBrains Toolbox já encontrado em '$DEV_DIR'. Pulando.${NC}"
    fi
}

# 9. Configura o Docker e instala o Docker Desktop
configure_docker() {
    print_header "Configurando o Docker e instalando o Docker Desktop"
    
    sudo systemctl enable --now docker
    sudo groupadd -f docker
    if ! groups "$USER" | grep -q "\bdocker\b"; then
        echo -e "${BLUE}--> Adicionando usuário '$USER' ao grupo docker...${NC}"
        sudo usermod -aG docker "$USER"
    fi
    
    if ! rpm -q docker-desktop &> /dev/null; then
        echo -e "${GREEN}--> Baixando e instalando o Docker Desktop...${NC}"
        local DOCKER_DESKTOP_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm"
        local DOCKER_DESKTOP_RPM="$HOME/Downloads/docker-desktop.rpm"
        
        curl -L --http1.1 -C - "$DOCKER_DESKTOP_URL" -o "$DOCKER_DESKTOP_RPM"
        
        sudo dnf install -y "$DOCKER_DESKTOP_RPM"
        rm "$DOCKER_DESKTOP_RPM"
    else
        echo -e "${YELLOW}--> Docker Desktop já está instalado. Pulando.${NC}"
    fi
}

# 10. Configura Pod com MariaDB e phpMyAdmin
configure_mariadb_pod() {
    print_header "Configurando Pod com MariaDB e phpMyAdmin"

    local POD_NAME="mariadb-pod"
    local DB_CONTAINER_NAME="mariadb-db"
    local DB_VOLUME_NAME="mariadb_app_data"
    local PMA_CONTAINER_NAME="phpmyadmin-ui"
    
    local ROOT_PASSWORD="$(date +%s)$(openssl rand -hex 8)"
    local PMA_PASSWORD="$(date +%s)$(openssl rand -hex 8)"
    local USER_PASSWORD="$(date +%s)$(openssl rand -hex 8)"

    echo -e "${BLUE}--> Criando o pod '$POD_NAME'...${NC}"
    podman pod create --name "$POD_NAME" -p 3306:3306 -p 8081:80

    echo -e "${BLUE}--> Iniciando o contêiner do MariaDB ('$DB_CONTAINER_NAME')...${NC}"
    podman run -d --name "$DB_CONTAINER_NAME" --pod "$POD_NAME" \
      -v "$DB_VOLUME_NAME:/var/lib/mysql:Z" \
      -e MYSQL_ROOT_PASSWORD="$ROOT_PASSWORD" \
      -e MYSQL_USER="$USER" \
      -e MYSQL_PASSWORD="$USER_PASSWORD" \
      docker.io/library/mariadb:latest

    echo -e "${GREEN}--> Verificando ativamente se o banco de dados está pronto e configurado...${NC}"
    local max_retries=30
    local retry_count=0
    while ! podman exec "$DB_CONTAINER_NAME" mariadb-admin ping -u root --password="$ROOT_PASSWORD" &> /dev/null; do
        retry_count=$((retry_count + 1))
        if [ $retry_count -ge $max_retries ]; then
            echo -e "${RED}ERRO: Timeout! O banco de dados não respondeu com as credenciais corretas.${NC}" >&2
            echo -e "${YELLOW}--> Últimos logs do contêiner '$DB_CONTAINER_NAME':${NC}"
            podman logs "$DB_CONTAINER_NAME"
            exit 1
        fi
        echo -e "${YELLOW}--> Tentativa $retry_count/$max_retries. Aguardando o banco de dados aceitar as credenciais...${NC}"
        sleep 5
    done
    echo -e "${BOLD_GREEN}--> Sucesso! O banco de dados está 100% operacional.${NC}"

    sleep 30

    echo -e "${BLUE}--> Configurando usuário 'pma' para o phpMyAdmin...${NC}"
    podman exec -i "$DB_CONTAINER_NAME" mariadb -u root --password="$ROOT_PASSWORD" <<-EOSQL
        DROP USER IF EXISTS 'pma'@'localhost';
        DROP USER IF EXISTS 'pma'@'127.0.0.1';
        DROP USER IF EXISTS 'pma'@'::1';
        FLUSH PRIVILEGES;
        CREATE DATABASE IF NOT EXISTS phpmyadmin_config_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER 'pma'@'localhost' IDENTIFIED BY '$PMA_PASSWORD'; GRANT ALL PRIVILEGES ON phpmyadmin_config_db.* TO 'pma'@'localhost';
        CREATE USER 'pma'@'127.0.0.1' IDENTIFIED BY '$PMA_PASSWORD'; GRANT ALL PRIVILEGES ON phpmyadmin_config_db.* TO 'pma'@'127.0.0.1';
        CREATE USER 'pma'@'::1' IDENTIFIED BY '$PMA_PASSWORD'; GRANT ALL PRIVILEGES ON phpmyadmin_config_db.* TO 'pma'@'::1';
        FLUSH PRIVILEGES;
EOSQL

    sleep 5
    echo -e "${BLUE}--> Iniciando o contêiner do phpMyAdmin ('$PMA_CONTAINER_NAME')...${NC}"
    podman run -d --name "$PMA_CONTAINER_NAME" --pod "$POD_NAME" \
      -e PMA_HOST="$DB_CONTAINER_NAME" \
      docker.io/library/phpmyadmin:latest

    echo -e "${GREEN}--> Pod com MariaDB e phpMyAdmin configurado com sucesso!${NC}"
    echo -e "${YELLOW}--> phpMyAdmin estará acessível em http://localhost:8081${NC}"
    
    echo -e ""
    echo -e "${CYAN}Credenciais do Banco de Dados:${NC}"
    echo -e "--------------------------------------------------"
    echo -e "  Host:         127.0.0.1"
    echo -e "  Porta:        3306"
    echo -e "  Usuário root: root"
    echo -e "  Senha root:   ${BOLD_GREEN}$ROOT_PASSWORD${NC}"
    echo -e "--------------------------------------------------"
    echo -e "  Usuário pma:  pma"
    echo -e "  Senha pma:    ${BOLD_GREEN}$PMA_PASSWORD${NC}"
    echo -e "--------------------------------------------------"
    echo -e "  Usuário app:  $USER"
    echo -e "  Senha app:    ${BOLD_GREEN}$USER_PASSWORD${NC}"
    echo -e "--------------------------------------------------"
}

# 11. Deleta o Pod do MariaDB, se houver
clean_mariadb_pod() {
    local POD_NAME="mariadb-pod"
    local DB_VOLUME_NAME="mariadb_app_data"
    
    if podman pod exists "$POD_NAME"; then
        echo -e "${YELLOW}--> Pod '$POD_NAME' encontrado. Removendo...${NC}"
        podman pod rm -f "$POD_NAME"
    fi

    if podman volume exists "$DB_VOLUME_NAME"; then
        echo -e "${YELLOW}--> Volume '$DB_VOLUME_NAME' encontrado. Removendo para garantir uma inicialização limpa...${NC}"
        podman volume rm -f "$DB_VOLUME_NAME"
        echo -e "${CYAN}--> Aguardando 5 segundos para garantir a sincronização do sistema de arquivos...${NC}"
        sleep 5
    fi

}

# 12. Deleta o Pod do PostgreSQL, se houver
clean_postgres_pod() {
    local POD_NAME="postgres-pod"
    local DB_VOLUME="postgres_data"
    local UI_VOLUME="pgadmin_data"
    
    if podman pod exists "$POD_NAME"; then
        echo -e "${YELLOW}--> Pod '$POD_NAME' encontrado. Removendo...${NC}"
        podman pod rm -f "$POD_NAME"
    fi

    for vol in "$DB_VOLUME" "$UI_VOLUME"; do
        if podman volume exists "$vol"; then
            echo -e "${YELLOW}--> Volume '$vol' encontrado. Removendo...${NC}"
            podman volume rm -f "$vol"
        fi
    done
    
    echo -e "${CYAN}--> Sincronizando sistema de arquivos para o Postgres...${NC}"
    sleep 3
}

# 13. Configura Pod com PostgreSQL e pgAdmin 4
configure_postgres_pod() {
    print_header "Configurando Pod com PostgreSQL e pgAdmin"

    local POD_NAME="postgres-pod"
    local DB_CONTAINER="postgres-db"
    local UI_CONTAINER="pgadmin-ui"
    
    # Credenciais conforme solicitado
    local DB_USER="$USER"
    local DB_PASS="$(date +%s)$(openssl rand -hex 8)"
    local DB_NAME="default_db"
    local ADMIN_EMAIL="admin@local.com"
    local ADMIN_PASS="$(date +%s)$(openssl rand -hex 8)"

    echo -e "${BLUE}--> Criando o pod '$POD_NAME'...${NC}"
    podman pod create --name "$POD_NAME" -p 5432:5432 -p 8082:80

    echo -e "${BLUE}--> Iniciando o contêiner do PostgreSQL ('$DB_CONTAINER')...${NC}"
    podman run -d --name "$DB_CONTAINER" --pod "$POD_NAME" \
      -v postgres_data:/var/lib/postgresql/data:Z \
      -e POSTGRES_USER="$DB_USER" \
      -e POSTGRES_PASSWORD="$DB_PASS" \
      -e POSTGRES_DB="$DB_NAME" \
      docker.io/library/postgres:latest

    echo -e "${GREEN}--> Aguardando o PostgreSQL inicializar...${NC}"
    local max_retries=60
    local retry_count=0
    
    # while ! podman exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" &> /dev/null; do
    #     retry_count=$((retry_count + 1))
    #     if [ $retry_count -ge $max_retries ]; then
    #         echo -e "${RED}ERRO: Timeout! O PostgreSQL não ficou pronto a tempo.${NC}" >&2
    #         exit 1
    #     fi
    #     echo -e "${YELLOW}--> Tentativa $retry_count/$max_retries. Aguardando...${NC}"
    #     sleep 3
    # done

    while true; do
        if podman exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" &> /dev/null; then
            break
        fi

        if [[ "$(podman inspect -f '{{.State.Running}}' "$DB_CONTAINER")" != "true" ]]; then
            echo -e "${RED}ERRO CRÍTICO: O contêiner '$DB_CONTAINER' parou de rodar inesperadamente!${NC}"
            echo -e "${YELLOW}--> Logs do erro:${NC}"
            podman logs "$DB_CONTAINER"
            exit 1
        fi

        retry_count=$((retry_count + 1))
        if [ $retry_count -ge $max_retries ]; then
            echo -e "${RED}ERRO: Timeout! O PostgreSQL não ficou pronto a tempo.${NC}" >&2
            echo -e "${YELLOW}--> Verifique os logs para mais detalhes:${NC}"
            podman logs "$DB_CONTAINER"
            exit 1
        fi

        echo -e "${YELLOW}--> Tentativa $retry_count/$max_retries. Aguardando...${NC}"
        sleep 3
    done

    echo -e "${BLUE}--> Iniciando o contêiner do pgAdmin 4 ('$UI_CONTAINER')...${NC}"
    podman run -d --name "$UI_CONTAINER" --pod "$POD_NAME" \
      -v pgadmin_data:/var/lib/pgadmin:Z \
      -e PGADMIN_DEFAULT_EMAIL="$ADMIN_EMAIL" \
      -e PGADMIN_DEFAULT_PASSWORD="$ADMIN_PASS" \
      -e PGADMIN_CONFIG_SERVER_MODE='True' \
      docker.io/dpage/pgadmin4:latest

    echo -e "${GREEN}--> Pod PostgreSQL e pgAdmin configurado com sucesso!${NC}"
    echo -e "${YELLOW}--> pgAdmin acessível em http://localhost:8088${NC}"
    
    echo -e ""
    echo -e "${CYAN}Credenciais do PostgreSQL:${NC}"
    echo -e "--------------------------------------------------"
    echo -e "  Host:           127.0.0.1"
    echo -e "  Porta:          5432"
    echo -e "  Usuário DB:     $DB_USER"
    echo -e "  Senha DB:       ${BOLD_GREEN}$DB_PASS${NC}"
    echo -e "  Database:       $DB_NAME"
    echo -e "--------------------------------------------------"
    echo -e "  Login pgAdmin:  $ADMIN_EMAIL"
    echo -e "  Senha pgAdmin:  ${BOLD_GREEN}$ADMIN_PASS${NC}"
    echo -e "--------------------------------------------------"
}

install_gnome_extensions() {
    print_header "Instalando Extensões do Gnome"

    if ! command -v pipx &> /dev/null; then
        echo -e "${BLUE}--> Instalando pipx...${NC}"
        sudo dnf install -y pipx
    else
        echo -e "${YELLOW}--> pipx já está instalado. Pulando.${NC}"
    fi

    echo -e "${MAGENTA}--> Garantindo que o pipx estejam na PATH...${NC}"
    pipx ensurepath
    export PATH="$PATH:$HOME/.local/bin"

    echo -e "${BLUE}--> Instalando gnome-extensions-cli pelo pipx...${NC}"
    pipx install gnome-extensions-cli

    declare -a EXTENSIONS_IDS=(
        "1414" # 'Unblank lock screen'
        "6162" # 'Solaar extension'
        "307" # 'Dash to Dock'
        "4839" # 'Clipboard history'
        "3193" # 'Blur my Shell'
        "6670" # 'Bluetooth Battery Meter'
        "615" # 'AppIndicator and KStatusNotifierItem Support'
        "5446" # 'Quick Settings Tweaks'
        "5506" # 'User Avatar In Quick Settings'
    )

    for id in "${EXTENSIONS_IDS[@]}"; do
        echo -e "${BLUE}--> Instalando a extensão $id pelo gnome-extensions-cli...${NC}"
        
        if ! gnome-extensions-cli install "$id"; then
            echo -e "${RED}ERRO: Erro ao instalar a extensão de ID: $id ${NC}" 
        fi
    done

    echo -e "${GREEN}--> Instalação das extensões finalizada com sucesso!${NC}"
}

install_openrgb_service() {
    print_header "Instalando e Configurando OpenRGB Server"

    echo -e "${BLUE}--> Instalando pacotes: openrgb, i2c-tools, openrgb-udev-rules...${NC}"
    sudo dnf install -y automake gcc-c++ qt5-qtbase-devel hidapi-devel libusbx-devel mbedtls-devel i2c-tools openrgb openrgb-udev-rules lm-sensors
    
    # --- Configuração Inteligente de Módulos (I2C) ---
    echo -e "${MAGENTA}--> Detectando hardware e configurando módulos I2C...${NC}"

    # 1. Carrega o módulo base obrigatório
    sudo modprobe i2c-dev
    if [ ! -f "/etc/modules-load.d/i2c-dev.conf" ]; then
        echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf > /dev/null
    fi

    # 2. Detecta CPU (Intel vs AMD) e carrega o driver de chipset apropriado
    local CPU_VENDOR=$(grep -m 1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    local MODULE_TO_LOAD=""

    if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        echo -e "${GREEN}--> Hardware Intel detectado. Configurando i2c-i801...${NC}"
        MODULE_TO_LOAD="i2c-i801"
    elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
        echo -e "${GREEN}--> Hardware AMD detectado. Configurando i2c-piix4...${NC}"
        MODULE_TO_LOAD="i2c-piix4"
    else
        echo -e "${YELLOW}--> Fabricante da CPU não identificado ($CPU_VENDOR). Pulando driver de chipset específico.${NC}"
    fi
    
    # Aplica a carga e persistência do driver de chipset, se identificado
    if [ -n "$MODULE_TO_LOAD" ]; then
        sudo modprobe "$MODULE_TO_LOAD" || echo -e "${YELLOW}--> Aviso: Falha ao carregar $MODULE_TO_LOAD.${NC}"
        if [ ! -f "/etc/modules-load.d/openrgb-chipset.conf" ]; then
            echo "$MODULE_TO_LOAD" | sudo tee /etc/modules-load.d/openrgb-chipset.conf > /dev/null
        fi
    fi
    
    # --- Localização Dinâmica do Binário ---
    local OPENRGB_BIN
    OPENRGB_BIN=$(which openrgb)

    if [ -z "$OPENRGB_BIN" ]; then
        echo -e "${RED}ERRO CRÍTICO: Binário 'openrgb' não encontrado. O serviço não será criado.${NC}"
        return 1
    fi
    echo -e "${GREEN}--> Binário OpenRGB localizado em: ${OPENRGB_BIN}${NC}"

    # --- Criação do Serviço Systemd ---
    # Alterações:
    # 1. Type=simple (para manter o processo rodando)
    # 2. --server (ativa o modo servidor)
    # 3. --no-gui (obrigatório para rodar headless/sem monitor)
    # 4. Mantivemos a cor estática (-c 080808) na inicialização
    
    echo -e "${BLUE}--> Criando arquivo de serviço Systemd (/etc/systemd/system/openrgb.service)...${NC}"
    
    sudo bash -c "cat > /etc/systemd/system/openrgb.service" <<EOF
[Unit]
Description=OpenRGB SDK Server
After=network.target lm_sensors.service

[Service]
Type=simple
ExecStart=${OPENRGB_BIN} --no-gui --server --port 6742 -c 080808 -m Direct
User=nobody
Group=i2c
Restart=always
RestartSec=5
ProtectSystem=full
ProtectHome=yes

[Install]
WantedBy=multi-user.target
EOF

    # --- Habilitar e Iniciar ---
    echo -e "${BLUE}--> Habilitando o serviço openrgb...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl enable openrgb.service
    
    echo -e "${BLUE}--> Tentando iniciar o serviço...${NC}"
    # Nota: Em instalações limpas, pode ser necessário rebootar para as regras udev pegarem
    # antes que o serviço funcione perfeitamente com user 'nobody'.
    if sudo systemctl start openrgb.service; then
        echo -e "${BOLD_GREEN}--> Serviço OpenRGB Server iniciado com sucesso.${NC}"
    else
        echo -e "${YELLOW}--> Aviso: O serviço foi habilitado, mas não iniciou imediatamente (provavelmente aguardando reboot para regras udev/permissões).${NC}"
    fi
}

# --- Função Principal ---
main() {
    if [[ $EUID -eq 0 ]]; then
       echo -e "${RED}ERRO: Este script não deve ser executado como root. Execute como um usuário normal.${NC}" >&2
       exit 1
    fi
    
    clean_mariadb_pod
    clean_postgres_pod
    
    update_system
    setup_multimedia_and_java
    install_oh_my_bash
    setup_flatpak
    install_dev_tools
    install_web_dev_stack
    install_fonts
    install_flutter_and_jetbrains
    configure_docker
    configure_mariadb_pod
    configure_postgres_pod
    install_gnome_extensions
    install_openrgb_service

    fastfetch

    print_header "Instalação Concluída!"
    echo -e "Para que TODAS as alterações (grupos, PATH, fontes, etc.) tenham efeito,"
    echo -e "você precisa SAIR e ENTRAR novamente na sua sessão ou reiniciar o computador."
    echo -e "Após reiniciar, os novos comandos e fontes estarão disponíveis."
    echo -e ""
    echo -e "Script finalizado com sucesso! 🎉"
}

# Executa a função principal
main
