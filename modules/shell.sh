#!/usr/bin/env bash
# Module shell : zsh + oh-my-zsh + powerlevel10k + plugins, et kitty.
# shellcheck shell=bash

_clone_or_update() {
    local url=$1 dest=$2
    if [[ -d $dest/.git ]]; then
        run git -C "$dest" pull --ff-only --quiet
    else
        run git clone --depth=1 --quiet "$url" "$dest"
    fi
}

_install_dotfile() {
    local src=$1 dest=$2
    if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
        ok "Inchangé : $dest"
        return 0
    fi
    dry && { printf '\e[2m  [dry-run] installerait %s\e[0m\n' "$dest"; return 0; }
    backup "$dest"
    install -D -m 644 "$src" "$dest"
    ok "Installé : $dest"
}

module_shell() {
    info "Shell : zsh + oh-my-zsh + powerlevel10k"
    pac_install zsh kitty ttf-jetbrains-mono-nerd

    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    _clone_or_update https://github.com/ohmyzsh/ohmyzsh.git                  "$HOME/.oh-my-zsh"
    _clone_or_update https://github.com/romkatv/powerlevel10k.git            "$zsh_custom/themes/powerlevel10k"
    _clone_or_update https://github.com/zsh-users/zsh-autosuggestions        "$zsh_custom/plugins/zsh-autosuggestions"
    _clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting    "$zsh_custom/plugins/zsh-syntax-highlighting"

    _install_dotfile "$DOTFILES/zsh/.zshrc"    "$HOME/.zshrc"
    _install_dotfile "$DOTFILES/zsh/.p10k.zsh" "$HOME/.p10k.zsh"

    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ]]; then
        run sudo chsh -s /usr/bin/zsh "$USER"
    fi
    ok "Shell configuré"

    info "Configuration de kitty"
    _install_dotfile "$DOTFILES/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
    ok "kitty configuré (zsh + traînée du curseur)"
}
