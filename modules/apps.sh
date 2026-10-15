#!/usr/bin/env bash
# Module apps : logiciels du quotidien.
# shellcheck shell=bash

# Pilotes Vulkan 32 bits selon le GPU (évite le choix interactif de Steam)
_vulkan_packages() {
    local gpus pkgs=()
    gpus="$(gpu_list)"
    grep -qi intel  <<<"$gpus" && pkgs+=(vulkan-intel lib32-vulkan-intel lib32-mesa)
    grep -qiE '\b(amd|ati)\b' <<<"$gpus" && pkgs+=(vulkan-radeon lib32-vulkan-radeon lib32-mesa)
    grep -qi nvidia <<<"$gpus" && pkgs+=(nvidia-utils lib32-nvidia-utils)
    ((${#pkgs[@]})) && printf '%s\n' "${pkgs[@]}"
    return 0
}

module_apps() {
    info "Applications"

    # Les pilotes d'abord : ils évitent à pacman de demander quel fournisseur Vulkan choisir pour Steam
    local vk
    mapfile -t vk < <(_vulkan_packages)
    ((${#vk[@]})) && pac_install "${vk[@]}"

    pac_install firefox steam blender discord vlc obsidian code proton-vpn-gtk-app

    # Dépôts officiels ou CachyOS si disponibles, sinon AUR (les PKGBUILD sont à relire)
    pkg_or_aur proton-pass proton-pass-bin
    pkg_or_aur onlyoffice-bin onlyoffice-bin
    pkg_or_aur proton-mail proton-mail-bin

    # Entrées de lanceur inutiles : masquées (NoDisplay), pas désinstallées
    local app dir="$HOME/.local/share/applications"
    for app in bvnc bssh avahi-discover qv4l2 qvidcap uuctl; do
        [[ -f /usr/share/applications/$app.desktop ]] || continue
        if dry; then
            printf '\e[2m  [dry-run] masquerait %s\e[0m\n' "$app"
        else
            install -d "$dir"
            printf '[Desktop Entry]\nType=Application\nName=%s (hidden)\nNoDisplay=true\nHidden=true\n' "$app" >"$dir/$app.desktop"
        fi
    done
}
