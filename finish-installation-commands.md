# Hyprland Install — Commands to Finish the Setup

**Source:** `system-state-findings.md` (scan from 2026-05-21)
**Goal:** Resolve every actionable item found in the scan, in priority order.
**Conventions:** Run each block top-to-bottom in a Kitty terminal. Reboot only where noted. `sudo` prompts will appear interactively; run commands one section at a time so you can read each result.

---

## 0. Pre-flight — Fix LTS kernel cmdline (CONFIRMED ISSUE)

**Verified state from `/boot/limine.conf`:**
- ✅ `linux-cachyos` entry has `nvidia-drm.modeset=1 nvidia_drm.fbdev=1`
- ❌ `linux-cachyos-lts` entry is **missing** those params
- All snapper snapshot entries inherit the same pattern (main: has modeset, LTS: doesn't)
- Snapshot 6 lacks modeset on main too (this is the pre-`cachyos-chwd` baseline)

**Why this matters:** Both `limine-mkinitcpio-hook 1.36.0-1` and `limine-snapper-sync 1.29.0-1` are installed and auto-regenerate `/boot/limine.conf` on kernel updates and snapper events. Edits made directly to `/boot/limine.conf` will be wiped. The persistent fix lives in `/etc/default/limine`.

### 0a. Discover how the existing nvidia params got injected
```bash
sudo cat /etc/default/limine
```

Look for variables like `KERNEL_CMDLINE[default]`, `KCMD`, or `KERNEL_CMDLINE_LINE_PREPEND`. The `cachyos-chwd` tool likely set something for the main kernel but not for LTS.

Three likely shapes you might see:

| Shape | Fix |
|---|---|
| `KERNEL_CMDLINE[default]="... nvidia-drm.modeset=1 nvidia_drm.fbdev=1"` (one shared line) | Surprising — would apply to both. If so, regenerate (step 0c) and the LTS line should pick it up. |
| `KERNEL_CMDLINE[linux-cachyos]="... nvidia-drm.modeset=1 ..."` (per-kernel) | Add a matching `KERNEL_CMDLINE[linux-cachyos-lts]="... nvidia-drm.modeset=1 nvidia_drm.fbdev=1"` line |
| Nothing nvidia-related in the file | `cachyos-chwd` edited `limine.conf` directly. Set a `KERNEL_CMDLINE[default]` (or equivalent) to make it persistent for both kernels. |

### 0b. Apply the fix to `/etc/default/limine`

Open the file:
```bash
sudo nano /etc/default/limine
```

Make the edit per the matching shape above. For the third (most likely) shape — no nvidia vars present — append at the bottom:
```
KERNEL_CMDLINE[default]="nvidia-drm.modeset=1 nvidia_drm.fbdev=1"
```
(`KERNEL_CMDLINE[default]` is a convention used by `limine-mkinitcpio-hook` — if your file uses a different variable name, mirror that name instead.)

### 0c. Regenerate Limine entries
```bash
sudo limine-mkinitcpio
```

### 0d. Verify both entries now carry the params
```bash
sudo grep -E "linux-cachyos|cmdline:" /boot/limine.conf | head -40
```

Both `linux-cachyos` AND `linux-cachyos-lts` cmdlines should now contain `nvidia-drm.modeset=1 nvidia_drm.fbdev=1`.

### 0e. Quick-and-dirty alternative (NOT persistent)
If you just want a one-shot fix right now and accept that the next kernel update will undo it:
```bash
sudo sed -i '/linux-cachyos-lts$/,/cmdline:/ s|\(cmdline:.*UUID=[a-f0-9-]*\)|\1 nvidia-drm.modeset=1 nvidia_drm.fbdev=1|' /boot/limine.conf
sudo grep -A1 "linux-cachyos-lts$" /boot/limine.conf | head -10
```
(Verify the result before rebooting. To roll back, restore `/boot/limine.conf` from a snapshot.)

**Snapshot entries:** the older snapper snapshot entries (6–12) will be regenerated whenever snapper creates a new snapshot, and will pick up the fix from `/etc/default/limine`. You don't need to fix them by hand — they're frozen historical state.

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

## 5. HiDPI scaling on the laptop screen (only if text is too small)

Plan recommends scale `1.6` on `eDP-1`. Test live before committing:

```bash
hyprctl keyword monitor "eDP-1, 2560x1600@240, 0x0, 1.6"
hyprctl keyword monitor "DP-1, 1920x1080@120, 1600x0, 1"
hyprctl keyword monitor "DP-2, 2560x1600@120, 3520x0, 1"
```

If the layout looks right, persist it:
```bash
cat > ~/.config/hypr/monitors.conf <<'EOF'
# Laptop built-in (leftmost) — 16" HiDPI, 240Hz, scaled
monitor = eDP-1, 2560x1600@240, 0x0, 1.6

# Samsung 24" (center) — PRIMARY, 120Hz
monitor = DP-1, 1920x1080@120, 1600x0, 1

# External HDMI 2560x1600 (right) @ 120Hz
monitor = DP-2, 2560x1600@120, 3520x0, 1

# Workspaces — Samsung primary
workspace = 1, monitor:DP-1, default:true
workspace = 2, monitor:DP-1
workspace = 3, monitor:DP-1
workspace = 4, monitor:eDP-1, default:true
workspace = 5, monitor:eDP-1
workspace = 6, monitor:DP-2, default:true
workspace = 7, monitor:DP-2
workspace = 8, monitor:DP-2
workspace = 9, monitor:DP-2
EOF
hyprctl reload
```

To revert: restore the original `monitors.conf` (which had scale `1` everywhere) and `hyprctl reload`.

---

## 6. Thunderbolt boot-hang fix (section 10 of plan)

**Only do this if you actually want to dock-during-boot.** The "boot then plug" workaround works fine if you can live with it. This is invasive (touches initramfs + bootloader).

```bash
# 6a — Remove plymouth from mkinitcpio HOOKS
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
sudo sed -i 's/\bplymouth\b//' /etc/mkinitcpio.conf
grep '^HOOKS' /etc/mkinitcpio.conf   # confirm 'plymouth' is gone

# 6b — Edit Limine cmdline manually (it's root-readable only; use nano)
sudo cp /boot/limine.conf /boot/limine.conf.bak
sudo nano /boot/limine.conf
# For EACH cmdline: line:
#   - remove 'quiet splash'
#   - append 'pcie_aspm=off thunderbolt.host_reset=0 ignore_loglevel'
# Save and exit.

# 6c — Rebuild
sudo mkinitcpio -P
sudo limine-mkinitcpio

# 6d — Reboot WITH the TB dock connected to test
# If it hangs again, photograph the last visible kernel lines for diagnosis.
# Recovery: boot another entry, restore the .bak files, re-run mkinitcpio + limine-mkinitcpio.
```

---

## 7. Optional config polish (section 14 TODOs)

### 7a. Kitty with Catppuccin Mocha
```bash
mkdir -p ~/.config/kitty/themes
curl -fsSL -o ~/.config/kitty/themes/Catppuccin-Mocha.conf \
  https://raw.githubusercontent.com/catppuccin/kitty/main/themes/mocha.conf

cat > ~/.config/kitty/kitty.conf <<'EOF'
font_family      JetBrainsMono Nerd Font
font_size        12.0
window_padding_width 8
background_opacity 0.95
confirm_os_window_close 0
include themes/Catppuccin-Mocha.conf
EOF
```

### 7b. Yazi — generate default config then edit
```bash
mkdir -p ~/.config/yazi
yazi --clear-cache 2>/dev/null
# Yazi reads ~/.config/yazi/yazi.toml, keymap.toml, theme.toml
# Get the defaults to start from:
cp /usr/share/yazi/yazi.toml ~/.config/yazi/ 2>/dev/null || \
  curl -fsSL -o ~/.config/yazi/yazi.toml \
    https://raw.githubusercontent.com/sxyazi/yazi/main/yazi-config/preset/yazi.toml
```

### 7c. Hyprlock styling
```bash
cat > ~/.config/hypr/hyprlock.conf <<'EOF'
background {
    monitor =
    path = ~/Pictures/Wallpapers/wall.jpg
    blur_passes = 3
    blur_size = 8
}

input-field {
    monitor =
    size = 280, 50
    position = 0, -100
    halign = center
    valign = center
    outline_thickness = 2
    inner_color = rgba(30, 30, 46, 0.85)
    outer_color = rgba(203, 166, 247, 0.85)
    font_color = rgba(205, 214, 244, 1.0)
    placeholder_text = <i>Password...</i>
    fade_on_empty = true
}

label {
    monitor =
    text = cmd[update:1000] echo "$(date +'%H:%M')"
    color = rgba(205, 214, 244, 1.0)
    font_size = 90
    font_family = JetBrains Mono Nerd Font
    position = 0, 200
    halign = center
    valign = center
}
EOF

# Test the lock screen (lock now; type password to unlock)
hyprlock
```

### 7d. Bluetooth indicator (if you use BT)
```bash
sudo pacman -S --needed blueman
# blueman-applet will run on autostart via XDG; or add:
# exec-once = blueman-applet
# to ~/.config/hypr/autostart.conf
```

### 7e. Walker — generate default config + enable clipboard plugin
```bash
mkdir -p ~/.config/walker
walker --gen-config 2>/dev/null || true
# Edit ~/.config/walker/config.toml to enable plugins: calc, emojis, clipboard
```

---

## 8. Ghostty vs Kitty (optional swap)

Plan settled on Kitty. If you want the originally preferred Ghostty:

```bash
sudo pacman -S --needed ghostty
# Then update ~/.config/hypr/keybindings.conf:
sed -i 's|^\$term = kitty$|$term = ghostty|' ~/.config/hypr/keybindings.conf
sed -i 's|^\$filemanager = kitty -e yazi$|$filemanager = ghostty -e yazi|' ~/.config/hypr/keybindings.conf
hyprctl reload
```

Both can stay installed in parallel — switching back is the reverse `sed`.

---

## 9. Disk cleanup — leftover Windows + Ubuntu partitions

**Destructive: doublecheck before running.** This wipes `nvme1n1p3` (Windows NTFS) and `nvme1n1p4` (old Ubuntu ext4) and the tiny MSR partition.

Confirm the layout first:
```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT /dev/nvme1n1
```

Expected output should show the same `p1` (260M vfat), `p2` (16M MSR), `p3` (559.8G ntfs), `p4` (393.8G ext4) you saw in the scan. Make sure none are mounted.

Then, after triple-checking:
```bash
# Wipe partition table on the entire second NVMe (drops ALL partitions on nvme1n1)
sudo wipefs -a /dev/nvme1n1
sudo sgdisk --zap-all /dev/nvme1n1

# Optionally create a single new partition spanning the disk and format as btrfs/ext4:
sudo sgdisk -n 0:0:0 -t 0:8300 /dev/nvme1n1
sudo mkfs.btrfs -L data /dev/nvme1n1p1
# Mount manually or add to /etc/fstab afterward.
```

If you only want to remove one partition (e.g., keep Windows EFI for now), use `cfdisk /dev/nvme1n1` interactively instead.

---

## 10. Final verification

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
| Destructive | 9. Disk cleanup | No (but BACKUP first) |

---

*All commands above are reversible except section 9. Take a snapper snapshot before sections 6 or 9 if you want belt-and-suspenders safety:*
```bash
sudo snapper -c root create --description "before TB fix / disk cleanup"
```
