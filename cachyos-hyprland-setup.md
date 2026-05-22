# CachyOS + Hyprland Setup Guide

**System:** Acer Predator PT516-52s
**Date:** May 2026
**OS:** CachyOS (Arch-based, rolling release)
**DE:** Hyprland 0.55.2 (Wayland) — fallback to KDE Plasma
**Bootloader:** Limine

---

## 1. Hardware

| Component | Spec |
|---|---|
| CPU | Intel Core i9-12900H (12th gen Alder Lake) |
| GPU 1 (iGPU) | Intel Iris Xe Graphics |
| GPU 2 (dGPU) | NVIDIA GeForce RTX 3080 Ti Laptop (16 GB) |
| RAM | 32 GB |
| Disks | Micron 3400 NVMe 1TB + SK hynix BC711 NVMe |
| Display (built-in) | 2560×1600 @ 240 Hz, 16" |
| External | Plugable Thunderbolt 4 dock → 2× HDMI (Samsung 1080p + 2560×1600 @ 120Hz) |

---

## 2. Installation Decisions (CachyOS Installer)

- **Filesystem:** btrfs (default), allows snapshots via snapper
- **Bootloader:** Limine (default)
- **EFI partition:** Reused existing 260 MiB FAT32 (the 4096 MiB warning is just a recommendation)
- **Replaced Ubuntu partition** (`nvme0n1p4`, ext4 393 GiB) with CachyOS
- **Kept Windows** initially, later deleted (`p1` EFI, `p2` MSR, `p3` NTFS) and reclaimed space
- **Desktop selection (installer):** Hyprland + KDE-Desktop (KDE as fallback/safety net)
- **Kernel:** linux-cachyos (performance-tuned, BORE scheduler) + linux-cachyos-lts (fallback)
- **Shell:** Fish (CachyOS default)

### Recommendation for future installs
- **2 SSDs:** install Windows on SSD 1, CachyOS on SSD 2. Disconnect SSD 2 during Windows install to prevent EFI conflicts.
- **Single SSD:** Windows first, then Linux on top.

---

## 3. CRITICAL FIX: NVIDIA + Wayland (Hyprland)

### Problem
Hyprland uses Wayland. NVIDIA + Wayland requires **kernel modesetting (KMS)** enabled, otherwise → black screen on boot.

### Solution applied

**Step 1 — Verify NVIDIA drivers installed:**
```bash
nvidia-smi  # Should show GPU info, not error
sudo cachyos-chwd -a  # Run if needed to auto-install correct drivers
```

If manual install needed:
```bash
sudo pacman -S nvidia-dkms nvidia-utils lib32-nvidia-utils \
  libva-nvidia-driver egl-wayland linux-cachyos-headers
```

**Step 2 — Add kernel parameters to Limine.**

CachyOS uses Limine, **NOT GRUB**. Edit `/boot/limine.conf` and add to the `cmdline:` line for each kernel entry:
```
nvidia-drm.modeset=1 nvidia_drm.fbdev=1
```

Note: `cachyos-chwd` auto-adds this to the `linux-cachyos` entry but NOT to `linux-cachyos-lts`. Add manually if you want both kernels to work with Hyprland.

**Step 3 — Set default kernel to `linux-cachyos` (not lts):**
In `/boot/limine.conf`, change `default_entry: 2` → `default_entry: 1`.

**Step 4 — Rebuild initramfs:**
```bash
sudo mkinitcpio -P
sudo limine-mkinitcpio  # IMPORTANT: required for Limine to update entries
```

**Step 5 — Verify after reboot:**
```bash
cat /proc/cmdline | grep -o "nvidia-drm.modeset=."
# Should print: nvidia-drm.modeset=1
uname -r
# Should print: 7.x.x-1-cachyos (NOT cachyos-lts)
```

---

## 4. Hyprland Package Stack

### Install command
```bash
sudo pacman -S --needed \
  hyprland hyprlock hypridle hyprpaper hyprpolkitagent hyprshutdown \
  waybar mako kitty walker yazi swayosd \
  grim slurp satty wl-clipboard cliphist \
  brightnessctl pavucontrol playerctl \
  qt5-wayland qt6-wayland xdg-desktop-portal-hyprland \
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji noto-fonts-cjk \
  papirus-icon-theme
```

### Stack philosophy: "polished and understated, dev-focused"

| Category | Choice | Why |
|---|---|---|
| Compositor | Hyprland | Modern Wayland tiling, large ecosystem |
| Status bar | Waybar | Standard, configurable |
| App launcher | Walker | Fastest Wayland-native launcher, plugin system |
| Terminal | Kitty | Mature, image previews (useful for TUI tools) |
| Notifications | Mako | Simple, gets out of the way |
| Wallpaper | Hyprpaper | Static, lightweight |
| Lock screen | Hyprlock | Hyprland ecosystem |
| Idle daemon | Hypridle | Pairs with Hyprlock for auto-lock |
| Auth prompts | hyprpolkitagent | Lightweight polkit agent |
| Screenshots | grim + slurp + satty | Region select + annotation |
| OSD (vol/brightness) | SwayOSD | Standard popup OSD |
| File manager | Yazi | Terminal, Rust, image previews |
| Theme | Catppuccin Mocha | Subtle, dev-favorite |
| Font | JetBrains Mono Nerd Font | Ligatures + icons |

---

## 5. Hyprland Config Files

### Directory structure
```
~/.config/hypr/
├── hyprland.conf       # Main entrypoint, sources others
├── env.conf            # NVIDIA + environment vars
├── monitors.conf       # Display setup
├── input.conf          # Keyboard/touchpad
├── look.conf           # Animations, decoration, theme
├── keybindings.conf    # All keyboard shortcuts
├── windowrules.conf    # Window-specific rules
├── autostart.conf      # Apps launched on session start
└── hyprpaper.conf      # Wallpaper config
```

### `hyprland.conf` (entrypoint)
```
source = ~/.config/hypr/env.conf
source = ~/.config/hypr/monitors.conf
source = ~/.config/hypr/input.conf
source = ~/.config/hypr/look.conf
source = ~/.config/hypr/keybindings.conf
source = ~/.config/hypr/windowrules.conf
source = ~/.config/hypr/autostart.conf
```

### `env.conf` (NVIDIA — CRITICAL)
```
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
env = GBM_BACKEND,nvidia-drm
env = NVD_BACKEND,direct
env = ELECTRON_OZONE_PLATFORM_HINT,auto
env = MOZ_ENABLE_WAYLAND,1
env = XCURSOR_SIZE,24
env = HYPRCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt6ct

cursor {
    no_hardware_cursors = true
}
```

### `monitors.conf` (3-monitor layout: laptop-left, Samsung-center [primary], HDMI-right)
```
monitor = eDP-1, 2560x1600@240, 0x0, 1
monitor = DP-1, 1920x1080@120, 2560x0, 1
monitor = DP-2, 2560x1600@120, 4480x0, 1

workspace = 1, monitor:DP-1, default:true
workspace = 2, monitor:DP-1
workspace = 3, monitor:DP-1
workspace = 4, monitor:eDP-1, default:true
workspace = 5, monitor:eDP-1
workspace = 6, monitor:DP-2, default:true
workspace = 7, monitor:DP-2
workspace = 8, monitor:DP-2
workspace = 9, monitor:DP-2
```

**HiDPI note:** If laptop text is too small, change last value of eDP-1 line from `1` to `1.6`, and shift other monitors accordingly:
- `eDP-1` scale `1.6` → effective width 1600
- `DP-1` position `1600x0`
- `DP-2` position `3520x0`

### `input.conf`
```
input {
    kb_layout = us
    follow_mouse = 1
    sensitivity = 0
    touchpad {
        natural_scroll = true
        tap-to-click = true
        disable_while_typing = true
    }
}
gesture = 3, horizontal, workspace
```

### `look.conf` (Catppuccin Mocha)
```
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgba(cba6f7ee) rgba(89b4faee) 45deg
    col.inactive_border = rgba(313244aa)
    layout = dwindle
    resize_on_border = true
}
decoration {
    rounding = 8
    active_opacity = 1.0
    inactive_opacity = 0.97
    blur {
        enabled = true
        size = 5
        passes = 2
        new_optimizations = true
    }
    shadow {
        enabled = true
        range = 12
        render_power = 2
        color = rgba(00000055)
    }
}
animations {
    enabled = true
    bezier = quick, 0.15, 0.85, 0.25, 1.0
    animation = windows, 1, 3, quick, slide
    animation = windowsOut, 1, 3, quick, slide
    animation = fade, 1, 4, quick
    animation = workspaces, 1, 4, quick, slide
    animation = border, 1, 6, quick
}
dwindle {
    preserve_split = true
}
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
```

### `keybindings.conf`
```
$mainMod = SUPER
$term = kitty
$launcher = walker
$browser = firefox
$filemanager = kitty -e yazi

# Core
bind = $mainMod, Return, exec, $term
bind = $mainMod, Space, exec, $launcher
bind = $mainMod SHIFT, Return, exec, $browser
bind = $mainMod, E, exec, $filemanager
bind = $mainMod, Q, killactive
bind = $mainMod SHIFT, Q, exit
bind = $mainMod, F, fullscreen
bind = $mainMod, V, togglefloating
bind = $mainMod, P, pseudo
bind = $mainMod, J, layoutmsg, togglesplit
bind = $mainMod, L, exec, hyprlock

# Focus windows
bind = $mainMod, left,  movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up,    movefocus, u
bind = $mainMod, down,  movefocus, d

# Move windows
bind = $mainMod SHIFT, left,  movewindow, l
bind = $mainMod SHIFT, right, movewindow, r
bind = $mainMod SHIFT, up,    movewindow, u
bind = $mainMod SHIFT, down,  movewindow, d

# Workspaces 1-9
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
# ... continue 3-9
bind = $mainMod SHIFT, 1, movetoworkspace, 1
# ... continue 3-9

# Focus monitor (F1=laptop, F2=Samsung, F3=HDMI)
bind = $mainMod, F1, focusmonitor, eDP-1
bind = $mainMod, F2, focusmonitor, DP-1
bind = $mainMod, F3, focusmonitor, DP-2
bind = $mainMod SHIFT, F1, movewindow, mon:eDP-1
bind = $mainMod SHIFT, F2, movewindow, mon:DP-1
bind = $mainMod SHIFT, F3, movewindow, mon:DP-2

# Cycle workspaces by scroll
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up,   workspace, e-1

# Mouse drag (Super + drag)
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Walker special modes
bind = $mainMod, period, exec, walker -m emojis

# Screenshots
bind = , Print, exec, grim -g "$(slurp)" - | satty --filename - --copy-command 'wl-copy'
bind = SHIFT, Print, exec, grim - | satty --filename - --copy-command 'wl-copy'

# Volume/brightness via SwayOSD
bindel = , XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise
bindel = , XF86AudioLowerVolume, exec, swayosd-client --output-volume lower
bindel = , XF86AudioMute,        exec, swayosd-client --output-volume mute-toggle
bindel = , XF86AudioMicMute,     exec, swayosd-client --input-volume mute-toggle
bindel = , XF86MonBrightnessUp,   exec, swayosd-client --brightness raise
bindel = , XF86MonBrightnessDown, exec, swayosd-client --brightness lower

# Media keys
bindl = , XF86AudioPlay, exec, playerctl play-pause
bindl = , XF86AudioNext, exec, playerctl next
bindl = , XF86AudioPrev, exec, playerctl previous
```

### `windowrules.conf` (note: `windowrule`, not `windowrulev2`)
```
windowrule = float, class:^(pavucontrol)$
windowrule = float, class:^(nm-connection-editor)$
windowrule = float, class:^(blueman-manager)$
windowrule = float, title:^(Picture-in-Picture)$
windowrule = pin,   title:^(Picture-in-Picture)$
```

### `autostart.conf`
```
exec-once = waybar
exec-once = mako
exec-once = hyprpaper
exec-once = hypridle
exec-once = hyprpolkitagent
exec-once = swayosd-server
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store
exec-once = nm-applet --indicator
```

### `hyprpaper.conf` (wallpaper on ALL monitors)
```
preload = ~/Pictures/Wallpapers/wall.jpg
wallpaper = eDP-1, ~/Pictures/Wallpapers/wall.jpg
wallpaper = DP-1, ~/Pictures/Wallpapers/wall.jpg
wallpaper = DP-2, ~/Pictures/Wallpapers/wall.jpg
splash = false
```

---

## 6. Waybar Config (Catppuccin Mocha)

### `~/.config/waybar/config.jsonc`
```jsonc
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
```

### `~/.config/waybar/style.css`
```css
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
```

---

## 7. SDDM — force X11 mode (avoids NVIDIA Wayland-greeter issues)

Create `/etc/sddm.conf.d/10-wayland.conf`:
```
[General]
DisplayServer=x11
```
SDDM itself runs X11, but the *session* (Hyprland) still runs Wayland. No conflict.

---

## 8. Keybindings Cheat Sheet

### Essential
| Combo | Action |
|---|---|
| Super + Enter | Open terminal (Kitty) |
| Super + Space | App launcher (Walker) |
| Super + Shift + Enter | Open Firefox |
| Super + Q | Close window |
| Super + Shift + Q | Exit Hyprland |
| Super + L | Lock screen |

### Navigation
| Combo | Action |
|---|---|
| Super + ←/→/↑/↓ | Move focus |
| Super + Shift + ←/→/↑/↓ | Move window |
| Super + 1..9 | Switch workspace |
| Super + Shift + 1..9 | Send window to workspace |
| Super + F1/F2/F3 | Focus monitor (laptop/Samsung/HDMI) |
| Super + Shift + F1/F2/F3 | Move window to monitor |
| Super + scroll | Cycle workspaces |

### Window
| Combo | Action |
|---|---|
| Super + F | Fullscreen |
| Super + V | Toggle floating |
| Super + J | Toggle split direction |
| Super + drag (left mouse) | Move window |
| Super + drag (right mouse) | Resize window |

### Utilities
| Combo | Action |
|---|---|
| Super + E | File manager (Yazi) |
| Super + period | Emoji picker (Walker) |
| Print Screen | Region screenshot → satty |
| Shift + Print Screen | Fullscreen → satty |

---

## 9. Useful Commands

### Verification
```bash
# Check kernel modeset enabled
cat /proc/cmdline | grep -o "nvidia-drm.modeset=."

# Check current kernel
uname -r

# Check NVIDIA driver works
nvidia-smi

# List monitors with current settings
hyprctl monitors all

# Hyprland version
hyprctl version

# Validate config syntax
Hyprland --verify-config
```

### Reload without logout
```bash
# Reload Hyprland config
hyprctl reload

# Restart waybar
pkill waybar; waybar & disown

# Restart wallpaper
pkill hyprpaper; hyprpaper & disown
```

### Find an installed package
```bash
pacman -Qs PACKAGE_NAME
pacman -Ss PACKAGE_NAME      # search repos
```

### Logs (debugging Hyprland crashes)
```bash
cat ~/.local/share/hyprland/hyprland.log | tail -50
journalctl --user -b | grep -i hyprland | tail -30
```

---

## 10. OUTSTANDING ISSUE: Thunderbolt Boot Hang

### Symptoms
- Boot with TB dock connected → black screen with loading dot, never reaches SDDM
- Boot without TB dock → works fine
- Connect TB dock after boot → works fine
- TTY (Ctrl+Alt+F2/F3/F4) does NOT respond during the hang

### Root cause (suspected)
TB devices need 2-5s longer than internal devices to fully enumerate. The kernel + NVIDIA driver + Plymouth try to talk to them before the dock's video controllers are responsive.

### BIOS limitations
Predator PT516-52s BIOS V1.04 is locked down. No exposed options for:
- Thunderbolt Boot Support
- Thunderbolt Security Level
- Discrete Graphics Mode
- Primary Display

Only Intel VTX/VTD are exposed in Advanced. Security only has Secure Boot/TPM/passwords.

### Fixes to try (Linux side)

**Step 1 — Remove Plymouth from initramfs:**
```bash
sudo nano /etc/mkinitcpio.conf
# Remove "plymouth" from HOOKS=(...)
```

**Step 2 — Edit `/boot/limine.conf`:**
For each `cmdline:` line, remove `quiet splash` and add:
```
pcie_aspm=off thunderbolt.host_reset=0 ignore_loglevel
```

**Step 3 — Rebuild:**
```bash
sudo mkinitcpio -P
sudo limine-mkinitcpio
```

**Step 4 — Reboot with dock connected.**
- If boots fine: one of those kernel params fixed it
- If still hangs but now shows text: photograph the screen, the last lines reveal the failing driver

### Current workaround
Boot without dock connected, plug in after login. Works fine.

---

## 11. Limine Bootloader Reference

CachyOS uses Limine (not GRUB or systemd-boot). Key files:
- `/boot/limine.conf` — main config (kernel entries, cmdline, theme)
- `/etc/default/limine` — global defaults (if exists)

### Auto-generated entries
Entries marked `### This kernel entry is auto-generated by limine-entry-tool` are managed by Limine's tooling. Manual edits to `cmdline:` MAY be overwritten by future kernel updates. For persistent kernel parameters, the proper way is through CachyOS's hardware detection tool (`cachyos-chwd`) or `/etc/default/limine`.

### Useful Limine commands
```bash
sudo limine-mkinitcpio       # Regenerate entries after kernel/initramfs changes
sudo limine-update           # Update Limine binaries (rare, on package upgrade)
```

---

## 12. Useful Wallpapers

Catppuccin official wallpaper repos:
- https://github.com/zhichaoh/catppuccin-wallpapers
- https://github.com/Gingeh/wallpapers (Catppuccin community)

Quick download:
```bash
mkdir -p ~/Pictures/Wallpapers
curl -L -o ~/Pictures/Wallpapers/wall.jpg \
  https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/main/landscapes/evening-sky.png
```

---

## 13. Quick "Fresh install" Checklist (replicate this setup)

1. Install CachyOS, pick Hyprland + KDE-Desktop, btrfs, Limine
2. After first boot into KDE (fallback), open terminal
3. Run `sudo cachyos-chwd -a` to ensure NVIDIA drivers correct
4. Verify `cat /proc/cmdline | grep modeset` shows `nvidia-drm.modeset=1`. If not, add to `/boot/limine.conf`, run `sudo mkinitcpio -P && sudo limine-mkinitcpio`, reboot.
5. Install Hyprland stack: `sudo pacman -S` (see section 4 list)
6. Create config dirs: `mkdir -p ~/.config/{hypr,waybar,mako} ~/Pictures/Wallpapers`
7. Drop the config files from sections 5-6 in place
8. Force SDDM to X11 (section 7)
9. Log out → SDDM → pick Hyprland → log in
10. If multi-monitor: run `hyprctl monitors all`, adjust `monitors.conf` accordingly
11. Verify Hyprland with `hyprctl version` and test keybindings

---

## 14. Things to Investigate Later

- [ ] Resolve Thunderbolt boot hang (section 10 procedure)
- [ ] HiDPI scaling on laptop screen (currently scale 1.0, text very small)
- [ ] Configure Yazi properly (~/.config/yazi/yazi.toml)
- [ ] Configure Walker plugins (calc, emoji, clipboard via cliphist)
- [ ] Add Kitty config with Catppuccin theme
- [ ] Set up hyprlock styling
- [ ] Configure hypridle timeouts (suspend/lock after N min)
- [ ] Consider replacing nm-applet with networkmanager_dmenu or rofi-network
- [ ] Set up Bluetooth indicator (blueberry or blueman)
- [ ] Battery/power profile management (auto-cpufreq, tlp, or power-profiles-daemon)
- [ ] Test gaming performance (Steam, Proton) — should be great with NVIDIA + Wayland in 2026
- [ ] Snapshot strategy with snapper (btrfs)

---

## 15. References

- Hyprland docs: https://wiki.hyprland.org/
- CachyOS docs: https://wiki.cachyos.org/
- Walker: https://github.com/abenz1267/walker
- Catppuccin themes (everything): https://github.com/catppuccin
- Omarchy (alternative opinionated Hyprland distro by DHH): https://omarchy.org/
- NVIDIA on Hyprland wiki page: https://wiki.hyprland.org/Nvidia/

---

*Generated during initial setup, May 2026. Update as the system evolves.*
