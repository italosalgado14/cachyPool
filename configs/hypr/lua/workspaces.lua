-- Per-monitor workspaces (Omarchy's B4), with STATIC blocks anchored by EDID.
--
-- Each panel owns ten slots of its own, so Super+1..0 always means "the Nth
-- workspace of the screen I am looking at":
--
--   eDP-1                     slots 1-10  → workspace ids  1-10
--   Xiaomi 27" 4K             slots 1-10  → workspace ids 11-20
--   VCHANCE AQ16H portable    slots 1-10  → workspace ids 21-30
--   anything else             slots 1-10  → workspace ids 91-100
--
-- WHY NOT Omarchy's own monitor-workspaces.lua: it is 713 lines with
-- persistent state files and dynamic block re-allocation, and its tie-break
-- when two panels share a description is `left.name < right.name` — ordering by
-- CONNECTOR NAME, which is exactly what rotates between DP-1/DP-2 here. With
-- three known panels, a fixed block anchored to the EDID description is both
-- shorter and harder to get wrong. The keyboard semantics are identical.
--
-- The cost of the static scheme: an unknown monitor lands in the 91-100
-- fallback block and shares it with any other unknown. Add a row to BLOCKS
-- when a fourth panel becomes permanent.

local SLOTS = 10
local FALLBACK_BASE = 90

-- Order is left-to-right on the desk; `name` matches a connector exactly,
-- `desc` is a prefix match against the EDID description.
local BLOCKS = {
  { name = "eDP-1", base = 0 },
  { desc = "Xiaomi Corporation Mi Monitor", base = 10 },
  { desc = "Invalid Vendor Codename - RTK HDMI", base = 20 },
}

local M = {}

local function base_of(monitor)
  if not monitor then
    return 0
  end

  for _, block in ipairs(BLOCKS) do
    if block.name and monitor.name == block.name then
      return block.base
    end

    local description = monitor.description or ""
    if block.desc and description:sub(1, #block.desc) == block.desc then
      return block.base
    end
  end

  return FALLBACK_BASE
end

-- The workspace id of a slot on a monitor (the focused one unless given).
function M.id(slot, monitor)
  return base_of(monitor or hl.get_active_monitor()) + slot
end

-- Go to a slot on the focused monitor.
function M.focus(slot)
  return function()
    local monitor = hl.get_active_monitor()
    if not monitor then
      return
    end

    hl.dispatch(hl.dsp.focus({ workspace = tostring(M.id(slot, monitor)) }))
  end
end

-- Move the active window to a slot on the focused monitor. `follow == false`
-- sends it without taking the focus along (Omarchy's "move silently").
function M.move_window(slot, follow)
  return function()
    local window = hl.get_active_window()
    local monitor = hl.get_active_monitor()
    if not window or not monitor then
      return
    end

    hl.dispatch(hl.dsp.window.move({
      workspace = tostring(M.id(slot, monitor)),
      follow = follow ~= false,
      window = "address:" .. window.address,
    }))
  end
end

-- Move the whole active workspace to the monitor in a direction ("l"/"r"/"u"/"d").
-- Hyprland reports a move toward no monitor as an error on screen, so check first.
function M.move_to_monitor(direction)
  return function()
    local target = hl.get_monitor(direction)
    if not target then
      return
    end

    hl.dispatch(hl.dsp.workspace.move({ monitor = target.name }))
  end
end

-- Move just the focused window to whatever the monitor in that direction shows.
function M.move_window_to_monitor(direction)
  return function()
    local target = hl.get_monitor(direction)
    if not target then
      return
    end

    hl.dispatch(hl.dsp.window.move({ monitor = target.name }))
  end
end

-- Pin every slot to its panel, and make each block's first slot that panel's
-- default workspace. Bound by description for the same reason as the geometry.
for _, block in ipairs(BLOCKS) do
  for slot = 1, SLOTS do
    hl.workspace_rule({
      workspace = tostring(block.base + slot),
      monitor = block.name or ("desc:" .. block.desc),
      default = slot == 1,
    })
  end
end

return M
