For your stated goals, here's what I'd run:
Compositor: Hyprland (decided) — but keep animations subtle. Edit animations config to use default curves and ~150ms durations, not the 500ms bouncy ones.
Terminal: Ghostty. Mitchell Hashimoto's (HashiCorp founder) terminal. Fast, GPU-accelerated, sane defaults, no Lua config drama. If unavailable on CachyOS, Kitty — battle-tested, image preview support (useful for previewing plots, diffs, etc. in TUI tools).

Status bar: Waybar with a minimal config. Workspaces left, clock center, system tray + battery + network + audio right. No CPU graphs, no weather widgets, no album art. The Omarchy config above is a good template.
App launcher: Walker. Genuinely faster than wofi/rofi, has plugins (calculator, emoji, clipboard, file search), Wayland-native. The current dev favorite.
Notifications: Mako. Simple, configures in 10 lines, has a "do not disturb" toggle. swaync is fine but has more UI than you need.
Lock screen: Hyprlock. Integrated with Hyprland, blurs background, looks clean.
Idle/sleep: Hypridle. Suspends laptop, dims screen, locks after timeout. Pairs with Hyprlock.
Wallpaper: Hyprpaper. Static. Don't install swww unless you want fade transitions between wallpapers — that's a "rice" thing.
Screenshots: grim + slurp + satty (annotation tool). The Omarchy combo. Bind Super+Shift+S.
Clipboard manager: cliphist + Walker plugin. Super+V to paste from history.
Auth prompts: hyprpolkitagent. Lightweight, matches Hyprland aesthetic.
Audio/brightness OSD: SwayOSD. The little volume/brightness popup when you press laptop hotkeys.
File manager: Yazi (terminal, Rust, image previews via Kitty graphics, vim-like). For occasional GUI need, keep KDE's Dolphin — it's already installed and excellent.
Editor: Use what you already use. If you're a Neovim person, LazyVim is the current default starter config. If you're VS Code, just keep VS Code — running it on Wayland works fine.
Theme: Catppuccin Mocha. It is the dev theme of 2025-2026. Subtle, dark, low-contrast, easy on eyes for long sessions. Everything I listed above has a Catppuccin theme officially. Alternative: Tokyo Night (slightly more contrast).
Font: JetBrains Mono Nerd Font (with ligatures and dev icons). Install: sudo pacman -S ttf-jetbrains-mono-nerd. Alternative: Iosevka Nerd Font if you prefer narrower characters.