#!/usr/bin/env bash
# Module base : pacman.conf, multilib, mise à jour, outils de base, assistant AUR.
# shellcheck shell=bash

module_base() {
    info "Base : pacman, multilib, mise à jour"

    # Color + ParallelDownloads (décommentés s'ils sont encore commentés)
    if grep -qE '^#(Color|ParallelDownloads)' /etc/pacman.conf; then
        run sudo sed -i -E 's/^#(Color)$/\1/; s/^#(ParallelDownloads.*)$/\1/' /etc/pacman.conf
    fi

    # CheckSpace : pacman vérifie l'espace disque avant d'installer (absent de certaines configs CachyOS)
    if ! grep -qE '^CheckSpace' /etc/pacman.conf; then
        run sudo sed -i -E '0,/^(ParallelDownloads.*|Color)$/ s/^(ParallelDownloads.*|Color)$/\1\nCheckSpace/' /etc/pacman.conf
    fi

    if grep -q '^\[multilib\]' /etc/pacman.conf; then
        ok "multilib déjà activé"
    else
        run sudo sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
        ok "multilib activé"
    fi

    run sudo pacman -Syu --noconfirm
    # pciutils : indispensable à la détection du GPU (lspci) ; sans lui, aucun GPU ne serait détecté
    pac_install base-devel git curl pciutils

    ensure_aur_helper
}
