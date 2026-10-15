#!/usr/bin/env bash
# Module security : SSH, pare-feu, fail2ban, auditd, AppArmor, sysctl, résolveur DNS.
# shellcheck shell=bash

# --- SSH ---------------------------------------------------------------------
_ssh_import_keys() {
    [[ -n ${SSH_GITHUB_USER:-} ]] || return 0
    info "SSH : import des clés publiques de github.com/$SSH_GITHUB_USER"
    dry && return 0
    local keys line
    keys="$(curl -fsSL "https://github.com/$SSH_GITHUB_USER.keys")" || { warn "Impossible de lire les clés GitHub"; return 0; }
    install -d -m 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
    while IFS= read -r line; do
        [[ $line == ssh-* || $line == ecdsa-* || $line == sk-* ]] || continue
        grep -qxF "$line" "$HOME/.ssh/authorized_keys" || { printf '%s\n' "$line" >>"$HOME/.ssh/authorized_keys"; ok "Clé ajoutée"; }
    done <<<"$keys"
}

_sshd() {
    info "SSH : serveur durci"
    pac_install openssh
    _ssh_import_keys

    local nopass=""
    if [[ ${SSH_DISABLE_PASSWORD:-no} == yes ]]; then
        if [[ -s $HOME/.ssh/authorized_keys ]]; then
            nopass=$'PasswordAuthentication no\nKbdInteractiveAuthentication no'
        else
            warn "SSH_DISABLE_PASSWORD=yes ignoré : ~/.ssh/authorized_keys est vide (tu te bloquerais l'accès)"
        fi
    fi

    local dest=/etc/ssh/sshd_config.d/10-hardening.conf
    write_root_file "$dest" <<EOF
PermitRootLogin no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
MaxStartups 5:50:10
X11Forwarding no
AllowAgentForwarding no
AllowUsers $USER
ClientAliveInterval 300
ClientAliveCountMax 2
${nopass}
EOF
    run sudo ssh-keygen -A
    if ! dry; then
        if ! sudo sshd -t; then
            sudo rm -f "$dest"
            die "Configuration sshd invalide : $dest supprimé"
        fi
    fi
    run sudo systemctl enable --now sshd.service
    run sudo systemctl reload sshd.service
}

# --- Pare-feu + fail2ban -----------------------------------------------------
_firewall() {
    info "Pare-feu (ufw) + fail2ban"
    if systemctl is-enabled firewalld.service >/dev/null 2>&1; then
        warn "firewalld est actif : ufw ignoré. Ouvre SSH à la main pour ton réseau local."
        FIREWALL=firewalld
    else
        FIREWALL=ufw
        pac_install ufw
        local lan="${LAN_CIDR:-$(detect_lan_cidr)}"
        run sudo ufw default deny incoming
        run sudo ufw default allow outgoing
        if [[ -n $lan ]]; then
            run sudo ufw allow from "$lan" to any port 22 proto tcp comment 'ssh LAN'
            ok "SSH autorisé depuis $lan"
        else
            warn "Sous-réseau local introuvable : SSH reste fermé. Renseigne LAN_CIDR dans config.env."
        fi
        run sudo ufw --force enable
        run sudo systemctl enable --now ufw.service
    fi

    pac_install fail2ban
    local banaction=""
    [[ $FIREWALL == ufw ]] && banaction="banaction = ufw"
    write_root_file /etc/fail2ban/jail.d/10-sshd.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 4
ignoreip = 127.0.0.1/8 ::1 ${FAIL2BAN_IGNORE:-}

[sshd]
enabled  = true
backend  = systemd
port     = ssh
${banaction}
EOF
    run sudo systemctl enable --now fail2ban.service
    run sudo systemctl restart fail2ban.service
}

# --- Audit -------------------------------------------------------------------
_audit() {
    info "Audit (auditd)"
    pac_install audit
    copy_root_file "$FILES/audit/10-hardening.rules" /etc/audit/rules.d/10-hardening.rules 640
    run sudo systemctl enable --now auditd.service
    # Le démarrage d'auditd charge déjà les règles (audit-rules.service) : un second chargement lancé en même
    # temps fait planter auditctl. On attend, puis on ne recharge que si les règles ne sont pas là.
    if ! dry; then
        sleep 3
        sudo auditctl -l 2>/dev/null | grep -q -- '-k identity' || sudo augenrules --load
        sudo systemctl reset-failed audit-rules.service 2>/dev/null || true
    fi
}

# --- AppArmor ----------------------------------------------------------------
_apparmor() {
    info "AppArmor"
    pac_install apparmor
    cmdline_add "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
    run sudo systemctl enable apparmor.service

    # attach_disconnected : requis pour le socket sd_notify de systemd sur certains noyaux (voir le profil)
    local flags="flags=(attach_disconnected) "
    [[ ${APPARMOR_MODE:-complain} == complain ]] && flags="flags=(attach_disconnected,complain) "
    sed "s|@FLAGS@|$flags|" "$FILES/apparmor/usr.bin.sshd" \
        | write_root_file /etc/apparmor.d/usr.bin.sshd 644

    if [[ -d /sys/kernel/security/apparmor ]]; then
        run sudo apparmor_parser -r /etc/apparmor.d/usr.bin.sshd
        run sudo systemctl restart sshd.service
        ok "Profil sshd chargé (${APPARMOR_MODE:-complain})"
    else
        ok "Profil sshd écrit : il sera chargé après le redémarrage (AppArmor n'est pas encore actif)"
    fi
}

# --- sysctl + DNS --------------------------------------------------------------
_sysctl_dns() {
    info "sysctl + résolveur"
    copy_root_file "$FILES/sysctl/90-hardening.conf" /etc/sysctl.d/90-hardening.conf
    run sudo sysctl --system >/dev/null

    if systemctl is-enabled systemd-resolved.service >/dev/null 2>&1; then
        write_root_file /etc/systemd/resolved.conf.d/10-hardening.conf <<'EOF'
[Resolve]
LLMNR=no
MulticastDNS=no
EOF
        run sudo systemctl restart systemd-resolved.service
    else
        ok "systemd-resolved inactif : LLMNR/mDNS ignorés"
    fi
}

module_security() {
    _sshd
    _firewall
    _audit
    _apparmor
    _sysctl_dns
}
