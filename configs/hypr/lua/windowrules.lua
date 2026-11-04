-- Window rules. The Lua form is hl.window_rule({ match = {...}, <effects> }),
-- where `match.class` / `match.title` are REGEXES matched in full and the
-- effects are plain keys (float, center, pin, size, tag, border_size…).
-- Syntax verified against Omarchy's default/hypr/apps/*.lua.

-- Terminals get a `terminal` tag, so one definition decides what counts as a
-- terminal. bindings-clipboard.lua reads it to pick Ctrl+Shift+C over Ctrl+C.
hl.window_rule({
  match = { class = "(kitty|foot|org\\.codeberg\\.dnkl\\.foot|Alacritty|com\\.mitchellh\\.ghostty)" },
  tag = "+terminal",
})

-- Float common dialog/utility windows
hl.window_rule({ match = { class = "pavucontrol" }, float = true })
hl.window_rule({ match = { class = "nm-connection-editor" }, float = true })
hl.window_rule({ match = { class = "blueman-manager" }, float = true })
hl.window_rule({ match = { class = "\\.blueman-manager-wrapped" }, float = true })
hl.window_rule({ match = { class = "file-roller" }, float = true })
hl.window_rule({ match = { class = "org\\.gnome\\.Calculator" }, float = true })

-- Picture-in-Picture (browser video popouts)
hl.window_rule({
  match = { title = "Picture.?in.?[Pp]icture" },
  float = true,
  pin = true,
  size = { 480, 270 },
})

-- Authentication dialogs
hl.window_rule({ match = { class = "hyprpolkitagent" }, float = true })
hl.window_rule({ match = { class = "polkit-kde-authentication-agent-1" }, float = true })

-- File pickers / dialogs: the portal only ever shows dialogs.
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, float = true })

-- Shortcuts cheatsheet popup (scripts/show-shortcuts.sh, Super+K)
hl.window_rule({
  match = { class = "shortcuts-cheatsheet" },
  float = true,
  center = true,
  size = { 880, 780 },
})

-- Hyprmon monitor-layout editor (scripts/hyprmon-edit.sh, Super+Ctrl+D)
hl.window_rule({
  match = { class = "hyprmon-edit" },
  float = true,
  center = true,
  size = { 1200, 800 },
})

-- Triton Panel hardware monitor. The class is the GTK application id, which is
-- also the .desktop's StartupWMClass — keep the three in step or it opens tiled.
hl.window_rule({
  match = { class = "dev\\.isalgado\\.TritonPanel" },
  float = true,
  center = true,
  size = { 900, 860 },
})
