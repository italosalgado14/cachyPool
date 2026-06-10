#!/usr/bin/env bash
# monitor-autoswitch.sh — pick the monitor layout automatically from what's
# connected. Only two states are ever auto-applied:
#
#   DP-1 (Samsung FHD) + DP-2 (portable QHD) both present  -> 'read'
#   exactly one external present                           -> 'onescreen'
#   no external displays at all (integrated screen only)   -> 'laptop'
#
# 'desktop' (3-across) is NEVER auto-applied — reach it manually with Super+M.
# Runs once at login, then blocks listening to Hyprland's .socket2 hotplug
# events. Super+M selects desktop/read manually between events (re-evaluated on
# the next monitor add/remove).
#
# Geometry lives in monitor-mode.sh — this script only decides which to apply.

set -uo pipefail

MODE_SCRIPT="$HOME/.config/hypr/scripts/monitor-mode.sh"
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"

desired_mode() {
  local names has1 has2
  names="$(hyprctl monitors -j | jq -r '.[].name')"
  grep -qx 'DP-1' <<<"$names" && has1=1 || has1=0
  grep -qx 'DP-2' <<<"$names" && has2=1 || has2=0
  if [[ "$has1" == 1 && "$has2" == 1 ]]; then
    echo read                       # both externals -> portrait read layout
  elif [[ "$has1" == 0 && "$has2" == 0 ]]; then
    echo laptop                     # no externals  -> integrated screen only
  else
    echo onescreen                  # one external  -> external + laptop
  fi
}

apply_if_changed() {
  local want cur
  want="$(desired_mode)"
  cur="$(cat "$STATE" 2>/dev/null || echo '')"
  if [[ "$want" != "$cur" ]]; then
    "$MODE_SCRIPT" "$want"
  fi
}

# Apply once at startup.
apply_if_changed

# React to monitor hotplug events.
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - "UNIX-CONNECT:$SOCK" 2>/dev/null | while read -r line; do
  case "${line%%>>*}" in
    monitoradded|monitoraddedv2|monitorremoved|monitorremovedv2)
      sleep 0.5          # let Hyprland finish configuring the new monitor set
      apply_if_changed
      ;;
  esac
done
