-- Look and feel. Colours are the Catppuccin pair this machine has used since
-- the install; a gradient border is a table of colours plus an angle in Lua,
-- where hyprlang took "rgba(..) rgba(..) 45deg".
local active_border = { colors = { "rgba(cba6f7ee)", "rgba(89b4faee)" }, angle = 45 }
local inactive_border = "rgba(313244aa)"

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 2,
    resize_on_border = true,
    layout = "dwindle",

    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },

  decoration = {
    rounding = 8,
    active_opacity = 1.0,
    inactive_opacity = 0.97,

    blur = {
      enabled = true,
      size = 5,
      passes = 2,
      new_optimizations = true,
    },

    shadow = {
      enabled = true,
      range = 12,
      render_power = 2,
      color = "rgba(00000055)",
    },
  },

  -- Window groups (Omarchy's A3) get a visible tab bar; without these the
  -- groupbar is there but unreadable against the Catppuccin borders.
  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },

    groupbar = {
      enabled = true,
      height = 20,
      font_size = 11,
      indicator_height = 2,
      gradients = true,
    },
  },

  dwindle = {
    preserve_split = true,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
  },

  animations = {
    enabled = true,
  },
})

hl.curve("quick", { type = "bezier", points = { { 0.15, 0.85 }, { 0.25, 1.0 } } })

-- Speed is in tenths of a second. Same five animations as the old look.conf.
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "quick", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "quick", style = "slide" })
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "quick" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "quick", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "quick" })
