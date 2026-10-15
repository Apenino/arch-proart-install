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
./install.sh --list                  # liste des modules
./install.sh --only security,boot    # seulement ces modules
./install.sh --skip apps,desktop     # tout sauf ceux-là
```

## Modules (dans l'ordre d'exécution)

| Module | Ce qu'il fait |
|---|---|
| `base` | `pacman.conf` (Color, téléchargements parallèles, multilib), mise à jour, assistant AUR (`paru`, sinon `yay`) |
| `system` | Btrfs (COW + checksums + `noatime` + zstd), snapshots **snapper** sur sous-volumes dédiés + `snap-pac`, `fstrim`, scrub mensuel, `paccache`, `fwupd`, `reflector` (Arch), profils d'énergie + `thermald` sur portable, nom d'hôte, masquage des unités TPM NvPCR en échec |
| `security` | `sshd` durci, pare-feu `ufw` (SSH depuis le réseau local seulement), `fail2ban`, `auditd`, AppArmor (profil `sshd`), sysctl, LLMNR/mDNS coupés |
| `shell` | zsh + oh-my-zsh + powerlevel10k + autosuggestions/syntax-highlighting, kitty (thème sombre, trainée du curseur) |
| `apps` | Firefox, Steam (+ Vulkan 32 bits selon le GPU), Blender, Discord, VLC, Obsidian, VS Code (Code-OSS), Proton VPN / Pass / Mail, OnlyOffice |
| `desktop` | Hyprland + [Lucid](https://github.com/Sn3akyy1/lucid) (version **épinglée et vérifiée par commit**), SDDM avec le thème Lucid, clavier du système, curseur sans rotation, nettoyage sûr des paquets inutiles |
| `hardware` | microcode CPU ; **pilote NVIDIA open** (RTX 50 : indispensable), paramètres noyau `nvidia-drm`, chargement précoce des modules, variables d'environnement Hyprland |
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

## Choix de sécurité à connaître

- **SSH** : root interdit, `AllowUsers` limité à ton compte, 3 essais maximum. Le mot de passe n'est coupé
  que si tu le demandes **et** qu'une clé est déjà en place.
- **Pare-feu** : tout le trafic entrant est refusé, sauf SSH depuis ton réseau local.
- **AppArmor** : le profil `sshd` est en mode `complain` par défaut (il journalise sans bloquer). Après une
  connexion SSH réussie, passe `APPARMOR_MODE="enforce"` et relance `./install.sh --only security`.
  Les shells et commandes lancés après connexion ne sont **pas** confinés.
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

Testé sur **Arch Linux + systemd-boot (images UKI) + Btrfs**, sur un portable Intel (Dell). Le module `hardware` (NVIDIA) est vérifié par tests unitaires et simulation de GPU, **pas sur la vraie carte**. Les modules ont été
validés en `--dry-run` (idempotence) et à la main. Une installation CachyOS a été **inspectée en lecture seule** (bootloader `sdboot-manage`, Plymouth, NVIDIA, Btrfs) et
le script corrigé en conséquence (voir `docs/HISTORIQUE.md`, §11), mais **il n'a pas encore été exécuté de bout
en bout dessus** : lance d'abord `./install.sh --dry-run` et relis ce qui est affiché.

## Historique et décisions

Tout ce qui a été fait sur la machine de référence, les pièges rencontrés et ce qui reste à faire :
**[docs/HISTORIQUE.md](docs/HISTORIQUE.md)**. La fiche de la machine cible : **[docs/MATERIEL.md](docs/MATERIEL.md)**.

## Structure

```
install.sh              point d'entrée (options, config, enchaînement des modules)
config.env.example      options personnalisables (copier en config.env)
lib/common.sh           journalisation, --dry-run, détection matériel/bootloader, helpers paquets et fichiers
modules/                base, system, security, shell, apps, desktop, boot
files/                  fichiers installés tels quels (sysctl, règles audit, profil AppArmor, thème Plymouth)
docs/HISTORIQUE.md     historique complet, décisions, pièges, pistes
docs/MATERIEL.md       fiche matérielle de la machine cible
dotfiles/
├── kitty/kitty.conf    config kitty
└── zsh/
    ├── .zshrc          config zsh / oh-my-zsh
    └── .p10k.zsh       config du prompt Powerlevel10k (refaire avec `p10k configure`)
```
