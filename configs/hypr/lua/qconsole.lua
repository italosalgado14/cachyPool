-- The Quake console (Omarchy's A1): a terminal that drops over whatever
-- workspace you are on, on its own special workspace, separate from the
-- full-size scratchpad on Super+S. Its binds live in bindings-tiling.lua.
--
-- This is a trimmed version of Omarchy's qconsole.lua: the slide animation and
-- the single-window centring box are left out, the drop-down and the per-monitor
-- refit are kept — the refit matters here because the three panels have very
-- different logical heights (1280 / 1728 / 1280).

local CONSOLE = "special:qconsole"

-- How much of the screen the console covers, measured from the top.
local SHARE = 0.5

-- Dimming only applies while a special workspace is open, so the console gets
-- its separation from the workspace underneath for free.
hl.config({
  decoration = {
    dim_special = 0.6,
  },
})

-- Refitting replaces the rule in place, but it still schedules a monitor and
-- window state refresh, and monitor.focused fires on every hop between
-- screens — so only write the rule when the gaps actually move.
local beside, below = nil, nil

local function cover(side, bottom)
  if beside == side and below == bottom then
    return
  end
  beside, below = side, bottom

  hl.workspace_rule({
    workspace = CONSOLE,
    gaps_in = 0,
    gaps_out = { top = 0, right = side, bottom = bottom, left = side },
  })
end

local function refit()
  local monitor = hl.get_active_monitor()
  if not monitor then
    return
  end

  local scale = monitor.scale or 1
  if scale == 0 then
    scale = 1
  end

  local width = (monitor.width or 0) / scale
  local height = (monitor.height or 0) / scale

  cover(math.floor(width * 0.02), math.floor(height * (1 - SHARE)))
end

refit()
hl.on("monitor.focused", refit)
hl.on("monitor.layout_changed", refit)

-- Seed the console with a terminal the first time it opens, rather than at
-- boot, so nothing is running until it is wanted. A console created by moving a
-- window onto it is not empty, and is left alone. The exec rule has to pin the
-- workspace itself.
hl.on("workspace.created", function(workspace)
  if not workspace or workspace.name ~= CONSOLE then
    return
  end

  local empty = workspace.is_empty
  if empty == nil then
    empty = (workspace.windows or 0) == 0
  end

  if empty then
    hl.exec_cmd("kitty", { workspace = CONSOLE .. " silent" })
  end
end)
