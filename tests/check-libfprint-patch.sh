#!/usr/bin/env bash
# Verify patches/libfprint-elan-0c4f-busy-retry.patch is still sound.
#
# Why a test for a patch: it is the only thing in this repo that changes code
# this machine does not own, so the next rebuild is against whatever upstream
# has become. Two things can rot independently -- the hunks can stop applying,
# and (quieter, and the one that would actually hurt) the new driver_data bit
# can start colliding with something upstream added. The second would change
# behaviour for the reader with nothing failing to build.
#
#   ./tests/check-libfprint-patch.sh                  # structure only
#   LIBFPRINT_SRC=/path/to/libfprint ./tests/...      # + apply + flag audit
#
# Offline and read-only. Without LIBFPRINT_SRC it checks what it can and says
# what it skipped, so it never reports a pass it did not earn.
# Reasoning: runbooks/fingerprint.md section 20x.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PATCH="patches/libfprint-elan-0c4f-busy-retry.patch"
pass=0 fail=0 skip=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no()   { printf '  \033[31mFAIL\033[0m  %s — %s\n' "$1" "$2"; fail=$((fail+1)); }
sk()   { printf '  \033[33mSKIP\033[0m  %s — %s\n' "$1" "$2"; skip=$((skip+1)); }

[ -f "$PATCH" ] || { echo "missing $PATCH"; exit 2; }

# -- structure -------------------------------------------------------------- #
for needle in \
  'ELAN_0C4F (1 << 4)' \
  'pid = 0x0c4f, .driver_data = ELAN_0C4F' \
  'self->dev_type == ELAN_0C58 || self->dev_type == ELAN_0C4F' \
  'Against: libfprint v1.94.100'
do
  if grep -qF "$needle" "$PATCH"; then ok "patch carries: ${needle:0:46}"
  else no "patch carries: ${needle:0:46}" "not found"; fi
done

# The bit must not be one upstream already uses. Checked against the patch's
# own context lines, which carry the neighbouring defines.
if grep -qE '^\+#define ELAN_0C4F \(1 << 4\)' "$PATCH" &&
   ! grep -qE '^[ -]#define ELAN_[0-9A-F]+ \(1 << 4\)' "$PATCH"; then
  ok "bit 4 is free in the context the patch was written against"
else
  no "bit 4 is free" "upstream context already defines a (1 << 4) flag"
fi

# -- against a real checkout ------------------------------------------------ #
SRC="${LIBFPRINT_SRC:-}"
if [ -z "$SRC" ]; then
  sk "applies to a checkout" "set LIBFPRINT_SRC to a pristine libfprint tree"
  sk "flag audit" "needs LIBFPRINT_SRC"
elif [ ! -f "$SRC/libfprint/drivers/elan.h" ]; then
  no "applies to a checkout" "$SRC has no libfprint/drivers/elan.h"
else
  if git -C "$SRC" apply --check "$(pwd)/$PATCH" 2>/dev/null; then
    ok "applies cleanly to $SRC"
  elif git -C "$SRC" apply --reverse --check "$(pwd)/$PATCH" 2>/dev/null; then
    ok "already applied to $SRC (reverses cleanly)"
  else
    no "applies cleanly to $SRC" "hunks do not match; upstream moved"
  fi

  # THE AUDIT. Every dev_type decision in the driver must be unchanged by the
  # new bit -- this is the claim the patch rests on, and the only one whose
  # breakage would be silent.
  python3 -I - "$SRC" <<'PY'
import re, sys, pathlib
src = pathlib.Path(sys.argv[1]) / "libfprint" / "drivers"
h = (src / "elan.h").read_text(errors="replace")
c = (src / "elan.c").read_text(errors="replace")
flags = {m.group(1): 1 << int(m.group(2))
         for m in re.finditer(r'#define (ELAN_[0-9A-Fa-f]+)\s+\(1 << (\d+)\)', h)}
bad = []
new = flags.get("ELAN_0C4F")
if new is None:
    bad.append("ELAN_0C4F is not defined in elan.h (patch not applied?)")
else:
    clash = [n for n, v in flags.items() if v == new and n != "ELAN_0C4F"]
    if clash:
        bad.append(f"ELAN_0C4F collides with {', '.join(clash)}")
    # ELAN_NOT_ROTATED is tested with &, so a shared bit WOULD change behaviour
    m = re.search(r'#define ELAN_NOT_ROTATED\s+(\S+)', h)
    if m and flags.get(m.group(1), 0) & new:
        bad.append(f"ELAN_NOT_ROTATED ({m.group(1)}) overlaps ELAN_0C4F")
    # every command mask that is not ELAN_ALL_DEV is &-tested in elan_run_cmd
    for mask in set(re.findall(r'\.devices = (ELAN_[0-9A-Fa-f]+)', h)):
        if flags.get(mask, 0) & new:
            bad.append(f"command mask {mask} would now run on 0c4f")
    # the calibration-attempt macro and the open-time switch are == tests;
    # flag them only if upstream turned either into a bitwise test
    if re.search(r'ELAN_CALIBRATION_ATTEMPTS\(dev_type\).*&', h, re.S):
        bad.append("ELAN_CALIBRATION_ATTEMPTS now uses & -- re-audit")
    if re.search(r'dev_type\s*&\s*ELAN_0C(42|58)', c):
        bad.append("an ELAN_0C42/0C58 test now uses & -- re-audit")
    if "0x0c4f, .driver_data = ELAN_0C4F" not in h:
        bad.append("the 0c4f table entry does not carry ELAN_0C4F")
for b in bad:
    print(f"  \033[31mFAIL\033[0m  flag audit — {b}")
if not bad:
    print(f"  \033[32mPASS\033[0m  flag audit: {len(flags)} flags, "
          f"ELAN_0C4F unique, no & test and no command mask reaches it")
sys.exit(1 if bad else 0)
PY
  if [ $? -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
fi

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
