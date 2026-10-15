-- hyprbars : barres de titre façon macOS sur toutes les fenêtres (écrit par arch-proart-install).
-- Le plugin est compilé et chargé par scripts/hyprbars-plugin.sh ; ces réglages ne s'appliquent que s'il l'est.
-- Désactiver : `scripts/hyprbars-plugin.sh remove` puis retirer require("modules.hyprbars") de hyprland.lua.
-- Masquer la barre sur certaines fenêtres : règles dynamiques `hyprbars:no_bar` (voir le README de hyprbars).
hl.on("hyprland.start", function ()
  local s = os.getenv("HOME") .. "/.config/hypr/scripts/hyprbars-plugin.sh"
  hl.exec_cmd("test -x '" .. s .. "' && exec '" .. s .. "' ensure")
end)

if hl.plugin.hyprbars then
  hl.config { plugin = { hyprbars = {
    enabled               = true,
    bar_height            = 28,
    bar_color             = "rgba(1e1e22e6)",
    ["col.text"]          = "rgba(c9c9cfff)",
    bar_text_size         = 10,
    bar_text_align        = "center",
    bar_buttons_alignment = "left",     -- pastilles à gauche, comme macOS
    bar_padding           = 12,
    bar_button_padding    = 8,
    bar_precedence_over_border = true,
    icon_on_hover         = true,       -- les symboles n'apparaissent qu'au survol
    inactive_button_color = "rgba(5a5a60ff)",
    on_double_click       = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = 1 })'",
  } } }

  -- de gauche à droite : rouge (fermer), jaune (ranger dans le scratchpad de Lucid), vert (plein écran).
  -- Les boutons agissent sur la fenêtre cliquée : hyprbars lui donne le focus avant d'exécuter l'action.
  -- stash() de Lucid renvoie une fonction : il faut l'appeler (d'où les deux paires de parenthèses).
  hl.plugin.hyprbars.add_button({ bg_color = "rgb(ff5f57)", fg_color = "rgb(4d0000)", size = 13, icon = "×",
    action = "hyprctl dispatch 'hl.dsp.window.close()'" })
  hl.plugin.hyprbars.add_button({ bg_color = "rgb(febc2e)", fg_color = "rgb(5a3d00)", size = 13, icon = "−",
    action = "hyprctl eval 'require(\"modules.specials\").stash()()'" })
  hl.plugin.hyprbars.add_button({ bg_color = "rgb(28c840)", fg_color = "rgb(003a0c)", size = 13, icon = "+",
    action = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = 1 })'" })
end
