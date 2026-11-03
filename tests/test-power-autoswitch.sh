#!/usr/bin/env bash
# Unit-test the patched transition branch with current_profile/set_profile stubbed.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/configs/hypr/scripts/power-autoswitch.sh"

# pull the branch out of the script so we test the real text, not a copy
BRANCH=$(awk '/^        if \[\[ "\$raw" == battery \]\]; then$/,/^        fi$/' "$SCRIPT")
[ -n "$BRANCH" ] || { echo "could not extract branch"; exit 1; }

PASS=0; FAIL=0
check() { # name expect_saved expect_profile
  local name="$1" exp_saved="$2" exp_prof="$3"
  if [[ "$saved_profile" == "$exp_saved" && "$PROF" == "$exp_prof" ]]; then
    printf "  PASS  %-46s saved='%s' profile=%s\n" "$name" "$saved_profile" "$PROF"; PASS=$((PASS+1))
  else
    printf "  FAIL  %-46s saved='%s' (want '%s')  profile=%s (want %s)\n" \
      "$name" "$saved_profile" "$exp_saved" "$PROF" "$exp_prof"; FAIL=$((FAIL+1))
  fi
}

run() { # raw  initial_profile  initial_saved
  raw="$1"; PROF="$2"; saved_profile="$3"
  current_profile() { echo "$PROF"; }
  set_profile() { [[ -n "$1" ]] && PROF="$1"; }
  notify-send() { :; }
  eval "$BRANCH"
}

echo "ratchet guard (battery side)"
run battery power-saver ""   ; check "battery boot, ppd already power-saver"      ""         power-saver
run battery balanced    ""   ; check "real AC(balanced) -> battery"               balanced   power-saver
run battery power-saver ""   ; check "toggle off/on while on battery"             ""         power-saver
run battery power-saver balanced ; check "re-entry must not clobber a capture"    balanced   power-saver
run battery performance ""   ; check "real AC(performance) -> battery"            performance power-saver

echo "restore (AC side)"
run ac power-saver balanced    ; check "transition with capture -> exact restore"  ""   balanced
run ac power-saver performance ; check "capture was performance -> restored"       ""   performance
run ac power-saver ""          ; check "nothing captured, ours -> hand to balanced" ""  balanced
run ac performance ""          ; check "AC boot, user's performance -> untouched"   ""  performance
run ac balanced    ""          ; check "AC boot, balanced -> untouched"             ""  balanced

echo
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
