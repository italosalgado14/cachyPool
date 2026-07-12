#!/usr/bin/env bash
# monitor-mode.sh — switch between monitor layout profiles live (no logout).
#
# Usage:
#   monitor-mode.sh desktop    # 3-across, all landscape (manual only, via Super+M)
#   monitor-mode.sh read       # portable QHD rotated to portrait in the middle
#   monitor-mode.sh laptop     # integrated screen only (no externals)
#   monitor-mode.sh onescreen  # one external screen + laptop, side by side
#   monitor-mode.sh trio       # both 16" portables + laptop, laptop in the middle
#   monitor-mode.sh toggle     # flip desktop<->read at the desk, trio<->read on
#                              # the road (default if no arg)
#
# Applies via `hyprctl keyword`, so nothing here is persistent — a `hyprctl
# reload` or relog returns to whatever monitors.conf says. To make a profile
# the boot default, point the `source = .../monitors.conf` line (or copy the
# profile over monitors.conf).

set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"

# Identify the externals by capability, not port name — DP-1/DP-2 shift with
# plug order (the QHD portable has enumerated as both). Sets globals:
#   EXT_QHD         the external that can do 2560x1600 (the QHD portable), or empty
#   EXT_OTHER       the first remaining external (the Xiaomi 27" 4K at the desk,
#                   demoset FHD portable on the road, whatever else otherwise), empty
#   EXT_OTHER_MODE  EXT_OTHER's best mode "WxH@R": highest resolution, then
#                   highest refresh. NOT Hyprland's `highrr` (which picks max
#                   refresh regardless of resolution — the demoset panel's
#                   800x600@60.32 outranks its 1920x1080@60.00 there) and NOT
#                   `preferred` (the old Samsung preferred 1080p@60 over its 120Hz).
#   EXT_OTHER_SCALE the scale EXT_OTHER renders at: 1.25 for a 4K-class panel
#                   (>=3840 wide, e.g. the Xiaomi -> 3072x1728), else 1 (1080p FHD).
#   EXT_OTHER_W     EXT_OTHER's LOGICAL width (physical width / scale) = the x-offset
#                   where the neighbouring monitor starts.
resolve_externals() {
  local mons
  mons="$(hyprctl monitors all -j)"
  EXT_QHD="$(jq -r '[.[] | select(.name != "eDP-1")
                         | select(any(.availableModes[]?; startswith("2560x1600")))]
                    | .[0].name // empty' <<<"$mons")"
  EXT_OTHER="$(jq -r --arg q "${EXT_QHD:-none}" \
                   '[.[] | select(.name != "eDP-1" and .name != $q)]
                    | .[0].name // empty' <<<"$mons")"
  EXT_OTHER_MODE="$(jq -r --arg n "${EXT_OTHER:-none}" '
      [.[] | select(.name == $n)] | .[0].availableModes // []
      | map(capture("(?<w>[0-9]+)x(?<h>[0-9]+)@(?<r>[0-9.]+)Hz")
            | {w: (.w|tonumber), h: (.h|tonumber), r: (.r|tonumber)})
      | sort_by(.w * .h, .r) | last
      | if . == null then empty else "\(.w)x\(.h)@\(.r)" end' <<<"$mons")"
  if [[ -z "$EXT_OTHER_MODE" ]]; then
    EXT_OTHER_MODE="preferred"
    EXT_OTHER_SCALE=1
    EXT_OTHER_W=1920
  else
    local _w="${EXT_OTHER_MODE%%x*}"
    # 4K-class externals (>=3840 wide, e.g. the Xiaomi 27") render at scale 1.25
    # to match the eDP-1/QHD panels; 1080p-class stays at scale 1. EXT_OTHER_W is
    # the LOGICAL width (physical / scale) used as the neighbour's x-offset.
    if (( _w >= 3840 )); then
      EXT_OTHER_SCALE=1.25
    else
      EXT_OTHER_SCALE=1
    fi
    EXT_OTHER_W="$(awk -v w="$_w" -v s="$EXT_OTHER_SCALE" 'BEGIN{printf "%d", int(w/s + 0.5)}')"
  fi
}

apply_desktop() {
  hyprctl --batch "\
    keyword monitor eDP-1,2560x1600@240,0x0,1.25 ; \
    keyword monitor DP-1,1920x1080@120,2048x0,1 ; \
    keyword monitor DP-2,2560x1600@120,3968x0,1.25"
  echo desktop > "$STATE"
  notify-send -t 2000 "Monitors" "Desktop layout (3-across)" 2>/dev/null || true
}

apply_read() {
  # Laptop screen OFF — only the two externals: the non-QHD one landscape on the
  # left at its best mode and scale (the Xiaomi 27" 4K @ 3072x1728 scale 1.25 at
  # the desk, demoset FHD@60 scale 1 on the road) + the QHD portable rotated to
  # portrait (right). Disabling eDP-1 orphans workspaces 4–5 (bound to it in
  # monitors.conf); Hyprland auto-relocates them to a live monitor and re-homes
  # them when eDP-1 returns under another profile.
  resolve_externals
  if [[ -n "$EXT_QHD" && -n "$EXT_OTHER" ]]; then
    hyprctl --batch "\
      keyword monitor $EXT_OTHER,$EXT_OTHER_MODE,0x0,$EXT_OTHER_SCALE ; \
      keyword monitor $EXT_QHD,2560x1600@120,${EXT_OTHER_W}x0,1.25,transform,3 ; \
      keyword monitor eDP-1,disable"
  else
    # Externals didn't resolve (no QHD-capable panel found) — fall back to the
    # historical name-bound desk geometry rather than doing nothing.
    hyprctl --batch "\
      keyword monitor DP-1,1920x1080@120,0x0,1 ; \
      keyword monitor DP-2,2560x1600@120,1920x0,1.25,transform,3 ; \
      keyword monitor eDP-1,disable"
  fi
  echo read > "$STATE"
  notify-send -t 2000 "Monitors" "Read layout (laptop off · two externals)" 2>/dev/null || true
}

apply_laptop() {
  hyprctl --batch "keyword monitor eDP-1,2560x1600@240,0x0,1.25"
  echo laptop > "$STATE"
  notify-send -t 2000 "Monitors" "Laptop only (integrated screen)" 2>/dev/null || true
}

apply_onescreen() {
  # Exactly ONE external screen detected + the laptop: external on the left,
  # laptop to its right. Works for whichever external happens to be connected.
  local names
  names="$(hyprctl monitors -j | jq -r '.[].name')"
  if grep -qx 'DP-1' <<<"$names"; then
    # Samsung FHD (1920 logical wide @ scale 1) | laptop at 1920
    hyprctl --batch "\
      keyword monitor DP-1,1920x1080@120,0x0,1 ; \
      keyword monitor eDP-1,2560x1600@240,1920x0,1.25"
  elif grep -qx 'DP-2' <<<"$names"; then
    # Portable QHD landscape (2048 logical wide @ scale 1.25) | laptop at 2048
    hyprctl --batch "\
      keyword monitor DP-2,2560x1600@120,0x0,1.25 ; \
      keyword monitor eDP-1,2560x1600@240,2048x0,1.25"
  else
    # Safety net: no external present -> laptop only
    hyprctl --batch "keyword monitor eDP-1,2560x1600@240,0x0,1.25"
  fi
  echo onescreen > "$STATE"
  notify-send -t 2000 "Monitors" "One external + laptop" 2>/dev/null || true
}

apply_trio() {
  # Road setup: both 16" portables + the laptop, three across, laptop in the
  # middle. Layout: FHD (left, best mode, 1920 logical) | laptop (center,
  # 2048 logical) | QHD (right). Swap the x offsets below to rearrange.
  resolve_externals
  if [[ -n "$EXT_QHD" && -n "$EXT_OTHER" ]]; then
    hyprctl --batch "\
      keyword monitor $EXT_OTHER,$EXT_OTHER_MODE,0x0,1 ; \
      keyword monitor eDP-1,2560x1600@240,${EXT_OTHER_W}x0,1.25 ; \
      keyword monitor $EXT_QHD,2560x1600@120,$((EXT_OTHER_W + 2048))x0,1.25"
    notify-send -t 2000 "Monitors" "Trio layout (FHD · laptop · QHD)" 2>/dev/null || true
  else
    # No QHD-capable external (e.g. demoset + a hotel TV) — apply a generic
    # layout instead of erroring out: laptop left, every external at its
    # preferred mode to the right. Must NOT exit non-zero without writing
    # $STATE: the autoswitcher would then re-attempt trio on every hotplug
    # event forever, spamming notifications and never converging.
    local batch ext
    batch="keyword monitor eDP-1,2560x1600@240,0x0,1.25"
    while read -r ext; do
      [[ -n "$ext" ]] && batch+=" ; keyword monitor $ext,preferred,auto,1"
    done < <(hyprctl monitors all -j | jq -r '.[] | select(.name != "eDP-1") | .name')
    hyprctl --batch "$batch"
    notify-send -t 2000 "Monitors" "Trio layout (generic: laptop + externals)" 2>/dev/null || true
  fi
  echo trio > "$STATE"
}

mode="${1:-toggle}"

if [[ "$mode" == "toggle" ]]; then
  current="$(cat "$STATE" 2>/dev/null || echo desktop)"
  if [[ "$current" == "read" ]]; then
    # Leaving read mode: at the desk that means the 3-across desktop; on the
    # road (demoset FHD portable connected) it means the trio instead.
    if hyprctl monitors -j | jq -e 'any(.[]; (.description // "") | test("demoset"))' >/dev/null; then
      mode=trio
    else
      mode=desktop
    fi
  else
    mode=read
  fi
fi

case "$mode" in
  desktop)   apply_desktop ;;
  read)      apply_read ;;
  laptop)    apply_laptop ;;
  onescreen) apply_onescreen ;;
  trio)      apply_trio ;;
  *) echo "usage: $0 {desktop|read|laptop|onescreen|trio|toggle}" >&2; exit 1 ;;
esac

# swayosd 0.3.1 aborts on the monitor-set change we just made (gtk4-layer-shell
# re-inits its windows on the GdkDisplay "monitors changed" signal and the
# Wayland roundtrip SIGABRTs). Its systemd unit has Restart=always, but restart
# it explicitly now — after the new layout has settled — so a healthy OSD server
# is bound to the final monitor set immediately, instead of waiting on the
# crash+respawn cycle. Without this, media keys / OSD go dead after every switch.
sleep 0.4
systemctl --user restart swayosd.service 2>/dev/null || true
