#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fp-debug.sh -- enrol through the REFERENCE client with libfprint debug open.
#
# Why this script exists: every failed enrolment so far has been attempted
# through Triton Panel, so "is it the panel or is it the driver?" was never
# answered. fprintd-enroll is fprintd's own CLI client -- same D-Bus calls, no
# GTK, no claim juggling. If it fails identically, the panel is exonerated and
# the fault is below it. If it gets further, the panel is the suspect.
#
# It also turns on G_MESSAGES_DEBUG=all for fprintd, which is what makes the
# `elan` driver print its per-frame reasoning. Without it the journal only
# carries the summary lines ("protocol error", "No minutiae found") that have
# been going in circles.
#
# The debug switch is a drop-in under /run, so it evaporates at reboot and the
# script removes it on every exit path anyway. Nothing persistent is changed.
#
# The sensor here was checked by eye on 2026-11-01: a ~1 cm square pad in the
# corner of the touchpad, i.e. an AREA sensor -- while `elan` drives it as a
# SWIPE sensor, stitching frames by the displacement between them. So the two
# enrolment modes below are not "the right way vs the wrong way": `press` is
# what the hardware wants, `swipe` manufactures displacement on a pad that has
# nowhere to swipe, which is what the driver wants. Run both; the comparison is
# the whole point.
#
# Added 2026-11-01 (§20m): a `verify` mode. Enrolment succeeded on 2026-11-01,
# but `fprintd-verify` then failed 4/4 -- 2x no-match, 2x a protocol error that
# fprintd reports as `verify-disconnected` although the sensor never left the
# USB bus. Two causes are still indistinguishable from the summary journal:
#
#   H1  the stored template is marginal (6 accepted captures, 2 rejections, on
#       a ~1 cm pad), so nothing will ever match it;
#   H2  the VERIFY captures are too thin -- verify gets ONE capture per touch
#       with no stitching, where enrolment stitched six, so it is strictly the
#       harder operation and may simply sit under the NBIS floor.
#
# Only the per-capture debug output separates them, and the H1 fix (re-enrol)
# is destructive while the H2 fix does not exist. So measure first.
#
# Usage:   ./fp-debug.sh press     # flat, hold ~2s, lift fully
#          ./fp-debug.sh swipe     # roll edge-to-edge without losing contact
#          ./fp-debug.sh verify    # measure MATCHING, enrols nothing
#          ./fp-debug.sh presence  # trace finger-present; enrols nothing
#          ./fp-debug.sh rebind    # recover a wedged reader, no enrolment
#
# Added 2026-11-01 (§20s): a `presence` mode, which is the thing that should
# have been built BEFORE the panel started gating anything on finger-present.
# Two bugs in a row came from guessing at that signal: §20r counted a dozen
# results from one unbroken press as a dozen placements, then §20s found the
# fix had made the device deaf for 3 s after every result. Neither would have
# been written if this trace had existed. It answers one question directly:
# does this driver report finger-present going FALSE, and when?
# ---------------------------------------------------------------------------
set -uo pipefail

GESTURE="${1:-press}"
FINGER="${FINGER:-right-index-finger}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/fprintd-$GESTURE-$(date +%Y%m%d-%H%M%S).log"
DROPIN=/run/systemd/system/fprintd.service.d/99-debug.conf
TAIL_PID=""

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }

# -- find the reader on the USB bus ----------------------------------------- #
find_reader() {
  local d
  for d in /sys/bus/usb/devices/*/; do
    [ -r "$d/idVendor" ] || continue
    if [ "$(cat "$d/idVendor")" = "04f3" ] && [ "$(cat "$d/idProduct")" = "0c4f" ]; then
      basename "$d"; return 0
    fi
  done
  return 1
}

# -- recovery: a PROTO error can leave the endpoint halted ------------------ #
# The upstream analysis of the sibling 04f3:0903 says a timed-out command is
# not followed by a clear-halt or an endpoint reset, so every later transfer
# fails too. Unbind/bind is the documented way out. Worth trying BEFORE an
# enrolment run so the device starts from a known state.
rebind() {
  local dev; dev="$(find_reader)" || { warn "reader 04f3:0c4f not on the bus"; return 1; }
  say "re-binding USB device $dev (clears a halted endpoint)"
  sudo systemctl stop fprintd 2>/dev/null
  echo -n "$dev" | sudo tee /sys/bus/usb/drivers/usb/unbind >/dev/null
  sleep 2
  echo -n "$dev" | sudo tee /sys/bus/usb/drivers/usb/bind >/dev/null
  sleep 2
  lsusb | grep -i 04f3:0c4f || warn "device did not come back -- check lsusb"
  # Start it back explicitly rather than leaving it to D-Bus activation, so
  # there is nothing to reason about afterwards: `systemctl stop` on a healthy
  # unit leaves it inactive, not failed, and this puts it back to active.
  sudo systemctl start fprintd
  echo "fprintd: $(systemctl is-active fprintd)"
}

cleanup() {
  [ -n "$TAIL_PID" ] && kill "$TAIL_PID" 2>/dev/null
  if [ -e "$DROPIN" ]; then
    say "removing the debug drop-in and restarting fprintd"
    sudo rm -f "$DROPIN"
    sudo rmdir /run/systemd/system/fprintd.service.d 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl restart fprintd 2>/dev/null
  fi
  if [ -s "$LOG" ]; then
    say "log: $LOG"
    printf '\n--- what to look for -------------------------------------------\n'
    grep -c . "$LOG" | xargs printf 'lines captured: %s\n'
    printf '\nframes / assembly (gesture-shaped if present):\n'
    grep -i -E "frame|assemble|too short|TOO_SHORT|displacement|minutiae" "$LOG" | tail -15
    printf '\nprotocol / USB errors (driver-shaped):\n'
    grep -i -E "protocol error|PROTO|halt|timeout|timed out|cancel|state machine" "$LOG" | tail -15
    printf '\ncalibration:\n'
    grep -i -E "calibrat" "$LOG" | tail -8
    if [ "$GESTURE" = "verify" ]; then
      printf '\nmatcher / minutiae detail (the H1-vs-H2 discriminator):\n'
      grep -i -E "minutia|bozorth|score|match|template|nbis|print_data" "$LOG" | tail -25
      printf '\nNOTE: if no per-capture minutiae COUNT appears above, the elan\n'
      printf '      driver did not print one -- say so rather than inferring a\n'
      printf '      number. In that case the next non-destructive step is a\n'
      printf '      FRESH TEMPLATE OF THE SAME FINGER in a second slot:\n'
      printf '        fprintd-enroll -f left-index-finger   # use the RIGHT index\n'
      printf '      The slot name is only a label -- nothing ties it to a left\n'
      printf '      finger -- and `fprintd-verify` with no -f tries every\n'
      printf '      template, so this costs nothing and deletes nothing.\n'
      printf '      Do NOT delete right-index-finger to test this.\n'
    fi
    printf '\n'
  fi
}
trap cleanup EXIT INT TERM

# -- rebind-only mode ------------------------------------------------------- #
if [ "$GESTURE" = "rebind" ]; then
  trap - EXIT INT TERM
  rebind
  exit 0
fi

case "$GESTURE" in
  press|swipe|verify|presence) ;;
  *) echo "usage: $0 {press|swipe|verify|presence|rebind}" >&2; exit 2 ;;
esac

# -- this must run inside the graphical session, not a tty ------------------ #
#
# Claim() goes through polkit, so it needs a polkit agent -- here
# hyprpolkitagent, started by autostart.conf INSIDE the Hyprland session. From
# a bare tty (Ctrl+Alt+F2) there is no agent and fprintd-enroll dies on an
# authorization error that reads exactly like a driver fault, which would send
# you chasing the wrong thing. "Close the panel" means close its window, not
# leave the session.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  warn "No WAYLAND_DISPLAY/DISPLAY -- this looks like a bare tty."
  warn "There is no polkit agent here, so Claim() will fail with an"
  warn "authorization error that is NOT a driver fault. Run this from a"
  warn "terminal inside the Hyprland session instead."
  exit 1
fi
if ! pgrep -f "hyprpolkitagent" >/dev/null 2>&1; then
  warn "hyprpolkitagent is not running; the polkit password prompt will not"
  warn "appear. Start it: systemctl --user start hyprpolkitagent.service"
fi

# -- the panel must not hold the claim -------------------------------------- #
#
# Match the INSTALLED path, not the bare name: this script normally runs from
# the triton-panel/ directory, so `pgrep -f triton-panel` also matches the
# shell that launched it (and this script itself). The bracket keeps the
# pattern from matching pgrep's own argument.
if pgrep -f "[.]local/bin/triton-panel" >/dev/null 2>&1; then
  warn "Triton Panel is running. Close its window first: it may hold the"
  warn "fprintd claim. Then run this again."
  exit 1
fi

say "reader on the bus"
lsusb | grep -i 04f3:0c4f || { warn "reader not found"; exit 1; }
printf 'scan-type reported by fprintd: '
busctl --system get-property net.reactivated.Fprint \
  /net/reactivated/Fprint/Device/0 net.reactivated.Fprint.Device scan-type 2>/dev/null || echo "?"

# -- warm the sudo ticket BEFORE the debug setup ---------------------------- #
#
# Added 2026-11-01. `pam_fprintd` went live in /etc/pam.d/sudo the moment a
# print existed, so every `sudo` below now waits on the reader first -- and it
# prompts "Swipe your right index finger" (the prompt is built from the
# driver's scan-type, not the real gesture) and blocks for ~30 s before falling
# through to the password. Six sudo calls follow. One `sudo -v` up front caches
# the ticket so the rest are silent, and it keeps the reader free for the run
# itself rather than letting PAM fight the script for the claim.
#
# pam_fprintd is `sufficient`, so pressing Enter at the prompt falls straight
# through to the password. Do NOT edit PAM to work around this.
# -- presence trace: no sudo, no drop-in, no restart ------------------------ #
#
# This one needs none of the privileged setup: finger-present arrives as an
# ordinary PropertiesChanged on the system bus, which any session can watch.
# Skipping the drop-in also means fprintd is NOT restarted, so the trace sees
# the daemon in the state the panel actually meets.
if [ "$GESTURE" = "presence" ]; then
  trap - EXIT INT TERM
  LOG="$HERE/presence-$(date +%Y%m%d-%H%M%S).log"
  PASSES="${PASSES:-4}"
  cat <<'EOF'

================================================================================
 PRESENCE TRACE -- enrols nothing, deletes nothing, writes nothing.

 Every finger-present / finger-needed change is printed with a millisecond
 timestamp, interleaved with each VerifyStatus result.

   1. Put the finger flat on the pad.
   2. HOLD about 2 seconds.
   3. LIFT IT RIGHT OFF and wait for the next prompt.

 What to read afterwards:
   * a `finger-present: true` with NO matching `false` after you lifted
     -> the driver does not report the lift, and anything gated on it is
        unreliable (this is the §20j invalid-transition bug)
   * both edges, promptly -> the signal is good and the panel can trust it
   * no finger-present lines at all -> the reader never reports contact;
     the panel detects this as `strip.supported is not True` and stops gating
================================================================================
EOF
  gdbus monitor --system --dest net.reactivated.Fprint 2>&1 \
    | grep --line-buffered -E 'finger-present|finger-needed|VerifyStatus|VerifyFingerSelected' \
    | while IFS= read -r line; do
        printf '%s  %s\n' "$(date +%H:%M:%S.%3N)" "$line"
      done | tee "$LOG" &
  MON_PID=$!
  sleep 1
  for i in $(seq 1 "$PASSES"); do
    printf '\n\033[1;36m==> pass %s of %s -- touch, hold ~2s, then LIFT\033[0m\n' "$i" "$PASSES"
    fprintd-verify >/dev/null 2>&1 || true
    sleep 1
  done
  sleep 1
  kill "$MON_PID" 2>/dev/null
  pkill -P $$ gdbus 2>/dev/null
  say "trace: $LOG"
  printf '\n--- finger-present edges seen ---\n'
  grep -c 'finger-present.*true'  "$LOG" 2>/dev/null | xargs printf '  true  (finger down): %s\n'
  grep -c 'finger-present.*false' "$LOG" 2>/dev/null | xargs printf '  false (finger up)  : %s\n'
  printf '\nIf the false count is 0 or much lower than the true count, the lift is\n'
  printf 'not being reported and the panel is relying on its wall-clock escape\n'
  printf '(SAME_PRESS_S) rather than on the driver. See §20s.\n\n'
  exit 0
fi

say "caching the sudo ticket (pam_fprintd will prompt -- press Enter, then type your password)"
sudo -v || { warn "could not cache sudo credentials"; exit 1; }

say "turning on libfprint debug (drop-in under /run -- gone at reboot)"
sudo mkdir -p /run/systemd/system/fprintd.service.d
printf '[Service]\nEnvironment=G_MESSAGES_DEBUG=all\n' | sudo tee "$DROPIN" >/dev/null
sudo systemctl daemon-reload
sudo systemctl restart fprintd
sleep 1

say "capturing the journal"
journalctl -u fprintd -f -o short-precise --since now >"$LOG" 2>&1 &
TAIL_PID=$!
sleep 1

cat <<EOF

================================================================================
 MODE FOR THIS RUN: $GESTURE
EOF
if [ "$GESTURE" = "verify" ]; then
cat <<'EOF'

   This measures MATCHING against the template already enrolled. It enrols
   nothing, deletes nothing, and writes nothing -- it is safe to run as often
   as you like.

   1. Put the finger flat on the pad -- the SAME region every time, centred,
      covering as much of it as you can.
   2. HOLD STILL until the result line appears -- do not slide.
   3. LIFT IT RIGHT OFF between attempts.

   Use the finger that is actually enrolled (right index). The point is not to
   try a different finger: it is to see, per capture, how much ridge detail the
   sensor hands to the matcher.

   What the log then tells you:
     * a minutiae COUNT on each capture, well under what the template carries
       -> H2, the small-sensor ceiling. Re-enrolling cannot fix that.
     * healthy counts but still `verify-no-match`
       -> H1, the stored template is the suspect, and a fresh one is worth it.
     * `protocol error` / halted endpoint and little else
       -> neither; run `./fp-debug.sh rebind` and try again.
EOF
elif [ "$GESTURE" = "press" ]; then
cat <<'EOF'

   1. Put the finger flat on the sensor, covering as much of it as you can.
   2. HOLD STILL about 2 seconds -- do not slide.
   3. LIFT IT RIGHT OFF, clear of the sensor.
   4. Wait for the next prompt before touching it again.

   Step 3 is the one that matters. libfprint will not begin the next capture
   until the driver reports the finger GONE, so a finger left resting on the
   sensor stalls the run with no message at all.
EOF
else
cat <<'EOF'

   The pad is a ~1 cm square -- there is nothing to swipe ALONG. But `elan`
   stitches frames by the displacement between them, and a still press gives
   it none, so this run manufactures that displacement on an area pad:

   1. Set the finger down on one edge of the pad.
   2. ROLL it slowly to the opposite edge over about 1 second, keeping
      contact the whole way -- a rocking motion, never losing the pad.
   3. LIFT IT RIGHT OFF, clear of the pad.
   4. Wait for the next prompt before going again.

   What this tests: if `press` keeps giving "No minutiae found" and this one
   produces frames or a passed stage, the swipe-driver-on-an-area-pad theory
   is confirmed -- and the fix is a driver, not a gesture.
EOF
fi
cat <<EOF

 A polkit dialog will ask for your own password. Six accepted captures are
 needed. Ctrl+C at any time -- the debug switch is removed on the way out.
================================================================================

EOF

if [ "$GESTURE" = "verify" ]; then
  # No -f: "default is automatic", i.e. fprintd tries EVERY enrolled template.
  # That matters once a second slot exists -- see the note in the summary below.
  say "running the reference client: fprintd-verify"
  fprintd-verify
  rc=$?
  say "fprintd-verify exited with status $rc"
else
  say "running the reference client: fprintd-enroll -f $FINGER"
  fprintd-enroll -f "$FINGER"
  rc=$?
  say "fprintd-enroll exited with status $rc"
fi
sleep 2   # let the last journal lines land in the log
exit $rc
