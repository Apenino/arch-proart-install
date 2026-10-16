# arch-proart-install

Script post-installation pour Arch Linux et dérivés (CachyOS...), pensé pour un ASUS ProArt (PC de bureau, Ryzen 9 9950X3D, RTX 5080 — voir [docs/MATERIEL.md](docs/MATERIEL.md)).
Il configure la machine de bout en bout : système, sécurité, shell, applications, bureau et démarrage.

> **Pas de gestion de CachyOS ici** : le noyau, les dépôts et les optimisations CachyOS viennent de
> l'installation depuis l'ISO CachyOS. Le script détecte ce qui existe déjà (bootloader, Btrfs, snapper,
> firewall...) et n'écrase pas un réglage déjà en place.

## Utilisation

```bash
git clone https://github.com/Apenino/arch-proart-install.git
cd arch-proart-install
cp config.env.example config.env     # facultatif : adapter les options
./install.sh --dry-run               # voir ce qui serait fait, sans rien modifier
./install.sh                         # tout installer
```

À lancer en **utilisateur normal** (pas en root) : `sudo` est demandé quand c'est nécessaire.
Le script peut être relancé sans risque : les fichiers déjà conformes sont laissés tels quels et les
fichiers remplacés sont sauvegardés en `*.bak.<date>`.

```
./install.sh --list                  # modules, rôle, et s'ils touchent à l'interface
./install.sh --only security,boot    # seulement ces modules (chacun se rejoue seul)
./install.sh --skip apps,desktop     # tout sauf ceux-là
```

Les modules marqués « interface » ne modifient le bureau que s'il est installé (module `desktop` déjà lancé) ; sinon
ils s'ignorent et le disent. `./tests/check.sh` vérifie la syntaxe, shellcheck et les helpers (sans toucher à la machine).

## Modules (dans l'ordre d'exécution)

| Module | Ce qu'il fait |
|---|---|
| `base` | `pacman.conf` (Color, téléchargements parallèles, multilib), mise à jour, assistant AUR (`paru`, sinon `yay`) |
| `system` | Btrfs (COW + checksums + `noatime` + zstd), snapshots **snapper** sur sous-volumes dédiés + `snap-pac`, `fstrim`, scrub mensuel, `paccache`, `fwupd`, `reflector` (Arch), profils d'énergie + `thermald` sur portable, nom d'hôte, masquage des unités TPM NvPCR en échec |
| `security` | `sshd` durci, pare-feu `ufw` (SSH depuis le réseau local seulement), `fail2ban`, `auditd`, AppArmor (profil `sshd`), sysctl, LLMNR/mDNS coupés |
| `shell` | zsh + oh-my-zsh (thème `robbyrussell`) + plugins système autosuggestions et syntax-highlighting ; le prompt **starship** et kitty viennent de Lucid |
| `apps` | Firefox, Steam (+ Vulkan 32 bits selon le GPU), Blender, Discord, VLC, Obsidian, VS Code (Code-OSS), Proton VPN / Pass / Mail, OnlyOffice |
| `desktop` | Hyprland + [Lucid](https://github.com/Sn3akyy1/lucid) avec son look complet (starship, kitty) — version **épinglée et vérifiée par commit** —, SDDM avec le thème Lucid, nettoyage sûr des paquets inutiles |
| `tweaks` | *(interface)* réglages de la config Hyprland, rejouables sans réinstaller Lucid : clavier du système, curseur sans rotation, XWayland lissé, latence de jeu (facultative, désactivée) |
| `hardware` | *(interface en partie)* microcode CPU ; **pilote NVIDIA open** (RTX 50 : indispensable), paramètres noyau `nvidia-drm`, chargement précoce des modules, variables d'environnement Hyprland |
| `hyprbars` | *(interface)* **facultatif** (`HYPRBARS="yes"` ou `--only hyprbars`, `"remove"` pour retirer) : barres de titre façon macOS (pastilles rouge = fermer, jaune = ranger dans le scratchpad de Lucid, verte = plein écran) via le plugin `hyprbars`, compilé pour ta version de Hyprland |
| `boot` | Démarrage silencieux avec le logo Arch (Plymouth), menu du bootloader masqué |

## Configuration (`config.env`)

Tout est optionnel, voir `config.env.example`. `config.env` est ignoré par git : **aucun secret ni
adresse personnelle n'est dans le dépôt**.

| Variable | Rôle |
|---|---|
| `HOSTNAME_NEW` | nom d'hôte |
| `LAN_CIDR` | sous-réseau autorisé pour SSH (détecté automatiquement si vide) |
| `SSH_GITHUB_USER` | importe les clés publiques de ce compte GitHub dans `authorized_keys` |
| `SSH_DISABLE_PASSWORD` | `yes` coupe le mot de passe SSH (ignoré si `authorized_keys` est vide) |
| `FAIL2BAN_IGNORE` | IP jamais bannies |
| `APPARMOR_MODE` | `complain` (par défaut) ou `enforce` pour le profil `sshd` |
| `BOOT_SPLASH` / `BOOT_HIDE_MENU` | démarrage silencieux / menu masqué |
| `PRUNE` | nettoyage des paquets inutiles installés avec Lucid |
| `KB_LAYOUT` | clavier Hyprland (sinon celui du système) |
| `PLYMOUTH_THEME` | `arch-logo` (logo Arch, par défaut) ou `keep` pour garder le thème de la distribution |
| `XWAYLAND_SMOOTH` | `yes` (défaut) lisse XWayland (Steam...) au lieu de le pixéliser à l'échelle fractionnaire |
| `GAMING_LATENCY` | `yes` active les réglages de latence de jeu — **déconseillé** pour l'instant, gain non démontré (`docs/PROBLEMES-CONNUS.md` §6) |
| `HYPRBARS` | `yes` active le module facultatif hyprbars, `remove` le retire (rouvrir ensuite la session) |
| `AUR_REVIEW` | `no` installe les paquets AUR sans afficher le `PKGBUILD` (lancement non interactif) ; garde `yes` par défaut |
| `LUCID_INSTALL_FLAGS` | options de l'installeur de Lucid (ex. `-y --no-apps --no-hypr --no-wallpapers --no-plugins` sur une machine déjà réglée) |
| `LUCID_REF` / `LUCID_COMMIT` | commit de Lucid épinglé (le hash est vérifié après le clonage) |
| `EXTRA_PACKAGES` | paquets supplémentaires des dépôts (ex. `solaar`) |

## Choix de sécurité à connaître

- **SSH** : root interdit, `AllowUsers` limité à ton compte, 3 essais maximum. Le mot de passe n'est coupé
  que si tu le demandes **et** qu'une clé est déjà en place.
- **Pare-feu** : tout le trafic entrant est refusé, sauf SSH depuis ton réseau local.
- **AppArmor** : le profil `sshd` est en mode `complain` par défaut (il journalise sans bloquer). Après une
  connexion SSH réussie, passe `APPARMOR_MODE="enforce"` et relance `./install.sh --only security`.
  Les shells et commandes lancés après connexion ne sont **pas** confinés. Le profil porte `attach_disconnected` :
  sur le noyau CachyOS, sans lui, `sshd` ne peut pas signaler « prêt » à systemd et reste en `activating`.
- **Sauvegardes** : les fichiers remplacés sont copiés dans `/var/backups/arch-proart-install/` (jamais à côté de
  l'original : certains dossiers, comme `/etc/apparmor.d/`, sont lus en entier par leur service).
- **`sudo` sans mot de passe** : le script n'y touche pas.
- **Démarrage** : sans menu visible, maintiens la **barre d'espace** au démarrage pour l'afficher (noyau de
  secours). Les paramètres noyau sont gérés pour **systemd-boot** et **GRUB** ; avec un autre bootloader
  (Limine...), le script affiche les paramètres à ajouter à la main.
- **Applications AUR** (Proton Mail...) : ton assistant AUR te montre le `PKGBUILD` pour relecture avant
  de compiler. Celui de `proton-mail-bin` 1.15.1 télécharge le `.deb` depuis `proton.me` avec sommes de
  contrôle et n'a pas de script d'installation.
- **Lucid** est cloné sur un **commit précis** (`3d6ed3b…`, version 1.20.1 + un correctif relu), vérifié avant de
  lancer son installeur. On épingle le hash et non le tag, car l'auteur peut déplacer un tag. Pour monter de version,
  relis le diff puis change `LUCID_REF` et `LUCID_COMMIT`.

## État des tests

**Exécuté de bout en bout** sur la machine cible : **CachyOS + systemd-boot + Btrfs + NVIDIA RTX 5080** (PC de bureau,
Ryzen 9 9950X3D). Le premier lancement réel a révélé quatre défauts, tous corrigés (voir `docs/HISTORIQUE.md`,
§12 et §13), puis deux redémarrages à froid ont validé le résultat (`sshd` confiné en `enforce`, pilote NVIDIA,
SDDM + Lucid, démarrage silencieux, aucune unité en échec). Les modules ont aussi été validés en `--dry-run`
(idempotence) sur une seconde machine, **Arch Linux + systemd-boot (UKI) + Btrfs** sur un portable Intel.

Depuis la restructuration (module `tweaks`, helpers Hyprland), les modules concernés ont été validés en `--dry-run` sur la
machine cible avec sa vraie configuration (aucun fichier modifié) et par `tests/check.sh`. Les réglages de latence de jeu et
le module `hyprbars` ont été essayés puis retirés de la machine de référence (voir `docs/PROBLEMES-CONNUS.md` §6 et §7).

**Non testé** : GRUB et Limine (les paramètres noyau sont gérés pour GRUB mais n'ont pas été exécutés ; Limine
affiche les paramètres à ajouter à la main), une installation Arch « nue » (hors CachyOS), un GPU AMD ou Intel sur
une installation fraîche, le chiffrement LUKS. Lance toujours `./install.sh --dry-run` d'abord et relis la sortie.

## Dépannage

| Symptôme | Cause connue | Voir |
|---|---|---|
| `sshd` en `activating`, relancé en boucle après un redémarrage | profil AppArmor sans `attach_disconnected`, ou anciennes sauvegardes dans `/etc/apparmor.d/` | HISTORIQUE §13 |
| Le script s'arrête sur « Commit Lucid inattendu » | l'auteur a déplacé un tag : relire le diff puis changer `LUCID_REF`/`LUCID_COMMIT` | HISTORIQUE §12 |
| Paramètres noyau sans effet sous CachyOS | les entrées viennent de `sdboot-manage` (`LINUX_OPTIONS`), pas de `/etc/kernel/cmdline` | HISTORIQUE §11 |
| Quickshell plante à l'ouverture d'une application | bogue connu d'icônes asynchrones (Qt 6.12 + Quickshell 0.3.2) | HISTORIQUE §17 |
| Steam et les applications X11 sont pixélisés | échelle fractionnaire + filtrage XWayland par défaut (`XWAYLAND_SMOOTH`) | HISTORIQUE §18 |
| Plus aucune fenêtre ni Lucid après un plantage, processus `Hyprland --safe-mode` | plugin déchargé à chaud : ne jamais le faire ; `systemctl --user stop wayland-wm@hyprland.desktop.service` puis reconnexion | HISTORIQUE §21 |
| Les écrans sont inversés dans Lucid | placement « auto » par ordre de connecteur | HISTORIQUE §14 |

## Historique et décisions

Tout ce qui a été fait sur la machine de référence, les pièges rencontrés et ce qui reste à faire :
**[docs/HISTORIQUE.md](docs/HISTORIQUE.md)**. La fiche de la machine cible : **[docs/MATERIEL.md](docs/MATERIEL.md)**.
Ce qui reste à corriger (rendu XWayland, CS2, etc.) : **[docs/PROBLEMES-CONNUS.md](docs/PROBLEMES-CONNUS.md)**.

## Structure

```
install.sh              point d'entrée (options, config, enchaînement des modules)
config.env.example      options personnalisables (copier en config.env)
lib/common.sh           journalisation, --dry-run, détection matériel/bootloader, helpers paquets et fichiers
modules/                base, system, security, shell, apps, desktop, tweaks, hardware, hyprbars (facultatif), boot
tests/check.sh          contrôles sans effet : syntaxe, shellcheck, modules, helpers Hyprland
files/                  fichiers installés tels quels (sysctl, règles audit, profil AppArmor, thème Plymouth, hyprbars)
docs/HISTORIQUE.md     historique complet, décisions, pièges, pistes
docs/MATERIEL.md       fiche matérielle de la machine cible
docs/PROBLEMES-CONNUS.md  problèmes constatés, causes, état (à corriger / à re-tester / en amont)
dotfiles/zsh/.zshrc    config zsh / oh-my-zsh (starship est ajouté par Lucid)
```
