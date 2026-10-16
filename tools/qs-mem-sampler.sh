#!/usr/bin/env bash
# Échantillonne la mémoire de Quickshell toutes les 30 s pendant 60 min (lecture seule). Usage : tools/qs-mem-sampler.sh fichier.csv
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)
OUT=$1
echo "t_s,rss_mb,pss_anon_mb,pss_file_mb,threads,fds,clients,cliphist,children_mb" > $OUT
T0=$(date +%s)
for i in $(seq 1 120); do
  PID=$(pgrep -x quickshell | head -1); [ -z "$PID" ] && { echo "$(( $(date +%s)-T0 )),QUICKSHELL_ABSENT" >> $OUT; sleep 30; continue; }
  R=$(awk '/^Rss:/{printf "%d",$2/1024}' /proc/$PID/smaps_rollup)
  A=$(awk '/^Pss_Anon:/{printf "%d",$2/1024}' /proc/$PID/smaps_rollup)
  F=$(awk '/^Pss_File:/{printf "%d",$2/1024}' /proc/$PID/smaps_rollup)
  C=$(hyprctl clients -j 2>/dev/null | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))' 2>/dev/null)
  H=$(cliphist list 2>/dev/null | wc -l)
  K=$(ps --ppid $PID -o rss= | awk '{s+=$1}END{printf "%d",s/1024}')
  echo "$(( $(date +%s)-T0 )),$R,$A,$F,$(ls /proc/$PID/task | wc -l),$(ls /proc/$PID/fd | wc -l),$C,$H,$K" >> $OUT
  sleep 30
done
