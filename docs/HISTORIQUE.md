# Historique et état de la machine de référence

Ce document résume **tout ce qui a été fait, décidé et appris** pendant la mise au point de la machine
de référence (surnommée *Maverick*), dont est tiré ce dépôt. Il sert à reprendre le projet sans la
conversation d'origine : pourquoi chaque réglage existe, ce qui a été testé, ce qui ne l'a pas été.

> Le dépôt est public : aucune adresse IP, clé, e-mail ou nom de machine personnelle n'y figure.
> Les valeurs propres à une installation vont dans `config.env` (ignoré par git).

## 1. La machine de référence

| Élément | Valeur |
|---|---|
| Type | portable Dell (batterie), UEFI, Secure Boot **désactivé** |
| CPU / GPU | Intel Tiger Lake-H, iGPU UHD GT1 (jeu d'instructions x86-64-v4 / AVX-512 pris en charge) |
| Mémoire / disque | 16 Go de RAM, NVMe de 476 Go, **non chiffré**, Btrfs |
| TPM | 2.0 (STMicro) présent et fonctionnel |
| Système de départ | Arch Linux, noyau 7.2.9-arch1, systemd 262, pacman 7.1.0, Hyprland 0.56 (config **Lua**) |
| Système à la fin | idem + dépôts CachyOS v4, noyau `linux-cachyos` 7.2.9-2 (le noyau Arch reste installé) |
| Démarrage | systemd-boot avec **images UKI** (un seul fichier `.efi` par noyau), ESP de 1 Go montée sur `/boot` |
| Sous-volumes Btrfs | `@` (/), `@home`, `@log`, `@pkg` (cache pacman), puis `@snapshots` et `@home_snapshots` |

Point de départ constaté : Hyprland + kitty + wofi + dolphin installés, aucun zsh, SSH désactivé,
et **toutes les partitions Btrfs montées en `nodatacow,nodatasum`** (voir §4).

## 2. Chronologie

1. **Shell et SSH.** zsh + oh-my-zsh (thème robbyrussell, plugins `git sudo history colored-man-pages`,
   autosuggestions et syntax-highlighting), `chsh` vers zsh. `sshd` activé (il a fallu générer les clés
   d'hôte avec `ssh-keygen -A`). Autostart de Hyprland depuis le tty1 via `~/.zprofile` (retiré plus tard).
2. **Thème Lucid** ([Sn3akyy1/lucid](https://github.com/Sn3akyy1/lucid) v1.20.1) : installeur lu avant
   exécution, lancé avec `-y --no-apps` (les applications du dock pèsent plusieurs Go). Il remplace
   `hyprland.lua` par une config modulaire (`~/.config/hypr/modules/*.lua`, ancienne config sauvegardée),
   installe starship dans `.zshrc`, remet le clavier en `us` (**à corriger en `fr`**) et rend waybar inutile.
3. **Dépendances manquantes** : seuls `playerctl` (dépôts) et `python-pywal` (AUR, optionnel) manquaient.
4. **Audit.** 4 unités TPM en échec, SSH ouvert à tout le réseau avec mot de passe, pas de pare-feu,
   LLMNR (5355) et KDE Connect (1716) à l'écoute, `sudo` sans mot de passe pour l'utilisateur.
5. **Durcissement, passe 1** : `ufw` (tout refusé en entrée sauf SSH depuis le réseau local), KDE Connect
   masqué, LLMNR/mDNS coupés, `sshd` durci, sysctl (§3).
6. **fail2ban + auditd** (§3).
7. **SSH par clé uniquement**, après test d'une connexion par clé depuis l'autre machine (le journal
   montrait `Accepted publickey`), puis `PasswordAuthentication no`.
8. **AppArmor** : le noyau Arch l'a compilé mais pas dans la liste LSM par défaut → paramètre noyau
   `lsm=landlock,lockdown,yama,integrity,apparmor,bpf`, image UKI régénérée, service activé. Profil
   `sshd` écrit en mode *complain*, testé, puis passé en *enforce* (§3).
9. **Nettoyage** de paquets inutiles (§5).
10. **Image de secours** `fallback` réactivée dans le preset mkinitcpio.
11. **Btrfs et snapshots** (§3).
12. **CachyOS** : clé de dépôt vérifiée, dépôts v4 ajoutés avant `core`/`extra`, 526 paquets remplacés par
    leurs builds optimisés, noyau `linux-cachyos` + `cachyos-settings` (§3). Démarrage unique de test
    (`bootctl set-oneshot`) avant de l'adopter.
13. **SDDM** : le thème Lucid était installé mais jamais activé (l'installeur de Lucid laisse ce choix à
    l'utilisateur) → `/etc/sddm.conf` avec `Current=lucid`.
14. **Curseur** : rotation désactivée (plugin `hypr-dynamic-cursors`, réglage absent de l'interface de Lucid).
15. **Démarrage silencieux** avec logo (Plymouth) et menu du bootloader masqué (§3).
16. **Applications** : Firefox, Steam, Blender, Obsidian, VS Code (Code-OSS), Proton VPN/Pass/Mail, OnlyOffice.
17. **Angles morts** traités : `paru`, maintenance pacman, firmware, énergie, nom d'hôte, TPM.
18. **Ce dépôt** : refonte en script modulaire (`install.sh` + `modules/`).

## 3. Configuration finale, par domaine

### Sécurité
- **SSH** (`/etc/ssh/sshd_config.d/10-hardening.conf`) : `PermitRootLogin no`, `PubkeyAuthentication yes`,
  `MaxAuthTries 3`, `LoginGraceTime 30`, `MaxStartups 5:50:10`, `X11Forwarding no`,
  `AllowAgentForwarding no`, `AllowUsers <utilisateur>`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`,
  puis `PasswordAuthentication no` et `KbdInteractiveAuthentication no`.
- **Pare-feu** `ufw` : entrée refusée par défaut, sortie autorisée, SSH (22/tcp) autorisé **depuis le
  sous-réseau local seulement**.
- **fail2ban** : jail `sshd` (backend systemd, action `ufw`), bannissement 1 h après 4 échecs en 10 min.
- **auditd** : 16 règles (`files/audit/10-hardening.rules`) sur `passwd/shadow/group/gshadow`, `sudoers`,
  config SSH, `ufw`, `/etc/systemd/system`, `pam.d`, `cron`, `lastlog`, élévations par setuid et chargement
  de modules noyau.
- **sysctl** (`files/sysctl/90-hardening.conf`) : `kptr_restrict=2`, `dmesg_restrict=1`,
  `unprivileged_bpf_disabled=1`, `bpf_jit_harden=2`, syncookies, `rp_filter`, redirections ICMP et source
  routing refusés, protections `fs.protected_*`.
- **Résolveur** : LLMNR et mDNS désactivés (`/etc/systemd/resolved.conf.d/10-hardening.conf`).
- **AppArmor** : profil `sshd` (`files/apparmor/usr.bin.sshd`). Il confine le démon et `sshd-session` /
  `sshd-auth` ; les shells et commandes lancés **après** connexion sortent du profil (`Ux`). Procédure
  suivie : *complain* → écriture de règles manquantes vues dans les journaux d'audit (`lastlog2`,
  `machine-id`, `uid_map`, capacité `net_admin`) → connexion de test → *enforce*. Sur la machine de
  référence il est en **enforce** ; le script installe **complain** par défaut (prudence sur une machine
  non testée). Le noyau CachyOS a bien AppArmor compilé (vérifié au démarrage).
- **KDE Connect** : masqué puis désinstallé.
- **Non modifié volontairement** : `sudo` sans mot de passe pour l'utilisateur.

### Btrfs et snapshots
- Options de montage corrigées : `nodatasum,nodatacow` retirés (ils désactivent le copy-on-write **et** les
  sommes de contrôle, donc aussi l'intérêt des snapshots), `noatime`, `compress=zstd:1`. Les données déjà
  écrites n'ont pas de checksums tant qu'elles ne sont pas réécrites (une défragmentation compressée a été
  lancée ; la plupart des fichiers étaient déjà incompressibles).
- **snapper** + **snap-pac** (un snapshot avant/après chaque transaction pacman). Sous-volumes dédiés
  `@snapshots` → `/.snapshots` et `@home_snapshots` → `/home/.snapshots` (snapper les crée imbriqués ; on
  les remplace par des sous-volumes de premier niveau et on ajoute les lignes `fstab`). Rétention : 5
  horaires, 7 quotidiens, 2 hebdomadaires, 1 mensuel.
- Timers : `fstrim`, `btrfs-scrub@-` (mensuel), `snapper-timeline`, `snapper-cleanup`. `discard=async`
  était déjà actif.
- **Limite connue** : les noyaux et images UKI sont sur l'ESP (FAT32), **hors des snapshots**. Après un
  retour en arrière de `/`, il faut réinstaller le noyau / régénérer les images (`mkinitcpio -P`) pour que
  les modules correspondent au noyau.

### CachyOS (sur la machine de référence, hors script)
- Clé de dépôt importée depuis un serveur de clés et **vérifiée par son empreinte officielle**
  `882D CFE4 8E20 51D4 8E25 62AB F3B6 0748 8DB3 5A47`, puis signée localement (`pacman-key --lsign-key`).
- Dépôts `cachyos-v4`, `cachyos-core-v4`, `cachyos-extra-v4`, `cachyos` placés **avant** `[core]`,
  `Architecture = x86_64 x86_64_v3 x86_64_v4`. Le script officiel `cachyos-repo.sh` a été lu mais **pas
  exécuté** : les étapes ont été faites à la main. Sauvegarde : `pacman.conf.bak-pre-cachyos`.
- `pacman -Syu` : 526 paquets remplacés par leur build v4 (même version, suffixe `-1.1`), plus
  `linux-cachyos` 7.2.9-2 et `cachyos-settings` (qui apporte notamment `ananicy-cpp` ; `vm.swappiness` a été observé à 150).
  Un miroir de repli a été utilisé pour quelques fichiers (erreur de téléchargement sans conséquence).
- Image `arch-linux-cachyos.efi` ; le noyau Arch (`arch-linux.efi`) et l'image `fallback` restent
  disponibles. Essai en **démarrage unique** avant adoption.

### Démarrage
- **UKI** générées par mkinitcpio ; ligne de commande dans `/etc/kernel/cmdline`
  (`root=PARTUUID=… rootflags=subvol=@ rw rootfstype=btrfs lsm=… quiet splash loglevel=3
  rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0 zswap.enabled=0`).
- **Plymouth** : thème maison `arch-logo` (logo Arch 220 px sur fond noir, légère pulsation, script en
  `files/plymouth/arch-logo/`), hook `plymouth` après `udev` dans `HOOKS`.
- `loader.conf` : `timeout 0`, `editor no` ; **maintenir la barre d'espace** au démarrage affiche le menu.
- L'image `fallback` est **volontairement sans Plymouth et verbeuse**
  (`/etc/mkinitcpio-fallback.conf` + `/etc/kernel/cmdline.fallback`) : si le splash casse le démarrage, il
  reste un chemin lisible. Cette séparation n'est **pas** dans le script (trop liée à cette configuration).
- Durée mesurée : ~17 s (8 s de firmware, 1,2 s de loader, 3,5 s de noyau, 4,3 s d'espace utilisateur).

### Bureau
- Hyprland (config Lua modulaire de Lucid), SDDM (greeter Qt6 sur X11) avec le thème Lucid
  (`/etc/sddm.conf`, `[Theme] Current=lucid`), session via `uwsm`.
- Clavier remis en `fr` (`~/.config/hypr/modules/input.lua`).
- Curseur : `mode = "none"` dans `~/.config/hypr/modules/plugins.lua` (le zoom quand on secoue la souris
  reste actif ; `shake.enabled = false` pour le couper aussi).
- Entrées de lanceur masquées via `~/.local/share/applications/*.desktop` (`NoDisplay=true`) : Avahi
  (3 outils), outils V4L2 (2), `uuctl`.

### Système et maintenance
- `paru` (dépôt CachyOS), `pacman-contrib` (`paccache.timer`), `reflector` (miroirs Arch : France,
  Allemagne, Belgique, Pays-Bas ; ignoré sous CachyOS), `fwupd` (+ `fwupd-refresh.timer`).
- Portable : `power-profiles-daemon` (profil `balanced`) + `thermald` (CPU Intel).
- **TPM** : les unités `systemd-tpm2-setup-early`, `systemd-pcrproduct` et `systemd-pcrlogin@` échouaient car
  `systemd-tpm2-setup` cherche `tpm2-pcr-public-key.pem`, fichier qui n'existe que si les images UKI sont
  **signées avec une clé PCR** (hors de notre configuration). Elles ont été **masquées**
  (`systemctl unmask` pour revenir en arrière). Le TPM lui-même fonctionne.
- Nom d'hôte changé (`hostnamectl` + `/etc/hosts`). `~/.zprofile` (autostart tty1) retiré : SDDM gère la session.

### Applications installées
Firefox, Steam (+ `lib32-vulkan-intel`, `lib32-mesa`), Blender, Obsidian, VS Code (`code`, version
Code-OSS), Proton VPN (`proton-vpn-gtk-app`), Proton Pass (dépôt CachyOS), OnlyOffice (`onlyoffice-bin`,
dépôt CachyOS), Proton Mail (AUR `proton-mail-bin` 1.15.1, construit à la main).
Le `PKGBUILD` de Proton Mail a été **relu** : il télécharge le `.deb` depuis `proton.me` avec sommes de
contrôle sha512/b2 et n'a pas de script d'installation.
**Écartés** : Claude Desktop (pas d'application officielle Linux → on utilise le web), `rclone` (reporté).
Proton Drive : aucune application Linux n'existe.

## 4. Pièges rencontrés (à ne pas refaire)

| Piège | Conséquence | Remède |
|---|---|---|
| `pacman -Rs` sur une dépendance (kdeconnect, dolphin...) | emporte `qt6-5compat`, `qt6-multimedia`, `sound-theme-freedesktop` que **Lucid exige**, installés seulement comme dépendances | marquer d'abord ces paquets `--asexplicit` ; **toujours lire la liste `--print` avant** |
| Retirer `songrec` sans relire la simulation | a aussi retiré `pipewire-pulse` (audio des applications PulseAudio, dont Firefox) | réinstallé en `--asexplicit` ; le script marque désormais les paquets de Lucid comme explicites |
| `v4l-utils` | impossible à retirer : `ffmpeg` en dépend | on masque seulement ses entrées de lanceur |
| `bootctl is-installed` sans droits | détection du bootloader à `unknown` (l'ESP est en `0700`) | appelé avec `sudo` (bug trouvé par le `--dry-run`) |
| `/tmp` vidé au redémarrage | clones et fichiers de travail perdus | tout ce qui compte est dans le dépôt |
| Lucid remet le clavier en `us` et laisse waybar | clavier faux, doublon de barre | clavier réglé après Lucid ; waybar retiré |
| Installeur de Lucid | n'active pas le thème SDDM | écrire `/etc/sddm.conf` |
| `systemd-boot` + une seule UKI, sans secours | aucun repli si une image échoue | `fallback` réactivé ; copie de l'ancienne UKI avant chaque changement de noyau/paramètres |
| `nodatacow,nodatasum` sur Btrfs | pas de checksums, snapshots moins utiles | options corrigées |

## 5. Paquets retirés (sûrs, vérifiés avant)

`noto-fonts-cjk`, `xf86-video-amdgpu/-ati/-nouveau` et `vulkan-radeon/-nouveau` (GPU absents),
`libva-intel-driver` (remplacé par `intel-media-driver`), `kdeconnect`, `sshfs`, `dunst` (remplacé par
`lucidnotif`), `polkit-kde-agent` (remplacé par `lucidpolkit`), `wofi` (lanceur de Lucid), `dolphin`
(Nautilus conservé), `fish`, `waybar`, `songrec`, plus une centaine de bibliothèques KDE devenues orphelines.

## 6. Ce que le script fait différemment de la machine de référence

| Sujet | Machine de référence | Script |
|---|---|---|
| Prompt | starship (installé par Lucid) | identique (powerlevel10k a été abandonné, §14) |
| Terminal / shell | kitty configuré par Lucid | identique (look complet de Lucid, `shell zsh`) |
| Profil AppArmor `sshd` | enforce | complain (option `APPARMOR_MODE`) |
| Image `fallback` verbeuse | oui | non (spécifique à la configuration UKI) |
| CachyOS (dépôts, noyau, réglages) | installé à la main | **hors périmètre** : fourni par l'ISO CachyOS |
| Mot de passe SSH | coupé | optionnel (`SSH_DISABLE_PASSWORD`) |
| IP / réseau local | codés en dur sur la machine | détectés ou fournis dans `config.env` |

## 7. Volontairement laissé de côté

- **`sudo` sans mot de passe** : décision de l'utilisateur, non modifié.
- **Sauvegarde externe** : les snapshots sont sur le même disque ; une copie hors machine
  (`restic`, `borg`, `rclone`) reste à faire.
- **Chiffrement du disque (LUKS) et Secure Boot** (`sbctl`) : non faits ; surtout utiles pour un portable
  qui sort de chez soi. Signer les UKI avec une clé PCR règlerait aussi les unités TPM.
- **Réservation DHCP** de l'adresse de la machine sur le routeur.
- `kernel.unprivileged_userns_clone=1` (valeur de `cachyos-settings`, par défaut chez Arch) : moins strict
  que le reste du durcissement.
- Profils AppArmor pour d'autres services que `sshd`.
- `rclone` / Proton Drive.

## 8. Vérifier une installation neuve

```bash
./install.sh --dry-run                   # lire attentivement ce qui serait fait
./install.sh --only system,security      # par étapes, si tu préfères
cat /sys/kernel/security/lsm             # doit contenir apparmor (après redémarrage)
sudo aa-status | head                    # profil sshd chargé
sudo ufw status verbose                  # SSH seulement depuis le réseau local
sudo fail2ban-client status sshd
sudo auditctl -l | wc -l                 # 16 règles
sudo snapper list-configs && sudo snapper -c root list
findmnt -t btrfs -o TARGET,OPTIONS       # plus de nodatacow, compress=zstd présent
systemctl --failed                       # idéalement vide
powerprofilesctl get                     # portable : profil d'énergie
```

Commandes utiles : `sudo snapper -c root create -d "avant X" -c important` (snapshot manuel),
`sudo mkinitcpio -P` (régénérer les images), `sudo bootctl list` (entrées de démarrage),
`sudo bootctl set-default <id>.efi` (entrée par défaut), `sudo journalctl -u sshd -b`.

## 9. Pistes pour la suite

1. Tester le script sur l'installation CachyOS fraîche, corriger les écarts (surtout la détection du
   bootloader : Limine n'est pas géré, seuls systemd-boot et GRUB le sont).
2. Passer `APPARMOR_MODE` à `enforce` après un test SSH.
3. Ajouter un module de sauvegarde externe.
4. Mettre à jour Lucid : changer `LUCID_REF` et `LUCID_COMMIT` après relecture des changements
   (commit actuel `3d6ed3b84edf7c31d24117eb58ed86cb357113c5`).

## 10. Machine cible et module `hardware`

Après la mise au point sur la machine de référence, la fiche de la machine cible (export `msinfo32` de Windows)
a permis d'adapter le script : voir [MATERIEL.md](MATERIEL.md). Constat principal : c'est un **PC de bureau AMD
avec une RTX 5080**, très différent d'un portable Intel. Changements :

- nouveau module **`hardware`** : microcode (`amd-ucode`/`intel-ucode`) et pilote NVIDIA **open** (obligatoire pour
  Blackwell) avec paramètres noyau `nvidia-drm.modeset=1 nvidia-drm.fbdev=1`, modules NVIDIA dans l'initramfs
  (utile pour Plymouth et Wayland) et variables d'environnement Hyprland ;
- `pciutils` ajouté à `base` : la détection du GPU (`lspci`) renvoyait sinon « aucun GPU » sans erreur ;
- `EXTRA_PACKAGES` dans `config.env` pour des paquets en plus (ex. `solaar`) ;
- une expression de détection des « anciens » GPU NVIDIA classait à tort les GTX 16xx (Turing) comme non
  compatibles avec les modules open : corrigé après test.

Non testé sur la vraie carte : les noms de paquets ont été vérifiés dans les dépôts, la logique par simulation.

## 11. Premier contact avec une vraie installation CachyOS (lecture seule, via SSH)

L'installation CachyOS de la machine cible a été inspectée avant de lancer le script. Constat et corrections :

| Constat sur CachyOS | Conséquence | Correction |
|---|---|---|
| Les entrées systemd-boot sont générées par **`sdboot-manage`** à partir de `LINUX_OPTIONS` (`/etc/sdboot-manage.conf`) ; `/etc/kernel/cmdline` existe mais n'alimente pas les entrées | les paramètres noyau (`lsm=…apparmor`, `nvidia-drm…`) n'auraient jamais été pris en compte | `cmdline_add` édite `LINUX_OPTIONS`, puis `sdboot-manage gen` est lancé en fin de script |
| Démarrage par **initramfs séparé** (`initrd=\initramfs-linux-cachyos.img`), pas d'image UKI | la logique « UKI » de Maverick ne s'applique pas | gérée par le même mécanisme (`mkinitcpio -P` si nécessaire) |
| **Plymouth déjà installé** (hook en place, thème CachyOS), `quiet splash` déjà présents | changer de thème sans reconstruire l'initramfs ne changerait rien au démarrage | `BOOT_REBUILD=1` quand le thème change ; option `PLYMOUTH_THEME` (`arch-logo` ou `keep`) |
| Modules NVIDIA déjà chargés tôt via `/etc/mkinitcpio.conf.d/10-chwd.conf` avec **`MODULES+=(`** | la détection `MODULES=` les ratait et ajoutait des doublons | détection sur toute la config (`=` et `+=`, fragments compris) |
| Pilote **NVIDIA open** déjà installé par l'installeur (`linux-cachyos-nvidia-open`) | le module `hardware` ne l'installe pas une seconde fois | détection d'un pilote existant (déjà prévue) |
| Dépôts `cachyos-znver4` (Zen 5), noyaux `linux-cachyos` et `linux-cachyos-lts` | `paru` s'installe depuis le dépôt CachyOS | rien à changer |
| Shell de connexion **fish** | les commandes distantes passent par fish ; le script bascule ensuite sur zsh | les scripts utilisent bash (`#!/usr/bin/env bash`) |
| `blkid` sans droits root renvoie un résultat vide | l'UUID des lignes `fstab` de snapper aurait été vide | `findmnt -no UUID /` |
| Les deux SanDisk sont vus comme **NVMe** (pas SATA) | erreur dans la fiche matérielle | `docs/MATERIEL.md` corrigé |

Autres observations : la RAM tourne bien à **6000 MT/s** (2 × 32 Go), Secure Boot est désactivé, aucune unité
systemd n'est en échec (les unités TPM de la machine de référence ne posent pas de problème ici), Btrfs a déjà
`noatime` et `compress=zstd:1`, l'ESP fait 2 Go. `snapper`, `paru`, `fail2ban` et `apparmor` ne sont pas
installés : c'est le travail du script.

## 12. Premier lancement réel sur la machine cible

- Le script s'est arrêté de lui-même au module `desktop` : **le tag `v1.20.1` de Lucid avait été déplacé** par son
  auteur (quelques minutes après l'épinglage, un correctif de capture d'écran avait été ajouté au même numéro de
  version). La vérification du commit a empêché d'exécuter du code non relu. Le diff (un commit, quatre fichiers,
  aucun changement d'installeur ni appel réseau) a été relu puis accepté.
- Leçon : l'épinglage se fait maintenant **sur le hash du commit** (`LUCID_REF` = `LUCID_COMMIT`), jamais sur un tag.

## 13. Premier redémarrage de la machine cible : sshd bloqué en « activating »

Après le redémarrage, `sshd` restait en `activating (start)` puis était tué et relancé en boucle, alors que les
connexions SSH réussissaient. Journal : `ssh_systemd_notify: socket "/run/systemd/notify" write: Permission denied`.

- **Cause** : le profil AppArmor de `sshd`. Le journal d'audit brut indiquait
  `info="Failed name lookup - disconnected path" error=-13 name="systemd/notify"` : le noyau CachyOS ne reconstitue pas
  le chemin du socket `sd_notify` de systemd (chemin « déconnecté »). C'est une **erreur de résolution de chemin, pas un
  refus de règle** : le mode *complain* ne la contourne donc pas, et `ausearch -m AVC | grep sshd` ne montrait rien
  d'utile (le filtre était trop étroit ; l'événement existe bien dans `/var/log/audit/audit.log`).
- **Bissection** : décharger le profil (`apparmor_parser -R`) + `systemctl restart sshd` → `active` aussitôt.
- **Fausse piste** : des règles `unix dgram` (hypothèse plausible) n'ont rien changé ; elles ont été retirées.
- **Correctif** : drapeau `attach_disconnected` + règle `/systemd/notify w,`. `sshd` passe `active`, 0 redémarrage.
- **Piège de diagnostic** : `ausearch` lit son entrée standard quand elle est un tube ; lancé depuis `ssh … bash -s`,
  il a avalé la suite du script. Toujours `ausearch --input-logs` (ou `< /dev/null`) dans un script distant.
- Le noyau Arch de la machine de référence n'avait pas ce comportement : le profil y fonctionnait sans ce drapeau.
- **Seconde cause, découverte au redémarrage suivant** : le correctif marchait à chaud mais `sshd` retombait en
  `activating` au démarrage. Le script sauvegardait chaque fichier réécrit **à côté de l'original**
  (`usr.bin.sshd.bak.<date>`), or `/etc/apparmor.d/` est lu **en entier** par `apparmor.service` : quatre anciennes
  versions du profil, toutes nommées `sshd`, étaient chargées à leur tour et l'une d'elles (ancienne, en `complain`,
  sans le bon réglage) écrasait la bonne. Le processus affichait `sshd (complain)` alors que le fichier réel était en
  `enforce`, indice décisif. **Correctif** : les sauvegardes vont dans `/var/backups/arch-proart-install/`,
  jamais dans un dossier que le service parcourt.
- **Leçon de méthode** : un correctif « qui marche à chaud » doit être revalidé **à froid** (redémarrage), et un
  profil AppArmor chargé doit se comparer au fichier voulu (`/sys/kernel/security/apparmor/profiles`).

## 14. Finitions sur la machine cible

- **Écrans** : Lucid place les écrans « automatiquement » dans l'ordre des connecteurs, ce qui peut inverser la
  disposition voulue (SDDM, lui, suit un autre ordre). La disposition explicite s'écrit dans
  `~/.config/hypr/lucid-monitors.lua` (format de la page *Réglages > Affichage*, appliqué à chaud par
  `hyprctl eval "LucidMonitors.apply()"`). L'écran de la barre, du dock et des widgets se règle par l'IPC de Lucid :
  `qs ipc call -- displays shell <écran>` (puis `bar auto`, `dock auto` pour qu'ils suivent). Ces préférences sont dans
  `~/.config/quickshell/lucidprefs/prefs.json`, dossier que l'installeur de Lucid peut déplacer : le module `desktop`
  les met de côté et les restaure.
- **SSH** : mot de passe coupé (`SSH_DISABLE_PASSWORD="yes"`) après vérification qu'une clé fonctionne et qu'un essai par
  mot de passe est refusé. `AllowUsers`, `fail2ban`, pare-feu inchangés.
- **Shell** : powerlevel10k abandonné au profit de l'environnement de la machine de référence : oh-my-zsh
  (`robbyrussell`), plugins système, starship et kitty fournis par Lucid (qui n'est plus lancé avec `--no-look`).
  `fish` est retiré s'il n'est plus le shell de connexion ; un paquet exigé par un autre (ex. `cachyos-fish-config`)
  est conservé sans bloquer le reste du nettoyage.

