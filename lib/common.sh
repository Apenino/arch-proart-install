#!/usr/bin/env bash
# Fonctions communes, sourcées par install.sh et les modules (ne pas lancer directement).
# shellcheck shell=bash

# --------------------------------------------------------------------------
# Affichage
# --------------------------------------------------------------------------
info() { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m  ✓\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m  !\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m  ✗\e[0m %s\n' "$*" >&2; exit 1; }

dry() { [[ ${DRY_RUN:-0} -eq 1 ]]; }

# Exécute une commande, ou l'affiche seulement en mode --dry-run.
run() {
    if dry; then
        printf '\e[2m  [dry-run] %s\e[0m\n' "$*"
    else
        "$@"
    fi
}

# --------------------------------------------------------------------------
# Détection du système
# --------------------------------------------------------------------------
is_cachyos() { grep -qiE '^ID=("?)cachyos' /etc/os-release 2>/dev/null; }

root_fstype() { findmnt -no FSTYPE / 2>/dev/null; }
is_btrfs()    { [[ "$(root_fstype)" == btrfs ]]; }

is_laptop() {
    local t
    t="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo 0)"
    [[ $t =~ ^(8|9|10|11|14|30|31|32)$ ]] || compgen -G '/sys/class/power_supply/BAT*' >/dev/null
}

is_intel_cpu() { grep -qm1 GenuineIntel /proc/cpuinfo; }
is_amd_cpu()   { grep -qm1 AuthenticAMD /proc/cpuinfo; }
has_nvidia_gpu() { gpu_list | grep -qi nvidia; }

gpu_list() { lspci 2>/dev/null | grep -E 'VGA compatible|3D controller|Display controller' || true; }

# systemd-boot | grub | limine | unknown
detect_bootloader() {
    if [[ -f /etc/default/limine ]] || command -v limine >/dev/null 2>&1; then
        echo limine
    elif command -v grub-mkconfig >/dev/null 2>&1 && [[ -f /etc/default/grub ]]; then
        echo grub
    elif command -v bootctl >/dev/null 2>&1 && sudo bootctl is-installed >/dev/null 2>&1; then
        echo systemd-boot
    else
        echo unknown
    fi
}

# Sous-réseau local de l'interface par défaut (ex. 192.168.1.0/24), vide si introuvable.
detect_lan_cidr() {
    ip -4 -o route show scope link 2>/dev/null \
        | awk '$1 ~ /\// && $0 !~ /linkdown/ && $3 !~ /^(docker|virbr|veth|br-|lo)/ {print $1; exit}'
}

# --------------------------------------------------------------------------
# Paquets
# --------------------------------------------------------------------------
pkg_installed() { pacman -Qq "$1" >/dev/null 2>&1; }
pkg_in_repos()  { pacman -Si "$1" >/dev/null 2>&1; }

# pac_install paquet... : installe ceux qui manquent, signale ceux introuvables dans les dépôts.
pac_install() {
    local p todo=() missing=()
    for p in "$@"; do
        pkg_installed "$p" && continue
        if pkg_in_repos "$p"; then todo+=("$p"); else missing+=("$p"); fi
    done
    ((${#missing[@]})) && warn "Introuvables dans les dépôts : ${missing[*]}"
    if ((${#todo[@]})); then
        run sudo pacman -S --needed --noconfirm "${todo[@]}"
    else
        ok "Rien à installer ($*)"
    fi
    return 0
}

# Assistant AUR : paru (dépôt CachyOS) ou yay ; sinon on compile yay-bin.
AUR=""
ensure_aur_helper() {
    [[ -n $AUR ]] && return 0
    if command -v paru >/dev/null 2>&1; then AUR=paru
    elif command -v yay >/dev/null 2>&1; then AUR=yay
    elif pkg_in_repos paru; then
        pac_install paru; AUR=paru
    else
        info "Installation de yay (AUR)"
        if dry; then AUR=yay; return 0; fi
        local tmp
        tmp="$(mktemp -d)"
        git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
        AUR=yay
    fi
    ok "Assistant AUR : $AUR"
}

# aur_install paquet... : l'assistant AUR affiche les PKGBUILD pour relecture (comportement par défaut).
aur_install() {
    ensure_aur_helper
    local p todo=()
    for p in "$@"; do pkg_installed "$p" || todo+=("$p"); done
    if ((${#todo[@]})); then
        run "$AUR" -S --needed "${todo[@]}"
    else
        ok "Déjà installés : $*"
    fi
}

# pkg_or_aur nom_dépôt nom_aur : paquet des dépôts s'il existe (officiel ou CachyOS), sinon AUR.
pkg_or_aur() {
    if pkg_installed "$1" || pkg_installed "$2"; then ok "Déjà installé : $1"
    elif pkg_in_repos "$1"; then pac_install "$1"
    else aur_install "$2"; fi
}

# --------------------------------------------------------------------------
# Fichiers
# --------------------------------------------------------------------------
backup() {
    local f=$1
    if [[ -e $f && ! -L $f ]]; then
        cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
        warn "Sauvegarde de $f"
    fi
}

# write_root_file DEST [MODE] : écrit stdin dans DEST (root). Idempotent, sauvegarde l'ancien fichier.
write_root_file() {
    local dest=$1 mode=${2:-644} tmp
    tmp="$(mktemp)"
    cat >"$tmp"
    if sudo test -f "$dest" && sudo cmp -s "$tmp" "$dest"; then
        ok "Inchangé : $dest"
    elif dry; then
        printf '\e[2m  [dry-run] écrirait %s\e[0m\n' "$dest"
    else
        if sudo test -f "$dest"; then sudo cp -a "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"; fi
        sudo install -D -m "$mode" -o root -g root "$tmp" "$dest"
        ok "Écrit : $dest"
    fi
    rm -f "$tmp"
}

# copy_root_file SRC DEST [MODE]
copy_root_file() { write_root_file "$2" "${3:-644}" <"$1"; }

# --------------------------------------------------------------------------
# Ligne de commande du noyau (selon le bootloader)
# --------------------------------------------------------------------------
BOOT_REBUILD=0   # 1 si les images (UKI/initramfs) doivent être régénérées
BOOT_REGEN_GRUB=0

_cmdline_has() { grep -qE "(^|[ \"])$2(=|[ \"]|$)" <<<"$1"; }

# cmdline_add "param[=valeur] ..." : ajoute les paramètres absents (jamais ne remplace une clé existante).
cmdline_add() {
    local bl param key current
    bl="$(detect_bootloader)"
    case $bl in
        systemd-boot)
            if [[ -f /etc/kernel/cmdline ]]; then
                current="$(cat /etc/kernel/cmdline)"
                for param in $1; do
                    key="${param%%=*}"
                    if _cmdline_has "$current" "$key"; then
                        ok "Paramètre déjà présent : $key"
                    else
                        current="$current $param"
                    fi
                done
                if [[ "$current" != "$(cat /etc/kernel/cmdline)" ]]; then
                    if dry; then
                        printf '\e[2m  [dry-run] /etc/kernel/cmdline -> %s\e[0m\n' "$current"
                    else
                        sudo cp -a /etc/kernel/cmdline /etc/kernel/cmdline.bak
                        printf '%s\n' "$current" | sudo tee /etc/kernel/cmdline >/dev/null
                    fi
                    BOOT_REBUILD=1
                fi
            else
                local e changed=0
                for e in /boot/loader/entries/*.conf /efi/loader/entries/*.conf; do
                    [[ -f $e ]] || continue
                    for param in $1; do
                        key="${param%%=*}"
                        if ! sudo grep -E '^options' "$e" | grep -qE "(^| )$key(=| |$)"; then
                            run sudo sed -i -E "/^options/ s|\$| $param|" "$e"
                            changed=1
                        fi
                    done
                done
                ((changed)) || ok "Entrées systemd-boot déjà à jour"
            fi
            ;;
        grub)
            current="$(sed -nE 's/^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/\1/p' /etc/default/grub)"
            local new="$current"
            for param in $1; do
                key="${param%%=*}"
                _cmdline_has "$new" "$key" && { ok "Paramètre déjà présent : $key"; continue; }
                new="$new $param"
            done
            if [[ "$new" != "$current" ]]; then
                run sudo cp -a /etc/default/grub "/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
                run sudo sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${new# }\"|" /etc/default/grub
                BOOT_REGEN_GRUB=1
            fi
            ;;
        *)
            warn "Bootloader '$bl' non géré automatiquement."
            warn "Ajoute à la main ces paramètres noyau : $1"
            ;;
    esac
}

# À appeler une fois en fin de script : régénère ce qui a été modifié.
boot_apply() {
    if ((BOOT_REBUILD)); then
        if command -v mkinitcpio >/dev/null 2>&1; then
            info "Régénération des images de démarrage (mkinitcpio -P)"
            run sudo mkinitcpio -P
        else
            warn "Régénère manuellement tes images de démarrage (dracut, etc.)."
        fi
    fi
    if ((BOOT_REGEN_GRUB)); then
        info "Régénération de la config GRUB"
        run sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi
    return 0
}
