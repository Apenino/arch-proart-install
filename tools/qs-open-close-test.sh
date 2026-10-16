#!/usr/bin/env bash
# Ouvre et ferme 20 fois une fenêtre kitty sur un espace spécial caché et mesure la mémoire de Quickshell.
# À lancer UNE SEULE fois à la fois, détaché : setsid nohup tools/qs-open-close-test.sh > sortie.txt 2>&1 < /dev/null &
# (plusieurs copies se ferment mutuellement leurs fenêtres de test). Les fenêtres ne sont jamais au premier plan :
# ni icône de fenêtre active ni aperçu ne sont sollicités.
set -u
XDG_RUNTIME_DIR=/run/user/$(id -u)
HYPRLAND_INSTANCE_SIGNATURE=$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' | sort -rn | head -1 | cut -d' ' -f2)
export XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE

QS=$(pgrep -x quickshell | head -1)
[[ -n $QS ]] || { echo "Quickshell ne tourne pas"; exit 1; }
rss() { awk '$1=="Rss:"{printf "%d",$2/1024}' "/proc/$QS/smaps_rollup" 2>/dev/null; }
testpid() { hyprctl clients -j | jq -r '.[] | select(.class=="qs-test-kitty") | .pid' | head -1; }

echo "départ : PID $QS, RSS $(rss) Mo, enfants $(pgrep -cP "$QS")"
base=$(rss)
for i in $(seq 1 20); do
    hyprctl dispatch "hl.dsp.exec_cmd('kitty --class qs-test-kitty --title qs-test-kitty', { workspace = 'special:qstest silent' })" >/dev/null
    p=""
    for _ in $(seq 1 20); do p=$(testpid); [[ -n $p ]] && break; sleep 0.5; done
    sleep 3
    opened=$(rss)
    [[ -n $p ]] && kill -TERM "$p"
    sleep 3
    closed=$(rss)
    printf '%2d  ouvert %4s Mo | fermé %4s Mo | écart à la base %+d Mo\n' "$i" "$opened" "$closed" $((closed - base))
done
sleep 8
echo "final : PID $(pgrep -x quickshell | head -1), RSS $(rss) Mo, enfants $(pgrep -cP "$QS"), fenêtres de test restantes: $(testpid | wc -l)"
