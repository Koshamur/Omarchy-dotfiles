#!/bin/bash

# Exit on error
set -e

echo "Starting installation process..."

# 1. Install Rust (check if rustc is available)
if ! command -v rustc &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # Load rustup env for current session
    source "$HOME/.cargo/env"
else
    echo "Rust is already installed, skipping..."
fi

# 2. Install Arch Official packages
echo "Installing packages from official Arch repositories..."
sudo pacman -Syu --needed \
    cmatrix \
    nautilus \
    firefox \
    chromium \
    steam \
    zsh \
    ollama \
    discord \
    git \
    base-devel \
    python \
    nodejs \
    npm \
    cmake \
    gcc \
    flatpak \
    gparted \
    vlc \
    libreoffice-fresh \
    timeshift \
    bleachbit \
    docker \
    wine \
    obs-studio \
    mangohud \
    gamemode \
    neovim \
    ripgrep \
    qbittorrent \
    shellcheck \
    wget \
    curl

# 3. Install AUR packages (try yay, then paru)
AUR_PACKAGES="visual-studio-code-bin ghostty telegram-desktop"
INSTALLED_AUR=false

if command -v yay &> /dev/null; then
    echo "Installing packages from AUR using yay..."
    yay -S --needed $AUR_PACKAGES && INSTALLED_AUR=true
elif command -v paru &> /dev/null; then
    echo "Installing packages from AUR using paru..."
    paru -S --needed $AUR_PACKAGES && INSTALLED_AUR=true
fi

if [ "$INSTALLED_AUR" = false ]; then
    echo "Neither yay nor paru was found. AUR packages were not installed."
fi

# 4. Setup Flathub and install Flatpak packages
echo "Configuring Flathub..."
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "Installing Flatpak packages..."
# Flatpak install -y handles existing packages gracefully, but we use --needed logic
flatpak install -y flathub \
    com.usebottles.bottles \
    org.vinegarhq.Sober

echo "Installation completed successfully!"
