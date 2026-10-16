-- XWayland (Steam, applications X11) : à une échelle fractionnaire (ex. 1,25) le compositeur agrandit les fenêtres X11.
-- use_nearest_neighbor = true (défaut de Hyprland) les rend pixélisées ; false les lisse (bilinéaire).
-- Écrit par arch-proart-install (XWAYLAND_SMOOTH="no" pour ne pas l'installer).
hl.config({ xwayland = { use_nearest_neighbor = false } })
