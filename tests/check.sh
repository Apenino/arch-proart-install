#!/usr/bin/env bash
# Contrôles sans effet sur la machine : syntaxe, shellcheck, liste des modules, et tests des helpers Hyprland
# sur une configuration jetable. Usage : ./tests/check.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

fail=0
check() { if "$@"; then printf '  ok   %s\n' "${*:2}"; else printf '  ÉCHEC %s\n' "${*:2}"; fail=1; fi; }

echo "== syntaxe"
for f in install.sh lib/common.sh modules/*.sh files/hyprbars/*.sh tests/check.sh; do check bash -n "$f"; done

echo "== shellcheck"
if command -v shellcheck >/dev/null; then
    check shellcheck -x -e SC1091 install.sh lib/common.sh modules/*.sh files/hyprbars/*.sh tests/check.sh
else
    echo "  (shellcheck absent : ignoré)"
fi

echo "== modules"
mods="$(./install.sh --list | awk 'NR>1{print $1}')"
for m in $mods; do check test -f "modules/$m.sh"; done
check bash -c '! ./install.sh --only inconnu >/dev/null 2>&1'

echo "== helpers Hyprland (config jetable)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
(
    export HOME="$tmp" DRY_RUN=0
    mkdir -p "$HOME/.config/hypr"
    # shellcheck source=/dev/null
    source lib/common.sh
    HYPR_CFG="$HOME/.config/hypr/hyprland.lua"
    printf '%s\n' 'require("modules.a")' '-- require("modules.gaming")' >"$HYPR_CFG"

    hypr_require modules.b >/dev/null
    grep -qx 'require("modules.b")' "$HYPR_CFG" || { echo "  ÉCHEC require ajouté"; exit 1; }
    hypr_require modules.b >/dev/null
    [[ "$(grep -c 'modules.b' "$HYPR_CFG")" == 1 ]] || { echo "  ÉCHEC require idempotent"; exit 1; }
    # une ligne commentée ne compte pas comme chargée
    hypr_require modules.gaming >/dev/null
    grep -qx 'require("modules.gaming")' "$HYPR_CFG" || { echo "  ÉCHEC ligne commentée ignorée"; exit 1; }
    hypr_unrequire modules.gaming >/dev/null
    ! grep -qx 'require("modules.gaming")' "$HYPR_CFG" || { echo "  ÉCHEC require retiré"; exit 1; }
    grep -q 'modules.a' "$HYPR_CFG" || { echo "  ÉCHEC autres lignes conservées"; exit 1; }
    echo "  ok   hypr_require / hypr_unrequire"

    # ordre de chargement : lucid-look doit passer avant settings
    printf '%s\n' 'require("modules.settings")' 'require("modules.nvidia")' 'require("modules.lucid-look")' >"$HYPR_CFG"
    hypr_require_before modules.lucid-look modules.settings >/dev/null
    [[ "$(grep -n 'lucid-look' "$HYPR_CFG" | cut -d: -f1)" -lt "$(grep -n 'modules.settings' "$HYPR_CFG" | cut -d: -f1)" ]] \
        || { echo "  ÉCHEC ordre look/settings"; exit 1; }
    [[ "$(grep -c 'require' "$HYPR_CFG")" == 3 ]] || { echo "  ÉCHEC lignes conservées"; exit 1; }
    hypr_require_before modules.lucid-look modules.settings >/dev/null
    [[ "$(grep -c 'lucid-look' "$HYPR_CFG")" == 1 ]] || { echo "  ÉCHEC ordre idempotent"; exit 1; }
    echo "  ok   hypr_require_before"

    rm -f "$HYPR_CFG"
    need_hypr_config test >/dev/null && { echo "  ÉCHEC sans interface"; exit 1; }
    echo "  ok   sans interface : étapes ignorées"
) || fail=1

((fail)) && { echo "ÉCHEC"; exit 1; }
echo "Tout est bon."
