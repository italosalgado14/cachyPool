#!/usr/bin/env bash
# monitor-mode.sh — switch between monitor layout profiles live (no logout).
#
# Usage:
#   monitor-mode.sh desktop    # 3-across, all landscape (manual only, via Super+M)
#   monitor-mode.sh read       # portable QHD rotated to portrait in the middle
#   monitor-mode.sh laptop     # integrated screen only (no externals)
#   monitor-mode.sh onescreen  # one external screen + laptop, side by side
#   monitor-mode.sh toggle     # flip between desktop and read (default if no arg)
#
# Applies via `hyprctl keyword`, so nothing here is persistent — a `hyprctl
# reload` or relog returns to whatever monitors.conf says. To make a profile
# the boot default, point the `source = .../monitors.conf` line (or copy the
# profile over monitors.conf).

set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"

apply_desktop() {
  hyprctl --batch "\
    keyword monitor eDP-1,2560x1600@240,0x0,1.25 ; \
    keyword monitor DP-1,1920x1080@120,2048x0,1 ; \
    keyword monitor DP-2,2560x1600@120,3968x0,1.25"
  echo desktop > "$STATE"
  notify-send -t 2000 "Monitors" "Desktop layout (3-across)" 2>/dev/null || true
}

apply_read() {
  hyprctl --batch "\
    keyword monitor DP-1,1920x1080@120,0x0,1 ; \
    keyword monitor DP-2,2560x1600@120,1920x0,1.25,transform,3 ; \
    keyword monitor eDP-1,2560x1600@240,3200x0,1.25"
  echo read > "$STATE"
  notify-send -t 2000 "Monitors" "Read layout (portable rotated portrait)" 2>/dev/null || true
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

mode="${1:-toggle}"

if [[ "$mode" == "toggle" ]]; then
  current="$(cat "$STATE" 2>/dev/null || echo desktop)"
  if [[ "$current" == "read" ]]; then mode=desktop; else mode=read; fi
fi

case "$mode" in
  desktop)   apply_desktop ;;
  read)      apply_read ;;
  laptop)    apply_laptop ;;
  onescreen) apply_onescreen ;;
  *) echo "usage: $0 {desktop|read|laptop|onescreen|toggle}" >&2; exit 1 ;;
esac
