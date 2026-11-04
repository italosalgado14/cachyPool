-- Application bindings. Omarchy's slots, this machine's apps.
local bind = require("bind")

bind("SUPER + RETURN", "Terminal", "kitty")
bind("SUPER + SHIFT + RETURN", "Browser", "firefox")

-- Omarchy opens its own root menu here; ours is Walker, which is the launcher
-- AND the entry point for the "Monitors" / "Shortcuts" / "Triton Panel" items.
bind("SUPER + SPACE", "Launcher", "walker")

-- Omarchy's file-manager slot, plus the Super+E this machine has always used.
bind("SUPER + SHIFT + F", "File manager", "kitty -e yazi")
bind("SUPER + E", nil, "kitty -e yazi")

-- Omarchy closes with either W or Q; both are kept.
bind("SUPER + W", "Close window", hl.dsp.window.close())
bind("SUPER + Q", "Close window", hl.dsp.window.close())

-- Omarchy routes exit through its system menu, which this machine does not
-- have. Keep an explicit exit or the keyboard has no way out.
bind("SUPER + SHIFT + Q", "Exit Hyprland", hl.dsp.exit())
