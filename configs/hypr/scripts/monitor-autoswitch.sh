#!/usr/bin/env bash
# monitor-autoswitch.sh — pick the monitor layout automatically from what's
# connected. Only these states are ever auto-applied:
#
#   two externals, one is the FHD portable ("demoset" EDID) -> 'trio'
#   two externals otherwise (desk ext, e.g. Xiaomi 4K + portable QHD) -> 'read'
#   exactly one external present                            -> 'onescreen'
#   no external displays at all (integrated screen only)    -> 'laptop'
#
# Externals are counted as "any monitor that isn't eDP-1" rather than by
# DP-1/DP-2 name, because port names shift with plug order.
# 'desktop' (3-across) is NEVER auto-applied — reach it manually with Super+M.
# Runs once at login, then blocks listening to Hyprland's .socket2 hotplug
# events. Super+M selections hold until the next EXTERNAL monitor add/remove —
# eDP-1 events are ignored (see the event loop below for why).
#
# Geometry lives in monitor-mode.sh — this script only decides which to apply.

set -uo pipefail

MODE_SCRIPT="$HOME/.config/hypr/scripts/monitor-mode.sh"
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"

desired_mode() {
  local mons externals demoset
  mons="$(hyprctl monitors -j)" || mons=""
  if [[ -z "$mons" ]]; then
    # hyprctl hiccup — keep whatever mode is current instead of concluding
    # "no monitors -> laptop" from an empty answer.
    cat "$STATE" 2>/dev/null || echo laptop
    return
  fi
  externals="$(jq '[.[] | select(.name != "eDP-1")] | length' <<<"$mons")"
  demoset="$(jq '[.[] | select((.description // "") | test("demoset"))] | length' <<<"$mons")"
  if [[ "$externals" -ge 2 && "$demoset" -ge 1 ]]; then
    echo trio                       # both 16" portables -> road trio, laptop on
  elif [[ "$externals" -ge 2 ]]; then
    echo read                       # desk externals -> portrait read layout
  elif [[ "$externals" -eq 0 ]]; then
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

# React to monitor hotplug events — but IGNORE events for eDP-1. The built-in
# panel is never physically hotplugged; add/remove events for it are the mode
# script's own keyword-driven disable/enable (Hyprland posts hotplug events
# for those too). Reacting to them would instantly revert every manual Super+M
# choice that toggles the laptop panel: read->desktop at the desk (desktop
# enables eDP-1 -> monitoradded -> autoswitch re-applies read) and trio->read
# on the road (read disables eDP-1 -> monitorremoved -> re-applies trio).
# v1 event payload is the monitor name; v2 payload is "id,name,description".
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - "UNIX-CONNECT:$SOCK" 2>/dev/null | while read -r line; do
  ev="${line%%>>*}"
  payload="${line#*>>}"
  case "$ev" in
    monitoradded|monitorremoved)     name="$payload" ;;
    monitoraddedv2|monitorremovedv2) name="$(cut -d, -f2 <<<"$payload")" ;;
    *) continue ;;
  esac
  [[ "$name" == "eDP-1" ]] && continue
  sleep 0.5          # let Hyprland finish configuring the new monitor set
  apply_if_changed
done
