#!/usr/bin/env bash
# waybar-acer.sh — one Waybar module for everything the Acer EC exposes on this
# machine: fan RPM, EC temperatures, the active platform profile, and the state
# of the 80% battery charge cap.
#
# Requires the in-kernel acer_wmi loaded with predator_v4=1
# (/etc/modprobe.d/acer-wmi-predator-v4.conf). Without that parameter the driver
# never selects quirk_acer_predator_v4 — the PT516-52s is absent from its DMI
# quirk table — so neither the hwmon nor platform_profile exists and this module
# degrades to a dash instead of lying.
#
# Never hardcode hwmonN: the index is handed out in probe order and moves between
# boots. /sys/devices/platform/acer-wmi/hwmon is the stable parent.
#
# Both fans really do read 0 RPM on a cool machine — this laptop stops them below
# roughly 50 C (verified 2026-10-31 under load: 0/0 at 41 C, 2564/2307 at 56 C).
# A 0 here is not a read failure.

set -u

HWDIR_GLOB=(/sys/devices/platform/acer-wmi/hwmon/hwmon*)
HWDIR=${HWDIR_GLOB[0]}
PROFILE=/sys/firmware/acpi/platform_profile
CAP=/sys/bus/wmi/drivers/acer-wmi-battery/health_mode

# Reads a sysfs file, or echoes the fallback when it is missing/unreadable.
read_sysfs() {
  local path=$1 fallback=$2 value
  if [[ -r $path ]] && read -r value < "$path" 2>/dev/null; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

if [[ ! -r $HWDIR/fan1_input ]]; then
  printf '{"text":" --","tooltip":"No acer_wmi hwmon.\\nIs predator_v4=1 set? Check: cat /sys/module/acer_wmi/parameters/predator_v4","class":"unavailable"}\n'
  exit 0
fi

fan1=$(read_sysfs "$HWDIR/fan1_input" 0)
fan2=$(read_sysfs "$HWDIR/fan2_input" 0)
# temp2_input is wired but always reads 0 on this board; skip it.
temp1=$(( $(read_sysfs "$HWDIR/temp1_input" 0) / 1000 ))
temp3=$(( $(read_sysfs "$HWDIR/temp3_input" 0) / 1000 ))

profile=$(read_sysfs "$PROFILE" "n/a")

case "$(read_sysfs "$CAP" "missing")" in
  1) cap="on (stops near 80%)" ;;
  0) cap="off (charges to 100%)" ;;
  *) cap="unknown — acer-wmi-battery not loaded?" ;;
esac

# The hotter fan drives the bar text; the tooltip carries the detail.
rpm=$(( fan1 > fan2 ? fan1 : fan2 ))
if (( rpm == 0 )); then
  class="idle"
elif (( rpm >= 4000 )); then
  class="high"
else
  class="active"
fi

printf '{"text":" %s  %s°C","tooltip":"Fans: %s / %s RPM\\nEC temps: %s°C / %s°C\\nPlatform profile: %s\\nCharge cap: %s","class":"%s"}\n' \
  "$rpm" "$temp1" "$fan1" "$fan2" "$temp1" "$temp3" "$profile" "$cap" "$class"
