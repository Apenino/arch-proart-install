# Problèmes connus et points à corriger

Liste vivante : ce qui a été constaté sur la machine cible, la cause connue ou supposée, et ce qu'il reste à faire.
Chaque entrée indique son **état** : `à corriger`, `à re-tester`, `contourné`, `en amont` (bogue d'un autre projet).

## 1. Rendu pixélisé ou flou des applications X11 (XWayland) — `contourné`, correctif net `à corriger`

**Contexte** : écrans 4K à l'échelle **1,25**. Les applications Wayland natives se mettent à l'échelle elles-mêmes (rendu net) ;
celles qui passent par XWayland sont dessinées à la taille logique puis **agrandies par le compositeur**.

**Contournement appliqué** : `xwayland:use_nearest_neighbor = false` (`files/hypr/xwayland.lua`, option `XWAYLAND_SMOOTH`).
Le filtrage par défaut (`true`) est « plus proche voisin » = pixélisé ; `false` lisse. Steam est jugé net avec ce réglage.

**Correctif net, non appliqué** (demande de rouvrir la session et rend les autres applications X11 plus petites tant
qu'elles ne se mettent pas à l'échelle elles-mêmes) :

- `xwayland:force_zero_scaling = true` (nom exact en Hyprland 0.56, pas `force_zero_scale`) ;
- Steam : variable `STEAM_FORCE_DESKTOPUI_SCALING=1.25` ;
- OnlyOffice : option de mise à l'échelle propre au logiciel (Qt xcb) ; VLC (Qt5) : `QT_SCALE_FACTOR=1.25`.

### Audit des applications installées (16/10/2026)

Méthode : chaque application est lancée **sur un espace de travail spécial caché** (`workspace = "special:audit silent"`),
on lit si sa fenêtre est XWayland dans `hyprctl clients -j`, puis on la ferme.

| Application | Backend | Remarque |
|---|---|---|
| kitty, Nautilus, Firefox, Discord, Obsidian, VS Code (Code-OSS), Blender, Disques | **Wayland natif** | net |
| Proton VPN, Proton Pass, Proton Mail | **Wayland natif** | net |
| **OnlyOffice** | **XWayland** | Qt embarqué avec le seul plugin `xcb` : impossible en Wayland natif |
| **VLC** | **XWayland** | Qt5 ; `qt5-wayland` est installé, `QT_QPA_PLATFORM=wayland` à tester (la sortie vidéo de VLC 3 reste à vérifier) |
| **Steam**, jeux Steam/Proton | **XWayland** | Steam : lissé (voir plus haut) ; les jeux : voir CS2 |

## 2. CS2 : interface (menus) pixélisée, partie nette — `à re-tester` puis `à corriger`

**Constat** : l'interface des menus paraît pixélisée, l'intérieur d'une partie (Dust2) non.

**Cause probable** : la résolution vidéo du jeu est **3072 × 1728** (`cs2_video.txt`), c'est-à-dire la taille *logique* d'un
écran 4K à l'échelle 1,25, en fenêtre sans bordure. Le jeu est dessiné en 3072×1728 puis **agrandi à 3840×2160 par
Hyprland**. Le MSAA 4× (`msaa_samples = 4`) adoucit les arêtes en jeu, pas le texte de l'interface.

**À faire** :
1. **Re-tester après la fin de la compilation des shaders** : le constat a été fait pendant/juste après l'annulation
   de la compilation, le menu a pu utiliser un rendu de repli. C'est peut-être sans rapport avec l'échelle.
2. Si le menu reste pixélisé : appliquer le correctif net du §1 (le jeu voit alors 3840×2160 en natif) et régler la
   résolution du jeu à **3840 × 2160**.

## 3. Compilation des shaders très longue (NVIDIA) — `en amont` / comportement normal

Mesuré : 32 processus `fossilize_replay` à 100 % d'un cœur (97 % du CPU), disque et GPU inactifs ; ~1,7 million de
pipelines pour CS2, environ **40 à 60 minutes** au premier lancement ; **à refaire après chaque mise à jour du pilote
NVIDIA**. Voir `HISTORIQUE.md` §18. Pas de correctif : laisser terminer une fois.

## 4. Quickshell plante à l'ouverture d'une application — `en amont`

Bogue d'icônes asynchrones (Qt 6.12 + Quickshell 0.3.2), déjà signalé en amont. Voir `HISTORIQUE.md` §17.
Contournement local non testé : `asynchronous: false` dans `lucidbar/ActiveWindow.qml`.

## 5. Lucid n'a pas de traduction — `en amont`

Menus de Lucid en anglais, sans option de langue (pas de `qsTr`). Seul l'auteur peut l'ajouter.

## À surveiller (non reproduit)

- Après un crash de Quickshell, des processus enfants restent en doublon (clipboard stocké deux fois) : redémarrer la
  session règle le problème.
- Au lancement d'une application dans un espace de travail spécial (Lucid assigne Discord à `special:comms`), l'espace
  spécial peut s'afficher et prendre le focus un instant.
