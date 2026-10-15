#!/usr/bin/env bash
# Module hardware : microcode CPU et pilote NVIDIA (modules open) avec les réglages Hyprland / boot associés.
# Les cartes RTX 50 (Blackwell) ne fonctionnent qu'avec les modules open de NVIDIA.
# shellcheck shell=bash

NVIDIA_EARLY_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

# --- Microcode ----------------------------------------------------------------
_microcode() {
    if is_amd_cpu; then pac_install amd-ucode
    elif is_intel_cpu; then pac_install intel-ucode; fi
}

# --- NVIDIA ---------------------------------------------------------------------
# Un pilote NVIDIA est-il déjà là (choisi à l'installation de la distribution) ?
_nvidia_driver_present() {
    pacman -Qq 2>/dev/null | grep -qE '^(nvidia(-open)?(-dkms|-lts)?|linux.*-nvidia(-open)?|nvidia-[0-9]+xx.*)$' \
        || lsmod 2>/dev/null | grep -q '^nvidia '
}

# Paquet des modules noyau à installer, selon le noyau en place.
_nvidia_kernel_pkg() {
    if pkg_installed linux-cachyos && pkg_in_repos linux-cachyos-nvidia-open; then
        echo linux-cachyos-nvidia-open
    elif pkg_installed linux && pkg_in_repos nvidia-open; then
        echo nvidia-open
    else
        echo nvidia-open-dkms
    fi
}

# Module déjà déclaré dans MODULES=(...) ou MODULES+=(...), dans la config principale ou ses fragments ?
_mkinit_module_declared() {
    local files f
    if [[ -n ${MKINIT_CONF_FILES:-} ]]; then
        read -ra files <<<"$MKINIT_CONF_FILES"
    else
        files=(/etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf)
    fi
    for f in "${files[@]}"; do
        [[ -f $f ]] && grep -E '^\s*MODULES\+?=' "$f" | grep -qw "$1" && return 0
    done
    return 1
}

# mkinitcpio_add_modules FICHIER mod... : ajoute à MODULES=(...) les modules qu'aucune config ne déclare déjà.
mkinitcpio_add_modules() {
    local conf=$1; shift
    local m missing=()
    for m in "$@"; do
        _mkinit_module_declared "$m" || missing+=("$m")
    done
    ((${#missing[@]})) || { ok "Modules déjà chargés tôt : $*"; return 0; }
    run sudo cp -a "$conf" "$conf.bak.$(date +%Y%m%d%H%M%S)"
    run sudo sed -i -E "s/^(\s*MODULES=\()([^)]*)\)/\1\2 ${missing[*]})/; s/^(\s*MODULES=\()\s+/\1/" "$conf"
    # shellcheck disable=SC2034
    BOOT_REBUILD=1
    ok "Modules ajoutés à l'initramfs : ${missing[*]}"
}

_nvidia_early_kms() {
    command -v mkinitcpio >/dev/null 2>&1 || { warn "mkinitcpio absent : ajoute $NVIDIA_EARLY_MODULES à l'initramfs à la main."; return 0; }
    # shellcheck disable=SC2086
    mkinitcpio_add_modules /etc/mkinitcpio.conf $NVIDIA_EARLY_MODULES
}

# Variables d'environnement Hyprland pour NVIDIA, dans un module Lua chargé par hyprland.lua.
_nvidia_hyprland_env() {
    local cfg="$HOME/.config/hypr/hyprland.lua" mod="$HOME/.config/hypr/modules/nvidia.lua"
    if [[ ! -f $cfg ]]; then
        ok "Pas de config Hyprland pour l'instant : réglages NVIDIA ignorés (relance ce module après 'desktop')"
        return 0
    fi
    local want
    want="$(cat <<'LUA'
-- Réglages NVIDIA pour Hyprland (écrit par arch-proart-install)
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
LUA
)"
    if [[ -f $mod ]] && [[ "$(cat "$mod")" == "$want" ]]; then
        ok "Inchangé : $mod"
    elif dry; then
        printf '\e[2m  [dry-run] écrirait %s\e[0m\n' "$mod"
        return 0
    else
        install -d "$(dirname "$mod")"
        printf '%s\n' "$want" >"$mod"
        ok "Environnement NVIDIA pour Hyprland : $mod"
    fi
    if ! grep -q 'require("modules.nvidia")' "$cfg"; then
        backup "$cfg"
        printf '\nrequire("modules.nvidia")\n' >>"$cfg"
    fi
    ok "Environnement NVIDIA pour Hyprland : $mod"
}

_nvidia() {
    has_nvidia_gpu || { ok "Pas de GPU NVIDIA"; return 0; }
    info "NVIDIA : pilote open + Wayland"

    if gpu_list | grep -qiE 'GeForce (GTX )?(6|7|9|10)[0-9]{2}\b|Quadro (K|M|P)[0-9]'; then
        warn "GPU NVIDIA ancien : les modules open ne le gèrent pas. Choisis le pilote adapté à la main."
        return 0
    fi

    if _nvidia_driver_present; then
        ok "Pilote NVIDIA déjà installé"
    else
        local kpkg
        kpkg="$(_nvidia_kernel_pkg)"
        if [[ $kpkg == nvidia-open-dkms ]]; then
            local k
            for k in linux linux-lts linux-zen linux-hardened linux-cachyos; do
                pkg_installed "$k" && pac_install "$k-headers"
            done
        fi
        pac_install "$kpkg"
    fi

    pac_install nvidia-utils lib32-nvidia-utils nvidia-settings libva-nvidia-driver egl-wayland

    # DRM modeset + framebuffer : requis pour Wayland et pour un splash propre
    cmdline_add "nvidia-drm.modeset=1 nvidia-drm.fbdev=1"
    _nvidia_early_kms
    _nvidia_hyprland_env
}

module_hardware() {
    _microcode
    _nvidia
}
