#!/usr/bin/env bash
# Module shell : zsh + oh-my-zsh (thème robbyrussell) avec les plugins système autosuggestions et
# syntax-highlighting. Le prompt starship et la config de kitty sont posés par Lucid (module desktop).
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

# Retire powerlevel10k et les plugins clonés à la main (les paquets système les remplacent).
_remove_p10k() {
    local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}" p
    for p in "$zsh_custom/themes/powerlevel10k" "$zsh_custom/plugins/zsh-autosuggestions" "$zsh_custom/plugins/zsh-syntax-highlighting"; do
        [[ -d $p ]] && { run rm -rf "$p"; ok "Retiré : $p"; }
    done
    if [[ -f $HOME/.p10k.zsh ]]; then
        dry || mv "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.bak.$(date +%Y%m%d%H%M%S)"
        ok "powerlevel10k : ~/.p10k.zsh mis de côté (.bak)"
    fi
    return 0
}

module_shell() {
    info "Shell : zsh + oh-my-zsh"
    pac_install zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting starship kitty ttf-jetbrains-mono-nerd

    _clone_or_update https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    _remove_p10k
    _install_dotfile "$DOTFILES/zsh/.zshrc" "$HOME/.zshrc"

    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ]]; then
        run sudo chsh -s /usr/bin/zsh "$USER"
    fi
    ok "Shell configuré (le prompt starship et kitty viennent de Lucid)"
}
