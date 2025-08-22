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
#       VERSION:  2.0
#
# ===================================================================================

# Encerra o script imediatamente se um comando falhar.
set -e
# Garante que o status de saída de um pipeline seja o do último comando a falhar.
set -o pipefail

# Função para imprimir um cabeçalho de seção formatado.
print_header() {
    printf "\n======================================================================\n"
    printf "  %s\n" "$1"
    printf "======================================================================\n"
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

    echo "Adicionando repositórios RPM Fusion (free e non-free)..."
    sudo dnf install -y \
      https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
      https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm

    echo "Atualizando o grupo de pacotes 'core'..."
    sudo dnf group upgrade -y core

    echo "Instalando Java, pacotes multimídia e codecs..."
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
        echo "Oh My Bash já está instalado. Pulando."
    else
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)" "" --unattended
    fi
}

# 4. Configura o Flatpak e instala os aplicativos
setup_flatpak() {
    print_header "Configurando o Flatpak e instalando aplicativos"
    sudo dnf install -y flatpak

    echo "Adicionando e habilitando o repositório Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    
    flatpak remote-modify --enable flathub

    # Lista de aplicativos Flatpak para instalar
    FLATPAK_APPS=(
        com.spotify.Client com.usebruno.Bruno com.discordapp.Discord
        org.gnome.Extensions com.github.tchx84.Flatseal it.mijorus.gearlever
        com.mattjakeman.ExtensionManager com.heroicgameslauncher.hgl
        com.github.PintaProject.Pinta app.zen_browser.zen
        io.github.flattool.Warehouse io.podman_desktop.PodmanDesktop
    )

    echo "Instalando aplicativos via Flatpak..."
    for app in "${FLATPAK_APPS[@]}"; do
        if flatpak info "$app" > /dev/null 2>&1; then
            echo "--> O aplicativo '$app' já está instalado. Pulando."
        else
            echo "--> Instalando: $app"
            flatpak install -y flathub "$app"
        fi
    done
}

# 5. Instala ferramentas de desenvolvimento (VS Code, GitHub CLI, Docker, Podman)
install_dev_tools() {
    print_header "Instalando Ferramentas de Desenvolvimento"

    # --- Adiciona repositórios de terceiros ---
    echo "Adicionando repositórios necessários..."
    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

    # --- Instala pacotes via DNF ---
    echo "Instalando pacotes: gh, code, podman, docker e dependências..."
    sudo dnf install -y \
      gh code podman podman-machine docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
}

# 6. Instala NVM, Node.js, PHP e Composer
install_web_dev_stack() {
    print_header "Instalando Stack de Desenvolvimento Web (NVM, Node.js, PHP, Composer)"

    # --- Instala NVM e Node.js ---
    echo "Baixando e instalando o NVM (Node Version Manager)..."
    # ALTERAÇÃO: Verifica se o NVM já está instalado antes de baixar.
    if [ ! -d "$HOME/.nvm" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    else
        echo "NVM já está instalado. Pulando download."
    fi

    echo "Carregando o NVM no shell atual para uso imediato..."
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    echo "Instalando a versão 22 do Node.js..."
    nvm install 22
    nvm use 22
    nvm alias default 22

    echo "Atualizando o npm para a versão mais recente..."
    npm install -g npm@latest

    # --- Instala pnpm ---
    echo "Instalando pnpm (gerenciador de pacotes)..."
    npm install -g pnpm@latest-10

    # --- Instala PHP e extensões ---
    echo "Instalando PHP e extensões via DNF..."
    sudo dnf install -y \
      php php-cli php-fpm php-mysqlnd php-gd php-intl php-mbstring php-pdo \
      php-xml php-pecl-zip php-bcmath php-sodium php-opcache php-devel php-common

    # --- Instala Composer e Laravel Installer ---
    echo "Instalando o Composer (gerenciador de dependências para PHP)..."
    if ! command -v composer &> /dev/null; then
        cd /tmp
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        EXPECTED_SIGNATURE=$(curl -s https://composer.github.io/installer.sig)
        ACTUAL_SIGNATURE=$(php -r "echo hash_file('sha384', 'composer-setup.php');")
        if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
            >&2 echo 'ERRO: Assinatura do instalador do Composer é inválida.'
            rm composer-setup.php
            exit 1
        fi
        php composer-setup.php --install-dir=/usr/local/bin --filename=composer
        rm composer-setup.php
        cd - > /dev/null
    else
        echo "Composer já está instalado. Pulando."
    fi
    
    COMPOSER_VENDOR_PATH="$HOME/.config/composer/vendor/bin"
    if ! grep -q "$COMPOSER_VENDOR_PATH" "$HOME/.bash_profile"; then
      echo -e '\n# Add Composer global bin to PATH\nexport PATH="$PATH:'"$COMPOSER_VENDOR_PATH"'"' >> "$HOME/.bash_profile"
    fi
    export PATH="$PATH:$COMPOSER_VENDOR_PATH"

    echo "Instalando o Laravel Installer globalmente..."
    composer global require laravel/installer
    cd - > /dev/null
}

# 7. Instala pnpm e fontes customizadas
install_fonts() {
    print_header "Instalando fontes (JetBrains Mono, Nerd Fonts)"

    # --- Instala Fontes ---
    DOWNLOAD_DIR="$HOME/Downloads"
    mkdir -p "$DOWNLOAD_DIR"

    # --- JetBrains Mono (Regular) ---
    echo "Baixando e instalando a fonte JetBrains Mono..."
    JB_FONT_URL="https://download.jetbrains.com/fonts/JetBrainsMono-2.304.zip"
    JB_FONT_ZIP="$DOWNLOAD_DIR/JetBrainsMono.zip"
    JB_FONT_EXTRACT_DIR="$DOWNLOAD_DIR/jetbrains-mono-extracted"
    JB_FONT_INSTALL_DIR="/usr/local/share/fonts/JetBrainsMono"

    curl -L "$JB_FONT_URL" -o "$JB_FONT_ZIP"
    unzip -o "$JB_FONT_ZIP" -d "$JB_FONT_EXTRACT_DIR"
    sudo mkdir -p "$JB_FONT_INSTALL_DIR"
    sudo cp -f "$JB_FONT_EXTRACT_DIR"/fonts/ttf/*.ttf "$JB_FONT_INSTALL_DIR/"
    
    # --- JetBrains Mono (Nerd Font) ---
    echo "Baixando e instalando a fonte JetBrains Mono Nerd Font..."
    NF_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip"
    NF_FONT_ZIP="$DOWNLOAD_DIR/JetBrainsMonoNF.zip"
    NF_FONT_EXTRACT_DIR="$DOWNLOAD_DIR/jetbrains-mono-nf-extracted"
    NF_FONT_INSTALL_DIR="/usr/local/share/fonts/JetBrainsMonoNF"

    curl -L "$NF_FONT_URL" -o "$NF_FONT_ZIP"
    unzip -o "$NF_FONT_ZIP" -d "$NF_FONT_EXTRACT_DIR"
    sudo mkdir -p "$NF_FONT_INSTALL_DIR"
    sudo cp -f "$NF_FONT_EXTRACT_DIR"/*.ttf "$NF_FONT_INSTALL_DIR/"

    # --- Configura permissões e atualiza cache de fontes ---
    echo "Configurando permissões e atualizando o cache de fontes do sistema..."
    sudo chown -R root: "$JB_FONT_INSTALL_DIR" "$NF_FONT_INSTALL_DIR"
    sudo chmod 644 "$JB_FONT_INSTALL_DIR"/* "$NF_FONT_INSTALL_DIR"/*
    sudo restorecon -vFr "$JB_FONT_INSTALL_DIR" "$NF_FONT_INSTALL_DIR"
    sudo fc-cache -fv

    # --- Limpeza ---
    echo "Limpando arquivos de instalação de fontes..."
    rm "$JB_FONT_ZIP" "$NF_FONT_ZIP"
    rm -rf "$JB_FONT_EXTRACT_DIR" "$NF_FONT_EXTRACT_DIR"
}


# 8. Instala dependências, Flutter e JetBrains Toolbox
install_flutter_and_jetbrains() {
    print_header "Instalando Flutter, JetBrains Toolbox e dependências"

    echo "Instalando dependências de compilação e do Flutter..."
    sudo dnf install -y \
      curl git unzip xz zip ninja-build cmake clang meson systemd-devel \
      pkg-config dbus-devel inih-devel fuse fuse-libs gtk3-devel egl-utils

    # --- Cria diretórios de trabalho ---
    DEV_DIR="$HOME/development"
    DOWNLOAD_DIR="$HOME/Downloads"
    mkdir -p "$DEV_DIR" "$DOWNLOAD_DIR"

    # --- Instala Flutter ---
    echo "Baixando o Flutter SDK..."
    FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.22.2-stable.tar.xz"
    FLUTTER_ARCHIVE="$DOWNLOAD_DIR/flutter.tar.xz"
    curl -L "$FLUTTER_URL" -o "$FLUTTER_ARCHIVE"
    echo "Extraindo o Flutter para $DEV_DIR..."
    tar -xf "$FLUTTER_ARCHIVE" -C "$DEV_DIR"
    if ! grep -q 'development/flutter/bin' "$HOME/.bash_profile"; then
      echo -e '\n# Add Flutter to PATH\nexport PATH="$PATH:$HOME/development/flutter/bin"' >> "$HOME/.bash_profile"
    fi
    
    # --- Instala JetBrains Toolbox ---
    echo "Baixando o JetBrains Toolbox..."
    JETBRAINS_URL="https://data.services.jetbrains.com/products/download?code=TBA&platform=linux&type=release"
    JETBRAINS_ARCHIVE="$DOWNLOAD_DIR/jetbrains-toolbox.tar.gz"
    curl -L "$JETBRAINS_URL" -o "$JETBRAINS_ARCHIVE"
    echo "Extraindo o JetBrains Toolbox..."
    tar -xzf "$JETBRAINS_ARCHIVE" -C "$DEV_DIR"
    TOOLBOX_DIR=$(find "$DEV_DIR" -maxdepth 1 -type d -name "jetbrains-toolbox-*")
    if [ -d "$TOOLBOX_DIR" ]; then
      echo "Iniciando o JetBrains Toolbox em segundo plano..."
      nohup "$TOOLBOX_DIR/jetbrains-toolbox" > /dev/null 2>&1 &
    else
      echo "ERRO: Não foi possível encontrar o diretório do JetBrains Toolbox."
    fi

    # --- Limpeza ---
    echo "Limpando arquivos de instalação baixados..."
    rm "$FLUTTER_ARCHIVE" "$JETBRAINS_ARCHIVE"
}

# 9. Configura o Docker e instala o Docker Desktop
configure_docker() {
    print_header "Configurando o Docker e instalando o Docker Desktop"
    sudo systemctl enable --now docker
    sudo groupadd docker || true
    sudo usermod -aG docker "$USER"
    
    echo "Baixando e instalando o Docker Desktop..."
    DOCKER_DESKTOP_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-x86_64.rpm"
    DOCKER_DESKTOP_RPM="$HOME/Downloads/docker-desktop.rpm"
    curl -L "$DOCKER_DESKTOP_URL" -o "$DOCKER_DESKTOP_RPM"
    sudo dnf install -y "$DOCKER_DESKTOP_RPM"
    rm "$DOCKER_DESKTOP_RPM"
}

# 10. Instala o MySQL Workbench
install_mysql_workbench() {
    print_header "Instalando o MySQL Workbench"
    
    # Define o diretório de downloads e garante que ele exista
    DOWNLOAD_DIR="$HOME/Downloads"
    mkdir -p "$DOWNLOAD_DIR"

    # URL e nome do arquivo RPM
    # Nota: A URL aponta para uma versão específica do Workbench para o Fedora 40.
    # Pode ser necessário atualizar esta URL no futuro.
    local WORKBENCH_URL="https://downloads.mysql.com/archives/get/p/8/file/mysql-workbench-community-8.0.42-1.fc40.x86_64.rpm"
    local WORKBENCH_RPM="$DOWNLOAD_DIR/mysql-workbench-community.rpm"
    
    echo "Baixando o MySQL Workbench..."
    curl -L "$WORKBENCH_URL" -o "$WORKBENCH_RPM"
    
    echo "Instalando o MySQL Workbench (resolvendo dependências com DNF)..."
    sudo dnf install -y "$WORKBENCH_RPM"
    
    echo "Limpando o arquivo de instalação do MySQL Workbench..."
    rm "$WORKBENCH_RPM"
}

# 11. Configura Pod com MariaDB e phpMyAdmin
configure_mariadb_pod() {
    print_header "Configurando Pod com MariaDB e phpMyAdmin"

    local POD_NAME="mariadb-pod"
    local DB_CONTAINER_NAME="mariadb-db"
    local PMA_CONTAINER_NAME="phpmyadmin-ui"
    
    local ROOT_PASSWORD="MariaDB@NarigudoGamer#ro0t"
    local PMA_PASSWORD="PMA@NarigudoGamer#ro0t"

    echo "Verificando e limpando o ambiente Podman existente..."
    if podman pod exists "$POD_NAME"; then
        echo "--> Pod '$POD_NAME' encontrado. Removendo..."
        podman pod rm -f "$POD_NAME"
    fi

    echo "Criando o pod '$POD_NAME'..."
    podman pod create --name "$POD_NAME" -p 3306:3306 -p 8081:80

    echo "Iniciando o contêiner do MariaDB ('$DB_CONTAINER_NAME')..."
    podman run -d --name "$DB_CONTAINER_NAME" --pod "$POD_NAME" \
      -v mariadb_app_data:/var/lib/mysql:Z \
      -e MYSQL_ROOT_PASSWORD="$ROOT_PASSWORD" \
      -e MYSQL_USER="henrique_1" \
      -e MYSQL_PASSWORD="Hl4035c360#" \
      mariadb:latest

    echo "Aguardando o banco de dados MariaDB ficar disponível..."
    local ready=0
    for i in {1..12}; do
        if podman exec "$DB_CONTAINER_NAME" mariadb-admin ping -u root -p"$ROOT_PASSWORD" &> /dev/null; then
            echo "--> Banco de dados está pronto!"
            ready=1
            break
        fi
        echo "--> Tentativa $i/12: Ainda não está pronto. Aguardando 5 segundos..."
        sleep 5
    done

    if [[ "$ready" -eq 0 ]]; then
        echo "ERRO: O banco de dados MariaDB não ficou pronto em 60 segundos." >&2
        exit 1
    fi

    echo "Configurando usuário 'pma' para o phpMyAdmin..."
    local SQL_COMMAND="DROP USER IF EXISTS 'pma'@'localhost'; DROP USER IF EXISTS 'pma'@'127.0.0.1'; DROP USER IF EXISTS 'pma'@'::1'; FLUSH PRIVILEGES; CREATE DATABASE IF NOT EXISTS phpmyadmin_config_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; CREATE USER 'pma'@'localhost' IDENTIFIED BY '$PMA_PASSWORD'; GRANT ALL PRIVILEGES ON phpmyadmin_config_db.* TO 'pma'@'localhost'; CREATE USER 'pma'@'127.0.0.1' IDENTIFIED BY '$PMA_PASSWORD'; GRANT ALL PRIVILEGES ON phpmyadmin_config_db.* TO 'pma'@'127.0.0.1'; CREATE USER 'pma'@'::1' IDENTIFIED BY '$PMA_PASSWORD'; GRANT ALL PRIVILEGES ON phpmyadmin_config_db.* TO 'pma'@'::1'; FLUSH PRIVILEGES;"
    podman exec "$DB_CONTAINER_NAME" mariadb -u root -p"$ROOT_PASSWORD" -e "$SQL_COMMAND"

    echo "Iniciando o contêiner do phpMyAdmin ('$PMA_CONTAINER_NAME')..."
    podman run -d --name "$PMA_CONTAINER_NAME" --pod "$POD_NAME" \
      -e PMA_HOST="$DB_CONTAINER_NAME" \
      phpmyadmin/phpmyadmin:latest

    echo "--> Pod com MariaDB e phpMyAdmin configurado com sucesso!"
    echo "--> phpMyAdmin estará acessível em http://localhost:8081"
}

# --- Função Principal ---
main() {
    if [[ $EUID -eq 0 ]]; then
       echo "ERRO: Este script não deve ser executado como root. Execute como um usuário normal." >&2
       exit 1
    fi

    update_system
    setup_multimedia_and_java
    install_oh_my_bash
    setup_flatpak
    install_dev_tools
    install_web_dev_stack
    install_fonts
    install_flutter_and_jetbrains
    configure_docker
    install_mysql_workbench
    configure_mariadb_pod

    print_header "Instalação Concluída!"
    echo "Para que TODAS as alterações (grupos, PATH, fontes, etc.) tenham efeito,"
    echo "você precisa SAIR e ENTRAR novamente na sua sessão ou reiniciar o computador."
    echo "Após reiniciar, os novos comandos e fontes estarão disponíveis."
    echo ""
    echo "Script finalizado com sucesso! 🎉"
}

# Executa a função principal
main