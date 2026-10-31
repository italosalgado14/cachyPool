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
#   monitor-mode.sh edp-rate   # reconcile ONLY the laptop panel's refresh rate
#                              # with the power source (240 Hz on AC, 60 Hz on
#                              # battery). Not a layout; see the block above the
#                              # dispatch. Called by power-autoswitch.sh.
#
# Applies via `hyprctl keyword`, so nothing here is persistent — a `hyprctl
# reload` or relog returns to whatever monitors.conf says. To make a profile
# the boot default, point the `source = .../monitors.conf` line (or copy the
# profile over monitors.conf).
#
# Geometry source: if ~/.config/hyprmon/profiles/<mode>.json exists and covers
# exactly the connected monitors, its positions/scales/rotations are applied
# (edit them visually with hyprmon-edit.sh, save with `P` under the mode's
# name). Otherwise the hand-written apply_<mode> below runs. See
# apply_from_profile.

set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"

# Written only when apply_monitor_tf actually cycles an output (see below).
# monitor-autoswitch.sh reads it to recognise that cycle's hotplug events as
# self-inflicted instead of treating them as a real plug/unplug.
FPFILE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-fingerprint"
CYCLED=0

# --------------------------------------------------------------------------- #
# eDP-1's refresh rate — ONE owner (2026-10-31)
#
# The built-in panel has exactly two modes: 2560x1600@240 and 2560x1600@60.
# Running it at 60 on battery is the cheapest real saving available on this
# machine, so the rate is not a constant any more: it is resolved from the power
# source by edp_mode() and EVERY site that emits an eDP-1 spec must call it.
#
# Do not reintroduce a `2560x1600@240` literal. Before this existed the string
# was repeated at 8 sites here plus a 9th path through apply_from_profile (which
# emits .Hz straight out of the hyprmon JSON, where desktop.json carries
# 240.00301), so anything setting the rate from outside was undone by the next
# profile apply, hotplug autoswitch or `hyprctl reload`.
#
# "On battery" is the SAME test hypridle's suspend listener uses, deliberately:
# BAT1/status covers barrel AC, USB-C PD and dock power alike, whereas
# ACAD/online reads 1 when only the TB4 dock is feeding the machine.
EDP_PREF="${XDG_CONFIG_HOME:-$HOME/.config}/triton-panel/power-auto"
EDP_HI="2560x1600@240"
EDP_LO="2560x1600@60"

on_battery() {
  grep -q Discharging /sys/class/power_supply/BAT1/status 2>/dev/null
}

# Absent pref file means ENABLED: the automatic saving is the default, and a
# fresh checkout must behave the same as a configured one. The `|| echo 1`
# matters under `set -euo pipefail` — a missing file must not abort the switch.
power_auto() {
  [[ "$(cat "$EDP_PREF" 2>/dev/null || echo 1)" != 0 ]]
}

edp_mode() {
  if power_auto && on_battery; then printf '%s' "$EDP_LO"; else printf '%s' "$EDP_HI"; fi
}

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

# Hyprmon-edited geometry (2026-10-15). A hyprmon profile named after the mode
# (~/.config/hyprmon/profiles/<mode>.json, saved from the TUI with `P`) replaces
# the hand-written layout of that mode: hyprmon is the visual EDITOR, this
# script stays the APPLIER. Never use `hyprmon --profile` or its `S` key — both
# set the transform with a bare keyword (the stale-layout-box bug above),
# rewrite a Hyprland config file and `hyprctl reload` on every switch. Launch
# hyprmon through hyprmon-edit.sh, which neuters the reload.
#
# The JSON is used only when its monitor set is EXACTLY the connected set,
# matched by hyprmon's own hardware_id (make/model/serial from the EDID, built
# like buildHardwareID in hyprmon's hardware_id.go), so DP-1/DP-2 order never
# matters. Anything else — an unknown hotel monitor, the demoset portable with
# no saved trio — returns 1 and the capability-resolved apply_<mode> runs
# instead. A profile can only ever refine a known desk, never break a new one.
#
# Every active output goes through apply_monitor_tf with its transform spelled
# out (0 included), so the disable -> re-enable cycle and the $FPFILE handshake
# keep working. Inactive outputs are disabled last, so the session never drops
# to zero monitors. vrr/bitdepth/cm from the JSON are ignored on purpose: the
# hand-written profiles never set them either.
PROFILE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyprmon/profiles"

apply_from_profile() {
  local mode="$1" file mons plan name active spec tf edphz
  file="$PROFILE_DIR/$mode.json"
  [[ -f "$file" ]] || return 1
  mons="$(hyprctl monitors all -j 2>/dev/null)" || return 1
  # Just the Hz out of edp_mode()'s "2560x1600@<hz>" — jq compares it numerically.
  edphz="$(edp_mode)"; edphz="${edphz##*@}"

  # One TSV line per profile monitor — connector, active, spec, transform —
  # active ones first. Empty output = the profile doesn't fit what's connected.
  # Hz is rounded to 2 decimals in jq rather than with printf, which would follow
  # the locale's decimal separator.
  #
  # eDP-1's Hz is OVERRIDDEN with $edphz rather than taken from the JSON. This is
  # the 9th emit site for the laptop panel's rate and the easiest to miss: the
  # profiles were saved by hyprmon while docked on AC, so desktop.json carries
  # eDP-1 at 240.00301, and without this override every docked profile apply
  # would quietly put the panel back to 240 Hz while on battery. The externals
  # keep their own JSON rate — only the built-in panel is power-managed.
  plan="$(jq -r --slurpfile p "$file" --argjson edphz "$edphz" '
      def hwid: [(.make // ""), (.model // ""), (.serial // "")]
                | map(tostring | gsub("^\\s+|\\s+$"; ""))
                | if .[0] == "" and .[1] == "" then ""
                  elif .[2] == "" then "\(.[0])/\(.[1])"
                  else join("/") end;
      ($p[0].monitors // []) as $prof
      | (map({key: hwid, value: .name}) | from_entries) as $conn
      | ([.[] | hwid] | sort) as $have
      | ([$prof[] | .hardware_id // ""] | sort) as $want
      | if $have != $want or any($want[]; . == "")
           or ([$prof[] | select(.Active)] | length) == 0
        then empty
        else ($prof | sort_by(if .Active then 0 else 1 end))[]
             | $conn[.hardware_id] as $n
             | (if $n == "eDP-1" then $edphz
                else ((.Hz * 100 | round) / 100) end) as $hz
             | [$n, (.Active | tostring),
                "\($n),\(.PxW)x\(.PxH)@\($hz),\(.X)x\(.Y),\(.Scale)",
                (.Transform // 0 | tostring)]
             | @tsv
        end' <<<"$mons" 2>/dev/null)" || plan=""
  [[ -n "$plan" ]] || return 1

  while IFS=$'\t' read -r name active spec tf; do
    if [[ "$active" == true ]]; then
      apply_monitor_tf "$name" "$spec,transform,$tf" "$tf"
    else
      hyprctl keyword monitor "$name,disable" >/dev/null
    fi
  done <<<"$plan"

  echo "$mode" > "$STATE"
  notify-send -t 2000 "Monitors" "${mode^} layout (hyprmon profile)" 2>/dev/null || true
  # Always 0 once applying started: a non-zero return here would make the
  # caller's `|| apply_<mode>` lay the hand-written geometry on top.
  return 0
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
      keyword monitor eDP-1,$(edp_mode),0x0,1.25 ; \
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
    batch="keyword monitor eDP-1,$(edp_mode),0x0,1.25"
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
      hyprctl --batch "keyword monitor eDP-1,$(edp_mode),0x0,1.25"
    fi
  fi
  echo read > "$STATE"
  notify-send -t 2000 "Monitors" "Read layout (laptop off · two externals)" 2>/dev/null || true
}

apply_laptop() {
  hyprctl --batch "keyword monitor eDP-1,$(edp_mode),0x0,1.25"
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
    hyprctl keyword monitor "eDP-1,$(edp_mode),${w}x0,1.25" >/dev/null
  else
    # Safety net: no external present -> laptop only
    hyprctl --batch "keyword monitor eDP-1,$(edp_mode),0x0,1.25"
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
      keyword monitor eDP-1,$(edp_mode),${EXT_OTHER_W}x0,1.25"
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
    batch="keyword monitor eDP-1,$(edp_mode),0x0,1.25"
    while read -r ext; do
      [[ -n "$ext" ]] && batch+=" ; keyword monitor $ext,preferred,auto,1"
    done < <(hyprctl monitors all -j | jq -r '.[] | select(.name != "eDP-1") | .name')
    hyprctl --batch "$batch"
    notify-send -t 2000 "Monitors" "Trio layout (generic: laptop + externals)" 2>/dev/null || true
  fi
  echo trio > "$STATE"
}

mode="${1:-toggle}"

# --------------------------------------------------------------------------- #
# edp-rate — re-emit ONLY eDP-1's refresh rate at whatever edp_mode() resolves,
# keeping its current position and scale. This is the reconcile hook
# power-autoswitch.sh calls; it is not a layout profile and deliberately does
# NOT touch $STATE, the fingerprint handshake or swayosd, so it can run every
# few seconds without the autoswitcher ever seeing it.
#
# Three guards, each for a failure found while building this:
#
#   1. eDP-1 must be in `hyprctl monitors -j` (ENABLED outputs only, never
#      `monitors all`). In 'read' mode the laptop panel is deliberately
#      disabled, and `hyprctl keyword monitor eDP-1,<mode>,...` against a
#      disabled output does not set a rate — it ENABLES the output. That would
#      silently undo 'read' every 5 seconds.
#   2. Skip while DPMS is off. A modeset wakes the panel, so reconciling under
#      hypridle's 10-minute DPMS-off would turn the screen back on by itself.
#   3. Only emit when the rate actually differs. Hyprland is not relied on to
#      deduplicate an identical keyword, and a real modeset every 5 s would
#      flicker the panel and flood the log.
if [[ "$mode" == "edp-rate" ]]; then
  want="$(edp_mode)"; want_hz="${want##*@}"
  read -r cur_hz cur_x cur_y cur_scale cur_dpms < <(
    hyprctl monitors -j 2>/dev/null \
      | jq -r '.[] | select(.name=="eDP-1")
               | "\(.refreshRate|round) \(.x) \(.y) \(.scale) \(.dpmsStatus)"' 2>/dev/null
  ) || exit 0
  # Written as `if` blocks, not `(( )) && exit`: under `set -e` a bare failing
  # arithmetic test as the first element of an AND-OR list is a foot-gun.
  if [[ -z "${cur_hz:-}" ]]; then exit 0; fi                  # guard 1
  # jq prints `null` for a monitor with no refreshRate, and a non-numeric value
  # would abort the whole script in the arithmetic test below under `set -e`.
  if [[ ! "$cur_hz" =~ ^[0-9]+$ ]]; then exit 0; fi
  if [[ "$cur_dpms" != "true" ]]; then exit 0; fi             # guard 2
  if (( cur_hz == ${want_hz%%.*} )); then exit 0; fi          # guard 3
  hyprctl keyword monitor "eDP-1,$want,${cur_x}x${cur_y},$cur_scale" >/dev/null
  exit 0
fi

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

# A matching hyprmon profile wins; otherwise the hand-written apply_<mode>.
case "$mode" in
  desktop|read|laptop|onescreen|trio)
    apply_from_profile "$mode" || "apply_$mode" ;;
  *) echo "usage: $0 {desktop|read|laptop|onescreen|trio|toggle|edp-rate}" >&2; exit 1 ;;
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
