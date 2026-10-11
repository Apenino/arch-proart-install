#!/usr/bin/env bash
# Script post-installation Arch Linux (ASUS ProArt)
# - Logiciels de base : firefox, onlyoffice, steam, blender, git, discord, vlc
# - Shell : kitty + zsh + oh-my-zsh + powerlevel10k (+ traînée du curseur)
#
# Usage : ./install.sh   (en utilisateur normal, sudo sera demandé)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$REPO_DIR/dotfiles"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

info() { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m  !\e[0m %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Lance ce script en utilisateur normal (pas en root), sudo sera utilisé au besoin." >&2
    exit 1
fi

sudo -n true 2>/dev/null || sudo -v

# --------------------------------------------------------------------------
# Dépôt multilib (nécessaire pour Steam)
# --------------------------------------------------------------------------
enable_multilib() {
    info "Activation du dépôt multilib"
    if grep -q '^\[multilib\]' /etc/pacman.conf; then
        ok "multilib déjà activé"
    else
        sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
        ok "multilib activé"
    fi
}

# --------------------------------------------------------------------------
# Pilotes Vulkan 32 bits selon le GPU (évite le choix interactif de Steam)
# --------------------------------------------------------------------------
vulkan_packages() {
    local gpus pkgs=()
    gpus="$(lspci | grep -E 'VGA compatible|3D controller|Display controller' || true)"
    grep -qi intel  <<<"$gpus" && pkgs+=(vulkan-intel lib32-vulkan-intel)
    grep -qiE '\b(amd|ati)\b' <<<"$gpus" && pkgs+=(vulkan-radeon lib32-vulkan-radeon)
    grep -qi nvidia <<<"$gpus" && pkgs+=(nvidia-utils lib32-nvidia-utils)
    (( ${#pkgs[@]} )) && printf '%s\n' "${pkgs[@]}"
    return 0
}

# --------------------------------------------------------------------------
# Paquets officiels
# --------------------------------------------------------------------------
install_packages() {
    info "Mise à jour du système et installation des paquets"
    local pkgs=(
        base-devel git curl
        firefox steam blender discord vlc
        kitty zsh ttf-jetbrains-mono-nerd
    )
    mapfile -t vk < <(vulkan_packages)
    sudo pacman -Syu --needed --noconfirm "${pkgs[@]}" "${vk[@]}"
    ok "Paquets installés"
}

# --------------------------------------------------------------------------
# yay (AUR) puis OnlyOffice
# --------------------------------------------------------------------------
install_yay() {
    info "Installation de yay (AUR)"
    if command -v yay >/dev/null; then
        ok "yay déjà installé"
        return
    fi
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
    ok "yay installé"
}

install_onlyoffice() {
    info "Installation d'OnlyOffice"
    yay -S --needed --noconfirm onlyoffice-bin
    ok "OnlyOffice installé"
}

# --------------------------------------------------------------------------
# Shell : oh-my-zsh + powerlevel10k + plugins
# --------------------------------------------------------------------------
clone_or_update() {
    local url=$1 dest=$2
    if [[ -d $dest/.git ]]; then
        git -C "$dest" pull --ff-only --quiet
    else
        git clone --depth=1 --quiet "$url" "$dest"
    fi
}

backup() {
    local f=$1
    if [[ -e $f && ! -L $f ]]; then
        cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
        warn "Sauvegarde de $f"
    fi
}

setup_shell() {
    info "Configuration de zsh + oh-my-zsh + powerlevel10k"
    if [[ ! -d $HOME/.oh-my-zsh ]]; then
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
            "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    clone_or_update https://github.com/romkatv/powerlevel10k.git            "$ZSH_CUSTOM/themes/powerlevel10k"
    clone_or_update https://github.com/zsh-users/zsh-autosuggestions        "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

    backup "$HOME/.zshrc"
    backup "$HOME/.p10k.zsh"
    install -m 644 "$DOTFILES/zsh/.zshrc"    "$HOME/.zshrc"
    install -m 644 "$DOTFILES/zsh/.p10k.zsh" "$HOME/.p10k.zsh"

    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ]]; then
        sudo chsh -s /usr/bin/zsh "$USER"
    fi
    ok "Shell configuré"
}

setup_kitty() {
    info "Configuration de kitty"
    mkdir -p "$HOME/.config/kitty"
    backup "$HOME/.config/kitty/kitty.conf"
    install -m 644 "$DOTFILES/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
    ok "kitty configuré (zsh + traînée du curseur)"
}

enable_multilib
install_packages
install_yay
install_onlyoffice
setup_shell
setup_kitty

info "Terminé ! Ferme ta session (ou relance kitty) pour profiter de zsh."
