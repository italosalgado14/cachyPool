# Daily Usability Guide — Hyprland on CachyOS

**Machine:** Acer Predator PT516-52s (Triton 500 SE) · **Last verified:** 2026-05-21

This is the practical "how do I use this thing day-to-day" reference for the current Hyprland setup. All keybindings below are pulled from `~/.config/hypr/keybindings.conf` (mirrored in `configs/hypr/keybindings.conf` in this repo).

> **`Super`** = Windows/⌘ key (a.k.a. `mainMod`). Everything below uses Super as the anchor.

---

## 1. Core Shortcuts — Cheat Sheet

### Launching things

| Combo | Action |
|---|---|
| `Super` + `Enter` | Open Kitty terminal |
| `Super` + `Space` | Walker app launcher |
| `Super` + `Shift` + `Enter` | Open Firefox |
| `Super` + `E` | Open file manager (Yazi in Kitty) |
| `Super` + `L` | Lock screen (Hyprlock) |
| `Super` + `Shift` + `Q` | Exit Hyprland (logout) |

### Walker modes (also reachable by typing a prefix character into Walker)

| Combo | Mode | Prefix |
|---|---|---|
| `Super` + `Ctrl` + `E` | Emoji / symbol picker | `.` |
| `Super` + `Ctrl` + `V` | Clipboard history (from cliphist) | `:` |
| (in Walker) type `=` | Calculator | `=` |
| (in Walker) type `/` | File search | `/` |
| (in Walker) type `>` | Shell command runner | `>` |
| (in Walker) type `?` | Web search | `?` |

### Window management

| Combo | Action |
|---|---|
| `Super` + `Q` | Close active window |
| `Super` + `F` | Toggle fullscreen |
| `Super` + `V` | Toggle floating |
| `Super` + `P` | Pseudo-tile (preserve size when moving) |
| `Super` + `J` | Toggle dwindle split direction |

### Navigation (focus)

| Combo | Action |
|---|---|
| `Super` + `←` / `→` / `↑` / `↓` | Focus neighbor window |
| `Super` + drag (left mouse) | Move window |
| `Super` + drag (right mouse) | Resize window |
| `Super` + scroll | Cycle through workspaces |

### Moving windows

| Combo | Action |
|---|---|
| `Super` + `Shift` + `←` / `→` / `↑` / `↓` | Move active window in that direction |

### Workspaces

| Combo | Action |
|---|---|
| `Super` + `1`…`9` | Switch to workspace N |
| `Super` + `Shift` + `1`…`9` | Send active window to workspace N |

> Workspaces 1–3 live on **DP-1 (Samsung)** · 4–5 on **eDP-1 (laptop)** · 6–9 on **DP-2 (HDMI right)**.
> Workspace `1` (Samsung) is the default for new windows.

### Screenshots

| Combo | Action |
|---|---|
| `Print` | Region capture → opens **satty** for annotation → copies to clipboard |
| `Shift` + `Print` | Full-screen capture → opens satty → copies to clipboard |

### Audio / brightness (via SwayOSD popups)

| Key | Action |
|---|---|
| `Fn` + Volume Up/Down/Mute | Adjust output volume |
| `Fn` + Mic Mute | Toggle microphone |
| `Fn` + Brightness Up/Down | Backlight (`nvidia_wmi_ec_backlight`) |
| Media keys (Play/Next/Prev) | Control playerctl-aware apps (Spotify, browsers) |

### Touchpad gesture

| Gesture | Action |
|---|---|
| 3-finger horizontal swipe | Switch workspace |

---

## 2. Recommended Daily Workflows

### A. "Start a coding session"

1. `Super` + `Enter` → open Kitty
2. `cd ~/code/<project>` then `code .` (VS Code) — VS Code is installed (`visual-studio-code-bin`) and runs on Wayland via the `ELECTRON_OZONE_PLATFORM_HINT=auto` env in `env.conf`.
3. `Super` + `2` to keep VS Code on a clean workspace (Samsung primary)
4. Another Kitty on `Super` + `3` for `git`/build commands.
5. If you need a side-by-side editor + browser:
   - VS Code on workspace `2` (Samsung)
   - Firefox (`Super` + `Shift` + `Enter`) → workspace `6` (HDMI right) for docs/MDN/preview
   - Workspace `4`/`5` on the laptop for logs / terminal output

### B. "I need to look something up fast"

- `Super` + `Space` → start typing. Walker fuzzy-matches installed apps + recents.
- Need to calculate something? `Super` + `Space`, then `=` → `2048 * 1.25` → `Enter` copies result.
- Insert an emoji into a chat? `Super` + `Ctrl` + `E` → type `smile` → `Enter` pastes.

### C. "I copied something earlier and lost it"

- `Super` + `Ctrl` + `V` → Walker opens with full clipboard history (powered by `cliphist`, fed by the two `wl-paste --watch` autostart entries).
- `cliphist` retains both text and images.

### D. "Manage tiling — I want this window over there"

The compositor is **dwindle**: every new window splits the focused space in half along its longer axis.

1. **Focus the window** you want to move (`Super` + arrows or click).
2. **`Super` + `Shift` + arrow** — slot it into a neighbor position.
3. To change *how* the split happened (vertical ↔ horizontal): focus the window, `Super` + `J`.
4. To break out of tiling for a single window: `Super` + `V` (toggle floating). Then drag with `Super` + left-mouse to move it freely, `Super` + right-mouse to resize.
5. To send a window to another monitor's workspace: `Super` + `Shift` + (`1`/`2`/`3` for Samsung, `4`/`5` for laptop, `6`–`9` for HDMI). Then follow with `Super` + N to jump to that workspace.

### E. "Quick screenshot for a bug report / Slack"

- Region: `Print` → drag to select → satty opens. Annotate with arrows/text/blur → press `Ctrl`+`C` (or close) → result is on your clipboard, ready to paste.
- Full screen: `Shift` + `Print`.

### F. "I'm done for the day"

- `Super` + `L` → lock immediately. Hyprlock shows a blurred wallpaper + clock + password input.
- Or just walk away — Hypridle handles it:
  - 5 min idle → lock screen
  - 10 min idle → monitors sleep (DPMS off)
  - 20 min idle → system suspend

### G. "Bluetooth headphones / mouse"

- Tray icon in Waybar (right cluster) — click to open Blueman.
- Or CLI: `bluetoothctl scan on` → `pair XX:XX:...` → `connect XX:XX:...`.

### H. "WiFi / Network"

- `nm-applet` tray icon (right cluster) → click → list of networks.
- Or CLI: `nmcli device wifi list` / `nmcli device wifi connect <SSID> password <pw>`.

---

## 3. Multi-Monitor Layout (current)

Effective horizontal layout, left to right:

```
[ eDP-1 laptop ]  [ DP-1 Samsung ]  [ DP-2 HDMI right ]
  2048 × 1280        1920 × 1080       2048 × 1280
   scale 1.25         scale 1.00        scale 1.25
   0px – 2048px       2048 – 3968px     3968 – 6016px
   240 Hz             120 Hz            120 Hz
```

- **Samsung is primary** — workspace 1 lives there and new windows default to it.
- Workspaces 4 / 5 live on the laptop.
- Workspaces 6–9 live on the HDMI right monitor.
- Move the cursor straight across the seam to traverse monitors.

> If you want bigger UI on the laptop later: bump `eDP-1` scale to `1.333333` and shift positions to `DP-1 @ 1920x0`, `DP-2 @ 3840x0`. See `system-state-findings.md` and `finish-installation-commands.md` for the math.

---

## 4. Walker — How to Drive It

Walker (`Super` + `Space`) replaces rofi/wofi/krunner. Behaviors that are easy to miss:

- **Empty input** → recent apps + applications list
- **Type a partial name** → fuzzy match across apps + calculator results inline
- **Prefix character at start** switches mode:
  - `.foo` → emoji/symbol named "foo"
  - `=2+2` → calculator
  - `:` → clipboard history
  - `/Pictures` → file search under home dir
  - `>htop` → run as shell command
  - `?rust async` → web search
- **Enter** activates the highlighted item
- **Shift + Enter** activates AND keeps Walker open (launch multiple apps in a row)
- **Escape** cancels
- **Up / Down** or **Ctrl-K / Ctrl-J** navigate the list

Walker runs as a resident service (`exec-once = walker --gapplication-service` in autostart), so opening it is near-instant.

---

## 5. Yazi — Terminal File Manager

`Super` + `E` opens Yazi inside Kitty. Vim-style by default.

Common keys (Yazi defaults — no custom config needed):

| Key | Action |
|---|---|
| `h` / `l` | Up a directory / enter directory |
| `j` / `k` | Down / up |
| `gg` / `G` | Top / bottom of list |
| `Space` | Toggle selection |
| `Enter` | Open file (text → micro / images → default viewer) |
| `y` / `x` / `p` | Yank (copy) / cut / paste |
| `d` | Delete (to trash) |
| `D` | Permanent delete |
| `a` | New file/dir (end in `/` for dir) |
| `r` | Rename |
| `.` | Toggle hidden files |
| `q` | Quit |

Image previews render in the right pane via Kitty's graphics protocol.

---

## 6. Kitty — Terminal Tips

The terminal uses JetBrains Mono Nerd Font 12pt + Catppuccin Mocha theme + 95% background opacity. Useful built-ins:

| Combo | Action |
|---|---|
| `Ctrl` + `Shift` + `T` | New tab |
| `Ctrl` + `Shift` + `Enter` | New split (window) inside Kitty |
| `Ctrl` + `Shift` + `]` / `[` | Next / previous split |
| `Ctrl` + `Shift` + `C` / `V` | Copy / paste |
| `Ctrl` + `Shift` + `+` / `-` | Font size up / down |
| `Ctrl` + `Shift` + `F2` | Edit kitty.conf live |
| `kitten icat IMAGE` | Show an image inline in the terminal |

---

## 7. Lock Screen / Idle

- **Manual lock:** `Super` + `L`
- **Auto-lock:** 5 minutes of input idle
- **Screen off:** 10 minutes
- **Suspend:** 20 minutes (will require password to resume)
- **Lid close:** triggers `loginctl lock-session` then suspend (handled by logind defaults, not hypridle)

To customize timeouts: edit `~/.config/hypr/hypridle.conf` and `hyprctl reload`.

---

## 8. Sound / Mic

- PipeWire is the audio server (PulseAudio compatibility layer also active).
- Volume keys handled by SwayOSD → on-screen popup.
- Click the Pulseaudio icon in Waybar to open `pavucontrol` for routing, app-level volumes, default device.
- Current default output: **Samson Go Mic** (USB) — change in pavucontrol if you plug in different headphones.

---

## 9. Troubleshooting Quick Reference

| Symptom | Fix |
|---|---|
| Waybar disappeared | `pkill waybar; waybar & disown` |
| Wallpaper gone | `pkill hyprpaper; hyprpaper & disown` |
| Tray icon missing | Check `nm-applet`/`blueman-applet` is in `autostart.conf` and running |
| Walker won't open | `pkill walker; walker --gapplication-service & disown` |
| Need to reload everything | `hyprctl reload` (re-reads all configs without logout) |
| Brightness key not working | `brightnessctl set 50%` to verify backlight works; check `swayosd-server` is running |
| Audio not working | `systemctl --user restart pipewire wireplumber pipewire-pulse` |

Check daemon liveness anytime:
```fish
for p in waybar mako hyprpaper hypridle hyprpolkitagent swayosd-server cliphist walker nm-applet
  pgrep -af $p > /dev/null; and echo "$p: OK"; or echo "$p: DOWN"
end
```

---

## 10. What I Don't Use But It's There

- **Dolphin** (`dolphin`) — KDE's GUI file manager, installed because KDE-Desktop is the safety-net DE. Useful for "I need to drag-and-drop files" moments.
- **Micro** (`micro`) — terminal text editor with sane defaults; opened by Yazi's `Enter` on text files.
- **KDE apps** (Konsole, KCalc, etc.) — installed via the KDE fallback, can be launched from Walker if needed.

---

## 11. The Three Files You'll Edit Most

| File | What it controls |
|---|---|
| `~/.config/hypr/keybindings.conf` | Add/remove keyboard shortcuts |
| `~/.config/hypr/monitors.conf` | Display layout, scale, position |
| `~/.config/hypr/autostart.conf` | What launches when you log in |

After any change: `hyprctl reload` (no logout needed). Tracked copies live in `configs/hypr/` in this repo.

---

*Last regenerated 2026-05-21 from live state via the scan in `system-state-findings.md`.*
