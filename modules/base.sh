#!/usr/bin/env bash
# Module base : pacman.conf, multilib, mise à jour, outils de base, assistant AUR.
# shellcheck shell=bash

module_base() {
    info "Base : pacman, multilib, mise à jour"

    # Color + ParallelDownloads (décommentés s'ils sont encore commentés)
    run sudo sed -i -E 's/^#(Color)$/\1/; s/^#(ParallelDownloads.*)$/\1/' /etc/pacman.conf

    if grep -q '^\[multilib\]' /etc/pacman.conf; then
        ok "multilib déjà activé"
    else
        run sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
        ok "multilib activé"
    fi

    run sudo pacman -Syu --noconfirm
    pac_install base-devel git curl

    ensure_aur_helper
}
