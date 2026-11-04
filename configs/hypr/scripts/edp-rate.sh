#!/usr/bin/env bash
# edp-rate.sh — reconcile ONLY eDP-1's refresh rate with the power source:
# 240 Hz on AC, 60 Hz on battery. This is the hook power-autoswitch.sh calls.
#
# WHY THIS FILE EXISTS (2026-11-03): it is a faithful port of
# `monitor-mode.sh edp-rate`. Hyprland 0.57.1 removed `hyprctl keyword` — the
# IPC request answers "unknown request" — so the apply goes through
# `hyprctl eval 'hl.monitor({...})'` instead. monitor-mode.sh (and with it the
# five layout profiles) is PARKED for the Lua migration, but the refresh-rate
# reconcile is the cheapest real power saving on this machine and must not go
# down with it. runbooks/power-battery.md §19.
#
# This is still the ONLY owner of eDP-1's refresh rate. Do not write a
# `2560x1600@240` literal anywhere else: before the rate had one owner the
# string was repeated at 9 sites and every profile apply, hotplug or reload
# undid whatever had set it.
#
# Resolution: `Discharging` in BAT1's status — never ACAD/online, which reads 1
# when only the TB4 dock feeds the machine — plus the Triton Panel toggle.
set -euo pipefail

EDP_HI="2560x1600@240"
EDP_LO="2560x1600@60"
EDP_PREF="${XDG_CONFIG_HOME:-$HOME/.config}/triton-panel/power-auto"

on_battery() {
  grep -q Discharging /sys/class/power_supply/BAT1/status 2>/dev/null
}

# Absent pref file means ENABLED: automatic saving is the default, and a fresh
# checkout must behave like a configured one. The `|| echo 1` matters under
# `set -euo pipefail` — a missing file must not abort the run.
power_auto() {
  [[ "$(cat "$EDP_PREF" 2>/dev/null || echo 1)" != 0 ]]
}

edp_mode() {
  if power_auto && on_battery; then printf '%s' "$EDP_LO"; else printf '%s' "$EDP_HI"; fi
}

want="$(edp_mode)"
want_hz="${want##*@}"

# Three guards, each for a failure found while building the original:
#
#   1. eDP-1 must be in `hyprctl monitors -j` (ENABLED outputs only, never
#      `monitors all`). Emitting a mode at a DISABLED output does not set a
#      rate — it ENABLES the output, which would undo a clamshell every tick.
#   2. Skip while DPMS is off. A modeset wakes the panel, so reconciling under
#      hypridle's DPMS-off would turn the screen back on by itself.
#   3. Only emit when the rate actually differs. A real modeset every few
#      seconds would flicker the panel and flood the log.
read -r cur_hz cur_x cur_y cur_scale cur_dpms < <(
  hyprctl monitors -j 2>/dev/null \
    | jq -r '.[] | select(.name=="eDP-1")
             | "\(.refreshRate|round) \(.x) \(.y) \(.scale) \(.dpmsStatus)"' 2>/dev/null
) || exit 0

# Written as `if` blocks, not `(( )) && exit`: under `set -e` a bare failing
# arithmetic test as the first element of an AND-OR list is a foot-gun.
if [[ -z "${cur_hz:-}" ]]; then exit 0; fi                      # guard 1
if [[ ! "$cur_hz" =~ ^[0-9]+$ ]]; then exit 0; fi
if [[ "$cur_dpms" != "true" ]]; then exit 0; fi                 # guard 2
if (( cur_hz == ${want_hz%%.*} )); then exit 0; fi              # guard 3

hyprctl eval "hl.monitor({ output = \"eDP-1\", mode = \"$want\", position = \"${cur_x}x${cur_y}\", scale = $cur_scale })" >/dev/null
