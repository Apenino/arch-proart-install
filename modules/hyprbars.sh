#!/usr/bin/env bash
# Module hyprbars (FACULTATIF) : barres de titre façon macOS (pastilles rouge/jaune/verte à gauche) sur toutes les
# fenêtres, via le plugin hyprbars de hyprwm/hyprland-plugins. Hyprland n'a pas de barre de titre ; Lucid n'en
# propose pas. Le plugin est compilé contre les en-têtes de Hyprland, au commit que le projet épingle pour la
# version installée (voir files/hyprbars/hyprbars-plugin.sh).
#   HYPRBARS="yes"     ou  ./install.sh --only hyprbars   : installer
#   HYPRBARS="remove"                                      : retirer (ligne de hyprland.lua et fichiers ; le plugin
#                                                            disparaît à la prochaine connexion, pas de déchargement à chaud)
# Ne fait rien si l'interface n'est pas installée.
# shellcheck shell=bash

HYPRBARS_FILES=(
    "$HOME/.config/hypr/modules/hyprbars.lua"
    "$HOME/.config/hypr/scripts/hyprbars-plugin.sh"
    "${XDG_DATA_HOME:-$HOME/.local/share}/lucid/plugins/hyprbars.so"
    "${XDG_DATA_HOME:-$HOME/.local/share}/lucid/plugins/hyprbars.abi"
)

# Pas de déchargement à chaud : décharger le plugin dans la session en cours a fait planter Hyprland (rappels laissés
# par le plugin, SEGV). On retire les fichiers et la ligne de hyprland.lua ; le plugin disparaît à la prochaine connexion.
_hyprbars_remove() {
    info "hyprbars : retrait"
    hypr_unrequire modules.hyprbars
    run rm -f "${HYPRBARS_FILES[@]}"
    if command -v gsettings >/dev/null 2>&1; then
        run gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:close' 2>/dev/null || true
    fi
    ok "hyprbars retiré. Ferme puis rouvre ta session Hyprland : le plugin reste chargé en mémoire jusque-là."
}

module_hyprbars() {
    if [[ ${HYPRBARS:-no} == remove ]]; then
        need_hypr_config "hyprbars" || return 0
        _hyprbars_remove
        return 0
    fi
    if [[ ${HYPRBARS:-no} != yes && ${ONLY:-} != *hyprbars* ]]; then
        ok "hyprbars : module facultatif, ignoré (HYPRBARS=\"yes\" dans config.env, ou --only hyprbars)"
        return 0
    fi
    need_hypr_config "hyprbars" || return 0
    info "hyprbars : barres de titre façon macOS"

    local hypr="$HOME/.config/hypr" loader="$HOME/.config/hypr/scripts/hyprbars-plugin.sh"
    pac_install git base-devel
    install_user_file "$FILES/hyprbars/hyprbars-plugin.sh" "$loader" 755
    install_user_file "$FILES/hyprbars/hyprbars.lua" "$hypr/modules/hyprbars.lua"
    hypr_require modules.hyprbars

    if dry; then
        printf '\e[2m  [dry-run] compilerait et chargerait le plugin\e[0m\n'
        return 0
    fi

    # compilation la première fois ; ensuite « ensure » recompile si Hyprland a changé, puis charge le plugin
    local so="${XDG_DATA_HOME:-$HOME/.local/share}/lucid/plugins/hyprbars.so"
    [[ -f $so ]] || "$loader" build
    if hypr_session_env; then
        if "$loader" ensure; then
            ok "Plugin compilé pour cette version de Hyprland et chargé dans la session en cours"
        else
            warn "Compilation ou chargement impossible : voir « hyprbars-plugin.sh status »"
        fi
    else
        ok "Plugin compilé : il se chargera à la prochaine connexion Hyprland"
    fi
}
