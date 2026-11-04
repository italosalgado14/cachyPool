-- B2: the universal clipboard. Super+C/V/X/A mean copy/paste/cut/select-all
-- everywhere, translated to Ctrl+Shift in terminals.
--
-- This is Omarchy's clipboard.lua, with their dynamic terminal tag replaced by
-- the static `terminal` tag that windowrules.lua puts on kitty & friends.
--
-- Mods go to the focused surface with the window target omitted, so the
-- shortcuts also reach layer-shell surfaces. A virtual keyboard (wtype) will
-- not do: the physically held SUPER merges into the injected chord at the seat.
-- The down/up split with a 50 ms gap works around Hyprland sometimes leaving
-- synthetic key state stuck or repeating.
-- https://github.com/hyprwm/Hyprland/discussions/14099
--
-- If this ever misbehaves: delete this file and its require in hyprland.lua,
-- and Super+V goes back to being nothing (floating moved to Super+T).
local bind = require("bind")

local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))

    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end

  local tags = type(window.tags) == "table" and window.tags or {}
  for _, tag in ipairs(tags) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end

  return false
end

local function universal(default_mods, default_key, terminal_mods, terminal_key)
  return function()
    if active_window_is_terminal() then
      send_shortcut_once(terminal_mods, terminal_key)()
    else
      send_shortcut_once(default_mods, default_key)()
    end
  end
end

bind("SUPER + A", "Select all", send_shortcut_once("CTRL", "A"))
bind("SUPER + C", "Universal copy", universal("CTRL", "C", "CTRL SHIFT", "C"))
bind("SUPER + V", "Universal paste", universal("CTRL", "V", "CTRL SHIFT", "V"))
bind("SUPER + X", "Universal cut", send_shortcut_once("CTRL", "X"))
