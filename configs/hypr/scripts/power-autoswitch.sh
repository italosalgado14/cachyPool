#!/usr/bin/env bash
# power-autoswitch.sh — follow the power source: save battery when it is the
# only thing feeding the machine, go back to normal on wall power.
#
# Added 2026-10-31. Two actions, nothing else:
#
#   on battery  ->  eDP-1 at 2560x1600@60   + platform profile `power-saver`
#   on AC       ->  eDP-1 at 2560x1600@240  + whatever profile was active before
#
# The laptop panel has exactly two modes (240 Hz and 60 Hz, same resolution and
# scale), so dropping to 60 is the cheapest real saving on this machine and
# costs nothing but smoothness.
#
# ---------------------------------------------------------------------------
# "On battery" is `grep -q Discharging /sys/class/power_supply/BAT1/status`, the
# SAME test hypridle's suspend listener uses. Not ACAD/online: the Plugable
# TBT4-UD5 feeds this laptop over USB-C PD, so ACAD reads 1 with no barrel jack
# attached, and `Not charging` (the 80% cap holding on AC) must count as AC.
#
# ---------------------------------------------------------------------------
# THE TWO POLICIES ARE DELIBERATELY DIFFERENT. This is the non-obvious part:
#
#   RATE    = reconciled on every stable tick (idempotent).
#             There is no manual UI for the refresh rate anywhere, so there is
#             no user choice to override — and reconciling is what catches the
#             three things that silently reset it: a `hyprctl reload` (which
#             snaps eDP-1 back to monitors.conf's @240), a Super+M profile
#             switch, and monitor-autoswitch.sh applying a profile on hotplug.
#             The actual emit lives in `monitor-mode.sh edp-rate`, which no-ops
#             unless the rate really differs.
#
#   PROFILE = changed only on a power-source TRANSITION.
#             The platform profile IS exposed in Triton Panel's Power group, so
#             a user who picks `performance` while on battery must keep it. A
#             reconcile loop here would fight that choice every few seconds.
#
# ---------------------------------------------------------------------------
# The toggle: ~/.config/triton-panel/power-auto, "1" (default when absent) or
# "0". Written by Triton Panel's "Automatic power saving" switch.
#
#   1 -> 0   restore 240 Hz once, then stop touching the rate. The profile is
#            LEFT ALONE: turning the automation off should not also undo the
#            profile the user is sitting on. Without the one-shot restore you
#            would be stranded at 60 Hz with no manual rate control anywhere.
#   0 -> 1   treated as a forced transition, so switching it on while already
#            on battery applies immediately instead of waiting for the next
#            plug/unplug.
#
# Triton Panel sends SIGUSR1 after writing the file, so the switch responds at
# once instead of up to POLL seconds later. It takes the target pid from the
# `pid=` line of the state file — see write_state for why not `pkill -f`.
#
# Only one instance should run. A second one would fight the first over the
# saved profile, so the loop refuses to start if a live pid is already there.

set -uo pipefail   # no -e, like monitor-autoswitch.sh: a transient hyprctl
                   # failure in the first second after login must not kill the
                   # loop that runs for the rest of the session.

MODE_SCRIPT="$HOME/.config/hypr/scripts/monitor-mode.sh"
PREF="${XDG_CONFIG_HOME:-$HOME/.config}/triton-panel/power-auto"
STATEFILE="${XDG_RUNTIME_DIR:-/tmp}/triton-power-mode"
BATSTATUS=/sys/class/power_supply/BAT1/status

POLL=5          # seconds between samples
STALE_AFTER=15  # the panel calls the state file dead after this many seconds

FORCE=0
trap 'FORCE=1' USR1

# --------------------------------------------------------------------------- #
# reading the world
# --------------------------------------------------------------------------- #

# "battery" or "ac". No BAT1 node at all (the pack was out from 2026-10-12 to
# 2026-10-31) counts as AC: with nothing to drain there is nothing to save.
read_source() {
  if [[ -r "$BATSTATUS" ]] && grep -q Discharging "$BATSTATUS" 2>/dev/null; then
    echo battery
  else
    echo ac
  fi
}

read_auto() {
  local value
  value="$(cat "$PREF" 2>/dev/null || echo 1)"
  [[ "$value" == 0 ]] && echo 0 || echo 1
}

# eDP-1's live refresh rate, or empty when the panel is disabled (as 'read' mode
# leaves it). Reported to the panel rather than assumed, so the UI shows what the
# hardware is actually doing.
read_rate() {
  hyprctl monitors -j 2>/dev/null \
    | jq -r '[.[] | select(.name=="eDP-1") | (.refreshRate|round)][0] // ""' 2>/dev/null
}

current_profile() {
  powerprofilesctl get 2>/dev/null | tr -d '[:space:]'
}

# --------------------------------------------------------------------------- #
# acting
# --------------------------------------------------------------------------- #

set_profile() {
  local wanted="$1"
  [[ -n "$wanted" ]] || return 0
  [[ "$(current_profile)" == "$wanted" ]] && return 0
  powerprofilesctl set "$wanted" 2>/dev/null \
    || echo "power-autoswitch: could not set profile $wanted" >&2
}

# Triton Panel reads this. key=value, one per line; `ts` lets it decide the
# daemon is gone rather than trusting a stale snapshot.
#
# `pid` is published so the panel can signal THIS process and nothing else.
# Do not reach for `pkill -USR1 -f power-autoswitch.sh` instead: -f matches the
# whole command line, so it also hits any shell, editor or pager whose argv
# merely mentions the script — during development that killed the very shell
# running the test. Signal the pid from here.
write_state() {
  local source="$1" auto="$2" saved="$3" rate="$4"
  local tmp="$STATEFILE.$$"
  {
    echo "source=$source"
    echo "auto=$auto"
    echo "rate=${rate:-}"
    echo "saved_profile=$saved"
    echo "profile=$(current_profile)"
    echo "stale_after=$STALE_AFTER"
    echo "pid=$$"
    echo "ts=$(date +%s)"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATEFILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# --------------------------------------------------------------------------- #
# the loop
# --------------------------------------------------------------------------- #

# Single instance. `exec-once` runs this at login and it is also started by hand
# after a config push; two copies would each keep their own saved_profile and
# undo each other's restore.
# The cmdline check matters: a bare `kill -0` would also succeed for an
# unrelated process that happened to inherit the dead daemon's pid, and would
# then block every future start.
existing="$(sed -n 's/^pid=//p' "$STATEFILE" 2>/dev/null)"
if [[ -n "$existing" && "$existing" != "$$" ]] \
   && kill -0 "$existing" 2>/dev/null \
   && tr '\0' ' ' < "/proc/$existing/cmdline" 2>/dev/null | grep -q power-autoswitch; then
  echo "power-autoswitch: already running as pid $existing" >&2
  exit 0
fi

last_source=unknown      # forces the first stable read to count as a transition
last_auto="$(read_auto)"
# Seeded with a real reading rather than "" so the FIRST tick already counts as
# stable. With an empty seed the first sample never matched and the first apply
# landed ~10 s into the session: on a battery login the panel would run at 240 Hz
# and then visibly modeset to 60 after the user was already looking at it. The
# two-identical-reads rule exists for live plug/unplug, where ACPI flashes
# `Unknown`; at login the power source has long settled.
prev_raw="$(read_source)"
saved_profile=""

while :; do
  auto="$(read_auto)"
  raw="$(read_source)"

  # The toggle moving 1 -> 0: restore the normal rate once and stand down. The
  # restore works because monitor-mode.sh's own power_auto() now reads 0, so
  # edp_mode() resolves to @240 regardless of the power source.
  if [[ "$auto" == 0 && "$last_auto" == 1 ]]; then
    "$MODE_SCRIPT" edp-rate 2>/dev/null || true
  fi
  # 0 -> 1: forget the last source so the block below treats this as a
  # transition and applies right now.
  if [[ "$auto" == 1 && "$last_auto" == 0 ]]; then
    last_source=unknown
  fi
  last_auto="$auto"

  if (( FORCE )); then
    FORCE=0
    prev_raw="$raw"        # a deliberate poke from the panel needs no debounce
  fi

  if [[ "$auto" == 1 ]]; then
    # Two identical consecutive samples before anything happens: ACPI briefly
    # reports `Unknown` on plug and unplug, and acting on that flash would
    # modeset the panel twice for nothing.
    if [[ "$raw" == "$prev_raw" ]]; then
      # RATE — every stable tick. edp-rate re-resolves from BAT1 itself and
      # no-ops when the rate already matches, so this is free when nothing
      # changed and self-healing when something reset it.
      "$MODE_SCRIPT" edp-rate 2>/dev/null || true

      # PROFILE — transitions only.
      if [[ "$raw" != "$last_source" ]]; then
        if [[ "$raw" == battery ]]; then
          # Only capture on the FIRST entry into battery. Flipping the toggle
          # off and on again while already on battery re-enters this branch,
          # and overwriting here would record `power-saver` as "what I had" —
          # so plugging in later would restore power-saver instead of the
          # profile from before the machine ever went to battery.
          # Cleared on the AC transition, which is what re-arms the capture.
          [[ -n "$saved_profile" ]] || saved_profile="$(current_profile)"
          set_profile power-saver
          notify-send -t 3000 "Power" "On battery — 60 Hz, power-saver" 2>/dev/null || true
        else
          set_profile "${saved_profile:-balanced}"
          notify-send -t 3000 "Power" \
            "On AC — 240 Hz, ${saved_profile:-balanced}" 2>/dev/null || true
          saved_profile=""
        fi
        last_source="$raw"
      fi
    fi
  else
    # Automation off: still report the truth so the panel's row is honest.
    last_source="$raw"
  fi

  prev_raw="$raw"
  write_state "$raw" "$auto" "$saved_profile" "$(read_rate)"

  # Backgrounded so the USR1 trap runs immediately instead of after the sleep.
  sleep "$POLL" &
  wait $! 2>/dev/null
done
