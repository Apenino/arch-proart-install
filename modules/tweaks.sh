#!/usr/bin/env bash
# Module tweaks : réglages de la configuration Hyprland posée par Lucid. Rejouable seul, sans réinstaller Lucid :
#   ./install.sh --only tweaks
# Ne fait rien si l'interface n'est pas installée (pas de ~/.config/hypr/hyprland.lua).
#   - ordre de chargement look/Settings (réglages de Lucid Settings > Windows pris en compte) ;
#   - clavier du système (Lucid met "us") ;  - curseur sans rotation ;
#   - XWayland lissé (XWAYLAND_SMOOTH) ;     - latence de jeu, facultatif (GAMING_LATENCY).
# shellcheck shell=bash

_tweak_keyboard() {
    local input="$HOME/.config/hypr/modules/input.lua" kb
    kb="${KB_LAYOUT:-$(localectl status 2>/dev/null | awk -F': *' '/X11 Layout/{print $2}')}"
    if [[ -f $input && -n $kb && $kb != n/a ]]; then
        run sed -i -E "s/^(\s*kb_layout\s*=\s*)\"[^\"]*\"/\1\"$kb\"/" "$input"
        ok "Clavier Hyprland : $kb"
    fi
}

# Curseur : pas de rotation/inclinaison (le zoom au secouement est conservé)
_tweak_cursor() {
    local plugins="$HOME/.config/hypr/modules/plugins.lua"
    [[ -f $plugins ]] || return 0
    run sed -i -E 's/^(\s*mode\s*=\s*)"(rotate|tilt|stretch)"/\1"none"/' "$plugins"
    ok "Curseur : rotation désactivée"
}

# XWayland : lissage bilinéaire (sinon Steam et les applications X11 sont pixélisées à l'échelle fractionnaire)
_tweak_xwayland() {
    [[ ${XWAYLAND_SMOOTH:-yes} == yes ]] || { ok "XWAYLAND_SMOOTH=no : XWayland inchangé"; return 0; }
    install_user_file "$FILES/hypr/xwayland.lua" "$HOME/.config/hypr/modules/xwayland.lua"
    hypr_require modules.xwayland
}

# Latence de jeu (facultatif, désactivé par défaut) : voir docs/PROBLEMES-CONNUS.md §6 avant de l'activer.
# Avec GAMING_LATENCY=no, un module déjà installé est retiré de hyprland.lua (le fichier reste sur le disque).
_tweak_gaming() {
    if [[ ${GAMING_LATENCY:-no} == yes ]]; then
        install_user_file "$FILES/hypr/gaming.lua" "$HOME/.config/hypr/modules/gaming.lua"
        hypr_require modules.gaming
    else
        hypr_unrequire modules.gaming
    fi
}

# L'installeur de Lucid ajoute require("modules.lucid-look") à la FIN de hyprland.lua, donc après modules.settings : le look
# (arrondi 25, ombre) écrase alors ce que l'utilisateur règle dans Lucid Settings > Windows, qui affiche les lignes comme verrouillées
# (« overridden » dans $XDG_RUNTIME_DIR/lucid-settings-status.json). On remet le look avant Settings.
_tweak_lucid_order() {
    hypr_require_before modules.lucid-look modules.settings
}

module_tweaks() {
    need_hypr_config "Réglages Hyprland" || return 0
    info "Réglages Hyprland"
    _tweak_lucid_order
    _tweak_keyboard
    _tweak_cursor
    _tweak_xwayland
    _tweak_gaming
}
