-- Utilities: cheatsheet, lock, notifications, toggles, zoom, capture, media,
-- displays and the lid. Omarchy's map, wired to what this machine actually runs
-- (mako, swayosd, walker, grim/satty, hyprlock) instead of its omarchy-* CLI.
--
-- Punctuation keysyms are written in lower case on purpose: xkbcommon names the
-- comma key "comma" and "COMMA" does not match. The same is assumed for slash,
-- grave and period.
local bind = require("bind")

local HOME = os.getenv("HOME") or ""
local SCRIPTS = HOME .. "/.config/hypr/scripts"

-- ── B1: the cheatsheet is generated from these very descriptions ───────────
bind("SUPER + K", "Keybindings cheatsheet", SCRIPTS .. "/show-shortcuts.sh")
bind("SUPER + slash", nil, SCRIPTS .. "/show-shortcuts.sh")

-- ── Lock ───────────────────────────────────────────────────────────────────
-- Decided 2026-11-03: Omarchy's slot. Super+L is deliberately LEFT FREE for the
-- workspace-layout cycle, which is Omarchy machinery not ported yet.
bind("SUPER + CTRL + L", "Lock system", "hyprlock")

-- ── B3: notifications through mako ─────────────────────────────────────────
bind("SUPER + comma", "Act on last notification", "makoctl invoke")
bind("SUPER + ALT + comma", "Dismiss last notification", "makoctl dismiss")
bind("SUPER + SHIFT + comma", "Dismiss all notifications", "makoctl dismiss --all")
bind("SUPER + SHIFT + ALT + comma", "Restore last dismissed notification", "makoctl restore")

-- ── B5: transparency and gaps ──────────────────────────────────────────────
-- A per-window toggle through a TAG, not a prop: hl.dsp.window.set_prop
-- rejects "alpha" ("Invalid prop name") in 0.57.1, while window.tag works and
-- a rule can key opacity off the tag. Same approach as Omarchy.
hl.window_rule({ match = { tag = "transparent" }, opacity = "0.85 0.75" })

bind("SUPER + BACKSPACE", "Toggle transparency on a window", function()
  local window = hl.get_active_window()
  if not window then
    return
  end

  -- Dynamic tags come back with a trailing "*".
  local tagged = false
  local tags = type(window.tags) == "table" and window.tags or {}
  for _, tag in ipairs(tags) do
    if tag:gsub("%*$", "") == "transparent" then
      tagged = true
    end
  end

  hl.dispatch(hl.dsp.window.tag({ tag = (tagged and "-" or "+") .. "transparent" }))
end)

local gaps = true

bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", function()
  gaps = not gaps
  hl.config({
    general = {
      gaps_in = gaps and 4 or 0,
      gaps_out = gaps and 8 or 0,
    },
  })
end)

-- ── A12: screen zoom ───────────────────────────────────────────────────────
bind("SUPER + CTRL + Z", "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)

bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)

-- ── Capture ────────────────────────────────────────────────────────────────
bind("PRINT", "Screenshot a region", "grim -g \"$(slurp)\" - | satty --filename - --copy-command wl-copy")
bind("SHIFT + PRINT", "Screenshot the screen", "grim - | satty --filename - --copy-command wl-copy")
-- A13: needs `hyprpicker`, which is NOT installed yet — it waits for the next
-- full `paru -Syu` (never `pacman -S` on this machine: runbooks/updates.md §1).
bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")

-- ── Walker pickers ─────────────────────────────────────────────────────────
bind("SUPER + CTRL + V", "Clipboard manager", "walker -m clipboard")
bind("SUPER + CTRL + E", "Emojis and symbols", "walker -m symbols")

-- ── Displays ───────────────────────────────────────────────────────────────
-- The monitor PROFILE system (monitor-mode.sh, monitor-autoswitch.sh) is parked
-- for this migration, so these two do their work natively. Omarchy keeps the
-- same two slots for exactly these jobs.
local function other_monitors()
  local count = 0
  for _, monitor in ipairs(hl.get_monitors()) do
    if monitor.name ~= "eDP-1" then
      count = count + 1
    end
  end
  return count
end

local function enable_edp()
  hl.monitor({ output = "eDP-1", mode = "2560x1600@240", position = "0x0", scale = 1.25 })
  -- Put the refresh rate back under the power source's control.
  hl.exec_cmd(SCRIPTS .. "/edp-rate.sh")
end

bind("SUPER + CTRL + Delete", "Toggle the laptop display", function()
  local edp = hl.get_monitor("eDP-1")

  if edp and edp.enabled then
    if other_monitors() == 0 then
      return -- never leave the session with no screen
    end
    hl.monitor({ output = "eDP-1", disabled = true })
  else
    enable_edp()
  end
end)

-- Super+Ctrl+D is deliberately LEFT FREE. It was going to open the Hyprmon
-- layout editor, but hyprmon is hyprlang-era throughout: its `A` applies a
-- transform with `hyprctl keyword monitor` (removed in 0.57.1) and its `S`
-- rewrites `monitor=` lines in hyprland.conf (now inert), while the JSON
-- profiles its `P` saves are only read by the parked monitor-mode.sh.
-- runbooks/monitors.md §16.

-- ── A9: the lid ────────────────────────────────────────────────────────────
-- Clamshell only: close the built-in panel when the lid shuts AND there is
-- somewhere else to look. Suspend-on-lid stays with logind/hypridle — this
-- bind must not grow into that path (runbooks/boot-suspend.md §15).
bind("switch:on:Lid Switch", nil, function()
  if other_monitors() > 0 then
    hl.monitor({ output = "eDP-1", disabled = true })
  end
end, { locked = true })

bind("switch:off:Lid Switch", nil, function()
  -- Only when the panel is actually off. Re-emitting a mode at an enabled
  -- output is a redundant modeset, and it would race edp-rate.sh: 240 from
  -- here, then 60 from the next tick of the loop, for one lid opening.
  local edp = hl.get_monitor("eDP-1")
  if not edp or not edp.enabled then
    enable_edp()
  end
end, { locked = true })

-- ── Volume, brightness and media (SwayOSD shows the bar) ───────────────────
local osd = { locked = true, repeating = true }

bind("XF86AudioRaiseVolume", nil, "swayosd-client --output-volume raise", osd)
bind("XF86AudioLowerVolume", nil, "swayosd-client --output-volume lower", osd)
bind("XF86AudioMute", nil, "swayosd-client --output-volume mute-toggle", osd)
bind("XF86AudioMicMute", nil, "swayosd-client --input-volume mute-toggle", osd)
bind("XF86MonBrightnessUp", nil, "swayosd-client --brightness raise", osd)
bind("XF86MonBrightnessDown", nil, "swayosd-client --brightness lower", osd)

bind("XF86AudioPlay", nil, "playerctl play-pause", { locked = true })
bind("XF86AudioNext", nil, "playerctl next", { locked = true })
bind("XF86AudioPrev", nil, "playerctl previous", { locked = true })
