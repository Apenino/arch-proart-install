-- Latence de jeu (CS2 et jeux Steam) — écrit par arch-proart-install (GAMING_LATENCY="yes" pour l'installer).
-- À charger APRÈS input.lua (c'est le cas) : ces valeurs surchargent celles de input.lua.
hl.config({
    general = {
        -- autorise le tearing ; seules les fenêtres avec la règle « immediate » (ci-dessous) en profitent
        allow_tearing = true,
    },
    render = {
        -- scanout direct automatique pour les jeux (Hyprland décide selon le type de contenu)
        direct_scanout = 2,
    },
    input = {
        -- souris 1:1 sur le bureau : pas d'accélération libinput (le jeu, lui, reçoit déjà des mouvements bruts)
        accel_profile = "flat",
        sensitivity   = 0,
    },
})

-- CS2 : présentation immédiate (tearing) et plein écran, quand les conditions sont réunies.
-- Le tearing ne s'active que si la fenêtre est en plein écran ET non mise à l'échelle par le compositeur
-- (échelle d'écran 1,0, ou XWayland sans mise à l'échelle) : voir docs/PROBLEMES-CONNUS.md §6.
hl.window_rule({
    name  = "cs2-latence",
    match = { class = "^cs2$" },

    immediate  = true,
    fullscreen = true,
})
