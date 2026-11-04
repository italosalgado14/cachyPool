-- Monitor geometry: the static 3-across "desktop" layout, in logical pixels.
--
-- Monitors are matched by EDID DESCRIPTION (`desc:` prefix), never by port
-- name. DP-1 and DP-2 swap with plug order on this machine — both externals
-- arrive as DP tunnels over the single Thunderbolt connector, so whichever
-- trains first wins the low number. eDP-1 keeps its port name: the built-in
-- panel never floats.
--
-- Check the live descriptions with:
--   hyprctl monitors -j | jq -r '.[] | "\(.name) = \(.description)"'
--
-- ⚠ monitor-mode.sh and monitor-autoswitch.sh are PARKED for the Lua
-- migration (2026-11-03): this file is now the only owner of geometry, and
-- there is no profile switching or hotplug reconcile. `monitor-mode.sh` still
-- works from a shell once its `hyprctl keyword` sites are ported to
-- `hyprctl eval` — see runbooks/monitors.md §16.
--
-- ⚠ Only eDP-1 was connected when this was written (the TBT4-UD5 dock was
-- unplugged), so the two `desc:` rules below are ported from the old
-- monitors.conf but NOT yet verified live. Verify on the next dock connect.

-- Laptop built-in (leftmost) — 16" HiDPI, 240 Hz, scale 1.25 → 2048 logical.
-- The refresh rate here is only the AC default: scripts/edp-rate.sh drops it to
-- 60 Hz on battery (runbooks/power-battery.md §19).
hl.monitor({ output = "eDP-1", mode = "2560x1600@240", position = "0x0", scale = 1.25 })

-- Xiaomi 27" 4K (centre) — PRIMARY, 60 Hz, scale 1.25 → 3072x1728 logical.
hl.monitor({
  output = "desc:Xiaomi Corporation Mi Monitor",
  mode = "3840x2160@60",
  position = "2048x0",
  scale = 1.25,
})

-- Portable QHD 16" (right) — VCHANCE AQ16H, 120 Hz, scale 1.25 → 2048x1280.
-- Its Realtek scaler publishes no vendor string, so the junk
-- "Invalid Vendor Codename - RTK HDMI" IS the match key and the placeholder
-- serial (0x01010101) cannot disambiguate.
hl.monitor({
  output = "desc:Invalid Vendor Codename - RTK HDMI",
  mode = "2560x1600@120",
  position = "5120x0",
  scale = 1.25,
})
