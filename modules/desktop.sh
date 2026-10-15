#!/usr/bin/env bash
# Module desktop : Hyprland + shell Lucid (https://github.com/Sn3akyy1/lucid) + SDDM.
# Lucid est cloné à une version précise et son commit est vérifié avant exécution.
# shellcheck shell=bash

LUCID_URL="https://github.com/Sn3akyy1/lucid.git"
LUCID_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/arch-proart/lucid"

_lucid_fetch() {
    info "Lucid $LUCID_REF : récupération"
    dry && return 0
    mkdir -p "$(dirname "$LUCID_DIR")"
    if [[ -d $LUCID_DIR/.git ]]; then
        git -C "$LUCID_DIR" fetch --tags --quiet
    else
        git clone --quiet "$LUCID_URL" "$LUCID_DIR"
    fi
    git -C "$LUCID_DIR" checkout --quiet "$LUCID_REF"
    local got
    got="$(git -C "$LUCID_DIR" rev-parse HEAD)"
    [[ $got == "$LUCID_COMMIT" ]] \
        || die "Commit Lucid inattendu ($got, attendu $LUCID_COMMIT). Vérifie LUCID_REF/LUCID_COMMIT avant de continuer."
    ok "Commit vérifié : ${got:0:12}"
}

_lucid_install() {
    info "Lucid : installation (sans les applications du dock ni le look : kitty/zsh restent les tiens)"
    dry && { printf '\e[2m  [dry-run] lancerait %s/install.sh -y --no-apps --no-look\e[0m\n' "$LUCID_DIR"; return 0; }
    (cd "$LUCID_DIR" && ./install.sh -y --no-apps --no-look)
}

# Lucid remplace le clavier par "us" : on remet celui du système.
_hypr_tweaks() {
    local input="$HOME/.config/hypr/modules/input.lua" plugins="$HOME/.config/hypr/modules/plugins.lua" kb
    kb="${KB_LAYOUT:-$(localectl status 2>/dev/null | awk -F': *' '/X11 Layout/{print $2}')}"
    if [[ -f $input && -n $kb && $kb != n/a ]]; then
        run sed -i -E "s/^(\s*kb_layout\s*=\s*)\"[^\"]*\"/\1\"$kb\"/" "$input"
        ok "Clavier Hyprland : $kb"
    fi
    # Curseur : pas de rotation/inclinaison (le zoom au secouement est conservé)
    if [[ -f $plugins ]]; then
        run sed -i -E 's/^(\s*mode\s*=\s*)"(rotate|tilt|stretch)"/\1"none"/' "$plugins"
        ok "Curseur : rotation désactivée"
    fi
}

_sddm() {
    info "SDDM : thème Lucid"
    local conf=/etc/sddm.conf
    if [[ ! -f $conf ]]; then
        write_root_file "$conf" <<'EOF'
[Theme]
Current=lucid
EOF
    elif grep -q '^Current=' "$conf"; then
        run sudo sed -i 's/^Current=.*/Current=lucid/' "$conf"
    else
        dry || printf '\n[Theme]\nCurrent=lucid\n' | sudo tee -a "$conf" >/dev/null
    fi
    run sudo systemctl enable --force sddm.service
    # Fond et palette du compte pour l'écran de connexion (nécessite la session graphique)
    if [[ -n ${WAYLAND_DISPLAY:-} && -x $HOME/.config/lucid/sync-sddm.sh ]]; then
        run "$HOME/.config/lucid/sync-sddm.sh" --missing
    else
        ok "Fond de l'écran de connexion : généré par Lucid au premier lancement de la session"
    fi
}

# Retire ce que Lucid installe mais dont on n'a pas besoin. Les paquets de Lucid sont d'abord marqués
# "explicites" : sans cela, retirer une dépendance (kdeconnect...) emporte aussi qt6-5compat,
# qt6-multimedia, pipewire-pulse... qui ne sont installés que comme dépendances.
_prune() {
    [[ ${PRUNE:-yes} == yes ]] || { ok "PRUNE=no : aucun nettoyage"; return 0; }
    info "Nettoyage des paquets inutiles"
    dry && return 0

    local p keep=(pipewire-pulse pipewire-audio wireplumber nautilus gvfs uwsm sddm hyprland)
    if [[ -f $LUCID_DIR/install.sh ]]; then
        mapfile -t lucid_pkgs < <(python3 -I - "$LUCID_DIR/install.sh" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
for name in ("PKG_REQUIRED", "PKG_FEATURES", "PKG_HYPR"):
    m = re.search(name + r"=\((.*?)\n?\)\n", s, re.S)
    if m:
        print("\n".join(re.sub(r"#.*", "", m.group(1)).split()))
PY
)
        keep+=("${lucid_pkgs[@]}" qt6-multimedia-ffmpeg qt6-shadertools sound-theme-freedesktop)
    fi
    local installed=()
    for p in "${keep[@]}"; do pkg_installed "$p" && installed+=("$p"); done
    ((${#installed[@]})) && sudo pacman -D --asexplicit "${installed[@]}" >/dev/null

    local cands=() c
    for c in kdeconnect sshfs dunst polkit-kde-agent wofi noto-fonts-cjk; do pkg_installed "$c" && cands+=("$c"); done
    # dolphin seulement si Nautilus est là pour le remplacer
    pkg_installed dolphin && pkg_installed nautilus && cands+=(dolphin)
    if ((${#cands[@]})); then
        sudo pacman -Rs --noconfirm "${cands[@]}"
        ok "Retirés : ${cands[*]}"
    else
        ok "Rien à nettoyer"
    fi

    # Si KDE Connect est resté (PRUNE partiel), on l'empêche au moins de démarrer
    if pkg_installed kdeconnect; then
        install -d "$HOME/.config/systemd/user"
        ln -sf /dev/null "$HOME/.config/systemd/user/kdeconnectd.service"
        ln -sf /dev/null "$HOME/.config/systemd/user/app-org.kde.kdeconnect.daemon.service"
    fi
}

module_desktop() {
    pac_install hyprland uwsm sddm xdg-desktop-portal-hyprland nautilus
    _lucid_fetch
    _lucid_install
    _hypr_tweaks
    _sddm
    _prune
}
