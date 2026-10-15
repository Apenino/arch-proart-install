# Machine cible : ASUS ProArt (PC de bureau)

Fiche matérielle tirée d'un export `msinfo32` de Windows 11 (15/10/2026, avant l'installation de Linux).
Ne contient volontairement **ni numéro de série, ni adresse MAC, ni nom d'utilisateur**.

## Matériel

| Élément | Détail |
|---|---|
| Type | **PC de bureau** (pas de batterie) |
| Carte mère | ASUS ProArt X870E-CREATOR WIFI, BIOS AMI du 28/01/2026, UEFI |
| Processeur | AMD Ryzen 9 9950X3D, 16 cœurs / 32 threads (Zen 5, V-Cache 3D) |
| Mémoire | 64 Go de RAM |
| GPU | **NVIDIA GeForce RTX 5080** (architecture Blackwell), écran 4K à 59 Hz |
| Stockage | NVMe **Crucial T710 2 To** (Windows : EFI 200 Mo + NTFS 1,82 To + récupération 906 Mo) ; 2 × **SanDisk SSD Plus 500 Go** (vus comme NVMe par Linux) (un en exFAT, un en NTFS) |
| Réseau | Intel Ethernet I226-V (2,5 GbE), Marvell AQtion 10 GbE, Qualcomm FastConnect 7800 Wi-Fi 7 (+ Bluetooth) |
| Audio | Realtek HD Audio (carte mère) + audio HDMI NVIDIA |
| USB | contrôleurs AMD (3.2 / 2.0), ASMedia (USB 3.2 et USB4) |
| Périphériques | clavier **AZERTY** Logitech (récepteur USB), souris Logitech en Bluetooth |
| Sécurité | **Secure Boot activé** sous Windows ; virtualisation (SVM) activée |

## À faire avant l'installation

- **BIOS** : désactiver **Secure Boot** (ou le laisser en mode personnalisé si tu sais enrôler des clés), désactiver le
  Fast Boot, rester en mode UEFI.
- **Disques** : installer sur le **NVMe de 2 To** et **ne pas sélectionner** les deux SanDisk de 500 Go (`nvme1n1` et `nvme2n1`) s'ils contiennent
  des données (le plus sûr : les débrancher pendant l'installation). Les partitions NTFS/exFAT se montent ensuite sans souci.
- **Pilote NVIDIA** : choisir la variante **open** dans l'installeur de la distribution. Les cartes RTX 50 (Blackwell)
  ne fonctionnent **qu'avec les modules open**. Le module `hardware` du script le vérifie et complète (paquets, paramètres
  noyau, environnement Hyprland) mais ne remplace pas ce choix.

## Conséquences pour le script

| Constat | Comportement du script |
|---|---|
| Bureau, pas de batterie | `power-profiles-daemon` ignoré (portable seulement) |
| CPU AMD | `thermald` ignoré (Intel seulement) ; `amd-ucode` installé |
| GPU NVIDIA Blackwell | module `hardware` : modules **open** (`linux-cachyos-nvidia-open`, sinon `nvidia-open` / `nvidia-open-dkms`), `nvidia-utils` + 32 bits pour Steam, `libva-nvidia-driver`, `egl-wayland`, paramètres noyau `nvidia-drm.modeset=1 nvidia-drm.fbdev=1`, modules NVIDIA chargés tôt dans l'initramfs, variables d'environnement Hyprland (`~/.config/hypr/modules/nvidia.lua`) |
| Plusieurs interfaces réseau | le pare-feu autorise SSH depuis le sous-réseau détecté ; mettre `LAN_CIDR` dans `config.env` si la détection choisit la mauvaise interface |
| Clavier Logitech | `solaar` possible via `EXTRA_PACKAGES="solaar"` dans `config.env` |

## À vérifier au premier démarrage sous Linux

```bash
lspci -k | grep -A3 -E 'VGA|Ethernet|Network'      # pilotes chargés : nvidia, igc, atlantic, ath12k (à confirmer)
nvidia-smi                                          # le GPU est vu, modules open
cat /sys/module/nvidia_drm/parameters/modeset       # Y
ip -br link                                         # les trois interfaces réseau
bluetoothctl list                                   # le Bluetooth est détecté
```

Un périphérique ACPI `RTK5452` apparaissait sans pilote sous Windows : sans conséquence connue pour Linux.
