-- Input. Key names verified against /usr/share/hypr/stubs/hl.meta.lua — the
-- Lua keys use underscores where hyprlang used dashes (`tap_to_click`, not
-- `tap-to-click`), and a wrong key is accepted in silence.
hl.config({
  input = {
    kb_layout = "us",
    follow_mouse = 1,
    sensitivity = 0,

    touchpad = {
      natural_scroll = true,
      tap_to_click = true,
      disable_while_typing = true,
    },
  },
})

-- Three-finger horizontal swipe through workspaces. Hyprland rejects a second
-- gesture on the same fingers+direction, so overriding one means unsetting it
-- first: hl.gesture({ fingers = 3, direction = "left", action = "unset" }).
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
