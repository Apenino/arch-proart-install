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
| **VLC** (remplacé par mpv le 16/10/2026) | **XWayland** | **Wayland natif impossible avec VLC 3.0.24** (testé : `QT_QPA_PLATFORM=wayland` est ignoré, et sans `DISPLAY` l'interface ne démarre pas : « no suitable interface module »). Remplacé par `mpv`, natif Wayland (§8) |
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

## 6. Latence de jeu (CS2) — `désactivé`, gain non démontré

**Module** : `files/hypr/gaming.lua` (option `GAMING_LATENCY`, **désactivée par défaut**) : `general:allow_tearing = true`,
`render:direct_scanout = 2`, règle de fenêtre `cs2` en `immediate` + plein écran, souris en profil plat
(`accel_profile = "flat"`, `sensitivity = 0`). Hyprland accepte l'ensemble sans erreur de configuration.

**Mesure (16/10/2026, CS2 en plein écran, `hyprctl monitors -j`)** : le tearing **n'est pas actif**
(`activelyTearing = False` sur les deux écrans). Le jeu est une fenêtre XWayland de 3072×1728 (état plein écran 2) agrandie
par Hyprland sur un écran 4K à l'échelle 1,25. Raisons rapportées : tearing `NOT_TORN`, `CANDIDATE` ; scanout direct
`CONTENT`, `SW`, `CANDIDATE` (écran du jeu) et `WINDOWED`, `SW`, `CANDIDATE` (l'autre). Le sens exact de ces codes n'a pas pu
être confirmé dans le code source (téléchargement impossible) : l'explication « fenêtre mise à l'échelle par le compositeur »
est une **déduction** cohérente avec les codes, pas une preuve.

**Effet constaté en jeu** : avec le module actif, la vue ne tournait plus du tout dans une partie (menu normal). Module
désactivé, la vue a de nouveau tourné. **Cause non isolée** : le test n'était pas contrôlé (le jeu a été relancé entre les
deux) ; la souris plate seule, la règle `immediate` ou la sensibilité du jeu (passée à 1) restent possibles. Pour
réessayer, activer **un seul réglage à la fois** (`input` d'abord, puis la règle de fenêtre).

**Limites connues** :

1. **Écran 60 Hz** (Dell U2718Q ×2) : la réactivité est d'abord limitée par l'écran ; un moniteur 144 à 240 Hz change bien
   plus que n'importe quel réglage logiciel. Pas de VRR sur ces écrans.
2. **Tearing et scanout direct exigent a priori une fenêtre plein écran non mise à l'échelle par le compositeur.** Pour
   essayer : `xwayland:force_zero_scaling` avec le jeu en 3840×2160 (voir §1), ce qui demande de rouvrir la session et
   rapetisse les autres applications X11. Non testé.
3. La souris plate ne change que le **bureau** : le jeu reçoit déjà des mouvements bruts (protocole de pointeur relatif).

**Réglage de sensibilité (conseil)** : souris Logitech G502 X à 800 DPI avec `sensitivity 1,99` = eDPI **1 592**, au-dessus de
la plage habituelle (environ 800 à 1 100). Valeur passée à `1` par l'utilisateur, qui doit s'y habituer.

## 7. Décharger le plugin hyprbars à chaud fait planter Hyprland — `contourné`

Le 16/10/2026, le retour arrière du module `hyprbars` a déchargé le plugin dans la session en cours (`hyprctl plugin unload`),
puis supprimé le `.so`. Quelques minutes plus tard Hyprland a fait un **SEGV** (saut vers une adresse qui n'existe plus : rappel
laissé par le plugin déchargé, c'est une déduction), le watchdog l'a relancé en **mode sans échec** (écran vide, plus de Lucid)
et **toutes les applications ouvertes ont été perdues**. Rien n'était cassé côté configuration.

**Règle** : ne jamais décharger un plugin Hyprland à chaud. `HYPRBARS="remove"` retire la ligne de `hyprland.lua` et les
fichiers, puis il faut **rouvrir la session**. Pour sortir du mode sans échec : `systemctl --user stop wayland-wm@hyprland.desktop.service`
(retour à SDDM). Voir `HISTORIQUE.md` §21.

## À surveiller (non reproduit)

- Après un crash de Quickshell, des processus enfants restent en doublon (clipboard stocké deux fois) : redémarrer la
  session règle le problème.
- Au lancement d'une application dans un espace de travail spécial (Lucid assigne Discord à `special:comms`), l'espace
  spécial peut s'afficher et prendre le focus un instant.

## 8. Vidéos HDR ternes dans VLC — `corrigé` (lecteur remplacé par mpv)

**Constat** : les vidéos HDR paraissaient délavées dans VLC. **Mesure** : l'EDID des deux Dell U2718Q ne contient **aucun bloc HDR**
(ni métadonnées `ST2084`/`HLG`, ni gamme BT.2020) et Hyprland les pilote en SDR (8 bits, préréglage `srgb`). Le câble n'est
pas en cause a priori (l'EDID passe par un canal séparé de l'image, et le 4K 60 Hz fonctionne) ; si le menu de l'écran propose
une option HDR, elle est à vérifier (certains écrans n'annoncent le HDR qu'une fois activé ou sur une seule entrée).

**Cause** : VLC 3.0 sur Linux ne ramène pas correctement le HDR vers un écran SDR. **Correction** : mpv (`files/mpv/mpv.conf` :
`vo=gpu-next`, `tone-mapping=bt.2446a`, `hdr-compute-peak=yes`), lecteur par défaut des vidéos, installé par le module `apps`.
Aucune conversion des fichiers (elle dégraderait la qualité). Le vrai HDR sur l'écran suppose que celui-ci l'annonce, puis le mode
expérimental de Hyprland : non tenté.


**Comparaison en direct (16/10/2026)** : même film HDR10 (PQ, BT.2020, 2160p H.265), mpv et VLC côte à côte sur le même écran, démarrés à
2 ms d'écart (écart de lecture de 109 ms après 4 s), mpv muet. Constat de l'utilisateur : **mpv nettement meilleur, couleurs plus
saturées et plus belles** ; VLC est ensuite désinstallé. mpv décode avec `nvdec` et rend avec `gpu-next`. Technique de comparaison :
VLC piloté par MPRIS (`busctl --user`, position et `Pause`/`Play`), mpv par son socket IPC (`--input-ipc-server`, `--start=<position>`),
lancé avec `hyprctl dispatch "hl.dsp.exec_cmd(...)"` (et non `hyprctl eval`, qui accepte la commande sans l'exécuter).

## 9. Polices des pages Microsoft différentes sous Linux — `corrigé` (Segoe UI → Selawik)

Segoe UI et Aptos sont propriétaires et absentes de Linux : `Segoe UI` retombait sur Adwaita Sans, `Aptos` sur Noto Sans (`Calibri` est
déjà bien remplacée par Carlito, aux mêmes dimensions). **Correction** : paquet AUR `ttf-selawik` (PKGBUILD relu : un zip GitHub
épinglé au commit `11fb355…`, copie des seuls `.ttf` et de la licence) + règle `fontconfig` `files/fontconfig/60-segoe-selawik.conf`.
Selawik ressemble à Segoe UI sans être identique. **Reste** : Aptos n'a pas de remplaçant libre. La vraie Segoe UI s'obtient en copiant les
fichiers d'une installation Windows possédée (question de licence, non fait).

## 10. Lucid Settings > Windows : l'arrondi des coins (et l'ombre) reste verrouillé — `corrigé et vérifié` (ordre de chargement)

**Constat** : dans Lucid Settings, la réglette des coins (`decoration.rounding`) est inutilisable ; « Reset » la débloque, puis un changement de
thème la reverrouille.
**Cause** (mesurée) : `$XDG_RUNTIME_DIR/lucid-settings-status.json` listait `decoration.rounding`, `rounding_power`, `shadow.enabled` et
`shadow.range` comme **`overridden`**. L'installeur de Lucid (`install.sh`, étape « look ») ajoute `require("modules.lucid-look")` à la **fin** de
`hyprland.lua`, donc après `require("modules.settings")` ; Hyprland applique les modules dans l'ordre et `lucid-look.lua` (arrondi 25, ombre 20)
écrase ce que Settings a écrit. Ce n'est pas une modification de ce dépôt (aucune référence à `lucid-look` dans le script avant la correction).
**Correction** : `lucid-look` est chargé **avant** `settings` (`hypr_require_before`, appelé par le module `tweaks`). Résultat : liste `overridden`
vide, arrondi 10 appliqué. **Vérifié par l'utilisateur après un changement de thème** : la réglette reste libre, la liste `overridden` reste vide.

## 11. Apple Music (client tiers AUR) ne démarre pas — `abandonné` (paquet retiré)

`apple-music-bin` 2.1.2 (Electron 28) s'arrête au démarrage : « Failed to install required components » (échec de l'installation du composant
Widevine, nécessaire à la lecture ; `--cdm-info` donne la même erreur). Le réseau n'est pas en cause (serveurs Google et Apple joignables). Cause
probable, non confirmée : Electron 28 trop ancien pour le service de composants actuel. Paquet retiré le 17/10/2026. Pistes : `sidra-bin` (non essayé),
ou Apple Music dans Firefox (Widevine déjà géré).

