#!/usr/bin/env bash
# Ouvre et ferme 20 fois une fenêtre kitty sur un espace spécial caché et mesure la mémoire de Quickshell.
# À lancer UNE SEULE fois à la fois, détaché : setsid nohup tools/qs-open-close-test.sh > sortie.txt 2>&1 < /dev/null &
# (plusieurs copies se ferment mutuellement leurs fenêtres de test).
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)
QS=$(pgrep -x quickshell | head -1)
rss(){ awk '/^Rss:/{printf "%d",$2/1024}' /proc/$QS/smaps_rollup 2>/dev/null; }
testpid(){ hyprctl clients -j | jq -r '.[] | select(.class=="qs-test-kitty") | .pid' | head -1; }
echo "départ : PID $QS, RSS $(rss) Mo, enfants $(pgrep -P $QS | wc -l)"
base=$(rss)
for i in $(seq 1 20); do
  hyprctl dispatch "hl.dsp.exec_cmd('kitty --class qs-test-kitty --title qs-test-kitty', { workspace = 'special:qstest silent' })" >/dev/null
  p=""; for k in $(seq 1 20); do p=$(testpid); [ -n "$p" ] && break; sleep 0.5; done
  sleep 3; o=$(rss)
  [ -n "$p" ] && kill -TERM "$p"; sleep 3; c=$(rss)
  printf '%2d  ouvert %4s Mo | fermé %4s Mo | écart à la base %+d Mo\n' $i "$o" "$c" $((c-base))
done
sleep 8
echo "final : PID $(pgrep -x quickshell | head -1), RSS $(rss) Mo, enfants $(pgrep -P $QS | wc -l), fenêtres de test restantes: $(testpid | wc -l)"
