# Install-Era Remediation — May 2026

> Archived 2026-11-03. Section numbers are preserved from
> `finish-installation-commands.md`. See `README.md`.

The parts of `finish-installation-commands.md` whose premise was the original May-2026 install: applied once, long superseded, referenced by nothing. Kept because this repo does not delete superseded reasoning. **Do not follow these steps on the current system** — check `../ACTUAL-CONFIGURATION.md` first.

---

# Hyprland Install — Commands to Finish the Setup

**Source:** `system-state-findings.md` (scan from 2026-05-21)
**Goal:** Resolve every actionable item found in the scan, in priority order.
**Conventions:** Run each block top-to-bottom in a Kitty terminal. Reboot only where noted. `sudo` prompts will appear interactively; run commands one section at a time so you can read each result.

> **fish-shell users — heredoc note.** Code blocks below use bash/zsh heredoc syntax (`cat >file <<'EOF' … EOF`, `sudo tee file <<'EOF' … EOF`). **fish does not support heredocs** and will error with `Expected a string, but found a redirection`. Three ways to handle it:
> 1. **Run heredoc blocks inside `bash` interactively.** Type just `bash` (with **no arguments**) at the fish prompt to enter a bash subshell, paste the multi-line block as-is, then type `exit` to return to fish. ⚠ Do **not** try `bash "<heredoc>"` or `bash -c "<heredoc>"` — bash with a string arg treats it as a filename / inline script and the heredoc terminator handling will surprise you. Recommended for the long file-creation heredocs in §1, §3, §7.
> 2. **Replace the heredoc with fish-native `echo`.** Pattern: `echo 'line1\nline2…' >file`. Single quotes keep `$VAR` literal, which is what you want when writing config files. Multi-line literals work inside fish single-quoted strings. §10.d uses this pattern as its primary path; copy that style for the others if you prefer staying in fish.
> 3. **Open the target file in an editor.** `nano <path>` / `nvim <path>` and paste the heredoc body (everything between the `<<'EOF'` and the closing `EOF`). Works in any shell.
>
> For the rest of this doc, plain non-heredoc commands (`sudo pacman`, `sudo systemctl`, `cp`, `grep`, etc.) run identically in fish and bash — no translation needed.

---

## 1. Fix the three failing autostart lines (highest impact)

### 1a. hyprpolkitagent — wrong invocation
The binary isn't on PATH. Two clean options — pick **one**:

**Option A (recommended): use the bundled systemd user unit.**
```bash
# Make sure systemd user instance can see the unit
systemctl --user daemon-reload

# Test it manually first
systemctl --user start hyprpolkitagent.service
systemctl --user status hyprpolkitagent.service --no-pager
```

Then edit autostart so it starts every Hyprland session:
```bash
sed -i 's|^exec-once = hyprpolkitagent$|exec-once = systemctl --user start hyprpolkitagent.service|' \
  ~/.config/hypr/autostart.conf
```

**Option B: call the binary by full path.**
```bash
sed -i 's|^exec-once = hyprpolkitagent$|exec-once = /usr/lib/hyprpolkitagent/hyprpolkitagent|' \
  ~/.config/hypr/autostart.conf
```

Verify the change:
```bash
grep polkit ~/.config/hypr/autostart.conf
```

### 1b. nm-applet — install the missing package
```bash
sudo pacman -S --needed network-manager-applet
# Start it now (so you don't need to relogin to see the tray icon)
nm-applet --indicator &
disown
```

(If you'd rather drop the tray icon entirely, instead delete the `nm-applet` line from `~/.config/hypr/autostart.conf`.)

### 1c. hypridle — write a config, then start the daemon
There is no `~/.config/hypr/hypridle.conf` yet. Drop in a sensible default (lock at 5 min, screen off at 10 min, suspend at 20 min):

```bash
cat > ~/.config/hypr/hypridle.conf <<'EOF'
general {
    lock_cmd = pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch dpms on
    ignore_dbus_inhibit = false
}

listener {
    timeout = 300                          # 5 min
    on-timeout = loginctl lock-session     # lock screen
}

listener {
    timeout = 600                          # 10 min
    on-timeout = hyprctl dispatch dpms off # screen off
    on-resume  = hyprctl dispatch dpms on
}

listener {
    timeout = 1200                         # 20 min
    on-timeout = systemctl suspend         # suspend
}
EOF

# Point autostart at hypridle (it already is; just start it now)
hypridle & disown
pgrep -a hypridle
```

---

## 2. Make hyprpaper actually render the wallpaper

The current `wallpaper = ,` line isn't binding. Use explicit per-monitor entries from the plan:

```bash
cat > ~/.config/hypr/hyprpaper.conf <<'EOF'
preload = ~/Pictures/Wallpapers/wall.jpg
wallpaper = eDP-1, ~/Pictures/Wallpapers/wall.jpg
wallpaper = DP-1, ~/Pictures/Wallpapers/wall.jpg
wallpaper = DP-2, ~/Pictures/Wallpapers/wall.jpg
splash = false
EOF

pkill hyprpaper
hyprpaper & disown
sleep 1
hyprctl hyprpaper listactive   # should now show wall.jpg on all three monitors
```

---

## 3. Drop in the planned Waybar config (Catppuccin Mocha)

Waybar is currently falling back to `/etc/xdg/waybar/`. Replace with the plan's section 6 config:

```bash
mkdir -p ~/.config/waybar

cat > ~/.config/waybar/config.jsonc <<'EOF'
{
  "layer": "top",
  "position": "top",
  "height": 32,
  "spacing": 8,
  "margin-top": 4,
  "margin-left": 8,
  "margin-right": 8,

  "modules-left": ["hyprland/workspaces", "hyprland/window"],
  "modules-center": ["clock"],
  "modules-right": ["tray", "network", "pulseaudio", "battery", "cpu", "memory"],

  "hyprland/workspaces": {
    "format": "{name}",
    "on-click": "activate",
    "sort-by-number": true
  },
  "hyprland/window": {
    "max-length": 60,
    "separate-outputs": true
  },
  "clock": {
    "format": "{:%H:%M  %a %d %b}",
    "tooltip-format": "<tt><small>{calendar}</small></tt>"
  },
  "cpu": { "format": "  {usage}%" },
  "memory": { "format": "  {percentage}%" },
  "battery": {
    "format": "{icon} {capacity}%",
    "format-icons": ["", "", "", "", ""],
    "states": { "warning": 30, "critical": 15 }
  },
  "network": {
    "format-wifi": "  {essid}",
    "format-ethernet": "  {ipaddr}",
    "format-disconnected": "  off"
  },
  "pulseaudio": {
    "format": "{icon} {volume}%",
    "format-muted": "  muted",
    "format-icons": { "default": ["", "", ""] },
    "on-click": "pavucontrol"
  },
  "tray": { "spacing": 8 }
}
EOF

cat > ~/.config/waybar/style.css <<'EOF'
* {
    font-family: "JetBrainsMono Nerd Font", sans-serif;
    font-size: 13px;
    font-weight: 500;
    border: none;
    border-radius: 0;
    min-height: 0;
}

window#waybar {
    background: rgba(30, 30, 46, 0.85);
    color: #cdd6f4;
    border-radius: 10px;
    border: 1px solid rgba(205, 214, 244, 0.1);
}

#workspaces button {
    padding: 0 8px;
    color: #6c7086;
    background: transparent;
    border-radius: 6px;
    margin: 4px 2px;
    transition: all 0.2s;
}
#workspaces button:hover {
    background: rgba(205, 214, 244, 0.1);
    color: #cdd6f4;
}
#workspaces button.active {
    background: rgba(203, 166, 247, 0.2);
    color: #cba6f7;
}

#window, #clock, #cpu, #memory, #battery, #network, #pulseaudio, #tray {
    padding: 0 12px;
    margin: 4px 2px;
    color: #cdd6f4;
}

#clock { color: #f9e2af; font-weight: 600; }
#cpu { color: #89b4fa; }
#memory { color: #a6e3a1; }
#battery { color: #f9e2af; }
#battery.warning { color: #fab387; }
#battery.critical { color: #f38ba8; }
#network { color: #94e2d5; }
#pulseaudio { color: #cba6f7; }
EOF

# Reload waybar
pkill waybar
waybar & disown
```

---

## 4. Fix the qt6ct env var

The `QT_QPA_PLATFORMTHEME=qt6ct` line in `env.conf` points at a package that isn't installed. Install it:

```bash
sudo pacman -S --needed qt6ct kvantum
```

(`kvantum` is the usual companion theme engine for Qt apps under qt6ct — install only if you plan to theme Qt apps. Otherwise just `qt6ct`.)

Then trigger Hyprland to re-read env vars (full relogin is cleanest):
```bash
hyprctl reload
```

If you prefer to skip qt6ct entirely, remove the line instead:
```bash
sed -i '/QT_QPA_PLATFORMTHEME/d' ~/.config/hypr/env.conf
hyprctl reload
```

---

## 9. Final verification

Reboot once everything above is applied, then:

```bash
# Wayland + Hyprland + NVIDIA still healthy?
echo $XDG_SESSION_TYPE $XDG_CURRENT_DESKTOP
uname -r
cat /proc/cmdline | grep -o "nvidia-drm.modeset=."
nvidia-smi | head -5
hyprctl version | head -2

# All autostart daemons running?
for p in waybar mako hyprpaper hypridle hyprpolkitagent swayosd-server nm-applet; do
  echo -n "$p: "; pgrep -a "$p" >/dev/null && echo "OK" || echo "MISSING"
done

# Wallpaper bound?
hyprctl hyprpaper listactive

# Waybar reading user config?
ls ~/.config/waybar/

# Config still valid?
Hyprland --verify-config | tail -3
```

Every line should look healthy. If anything reports MISSING, re-check the relevant section above.

---

## Order of operations summary

| Priority | Section | Reboot needed? |
|---|---|---|
| 🔥 Do first | 1. Autostart fixes (polkit, nm-applet, hypridle) | No |
| 🔥 Do first | 2. Hyprpaper fix | No |
| 🔥 Do first | 3. Waybar Catppuccin config | No |
| ⚠ Recommended | 0. Verify LTS cmdline | No |
| ⚠ Recommended | 4. qt6ct env fix | No (or hyprctl reload) |
| Quality of life | 5. HiDPI scale | No (hyprctl reload) |
| Quality of life | 7. Kitty/Yazi/Hyprlock/Bluetooth/Walker | No |
| Quality of life | 8. Ghostty swap (optional) | No |
| Invasive | 6. Thunderbolt boot fix | YES — and with dock |
| Invasive | 10. Switch DM → getty autologin (fixes phantom cursor at root) | YES |
| ⚠ Recommended | 11. Force `s2idle` (NVIDIA resume black-screen) | Live: No · Persist: YES |
| 🔥 Do first | 12. Firefox-freeze fix: VA-API → iGPU, hardware decode paused | YES — reboot also clears the wedged i915 |
| ✅ Done 2026-07-31 | 13. Install VLC (+ disable its hardware decode, per §12) | No |
| ✅ Verified 2026-10-31 | 14. Battery charge cap at 80% (`acer-wmi-battery-dkms`) — charging stops at 80%, proven | No |
| ✅ Done 2026-10-12 | 15. logind: ignore lid close on external power (written 2026-07-12, installed 2026-10-12) | No |
| ✅ Done 2026-10-16 | 16. Visual monitor layouts: Hyprmon editor + Monitors menu | No |
| ✅ Done 2026-10-31 | 17. Force `predator_v4` → fan RPM + 5-state `platform_profile` | Live: No · **Confirm on the next boot** |
| ✅ Done 2026-10-31 | 18. `triton-panel` GUI (depends on 17) | No |
| ✅ Done 2026-10-31 | 19. Automatic power saving by power source (60 Hz + power-saver on battery) | No |
| ✅ Done 2026-10-31 | 20. Fingerprint: enrol + hyprlock unlock from Triton Panel (enrolment pending) | No |

---

*All commands above are reversible. Take a snapper snapshot before section 6 or 10 if you want belt-and-suspenders safety:*
```bash
sudo snapper -c root create --description "before TB fix / DM switch"
```
