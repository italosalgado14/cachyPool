#!/usr/bin/env bash
# monitor-menu.sh — a "Setup > Monitors" menu (after Omarchy's), shown in Walker.
#
# Entry points:
#   - Super+Shift+M (keybindings.conf).
#   - The "Monitors" Walker entry (~/.local/share/applications/monitors.desktop,
#     mirrored in configs/applications/).
#
# Picks a monitor-mode.sh profile by hand (only the ones that fit the connected
# monitors, see below), opens the hyprmon layout editor (hyprmon-edit.sh), or
# shows the live layout. Picking a profile is a manual override exactly like Super+M: it
# holds until the next external plug/unplug, when monitor-autoswitch.sh decides
# again.
#
# Launched from Walker this runs under the systemd --user manager, not
# Hyprland; hyprctl still works there because HYPRLAND_INSTANCE_SIGNATURE is in
# the user manager's environment (checked 2026-10-15 with
# `systemctl --user show-environment`).

set -uo pipefail

SCRIPTS="$HOME/.config/hypr/scripts"
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"
current="$(cat "$STATE" 2>/dev/null || echo '')"

# Only offer the profiles that fit what's connected, using the same
# classification as desired_mode() in monitor-autoswitch.sh: the auto profile
# for that set plus its Super+M partner. The rest are wrong for the set, and
# some overlap outputs. At the desk, `trio` puts the Xiaomi at scale 1 (3840
# logical wide) with eDP-1 at x=3072 on top of it. With two externals,
# `onescreen` drops the AQ16H at 0x0 over the Xiaomi. `laptop` never disables
# the externals. Run monitor-mode.sh by hand to force one anyway.
mons="$(hyprctl monitors -j 2>/dev/null)" || mons="[]"
externals="$(jq '[.[] | select(.name != "eDP-1")] | length' <<<"$mons" 2>/dev/null)" || externals=0
demoset="$(jq '[.[] | select((.description // "") | test("demoset"))] | length' <<<"$mons" 2>/dev/null)" || demoset=0
if (( externals >= 2 && demoset >= 1 )); then
  modes=(trio read)
elif (( externals >= 2 )); then
  modes=(read desktop)
elif (( externals == 1 )); then
  modes=(onescreen)
else
  modes=(laptop)
fi

declare -A blurb=(
  [desktop]="3-across, all landscape"
  [read]="portable portrait, laptop off"
  [laptop]="integrated screen only"
  [onescreen]="one external + laptop"
  [trio]="both portables + laptop"
)
EDIT="Edit layout (Hyprmon)"
SHOW="Show current layout"

menu() {
  local m mark
  for m in "${modes[@]}"; do
    [[ "$m" == "$current" ]] && mark="●" || mark="○"
    printf '%s %s — %s\n' "$mark" "$m" "${blurb[$m]}"
  done
  printf '%s\n%s\n' "$EDIT" "$SHOW"
}

show_layout() {
  local body
  body="$(hyprctl monitors all -j 2>/dev/null | jq -r '.[]
      | "\(.name): \(.model) — "
        + (if .disabled then "off"
           else "\(.width)x\(.height)@\(.refreshRate | round)Hz at \(.x),\(.y), scale \(.scale), transform \(.transform)"
           end)')" || body="hyprctl did not answer"
  notify-send -t 10000 "Monitors — mode: ${current:-unknown}" "$body" 2>/dev/null || true
}

choice="$(menu | walker --dmenu -p "Monitors" 2>/dev/null)" || exit 0
[[ -n "$choice" ]] || exit 0

case "$choice" in
  "$EDIT") exec "$SCRIPTS/hyprmon-edit.sh" ;;
  "$SHOW") show_layout ;;
  *)
    mode=""
    read -r _ mode _ <<<"$choice"
    # Only a profile the menu actually offered; the -n guard also matters because
    # an empty key is a "bad array subscript" error on an associative array.
    if [[ -n "$mode" && -n "${blurb[$mode]+x}" && " ${modes[*]} " == *" $mode "* ]]; then
      exec "$SCRIPTS/monitor-mode.sh" "$mode"
    fi
    ;;
esac
