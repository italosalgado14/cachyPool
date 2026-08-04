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
# eDP-1 events are ignored (see parse_event below for why).
#
# Geometry lives in monitor-mode.sh — this script only decides which to apply.
#
# DEBOUNCE (2026-08-03) — why this is not a plain "react to each event" loop:
# both externals reach this machine as DP tunnels over ONE Thunderbolt
# connector (Plugable TBT4-UD5 on typec port0). Anything that upsets that
# connector can drop and restore both tunnels within a second or two: a USB
# device failing to enumerate on the same xHCI (0000:00:14.0 — a Kobo e-reader
# did exactly this, four failed attempts plus a port power cycle), a cable
# jiggle, an s2idle resume. The old loop acted on every raw event after a flat
# `sleep 0.5`, so one blink became
#     monitorremoved -> apply 'onescreen' -> monitoradded -> apply 'read'
# which forced wrong geometry on the way through and scattered workspaces.
# Now an event burst is coalesced and the monitor set must prove stable before
# anything is applied, so a blink resolves to a no-op. Cost: a real plug or
# unplug now takes ~3s to take effect instead of ~0.5s.

set -uo pipefail

MODE_SCRIPT="$HOME/.config/hypr/scripts/monitor-mode.sh"
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"
FPFILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-fingerprint"

SETTLE=2         # seconds of socket quiet that ends an event burst
CONFIRM=1        # seconds between the two identical samples that prove stability
CONFIRM_TRIES=5  # stop trying to prove stability after this many rounds, act anyway
SELF_GRACE=15    # seconds a $FPFILE stays valid as proof of a self-inflicted cycle

# Identity of the currently enabled monitor set — name + description, order
# independent. Used ONLY to answer "has this settled yet", never to pick a mode.
# Must stay byte-identical to the copy in monitor-mode.sh — the two are compared
# as strings across the scripts (see self_inflicted below).
monitor_fingerprint() {
  hyprctl monitors -j 2>/dev/null \
    | jq -Sc 'sort_by(.name) | map({name, description})' 2>/dev/null
}

# Was the burst we just settled caused by monitor-mode.sh itself?
#
# monitor-mode.sh cycles an output off and on to rebuild its layout box whenever
# a profile changes the AQ16H's rotation (see apply_monitor_tf there — Hyprland
# will not rebuild the box for a live `transform` keyword). That cycle posts
# external monitorremoved+monitoradded, indistinguishable from a real replug at
# the socket. Reacting to it would undo every manual Super+M choice that changes
# the rotation: 'desktop' un-rotates the AQ16H, so its cycle would wake us and
# desired_mode() — which always answers 'read' for two desk externals — would
# drag the layout back to 'read' a few seconds later.
#
# Two conditions, both required:
#   * $FPFILE is FRESH. monitor-mode.sh writes it only when it actually cycled,
#     and deletes it otherwise, so an old file can never suppress a real event.
#   * the settled monitor set MATCHES what monitor-mode.sh recorded. A real
#     unplug changes the set and is therefore still acted on even inside the
#     grace window.
# A blink that resolves to the same set does NOT land here (no cycle -> no
# $FPFILE), so it still gets the forced re-apply it needs.
self_inflicted() {
  local mt now
  [[ -f "$FPFILE" ]] || return 1
  mt="$(stat -c %Y "$FPFILE" 2>/dev/null || echo 0)"
  now="$(date +%s)"
  (( now - mt <= SELF_GRACE )) || return 1
  [[ "$(monitor_fingerprint)" == "$(cat "$FPFILE" 2>/dev/null)" ]]
}

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

# force=1 re-applies the profile even when the mode NAME is unchanged. Required
# whenever a monitor was ADDED: Hyprland configures a returning output from
# monitors.conf, so after a blink the screens sit at the monitors.conf desktop
# geometry while $STATE still says 'read'. Without the force, the debounce above
# would correctly decide "same mode" and leave the wrong geometry on screen.
apply_if_changed() {
  local force="${1:-0}" want cur
  want="$(desired_mode)"
  cur="$(cat "$STATE" 2>/dev/null || echo '')"
  if [[ "$want" != "$cur" || "$force" == 1 ]]; then
    "$MODE_SCRIPT" "$want"
  fi
}

# Parse one raw .socket2 line. Sets $EV and $MON; returns 1 for anything that is
# not an EXTERNAL monitor add/remove.
# v1 event payload is the monitor name; v2 payload is "id,name,description".
parse_event() {
  local payload
  EV="${1%%>>*}"
  payload="${1#*>>}"
  case "$EV" in
    monitoradded|monitorremoved)     MON="$payload" ;;
    monitoraddedv2|monitorremovedv2) MON="$(cut -d, -f2 <<<"$payload")" ;;
    *) return 1 ;;
  esac
  # IGNORE events for eDP-1. The built-in panel is never physically hotplugged;
  # add/remove events for it are the mode script's own keyword-driven
  # disable/enable (Hyprland posts hotplug events for those too). Reacting to
  # them would instantly revert every manual Super+M choice that toggles the
  # laptop panel: read->desktop at the desk (desktop enables eDP-1 ->
  # monitoradded -> autoswitch re-applies read) and trio->read on the road
  # (read disables eDP-1 -> monitorremoved -> re-applies trio).
  [[ "$MON" == "eDP-1" ]] && return 1
  return 0
}

# Swallow the rest of an event burst, then wait for the monitor set to hold
# still. Sets SAW_ADD=1 if any external (re)appeared anywhere in the burst.
settle() {
  local drained fp1 fp2 i
  # 1. Coalesce: keep reading until the socket has been quiet for $SETTLE.
  while read -r -t "$SETTLE" drained; do
    parse_event "$drained" || continue
    [[ "$EV" == monitoradded* ]] && SAW_ADD=1
  done
  # 2. Confirm: two identical fingerprints $CONFIRM apart. A dock renegotiation
  #    can bounce for several seconds; acting mid-bounce is what produced the
  #    wrong geometry in the first place.
  for ((i = 0; i < CONFIRM_TRIES; i++)); do
    fp1="$(monitor_fingerprint)"
    sleep "$CONFIRM"
    fp2="$(monitor_fingerprint)"
    [[ -n "$fp1" && "$fp1" == "$fp2" ]] && return 0
  done
  return 0
}

# Apply once at startup, unconditionally: $STATE lives in $XDG_RUNTIME_DIR and
# survives a compositor restart (Super+Shift+Q), so a plain "has the mode
# changed" test would skip the apply and leave monitors.conf geometry standing.
apply_if_changed 1

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - "UNIX-CONNECT:$SOCK" 2>/dev/null | while read -r line; do
  parse_event "$line" || continue
  SAW_ADD=0
  [[ "$EV" == monitoradded* ]] && SAW_ADD=1
  settle
  # monitor-mode.sh's own rotation cycle, not a real plug/unplug — leave the
  # layout it just applied alone.
  self_inflicted && continue
  apply_if_changed "$SAW_ADD"
done
