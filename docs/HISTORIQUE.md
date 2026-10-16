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

## 15. hyprbars : barres de titre façon macOS (module facultatif)

> Retiré de la machine de référence le 16/10/2026 (le module reste dans le dépôt) : voir §21.

Lucid n'a pas d'option de barre de titre ni de boutons de fenêtre, et Hyprland n'en dessine pas : les applications
n'ont des boutons que si elles les dessinent elles-mêmes (les applications GTK n'affichent qu'une croix : réglage
`button-layout = appmenu:close`). Dans Hyprland il n'y a de plus ni vraie réduction (pas de barre des tâches) ni
agrandissement classique : le bouton jaune de macOS n'a pas d'équivalent direct.

- **Solution** : le plugin `hyprbars` (hyprwm/hyprland-plugins), absent des dépôts Arch et de l'AUR, compilé ici avec
  `make` contre les en-têtes du paquet `hyprland`, **au commit que `hyprpm.toml` épingle pour la version installée**
  (hash vérifié). Le chargeur `files/hyprbars/hyprbars-plugin.sh` est adapté du script que Lucid utilise pour son
  plugin de curseur (compile, recompile si Hyprland change, charge). Aucun `hyprpm`, aucun `cmake`, aucun droit root.
- **Boutons** (de gauche à droite) : rouge = fermer, jaune = ranger dans le scratchpad de Lucid, vert = plein écran.
- **Piège 1** : `require("modules.specials").stash()` **renvoie une fonction** (les raccourcis de Lucid l'appellent à
  chaque pression) ; il faut `stash()()`. Avec une seule paire de parenthèses le bouton ne fait rien, et `hyprctl`
  répond quand même `ok`.
- **Piège 2, erreur de procédure** : un test « de bouton » lancé sans vérifier que la fenêtre de test existait encore a
  visé la fenêtre active (celle d'un utilisateur). Les tests d'actions se font désormais avec un **garde-fou** : avant
  chaque action, on vérifie que la fenêtre active est bien la fenêtre de test, sinon on abandonne sans rien lancer.
- **Au clic**, hyprbars donne d'abord le focus à la fenêtre cliquée puis exécute l'action : « fermer » vise toujours la
  bonne fenêtre.
- **Sauvegarde avant essai** : archive de `~/.config/hypr`, des préférences de Lucid et des plugins, snapshots Btrfs,
  et un script de rollback qui décharge le plugin, supprime les fichiers et restaure la configuration.
- **Activation** : `HYPRBARS="yes"` dans `config.env`, ou `./install.sh --only hyprbars`.

## 16. Bilan

Une configuration complète (système, sécurité, shell, applications, bureau, démarrage) est reproductible par un script
modulaire, idempotent, en `--dry-run`, testé de bout en bout sur une installation CachyOS réelle. Les deux principales
leçons de méthode :

1. **Revalider à froid** : un correctif qui marche « à chaud » peut échouer au démarrage (cas de `sshd`, §13).
2. **Lire l'état réel, pas seulement le journal** : le processus affichait `sshd (complain)` alors que le fichier voulu
   était `enforce` ; la comparaison entre le fichier et ce que le noyau a chargé a levé le doute.

**Pistes restantes** : GRUB/Limine à tester, une installation Arch « nue », sauvegarde externe (les snapshots sont sur
le même disque), chiffrement du disque et Secure Boot (`sbctl`), profils AppArmor pour d'autres services, mise en
conformité de la machine de référence avec les deux correctifs du profil `sshd`.

## 17. Crash de Quickshell à l'ouverture d'une application (bogue connu en amont)

À l'ouverture de Discord depuis le lanceur, le shell de Lucid a planté (`SIGABRT`) puis a été relancé par le
gestionnaire de crash de Quickshell. Analyse (coredump, rapport de Quickshell, trace `strace`) :

- **Cause immédiate** : appel de fonction purement virtuelle dans `QPlatformPixmap::fromFile`, appelé par `QIcon::pixmap`
  depuis le fil de chargement d'images de Qt (`QQuickPixmapReader`).
- **Cause profonde** : le fournisseur d'icônes de Quickshell appelle `QIcon::pixmap()` hors du fil principal quand un
  `Image` QML est en `asynchronous: true` ; `QPlatformPixmap` n'est pas prévu pour cela. **Bogue déjà signalé en amont**
  (quickshell-mirror/quickshell : #1028, #979, #974 fermée comme « upstream », #1079 variante dans le fil principal).
- **Déclencheur dans Lucid** : `lucidbar/ActiveWindow.qml` charge l'icône de la fenêtre active en `asynchronous: true`.
  Intermittent : le second lancement de Discord, sous trace, n'a rien produit. Qt 6.12.0 + Quickshell 0.3.2.
- **Effet secondaire** : après la relance, les processus enfants de l'ancienne instance (`pactl subscribe`,
  `nmcli monitor`, `wl-paste --watch cliphist store`...) restent en doublon à côté des nouveaux. Ils se terminent par
  `kill` mais n'étant pas « récoltés » par leur parent ils restent zombies jusqu'à la prochaine session.
- **Contournement local, non testé** : `asynchronous: false` dans `ActiveWindow.qml` (à refaire après chaque
  réinstallation de Lucid). Les brouillons de rapports (commentaire sur la fiche existante, fiche « enfants orphelins »,
  fiche pour l'auteur de Lucid) ont été rédigés mais pas publiés.

**Pièges d'interprétation à ne pas refaire** (une conclusion fausse a été tirée puis corrigée) :

1. Après un crash, Quickshell se relance **sur place** : **même PID, même date de démarrage dans `ps`**. « Le PID n'a pas
   changé » ne prouve donc pas que le shell n'a pas planté. Les dates de création des fils (`/proc/<pid>/task/*/stat`) et
   des processus enfants, elles, le montrent.
2. Dans un coredump, le « PID parent » (`pr_ppid`) est l'identifiant du **fil** qui a créé le processus, pas du processus.
   Le « processus planté » n'est ici qu'un instantané à un seul fil, créé par le gestionnaire de crash.
3. `ausearch` lit son entrée standard quand elle est un tube (voir §13) ; `pacman -Rns` refuse `--print` (simulation :
   `pacman -Rs --print`, sans `-n`).

## 18. Réglages du lendemain : échelle, espaces de travail, plugins, langue, shaders

- **Steam « pixélisé »** : Steam est un client XWayland et les écrans sont à l'échelle fractionnaire 1,25 ; le compositeur
  agrandit donc la fenêtre X11. `xwayland:use_nearest_neighbor` vaut `true` par défaut, ce qui donne un rendu
  **pixélisé** (la description de l'option le dit). Passé à `false` (lissage bilinéaire) via `files/hypr/xwayland.lua`
  (option `XWAYLAND_SMOOTH`). Alternative plus nette, non appliquée : `xwayland:force_zero_scaling = true` (c'est bien ce
  nom en 0.56, pas `force_zero_scale`) avec `STEAM_FORCE_DESKTOPUI_SCALING=1.25` ; elle demande de rouvrir la session et
  rend les autres applications X11 plus petites.
- **« Le workspace de DP-3 est le 7 »** : par défaut Lucid est en mode **partagé** (un espace s'ouvre là où l'on est) :
  les espaces 1 à 6 sont nés sur le premier écran et le 7 sur le second. Lucid a un mode **séparé** (chaque espace
  appartient à un écran) : préférence `monitorWorkspaces` = `{"mode":"split","assign":{"1":<écran>,...}}` dans
  `~/.config/quickshell/lucidprefs/prefs.json`. Lucid **surveille ce fichier** : il régénère seul `lucid-monitors.lua`
  et recharge Hyprland. Choix fait : 1 à 5 sur l'écran principal, 6 à 10 sur l'autre. Un écran garde l'espace qu'il
  affichait : il faut le faire passer sur le nouveau (`hl.dsp.focus({ workspace = 1 })`).
- **Un plugin perdu au démarrage** (corrigé) : `hyprbars-plugin.sh` et `cursor-plugin.sh` de Lucid partageaient le même
  fichier de verrou ; lancés en même temps au démarrage, le second **quittait sans rien dire** et son plugin n'était pas
  chargé (ici le plugin de curseur). Chaque script a maintenant son verrou. Piège plus général : un verrou partagé avec
  `flock -n ... || exit 0` transforme une collision en échec silencieux.
- **Langue de Lucid** : aucune traduction (pas de `qsTr`, pas de fichiers `.qm`) ; seules les dates suivent la locale
  et l'OCR a sa langue. Le menu est en anglais, sans option.
- **Shaders très longs (CS2, Tiny Glade)** : une première hypothèse (priorité trop basse) a été **réfutée par la mesure**.
  `ananicy-cpp` classe bien `steam` en « Launcher » (`nice 16`, E/S `idle`, hérités par les sous-processus), mais un
  enregistreur (priorités, %CPU, disque, GPU, toutes les 3 s) a montré, pendant le rejeu de CS2 : **32 processus
  `fossilize_replay` (un par thread) à 100 % d'un cœur chacun, 97 % du CPU au total**, disque quasi inactif (0-10 Mo/s),
  GPU à 0 % d'utilisation (la VRAM, ~5,6 Go, sert aux contextes Vulkan). La priorité ne gêne donc rien : aucune
  concurrence sur les cœurs. Le temps est celui de la charge : Steam rejoue un cache de pipelines Vulkan d'environ
  **1,7 million de pipelines** pour CS2 (visible dans son journal : `Still replaying 730 (7%, 113554/1579462)`), à
  ~650 pipelines/s sur un Ryzen 9 9950X3D, soit **environ 40 minutes** au premier lancement. Le GPU n'y participe pas :
  **les pilotes NVIDIA compilent les pipelines sur le CPU, par conception**.
  Conséquences : (1) laisser terminer une fois, le résultat est gardé dans le cache du pilote (le journal de Steam avait
  noté un premier rejeu « killed » au bout de 3 minutes) ; (2) **toute mise à jour du pilote NVIDIA invalide ce cache** :
  la compilation est à refaire (rolling release : régulier) ; (3) mesurer plutôt que supposer : l'ananicy n'était pas en
  cause. Méthode : un échantillonneur (/proc, `nvidia-smi`) lancé pendant que l'utilisateur démarre le jeu.

## 19. Audit du rendu des applications (XWayland ou Wayland) et technique de test

L'audit complet des applications installées est dans `PROBLEMES-CONNUS.md` §1 : 11 applications en Wayland natif, 2 en
XWayland (OnlyOffice, VLC) plus Steam et les jeux. Pour CS2, la résolution vidéo du jeu (3072×1728) est la taille logique
d'un écran 4K à l'échelle 1,25 : le jeu est agrandi par Hyprland.

**Technique** (réutilisable) : lancer une application sur un espace spécial caché pour l'inspecter sans déranger l'écran.
- La forme qui fonctionne : `hl.dsp.exec_cmd("cmd", { workspace = "special:audit silent" })`. L'option `silent = true`
  est refusée (`unknown effect 'silent'`) ; sans `silent`, l'espace spécial s'affiche et prend le focus un instant.
- Lire `hyprctl clients -j` (`xwayland`, `class`, `pid`), puis fermer en envoyant `SIGTERM` au processus **et à ses
  descendants** (`pgrep -P` récursif), jamais à une instance déjà ouverte avant le test.
- Des exceptions : Lucid assigne Discord à `special:comms`, et VS Code (lanceur qui se détache) s'ouvre sur l'espace
  courant malgré la règle.
- Piège : `pkill -f motif` lancé par SSH peut se tuer lui-même (la ligne de commande de la session contient le motif) ;
  utiliser `pkill -f '[m]otif'`.

## 20. Réglages de latence de jeu

> Résultat des mesures et désactivation : voir §21 et `PROBLEMES-CONNUS.md` §6.

Module `files/hypr/gaming.lua` (option `GAMING_LATENCY`, chargé après `input.lua`) : tearing autorisé, scanout direct
automatique, règle `cs2` (`immediate` + plein écran), souris en profil plat. Constat utile : Hyprland 0.56 expose
`activelyTearing`, `tearingBlockedBy` et `directScanoutBlockedBy` dans `hyprctl monitors -j`, ce qui permet de **vérifier**
plutôt que supposer. Limite : écran à l'échelle 1,25 + client XWayland empêche a priori le scanout direct (voir
`PROBLEMES-CONNUS.md` §6). Une souris plate n'agit que sur le bureau (les jeux utilisent le pointeur relatif brut).

## 21. Latence testée, retour arrière de hyprbars, plantage de Hyprland et restructuration du dépôt (16/10/2026)

**Tearing mesuré.** CS2 en plein écran (XWayland, 3072×1728 agrandi à l'échelle 1,25) : `activelyTearing = False` sur les deux
écrans, scanout direct bloqué. Détail et limites de l'interprétation : `PROBLEMES-CONNUS.md` §6.

**Test en jeu.** Avec `gaming.lua` actif la vue ne tournait plus en partie (la souris fonctionnait dans les menus). Le module a
été commenté dans `hyprland.lua` (copie : `~/backups/hyprland.lua.avant-desactivation-gaming`), `hyprctl reload`, et la vue a
de nouveau tourné. Cause non isolée (test non contrôlé). Décision : `GAMING_LATENCY` reste **désactivé**.

**Retour arrière de hyprbars (billes macOS).** Le script de retour arrière écrit le 15/10 restaurait toute la sauvegarde de
`~/.config/hypr`, ce qui aurait aussi annulé les réglages faits depuis (lissage XWayland, espaces de travail répartis) : il n'a
**pas** été lancé. À la place : retrait ciblé (ligne `require`, module Lua, script de chargement, `.so`), fichiers rangés dans
`~/backups/hyprbars-module/` pour pouvoir y revenir. Le module reste dans le dépôt, facultatif.

**Incident.** Le plugin avait été déchargé à chaud ; Hyprland a ensuite planté (SEGV), relancé en mode sans échec, session et
applications perdues. Récupération : vérification de la config (`Hyprland --verify-config`), arrêt de l'unité
`wayland-wm@hyprland.desktop.service`, nouvelle connexion par SDDM. Leçon : **pas de déchargement de plugin à chaud**
(`PROBLEMES-CONNUS.md` §7). `hyprctl dispatch exit` ne fonctionne plus en Lua (`hl.dsp.exit()` n'a pas suffi non plus en mode
sans échec).

**Restructuration du dépôt.**
- Nouveau module **`tweaks`** : les réglages de la config Hyprland (clavier, curseur, XWayland, latence) sortent de `desktop`,
  qui ne fait plus que Hyprland + Lucid + SDDM. On peut donc rejouer un réglage sans réinstaller Lucid.
- Règle de cohérence : tout ce qui touche à l'interface (`tweaks`, `hyprbars`, variables NVIDIA de `hardware`) passe par
  `need_hypr_config` et **ne fait rien si le bureau n'est pas installé**.
- Défaut corrigé : `hypr_require` considérait comme chargé un `require` **commenté** (`-- require(...)`) ; il ne regarde plus que
  les lignes actives. Ajout de `hypr_unrequire` et `hypr_session_env` (retrouve la session Hyprland depuis SSH).
- `install.sh` : tableau des modules (`--list` affiche rôle et « interface »), un nom inconnu dans `--only/--skip` est refusé.
- `HYPRBARS="remove"` retire le module sans décharger le plugin.
- `tests/check.sh` : syntaxe, shellcheck, liste des modules, tests des helpers sur une configuration jetable.

**Alignement de Maverick et fin du `sudo` sans mot de passe (16/10/2026).** Le dépôt a été cloné sur Maverick (le portable) avec
un `config.env` local qui reflète son état réel (mot de passe SSH déjà coupé, AppArmor en `enforce`) : sans lui, le module
`security` aurait réécrit `10-hardening.conf` sans `PasswordAuthentication no`. Seuls deux écarts existaient : le profil
AppArmor `sshd` corrigé (`attach_disconnected`) et le lissage XWayland. Appliqués avec `--only tweaks,security` après un
`--dry-run`. Le fichier `/etc/sudoers.d/10-nopasswd` posé pendant l'installation a ensuite été supprimé sur les **deux**
machines (le `sudo` demande de nouveau un mot de passe). Conséquence : les modules qui utilisent `sudo` ne se lancent plus
sans terminal interactif ; à partir de maintenant ils se lancent depuis une session où l'utilisateur saisit son mot de passe.

## 22. Audit complet de la machine de référence (16/10/2026) et correctifs

Audit en lecture seule : aucune unité en échec, SSD sain (SMART OK, 1 % d'usure), pile de sécurité active (79 profils AppArmor en
`enforce`, aucun bannissement), bureau sans doublon de processus. Points traités :

- **`NetworkManager-wait-online` (15,6 s dans `systemd-analyze blame`)** : **hors du chemin critique** (`graphical.target` est atteint
  à 3,4 s). Il ne retarde que les unités qui attendent `network-online.target` (montages réseau, `fwupd-refresh`). Aucun changement.
- **Erreurs CIFS du noyau** (« Close interrupted / unmatched open ») avec des partages montés à la demande (`x-systemd.automount`) :
  tous les partages sont montés en rafale, puis démontés au bout de 60 s d'inactivité pendant que des fichiers sont ouverts
  (lecture vidéo, gestionnaire de fichiers). Corrigé en passant `x-systemd.idle-timeout` de 60 à 600. Réglage propre à la machine,
  donc **non porté dans le script**.
- **Fichiers `.pacnew`** (`pacman.conf`, listes de miroirs, `resolv.conf`) : la config en place était plus riche (Color,
  ILoveCandy, dépôts CachyOS v4) ; seul `CheckSpace` a été repris (ajouté au module `base`), les `.pacnew` supprimés après copie dans
  `/var/backups/arch-proart-install/`.
- **Paquet orphelin `electron`** : **ne pas le retirer**. Proton Pass tourne avec `/usr/lib/electron44/electron` sans le déclarer
  comme dépendance (`electron44` n'est « requis » que par le méta-paquet `electron`). Marqué comme installé volontairement
  (`pacman -D --asexplicit electron`). VS Code utilise `electron42`, Obsidian et Proton Mail `electron43`.
- **Mises à jour** (10 paquets : firefox, freetype2, glycin, xorg-server...) appliquées avec un snapshot avant/après (52 / 53). Pas
  de noyau ni de pilote NVIDIA : le cache de shaders reste valide.
- **Les plantages Electron/OnlyOffice de 09:00** sont ceux de l'audit du §19 (applications lancées puis fermées par `SIGTERM`), pas
  des bogues ; le second SEGV de Hyprland (09:44) est l'instance en mode sans échec, cf. §21.
- **À surveiller** : Quickshell occupe 2,6 Go de mémoire après 4,2 h de session (fuite possible, non confirmée).

## 23. Mémoire de Quickshell : mesures (16/10/2026)

Hier : 2,6 Go après 4,2 h de session (précédée d'un plantage et d'un redémarrage sur place). Mesures du jour, session propre :
- **Au repos** : 650 → 708 Mo dans les 90 premières secondes (démarrage), puis plat (704 à 714 Mo) pendant 10 min ; 6 fenêtres, processus
  enfants stables (107 Mo). Pas de fuite continue à l'inactivité.
- **Ouvrir et fermer 20 fois une fenêtre** (kitty sur un espace spécial caché) : +4 Mo au total, plateau dès le 5e cycle. Le cycle de vie
  d'une fenêtre n'est donc pas la cause. Limite du test : fenêtres jamais focalisées, donc ni icône de fenêtre active ni aperçu.
- **Usage normal** (Nautilus, lecture d'un film, Firefox) : 709 → 765 Mo en 18 min, puis plat. Hausse modérée, sans lien établi.
- **Pistes restantes** (non testées) : aperçus de fenêtres (`ScreencopyView` dans `Workspaces.qml`, `StackPopup.qml`, `Switcher.qml`),
  chargements d'icônes de la fenêtre active, fonds d'écran animés, miniatures du presse-papiers. Les 2,6 Go d'hier restent inexpliqués.
- Méthode : échantillonneur lisant `/proc/<pid>/smaps_rollup` toutes les 30 s ; test détaché (`setsid nohup`) avec PID fourni par
  `hyprctl clients -j` (jamais `pkill -f` sur un motif présent dans sa propre ligne de commande). Piège : plusieurs copies du script
  lancées en parallèle se ferment mutuellement leurs fenêtres de test.

## 24. État en fin de séance (16/10/2026) et suite

**Machines.** ProArt (CachyOS, Ryzen 9 9950X3D, RTX 5080) est la machine de travail ; Maverick (portable) est alignée sur le dépôt (`tweaks`,
`security`). Le dépôt se pousse depuis ProArt en SSH avec une clé de déploiement (empreinte de GitHub vérifiée contre `api.github.com/meta`).
`sudo` : le fichier `10-nopasswd` a été supprimé le 16/10, puis est réapparu sur ProArt après un redémarrage (remis par l'utilisateur, non
vérifié). Piste évoquée, non faite : délai `timestamp_timeout=60` + `log_output`, ou un programme racine à actions fixes (`proart-admin`).

**Fait aujourd'hui** : lissage XWayland, latence de jeu mesurée puis désactivée (§21), hyprbars retiré (§21), restructuration du dépôt et tests,
audit complet (§22), mpv à la place de VLC (HDR, `PROBLEMES-CONNUS.md` §8), Selawik pour Segoe UI (§9), `copy_on_select clipboard` dans kitty
(`~/.config/kitty/kitty.conf`, à refaire si Lucid réécrit ce fichier), mémoire de Quickshell mesurée (§23).

**Nettoyage de fin de séance** : processus de mesure arrêtés, fichiers temporaires supprimés, cache de pacman allégé (paquets désinstallés et
dossiers de téléchargement interrompus retirés), aucun orphelin, aucune unité en échec. Les sauvegardes (`~/backups/`, `/var/backups/arch-proart-install/`)
sont conservées.

**Pour la suite** :
1. Suivi passif de la mémoire de Quickshell sur une journée entière (service utilisateur, un relevé toutes les 5 min) ; piste : aperçus de fenêtres.
2. CS2 : essayer le rendu 3840×2160 natif (`xwayland:force_zero_scaling`) pour savoir si le tearing s'active ; réessayer la latence un réglage à la fois.
3. Écran : chercher une option HDR dans le menu des Dell U2718Q ; le vrai HDR suppose que l'écran l'annonce, puis le mode expérimental de Hyprland.
4. `sudo` : décider entre sans mot de passe, délai d'une heure journalisé, ou programme à actions fixes.
5. Mémoire de Quickshell et crash d'icônes : contournement `asynchronous: false` dans `ActiveWindow.qml`, non testé. Rapports amont non publiés (décision de l'utilisateur).
6. Compiler un jour la liste des bogues d'interface restants avec l'utilisateur (aucun nouveau signalé ce jour).


## 25. Coins de Lucid Settings verrouillés : ordre de chargement des modules Hyprland (16/10/2026)

Cause trouvée par le fichier d'état de Lucid (`lucid-settings-status.json`, clé `overridden`) puis dans l'installeur de Lucid : il ajoute
`lucid-look` en fin de `hyprland.lua`, après `settings`. Correction par `hypr_require_before` (module `tweaks`, test dans `tests/check.sh`),
sauvegarde `~/backups/hyprland.lua.avant-ordre-lucid-look`. Règle à retenir : **dans `hyprland.lua`, le dernier module chargé gagne** ; tout ce que
Lucid Settings pilote (Windows, Input) doit venir après les modules qui posent des valeurs par défaut. Voir `PROBLEMES-CONNUS.md` §10.

## 26. Minecraft Java (17/10/2026)

Installé via **Prism Launcher** (dépôt `extra`) plutôt que le lanceur officiel (absent des dépôts et de l'AUR consultée) : plusieurs instances et versions,
mods, Java choisi par instance. Java 21 (par défaut du système) et Java 25 installés pour les versions récentes. La connexion se fait dans le lanceur avec
le compte Microsoft de l'utilisateur ; aucun compte n'est stocké par le script. Intégré au module `apps`. Pistes si le rendu paraît flou à l'échelle 1,25 :
dans Prism, *Paramètres > Minecraft > Ajustements* : « GLFW natif » (Wayland natif) ; le lissage XWayland du §18 s'applique sinon.
