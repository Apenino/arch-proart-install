#!/usr/bin/env bash
# Module hyprbars (FACULTATIF) : barres de titre façon macOS (pastilles rouge/jaune/verte à gauche) sur toutes les
# fenêtres, via le plugin hyprbars de hyprwm/hyprland-plugins. Hyprland n'a pas de barre de titre ; Lucid n'en
# propose pas. Le plugin est compilé contre les en-têtes de Hyprland, au commit que le projet épingle pour la
# version installée (voir files/hyprbars/hyprbars-plugin.sh). À activer avec HYPRBARS="yes" ou --only hyprbars.
# shellcheck shell=bash

module_hyprbars() {
    if [[ ${HYPRBARS:-no} != yes && ${ONLY:-} != *hyprbars* ]]; then
        ok "hyprbars : module facultatif, ignoré (HYPRBARS=\"yes\" dans config.env, ou --only hyprbars)"
        return 0
    fi
    info "hyprbars : barres de titre façon macOS"

    local hypr="$HOME/.config/hypr" cfg="$HOME/.config/hypr/hyprland.lua"
    local loader="$hypr/scripts/hyprbars-plugin.sh"
    if [[ ! -f $cfg ]]; then
        warn "Pas de config Hyprland : lance d'abord le module desktop. hyprbars ignoré."
        return 0
    fi

    pac_install git base-devel
    install_user_file "$FILES/hyprbars/hyprbars-plugin.sh" "$loader" 755
    install_user_file "$FILES/hyprbars/hyprbars.lua" "$hypr/modules/hyprbars.lua"

    # une seule ligne dans hyprland.lua (sauvegardé avant)
    if grep -q 'modules.hyprbars' "$cfg"; then
        ok "hyprland.lua charge déjà modules.hyprbars"
    else
        if dry; then
            printf '\e[2m  [dry-run] ajouterait require("modules.hyprbars") à hyprland.lua\e[0m\n'
        else
            backup "$cfg"
            printf '\nrequire("modules.hyprbars")\n' >>"$cfg"
            ok "require(\"modules.hyprbars\") ajouté à hyprland.lua"
        fi
    fi

    if dry; then
        printf '\e[2m  [dry-run] compilerait et chargerait le plugin\e[0m\n'
        return 0
    fi

    # compilation : la première fois ; ensuite « ensure » recompile si Hyprland a changé depuis
    local so="${XDG_DATA_HOME:-$HOME/.local/share}/lucid/plugins/hyprbars.so"
    if [[ ! -f $so ]]; then
        "$loader" build
    else
        "$loader" ensure || warn "Recompilation impossible pour cette version de Hyprland (hyprbars-plugin.sh build)"
    fi

    # chargement à chaud si une session Hyprland tourne (sinon : au prochain démarrage de session)
    local rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" newest
    if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} && -d $rt/hypr ]]; then
        newest="$(find "$rt/hypr" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' | sort -rn | head -1 | cut -d' ' -f2)"
        [[ -n $newest ]] && export XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$newest"
    fi
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        if "$loader" load; then
            ok "Plugin chargé dans la session en cours"
        else
            warn "Chargement à chaud impossible : il le sera à la prochaine connexion"
        fi
    else
        ok "Plugin compilé : il se chargera à la prochaine connexion Hyprland"
    fi
}
