#!/bin/bash

# ===================================================================================
#
#          FILE:  post-install.sh
#   DESCRIPTION:  Script híbrido para Fedora e Pop!_OS / Ubuntu.
#        AUTHOR:  Henrique Bissoli Malaman Alonso (Refatorado para Multi-Distro)
#       VERSION:  3.0
#
# ===================================================================================

# Encerra o script imediatamente se um comando falhar.
set -e
# Garante que o status de saída de um pipeline seja o do último comando a falhar.
set -o pipefail

# --- Detecção de Sistema ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    echo "Não foi possível detectar a distribuição."
    exit 1
fi

# --- Definição de Cores ---
CYAN='\e[0;36m'
BLUE='\e[0;34m'
GREEN='\e[0;32m'
RED='\e[0;31m'
YELLOW='\e[0;33m'
MAGENTA='\e[0;35m'
BOLD_GREEN='\e[1;32m'
NC='\e[0m' # No Color (Reset)

print_header() {
    printf "\n${CYAN}======================================================================${NC}\n"
    printf "${CYAN}  %s${NC}\n" "$1"
    printf "${CYAN}======================================================================${NC}\n"
}


pkg_install() {
    if [[ "$DISTRO" == "fedora" ]]; then
        sudo dnf install -y "$@"
    elif [[ "$DISTRO" == "pop" || "$DISTRO" == "ubuntu" ]]; then
        sudo apt update && sudo apt install -y "$@"
    fi
}

update_system() {
    print_header "Atualizando o sistema"
    if [[ "$DISTRO" == "fedora" ]]; then
        sudo dnf upgrade -y
    else
        sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y
    fi
}

setup_multimedia_and_base_dependencies() {
    print_header "Instalando Codecs e Dependências Base"

    if [[ "$DISTRO" == "fedora" ]]; then
        echo -e "${MAGENTA}--> Verificando repositórios RPM Fusion...${NC}"
        if ! rpm -q rpmfusion-free-release > /dev/null 2>&1; then
            echo -e "${MAGENTA}--> Adicionando repositórios RPM Fusion (free e non-free)...${NC}"
            sudo dnf install -y \
              https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
              https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm
        fi
        
        echo -e "${BLUE}--> Atualizando o grupo de pacotes 'core'...${NC}"
        sudo dnf group upgrade -y core

        echo -e "${BLUE}--> Instalando Java, pacotes multimídia e codecs...${NC}"
        sudo dnf group install -y multimedia
        
        pkg_install \
          java-latest-openjdk.x86_64 \
          gstreamer1-plugin-openh264 \
          mozilla-openh264 \
          dnf5-plugins \
          dnf-plugins-core \
          unzip curl wget
    else
        echo -e "${BLUE}--> Preparando instalação para Pop!_OS...${NC}"
        
        echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections
        
        pkg_install \
          ubuntu-restricted-extras \
          curl wget unzip \
          build-essential \
          software-properties-common \
          gpg \
          openjdk-17-jdk \
          libfuse2 \
          curl \
          git \
          wget \
          unzip
    fi
}

install_oh_my_bash() {
    print_header "Instalando o Oh My Bash"
    
    if [ -d "$HOME/.oh-my-bash" ]; then
        echo -e "${YELLOW}--> Oh My Bash já está instalado. Pulando.${NC}"
        return 0
    fi

    if ! command -v curl &> /dev/null || ! command -v git &> /dev/null; then
        echo -e "${RED}ERRO: curl ou git não encontrados. Instale-os antes de prosseguir.${NC}"
        return 1
    fi

    echo -e "${BLUE}--> Instalando Oh My Bash...${NC}"
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" "" --unattended
}

setup_flatpak() {
    print_header "Configurando o Flatpak e instalando aplicativos"
    
    echo -e "${BLUE}--> Garantindo que o Flatpak está instalado...${NC}"
    if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "pop" ]]; then
        pkg_install flatpak gnome-software-plugin-flatpak

        local FLATPAK_EXPORT='export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:$XDG_DATA_DIRS"'
        if ! grep -q "var/lib/flatpak/exports/share" "$HOME/.bashrc"; then
            echo -e "${BLUE}--> Adicionando XDG_DATA_DIRS do Flatpak ao .bashrc...${NC}"
            echo -e "\n# Flatpak Environment Config" >> "$HOME/.bashrc"
            echo "$FLATPAK_EXPORT" >> "$HOME/.bashrc"
        else
            echo -e "${YELLOW}--> Variável XDG_DATA_DIRS já configurada no .bashrc. Pulando.${NC}"
        fi
    else
        pkg_install flatpak
    fi

    echo -e "${MAGENTA}--> Adicionando e habilitando o repositório Flathub...${NC}"
    flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo
    
    flatpak remote-modify --enable flathub

    # Lista de aplicativos Flatpak para instalar
    local FLATPAK_APPS=(
        com.spotify.Client
        com.usebruno.Bruno
        com.discordapp.Discord
        com.github.tchx84.Flatseal
        it.mijorus.gearlever
        com.mattjakeman.ExtensionManager
        com.heroicgameslauncher.hgl
        com.github.PintaProject.Pinta
        app.zen_browser.zen
        io.github.flattool.Warehouse
        io.podman_desktop.PodmanDesktop
        net.nokyan.Resources
    )

    echo -e "${BLUE}--> Instalando aplicativos via Flatpak...${NC}"
    
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak list --columns=application | grep -q "^$app$"; then
            echo -e "${YELLOW}--> O aplicativo '$app' já está instalado. Pulando.${NC}"
        else
            echo -e "${BLUE}--> Instalando: $app${NC}"

            flatpak install -y --system --noninteractive flathub "$app"
        fi
    done
}

install_dev_tools() {
    print_header "Configurando Repositórios e Ferramentas de Desenvolvimento"

    echo -e "${MAGENTA}--> Adicionando repositórios necessários...${NC}"

    if [[ "$DISTRO" == "fedora" ]]; then
        if [ ! -f "/etc/yum.repos.d/gh-cli.repo" ]; then
            echo -e "${MAGENTA}--> Adicionando repositório do GitHub CLI...${NC}"
            sudo dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo
        fi

        echo -e "${BLUE}--> Instalando GitHub CLI no Fedora...${NC}"
        sudo dnf install -y gh --repo gh-cli

        if [ ! -f "/etc/yum.repos.d/vscode.repo" ]; then
            echo -e "${MAGENTA}--> Adicionando repositório do Visual Studio Code...${NC}"
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null    
        fi
    
        if [ ! -f "/etc/yum.repos.d/docker-ce.repo" ]; then
            echo -e "${MAGENTA}--> Adicionando repositório do Docker...${NC}"
            sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        fi

        echo -e "${BLUE}--> Instalando pacotes de dev no Fedora...${NC}"
        pkg_install \
          code podman podman-machine docker-ce docker-ce-cli containerd.io \
          docker-buildx-plugin docker-compose-plugin fastfetch
    else
        sudo mkdir -p -m 755 /etc/apt/keyrings

        echo -e "${MAGENTA}--> Adicionando PPA do Fastfetch...${NC}"
        sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
        
        # GH CLI
        if [ ! -f "/etc/apt/keyrings/githubcli-archive-keyring.gpg" ]; then
            echo -e "${MAGENTA}--> Adicionando repositório do GitHub CLI...${NC}"
            wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        fi
        
        # VS Code
        if [ ! -f "/etc/apt/keyrings/packages.microsoft.gpg" ]; then
            echo -e "${MAGENTA}--> Adicionando repositório do Visual Studio Code...${NC}"
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        fi
    
        # Docker
        if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
            echo -e "${MAGENTA}--> Adicionando repositório do Docker...${NC}"
            wget -qO- https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        fi

        echo -e "${BLUE}--> Atualizando índices do APT...${NC}"
        sudo apt update

        echo -e "${BLUE}--> Instalando pacotes de dev no Pop!_OS...${NC}"

        pkg_install code gh docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin podman fastfetch
    fi
}

install_web_stack(){
    print_header "Instalando PHP e Composer"

    if [[ "$DISTRO" == "fedora" ]]; then
        echo -e "${BLUE}--> Instalando PHP e extensões no Fedora...${NC}"
        
        pkg_install \
          php php-cli php-fpm php-mysqlnd php-gd php-intl php-mbstring php-pdo \
          php-xml php-pecl-zip php-bcmath php-sodium php-opcache php-devel php-common
    else
        echo -e "${BLUE}--> Instalando PHP e extensões no Pop!_OS...${NC}"
        pkg_install php-cli php-fpm php-mysql php-gd php-intl php-mbstring php-xml php-zip php-bcmath php-curl php-sqlite3
    fi

    echo -e "${BLUE}--> Verificando Composer...${NC}"
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
        sudo composer self-update
    fi 
    
    local COMPOSER_BIN="$HOME/.config/composer/vendor/bin"
    if [[ ":$PATH:" != *":$COMPOSER_BIN:"* ]]; then
        echo -e "${BLUE}--> Adicionando Composer ao PATH...${NC}"
        echo -e "\n# Composer Global Bin\nexport PATH=\"\$PATH:$COMPOSER_BIN\"" >> "$HOME/.bashrc"
        export PATH="$PATH:$COMPOSER_BIN"
    fi

    echo -e "${BLUE}--> Instalando/Atualizando Laravel Installer...${NC}"
    composer global require laravel/installer
}

# 6. Instala NVM, Node.js, PHP e Composer
install_js_stack() {
    print_header "Instalando Node.js e Deno e pnpm"

    if [ ! -d "$HOME/.nvm" ]; then
        echo -e "${GREEN}--> Instalando NVM...${NC}"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    echo -e "${BLUE}--> Garantindo Node.js v24...${NC}"
    nvm install 24
    nvm use 24
    nvm alias default 24

    echo -e "${BLUE}--> Atualizando ferramentas globais (npm, pnpm)...${NC}"
    npm install -g npm@latest pnpm@latest-10

    if ! command -v deno &> /dev/null; then
        echo -e "${GREEN}--> Instalando Deno...${NC}"
        printf "y\n \n\n" | sh -c "$(curl -fsSL https://deno.land/install.sh)"
        
        # Adiciona ao PATH se não existir
        if ! grep -q "DENO_INSTALL" "$HOME/.bashrc"; then
            echo -e '\n# Deno config\nexport DENO_INSTALL="$HOME/.deno"\nexport PATH="$DENO_INSTALL/bin:$PATH"' >> "$HOME/.bashrc"
        fi
        export DENO_INSTALL="$HOME/.deno"
        export PATH="$DENO_INSTALL/bin:$PATH"
    else
        echo -e "${YELLOW}--> Deno já está instalado. Atualizando...${NC}"
        deno upgrade
    fi
}

install_fonts() {
    print_header "Instalando fontes (JetBrains Mono, Nerd Fonts)"

    # --- Instala Fontes ---
    local DOWNLOAD_DIR="/tmp/fonts-download"
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

    if command -v restorecon &> /dev/null; then
        sudo restorecon -vFr /usr/local/share/fonts/
    fi
    
    sudo fc-cache -fv
}

install_flutter_and_jetbrains() {
    print_header "Instalando Flutter, JetBrains Toolbox e dependências"

    echo -e "${BLUE}--> Instalando dependências de compilação e do Flutter...${NC}"
    if [[ "$DISTRO" == "fedora" ]]; then
        pkg_install \
          curl git unzip xz zip ninja-build cmake clang meson systemd-devel \
          pkg-config dbus-devel inih-devel fuse fuse-libs gtk3-devel egl-utils
    else
        pkg_install \
            curl git unzip xz-utils zip libglu1-mesa
    fi

    # --- Cria diretórios de trabalho ---
    local DEV_DIR="$HOME/development"
    local DOWNLOAD_DIR="/tmp/dev-downloads"
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

    local FLUTTER_PATH_CMD='export PATH="$PATH:$HOME/development/flutter/bin"'
    local TARGET_SHELL_CONFIG="$HOME/.bashrc"

    if [[ "$DISTRO" == "fedora" ]]; then TARGET_SHELL_CONFIG="$HOME/.bash_profile"; fi
    if ! grep -q 'development/flutter/bin' "$TARGET_SHELL_CONFIG"; then
        echo -e "\n# Add Flutter to PATH\n$FLUTTER_PATH_CMD" >> "$TARGET_SHELL_CONFIG"
    fi
    export PATH="$PATH:$HOME/development/flutter/bin"
    
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
            echo -e "${BOLD_GREEN}--> JetBrains Toolbox iniciado para configuração inicial.${NC}"
        else
            echo -e "${RED}ERRO: Não foi possível encontrar o diretório do JetBrains Toolbox.${NC}"
        fi

        rm "$JETBRAINS_ARCHIVE"
    else
      echo -e "${YELLOW}--> JetBrains Toolbox já encontrado em '$DEV_DIR'. Pulando.${NC}"
    fi
}

configure_docker() {
    print_header "Configurando o Docker e Docker Desktop"
    
    sudo systemctl enable --now docker
    sudo groupadd -f docker
    if ! groups "$USER" | grep -q "\bdocker\b"; then
        echo -e "${BLUE}--> Adicionando usuário '$USER' ao grupo docker...${NC}"
        sudo usermod -aG docker "$USER"
    fi

    local IS_INSTALLED=false
    if [[ "$DISTRO" == "fedora" ]]; then
        rpm -q docker-desktop &> /dev/null && IS_INSTALLED=true
    else
        dpkg -l docker-desktop &> /dev/null && IS_INSTALLED=true
    fi
    
    if [ "$IS_INSTALLED" = false ]; then
        echo -e "${GREEN}--> Baixando e instalando o Docker Desktop...${NC}"
        mkdir -p /tmp/docker-install
        
        if [[ "$DISTRO" == "fedora" ]]; then
            local URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm"
            curl -L "$URL" -o /tmp/docker-install/docker-desktop.rpm
            sudo dnf install -y /tmp/docker-install/docker-desktop.rpm
        else
            # Versão para Pop!_OS / Ubuntu
            local URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"
            curl -L "$URL" -o /tmp/docker-install/docker-desktop.deb
            sudo apt update && sudo apt install -y /tmp/docker-install/docker-desktop.deb
        fi
        rm -rf /tmp/docker-install
    else
        echo -e "${YELLOW}--> Docker Desktop já está instalado. Pulando...${NC}"
    fi
}

clean_mariadb_pod() {
    local POD_NAME="mariadb-pod"
    local DB_VOLUME_NAME="mariadb_app_data"

    print_header "Limpando ambiente MariaDB"
    
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
      -v postgres_data:/var/lib/postgresql:Z \
      -e POSTGRES_USER="$DB_USER" \
      -e POSTGRES_PASSWORD="$DB_PASS" \
      -e POSTGRES_DB="$DB_NAME" \
      docker.io/library/postgres:latest

    echo -e "${GREEN}--> Aguardando o PostgreSQL inicializar...${NC}"
    local max_retries=60
    local retry_count=0

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
    echo -e "${YELLOW}--> pgAdmin acessível em http://localhost:8082${NC}"
    
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
    if [[ "$DISTRO" != "fedora" ]]; then
        echo -e "${YELLOW}--> Distribuição '$DISTRO' detectada. Pulando extensões do GNOME (exclusivo para Fedora).${NC}"
        return 0
    fi
    
    print_header "Instalando Extensões do Gnome"

    if ! command -v pipx &> /dev/null; then
        echo -e "${BLUE}--> Instalando pipx...${NC}"
        pkg_install pipx
    else
        echo -e "${YELLOW}--> pipx já está instalado. Pulando.${NC}"
    fi

    echo -e "${MAGENTA}--> Garantindo que o pipx estejam na PATH...${NC}"
    pipx ensurepath --force > /dev/null 2>&1
    export PATH="$PATH:$HOME/.local/bin"

    if ! command -v gnome-extensions-cli &> /dev/null; then
        echo -e "${BLUE}--> Instalando gnome-extensions-cli via pipx...${NC}"
        pipx install gnome-extensions-cli
    else
        echo -e "${YELLOW}--> gnome-extensions-cli já está presente.${NC}"
    fi

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
        
        if ! gnome-extensions-cli install "$id" --update 2>/dev/null; then
            echo -e "${YELLOW}--> Nota: A extensão $id pode já estar instalada ou ser incompatível com esta versão do GNOME.${NC}" 
        fi
    done

    echo -e "${GREEN}--> Instalação das extensões finalizada com sucesso!${NC}"
}

install_steam() {
    print_header "Instalando Steam"
    
    if [[ "$DISTRO" == "fedora" ]]; then
        echo -e "${BLUE}--> Instalando Steam via RPM Fusion (Fedora)...${NC}"
        
        # Verifica se o repositório nonfree está presente (essencial para Steam no Fedora)
        if ! rpm -q rpmfusion-nonfree-release &> /dev/null; then
            echo -e "${RED}ERRO: Repositório RPM Fusion Non-Free não encontrado.${NC}"
            echo -e "${YELLOW}Certifique-se de que a função 'setup_multimedia_and_base_dependencies' rodou corretamente.${NC}"
            return 1
        fi

        pkg_install steam mangohud gamemode
    else
        # Lógica para Pop!_OS / Ubuntu
        echo -e "${BLUE}--> Preparando ambiente Debian-based para Steam...${NC}"
        
        # Steam exige arquitetura de 32 bits no Ubuntu/Pop
        sudo dpkg --add-architecture i386
        sudo apt update

        if ! dpkg -l steam &> /dev/null; then
            echo -e "${GREEN}--> Baixando e instalando Steam oficial (.deb)...${NC}"
            local STEAM_URL="https://cdn.fastly.steamstatic.com/client/installer/steam.deb"
            local TEMP_DEB="/tmp/steam.deb"

            curl -L "$STEAM_URL" -o "$TEMP_DEB"
            # O apt install resolve as dependências de 32 bits automaticamente
            sudo apt install -y "$TEMP_DEB" mangohud mangohud:i386 gamemode
            rm -f "$TEMP_DEB"
        else
            echo -e "${YELLOW}--> Steam já instalada. Pulando.${NC}"
        fi
    fi

    echo -e "${BOLD_GREEN}--> Steam configurada com sucesso em seu sistema $DISTRO!${NC}"
}

# --- Função Principal ---
main() {
    if [[ $EUID -eq 0 ]]; then
       echo -e "${RED}ERRO: Este script não deve ser executado como root. Execute como um usuário normal.${NC}" >&2
       exit 1
    fi
    
    # 2. Reset de ambiente para Idempotência
    clean_mariadb_pod
    clean_postgres_pod
    
    # 3. Base do Sistema
    update_system
    setup_multimedia_and_base_dependencies  # Nome sincronizado aqui
    install_oh_my_bash                      # Instalado antes para preparar o .bashrc
    
    # 4. Gerenciadores e Repositórios
    setup_flatpak
    install_dev_tools
    
    # 5. Stacks de Linguagens (PHP, JS, Flutter)
    install_web_stack
    install_js_stack
    install_flutter_and_jetbrains
    
    # 6. Configurações de Ambiente e Fontes
    install_fonts
    install_steam
    configure_docker
    install_gnome_extensions
    
    # 7. Infraestrutura (Containers/Pods)
    configure_mariadb_pod
    configure_postgres_pod
    
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
