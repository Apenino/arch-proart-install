# Journal des changements

Format libre, version la plus récente en haut. Le détail des décisions et des mesures est dans `docs/HISTORIQUE.md`.

## v1.1.0 — 17/10/2026 : restructuration, tests et réglages vérifiés sur la machine cible

### Ajouté
- **Module `tweaks`** : réglages de la configuration Hyprland (clavier, curseur, XWayland lissé, latence de jeu facultative, ordre de chargement
  `lucid-look` / `settings`), rejouables seuls sans réinstaller Lucid (`./install.sh --only tweaks`).
- **Module `hyprbars`** (facultatif) : barres de titre façon macOS ; `HYPRBARS="remove"` le retire sans décharger le plugin à chaud.
- **`tests/check.sh`** : syntaxe, shellcheck, liste des modules, tests des helpers Hyprland sur une configuration jetable.
- **`tools/`** : échantillonneur de mémoire de Quickshell et test d'ouverture/fermeture de fenêtres.
- **Applications** : mpv (lecteur vidéo par défaut, HDR vers SDR), Prism Launcher + Java 21/25 (Minecraft Java), police Selawik (équivalent libre de
  Segoe UI) avec sa règle `fontconfig`.
- `CheckSpace` dans `pacman.conf`.
- `--list` affiche le rôle de chaque module et s'il touche à l'interface ; un nom de module inconnu dans `--only`/`--skip` est refusé.
- Documentation : `PROBLEMES-CONNUS.md` (tableau récapitulatif), `HISTORIQUE.md` §17 à §28, ce journal.

### Corrigé
- `hypr_require` considérait comme chargé un `require` **commenté** ; il ne regarde plus que les lignes actives.
- Lucid Settings affichait les coins et l'ombre comme verrouillés : `lucid-look` était chargé après `settings` (installeur de Lucid).
- Les étapes qui touchent au bureau (`tweaks`, `hyprbars`, variables NVIDIA) ne font plus rien si Hyprland n'est pas installé.

### Retiré / désactivé
- VLC (remplacé par mpv) ; `GAMING_LATENCY` reste **désactivé par défaut** (tearing non actif mesuré, cause d'un blocage de la vue non isolée) ;
  `hyprbars` retiré de la machine de référence (le module reste dans le dépôt).

## v1.0.0 — 15/10/2026 : première version

Script modulaire (`base`, `system`, `security`, `shell`, `apps`, `desktop`, `hardware`, `boot`) : Btrfs + snapper, `sshd` durci, `ufw`, `fail2ban`, `auditd`,
AppArmor, zsh, Hyprland + Lucid (épinglé par hash), pilote NVIDIA open, démarrage silencieux. Validé de bout en bout sur CachyOS + systemd-boot + Btrfs + RTX 5080.
