#!/usr/bin/env bash
# Échantillonne la mémoire de Quickshell toutes les 30 s pendant 60 min (lecture seule).
# Usage : tools/qs-mem-sampler.sh fichier.csv   (à lancer détaché : setsid nohup ... &)
# Colonnes : secondes, RSS, Pss_Anon, Pss_File (Mo), threads, descripteurs, fenêtres, entrées cliphist, mémoire des enfants (Mo)
set -u
OUT=${1:?usage : $0 fichier.csv}
XDG_RUNTIME_DIR=/run/user/$(id -u)
HYPRLAND_INSTANCE_SIGNATURE=$(find "$XDG_RUNTIME_DIR/hypr" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' | sort -rn | head -1 | cut -d' ' -f2)
export XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE

smaps() { awk -v k="$1:" '$1==k{printf "%d",$2/1024}' "/proc/$PID/smaps_rollup"; }
count() { find "$1" -mindepth 1 -maxdepth 1 | wc -l; }

echo "t_s,rss_mb,pss_anon_mb,pss_file_mb,threads,fds,clients,cliphist,children_mb" >"$OUT"
T0=$(date +%s)
for _ in $(seq 1 120); do
    PID=$(pgrep -x quickshell | head -1)
    if [[ -z $PID ]]; then
        echo "$(($(date +%s) - T0)),QUICKSHELL_ABSENT" >>"$OUT"
        sleep 30
        continue
    fi
    clients=$(hyprctl clients -j 2>/dev/null | jq length 2>/dev/null)
    cliphist=$(cliphist list 2>/dev/null | wc -l)
    children=$(ps --ppid "$PID" -o rss= | awk '{s+=$1} END{printf "%d",s/1024}')
    echo "$(($(date +%s) - T0)),$(smaps Rss),$(smaps Pss_Anon),$(smaps Pss_File),$(count "/proc/$PID/task"),$(count "/proc/$PID/fd"),${clients:-?},$cliphist,$children" >>"$OUT"
    sleep 30
done
