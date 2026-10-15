#!/usr/bin/env bash
# Module system : Btrfs + snapshots (snapper), maintenance, énergie, TPM, nom d'hôte.
# shellcheck shell=bash

# --- Btrfs : COW + checksums + compression ---------------------------------
_btrfs_options() {
    is_btrfs || { ok "Racine non Btrfs : options Btrfs ignorées"; return 0; }
    info "Btrfs : options de montage"

    if grep -qE 'nodatacow|nodatasum' /etc/fstab; then
        warn "fstab : nodatacow/nodatasum retirés (ils désactivent le COW et les checksums)"
        run sudo cp -a /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
        run sudo sed -i -E '/btrfs/ s/,(nodatasum|nodatacow)//g' /etc/fstab
    fi
    # noatime (sauf si déjà là) et compression zstd (sauf si une compression est déjà choisie)
    run sudo sed -i -E '/[[:space:]]btrfs[[:space:]]/ { /noatime/! s/,relatime/,noatime/ }' /etc/fstab
    run sudo sed -i -E '/[[:space:]]btrfs[[:space:]]/ { /compress/! s/(btrfs[[:space:]]+[^[:space:]]+)/\1,compress=zstd:1/ }' /etc/fstab

    local mp
    while read -r mp; do
        run sudo mount -o remount,datacow,datasum,noatime "$mp" || warn "Remontage impossible : $mp (effectif au prochain démarrage)"
    done < <(findmnt -rn -t btrfs -o TARGET)

    run sudo systemctl enable --now fstrim.timer
    run sudo systemctl enable --now "btrfs-scrub@$(systemd-escape -p /).timer"
}

# --- Snapshots : snapper avec sous-volumes dédiés ----------------------------
_snapper() {
    is_btrfs || return 0
    info "Snapshots : snapper"
    pac_install snapper snap-pac compsize btrfs-progs
    dry && return 0

    local src dev uuid
    src="$(findmnt -no SOURCE /)"; dev="${src%%[*}"
    uuid="$(findmnt -no UUID /)"

    local cfg mp snapname
    for cfg in root:/ home:/home; do
        mp="${cfg#*:}"; cfg="${cfg%%:*}"
        mountpoint -q "$mp" || continue
        [[ "$(findmnt -no FSTYPE "$mp" 2>/dev/null)" == btrfs ]] || continue
        snapname="@snapshots"; [[ $cfg == home ]] && snapname="@home_snapshots"

        if sudo snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx "$cfg"; then
            ok "Config snapper '$cfg' déjà présente"
            continue
        fi
        sudo snapper -c "$cfg" create-config "$mp"
        # snapper crée un .snapshots imbriqué ; on le remplace par un sous-volume de premier niveau
        sudo btrfs subvolume delete "$mp/.snapshots" >/dev/null 2>&1 || true
        sudo mkdir -p /mnt/btrfs-top
        sudo mount -o subvolid=5 "$dev" /mnt/btrfs-top
        [[ -d /mnt/btrfs-top/$snapname ]] || sudo btrfs subvolume create "/mnt/btrfs-top/$snapname" >/dev/null
        sudo umount /mnt/btrfs-top && sudo rmdir /mnt/btrfs-top
        sudo mkdir -p "$mp/.snapshots"
        if ! grep -qE "[[:space:]]${mp%/}/\.snapshots[[:space:]]" /etc/fstab; then
            printf 'UUID=%s\t%s/.snapshots\tbtrfs\trw,noatime,compress=zstd:1,ssd,discard=async,space_cache=v2,subvol=/%s\t0 0\n' \
                "$uuid" "${mp%/}" "$snapname" | sudo tee -a /etc/fstab >/dev/null
        fi
        sudo systemctl daemon-reload
        sudo mount "${mp%/}/.snapshots"
        sudo chmod 750 "${mp%/}/.snapshots"
        sudo snapper -c "$cfg" set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes NUMBER_CLEANUP=yes \
            TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 \
            TIMELINE_LIMIT_MONTHLY=1 TIMELINE_LIMIT_YEARLY=0 NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5 \
            ALLOW_USERS="$USER" SYNC_ACL=yes
        sudo snapper -c "$cfg" create -d "baseline (post-install)"
        ok "snapper '$cfg' configuré"
    done
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
}

# --- Maintenance, énergie, TPM, nom d'hôte -------------------------------------
_maintenance() {
    info "Maintenance"
    pac_install pacman-contrib fwupd
    run sudo systemctl enable --now paccache.timer fwupd-refresh.timer

    if is_cachyos; then
        ok "CachyOS : miroirs gérés par cachyos-rate-mirrors (reflector ignoré)"
    else
        pac_install reflector
        write_root_file /etc/xdg/reflector/reflector.conf <<'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--country France,Germany,Belgium,Netherlands
--latest 10
--sort rate
EOF
        run sudo systemctl enable --now reflector.timer
    fi
}

_power() {
    is_laptop || { ok "Pas un portable : gestion d'énergie ignorée"; return 0; }
    info "Énergie (portable)"
    if pkg_installed tlp; then
        ok "TLP déjà installé : power-profiles-daemon ignoré (ils entrent en conflit)"
    else
        pac_install power-profiles-daemon
        run sudo systemctl enable --now power-profiles-daemon.service
    fi
    if is_intel_cpu; then
        pac_install thermald
        run sudo systemctl enable --now thermald.service
    fi
}

# Les unités NvPCR de systemd échouent tant que les images UKI ne sont pas signées avec une clé PCR.
# Elles sont sans utilité ici : on les masque si (et seulement si) elles sont en échec.
_tpm_units() {
    local u masked=0
    for u in systemd-tpm2-setup-early.service systemd-pcrproduct.service; do
        if systemctl is-failed -q "$u" 2>/dev/null; then
            run sudo systemctl mask "$u"; masked=1
        fi
    done
    if systemctl list-units --failed --plain --no-legend 'systemd-pcrlogin@*' 2>/dev/null | grep -q .; then
        run sudo systemctl mask 'systemd-pcrlogin@.service'; masked=1
    fi
    ((masked)) && { run sudo systemctl reset-failed; ok "Unités TPM NvPCR en échec masquées"; }
    return 0
}

_hostname() {
    [[ -n ${HOSTNAME_NEW:-} ]] || return 0
    [[ "$(hostnamectl --static 2>/dev/null)" == "$HOSTNAME_NEW" ]] && { ok "Nom d'hôte déjà : $HOSTNAME_NEW"; return 0; }
    info "Nom d'hôte : $HOSTNAME_NEW"
    run sudo hostnamectl set-hostname "$HOSTNAME_NEW"
    grep -q "$HOSTNAME_NEW" /etc/hosts \
        || { dry || printf '127.0.1.1\t%s.localdomain\t%s\n' "$HOSTNAME_NEW" "$HOSTNAME_NEW" | sudo tee -a /etc/hosts >/dev/null; }
}

module_system() {
    _btrfs_options
    _snapper
    _maintenance
    _power
    _tpm_units
    _hostname
}
