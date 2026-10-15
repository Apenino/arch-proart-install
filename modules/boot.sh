#!/usr/bin/env bash
# Module boot : démarrage silencieux avec le logo Arch (Plymouth) et menu du bootloader masqué.
# Les images de démarrage sont régénérées une seule fois, en fin de script (boot_apply).
# shellcheck shell=bash

_plymouth_theme() {
    local want=${PLYMOUTH_THEME:-arch-logo}
    if [[ $want == keep ]]; then
        ok "PLYMOUTH_THEME=keep : thème actuel conservé ($(plymouth-set-default-theme 2>/dev/null || echo inconnu))"
        return 0
    fi
    local f t=/usr/share/plymouth/themes/arch-logo
    for f in arch-logo.plymouth arch-logo.script logo.png; do
        copy_root_file "$FILES/plymouth/arch-logo/$f" "$t/$f"
    done
    if [[ "$(plymouth-set-default-theme 2>/dev/null)" == arch-logo ]]; then
        ok "Thème Plymouth déjà : arch-logo"
    else
        run sudo plymouth-set-default-theme arch-logo
        # le thème est copié dans l'initramfs à sa construction : il faut la refaire
        # shellcheck disable=SC2034
        BOOT_REBUILD=1
    fi
}

# HOOKS effectifs, calculés comme mkinitcpio : config principale, puis fragments dans l'ordre.
# (Un fragment peut dériver la liste, ex. CachyOS : HOOKS=(${HOOKS[@]/kms/}).)
_effective_hooks() {
    local cfgs=()
    if [[ -n ${MKINIT_CONF_FILES:-} ]]; then
        read -ra cfgs <<<"$MKINIT_CONF_FILES"
    else
        cfgs=(/etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf)
    fi
    bash -c 'for f in "$@"; do [[ -f $f ]] && source "$f"; done; echo "${HOOKS[*]}"' _ "${cfgs[@]}" 2>/dev/null
}

# Insère le hook plymouth dans la liste HOOKS de la config principale (après "systemd" si l'initramfs
# est basé sur systemd, sinon après "udev"), seulement s'il manque dans la liste effective.
_plymouth_hook() {
    if ! command -v mkinitcpio >/dev/null 2>&1; then
        warn "mkinitcpio absent (dracut ?) : ajoute le module plymouth à ta config d'initramfs à la main."
        return 0
    fi
    local eff conf=${MKINIT_MAIN_CONF:-/etc/mkinitcpio.conf}
    eff="$(_effective_hooks)"
    if grep -qw plymouth <<<"$eff"; then
        ok "Hook plymouth déjà présent (HOOKS effectifs)"
        return 0
    fi
    local after=udev
    grep -qw systemd <<<"$eff" && after=systemd
    if ! grep -E '^\s*HOOKS=' "$conf" | grep -qw "$after"; then
        warn "Le hook '$after' n'est pas dans $conf : ajoute 'plymouth' à HOOKS à la main."
        return 0
    fi
    run sudo cp -a "$conf" "$conf.bak.$(date +%Y%m%d%H%M%S)"
    run sudo sed -i -E "/^\s*HOOKS=/ s/\b$after\b/$after plymouth/" "$conf"
    # shellcheck disable=SC2034
    BOOT_REBUILD=1
    ok "Hook plymouth ajouté après '$after' ($conf)"
}

_hide_boot_menu() {
    [[ ${BOOT_HIDE_MENU:-yes} == yes && "$(detect_bootloader)" == systemd-boot ]] || return 0
    local lc f
    for f in /boot/loader/loader.conf /efi/loader/loader.conf; do [[ -f $f ]] && lc=$f && break; done
    [[ -n ${lc:-} ]] || return 0
    run sudo cp -a "$lc" "$lc.bak"
    if sudo grep -qE '^timeout' "$lc"; then
        run sudo sed -i -E 's/^timeout.*/timeout 0/' "$lc"
    elif ! dry; then
        echo 'timeout 0' | sudo tee -a "$lc" >/dev/null
    fi
    sudo grep -qE '^editor' "$lc" 2>/dev/null || { dry || echo 'editor no' | sudo tee -a "$lc" >/dev/null; }
    ok "Menu du bootloader masqué (maintiens la barre d'espace au démarrage pour l'afficher)"
}

module_boot() {
    [[ ${BOOT_SPLASH:-yes} == yes ]] || { ok "BOOT_SPLASH=no : démarrage inchangé"; return 0; }
    info "Démarrage silencieux avec logo (Plymouth)"
    pac_install plymouth
    _plymouth_theme
    _plymouth_hook
    cmdline_add "quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0"
    _hide_boot_menu
}
