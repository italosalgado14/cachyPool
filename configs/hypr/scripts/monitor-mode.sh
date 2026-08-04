#!/usr/bin/env bash
# monitor-mode.sh — switch between monitor layout profiles live (no logout).
#
# Usage:
#   monitor-mode.sh desktop    # 3-across, all landscape (manual only, via Super+M)
#   monitor-mode.sh read       # portable QHD rotated to portrait in the middle
#                              # (the QHD portable is a VCHANCE AQ16H 16" 2560x1600)
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

# Written only when apply_monitor_tf actually cycles an output (see below).
# monitor-autoswitch.sh reads it to recognise that cycle's hotplug events as
# self-inflicted instead of treating them as a real plug/unplug.
FPFILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-fingerprint"
CYCLED=0

# Identity of the enabled monitor set — name + description, order independent.
# Must stay byte-identical to monitor_fingerprint() in monitor-autoswitch.sh:
# the two are compared as strings across the two scripts.
monitor_fingerprint() {
  hyprctl monitors -j 2>/dev/null \
    | jq -Sc 'sort_by(.name) | map({name, description})' 2>/dev/null
}

# Apply a monitor spec whose TRANSFORM may differ from what the output is
# currently running, cycling the output off and on when it does.
#
# WHY (2026-08-04) — `hyprctl keyword monitor <name>,...,transform,N` against an
# output that is ALREADY ENABLED rotates the render pass but does NOT rebuild the
# monitor's layout box. The tiling engine keeps handing out the pre-rotation
# geometry, so on the portrait VCHANCE AQ16H a window came out 2028x1224 on a
# 1280x2048 screen — landscape content spilling 758px past the right edge, while
# `hyprctl monitors` cheerfully reported `transform 3`. That mismatch is why the
# panel looked correctly configured and was not. The bug is SYMMETRIC: leaving
# portrait for a landscape profile strands a 1280x2048 box on a 2048x1280 screen,
# so every profile that puts a transform on the QHD goes through this function,
# including the ones that want transform 0.
#
# Verified non-fixes — do not swap one of these back in: `dispatch
# forcerendererreload`, `dispatch moveworkspacetomonitor`, and re-applying the
# identical spec a second time all leave the stale box in place. Only a
# disable -> re-enable rebuilds it.
#
# Cycle ONLY when the transform actually changes: it blanks the output for a
# moment and posts external monitorremoved/monitoradded events. Workspaces bound
# to the panel by `desc:` in monitors.conf re-home themselves when it returns, so
# nothing has to be moved back by hand.
apply_monitor_tf() {
  local name="$1" spec="$2" want="$3" cur
  # `|| cur=""` matters: this script runs under `set -euo pipefail`, so a bare
  # failing command substitution (hyprctl not answering) would abort the whole
  # mode switch mid-layout instead of falling through to a plain apply.
  cur="$(hyprctl monitors -j 2>/dev/null \
         | jq -r --arg n "$name" \
             '[.[] | select(.name == $n)] | .[0].transform // empty' 2>/dev/null)" || cur=""
  # Empty $cur = the output is currently disabled; enabling it builds a fresh
  # box anyway, so no cycle is needed.
  if [[ -n "$cur" && "$cur" != "$want" ]]; then
    hyprctl keyword monitor "$name,disable" >/dev/null
    sleep 0.3
    CYCLED=1
  fi
  hyprctl keyword monitor "$spec" >/dev/null
}

# Identify the externals by capability, not port name — DP-1/DP-2 shift with
# plug order (the QHD portable has enumerated as both). Sets globals:
#   EXT_QHD         the external that can do 2560x1600 (the VCHANCE AQ16H 16"
#                   QHD portable), or empty
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
  # 3-across, all landscape: laptop (left, 2048 logical) | desk external
  # (center, at its best mode and scale) | QHD portable (right).
  # Resolved by capability so it follows the Xiaomi 27" 4K wherever it
  # enumerates. The pre-2026-08-03 version hardcoded DP-1 to the retired
  # Samsung's 1920x1080@120 scale 1 and forced whatever landed on DP-1 into it.
  resolve_externals
  if [[ -n "$EXT_QHD" && -n "$EXT_OTHER" ]]; then
    hyprctl --batch "\
      keyword monitor eDP-1,2560x1600@240,0x0,1.25 ; \
      keyword monitor $EXT_OTHER,$EXT_OTHER_MODE,2048x0,$EXT_OTHER_SCALE"
    # transform 0 stated explicitly and routed through apply_monitor_tf: coming
    # back from 'read' this has to UNDO a rotation, which needs the same output
    # cycle as applying one. Omitting it left the AQ16H rendering landscape with
    # a 1280x2048 portrait layout box.
    apply_monitor_tf "$EXT_QHD" \
      "$EXT_QHD,2560x1600@120,$((2048 + EXT_OTHER_W))x0,1.25,transform,0" 0
  else
    # Fewer than two resolvable externals — lay the connected ones out generically
    # rather than forcing a geometry no attached panel can actually do.
    local batch ext
    batch="keyword monitor eDP-1,2560x1600@240,0x0,1.25"
    while read -r ext; do
      [[ -n "$ext" ]] && batch+=" ; keyword monitor $ext,preferred,auto,1"
    done < <(hyprctl monitors all -j | jq -r '.[] | select(.name != "eDP-1") | .name')
    hyprctl --batch "$batch"
  fi
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
    hyprctl keyword monitor "$EXT_OTHER,$EXT_OTHER_MODE,0x0,$EXT_OTHER_SCALE" >/dev/null
    # Not batched with the others any more: the rotation has to go through
    # apply_monitor_tf, which may cycle the output to rebuild its layout box.
    apply_monitor_tf "$EXT_QHD" \
      "$EXT_QHD,2560x1600@120,${EXT_OTHER_W}x0,1.25,transform,3" 3
    hyprctl keyword monitor "eDP-1,disable" >/dev/null
  else
    # No QHD-capable panel resolved. Lay out whatever externals are attached at
    # their preferred mode and turn the laptop off — but NEVER disable eDP-1
    # when there is no external to fall back to: 'read' is also reachable from
    # Super+M, and disabling the only live output blacks the session with no way
    # back. The pre-2026-08-03 fallback hardcoded the retired Samsung's DP-1
    # geometry and had exactly that landmine.
    local batch ext n
    batch=""; n=0
    while read -r ext; do
      [[ -n "$ext" ]] || continue
      batch+="keyword monitor $ext,preferred,auto,1 ; "
      n=$((n + 1))
    done < <(hyprctl monitors all -j | jq -r '.[] | select(.name != "eDP-1") | .name')
    if (( n > 0 )); then
      hyprctl --batch "${batch}keyword monitor eDP-1,disable"
    else
      hyprctl --batch "keyword monitor eDP-1,2560x1600@240,0x0,1.25"
    fi
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
  # Exactly ONE external + the laptop, side by side: external on the left,
  # laptop to its right at the external's LOGICAL width.
  # Resolved by capability. The pre-2026-08-03 version keyed off the literal
  # names DP-1/DP-2 and pinned DP-1 to the retired Samsung's 1920x1080@120
  # scale 1 — so a QHD portable or the Xiaomi 4K that happened to enumerate as
  # DP-1 got forced to 1080p at the wrong scale. Port names float here (both
  # externals are DP tunnels over one Thunderbolt connector), so that fired on
  # ordinary replugs, not just exotic ones.
  resolve_externals
  local ext mode scale w
  if [[ -n "$EXT_QHD" ]]; then
    ext="$EXT_QHD"; mode="2560x1600@120"; scale=1.25; w=2048
  elif [[ -n "$EXT_OTHER" ]]; then
    ext="$EXT_OTHER"; mode="$EXT_OTHER_MODE"; scale="$EXT_OTHER_SCALE"; w="$EXT_OTHER_W"
  else
    ext=""
  fi
  if [[ -n "$ext" ]]; then
    if [[ "$ext" == "$EXT_QHD" ]]; then
      # The AQ16H may be arriving straight out of 'read' still rotated — undo it
      # through apply_monitor_tf so the layout box is rebuilt, not just the
      # render transform.
      apply_monitor_tf "$ext" "$ext,$mode,0x0,$scale,transform,0" 0
    else
      hyprctl keyword monitor "$ext,$mode,0x0,$scale" >/dev/null
    fi
    hyprctl keyword monitor "eDP-1,2560x1600@240,${w}x0,1.25" >/dev/null
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
      keyword monitor eDP-1,2560x1600@240,${EXT_OTHER_W}x0,1.25"
    # Same reason as apply_desktop: 'trio' may follow 'read', so the AQ16H's
    # rotation has to be undone through apply_monitor_tf.
    apply_monitor_tf "$EXT_QHD" \
      "$EXT_QHD,2560x1600@120,$((EXT_OTHER_W + 2048))x0,1.25,transform,0" 0
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

sleep 0.4

# If apply_monitor_tf cycled an output, record the monitor set we are leaving
# behind so monitor-autoswitch.sh can tell those hotplug events apart from a real
# plug/unplug. Without this handshake, a manual Super+M 'desktop' would cycle the
# AQ16H, the autoswitcher would see an external monitoradded, and desired_mode()
# — which always answers 'read' for two desk externals — would yank the layout
# back to 'read' about three seconds later.
#
# Timing: the autoswitcher only reads this after its own >=3s settle window
# (SETTLE 2s of quiet + a CONFIRM round), and we get here roughly 1s after the
# cycle, so the file is always in place first.
#
# When nothing was cycled the file is REMOVED rather than refreshed: a stale
# fingerprint that still matched would suppress the forced re-apply that a real
# display blink needs (Hyprland reconfigures a returning output from
# monitors.conf, so a blink has to be re-applied even though the monitor set is
# unchanged — see apply_if_changed in monitor-autoswitch.sh).
if (( CYCLED )); then
  monitor_fingerprint > "$FPFILE" 2>/dev/null || true
else
  rm -f "$FPFILE" 2>/dev/null || true
fi

# swayosd 0.3.1 aborts on the monitor-set change we just made (gtk4-layer-shell
# re-inits its windows on the GdkDisplay "monitors changed" signal and the
# Wayland roundtrip SIGABRTs). Its systemd unit has Restart=always, but restart
# it explicitly now — after the new layout has settled — so a healthy OSD server
# is bound to the final monitor set immediately, instead of waiting on the
# crash+respawn cycle. Without this, media keys / OSD go dead after every switch.
systemctl --user restart swayosd.service 2>/dev/null || true
