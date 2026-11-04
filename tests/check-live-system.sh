#!/usr/bin/env bash
# Verify this machine still matches what the repo says it is.
#
# Added 2026-11-03 with the update procedure (runbooks/updates.md). An update is the
# only routine operation here that can silently revert a documented fix, and the three
# ways it does that are all invisible until you need the thing:
#
#   1. a DKMS module quietly fails to rebuild      -> the 80% charge cap stops working
#   2. a .pacnew overwrite drops a hand-edited line -> the fix is gone, the file looks fine
#   3. a live file drifts from its repo mirror      -> the docs describe a machine that
#      no longer exists (the logind drop-in sat uninstalled for three months this way)
#
# Everything here is read-only and needs no sudo, so it is safe to run at any time.
# Run it BEFORE an upgrade as the gate (--strict), and again after, before and after
# the reboot.
#
#   ./tests/check-live-system.sh            # FAIL fails the run; WARN is reported only
#   ./tests/check-live-system.sh --strict   # WARN fails too -- the pre-upgrade gate
#
# FAIL = an invariant this repo documents is broken right now.
# WARN = maintenance is pending (unmerged .pacnew, reboot owed, updates waiting).
# note = informational, including mirror drift that is comments-only.
#
# A FAIL is a bug in the machine. Fix it or correct the document that claims it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

F=0; W=0; N=0; P=0
pass() { printf '  \033[32mPASS\033[0m  %-44s %s\n' "$1" "${2:-}"; P=$((P+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %-44s %s\n' "$1" "${2:-}"; F=$((F+1)); }
warn() { printf '  \033[33mWARN\033[0m  %-44s %s\n' "$1" "${2:-}"; W=$((W+1)); }
note() { printf '  note  %-44s %s\n' "$1" "${2:-}"; N=$((N+1)); }

# want <name> <expected> <actual>  -- FAIL unless they match exactly
want() {
  if [ "$2" = "$3" ]; then pass "$1" "$3"; else fail "$1" "got '$3', want '$2'"; fi
}

echo
echo "── Hardware invariants ──────────────────────────────────────────────────────────"

RUNNING=$(uname -r)
pass "running kernel" "$RUNNING"

# The 80% charge cap. BAT1 exposes no charge_control_* node on this machine -- the cap
# lives in the out-of-tree acer_wmi_battery module, so this is the only node that
# answers "is it capped?".  runbooks/power-battery.md §14
HM=/sys/bus/wmi/drivers/acer-wmi-battery/health_mode
if [ -r "$HM" ]; then want "charge cap (health_mode)" 1 "$(cat "$HM")"
else fail "charge cap (health_mode)" "$HM not readable -- module loaded?"; fi

# The cap only survives a kernel change if DKMS rebuilt against it. The hook builds at
# install time, so the new kernel can be checked BEFORE rebooting into it.
DKMS=$(dkms status 2>/dev/null)
if echo "$DKMS" | grep -q "acer-wmi-battery.*$RUNNING.*installed"; then
  pass "dkms acer-wmi-battery (running)" "$RUNNING"
else
  fail "dkms acer-wmi-battery (running)" "not installed for $RUNNING -- the charge cap is dead"
fi

INSTALLED_KERNEL=$(pacman -Q linux-cachyos 2>/dev/null | awk '{print $2}')
if [ -n "$INSTALLED_KERNEL" ]; then
  # pacman 7.3.1-1 -> module dir 7.3.1-1-cachyos
  KDIR="${INSTALLED_KERNEL}-cachyos"
  if [ "$KDIR" = "$RUNNING" ]; then
    pass "kernel is the installed one" "$KDIR"
  elif echo "$DKMS" | grep -q "acer-wmi-battery.*$KDIR.*installed"; then
    warn "reboot owed" "installed $KDIR, running $RUNNING (dkms ready for both)"
  else
    fail "dkms acer-wmi-battery (installed)" "missing for $KDIR -- cap will not survive the reboot"
  fi
fi

# Fans + the 5-state platform profile exist only because of a forced module parameter;
# the PT516-52s is absent from the driver's DMI quirk table. runbooks/power-battery.md §17
PV4=/sys/module/acer_wmi/parameters/predator_v4
if [ -r "$PV4" ]; then want "acer_wmi predator_v4" Y "$(cat "$PV4")"
else fail "acer_wmi predator_v4" "$PV4 missing"; fi

PP=""
for c in /sys/firmware/acpi/platform_profile /sys/class/platform-profile/platform-profile-0/profile; do
  [ -r "$c" ] && { PP=$(cat "$c"); pass "platform_profile" "$PP ($c)"; break; }
done
[ -n "$PP" ] || fail "platform_profile" "no platform-profile node -- predator_v4 quirk not applied"

if grep -lx acer /sys/class/hwmon/*/name >/dev/null 2>&1; then
  pass "acer hwmon (fan RPM)" "$(grep -lx acer /sys/class/hwmon/*/name | head -1 | xargs dirname | xargs basename)"
else
  fail "acer hwmon (fan RPM)" "no hwmon named 'acer' -- no fan readings"
fi

# The Thunderbolt shutdown-hang fix: the stop timeout must be SHORT, so a device that
# refuses to release does not hold shutdown for 90s. runbooks/boot-suspend.md §6.3
# What matters is the effective value, not which file carries it -- a drop-in under
# /usr/lib/systemd/system.conf.d/ overrides /etc/systemd/system.conf, so reading that
# file is not evidence. `systemd-analyze cat-config systemd/system.conf` shows the order.
to_sec() { # "10s" | "1min 30s" | "infinity" -> seconds
  local v="$1" t=0 n u
  [ "$v" = infinity ] && { echo 999999; return; }
  while [[ "$v" =~ ^[[:space:]]*([0-9]+)(min|ms|us|s|h)(.*)$ ]]; do
    n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2]}"; v="${BASH_REMATCH[3]}"
    case "$u" in h) t=$((t+n*3600));; min) t=$((t+n*60));; s) t=$((t+n));; esac
  done
  echo "$t"
}
TMO=$(systemctl show -p DefaultTimeoutStopUSec --value 2>/dev/null)
TMO_S=$(to_sec "$TMO")
TMO_SRC=$(systemd-analyze cat-config systemd/system.conf 2>/dev/null \
          | awk '/^# \//{f=$2} /^DefaultTimeoutStopSec=/{src=f} END{print src}')
if [ "${TMO_S:-0}" -gt 0 ] && [ "${TMO_S}" -le 15 ]; then
  pass "DefaultTimeoutStopSec <= 15s" "$TMO (from ${TMO_SRC:-?})"
else
  fail "DefaultTimeoutStopSec <= 15s" "effective $TMO (from ${TMO_SRC:-?}) -- TB4 shutdown hang returns"
fi

# A partial upgrade leaves the loaded module and the userspace libraries at different
# versions; KMS then fails and Hyprland black-screens. Read the loaded module's own
# version rather than nvidia-smi, which can wake (or fail on) the dGPU.
NV_MOD=$(cat /sys/module/nvidia/version 2>/dev/null)
NV_PKG=$(pacman -Q nvidia-utils 2>/dev/null | awk '{print $2}' | sed 's/-[0-9]*$//')
if [ -z "$NV_MOD" ]; then
  fail "nvidia module loaded" "/sys/module/nvidia/version missing"
elif [ "$NV_MOD" = "$NV_PKG" ]; then
  pass "nvidia module == nvidia-utils" "$NV_MOD"
else
  fail "nvidia module == nvidia-utils" "module $NV_MOD, package $NV_PKG -- partial upgrade"
fi

if lsusb -d 04f3:0c4f >/dev/null 2>&1; then pass "fingerprint reader present" "04f3:0c4f"
else warn "fingerprint reader present" "04f3:0c4f not enumerated"; fi

echo
echo "── Hyprland session ─────────────────────────────────────────────────────────────"

if MON=$(hyprctl monitors -j 2>/dev/null) && [ -n "$MON" ]; then
  COUNT=$(echo "$MON" | jq 'length')
  NAMES=$(echo "$MON" | jq -r 'map(.name) | join(" ")')
  if [ "$COUNT" -ge 1 ]; then pass "monitors connected" "$COUNT: $NAMES"
  else fail "monitors connected" "hyprctl reports none"; fi
  # The compositor must stay on the Intel iGPU; nothing here may assume the dGPU renders.
  ERR=$(hyprctl configerrors 2>/dev/null)
  if [ -z "$ERR" ] || [ "$ERR" = "no errors" ]; then pass "hyprctl configerrors" "clean"
  else fail "hyprctl configerrors" "$ERR"; fi
  # Config language: hyprlang is deprecated upstream since 0.55 and this machine still
  # runs the legacy parser.  ACTUAL-CONFIGURATION.md §15, runbooks/updates.md §4
  if [ -e "$HOME/.config/hypr/hyprland.lua" ]; then
    note "hypr config language" "LUA (hyprland.lua present) -- hyprctl keyword no longer works"
  else
    note "hypr config language" "legacy hyprlang (no hyprland.lua) -- retirement date unknown"
  fi
  if pgrep -x hyprpaper >/dev/null; then pass "hyprpaper running" "$(pgrep -cx hyprpaper) proc"
  else fail "hyprpaper running" "not running -- wallpaper is blank"; fi
else
  note "hyprland session" "hyprctl unreachable (not in a Hyprland session?) -- session checks skipped"
fi

echo
echo "── Mirror parity: configs/ vs the live system ───────────────────────────────────"
# This is the manifest. Every line is a live path this repo claims to own. A file that
# drifts by design is marked so, and is never a failure.
#   repo path | live path | mode     mode: strict | comments | bydesign
MANIFEST=$(cat <<'MAP'
configs/hypr/*.conf|~/.config/hypr/|strict
configs/hypr/scripts/*|~/.config/hypr/scripts/|strict
configs/hyprmon/profiles/*.json|~/.config/hyprmon/profiles/|strict
configs/kitty/kitty.conf|~/.config/kitty/|strict
configs/kitty/themes/*.conf|~/.config/kitty/themes/|strict
configs/waybar/*|~/.config/waybar/|strict
configs/systemd/user/*|~/.config/systemd/user/|strict
configs/applications/*.desktop|~/.local/share/applications/|strict
configs/modprobe.d/*|/etc/modprobe.d/|comments
configs/systemd/logind.conf.d/*|/etc/systemd/logind.conf.d/|comments
triton-panel/triton-panel|~/.local/bin/|strict
configs/vlc/vlcrc|~/.config/vlc/|bydesign
MAP
)
# hyprlock.conf is written by Triton Panel on the live side (the fingerprint switch),
# so it drifts by design even though it sits in a strict group.
BYDESIGN_FILES="configs/hypr/hyprlock.conf"

# effective content: drop blank lines and whole-line comments
eff() { sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*\/\//d' -e '/^$/d' "$1"; }

MISSING=0; DRIFT=0; SAME=0
while IFS='|' read -r pattern dest mode; do
  [ -z "$pattern" ] && continue
  dest="${dest/#\~/$HOME}"
  for repo in $pattern; do
    [ -f "$repo" ] || continue
    live="$dest$(basename "$repo")"
    label="$(basename "$repo")"
    m="$mode"
    case " $BYDESIGN_FILES " in *" $repo "*) m=bydesign ;; esac
    if [ ! -e "$live" ]; then
      if [ "$m" = bydesign ]; then note "$label" "not installed (drifts by design)"
      else fail "$label" "committed but NOT installed at $live"; MISSING=$((MISSING+1)); fi
    elif cmp -s "$repo" "$live"; then
      SAME=$((SAME+1))
    elif [ "$m" = bydesign ]; then
      note "$label" "differs from $live (by design)"
    elif diff -q <(eff "$repo") <(eff "$live") >/dev/null 2>&1; then
      note "$label" "differs in comments only -- pull or push to re-sync"
      DRIFT=$((DRIFT+1))
    elif [ "$m" = comments ]; then
      fail "$label" "effective lines differ from $live"; DRIFT=$((DRIFT+1))
    else
      warn "$label" "differs from $live -- diff it, then push or pull"; DRIFT=$((DRIFT+1))
    fi
  done
done <<< "$MANIFEST"
pass "mirror files identical" "$SAME in step, $DRIFT drifted, $MISSING not installed"

echo
echo "── Update hygiene ───────────────────────────────────────────────────────────────"

PACNEW=$(find /etc -name '*.pacnew' 2>/dev/null | sort)
PN=$(echo "$PACNEW" | grep -c . )
if [ "$PN" -eq 0 ]; then pass ".pacnew pending" "none"
else
  warn ".pacnew pending" "$PN -- merge before the next upgrade (runbooks/updates.md §2)"
  echo "$PACNEW" | sed 's/^/          /'
fi

if command -v checkupdates >/dev/null; then
  CU=$(checkupdates 2>/dev/null | grep -c . )
  if [ "$CU" -eq 0 ]; then pass "repo updates waiting" "none"
  elif [ "$CU" -lt 150 ]; then note "repo updates waiting" "$CU"
  else warn "repo updates waiting" "$CU -- large queue, upgrade weekly (runbooks/updates.md §1)"; fi
fi

if systemctl is-enabled --quiet paccache.timer 2>/dev/null; then
  pass "paccache.timer" "enabled"
else
  CACHE=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
  warn "paccache.timer" "disabled -- package cache is $CACHE (runbooks/updates.md §5)"
fi

if systemctl is-enabled --quiet limine-snapper-sync.service 2>/dev/null; then
  pass "limine-snapper-sync" "enabled (snapshots become boot entries)"
else
  fail "limine-snapper-sync" "disabled -- an upgrade would have no bootable rollback"
fi

for h in /usr/share/libalpm/hooks/05-snap-pac-pre.hook /usr/share/libalpm/hooks/zz-snap-pac-post.hook; do
  [ -e "$h" ] || { fail "snap-pac hooks" "$h missing -- no automatic pre/post snapshot"; break; }
done
[ -e /usr/share/libalpm/hooks/05-snap-pac-pre.hook ] && pass "snap-pac hooks" "pre + post present"

# The LTS entry is the escape hatch for a bad kernel; it must carry this machine's two
# required parameters. KERNEL_CMDLINE[default] applies to every entry. runbooks/boot-suspend.md §0
CMDLINE=$(grep -h 'KERNEL_CMDLINE\[default\]' /etc/default/limine 2>/dev/null)
for p in thunderbolt.host_reset=0 mem_sleep_default=s2idle; do
  if echo "$CMDLINE" | grep -q -- "$p"; then pass "limine cmdline: $p" "present (all entries)"
  else fail "limine cmdline: $p" "absent from /etc/default/limine"; fi
done

echo
echo "────────────────────────────────────────────────────────────────────────────────"
printf '  %d passed, %d failed, %d warning(s), %d note(s)\n' "$P" "$F" "$W" "$N"
if [ "$F" -gt 0 ]; then
  echo "  A FAIL means an invariant this repo documents is broken. Fix it, or correct"
  echo "  the document that claims it."
  exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$W" -gt 0 ]; then
  echo "  --strict: warnings are fatal. Clear them before upgrading."
  exit 1
fi
exit 0
