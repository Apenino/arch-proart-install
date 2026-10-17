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

# mpv : lecteur vidéo par défaut. VLC 3 n'est pas natif Wayland et rend mal le HDR (couleurs ternes) ; mpv ramène le HDR
# en SDR proprement. Réglages dans files/mpv/mpv.conf (n'écrase pas une config existante différente : sauvegarde .bak).
_mpv_setup() {
    install_user_file "$FILES/mpv/mpv.conf" "$HOME/.config/mpv/mpv.conf"
    command -v xdg-mime >/dev/null 2>&1 || return 0
    local t
    for t in video/x-matroska video/mp4 video/webm video/x-msvideo video/quicktime video/mpeg video/x-flv; do
        [[ "$(xdg-mime query default "$t" 2>/dev/null)" == mpv.desktop ]] || run xdg-mime default mpv.desktop "$t"
    done
    ok "mpv : lecteur par défaut (mkv, mp4, webm, avi, mov...)"
}

module_apps() {
    info "Applications"

    # Les pilotes d'abord : ils évitent à pacman de demander quel fournisseur Vulkan choisir pour Steam
    local vk
    mapfile -t vk < <(_vulkan_packages)
    ((${#vk[@]})) && pac_install "${vk[@]}"

    pac_install firefox steam blender discord mpv obsidian proton-vpn-gtk-app
    # VS Code officiel (Microsoft, AUR) plutôt que « code » (build libre) : seule la version officielle accepte les
    # extensions Remote-SSH de Microsoft (développement dans des conteneurs/VM). Sur une machine où « code » est déjà
    # installé, l'assistant AUR proposera de le remplacer (conflit de paquets).
    pkg_or_aur visual-studio-code-bin visual-studio-code-bin
    # Minecraft Java : Prism Launcher (open source, plusieurs versions et mods) + Java 21 et 25 (versions récentes du jeu). Connexion avec
    # le compte Microsoft de l'utilisateur dans le lanceur : le jeu doit être possédé.
    pac_install prismlauncher jre21-openjdk jre25-openjdk
    # Paquets supplémentaires choisis dans config.env (ex. solaar pour du matériel Logitech)
    # shellcheck disable=SC2086
    [[ -n ${EXTRA_PACKAGES:-} ]] && pac_install $EXTRA_PACKAGES

    # Dépôts officiels ou CachyOS si disponibles, sinon AUR (les PKGBUILD sont à relire)
    pkg_or_aur proton-pass proton-pass-bin
    pkg_or_aur onlyoffice-bin onlyoffice-bin
    pkg_or_aur proton-mail proton-mail-bin
    # Selawik : équivalent libre de Segoe UI (mêmes dimensions), pour les pages Microsoft ; Calibri a déjà Carlito
    pkg_or_aur ttf-selawik ttf-selawik
    install_user_file "$FILES/fontconfig/60-segoe-selawik.conf" "$HOME/.config/fontconfig/conf.d/60-segoe-selawik.conf"

    _mpv_setup

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
