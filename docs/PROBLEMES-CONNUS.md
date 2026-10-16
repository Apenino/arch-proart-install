# Problèmes connus et points à corriger

Liste vivante : ce qui a été constaté sur la machine cible, la cause connue ou supposée, et ce qu'il reste à faire.
Chaque entrée indique son **état** : `à corriger`, `à re-tester`, `contourné`, `en amont` (bogue d'un autre projet).

## 1. Rendu pixélisé ou flou des applications X11 (XWayland) — `contourné` (net : correctif optionnel)

**Contexte** : écrans 4K à l'échelle **1,25**. Les applications Wayland natives se mettent à l'échelle elles-mêmes (rendu net) ;
celles qui passent par XWayland sont dessinées à la taille logique puis **agrandies par le compositeur**.

**Contournement appliqué** : `xwayland:use_nearest_neighbor = false` (`files/hypr/xwayland.lua`, option `XWAYLAND_SMOOTH`).
Le filtrage par défaut (`true`) est « plus proche voisin » = pixélisé ; `false` lisse. Steam et le menu de CS2 sont jugés nets avec ce réglage.

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
| **VLC** | **XWayland** | **Wayland natif impossible avec VLC 3.0.24** (testé : `QT_QPA_PLATFORM=wayland` est ignoré, et sans `DISPLAY` l'interface ne démarre pas : « no suitable interface module »). Attendre VLC 4, ou utiliser `mpv`/Celluloid, natifs Wayland |
| **Steam**, jeux Steam/Proton | **XWayland** | Steam : lissé (voir plus haut) ; les jeux : voir CS2 |

## 2. CS2 : interface (menus) pixélisée, partie nette — `résolu` (par le lissage XWayland)

**Constat initial** : l'interface des menus paraissait pixélisée, l'intérieur d'une partie (Dust2) non.

**Cause** : la résolution vidéo du jeu est **3072 × 1728** (`cs2_video.txt`), c'est-à-dire la taille *logique* d'un écran 4K à
l'échelle 1,25, en fenêtre sans bordure : le jeu est dessiné en 3072×1728 puis **agrandi à 3840×2160 par Hyprland**, avec le
filtrage « plus proche voisin » par défaut = pixélisé. Le MSAA 4× (`msaa_samples = 4`) adoucit les arêtes en jeu, pas le
texte de l'interface.

**Correction** : le lissage XWayland du §1 (`xwayland:use_nearest_neighbor = false`). Constaté : **le menu est net**, avec
une compilation de shaders encore incomplète (le rendu de repli du menu n'était donc pas en cause).

**Reste possible (optionnel)** : la résolution du jeu reste 3072×1728 agrandie (légère douceur). Le rendu en 3840×2160 natif
demande le correctif net du §1 (`force_zero_scaling`) et la résolution du jeu à 3840×2160.

## 3. Compilation des shaders très longue (NVIDIA) — `en amont` / comportement normal

Mesuré : 32 processus `fossilize_replay` à 100 % d'un cœur (97 % du CPU), disque et GPU inactifs ; ~1,7 million de
pipelines pour CS2, environ **40 à 60 minutes** au premier lancement ; **à refaire après chaque mise à jour du pilote
NVIDIA**. Voir `HISTORIQUE.md` §18. Pas de correctif : laisser terminer une fois.

## 4. Quickshell plante à l'ouverture d'une application — `en amont`

Bogue d'icônes asynchrones (Qt 6.12 + Quickshell 0.3.2), déjà signalé en amont. Voir `HISTORIQUE.md` §17.
Contournement local non testé : `asynchronous: false` dans `lucidbar/ActiveWindow.qml`.

## 5. Lucid n'a pas de traduction — `en amont`

Menus de Lucid en anglais, sans option de langue (pas de `qsTr`). Seul l'auteur peut l'ajouter.

## 6. Latence de jeu (CS2) — `appliqué`, efficacité `à vérifier en jeu`

**Appliqué** (`files/hypr/gaming.lua`, option `GAMING_LATENCY`) : `general:allow_tearing = true`, `render:direct_scanout = 2`
(automatique), règle de fenêtre `cs2` en `immediate` + plein écran, souris en profil plat (`accel_profile = "flat"`,
`sensitivity = 0`). Hyprland accepte l'ensemble sans erreur de configuration.

**Limites connues** (à garder en tête avant d'attendre un gain) :

1. **Écran 60 Hz** (Dell U2718Q ×2) : la réactivité est d'abord limitée par l'écran ; un moniteur 144 à 240 Hz change bien
   plus que n'importe quel réglage logiciel. Pas de VRR sur ces écrans.
2. **Le tearing et le scanout direct exigent une fenêtre plein écran non mise à l'échelle par le compositeur.** CS2 est un
   client XWayland et l'écran est à l'échelle 1,25 : Hyprland agrandit la fenêtre du jeu, ce qui bloque a priori le
   scanout direct. Le gain n'est donc pas garanti dans cette configuration. Pour l'obtenir : `xwayland:force_zero_scaling`
   avec le jeu en 3840×2160 (voir §1), ce qui demande de rouvrir la session.
3. La souris plate ne change que le **bureau** : le jeu reçoit déjà des mouvements bruts (protocole de pointeur relatif).

**Vérification objective, pendant que CS2 est en plein écran** : `hyprctl monitors -j` expose, par écran, `activelyTearing`,
`tearingBlockedBy` et `directScanoutBlockedBy` (la liste des raisons qui empêchent le tearing/scanout). Au repos :
`tearingBlockedBy = ['NOT_TORN', 'CANDIDATE']`. Si, en jeu, `activelyTearing` reste `False` et qu'une raison de type
échelle/plein écran apparaît, c'est la limite n°2.

**Réglage de sensibilité (conseil, non appliqué)** : souris Logitech G502 X à 800 DPI avec `sensitivity 1,99` = eDPI **1 592**,
au-dessus de la plage habituelle (environ 800 à 1 100). Une valeur de départ proche de `1.0` à `1.25` est un bon essai ;
changer progressivement et garder la même sensibilité partout.

## À surveiller (non reproduit)

- Après un crash de Quickshell, des processus enfants restent en doublon (clipboard stocké deux fois) : redémarrer la
  session règle le problème.
- Au lancement d'une application dans un espace de travail spécial (Lucid assigne Discord à `special:comms`), l'espace
  spécial peut s'afficher et prendre le focus un instant.
