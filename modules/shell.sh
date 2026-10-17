#!/usr/bin/env bash
# Module shell : zsh + oh-my-zsh (thème robbyrussell) avec les plugins système autosuggestions et
# syntax-highlighting. Le prompt starship et la config de kitty sont posés par Lucid (module desktop).
# shellcheck shell=bash

OMZ_URL="https://github.com/ohmyzsh/ohmyzsh.git"

# oh-my-zsh épinglé : clonage (ou récupération) puis passage au commit OMZ_COMMIT, vérifié ; la mise à jour
# automatique est coupée dans .zshrc (zstyle ':omz:update' mode disabled). Mettre à jour = changer OMZ_COMMIT.
_omz_fetch() {
    local dest="$HOME/.oh-my-zsh" got
    info "oh-my-zsh ${OMZ_COMMIT:0:12} : récupération"
    dry && return 0
    if [[ -d $dest/.git ]]; then
        git -C "$dest" fetch --quiet origin
    else
        git clone --quiet "$OMZ_URL" "$dest"
    fi
    git -C "$dest" checkout --quiet "$OMZ_COMMIT"
    got="$(git -C "$dest" rev-parse HEAD)"
    [[ $got == "$OMZ_COMMIT" ]] \
        || die "Commit oh-my-zsh inattendu ($got, attendu $OMZ_COMMIT). Vérifie OMZ_COMMIT avant de continuer."
    ok "Commit vérifié : ${got:0:12}"
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

# .zshrc : Lucid y ajoute son bloc starship ("# added by Lucid"). On compare sans ce bloc pour rester idempotent,
# et si le fichier doit être remplacé, on remet le bloc à la fin.
_install_zshrc() {
    local src="$DOTFILES/zsh/.zshrc" dest="$HOME/.zshrc" block=""
    _strip_trailing_blanks() { sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'; }
    if [[ -f $dest ]]; then
        block="$(awk '/^# added by Lucid/ {f=1} f' "$dest")"
        if cmp -s <(_strip_trailing_blanks <"$src") <(awk '/^# added by Lucid/ {exit} {print}' "$dest" | _strip_trailing_blanks); then
            ok "Inchangé : $dest (hors bloc Lucid)"
            return 0
        fi
    fi
    if dry; then
        printf '\e[2m  [dry-run] installerait %s\n\e[0m' "$dest"
        return 0
    fi
    install_user_file "$src" "$dest"
    [[ -n $block ]] && printf '\n%s\n' "$block" >>"$dest"
    return 0
}

module_shell() {
    info "Shell : zsh + oh-my-zsh"
    pac_install zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting starship kitty ttf-jetbrains-mono-nerd

    _omz_fetch
    _remove_p10k
    _install_zshrc

    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ]]; then
        run sudo chsh -s /usr/bin/zsh "$USER"
    fi
    ok "Shell configuré (le prompt starship et kitty viennent de Lucid)"
}
