-- Tiling, workspaces, monitors and groups — Omarchy's map (A2-A7, A10, A11,
-- A3), with this machine's per-monitor workspace blocks from workspaces.lua.
local bind = require("bind")
local workspaces = require("workspaces")

-- ── Window state ───────────────────────────────────────────────────────────
bind("SUPER + J", "Toggle window split", hl.dsp.layout("togglesplit"))
bind("SUPER + P", "Pseudo window", hl.dsp.window.pseudo())
bind("SUPER + T", "Toggle window floating/tiling", hl.dsp.window.float({ action = "toggle" }))
bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
-- A10: fullscreen COVERS the screen, maximized fills the tiled space. Two things.
bind("SUPER + ALT + F", "Full width (maximized)", hl.dsp.window.fullscreen({ mode = "maximized" }))

-- ── Focus ──────────────────────────────────────────────────────────────────
bind("SUPER + LEFT", "Focus on left window", hl.dsp.focus({ direction = "l" }))
bind("SUPER + RIGHT", "Focus on right window", hl.dsp.focus({ direction = "r" }))
bind("SUPER + UP", "Focus on above window", hl.dsp.focus({ direction = "u" }))
bind("SUPER + DOWN", "Focus on below window", hl.dsp.focus({ direction = "d" }))

-- ── A11: swap positions, where the old map moved the window ────────────────
bind("SUPER + SHIFT + LEFT", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
bind("SUPER + SHIFT + RIGHT", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
bind("SUPER + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
bind("SUPER + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))

-- ── B4: each monitor has ten workspaces of its own ─────────────────────────
-- Written as keycodes (A8): code:10-19 are the number row whatever the layout
-- maps them to, so the binds survive a layout change.
for slot = 1, 10 do
  local key = "code:" .. tostring(slot + 9)

  bind("SUPER + " .. key, "Switch to workspace " .. slot, workspaces.focus(slot))
  bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. slot, workspaces.move_window(slot))
  bind(
    "SUPER + SHIFT + ALT + " .. key,
    "Move window silently to workspace " .. slot,
    workspaces.move_window(slot, false)
  )
end

-- ── A7: walk the focused monitor's own workspaces ──────────────────────────
bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "m+1" }))
bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "m-1" }))
bind("SUPER + CTRL + TAB", "Former workspace", hl.dsp.focus({ workspace = "previous_per_monitor" }))

-- ── A6: workspace or window across monitors ────────────────────────────────
bind("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", workspaces.move_to_monitor("l"))
bind("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", workspaces.move_to_monitor("r"))
bind("SUPER + SHIFT + ALT + UP", "Move workspace to up monitor", workspaces.move_to_monitor("u"))
bind("SUPER + SHIFT + ALT + DOWN", "Move workspace to down monitor", workspaces.move_to_monitor("d"))

bind("SUPER + SHIFT + CTRL + LEFT", "Move window to left monitor", workspaces.move_window_to_monitor("l"))
bind("SUPER + SHIFT + CTRL + RIGHT", "Move window to right monitor", workspaces.move_window_to_monitor("r"))
bind("SUPER + SHIFT + CTRL + UP", "Move window to up monitor", workspaces.move_window_to_monitor("u"))
bind("SUPER + SHIFT + CTRL + DOWN", "Move window to down monitor", workspaces.move_window_to_monitor("d"))

bind("CTRL + ALT + TAB", "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }))
bind("CTRL + ALT + SHIFT + TAB", "Focus on previous monitor", hl.dsp.focus({ monitor = "-1" }))

-- ── A2 scratchpad, A1 Quake console, B6 minimize ───────────────────────────
bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
bind(
  "SUPER + ALT + S",
  "Move window to scratchpad",
  hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })
)

bind("SUPER + grave", "Toggle Quake console", hl.dsp.workspace.toggle_special("qconsole"))
bind(
  "SUPER + SHIFT + grave",
  "Move window to Quake console",
  hl.dsp.window.move({ workspace = "special:qconsole", follow = false })
)

-- Omarchy minimizes to its dock; this machine has none, so a window goes to a
-- special workspace and Super+Shift+M is how it comes back.
bind("SUPER + M", "Minimize window", hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
bind("SUPER + SHIFT + M", "Show minimized windows", hl.dsp.workspace.toggle_special("minimized"))

-- ── A4: Alt+Tab ────────────────────────────────────────────────────────────
-- Going backwards lowers the window it leaves instead of raising the one it
-- lands on: bring_to_top moves the active window to the end of the same list
-- cycle_next walks, so a raise here ping-pongs. (Omarchy's note, kept.)
bind("ALT + SHIFT + TAB", nil, hl.dsp.window.alter_zorder({ mode = "bottom" }))
bind("ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())
bind("ALT + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
bind("ALT + TAB", nil, hl.dsp.window.bring_to_top())

-- ── A5: resize from the keyboard in three scales ───────────────────────────
-- code:20 is the key left of "=", code:21 is "=" — the pair next to Backspace.
bind("SUPER + code:20", "Expand window left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
bind("SUPER + code:21", "Shrink window left", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
bind("SUPER + SHIFT + code:20", "Shrink window up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
bind("SUPER + SHIFT + code:21", "Expand window down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))

bind("SUPER + ALT + code:20", "Expand window left a little", hl.dsp.window.resize({ x = -25, y = 0, relative = true }))
bind("SUPER + ALT + code:21", "Shrink window left a little", hl.dsp.window.resize({ x = 25, y = 0, relative = true }))
bind("SUPER + SHIFT + ALT + code:20", nil, hl.dsp.window.resize({ x = 0, y = -25, relative = true }))
bind("SUPER + SHIFT + ALT + code:21", nil, hl.dsp.window.resize({ x = 0, y = 25, relative = true }))

bind("SUPER + CTRL + code:20", "Expand window left a lot", hl.dsp.window.resize({ x = -300, y = 0, relative = true }))
bind("SUPER + CTRL + code:21", "Shrink window left a lot", hl.dsp.window.resize({ x = 300, y = 0, relative = true }))
bind("SUPER + CTRL + SHIFT + code:20", nil, hl.dsp.window.resize({ x = 0, y = -300, relative = true }))
bind("SUPER + CTRL + SHIFT + code:21", nil, hl.dsp.window.resize({ x = 0, y = 300, relative = true }))

-- ── Mouse ──────────────────────────────────────────────────────────────────
bind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "m+1" }))
bind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "m-1" }))
bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

-- ── A3: window groups (tabs) ───────────────────────────────────────────────
bind("SUPER + G", "Toggle window grouping", hl.dsp.group.toggle())
bind("SUPER + ALT + G", "Move active window out of group", hl.dsp.window.move({ out_of_group = true }))

bind("SUPER + ALT + LEFT", "Move window to group on left", hl.dsp.window.move({ into_group = "l" }))
bind("SUPER + ALT + RIGHT", "Move window to group on right", hl.dsp.window.move({ into_group = "r" }))
bind("SUPER + ALT + UP", "Move window to group on top", hl.dsp.window.move({ into_group = "u" }))
bind("SUPER + ALT + DOWN", "Move window to group on bottom", hl.dsp.window.move({ into_group = "d" }))

bind("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())
bind("SUPER + ALT + SHIFT + TAB", "Previous window in group", hl.dsp.group.prev())
bind("SUPER + CTRL + LEFT", "Move grouped window focus left", hl.dsp.group.prev())
bind("SUPER + CTRL + RIGHT", "Move grouped window focus right", hl.dsp.group.next())

for index = 1, 5 do
  bind(
    "SUPER + ALT + code:" .. tostring(index + 9),
    "Switch to group window " .. index,
    hl.dsp.group.active({ index = index })
  )
end
