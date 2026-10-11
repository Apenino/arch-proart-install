# arch-proart-install

Script post-installation pour Arch Linux (ASUS ProArt).

## Ce qu'il installe

- **Logiciels** : Firefox, OnlyOffice (AUR, via `yay`), Steam, Blender, Git
- **Pilotes Vulkan 32 bits** adaptés au GPU détecté (Intel / AMD / NVIDIA) pour Steam
- **Shell** : zsh + [Oh My Zsh](https://ohmyz.sh) + [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
  - plugins : `git`, `sudo`, `colored-man-pages`, `zsh-autosuggestions`, `zsh-syntax-highlighting`
- **kitty** : thème sombre, JetBrainsMono Nerd Font, zsh par défaut, traînée du curseur (`cursor_trail`)

Le dépôt `multilib` est activé automatiquement s'il ne l'est pas.

## Utilisation

```bash
git clone https://github.com/Apenino/arch-proart-install.git
cd arch-proart-install
./install.sh
```

À lancer en utilisateur normal (pas en root) : `sudo` est demandé quand c'est nécessaire.
Le script peut être relancé sans risque ; les fichiers de config existants sont sauvegardés en `*.bak.<date>` avant d'être remplacés.

## Structure

```
install.sh              script principal
dotfiles/
├── kitty/kitty.conf    config kitty
└── zsh/
    ├── .zshrc          config zsh / oh-my-zsh
    └── .p10k.zsh       config du prompt Powerlevel10k (refaire avec `p10k configure`)
```
