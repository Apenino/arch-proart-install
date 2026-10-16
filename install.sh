#!/usr/bin/env bash
# Script post-installation Arch Linux / CachyOS (ASUS ProArt)
#
# Modules, dans l'ordre d'exécution :
#   base      pacman.conf, multilib, mise à jour, assistant AUR
#   system    Btrfs + snapshots, maintenance, énergie, nom d'hôte
#   security  SSH, pare-feu, fail2ban, auditd, AppArmor, sysctl
#   shell     zsh + oh-my-zsh (le prompt starship et kitty viennent de Lucid)
#   apps      Firefox, Steam, Blender, Obsidian, VS Code, Proton, OnlyOffice...
#   desktop   Hyprland + shell Lucid + SDDM
#   hardware  microcode, pilote NVIDIA (open) et réglages Hyprland/boot associés
#   hyprbars  (facultatif) barres de titre façon macOS : HYPRBARS="yes" ou --only hyprbars
#   boot      démarrage silencieux avec logo (Plymouth)
#
# Usage : ./install.sh [--dry-run] [--only a,b] [--skip a,b] [--list] [-h]
# À lancer en utilisateur normal (pas en root) : sudo est demandé quand c'est nécessaire.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_DIR
export DOTFILES="$REPO_DIR/dotfiles"
export FILES="$REPO_DIR/files"

# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

ALL_MODULES=(base system security shell apps desktop hardware hyprbars boot)
ONLY=""
SKIP=""
DRY_RUN=0

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while (($#)); do
    case $1 in
        --dry-run) DRY_RUN=1 ;;
        --only)    ONLY="${2:?--only demande une liste}"; shift ;;
        --skip)    SKIP="${2:?--skip demande une liste}"; shift ;;
        --list)    printf '%s\n' "${ALL_MODULES[@]}"; exit 0 ;;
        -h|--help) usage ;;
        *) die "Option inconnue : $1 (voir --help)" ;;
    esac
    shift
done
export DRY_RUN

if [[ $EUID -eq 0 ]]; then
    die "Lance ce script en utilisateur normal (pas en root), sudo sera utilisé au besoin."
fi
[[ -f /etc/arch-release ]] || die "Ce script est prévu pour Arch Linux ou une base Arch (CachyOS...)."

# --------------------------------------------------------------------------
# Configuration (config.env, voir config.env.example) — jamais commitée
# --------------------------------------------------------------------------
HOSTNAME_NEW="" LAN_CIDR="" SSH_GITHUB_USER="" SSH_DISABLE_PASSWORD="no" FAIL2BAN_IGNORE=""
EXTRA_PACKAGES="" XWAYLAND_SMOOTH="yes" HYPRBARS="no" LUCID_INSTALL_FLAGS="" AUR_REVIEW="yes" APPARMOR_MODE="complain" BOOT_SPLASH="yes" PLYMOUTH_THEME="arch-logo" BOOT_HIDE_MENU="yes" PRUNE="yes" KB_LAYOUT=""
LUCID_REF="3d6ed3b84edf7c31d24117eb58ed86cb357113c5" LUCID_COMMIT="3d6ed3b84edf7c31d24117eb58ed86cb357113c5"
if [[ -f $REPO_DIR/config.env ]]; then
    # shellcheck source=/dev/null
    source "$REPO_DIR/config.env"
    info "Configuration chargée : config.env"
fi
export HOSTNAME_NEW LAN_CIDR SSH_GITHUB_USER SSH_DISABLE_PASSWORD FAIL2BAN_IGNORE
export EXTRA_PACKAGES XWAYLAND_SMOOTH HYPRBARS LUCID_INSTALL_FLAGS AUR_REVIEW APPARMOR_MODE BOOT_SPLASH PLYMOUTH_THEME BOOT_HIDE_MENU PRUNE KB_LAYOUT LUCID_REF LUCID_COMMIT

in_list() { [[ ",$2," == *",$1,"* ]]; }

selected=()
for m in "${ALL_MODULES[@]}"; do
    if [[ -n $ONLY ]] && ! in_list "$m" "$ONLY"; then continue; fi
    if [[ -n $SKIP ]] && in_list "$m" "$SKIP"; then continue; fi
    selected+=("$m")
done
((${#selected[@]})) || die "Aucun module sélectionné."

dry && warn "MODE DRY-RUN : rien n'est modifié, les commandes sont seulement affichées."
sudo -n true 2>/dev/null || sudo -v

for m in "${selected[@]}"; do
    # shellcheck source=/dev/null
    source "$REPO_DIR/modules/$m.sh"
    "module_$m"
done

boot_apply

info "Terminé !"
cat <<EOF

À faire à la main :
  - Redémarrer (noyau, AppArmor, démarrage silencieux, SDDM).
  - SSH : copier ta clé depuis l'autre machine (ssh-copy-id), puis, si tu veux couper le mot de passe,
    mettre SSH_DISABLE_PASSWORD="yes" dans config.env et relancer : ./install.sh --only security
  - Te connecter à Proton (Mail, VPN, Pass), Steam, Obsidian.
  - Mises à jour du firmware : fwupdmgr get-updates
EOF
