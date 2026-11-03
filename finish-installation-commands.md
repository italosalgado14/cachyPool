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

## 6. Thunderbolt boot-AND-shutdown hang fix (supersedes section 10 of plan)

**Status:** the symptom set has expanded since the original plan was written. We now have **two** failure modes that look related but have distinct root causes and need separate remediations:

- **Boot hang** — TB4 dock connected at power-on → black screen + dead TTYs, never reaches greeter. Original symptom.
- **Shutdown / power-off hang** — TB4 dock connected at shutdown → system never powers off, sits on a stop job forever (or hangs after the DM exits). New symptom.

### 6.0 Applied state on `triton500se` — 2026-05-22 ✅

Section 6 was executed via `/tmp/tb-section6-fix.sh` (sudo) on 2026-05-22 and verified working: TB4 dock (Plugable TBT4-UD5, USB4 40 Gb/s, IOMMU policy) now boots **and** powers off cleanly while attached. Detailed playbook lives in 6.1–6.6 below; this subsection records what actually shipped so future-you doesn't have to re-derive it from system state.

**Boot side**

| Step | Action | Evidence on disk |
|---|---|---|
| 6.2.a | No `thunderbolt` / `nhi` entries found in initrd or `mkinitcpio.conf.d/` → skipped (early-load case did not apply on this machine). `/etc/mkinitcpio.conf.d/` contains only `10-chwd.conf` (loads `nvidia*` only) and `10-limine-snapper-sync.conf`. | `lsinitcpio /boot/initramfs-linux-cachyos.img \| grep -iE 'thunderbolt\|nhi'` → empty |
| 6.2.b | `/etc/default/limine.bak` created; appended `KERNEL_CMDLINE[default]+=" thunderbolt.host_reset=0"` (with a comment tagging the change to Section 6). Also dropped `quiet` and `splash` from the existing cmdline for boot-time visibility. `pcie_aspm=off` deliberately omitted (no ASPM evidence in `dmesg`). | `cat /proc/cmdline` shows `thunderbolt.host_reset=0`; `cat /sys/module/thunderbolt/parameters/host_reset` → `N` |
| 6.2.c | `/etc/mkinitcpio.conf.bak` created; `plymouth` removed from `HOOKS=`. | `grep '^HOOKS' /etc/mkinitcpio.conf` no longer lists `plymouth` |
| 6.2.d | `sudo mkinitcpio -P` + `sudo limine-mkinitcpio` rebuilt initrds and `/boot/limine.conf`. Reboot with dock attached reached greeter normally. | — |

**Shutdown side**

| Step | Action | Evidence on disk |
|---|---|---|
| 6.3.a | `nvidia-suspend.service`, `nvidia-resume.service`, `nvidia-hibernate.service` all enabled. | `systemctl is-enabled nvidia-{suspend,resume,hibernate}.service` → `enabled` ×3 |
| 6.3.b | Created `/etc/modprobe.d/nvidia-power-management.conf` with `options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp` (spill path on real disk, not tmpfs). Initramfs rebuilt to pick it up at boot. | File present with Section 6.3.b header comment |
| 6.3.c | Masked all four Plymouth shutdown units (`plymouth-quit`, `plymouth-quit-wait`, `plymouth-poweroff`, `plymouth-reboot`). | `systemctl status plymouth-quit.service` → `Loaded: masked` (same for the other three) |
| 6.3.d | `reboot=efi` **not** added — shutdown succeeded without it. Keep in reserve only if a future regression brings the ACPI-poweroff hang back. | cmdline unchanged beyond 6.2.b |
| 6.3.e | `DefaultTimeoutStopSec=15s` set in `[Manager]` block of `/etc/systemd/system.conf` (line 50). Diagnostic-only; safe to revert to default (90s) now that the hang is gone. | `grep DefaultTimeoutStopSec /etc/systemd/system.conf` → uncommented 15s |
| 6.3.f | No specific unit needed masking — shutdown completed within the lowered timeout, so the `systemd-rfkill` / `nvidia-persistenced` paths were never the blockers on this machine. | — |

**Backups in place for rollback** (per 6.5):
- `/etc/default/limine.bak`
- `/etc/mkinitcpio.conf.bak`

**Follow-ups still open**
- LTS kernel cmdline does not yet carry `thunderbolt.host_reset=0` — booting `linux-cachyos-lts` with the dock attached will likely regress until the same `KERNEL_CMDLINE[lts]+=` line is added (see section 0 for the lts-key convention).
- Plymouth `HOOKS=` removal is permanent for now. Reintroduce only after a week of stable boots with the dock, per 6.4's note.
- `DefaultTimeoutStopSec=15s` was a diagnostic lever; consider restoring 90s once you're confident the shutdown path is stable.

---


The original section 10 plan (remove Plymouth + `pcie_aspm=off thunderbolt.host_reset=0 ignore_loglevel`) was a reasonable first draft, but research into Arch BBS, kernel source, NVIDIA developer forums, and the omarchy/CachyOS-side ecosystem changed the picture. Corrections:

| Old plan said | Verdict after research |
|---|---|
| `thunderbolt.host_reset=0` | ✅ **Correct** — confirmed by Arch BBS 295824 [SOLVED] (Dell TB16, kernel 6.8.8 regression). The kernel `bool` accepts `=0` and `=false`. Polarity is right. |
| `pcie_aspm=off` | ⚠ **Probably outdated.** Not cited in any 2024-2026 [SOLVED] thread for TB4 + Alder Lake. Hurts battery on RTX 30-series. Drop unless `dmesg` actually shows ASPM errors. |
| Remove Plymouth from `HOOKS=` | ✅ **Keep, but reframe as diagnostic.** Plymouth doesn't *cause* the hang; it hides the kernel messages that would reveal it. Removing it lets you see the real error. |
| Strip `quiet splash` | ✅ Same logic — keep for visibility. |
| Edit `/boot/limine.conf` with `nano` | ❌ **Wrong file.** Section 0 of this same doc explains: `limine-mkinitcpio-hook` regenerates `/boot/limine.conf` on every kernel update and wipes manual edits. Persistent cmdline lives in `/etc/default/limine`. |
| (missing) Check initrd for early-loaded `thunderbolt` module | ➕ **Most likely the actual curative step.** Arch BBS 305292 [SOLVED] (X1 Carbon Gen11 + TB3) + omarchy #3906: early-loading `thunderbolt` in initrd tears down DP tunnels before the NVIDIA driver claims them. |
| (missing) Anything about shutdown | ➕ Whole new section below. |

> **Still optional.** If "boot without dock, plug in after login" is acceptable, you can skip 6.2 entirely and just do 6.3 to handle the shutdown side. The boot-side change is invasive; the shutdown-side change is mostly userland.

---

### 6.1 Diagnose FIRST — gather evidence before changing anything

Touching initramfs and bootloader without first knowing *which* subsystem is hanging is how single-fix sessions turn into multi-day yak-shaves. Run these in a Kitty terminal, save the output, then decide which subsections below to apply.

```bash
# What hung on the previous failed boot / shutdown?
journalctl --list-boots                                 # confirm boot indexing
journalctl -b -1 -p err --no-pager                      # errors from previous boot
journalctl -b -1 -k --no-pager | tail -200              # kernel ring buffer just before the hang
journalctl -b -1 _PID=1 --no-pager | tail -100          # PID 1 (systemd) last words before shutdown hang

# Where is boot spending time?
systemd-analyze blame | head -30
systemd-analyze critical-chain

# Thunderbolt state
boltctl list                                            # devices known & authorized?
boltctl domains                                         # IOMMU DMA protection mode
dmesg | grep -iE 'thunderbolt|tb[0-9]|usb4|nhi'
modinfo thunderbolt | grep -i host_reset                # confirms param exists
cat /sys/module/thunderbolt/parameters/host_reset       # confirms current runtime value (Y=on)

# NVIDIA / DRM state
dmesg | grep -iE 'nvidia|drm|nouveau'
pacman -Qi linux-cachyos-nvidia-open | grep Version
nvidia-smi | head -5                                    # driver version
systemctl is-enabled nvidia-suspend nvidia-resume nvidia-hibernate

# Initrd contents — is thunderbolt being early-loaded?
lsinitcpio /boot/initramfs-linux-cachyos.img | grep -iE 'thunderbolt|nhi'
grep -r thunderbolt /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/ 2>/dev/null
ls /etc/mkinitcpio.conf.d/

# Shutdown side
systemctl list-units --state=failed
grep -i timeout /etc/systemd/system.conf
```

The two highest-signal outputs:
- `journalctl -b -1 -k --no-pager | tail -200` — the last kernel words before the freeze. Photograph this output and keep it; it tells you whether the hang is in `thunderbolt`, `nvidia`, `xhci`, `pcieport`, or somewhere else entirely.
- The initrd contents check — if `thunderbolt` appears in the initrd listing, that's almost certainly the boot-side culprit and step 6.2.a alone will likely fix it.

> **NVIDIA driver patch level — already satisfied.** Per `ACTUAL-CONFIGURATION.md` §3, the installed driver is **595.71.05**, which is past **595.58.03** — the version that fixed the `nvidia_modeset` NULL-deref on 2-monitor TB-dock disconnect (NVIDIA bug 5871511, forum thread 359280). So you don't need to chase that specific bug. If `nvidia-smi` shows something older, upgrade before doing anything else here.

---

### 6.2 Boot-side fix (apply if 6.1 confirms a TB-related boot hang)

#### 6.2.a Remove `thunderbolt` from any initrd early-load snippet

This is the most-likely curative step. CachyOS's `chwd` or a derivative snippet may have dropped a config file into `/etc/mkinitcpio.conf.d/` that pulls `thunderbolt` (or `nhi`) into initrd, where it tears down DP tunnels before NVIDIA is ready.

```bash
# Inspect — anything mentioning thunderbolt?
ls -la /etc/mkinitcpio.conf.d/
grep -r 'thunderbolt\|nhi' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/ 2>/dev/null

# If you find e.g. /etc/mkinitcpio.conf.d/thunderbolt_module.conf, back it up and remove it:
sudo cp /etc/mkinitcpio.conf.d/thunderbolt_module.conf /tmp/thunderbolt_module.conf.bak  # if exists
sudo rm /etc/mkinitcpio.conf.d/thunderbolt_module.conf                                   # if exists

# Also check the main MODULES= line in /etc/mkinitcpio.conf — should NOT contain thunderbolt
grep '^MODULES' /etc/mkinitcpio.conf
```

If nothing references `thunderbolt`/`nhi` in initrd, skip the rm and move on — the early-load case doesn't apply.

#### 6.2.b Set kernel cmdline params via `/etc/default/limine` (persistent)

```bash
sudo cp /etc/default/limine /etc/default/limine.bak
sudo nano /etc/default/limine
```

Following the same convention used in section 0 (whichever `KERNEL_CMDLINE[...]` variable shape this file already uses), append to the params:

```
thunderbolt.host_reset=0 ignore_loglevel
```

Notes on what to **omit** vs the original plan:
- **Skip `pcie_aspm=off`** unless §6.1's `dmesg` showed ASPM errors. (See the table above.)
- **Skip `quiet splash` removal here** if you want; it's controlled separately below.

If §6.1's evidence specifically pointed at PCIe ASPM messages, you can add `pcie_aspm=off` back — but treat it as a hypothesis to validate, not a default.

#### 6.2.c Remove Plymouth from initramfs HOOKS (diagnostic visibility)

```bash
sudo cp /etc/mkinitcpio.conf /etc/mkinitcpio.conf.bak
sudo sed -i 's/\bplymouth\b//' /etc/mkinitcpio.conf
grep '^HOOKS' /etc/mkinitcpio.conf   # confirm 'plymouth' is gone
```

Also strip `quiet splash` from the cmdline in `/etc/default/limine` so kernel messages are visible during the next boot attempt. If a future boot hangs again with these in place, you'll see the failing driver in plaintext instead of a hidden loading dot.

#### 6.2.d Rebuild and test

```bash
sudo mkinitcpio -P              # rebuild all kernel initrds
sudo limine-mkinitcpio          # regenerate /boot/limine.conf from /etc/default/limine

# Sanity-check the result:
sudo grep -A1 'linux-cachyos' /boot/limine.conf | grep -i thunderbolt
# should show thunderbolt.host_reset=0 on the linux-cachyos cmdline (and ideally linux-cachyos-lts; if not, see section 0)

# Reboot WITH the TB dock connected. If it still hangs:
# 1. Photograph the last visible kernel lines (now visible since Plymouth is gone + no `quiet`).
# 2. From the next boot WITHOUT the dock, read journalctl -b -1 -k | tail -200.
# 3. Adjust based on which driver is in the failing line.
```

---

### 6.3 Shutdown-side fix (apply if the dock-connected power-off hangs)

The shutdown hang almost certainly has a different root cause than the boot hang, even though both are triggered by "dock attached". Don't expect the boot fix to fix shutdown automatically.

#### 6.3.a Enable the NVIDIA sleep/shutdown handoff services

Without these enabled, the kernel can yank the GPU before NVIDIA's clean-teardown path runs, which deadlocks the shutdown when external displays are still being driven over Thunderbolt.

```bash
# Check current state
systemctl is-enabled nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service

# Enable any that are 'disabled'
sudo systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
```

#### 6.3.b Set VRAM-preserve options for the NVIDIA module

Create `/etc/modprobe.d/nvidia-power-management.conf`:

```bash
sudo tee /etc/modprobe.d/nvidia-power-management.conf >/dev/null <<'EOF'
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF

# Module options change → rebuild initramfs so nvidia-open picks them up at boot:
sudo mkinitcpio -P
```

`/var/tmp` (not `/tmp`) is intentional — `/tmp` is `tmpfs` and gets unmounted too early in the shutdown sequence to be safe.

#### 6.3.c Mask Plymouth's shutdown units

Removing Plymouth from `HOOKS=` (step 6.2.c) removes its *boot* interception but doesn't touch its *shutdown* units, which can stall when the DRM master handoff doesn't complete cleanly with a TB-attached GPU.

```bash
sudo systemctl mask plymouth-quit.service plymouth-quit-wait.service \
                    plymouth-poweroff.service plymouth-reboot.service
```

You can `unmask` later if you ever want to reintroduce Plymouth.

> ⚠ **2026-11-02 — this step had an unmeasured cost for 5½ months.** Masking the *quit* units without
> touching `plymouth-start.service` left `plymouthd` with nothing to tell it to exit: this boot path has no
> display manager, so nothing ever calls `plymouth quit`. The daemon therefore ran for the whole session,
> busy-looping at **2.88 % of a core** (systemd's own accounting on stop: `Consumed 1min 616ms CPU time over
> 35min 3.668s wall clock time`) while drawing nothing at all — there is no splash on this machine, since
> `plymouth` is out of `HOOKS=` and `quiet splash` is off the cmdline. Fixed by also masking the start unit:
> `sudo systemctl mask --now plymouth-start.service`. See the `plymouthd` row in `ACTUAL-CONFIGURATION.md`
> §15 for the measurement, why `mask` and not `disable`, and the `plymouth.enable=0` alternative.
> **Lesson:** masking a service's *stop* half orphans whatever its *start* half launched.

#### 6.3.d Try `reboot=efi` (Acer-specific ACPI poweroff history)

Acer laptops have a documented history of hanging on ACPI poweroff — see the 2017 kernel patch by Daniel Drake (Endless): *"Multiple Acer laptops hang on ACPI poweroff... A workaround has been found to force these systems to use EFI for poweroff."* The Predator firmware lineage inherits this.

Add to `/etc/default/limine` cmdline, in this order of preference (try one at a time, rebuild + reboot between each):

```
reboot=efi
# if that doesn't help:
reboot=pci
# last resort:
reboot=acpi
```

Then `sudo limine-mkinitcpio` and test the shutdown with the dock attached.

#### 6.3.e Lower the systemd stop timeout while diagnosing

Default `DefaultTimeoutStopSec=90s` is why a stuck unit feels like "indefinite hang". Lower it so a stuck stop becomes a 15-second pause-then-force, and so the prior boot's `journalctl -b -1 _PID=1` shows which unit was the blocker.

```bash
sudo nano /etc/systemd/system.conf
# Uncomment and set:
#   DefaultTimeoutStopSec=15s
sudo systemctl daemon-reexec
```

Revert to default (or 30s) once you've identified the offending unit.

#### 6.3.f If a specific unit shows up as the blocker

Common shutdown blockers in this family of bugs:
- `systemd-rfkill.service` — known to stall on hybrid laptops; safe to `systemctl mask` if it shows in `journalctl -b -1 _PID=1`.
- `nvidia-persistenced.service` — NVIDIA dev forum 239943 documents shutdown timeouts; mask if it's the blocker.
- Any user-session unit holding a DRM handle — check `loginctl list-sessions`.

Only mask after `journalctl -b -1` confirms the unit is what stalled the shutdown.

---

### 6.4 Verify both paths

```bash
# Boot side:
cat /proc/cmdline | grep thunderbolt    # should show thunderbolt.host_reset=0
cat /sys/module/thunderbolt/parameters/host_reset   # should print N
lsinitcpio /boot/initramfs-linux-cachyos.img | grep -iE 'thunderbolt|nhi'   # ideally empty

# Shutdown side:
systemctl is-enabled nvidia-{suspend,resume,hibernate}.service   # all 'enabled'
cat /etc/modprobe.d/nvidia-power-management.conf
systemctl is-masked plymouth-quit.service                        # 'masked'

# Real test (do these in order, separate reboots):
#   1. Reboot WITH dock connected — should reach greeter.
#   2. After login with dock, `systemctl poweroff` — should power off cleanly.
#   3. Re-enable Plymouth in HOOKS later, only after both paths are stable for a week.
```

### 6.5 Recovery if something breaks

All destructive steps above were preceded by `.bak` copies. To roll back:

```bash
sudo cp /etc/default/limine.bak     /etc/default/limine
sudo cp /etc/mkinitcpio.conf.bak    /etc/mkinitcpio.conf
sudo rm  /etc/modprobe.d/nvidia-power-management.conf       # if it caused issues
sudo systemctl unmask plymouth-quit.service plymouth-quit-wait.service \
                      plymouth-poweroff.service plymouth-reboot.service
sudo mkinitcpio -P
sudo limine-mkinitcpio
```

Or, if the machine won't boot at all: at the Limine menu, pick a working **snapper snapshot entry** (sections 11+ have details) and roll back the btrfs subvolume.

### 6.6 References (so future-you can re-verify)

**Boot-side**
- Arch BBS 295824 [SOLVED] — Dell TB16, kernel 6.8.8 regression, `thunderbolt.host_reset=false` confirmed fix: https://bbs.archlinux.org/viewtopic.php?id=295824
- Arch BBS 305292 [SOLVED] — X1 Carbon Gen11 + TB3 dock, fixed by removing `thunderbolt` from `MODULES=`: https://bbs.archlinux.org/viewtopic.php?id=305292
- omarchy #3906 — early TB-module load breaks multi-monitor on dGPU systems (matches our exact symptom): https://github.com/basecamp/omarchy/issues/3906
- Kernel source — `host_reset` parameter definition: https://github.com/torvalds/linux/blob/master/drivers/thunderbolt/nhi.c
- CachyOS — Limine boot manager docs: https://wiki.cachyos.org/configuration/boot_manager_configuration/

**Shutdown-side**
- NVIDIA dev forum 359280 — `nvidia_modeset` NULL-deref on TB dock disconnect, fixed 595.58.03 (we're past this on 595.71.05): https://forums.developer.nvidia.com/t/kernel-null-pointer-dereference-in-nvidia-modeset-during-thunderbolt-dock-disconnect/359280
- NVIDIA dev forum 233643 — `PreserveVideoMemoryAllocations` + systemd services hibernate/shutdown interaction: https://forums.developer.nvidia.com/t/preservevideomemoryallocations-systemd-services-causes-resume-from-hibernate-to-fail/233643
- NVIDIA dev forum 239943 — `nvidia-persistenced` shutdown timeout pattern: https://forums.developer.nvidia.com/t/nvidia-persistenced-timeout-when-computer-shutdown/239943
- Arch wiki NVIDIA — power management & module options: https://wiki.archlinux.org/title/NVIDIA
- EndeavourOS forum 42303 — concrete `NVreg_*` + suspend/resume service recipe: https://forum.endeavouros.com/t/how-to-fix-the-sleep-suspend-issue-glitch-with-crashing-nvidia-propietary-drivers-and-x11-wayland-on-kde-plasma-arch-endeavouros/42303
- Kernel patch — Acer laptops hang on ACPI poweroff, `reboot=efi` workaround (Daniel Drake, 2017): https://patchwork.kernel.org/project/linux-acpi/patch/20170303201524.8150-1-drake@endlessm.com/
- Arch BBS 269549 — process hangs at shutdown patterns: https://bbs.archlinux.org/viewtopic.php?id=269549

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

### 7e. Walker — proper Elephant-backed install + config

**Why this is its own subsection now.** Walker 2.x is a thin GTK4 frontend over a separate backend daemon called **Elephant**. Each capability (apps, calculator, clipboard, symbols, files, runner, websearch, etc.) is delivered by a discrete `elephant-<provider>` package. The previous one-liner (`walker --gen-config`) doesn't reflect any of this — without Elephant running and the right providers installed, the keybindings in `keybindings.conf` (`Super+Ctrl+E` → symbols, `Super+Ctrl+V` → clipboard, etc.) silently no-op or fall back to the desktopapplications default. `ACTUAL-CONFIGURATION.md` §12 currently claims "using upstream defaults"; in practice that means most of Walker's advertised capabilities aren't actually wired up.

#### 7e.i Install Elephant + the providers we want

CachyOS ships `walker 2.16.2-1` (`pacman -Qi walker` to confirm), but **every `elephant*` package is AUR-only as of 2026-05-23** — verified on this machine: `pacman -Ss '^elephant'` returns only the unrelated `elephantdsp-roomreverb-*` audio plugins in `extra/`. Use `paru` (the AUR helper already installed on this machine; `yay` is not present here):

```bash
# Confirm walker is the current version (≥ 2.16 → Elephant backend)
pacman -Qi walker | grep -E '^(Name|Version)'

# Install Elephant hub + the 9 providers we want from AUR
paru -S --needed \
  elephant \
  elephant-desktopapplications \
  elephant-calc \
  elephant-runner \
  elephant-files \
  elephant-symbols \
  elephant-clipboard \
  elephant-websearch \
  elephant-providerlist \
  elephant-menus

# Calculator dependency (libqalculate ships qalc)
sudo pacman -S --needed libqalculate

# qalc's first run wants a config dir or it spams warnings into Walker
mkdir -p ~/.config/qalculate
touch  ~/.config/qalculate/qalc.cfg
```

> **`-bin` vs source.** Every provider also has an AUR `-bin` flavor (e.g. `elephant-bin`, `elephant-calc-bin`). The names above compile from source (Go, ~1 min total on this machine). If you want prebuilt, swap **every** name to its `-bin` form — don't mix source and `-bin` in the same batch.
>
> **Version-match warning** (per Omarchy guide #2835): *"Elephant and the providers need to be installed from the same source. A version mismatch leads to the error you are seeing."* Currently all packages above land at `2.21.0-1`, so a single `paru -S` batch keeps them aligned. Don't install some now and others later from a different source / flavor.

#### 7e.ii Create + enable the Elephant systemd user unit

The AUR `elephant` package ships **no** systemd unit (verified: `pacman -Ql elephant | grep systemd` is empty — its files are just `/usr/bin/elephant`, `/usr/share/licenses/…`, and `/usr/lib/elephant/*.so` provider modules). So `systemctl --user enable --now elephant.service` will fail with `Unit elephant.service does not exist`. Write the unit yourself:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/elephant.service <<'EOF'
[Unit]
Description=Elephant provider hub for Walker
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/elephant
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now elephant.service

# Verify
systemctl --user status elephant.service --no-pager | head -10
elephant listproviders     # NB: subcommand is 'listproviders' (alias 'l'), NOT 'providers list'
```

`elephant listproviders` will show **8** of the 9 providers you installed — `menus` is missing from that output even when it loaded fine. Confirm with the journal:

```bash
journalctl --user -u elephant.service -b --no-pager | grep 'providers loaded'
# Expected: one 'INFO providers loaded=<name>' line per installed provider, including menus
```

The omission is by design: `menus` is a trigger-mode subsystem invoked via the top-level `elephant menu …` subcommand, not a query provider listed alongside `calc`/`runner`/etc.

> **Alternative**: `elephant service install` (and the `elephant service` subcommand family) can manage the systemd user unit for you. We use the explicit `cat > … .service` path above because it's transparent, version-stable, and matches the existing pattern used for `hyprpolkitagent.service` in §7c — but `elephant service` exists if you prefer it.

> ⚠ **`enable` alone is NOT enough on this machine (discovered 2026-05-26).** `WantedBy=graphical-session.target` only auto-starts the unit when that target activates — and this box's boot path (`getty@tty1` autologin → fish → `start-hyprland`, no display manager, no `uwsm`) **never activates `graphical-session.target`** (`systemctl --user is-active graphical-session.target` → `inactive`). Result: elephant stays `inactive (dead)` at login, no `elephant.sock` is created, and Walker hangs forever on **"Waiting for elephant"**. The unit is correct and starts fine on demand (`systemctl --user start elephant.service` → loads all providers in <1s); it just needs an explicit trigger. That trigger is the `exec-once` line in 7e.iii below — which is the actual fix, not a "belt-and-suspenders fallback."

#### 7e.iii Hyprland integration

`~/.config/hypr/autostart.conf` already has `exec-once = walker --gapplication-service` (the frontend daemon, separate from Elephant). Because `graphical-session.target` never fires under this session (see the ⚠ note in 7e.ii), Elephant **must** be started explicitly here too — same pattern as the `hyprpolkitagent.service` line. Add an elephant start line **before** the walker line so the backend socket exists before the frontend looks for it:

```bash
# Start the Elephant backend (required — its WantedBy=graphical-session.target never fires here)
grep -qF 'start elephant.service' ~/.config/hypr/autostart.conf || \
  sed -i '/^exec-once = walker --gapplication-service/i exec-once = systemctl --user start elephant.service' \
    ~/.config/hypr/autostart.conf

# Confirm the walker frontend line is present
grep -n '^exec-once.*walker' ~/.config/hypr/autostart.conf || \
  echo 'exec-once = walker --gapplication-service' >> ~/.config/hypr/autostart.conf
```

The keybindings in `~/.config/hypr/keybindings.conf` that the original install already wired up (`Super`+`Space`, `Super`+`Ctrl`+`E`, `Super`+`Ctrl`+`V`) keep working — Walker invocations are forwarded to the resident frontend and routed to Elephant for results. No keybinding changes needed.

For fastest possible launch (skips even the GTK app startup, talks straight to the socket), you *can* swap the keybinding to use the socket — but it doesn't accept arguments, so it's only useful for the bare `Super`+`Space` case:

```hyprland
# Optional, in keybindings.conf — only swap if you measure that walker is slow
# bind = SUPER, SPACE, exec, nc -U /run/user/1000/walker/walker.sock
```

Leave the existing binding alone unless you need the extra ms — the resident service is already very fast.

#### 7e.iv Walker config — `~/.config/walker/config.toml`

```bash
mkdir -p ~/.config/walker
cat > ~/.config/walker/config.toml <<'EOF'
# Walker 2.x frontend config — paired with Elephant backend (see 7e.i)
theme = "default"
max_results = 50

[placeholders]
default              = { input = "Search…",     list = "No results" }
desktopapplications  = { input = "Launch app…", list = "No apps found" }
clipboard            = { input = "Clipboard…",  list = "Empty history" }
symbols              = { input = "Symbol…",     list = "No symbols" }
calc                 = { input = "= 2+2",       list = "No result" }
runner               = { input = "> command",   list = "No matches" }
files                = { input = "/path",       list = "No files" }
websearch            = { input = "@query",      list = "Press Enter to search" }

# Provider lists by context. 'default' = visible when Walker is opened with no prefix.
# 'empty' = visible when input is empty (just the launcher, before typing anything).
[providers]
default = [
  "desktopapplications",
  "calc",
  "runner",
  "menus",
  "websearch",
]
empty = ["desktopapplications"]

# Default prefix routing (override here only if you want a non-default prefix char).
# These match the official Walker 2.x defaults — listed for explicitness:
[[providers.prefixes]]
prefix   = "="
provider = "calc"

[[providers.prefixes]]
prefix   = ">"
provider = "runner"

[[providers.prefixes]]
prefix   = "/"
provider = "files"

[[providers.prefixes]]
prefix   = "."
provider = "symbols"

[[providers.prefixes]]
prefix   = ":"
provider = "clipboard"

[[providers.prefixes]]
prefix   = "@"
provider = "websearch"

[[providers.prefixes]]
prefix   = ";"
provider = "providerlist"
EOF
```

> **Default web-search prefix is `@`, not `?`.** Walker 2.x's default prefix changed from the older `?`. If you specifically want `?` back, replace the `websearch` prefix block above with `prefix = "?"` *and* update `shortcuts.md` §1.2 / §4 to match (currently those reflect the `@` default).

#### 7e.v Provider-specific configs under `~/.config/elephant/`

These are optional, but the websearch engine choice is the most common customization people regret not doing up front.

```bash
mkdir -p ~/.config/elephant

# Web search → DuckDuckGo (per Omarchy guide; default is google)
cat > ~/.config/elephant/websearch.toml <<'EOF'
[[engines]]
name    = "DuckDuckGo"
url     = "https://duckduckgo.com/?q=%TERM%"
default = true

[[engines]]
name = "GitHub"
url  = "https://github.com/search?q=%TERM%"

[[engines]]
name = "Arch Wiki"
url  = "https://wiki.archlinux.org/index.php?search=%TERM%"

[[engines]]
name = "MDN"
url  = "https://developer.mozilla.org/en-US/search?q=%TERM%"
EOF

# Restart elephant so it picks up the new provider configs
systemctl --user restart elephant.service
```

If you want to reset Walker's GTK frontend after editing themes or major config changes:

```bash
pkill -x walker && walker --gapplication-service &disown
```

#### 7e.vi Catppuccin theme (manual — not packaged)

Walker themes are a `style.css` + theme `.toml` pair under `~/.config/walker/themes/<name>/`. There's no official Catppuccin theme shipped; the community publishes a few. Quick scaffold:

```bash
mkdir -p ~/.config/walker/themes/catppuccin-mocha

# Pull a community-maintained Catppuccin walker theme (verify the URL before running —
# walker theme schemas drift between minor versions; pin to a tag matching your walker version)
# Search: github.com 'walker catppuccin' — pick the one with the most-recent commit
# Then in config.toml change:  theme = "catppuccin-mocha"
```

Leaving `theme = "default"` until you've confirmed the theme repo's compatibility with Walker 2.16.x is safer than committing a broken theme that'll wedge Walker on next launch.

#### 7e.vii Verify

```bash
# Backend
systemctl --user is-active elephant.service          # expect 'active'
elephant listproviders                               # expect 8 of 9 (menus is hidden by design — see 7e.ii)
journalctl --user -u elephant.service -b --no-pager | grep 'providers loaded'
                                                     # expect one line per installed provider, INCLUDING menus

# Frontend
pgrep -af 'walker --gapplication-service'            # expect a running PID

# Each capability — fire Walker (Super+Space) and try each prefix:
#   (nothing)  →  apps list with fuzzy search
#   =2*1024    →  calc returns 2048
#   .check     →  symbol picker shows ✓ ✔ ✅ ...
#   :          →  clipboard history populates from cliphist
#   /Pictures  →  file search under ~ for matches
#   >htop      →  runner offers htop
#   @rust async→  websearch opens DuckDuckGo with the query (default if you wrote 7e.v)
#   ;          →  providerlist shows every provider registered
```

If any prefix returns "No results" while its package is installed, check `journalctl --user -u elephant.service -n 50 --no-pager` for provider-load errors. The two most common causes (observed on this machine 2026-05-23):

1. **`Please install elephant.`** when running `walker -m <mode>` — the elephant service isn't running. Re-check 7e.ii.
2. **Version-mismatch** between `elephant` and one of the `elephant-*` packages (see 7e.i warning) — provider .so file refuses to load against a different hub version.

#### 7e.viii Update the snapshot doc

After 7e.i–iii are applied (the minimum to make Walker functional), update `ACTUAL-CONFIGURATION.md`:

- **§5** — add the `elephant` hub + each `elephant-*` provider package, all `2.21.0-1` from AUR.
- **§10** — add `elephant` to the running-daemons list (started by `elephant.service` user unit).
- **§12** — note `~/.config/systemd/user/elephant.service` (the user unit you wrote in 7e.ii). If you also did 7e.iv–v, change the `~/.config/walker/` and `~/.config/elephant/` lines from EMPTY.
- **§15** — flip the Walker row to ✅ Elephant-backed (8 query providers + menus subsystem; defaults working).

If you stop after 7e.iii (no config.toml, no provider configs), Walker runs on Elephant defaults — that's already a fully-working setup. 7e.iv–vi are only needed if you want to pin prefixes, swap the websearch engine, or change theme.

---

### 7f. VS Code — silence the "OS keyring couldn't be identified" notification

**Symptom.** On every launch, VS Code (`visual-studio-code-bin`, Electron) raises the notification *"An OS keyring couldn't be identified for storing the encryption related data in your current desktop environment."* Electron tries to store credentials in an OS keyring via `libsecret` → the `org.freedesktop.secrets` D-Bus service, and this Hyprland/Wayland session runs **no keyring daemon** (gnome-keyring isn't installed; KWallet isn't autostarted/unlocked) — so nothing registers a Secret Service on D-Bus.

**Fix.** Tell VS Code to skip the keyring lookup with `--password-store=basic`. The `/usr/bin/code` wrapper (used by both the terminal `code` command **and** the Walker `.desktop` launcher — both `Exec` lines point at it) reads launch flags from `~/.config/code-flags.conf`, one flag per line, `#` comments stripped.

```bash
cat > ~/.config/code-flags.conf <<'EOF'
# VS Code launch flags — read by the /usr/bin/code wrapper (visual-studio-code-bin).
# Skip the OS keyring lookup: this Hyprland session provides no Secret Service
# backend (org.freedesktop.secrets), so VS Code otherwise shows the startup
# notification "An OS keyring couldn't be identified for storing the encryption
# related data in your current desktop environment".
# Trade-off: stored secrets are kept in an obfuscated local file under
# ~/.config/Code, not encrypted by a keyring. To revert, delete this line and
# set up gnome-keyring or KWallet (see below).
--password-store=basic
EOF
```

> **fish note.** The heredoc above needs `bash` (type `bash`, paste, `exit`). To stay in fish, use the native echo form instead — the file only needs the one functional line:
> ```fish
> echo '--password-store=basic' > ~/.config/code-flags.conf
> ```

**Verify** the wrapper parses the file down to exactly the one flag:

```bash
echo "  ->[$(sed 's/#.*//' ~/.config/code-flags.conf | tr '\n' ' ' | xargs)]"
# expected:   ->[--password-store=basic]
```

**Apply it.** The flag is only read at process startup — *"Reload Window" will not pick it up*. **Fully quit VS Code** (close all windows) and reopen. The notification will be gone.

**Reverting / upgrading to real encryption later.** Delete the `--password-store=basic` line, then either:
- install `gnome-keyring` and let it provide the Secret Service, or
- enable KWallet (already installed) via autostart + a PAM unlock line.

Both give you an actually-encrypted store; `basic` keeps secrets (Settings-Sync login, extension tokens) in an obfuscated local file, which is fine on a single-user box.

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

## 10. Switch from plasma-login-manager to getty autologin + Hyprland from fish login

**Why this exists.** `plasma-login-manager` (PlasmaLogin / `plasmalogin.service`) is the source of the **phantom-cursor handoff bug** (Hyprland Discussions #13464): the greeter sets up a cursor plane on `eDP-1`; when Hyprland takes over, that plane isn't always invalidated, so a stale cursor image remains in the center of the laptop screen. The DPMS-toggle workaround in `autostart.conf` masks the symptom; this section removes the cause by removing the greeter entirely. Side benefits: faster boot (no Qt/Plasma libs in the auth path), one less Wayland session handoff, and a more diagnostic-friendly failure mode (drops to a fish prompt on tty1 instead of looping back to a graphical greeter that can't launch a compositor).

**Login shell.** This machine's login shell is **fish** (`/bin/fish` in `/etc/passwd` for `isalgado`). The primary path below uses `~/.config/fish/conf.d/99-hyprland-autostart.fish`. A **zsh** alternative is documented at the end of 10.d for the case where you've since switched login shells (or are replicating this on a zsh box).

**Reversibility:** high. `plasmalogin.service` is only **disabled**, not uninstalled — KDE Plasma remains available as a manual fallback session via `startplasma-wayland`. Full rollback in 10.g restores the previous setup in three commands.

**Risk:** low. Worst case: Hyprland fails to start on next boot and you land at a fish prompt on tty1, from which you can debug or run `startplasma-wayland` manually. There's no scenario where you're locked out — every TTY remains accessible.

### 10.a Pre-flight — confirm assumptions

```bash
getent passwd $USER | awk -F: '{print $7}'   # expect /bin/fish  (authoritative login shell)
echo $SHELL                                  # may show /usr/bin/zsh if launched from a non-login zsh — that's fine, $SHELL is inherited, not the login shell
whoami                                       # expect isalgado
who                                          # expect a single session on tty? (likely tty2 under Hyprland)
loginctl show-user isalgado                  # confirms logind sees you as the active user
systemctl is-enabled plasmalogin.service     # expect 'enabled' — that's what we're changing
ls -la ~/.config/fish/                       # confirms fish config dir is present
```

If the login shell in `/etc/passwd` shows `/usr/bin/zsh` (or you've intentionally moved to zsh), follow the **zsh alternative** at the bottom of step 10.d instead of the fish path. Don't follow both — pick the one that matches your current login shell.

### 10.b Disable plasma-login-manager (keep installed)

```bash
# Disable so it doesn't start on next boot. Do NOT stop while a graphical session is alive.
sudo systemctl disable plasmalogin.service

# Verify
systemctl is-enabled plasmalogin.service   # expect 'disabled'

# Do NOT mask — disable is the reversible level.
# Do NOT 'pacman -Rns plasma-*' — KDE stays as the safety-net DE per the original install plan.
```

### 10.c Set up getty autologin on tty1

Drop-in override for the existing `getty@tty1` unit (systemd's standard pattern; doesn't touch `/usr/lib/systemd/system/`):

```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf >/dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin isalgado --noclear %I $TERM
EOF
sudo systemctl daemon-reload
```

> The empty `ExecStart=` line is **load-bearing**: systemd requires explicitly clearing the inherited `ExecStart` before setting a new one. Without it you'd get two `ExecStart` lines and systemd would refuse to start the unit. `-` before `/sbin/agetty` suppresses failure exit codes from being treated as unit failure. `--noclear` keeps any prior tty output visible (useful if Hyprland crashes loudly).

Other TTYs (tty2–tty6) are unchanged — they keep prompting for username + password normally, so you always have a clean rescue TTY.

### 10.d Auto-launch Hyprland from fish login (primary path)

Drop a dedicated snippet into `~/.config/fish/conf.d/` rather than appending to `config.fish` directly — it isolates the change for easy removal in rollback, and keeps `config.fish` clean. All files in `conf.d/` are sourced automatically by every fish startup; the `status is-login` guard restricts the autostart to login shells only.

> **Heads-up: fish has no heredoc.** A `cat >file <<'EOF' … EOF` block (bash/zsh heredoc) errors out in fish with `Expected a string, but found a redirection`. The commands below use fish-native multi-line single-quoted strings piped with `echo`, which preserve `$` literally and don't expand variables — exactly what we want, since the `$WAYLAND_DISPLAY` and `$XDG_VTNR` references must land in the file unexpanded.

Run these in your fish shell:

```fish
# Create the autostart snippet (fish-native, no heredoc)
echo '# Auto-start Hyprland on tty1 only (post-install §10)
# Login shell + no existing Wayland session + virtual terminal 1 → exec start-hyprland.
if status is-login
    if test -z "$WAYLAND_DISPLAY" -a "$XDG_VTNR" = "1"
        exec start-hyprland
    end
end' >~/.config/fish/conf.d/99-hyprland-autostart.fish

# Verify
cat ~/.config/fish/conf.d/99-hyprland-autostart.fish

# (No backup needed — this is a new file. To remove later: rm the file.)
```

If you'd rather avoid the multi-line `echo` entirely, open the file in an editor instead:

```fish
nano ~/.config/fish/conf.d/99-hyprland-autostart.fish
# Paste the snippet body (the `if status is-login …` block above) and save.
```

Guard explanation (each clause matters):

- `status is-login` — fish's equivalent of "is this a login shell". Restricts the autostart to the autologin'd tty1 shell; **does not** fire inside kitty terminals you spawn under Hyprland (those are interactive non-login shells).
- `test -z "$WAYLAND_DISPLAY"` — only when no Wayland session is already attached. Belt-and-suspenders against an accidental nested launch.
- `test "$XDG_VTNR" = "1"` — only on tty1. tty2–tty6 stay as plain fish prompts so you can `Ctrl+Alt+F2` to a working shell if Hyprland breaks.
- `exec start-hyprland` — replaces the shell process with the **wrapper** at `/usr/bin/start-hyprland` (shipped by the `hyprland` package), which sets up the systemd user session, D-Bus activation, and XDG session vars (`XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=Hyprland`, etc.) before exec'ing the compositor itself. Required since Hyprland 0.53 — launching `Hyprland` bare emits a startup warning and leaves portals, polkit prompts, and screen sharing misconfigured. When Hyprland exits, the session ends and getty re-prompts (then the autologin + conf.d chain restarts Hyprland — so `Super+Shift+Q` effectively becomes "restart Hyprland"). To get a real shell after exit: switch to tty2 first.

**Why `conf.d/` and `status is-login` together (not `config.fish` alone, not bare `conf.d/`):** fish has no direct equivalent of zsh's split between `.zlogin` (login-only) and `.zshrc` (every interactive shell). Both `config.fish` and `conf.d/*.fish` are sourced for every fish shell. The `status is-login` guard is what makes the snippet equivalent to `.zlogin` semantics. Without it, opening a kitty terminal inside Hyprland would attempt `exec start-hyprland` and either deadlock or kill your terminal (the inner two guards would still bail out, but you'd be relying on `$XDG_VTNR` not being 1 — fine for kitty under Hyprland on tty2, fragile if you ever launch a terminal directly on tty1).

#### 10.d alt — zsh alternative (only if your login shell is `/usr/bin/zsh`)

Skip this block if you followed the fish path above. Use it only if `getent passwd $USER` shows `/usr/bin/zsh`.

Two variants depending on which shell you're typing the install commands into.

**Run from zsh / bash** (heredoc works):

```bash
[ -f ~/.zlogin ] && cp ~/.zlogin ~/.zlogin.bak

cat >>~/.zlogin <<'EOF'

# Auto-start Hyprland on tty1 only (post-install §10)
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
  exec start-hyprland
fi
EOF
```

**Run from fish** (heredoc forbidden — same `echo`-with-single-quoted-string trick as the primary path):

```fish
test -f ~/.zlogin; and cp ~/.zlogin ~/.zlogin.bak

echo '
# Auto-start Hyprland on tty1 only (post-install §10)
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = "1" ]; then
  exec start-hyprland
fi' >>~/.zlogin
```

The single quotes are load-bearing in both variants — they keep `$WAYLAND_DISPLAY` and `$XDG_VTNR` unexpanded so the file contains literal zsh references, evaluated later when zsh actually sources `.zlogin`.

`.zlogin` (not `.zprofile` or `.zshrc`) is the correct file in zsh: it runs only for **login** shells, which is exactly what getty's autologin produces. `.zshrc` runs for every interactive shell (including every kitty terminal you open inside Hyprland) — putting `exec start-hyprland` there would be catastrophic.

### 10.e Reboot to apply

```bash
sudo systemctl reboot
```

Expected sequence:
1. Limine menu → linux-cachyos picked.
2. Kernel boot messages visible (assuming you stripped `quiet splash` in §6).
3. **No greeter.** tty1 flashes briefly with `agetty` autologin.
4. Hyprland comes up directly — workspace 1 on the Samsung, just as before.

If it works, the phantom cursor should be gone (or at least no longer attributable to greeter handoff).

### 10.f Verify

```bash
echo $XDG_VTNR                              # expect 1
echo $XDG_SESSION_TYPE                      # expect wayland
echo $XDG_CURRENT_DESKTOP                   # expect Hyprland
loginctl session-status | head -10          # expect Wayland, tty1, isalgado
systemctl is-active plasmalogin.service     # expect inactive
systemctl is-enabled plasmalogin.service    # expect disabled
hyprctl version | head -2                   # confirms Hyprland is the compositor
ps -p $fish_pid -o comm= 2>/dev/null; or ps -p $$ -o comm=   # confirms terminal shell is fish (zsh on the alt path)
ls ~/.config/fish/conf.d/99-hyprland-autostart.fish   # fish path: file exists
# OR on the zsh alt path:
# grep -A3 'Auto-start Hyprland' ~/.zlogin
```

### 10.g Rollback (full restore of plasma-login-manager)

```bash
sudo systemctl enable plasmalogin.service
sudo rm /etc/systemd/system/getty@tty1.service.d/override.conf
sudo systemctl daemon-reload

# Remove the fish autostart snippet (primary path)
rm -f ~/.config/fish/conf.d/99-hyprland-autostart.fish

# If you used the zsh alternative instead, restore the backup:
if [ -f ~/.zlogin.bak ]; then
  mv ~/.zlogin.bak ~/.zlogin
elif [ -f ~/.zlogin ]; then
  # No backup → just strip the appended block
  sed -i '/Auto-start Hyprland on tty1 only/,/^fi$/d' ~/.zlogin
fi

sudo systemctl reboot
```

After reboot the PlasmaLogin greeter should reappear at boot just as before.

### 10.h If Hyprland fails to start at next boot

You'll land at a fish prompt on tty1 (the autologin worked, but `exec start-hyprland` failed and the shell continued — on the zsh alt path, a zsh prompt). Diagnose from there:

```bash
# Capture the failure
Hyprland 2>&1 | tee /tmp/hypr-fail.log
journalctl --user -b -p err --no-pager | tail -40

# If Hyprland is unrecoverable right now, use KDE as a one-shot fallback (no DM re-enable needed):
startplasma-wayland

# Or just switch to tty2 for a normal text login and full toolkit:
# Ctrl+Alt+F2
```

### 10.i Notes / gotchas

- **`Super+Shift+Q` behavior changes.** Previously: exits Hyprland → returns to PlasmaLogin greeter. Now: exits Hyprland → getty autologin → fish `conf.d` (or `.zlogin` on the zsh alt path) → Hyprland again. So `Super+Shift+Q` is effectively "restart compositor" instead of "log out". To actually log out: switch to tty2 via `Ctrl+Alt+F2`, then `loginctl terminate-user isalgado`.
- **KDE fallback still works.** Boot into the failure path above and run `startplasma-wayland`. No DM re-enable required.
- **dbus / xdg-desktop-portal**: `exec start-hyprland` (the wrapper at `/usr/bin/start-hyprland` shipped by the `hyprland` package since 0.53) is what handles the dbus + portal + systemd user-session bring-up — it sets `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=Hyprland`, registers with logind, and activates the user-units before exec'ing the compositor. If you later notice portal-related issues (file pickers, screensharing, polkit prompts not appearing), check that `start-hyprland` is on `$PATH` and that the autostart snippet calls the wrapper, not the bare `Hyprland` binary. Modern alternative: [`uwsm`](https://github.com/Vladimir-csp/uwsm) (Universal Wayland Session Manager) — `exec uwsm start hyprland-uwsm.desktop` — gives cleaner `graphical-session.target` semantics but adds a dependency.
- **`env.conf` keeps working.** The `env = ...` lines in `~/.config/hypr/env.conf` are processed by Hyprland itself, not by the launching shell. Changing the launch path doesn't affect NVIDIA/Qt env vars.
- **Update `ACTUAL-CONFIGURATION.md` §2** once this is applied: ✅ Done 2026-05-23. Display-manager row, §14, §15 row, and the §17 boot flow now reflect the `getty@tty1` autologin + fish `exec start-hyprland` path.

### 10.j References

- [Hyprland Discussions #13464 — phantom cursor handoff bug from KDE login manager](https://github.com/hyprwm/Hyprland/discussions/13464) — the original motivation for this change.
- [Arch Wiki — Automatic login to virtual console](https://wiki.archlinux.org/title/Getty#Automatic_login_to_virtual_console) — canonical `getty@tty1` override pattern.
- [Arch Wiki — Start X / Wayland at login](https://wiki.archlinux.org/title/Start_X_at_login) — login-shell guard conventions (both `.zlogin` and fish `status is-login`).
- [fish docs — Initialization files](https://fishshell.com/docs/current/language.html#initialization-files) — confirms `conf.d/*.fish` is sourced on every startup and `status is-login` is the correct login-shell guard.
- [Hyprland Wiki — starting Hyprland](https://wiki.hypr.land/Getting-Started/Master-Tutorial/) — confirms Hyprland is greeter-agnostic. As of Hyprland 0.53, the supported launch is `exec start-hyprland` (the package-shipped wrapper that initializes the systemd user session and XDG env before exec'ing the compositor); `exec Hyprland` still works but emits a startup warning and skips that setup.
- [Omarchy install scripts](https://github.com/basecamp/omarchy) — reference implementation of the no-DM Hyprland pattern this section follows.

---

## 11. NVIDIA black-screen on resume from suspend — force `s2idle` (CONFIRMED ISSUE)

**Why this exists.** Resuming from **deep (S3)** suspend crashes the NVIDIA open kernel module (595.71.05) and leaves the screen black while the system keeps running headless. Diagnosed 2026-05-26 from the journal of the session that ended in a forced power-off — see `ACTUAL-CONFIGURATION.md` §15 ("NVIDIA black-screen on resume from suspend").

**Diagnosis (what the journal showed).** On the 2026-05-26 21:38 resume:

```
PM: suspend exit
[drm:__nv_drm_connector_detect_internal [nvidia_drm]] *ERROR* ... Failed to detect display state
NVRM: ... mmuWalkUnmap: Failed to unmap VA Range ...  Status = 0x00000040
NVRM: ... mmuWalkSparsify: Failed to sparsify VA Range ...
   ( ×333 NVRM assertion failures — the GPU MMU never restored its mappings )
nvidia-modeset: WARNING: GPU:0: Failed to disable hotplug notifications
```

The display engine wedged → screen stayed black → journal ends mid-line at 21:44 with **no shutdown sequence** (hard power-off). The same `Failed to detect display state` appeared milder on the 2026-05-25 19:15 resume, so it recurs.

**Not a misconfig.** The usual S3 mitigations were *already* correctly in place and did **not** prevent this:

```bash
grep -i preserve /proc/driver/nvidia/params         # PreserveVideoMemoryAllocations: 1  ✓
grep -i temporaryfile /proc/driver/nvidia/params     # TemporaryFilePath: "/var/tmp"      ✓
systemctl is-enabled nvidia-{suspend,resume,hibernate}.service   # all 'enabled'          ✓
```

So this is a driver-level S3-resume bug. The fix is to suspend via **`s2idle`** instead of S3, which resumes reliably on this NVIDIA + Wayland laptop.

### 11a. Apply live (no reboot — test before committing to the bootloader)

```bash
echo s2idle | sudo tee /sys/power/mem_sleep
cat /sys/power/mem_sleep            # want: [s2idle] deep   (brackets = active)
```

Then suspend and resume once. A clean resume journal should have **no** `Failed to detect display state` and **no** `NVRM:` MMU-walk flood:

```bash
systemctl suspend                   # resume, then:
journalctl -b 0 -k --since "5 min ago" | grep -iE "NVRM|Failed to detect display state"
```

### 11b. Persist on the `linux-cachyos` cmdline (survives reboots)

Edit goes in `/etc/default/limine`, **not** `/boot/limine.conf` — the latter is regenerated by `limine-mkinitcpio-hook`/`limine-snapper-sync` on every kernel update or snapshot and your edit would be lost.

```bash
# Append the param (commented, matching the existing convention in the file)
printf '\n# Added 2026-05-26: force s2idle to fix NVIDIA S3-resume black-screen (ACTUAL-CONFIGURATION.md §15)\nKERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle"\n' | sudo tee -a /etc/default/limine

# Regenerate the boot entries
sudo limine-mkinitcpio
```

### 11c. Verify after reboot

```bash
cat /proc/cmdline                   # should contain mem_sleep_default=s2idle
cat /sys/power/mem_sleep            # should show [s2idle] deep
```

⚠ This patches only the `linux-cachyos` entry. The `linux-cachyos-lts` entry is **not** updated (same gap as §0 for `nvidia-drm.modeset=1` and §6 for `thunderbolt.host_reset=0`) — booting LTS will still use S3 until you add the param to its entry too.

### 11d. Recovery / revert

To go back to S3 suspend, remove the appended block from `/etc/default/limine` and re-run `sudo limine-mkinitcpio`. To revert just the live setting without a reboot: `echo deep | sudo tee /sys/power/mem_sleep`.

If a future NVIDIA driver fixes S3 resume, this whole section can be dropped — re-test S3 by reverting and doing a suspend/resume cycle.

### 11e. References

- [Arch Wiki — Power management / Suspend and hibernate: `mem_sleep`](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate#Changing_suspend_method) — `mem_sleep_default=` kernel param and `/sys/power/mem_sleep` semantics.
- [Arch Wiki — NVIDIA/Tips: Preserve video memory after suspend](https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Preserve_video_memory_after_suspend) — the `nvidia-{suspend,resume,hibernate}` + `PreserveVideoMemoryAllocations` mechanism that was already in place.

---

## 12. Firefox freeze 2026-07-02 — VA-API off the NVIDIA shim, hardware decode paused (CONFIRMED ISSUE)

**Symptom (2026-07-02 21:10):** Firefox froze solid mid-video; the whole session was on borrowed time until reboot.

### 12a. What actually happened (journal, boot `8790fdd2809a4b8991c4b0d1f17b1a94`)

1. **20:48:45 — resume from suspend; the dGPU never came back.** GSP firmware re-init failed: `NVRM: … Reset required [NV_ERR_RESET_REQUIRED] … kgspWaitForRmInitDone`. The dGPU is dead until reboot, and everything that touches it afterwards logs NVRM errors — **384 this boot** (344 / 359 on the two prior boots; a boot without a suspend cycle logged 0).
2. **20:57:39** — `NVRM: GPU0 vaspaceapiConstruct_IMPL: Could not construct VA space. Status 1a`: a client tried to create a GPU **virtual address space** on the dead dGPU. Despite the name, this is *not* the VA-API video shim — it's generic GPU memory management failing.
3. **21:10:42–54 — the freeze.** Firefox's decoder thread hung the **Intel iGPU's** video engine three times (`i915 … GPU HANG: ecode 12:4:0ccbc9c7, in MediaPD~der`), and i915's hang-recovery then crashed the kernel: `BUG: kernel NULL pointer dereference … RIP: __gen8_ppgtt_clear+0x1da/0x2c0 [i915]`. That wedges i915's GPU memory management — and i915 drives all three monitors.

### 12b. Findings that corrected the working theory

- **Firefox never used the NVIDIA VA-API path.** Walker → Elephant launches apps from the systemd `--user` manager, so `env.conf` vars (including `LIBVA_DRIVER_NAME=nvidia`) never reach them — verified in the running Firefox's `/proc/<pid>/environ`. Firefox auto-picked the compositor's device and was **already** hardware-decoding on the iGPU.
- **The compositor renders on the iGPU.** aquamarine: `card2` (i915) is primary DRM, renderer on `renderD129`; all three monitors are iGPU connectors. `card1` (NVIDIA) is a secondary backend with unused connectors (`eDP-2`, `HDMI-A-1`).
- **Firefox's profile is XDG-based:** `~/.config/mozilla/firefox/31yk9hxe.default-release` (there is no `~/.mozilla`). The pacman `firefox 151.0.4` is the one in use; the `org.mozilla.firefox` flatpak has no profile.
- Net: **two independent bugs** (NVIDIA GSP resume death on `610.43.02`; i915 hang-recovery NULL deref in `7.0.12-1-cachyos`) **plus one useless config** (VA-API forced at a dGPU that should never decode video).

### 12c. Applied 2026-07-02 (repo + live, no sudo needed)

1. `configs/hypr/env.conf` → `~/.config/hypr/env.conf`: `LIBVA_DRIVER_NAME` `nvidia` → `iHD` (`intel-media-driver 26.1.5` was already installed); `NVD_BACKEND=direct` removed (shim-only knob). Takes effect on the next Hyprland start — the reboot below covers it.
2. Firefox hardware video decode **paused** via `~/.config/mozilla/firefox/31yk9hxe.default-release/user.js`:

   ```js
   user_pref("media.ffmpeg.vaapi.enabled", false);
   user_pref("media.hardware-video-decoding.force-enabled", false);
   ```

   Software decode is the deliberate stable state: on this kernel any future video-engine hang can NULL-deref again, and env vars can't protect Walker-launched Firefox — profile prefs can. The i9-12900H handles software decode fine; the cost is CPU/battery, not stability.

### 12d. Run with sudo (pending)

```bash
# Remove the NVIDIA VA-API shim — leaf package, nothing depends on it
# (revert = sudo pacman -S libva-nvidia-driver):
sudo pacman -Rns libva-nvidia-driver

# While you have sudo, inspect the LTS boot entry (escape hatch for the i915 bug):
sudo grep -i -B2 -A8 lts /boot/limine.conf
# → its cmdline should match the main entry (root=…, nowatchdog,
#   thunderbolt.host_reset=0, mem_sleep_default=s2idle).
# modeset params are NOT needed on any cmdline anymore: nvidia-drm.modeset is the
# 610-series driver default and the modules early-load via
# /etc/mkinitcpio.conf.d/10-chwd.conf (kernel-agnostic).
```

Then **reboot** — mandatory regardless: this boot's i915 is wedged (the NULL deref already fired at 21:10).

### 12e. Verify after reboot

```bash
env | grep LIBVA                    # in a keybind-launched kitty → LIBVA_DRIVER_NAME=iHD
journalctl -k -b 0 | grep -c NVRM   # ~0 before the first suspend
```

- Firefox `about:support` → the media section should report hardware video decoding **disabled** (by pref).
- Play ~10 min of video; `journalctl -kf` must stay free of `GPU HANG`.
- After the first suspend/resume: if the GSP `Reset required` burst returns, that's the separate open dGPU bug (§15 row) — the session should survive it since nothing critical runs on the dGPU.

### 12f. Re-enable hardware decode later (the real fix arrives with a kernel)

When a kernel newer than `7.0.12-1-cachyos` lands (or when testing on `linux-cachyos-lts`):

1. Delete the two `user_pref` lines (or the whole `user.js` if nothing else was added to it) and restart Firefox — it will hardware-decode on the iGPU via iHD, which is the desired end state.
2. Play video and watch `journalctl -kf` for `GPU HANG`. Clean for a few sessions → keep it. A hang again → restore the prefs and stay on software decode.

Optional sanity check of the iHD stack: `sudo pacman -S libva-utils`, then `vainfo --display drm --device /dev/dri/by-path/pci-0000:00:02.0-render`.

### 12g. Escape hatch if freezes continue even with hardware decode off

Boot `linux-cachyos-lts 6.18.35` from the Limine menu (verify the entry per §12d first). Its i915 predates the bleeding-edge branch — that's the point — but re-test suspend/resume behavior there before adopting it.

### 12h. References

- Journal evidence: `journalctl -k -b 8790fdd2809a4b8991c4b0d1f17b1a94`.
- [Arch Wiki — Hardware video acceleration](https://wiki.archlinux.org/title/Hardware_video_acceleration) — VA-API driver selection (`LIBVA_DRIVER_NAME`, iHD vs the NVIDIA shim).
- [Arch Wiki — Firefox § Hardware video acceleration](https://wiki.archlinux.org/title/Firefox#Hardware_video_acceleration) — `media.ffmpeg.vaapi.enabled`.

---

## 13. Install VLC (video playback) — ✅ APPLIED 2026-07-31

**Why:** no general-purpose video player was set up for GUI use. What was on the machine was a half-install: `vlc-plugins-all` was *explicitly* installed (2026 install-time), which pulled `libvlc` and every codec plugin — but the `vlc` package itself and its Qt GUI never were, so there was **no `vlc` binary on `$PATH`**. `haruna` (mpv/Qt, KDE) was installed and does work, but it wasn't documented anywhere and wasn't the ask.

**Applied state 2026-07-31:** `vlc 3.0.23_2-9.1` installed (5 packages, as predicted); hardware decode disabled via `~/.config/vlc/vlcrc`; Elephant hot-reloaded so VLC appears in Walker with no restart. Verification evidence in §13e.

### 13a. Install

```bash
sudo pacman -S vlc
```

Pulls only **5 packages** — every plugin dependency is already satisfied:

| Package | Why |
|---|---|
| `vlc` | The metapackage / `vlc` launcher + `.desktop` entry |
| `vlc-gui-qt` | The Qt5 interface (the actual window) |
| `vlc-cli` | `cvlc`/`nvlc` command-line frontends (hard dep of the Qt GUI) |
| `qt5-svg`, `qt5-x11extras` | Qt5 deps of `vlc-gui-qt` |

`qt5-wayland` is already installed (§6 of `ACTUAL-CONFIGURATION.md`), so no extra Wayland plumbing is needed.

### 13b. Make it appear in Walker

VLC ships `/usr/share/applications/vlc.desktop`. Elephant's `desktopapplications` provider **sometimes** hot-reloads and sometimes serves a stale cache (Obsidian hot-reloaded; Google Chrome did not — see §7 notes in `ACTUAL-CONFIGURATION.md`).

**2026-07-31: it hot-reloaded — no restart was needed.** Verified immediately after install:

```bash
elephant query 'desktopapplications;vlc;5'
# → identifier:"vlc.desktop" text:"VLC media player" subtext:"Media player" score:88   ← top hit
```

If a future install *doesn't* show up, the fallback is still `systemctl --user restart elephant.service`.

Nothing goes in `configs/applications/` — that mirror is only for custom entries like `shortcuts.desktop`.

### 13c. ⚠ Turn hardware decoding OFF (this machine, for now)

This is the one non-obvious step. Per §12, the i915 hang-recovery NULL deref in kernel `7.0.12`/`7.1.x` can wedge the whole session when a client hangs the **iGPU** video engine — which is exactly what Firefox did on 2026-07-02. Firefox is pinned to software decode via its profile `user.js`; VLC needs the equivalent, or it reintroduces the same freeze risk with the same GPU.

VLC defaults to `--avcodec-hw=any`, i.e. it *will* try VA-API (→ iHD → iGPU). Disable it:

**GUI:** Tools → Preferences → **Show settings: All** → Input / Codecs → *Hardware-accelerated decoding* → **Disable** → Save.

**Or write the config directly** — this is what was done on 2026-07-31:

```bash
mkdir -p ~/.config/vlc
printf '[avcodec]\navcodec-hw=none\n' >> ~/.config/vlc/vlcrc
```

VLC does **not** rewrite `vlcrc` on exit — verified by md5 before/after a full headless playback run, file unchanged. It only rewrites when you hit **Save** in the Preferences dialog, and since it reads the value at startup the GUI will show "Disable" and a Save preserves it. A hand-written partial `vlcrc` is therefore safe to leave in place.

**Or per-launch:** `vlc --avcodec-hw=none <file>`

The i9-12900H decodes 4K H.264/HEVC in software without trouble; the cost is CPU and battery, not playability.

> Re-enable (`avcodec-hw=any`, or just delete the `vlcrc` line) at the same time as Firefox's decode prefs — see §12f — once a kernel past `7.0.12-1-cachyos` proves stable.

### 13d. Do not rely on `env.conf` here

`LIBVA_DRIVER_NAME=iHD` lives in `configs/hypr/env.conf`, which only reaches processes **Hyprland** spawns. Walker/Elephant launches apps from the systemd `--user` manager, which never sees those vars (the §12b finding). So a Walker-launched VLC gets no `LIBVA_DRIVER_NAME` at all — which is another reason 13c belongs in `~/.config/vlc/vlcrc`, not in an env var.

### 13e. Verify — results 2026-07-31 ✅

```bash
which vlc                # → /usr/bin/vlc
vlc --version            # → VLC 3.0.23 Vetinari (3.0.23-2-0-g79128878dd)
grep -A1 '^\[avcodec\]' ~/.config/vlc/vlcrc | grep avcodec-hw    # → avcodec-hw=none
```

**The decode path is the check that matters.** Don't trust the config file alone — prove VLC honours it. Play any file headless with verbose logging and read the module lookup:

```bash
ffmpeg -y -f lavfi -i testsrc=size=1280x720:rate=30:duration=3 -c:v libx264 -pix_fmt yuv420p /tmp/test.mp4
vlc -I dummy -vv --play-and-exit --no-audio --vout=dummy /tmp/test.mp4 2>&1 | grep -i 'hw decoder\|trying format'
```

Expected — and what was observed:

```
avcodec decoder debug: trying format vaapi
main generic debug: looking for hw decoder module matching "none": 3 candidates
main generic debug: no hw decoder modules matched          ← the pin is working
avcodec decoder debug: trying format vdpau
main generic debug: no hw decoder modules matched
main decoder debug: Received first picture                 ← software decode succeeded
```

VLC still *enumerates* the hardware formats (vaapi, vdpau, cuda, vulkan are all compiled in) and still *tries* them — that's normal. The pin bites one step later, at the hw-decoder **module** lookup, which is what keeps the iGPU video engine untouched.

Kernel log after the run: `journalctl -k -b 0 --since "10 min ago" | grep -ci "GPU HANG\|i915.*error\|NULL pointer"` → **0**.

Then play a real video in the GUI and confirm: window opens, audio routes through PipeWire, subtitles render, `journalctl -kf` stays clean.

### 13f. Revert

```bash
sudo pacman -Rns vlc vlc-gui-qt vlc-cli
```

Leave `vlc-plugins-all` — it predates this install and `phonon-qt6-vlc` (KDE's multimedia backend) depends on the libvlc side of it.

### 13g. Docs updated 2026-07-31 ✅

- `ACTUAL-CONFIGURATION.md` — §7 media table (VLC installed; `haruna` documented for the first time), §9 counts (explicit 273 → **274**, total 1427 → **1432**, AUR unchanged at 12), §15 row moved to ✅, §16 repo layout gained `configs/vlc/`.
- `spected-installation.md` — VLC added to the recommended stack as the video-player entry.
- `configs/vlc/vlcrc` — the decode pin is now mirrored in the repo. Restore path on a rebuild: `cp configs/vlc/vlcrc ~/.config/vlc/vlcrc`.

---

## 14. Battery charge cap at 80% (acer-wmi-battery) — ✅ VERIFIED WORKING 2026-10-31 (installed 2026-10-12)

**Why:** the original battery failed and was physically removed on 2026-10-12. A replacement is on order and should arrive within a few weeks. The likely cause is months spent docked at 100%, made worse by a gaming laptop's heat. Capping the charge at 80% is the standard mitigation, and it should already be in place when the new pack goes in.

**Why this tool and not TLP / KDE / GNOME:** all of those write the kernel's standard `charge_control_end_threshold` attribute on the battery's `power_supply` node. Nothing on this machine exposes that attribute. The in-kernel `acer_wmi` (7.2.8) has no battery code at all: its module contains no charge, battery or health strings. The firmware *does* expose Acer's battery-health WMI interface, GUID `79772EC5-04B1-4BFD-843C-61E7F77B6CC9`, which is what Acer Care Center / PredatorSense use on Windows. `acer-wmi-battery` is a small out-of-tree driver for exactly that GUID.

**Evidence gathered 2026-10-12, before installing:**

| Check | Result |
|---|---|
| Battery present | No. `/sys/class/power_supply/` holds only `ACAD` and two UCSI USB-C sources |
| Battery-health WMI GUID | Present (`79772EC5-04B1-4BFD-843C-61E7F77B6CC9-4`, no driver bound) |
| Charge limit in the in-kernel `acer_wmi` | None |
| Upstream `MODELS.md` | Predator Triton 300 SE and Helios Neo 16 reported working. PT516-52s not listed |
| Test build vs `7.2.8-1-cachyos` (clang 22, ThinLTO, `LLVM=1`) | ✅ clean |
| Test build vs `6.18.52-1-cachyos-lts` (GCC) | ✅ clean |
| `makepkg` of AUR `acer-wmi-battery-dkms 0.2.0-2` | ✅ source sha256 matches the PKGBUILD |
| Reviewed by hand | PKGBUILD, `dkms.conf`, `.install` (prints a notice, sleeps 5 s), Makefile (plain `obj-m`), C source (three WMI methods: 19 battery info, 20 get status, 21 set) |
| Secure Boot | Disabled, so the unsigned DKMS module loads without MOK enrolment |

**Rejected alternative:** `linuwu-sense-dkms` / `div-acer-manager-max` (DAMX). It has the same fixed 80% limiter, but it *replaces* the in-kernel `acer_wmi` to add fan, RGB and thermal control, and upstream only claims full support for the PHN16-71. More blast radius for the same cap.

### 14a. Install

Run in a Kitty terminal, since the `sudo` prompts are interactive:

```bash
paru -S --skipreview acer-wmi-battery-dkms
sudo install -Dm644 ~/code/cachyPool/configs/modprobe.d/acer-wmi-battery.conf /etc/modprobe.d/acer-wmi-battery.conf
sudo modprobe acer_wmi_battery
```

- **`dkms` comes along** as the only new dependency. pacman picks the `cachyos` repo build (`3.4.3-1`), which depends on clang/lld/llvm. Those are already installed, and the main kernel needs them because it is clang-built. The DKMS pacman hook builds the module for **both** installed kernels and rebuilds it on every kernel update.
- **Autoload:** the package ships `/usr/lib/modules-load.d/acer-wmi-battery.conf`, so the module loads at every boot.
- **The cap itself** comes from `configs/modprobe.d/acer-wmi-battery.conf`, which sets `enable_health_mode=1`. Every module load re-sends the 80% cap. Without that option the module loads but leaves the firmware setting untouched.
- **The cap is fixed at 80%** by the firmware. It is not configurable.
- **paru asks you to pick a provider** because `acer-wmi-battery-dkms-git` also provides the name. Pick `1`, the default: the pinned `0.2.0` release with a checksum, which is the one reviewed above. The `-git` package builds whatever is on the upstream branch that day.

### 14b. Verify

```bash
dkms status acer_wmi_battery                              # → installed for 7.2.8-1-cachyos and 6.18.52-1-cachyos-lts
lsmod | grep acer_wmi_battery
cat /sys/bus/wmi/drivers/acer-wmi-battery/health_mode     # 1 = cap on · 0 = off · -1 = firmware reports it unsupported
journalctl -k -b | grep acer_wmi_battery                  # "available modes: health mode, calibration mode"
systemctl is-failed systemd-modules-load.service          # must print "active", not "failed"
```

The real test is not any of the above: it is **charging stopping near 80% instead of climbing to 100%**. That test was finally run on 2026-10-31 and it passed — see "Results 2026-10-31" below. The 2026-10-12 results are kept because they explain what a `health_mode = 0` with no pack looks like.

```bash
upower -i $(upower -e | grep BAT)
```

**Results 2026-10-12: installed and loading, cap not active yet.**

| Check | Result |
|---|---|
| Install sequence | paru 21:02:50 → 21:03:20 (`dkms` first, then the package), option file copied 21:03:28, `modprobe` 21:03:35. The option was in place before the load |
| `dkms status` | `installed` for `7.2.8-1-cachyos` and `6.18.52-1-cachyos-lts`. The 7.2.8 `make.log` shows DKMS added `LLVM=1` by itself for the clang-built kernel |
| `modprobe -c` | `options acer_wmi_battery enable_health_mode=1`, plus the alias `wmi:79772EC5_04B1_4bfd_843C_61E7F77B6CC9`, so udev can also autoload it |
| `lsmod` | loaded |
| Kernel log | `available modes: health mode, calibration mode`, and no `active modes` line. Also `module verification failed: signature and/or required key missing - tainting kernel`, which is expected for an unsigned out-of-tree module with Secure Boot off |
| `health_mode` | **`0`** |
| `temperature` | `No such device or address`, since there is no pack to read |
| `systemd-modules-load.service` | `active` |

**Reading the `0`:** the set call succeeded at the ACPI level, because otherwise init returns `-EIO` and the module would not be loaded. Yet the firmware's own status read right after it reports health mode off. The driver ignores the firmware's return code, so a silent refusal looks exactly like this. The likely reason is that there is no pack for the EC to apply the cap to. That is not proven: it could also mean this firmware ignores the command. The successful load without a battery does settle one worry: boot will not fail `systemd-modules-load.service`.

**Results 2026-10-31: the cap works. ✅**

The replacement pack (Getac `AP20BHU`, serial `41378`, `cycle_count` 0) was fitted with the laptop off and the machine booted normally, so the module re-sent the cap as it loaded.

| Check | Result |
|---|---|
| `health_mode` | **`1`** |
| Kernel log | `acer_wmi_battery: active modes: health mode` — the line that was missing on the two pack-less boots |
| `temperature` | `27900` → 27.9 °C, readable now that there is a pack |
| **Charge stop** | the pack charged from 74% and **stopped at exactly 80%** |
| `BAT1/status` | `Not charging`, with `ACAD/online` = `1` |
| `charge_now` | identical at 11:37 and 11:43 — six minutes, not a pause |
| `current_now` | `0` |
| `upower` | `state: pending-charge`, `energy-rate: 0 W` |
| Pack health | `energy_full` 101.67 Wh vs 99.99 Wh design — factory variance on a 0-cycle pack, not cap-induced drift |

**Nothing else on this machine could have stopped it.** TLP is not installed. BAT1 exposes **no** `charge_control_*` or `charge_behaviour` node at all, because the in-kernel `acer_wmi` has no charge-limit code. The only limiter present is `health_mode`. So the `0` seen on 2026-10-12 was exactly what it looked like: no pack for the EC to apply the setting to, not a firmware refusal. The `linuwu-sense` fallback named above is **no longer needed**.

Re-run the check any time with:

```bash
cat /sys/bus/wmi/drivers/acer-wmi-battery/health_mode     # 1
cat /sys/class/power_supply/BAT1/status                   # "Not charging" at 80% on AC
upower -i $(upower -e | grep BAT)                         # state: pending-charge, 0 W
```

**Lifting the cap for travel is not persistent, by design.** `/etc/modprobe.d/acer-wmi-battery.conf` re-sends `enable_health_mode=1` on every module load, so an `echo 0` survives only until the next load or reboot. That is deliberate: forgetting to re-arm the cap is what killed the first pack. `triton-panel` exposes the same toggle as a switch and says so in the toast.

### 14c. Calibration mode: leave it alone

The driver also exposes `/sys/bus/wmi/drivers/acer-wmi-battery/calibration_mode`. Calibration turns health mode off, charges to 100%, drains, and recharges, which takes hours on AC with the laptop idle. It is not part of this setup. If it is ever used, write `0` to it by hand afterwards, because the driver does not handle the firmware's completion event, then write `1` to `health_mode` again.

### 14d. Revert

```bash
echo 0 | sudo tee /sys/bus/wmi/drivers/acer-wmi-battery/health_mode   # lift the cap in firmware first
sudo rm /etc/modprobe.d/acer-wmi-battery.conf
sudo modprobe -r acer_wmi_battery
paru -Rns acer-wmi-battery-dkms                                        # takes dkms with it if nothing else needs it
```

### 14e. Docs updated

**2026-10-31** (cap verified)

- `ACTUAL-CONFIGURATION.md`: header, §1 battery row, §8 `acer-wmi-battery-dkms` row, §15 battery row moved to ✅ with the evidence, §15 hypridle row annotated (battery-only suspend armed again).
- `CLAUDE.md`: battery bullet rewritten.
- `shortcuts.md`: §7 lid-close note and the hypridle suspend bullet — both paths are live again now that there is a pack.

**2026-10-12** (installed)

- `ACTUAL-CONFIGURATION.md`: §1 battery row, §8 rows for `acer-wmi-battery-dkms` and `dkms`, §9 counts, §15 new row, §16 repo layout gained `configs/modprobe.d/`.
- `configs/modprobe.d/acer-wmi-battery.conf`: new mirror of `/etc/modprobe.d/acer-wmi-battery.conf`. Restore path on a rebuild is the `sudo install` line in §14a.
- `CLAUDE.md`: hardware-constraints bullet.

---

## 15. logind: ignore lid close on external power — ✅ APPLIED 2026-10-12 (written 2026-07-12, never installed until then)

**Why:** resuming from s2idle can crash `nvidia_modeset` on this machine, ending in a black screen and a forced power-off (GSP row in `ACTUAL-CONFIGURATION.md` §15). The 2026-07-12 mitigation had two halves: hypridle's 20-min suspend became battery-only, and closing the lid on external power was to be ignored by logind. The first half went live. The second was only committed to the repo as `configs/systemd/logind.conf.d/50-no-suspend-on-external-power.conf`. `/etc/systemd/logind.conf.d/` never existed, and `shortcuts.md` §7 and the GSP row described a setting that was not there.

**State before the fix, 2026-10-12** (`busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager <prop>`):

| Property | Value | Meaning |
|---|---|---|
| `HandleLidSwitch` | `suspend` | the default |
| `HandleLidSwitchExternalPower` | *(empty)* | unset, so it falls back to `HandleLidSwitch` = suspend |
| `HandleLidSwitchDocked` | `ignore` | the default |
| `Docked` | `true` | logind counts the two TB4 monitors as "docked" |
| `OnExternalPower` | `true` | always, since the battery was removed |

**Why nobody noticed:** at the desk, closing the lid did nothing because logind saw the machine as docked. The exposure was a dock blink with the lid shut. logind keeps re-evaluating the lid action while the lid stays closed, and its docked test reads the DRM connector status. The Plugable TBT4-UD5 has twice dropped both DP tunnels for about 5 s with no host-side trigger, on 2026-10-07 at 22:14:46 and on 2026-10-12 at 20:22:59. Each time it was about a minute after boot, past logind's 30 s holdoff. With the lid closed, that blink reads as undocked on external power, which fell through to suspend: the crash path. No such suspend happened. The journal, retained from 2026-09-30, had no lid events at all before 2026-10-12.

### 15a. Apply

```bash
sudo install -Dm644 ~/code/cachyPool/configs/systemd/logind.conf.d/50-no-suspend-on-external-power.conf /etc/systemd/logind.conf.d/50-no-suspend-on-external-power.conf
sudo systemctl kill -s HUP systemd-logind
```

The HUP makes logind re-read its config in place: no restart, and the session keeps running. Do **not** `systemctl restart systemd-logind` from inside the graphical session.

### 15b. Verify — results 2026-10-12 ✅

```bash
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitchExternalPower   # → s "ignore"
journalctl -u systemd-logind -b | tail -3
```

| Check | Result |
|---|---|
| Applied | `install` at 21:15:02, HUP at 21:15:13. logind logged `Config file reloaded.` |
| Live file | identical to the repo mirror |
| `HandleLidSwitchExternalPower` | `ignore` |
| Real lid close | 21:16:17, dock attached, `read` profile. logind logged `Lid closed.` and nothing else. No suspend in the journal. Both TB4 monitors stayed on with DPMS on, and the session kept running |

**Resulting behaviour:**

| Situation | Lid close does |
|---|---|
| Docked, any power | nothing |
| External power, not docked | nothing (new) |
| Battery, not docked | suspend, locking first via hypridle's `before_sleep_cmd` |

With the battery removed, the machine is always on external power, so the lid never suspends it until the replacement pack is fitted.

**Not covered by logind:** hypridle still locks after 5 min idle and turns the outputs off after 10 min, lid open or closed. Input from an external keyboard or mouse resets both. For closed-lid use, stay in the `read` profile: in `desktop`, eDP-1 stays enabled behind the lid, holding workspaces 4–5, and the cursor can wander onto it.

### 15c. Revert

```bash
sudo rm /etc/systemd/logind.conf.d/50-no-suspend-on-external-power.conf
sudo systemctl kill -s HUP systemd-logind
```

### 15d. Docs updated 2026-10-12

- `ACTUAL-CONFIGURATION.md`: GSP row annotated, new §15 row, §16 repo layout gained `configs/systemd/logind.conf.d/`.
- `shortcuts.md` §7: lid-close line corrected. It used to say the lid "locks, then suspends", but nothing locks on lid close unless the machine actually suspends. Closed-lid tips added.
- `CLAUDE.md`: note that `configs/` also mirrors two system paths whose live copies must be checked.

---

## 16. Visual monitor layouts: Hyprmon as editor, `monitor-mode.sh` as applier — ✅ APPLIED 2026-10-15, `hyprmon-bin` installed + verified 2026-10-16

**Why:** the only way to rearrange screens was editing coordinate arithmetic in `monitor-mode.sh`, and there was no quick way into monitor settings. Omarchy's answer is *Setup > Monitors*, which opens its `monitors.lua` in an editor, plus a pointer to Hyprmon in its manual for drag-to-arrange. Adopting Hyprmon wholesale was rejected after reading hyprmon 0.0.17's source. `applyProfile` and the `S` key set transforms with a bare `hyprctl keyword monitor` (the 2026-08-04 stale-layout-box bug). They rewrite `monitor=` lines in `hyprland.conf`, where ours has none, so hyprmon would *append* port-bound lines after the `source` lines. They leave a never-pruned `.bak.<ts>`, write only the profile's monitors, and end with `hyprctl reload`. Hyprmon also has no hotplug auto-switching, and its profiles only know specific monitors. So it's a hybrid: Hyprmon edits, `monitor-mode.sh` applies.

**What changed** (repo and live, 2026-10-15):

| Piece | What it does |
|---|---|
| `monitor-mode.sh` → `apply_from_profile` | `~/.config/hyprmon/profiles/<mode>.json` wins when its monitors, matched by hyprmon's `hardware_id` (EDID `make/model[/serial]`), are **exactly** the connected set; otherwise `apply_<mode>` runs as before. Goes through `apply_monitor_tf`, so the rotation cycle and fingerprint handshake are intact |
| `configs/hyprmon/profiles/{desktop,read}.json` | Seeded from the existing hand-written geometry with hyprmon's JSON field names (`PxW`, `X`, `Transform`, `hardware_id`, …) |
| `scripts/hyprmon-edit.sh` | Runs hyprmon in a floating Kitty with `HYPRLAND_CONFIG=~/.local/state/hyprmon/scratch.conf` (nothing sources it) and a `hyprctl` shim first in `$PATH` that blocks `reload`. Re-applies the current mode on quit |
| `scripts/monitor-menu.sh` | `walker --dmenu` menu: the profiles that fit the connected set (same classification as `desired_mode()`; current marked `●`), *Edit layout (Hyprmon)*, *Show current layout* |
| `keybindings.conf` | `Super+Shift+M` → `monitor-menu.sh` |
| `windowrules.conf` | `class hyprmon-edit`: float, 1200×800, centred |
| `configs/applications/monitors.desktop` | "Monitors" Walker entry → `monitor-menu.sh` |
| `configs/applications/hyprmon.desktop` | Shadows the packaged entry (`Exec=uwsm app -- hyprmon`, which bypasses the wrapper) → `hyprmon-edit.sh` |
| `show-shortcuts.sh` | `Super+Shift+M` added; the stale Samsung "desktop" block replaced with the current Xiaomi geometry |

### 16a. Install Hyprmon (needs your sudo password) — ✅ done 2026-10-15 23:54

```bash
paru -S hyprmon-bin        # NOT 'hyprmon': on the AUR that name is an unrelated Rust project
```

PKGBUILD reviewed 2026-10-15: it downloads `hyprmon-linux-amd64.tar.gz` from the upstream v0.0.17 GitHub release with a pinned sha256, and installs `/usr/bin/hyprmon`, `/usr/share/applications/hyprmon.desktop` and an icon. Nothing runs at install time.

### 16b. Deploy (done 2026-10-15)

```bash
cd ~/code/cachyPool
cp configs/hypr/scripts/{monitor-mode,hyprmon-edit,monitor-menu,show-shortcuts}.sh ~/.config/hypr/scripts/
chmod +x ~/.config/hypr/scripts/{monitor-mode,hyprmon-edit,monitor-menu}.sh
install -Dm600 configs/hyprmon/profiles/read.json    ~/.config/hyprmon/profiles/read.json
install -Dm600 configs/hyprmon/profiles/desktop.json ~/.config/hyprmon/profiles/desktop.json
install -Dm644 configs/applications/monitors.desktop ~/.local/share/applications/monitors.desktop
install -Dm644 configs/applications/hyprmon.desktop  ~/.local/share/applications/hyprmon.desktop
cp configs/hypr/{windowrules,keybindings}.conf ~/.config/hypr/
hyprctl reload                                   # auto-reload missed the second file once
~/.config/hypr/scripts/monitor-mode.sh "$(cat $XDG_RUNTIME_DIR/hypr-monitor-mode)"   # reload reset the screens
```

⚠ Copying any sourced `.conf` triggers Hyprland's auto-reload, which **snaps the screens to the `monitors.conf` boot geometry** while `$STATE` still names the old profile. Always re-apply the profile afterwards.

### 16c. Verify — results 2026-10-15

| Check | Result |
|---|---|
| Dry run, stub `hyprctl` | `read`/`desktop` JSON emit the same specs as the hand-written code, with `transform,N` explicit. `trio`/`onescreen`/`laptop` have no JSON and use the code path. A JSON with a wrong serial, invalid JSON, or a missing monitor each fall back to the code path |
| `read` live | Xiaomi `0,0`, AQ16H `3072,0 t3`, eDP-1 off, `$FPFILE` fresh (it cycled). Test window on WS 7: `1260×1992` |
| `desktop` live | eDP-1 `0`, Xiaomi `2048`, AQ16H `5120`, all `t0`. Test window: `2028×1224`. Still `desktop` after 15 s, so the daemon held it |
| Back to `read` | Same as the first `read` row, user workspaces back in place, `swayosd` active |
| Keybind | `hyprctl binds` lists `mods=65 key=M → monitor-menu.sh` |
| Walker | `elephant query 'desktopapplications;monitors;5'` → "Monitors" (score 218); `…;hyprmon;5` → the override (subtext "Monitor layout editor") |
| systemd env | `HYPRLAND_INSTANCE_SIGNATURE` present, so the menu's `hyprctl` calls work when launched from Walker |

**After 16a — results 2026-10-16:**

| Check | Result |
|---|---|
| Package | `hyprmon-bin 0.0.17-1`, explicit, installed 2026-10-15 23:54. `hyprmon --version` → `v0.0.17 (commit: 3131caf)`. No new dependencies |
| Hyprmon reads the seeded JSON | `hyprmon --list-profiles` → `desktop`, `read *`; `--active-profile` → `read`. Its own `compareMonitorConfigurations` matched the live set, so the seed format is correct |
| Scripted editor session | The wrapper was driven through a pty: `P` → type `zzprobe` → Enter, then `S`, then `Q`. The script answers termenv's OSC 10/11 colour queries; unanswered, they swallowed the keystrokes |
| `P` | Wrote `zzprobe.json`, identical to `read.json` on every field `apply_from_profile` uses (`hardware_id`, `PxW`/`PxH`, `Scale`, `X`/`Y`, `Active`, `Transform`). Only the Hz decimals differ (`60` vs `60.00000`). The key sets are identical too. A dry run fed that file emitted exactly the seed's specs. Probe profile deleted afterwards |
| `S` | Wrote `monitor=eDP-1,disable` / `monitor=DP-1,…,0x0,1.25` / `monitor=DP-2,…,3072x0,1.25,transform,3` into `~/.local/state/hyprmon/scratch.conf`: port-bound lines, which is exactly what it would have appended to `hyprland.conf`. Geometry was **unchanged** while hyprmon was still open, so the shim blocked the `hyprctl reload` |
| Quit | Wrapper exit 0. `monitor-mode.sh read` re-ran (swayosd restarted), `scratch.conf.bak.*` removed, geometry unchanged |
| Killed instead of quit | `SIGTERM` to hyprmon → the `EXIT` trap still re-applied the profile. Bash defers the wrapper's own `TERM`/`HUP` trap until hyprmon exits, so a closed Kitty window is covered once hyprmon dies |
| Coordinates | hyprmon reads `X`/`Y` from `hyprctl monitors` and moves them in pixel steps of the same space. Its saved values equal the live logical positions, which are what `apply_from_profile` passes through. A real drag-and-save hasn't been done yet; the first one you make will show it |
| Keys in 0.0.17 | `G` grid, `L` (uppercase; lowercase `l` moves right) snapping, `R` scale picker, `C`/`D` advanced settings incl. rotation, `A` apply, `P` save profile, `S` save config, `O` hyprmon's profile menu (avoid), `Z` revert, `Q` quit. The profile-name box takes **one key per keystroke**, so typing works and pasting doesn't |
| Menu | The editor was first opened at 2026-10-15 23:55, when `~/.local/state/hyprmon/` was created. The Walker `--dmenu` path itself wasn't scripted; its parsing and filtering were tested with a stub `walker` |

### 16d. Usage rules

- Save layouts with **`P`** under the profile's name. **Never `S`**; it's harmless here, but it isn't the save key. Never `hyprmon --profile` either.
- Don't switch an **external** off inside Hyprmon: the auto-switcher treats it as an unplug.
- A profile applies only when exactly its monitors are connected. Anything else falls back to the hand-written layout.
- After editing a profile, pull it into the repo: `cp ~/.config/hyprmon/profiles/<mode>.json configs/hyprmon/profiles/`.

### 16e. Revert

```bash
rm ~/.config/hyprmon/profiles/*.json      # monitor-mode.sh falls straight back to the hand-written geometry
paru -Rns hyprmon-bin
rm ~/.local/share/applications/{hyprmon,monitors}.desktop
# then drop the Super+Shift+M bind and the hyprmon-edit windowrules, and re-copy the .conf files
```

### 16f. Docs updated 2026-10-15

- `ACTUAL-CONFIGURATION.md`: header, §5 `hyprmon-bin` row, §11 file list and profile bullets, §15 new row, §16 repo layout.
- `shortcuts.md`: Quick reference and §1.1 `Super+Shift+M`, §3 editing workflow, §11 `monitors.conf` row.
- `CLAUDE.md`: monitor section notes the profile JSONs and the "never `S` / `--profile`" rule.

---

## 17. Fan RPM and the platform profile: force `predator_v4` — ✅ APPLIED 2026-10-31 (reboot check pending)

**Why:** this laptop had no fan readings and no `/sys/firmware/acpi/platform_profile` at all. Not a missing package — the in-kernel `acer_wmi` (7.2.8) simply selects no quirk on this model.

The driver carries `module_param(predator_v4, bool, 0444)`, and `find_quirks()` does:

```c
if (predator_v4)
        quirks = &quirk_acer_predator_v4;   /* .hwmon = true, .platform_profile = true */
else if (!force_series)
        dmi_check_system(acer_quirks);
```

Its DMI quirk table lists only `Predator PHN16-71`, `PH16-71` and `PH18-71`. The **PT516-52s is absent**, so the DMI path finds nothing and the driver falls back to `quirk_unknown`. Forcing the parameter skips the DMI match entirely.

**What it gives, verified live on 2026-10-31 with a real unload/reload (confirmed in `dmesg`):**

| | |
|---|---|
| `/sys/firmware/acpi/platform_profile` | appears, with five states: `low-power quiet balanced balanced-performance performance` |
| `/sys/class/hwmon/hwmonN` (`name` = `acer`) | `fan1_input`, `fan2_input`, `temp1_input`, `temp3_input` (`temp2_input` is wired but always reads 0) |
| lm_sensors chip name | `acer-isa-0ace` |
| Load test | 0/0 RPM at 41 °C → 20 threads for 45 s → **2564/2307 RPM at 56 °C** → back to 2097/2027 |
| Survived the reload | `Acer WMI hotkeys` input device, the `acer-*` rfkill switches, and `health_mode` = 1 |

**0 RPM at idle is a real reading**, not a failure: this laptop stops both fans when it is cool.

**What it does NOT give:**

- **No fan control.** `quirk_acer_predator_v4` sets `.hwmon` but not `.pwm`, so the fans are readable and nothing more.
- **No keyboard RGB.** The in-tree `acer_wmi` never exposes `four_zoned_kb`. That needs an out-of-tree driver — the route, and why it is uncertain on this 3-zone keyboard, is in `triton-panel/README.md`.

### 17a. Install

The parameter is `0444`: settable only at module load, never writable through sysfs. So it has to be a modprobe drop-in.

```bash
sudo install -Dm644 ~/code/cachyPool/configs/modprobe.d/acer-wmi-predator-v4.conf \
     /etc/modprobe.d/acer-wmi-predator-v4.conf
sudo systemctl restart power-profiles-daemon
```

- **No initramfs rebuild.** `acer_wmi` appears in no mkinitcpio `MODULES` list; the only `MODULES+=` on this machine is the NVIDIA one in `/etc/mkinitcpio.conf.d/10-chwd.conf`.
- **The `power-profiles-daemon` restart is required, not optional.** ppd probes platform drivers once at startup. Until it is restarted it keeps reporting `PlatformDriver: placeholder`, and switching profiles moves the `intel_pstate` EPP and nothing thermal.

### 17b. Verify

```bash
cat /sys/module/acer_wmi/parameters/predator_v4   # Y
cat /sys/firmware/acpi/platform_profile           # must exist
cat /sys/firmware/acpi/platform_profile_choices   # 5 states
sensors acer-isa-0ace                             # fan1/fan2 + temp1/temp3
powerprofilesctl list                             # no "placeholder" left
```

⚠ **The parameter reads `Y` after a live reload too, so the only honest test is a reboot.** Run the five commands above after the next boot; if `predator_v4` reads `N`, the drop-in is not being picked up.

**Mapping ppd onto the five states.** ppd has only three targets, so `quiet` and `balanced-performance` are unreachable through it. Expected, to be confirmed after the restart:

```bash
powerprofilesctl set power-saver && cat /sys/firmware/acpi/platform_profile   # expect low-power
powerprofilesctl set balanced    && cat /sys/firmware/acpi/platform_profile   # expect balanced
powerprofilesctl set performance && cat /sys/firmware/acpi/platform_profile   # expect performance
```

To use the other two, write the file directly (`triton-panel` does this through its helper). Note that ppd **monitors** that sysfs file, so a direct write makes ppd relabel its own active profile — `quiet` reads back as `power-saver`, `balanced-performance` as `balanced`. That is ppd behaving correctly, not a conflict.

### 17c. Revert

```bash
sudo rm /etc/modprobe.d/acer-wmi-predator-v4.conf
sudo modprobe -r acer_wmi && sudo modprobe acer_wmi
sudo systemctl restart power-profiles-daemon
```

Everything the parameter adds disappears; hotkeys, rfkill and the battery cap are untouched, since the cap lives in the separate `acer_wmi_battery` module.

### 17d. Docs updated 2026-10-31

- `configs/modprobe.d/acer-wmi-predator-v4.conf`: new mirror of the live drop-in.
- `ACTUAL-CONFIGURATION.md`: header, §15 new row, §16 repo layout.
- `CLAUDE.md`: new hardware-constraints bullet.

---

## 18. `triton-panel` — a GUI for this machine's own hardware — ✅ APPLIED 2026-10-31 (sudoers rule pending)

**Why:** everything §14 and §17 unlocked was reachable only by `cat`-ing sysfs. No general-purpose tool covers it — `mission-center` shows no fans, `coolercontrol` is a fan *control* front end for hardware that has no PWM here, `psensor` graphs RPM but cannot touch the charge cap or the platform profile, and `powerprofilesctl` reaches three of the five states.

`triton-panel/` in this repo is a small GTK4/libadwaita app: temperature and fan graphs, CPU/memory/iGPU/dGPU, power source and dock, battery health, the five-state profile selector, the 80% cap as a switch, and a keyboard-backlight row. It is launched from Walker and depends on nothing that is not already installed (`gtk4`, `libadwaita`, `python-gobject`, `python-cairo` were all present).

### 18a. Install

```bash
cd ~/code/cachyPool/triton-panel
install -Dm755 triton-panel ~/.local/bin/triton-panel
install -Dm644 triton-panel.desktop ~/.local/share/applications/triton-panel.desktop

# the privileged helper -- MUST be root-owned, see 18b
sudo install -Dm755 -o root -g root triton-ctl /usr/local/bin/triton-ctl
sudo visudo -cf triton-panel.sudoers      # validate FIRST, always
sudo install -Dm440 -o root -g root triton-panel.sudoers /etc/sudoers.d/triton-panel

# float + centre the window
cp ~/code/cachyPool/configs/hypr/windowrules.conf ~/.config/hypr/windowrules.conf
hyprctl reload
```

⚠ Writing a sourced Hyprland `.conf` auto-reloads Hyprland, which snaps the screens back to `monitors.conf` geometry — re-apply the current monitor profile afterwards (`Super+M` or `monitor-mode.sh <mode>`).

### 18b. Privileges

The app runs entirely unprivileged; every number it shows is a world-readable sysfs file. Only three nodes are root-write (the charge cap, `platform_profile`, and the keyboard backlight), and those go through `triton-ctl`: no path arguments, no `eval`, every accepted value matched against a literal in a `case` statement.

**A NOPASSWD sudoers rule pointing at a file the invoking user can write *is* root.** `triton-ctl` therefore refuses to start unless root owns it — but install it correctly anyway, exactly as above.

**State as of 2026-10-31:** the app, the `.desktop` and `/usr/local/bin/triton-ctl` (root-owned, verified) are all installed. **Only the sudoers rule is outstanding** — do not reinstall the helper, just run its two lines. Until then the cap switch and the `quiet`/`balanced-performance` entries raise a toast; everything else works.

### 18c. Verify

```bash
triton-panel &                       # fans, temps and the profile selector must be populated
# Walker: Super+Space, type "triton"
```

If the fan and profile groups read "unavailable", §17 is not in effect. If the cap switch raises a toast about sudoers, the two `sudo` lines in 18a were skipped.

### 18d. Revert

```bash
rm ~/.local/bin/triton-panel ~/.local/share/applications/triton-panel.desktop
sudo rm /usr/local/bin/triton-ctl /etc/sudoers.d/triton-panel
```

Then drop the `dev.isalgado.TritonPanel` block from `windowrules.conf`.

### 18e. Docs updated 2026-10-31

- `triton-panel/README.md`: the full reference — install, privileges, design notes, troubleshooting, and the keyboard-backlight caveat.
- `README.md`: repo index gains `triton-panel/` and the note that it is the one directory holding source rather than docs or mirrors.
- `ACTUAL-CONFIGURATION.md`: §15 new row, §16 repo layout.
- `configs/applications/triton-panel.desktop`, `configs/hypr/windowrules.conf`: new mirror and new rule block.
- `triton-panel/waybar/`: optional Waybar modules showing the same data in the bar. **Not applied** — the live Waybar config is untouched; see that directory's README.

---

## 19. Automatic power saving by power source — ✅ APPLIED 2026-10-31

On battery the machine now drops the laptop panel to 60 Hz and switches the
platform profile to `power-saver`; on AC it restores 240 Hz and the profile that
was active before. Two actions only — no backlight, no hypridle changes, no
charge-cap changes, no dGPU parameters.

eDP-1 has exactly two modes (`2560x1600@240` and `2560x1600@60`, same resolution
and scale), so this costs nothing but smoothness and is the cheapest real saving
available here.

### 19a. Why the refresh rate needed a single owner first

`2560x1600@240` was hardcoded at **8 sites** in `monitor-mode.sh` plus a **9th**
path through `apply_from_profile`, which emits `.Hz` straight out of the hyprmon
JSON — and `configs/hyprmon/profiles/desktop.json` carries eDP-1 at `240.00301`
because it was saved while docked on AC. Anything setting the rate from outside
was therefore undone by the next profile apply, hotplug autoswitch or
`hyprctl reload`.

So the rate is now resolved in one place:

```bash
# monitor-mode.sh
edp_mode() { if power_auto && on_battery; then printf %s "$EDP_LO"; else printf %s "$EDP_HI"; fi; }
```

**Never reintroduce a `2560x1600@240` literal in that script.** `apply_from_profile`
overrides eDP-1's Hz with `--argjson edphz`; the externals keep their JSON rate.

`on_battery` is `grep -q Discharging /sys/class/power_supply/BAT1/status`, the
same test hypridle's suspend listener uses — not `ACAD/online`, which reads 1
when only the TB4 dock is feeding the machine, and `Not charging` (the 80% cap
holding on AC) must count as AC.

### 19b. The two policies are deliberately different

| | policy | why |
|---|---|---|
| **Rate** | reconciled every stable tick (idempotent) | no manual UI exists for it, so there is no user choice to override — and reconciling is what repairs a `hyprctl reload`, a `Super+M` switch or a hotplug autoswitch |
| **Profile** | changed only on a power-source **transition** | the profile *is* exposed in Triton Panel, so a `performance` chosen on battery must survive |

### 19c. Install

```bash
cd ~/code/cachyPool
cp configs/hypr/scripts/monitor-mode.sh      ~/.config/hypr/scripts/monitor-mode.sh
cp configs/hypr/scripts/power-autoswitch.sh  ~/.config/hypr/scripts/power-autoswitch.sh
chmod +x ~/.config/hypr/scripts/power-autoswitch.sh
cp configs/hypr/autostart.conf               ~/.config/hypr/autostart.conf   # adds the exec-once
install -Dm755 triton-panel/triton-panel     ~/.local/bin/triton-panel

# exec-once does NOT re-run on a reload, so start it once for this session:
~/.config/hypr/scripts/power-autoswitch.sh &
```

### 19d. Verify — results 2026-10-31

```bash
cat /run/user/1000/triton-power-mode     # source/auto/rate/saved_profile/pid/ts
hyprctl monitors -j | jq -r '.[] | select(.name=="eDP-1") | .refreshRate'
powerprofilesctl get
```

Checked on battery, all passing:

| check | result |
|---|---|
| daemon start on battery | rate 240 → **60**, profile `balanced` → **power-saver**, `saved_profile=balanced` |
| `monitor-mode.sh laptop` afterwards | stays **60** — the centralization proof; before this change it forced 240 |
| `hyprctl reload` (snaps to `monitors.conf` @240) | daemon restored **60** within one tick, unattended |
| panel switch → off | **240** restored, profile left on `power-saver` as designed |
| panel switch → on | back to **60**, and `saved_profile` still `balanced`, not `power-saver` |
| `edp-rate` while DPMS off | **no-op** — a modeset would wake the panel |
| `edp-rate` run twice | second run emits nothing (rate already matches) |

⚠ **The AC branch is still untested** — it needs the charger physically plugged
in. Expect 240 Hz and `balanced` restored, plus a "On AC" notification.

### 19e. Gotchas found while building this

* **Never signal the daemon with `pkill -f power-autoswitch.sh`.** `-f` matches
  whole command lines, so it also hits any shell, editor or pager whose argv
  merely mentions the script — during testing it killed the shell running the
  test. The daemon publishes `pid=` in its state file; signal that.
* **`edp-rate` must no-op when eDP-1 is absent from `hyprctl monitors -j`.**
  The `read` profile disables the laptop panel on purpose, and a
  `keyword monitor eDP-1,<mode>,…` against a disabled output does not set a
  rate — it *enables* the output, silently undoing `read` every few seconds.
* **Skip the modeset while `dpmsStatus` is false**, or reconciling under
  hypridle's 10-minute DPMS-off turns the screen back on by itself.

### 19f. Revert

```bash
rm ~/.config/hypr/scripts/power-autoswitch.sh
# drop the exec-once line from autostart.conf, then:
echo 0 > ~/.config/triton-panel/power-auto   # or just leave it: no daemon, no effect
~/.config/hypr/scripts/monitor-mode.sh edp-rate   # back to 240
```

`edp_mode()` itself is harmless with the daemon gone: with the pref at `0` it
always resolves to 240, exactly the old hardcoded behaviour.

### 19g. Docs updated 2026-10-31

`ACTUAL-CONFIGURATION.md` §10 (new daemon), §11 (new script + the rate-owner
rule), §15 (new row); `CLAUDE.md` (monitor section); `triton-panel/README.md`;
this section.

### 19h. `saved_profile` ratcheted to `power-saver` — fixed 2026-11-02

**Symptom.** The live state file read `saved_profile=power-saver`, where §19d
recorded `saved_profile=balanced` on 2026-10-31. Consequence: the AC branch
"restores" `power-saver`, so `balanced` on AC was effectively dead.

**Mechanism.** `power-profiles-daemon` persists its choice in
`/var/lib/power-profiles-daemon/state.ini` (`Profile=power-saver`). The daemon
forces `power-saver` on battery; ppd persists that; the next boot restores it;
and because `last_source=unknown` makes the **first stable read count as a
transition**, the daemon's first tick then captures that same `power-saver` as
"what I had before battery". Each boot re-persists it — a self-feeding loop.
§19d's `profile balanced → power-saver` at daemon start on battery is the proof
that ppd did *not* start in `power-saver` before the loop closed (the same
`battery_aware=true` was already set then, so battery-awareness is not the
cause). The capture is simply meaningless on a battery boot: there is no
pre-battery profile to capture.

**Second bug, same branch, found while fixing this one.** With nothing
captured, the AC side ran `set_profile "${saved_profile:-balanced}"` — so an
**AC boot forced `balanced`** and silently destroyed a hand-picked
`performance`. That contradicts §19b's "a manual choice must survive", and is
likely why §19d never managed to tick the AC branch off.

**The invariant (the whole fix).** *Never record `power-saver` as
`saved_profile`.* On battery it can only ever be this daemon's own doing, so it
says nothing about what the user wanted on AC. One guard covers both paths that
reach the branch without a real transition: the boot tick, and the Triton Panel
toggle flipped off→on while already on battery.

```bash
# battery side — capture only a profile that is not our own doing
[[ -n "$saved_profile" || "$(current_profile)" == power-saver ]] \
  || saved_profile="$(current_profile)"

# AC side — restore only what was actually captured
#   capture present      -> restore it exactly
#   none, and power-saver -> that is ours: hand it back to `balanced`
#   none, anything else   -> the user picked it: leave it alone
```

No new state flag. `configs/hypr/scripts/power-autoswitch.sh`, pushed live with
`cp` and the daemon restarted via the **published pid** from the state file
(never `pkill -f` — §19e).

**Verified live 2026-11-02 (battery side).**

| Check | Result |
|---|---|
| state file before → after | `saved_profile=power-saver` → `saved_profile=` |
| profile / platform profile | `power-saver` / `low-power`, unchanged |
| eDP-1 | still `@60.002`, unchanged |
| daemon instances | 1 (a second cmdline match was a transient bash fork for `sleep 5 &`, caught pre-`exec` — the same argv-matching trap as §19e) |
| `bash -n` | clean (an earlier draft used `local` outside a function, which would have aborted the loop) |
| logic harness | 10/10 — extracts the real branch text from the script and stubs `current_profile`/`set_profile` |

⚠ **The AC branch is still untested on hardware.** It needs the charger, and
this sequence closes §19d's open item as well:

1. plug in → expect profile `balanced` (nothing captured, and we were in `power-saver`)
2. unplug → expect `balanced` captured, profile → `power-saver`, rate → 60
3. plug in → expect `balanced` restored exactly, rate → 240

The harness lives at `tests/test-power-autoswitch.sh` — a new top-level
`tests/`, deliberately not under `configs/`, which mirrors live dotfiles and so
can never hold a test. It resolves the script relative to its own location, so
it runs from anywhere:

```bash
./tests/test-power-autoswitch.sh     # 10 passed, 0 failed
```

It `awk`s the branch out of the real script and stubs `current_profile` /
`set_profile`, so it exercises the shipped code, not a transcription — if the
branch is reindented or renamed the extraction returns empty and the test
fails loudly rather than passing against nothing.

---

## 20. Fingerprint: enrol and unlock from Triton Panel — ✅ WIRED 2026-10-31 · ✅ ENROLLED 2026-11-01

The machine has an **ELAN `04f3:0c4f`** reader. `fprintd 1.94.5` + `libfprint
1.94.100` were already installed and libfprint's in-tree **`elan`** driver binds
it: `fprintd-list` answers *"ElanTech Fingerprint Sensor"*, which is that
driver's `full_name` (`elanmoc` would say *"Elan MOC Sensors"* and `elanspi`
*"ElanTech Embedded Fingerprint Sensor"* — all three strings sit in
`libfprint-2.so.2`, so the reported name identifies the driver).

✅ **`right-index-finger` enrolled 2026-11-01** — 6 of 6 stages in ~54 s with
two rejections and **zero** protocol errors. It had failed for three sessions,
and **§20g's verdict that no gesture could fix it was wrong**: the cause was
the *instructions*, both of which the panel derived from bad inputs. See §20l
for the correction and what it means for reading a journal like this one.
§20a–§20f are correct and verified; §20g is kept as the record of the
misreading, annotated.

### 20a. What already existed

* **`sudo` was already wired.** CachyOS's `chwd` had put
  `auth sufficient pam_fprintd.so # chwd-fprintd` in `/etc/pam.d/sudo`. It
  starts working the moment a finger is enrolled; the panel reports its state
  but **never edits it** — that is the lockout-class file.
* **No PAM change is needed for the lock screen.** hyprlock 0.9.6 drives
  fprintd **over D-Bus itself** (`auth:fingerprint:*` config keys, strings
  `fprint: started verifying` in the binary). So unlocking by fingerprint
  carries none of the risk a `/etc/pam.d/hyprlock` edit would.
* **There is nothing else to unlock.** This machine boots via `getty@tty1`
  autologin with no display manager and no login prompt, so hyprlock
  (`Super+L`, and hypridle at 5 min) is the only gate.

### 20b. polkit, and why the panel can do this unprivileged

From `net.reactivated.fprint.device.policy` on this machine:

| action | `allow_active` | consequence |
|---|---|---|
| `…device.verify` | `yes` | listing enrolled fingers needs **no** prompt |
| `…device.enroll` | `auth_self_keep` | `Claim()` raises a polkit dialog for your **own** password |
| `…device.setusername` | `auth_admin_keep` | never used — the panel only ever touches the current user |

`/var/lib/fprint` is `drwx------ root root`, so enrolled prints **cannot** be
read from the filesystem as the user. Everything goes through D-Bus.

### 20c. The panel's Fingerprint group

Sensor (name · scan type · enroll stages), what is enrolled, a finger picker
with **Enroll**, **Delete all prints**, an **Unlock hyprlock with fingerprint**
switch, and a read-only `sudo` row.

Three rules it enforces:

1. **Claim → EnrollStart → EnrollStop → Release, on every path out**, including
   errors and closing the window mid-enrolment (`close-request`). A claim left
   behind means the next `Super+L` has no fingerprint until fprintd times it
   out.
2. **The switch refuses to enable with zero fingers enrolled**, which would
   otherwise give a lock screen asking for a finger it can never match.
   Deleting the last print also switches it back off.
3. **It refuses to touch `hyprlock.conf` if that file already has its own
   `auth` block**, rather than produce a config with two.

Not polled on the 2 s tick: enrolled prints change only when the panel changes
them, and a timed `ListEnrolledFingers` would race the `EnrollStatus` signals.

### 20d. The hyprlock block

`hyprlock.conf` is **not** in `hyprland.conf`'s `source` list, so writing it does
**not** trigger Hyprland's auto-reload (which would snap the monitors to the
`monitors.conf` boot geometry). hyprlock reads it at launch, so a change applies
at the next lock. The panel owns a marker-delimited block and writes it
atomically:

```
# >>> triton-panel: fingerprint unlock >>>
auth {
    fingerprint {
        enabled = true
        ready_message = (Touch finger to unlock)
        present_message = Scanning fingerprint
        retry_delay = 250
    }
}
# <<< triton-panel: fingerprint unlock <<<
```

⚠ **Corrected 2026-11-01.** The verb used to come from the device's reported
`scan-type`, which is **`swipe`** here — and that turned out to be *wrong*, so
the block said "Swipe finger to unlock" for a pad that cannot be swiped. It now
comes from `info["gesture"]`, the physical sensor type (§20j): `Touch` for an
area pad, `Swipe` only for a real strip. Never rebuild this from `scan-type`.

⚠ The panel writes the **live** file. `configs/hypr/hyprlock.conf` then differs
and must be pulled back into the repo by hand — the panel says so in a toast.

### 20e. Verify — results 2026-10-31

| check | result |
|---|---|
| reader detected | ElanTech Fingerprint Sensor · `swipe` · **6** enroll stages |
| `ListEnrolledFingers` with nothing enrolled | fprintd **raises** rather than returning `[]`; translated to "none", every other error reported as a real failure |
| group renders | all six rows; switch **insensitive** with "Enroll a finger first" |
| no claim leaked | after each panel run the device still answers — a leak would fail with "already claimed" |
| block write | enable → disable → enable is idempotent (exactly one marker block); disable removes it cleanly |
| hand-written `auth` block present | refused with "edit it by hand" |

⚠ Enrolment itself was untested at this date. It then failed repeatedly for
three sessions — see §20g for the diagnosis that turned out to be wrong, and
§20l for the enrolment that succeeded on 2026-11-01.

### 20f. The enrolment window — added 2026-11-01

Enrolling used to report through **one subtitle on a combo row**. That is how
every failed attempt across three sessions produced no usable account of why:
the only surviving evidence was fprintd's own journal, read the next morning. The
**Enroll** button now opens a dedicated window (`EnrollWindow`) that owns the
claim for its whole lifetime.

What it shows:

| element | what it is for |
|---|---|
| **contact strip** | the last 12 s of fprintd's `finger-present` property drawn as blocks, with every result marked on the same time axis — green accepted, amber gesture, red driver |
| **stage pills + `n / 6`** | advanced **only** by `enroll-stage-passed` |
| **status + hint** | the current result in words, with advice that escalates after the same reason repeats three times |
| **tally** | `11 attempts · 6x Too fast · 3x No usable detail` |
| **attempt log** | timestamped rows, **mirrored to stderr** so `journalctl --user` keeps them |
| **banner** | shown when the reader's USB id is a known driver/sensor mismatch |

Seven rules in the code worth keeping:

1. **Results are classified `gesture` / `driver` / `fatal`, and the UI says
   which.** This is the point of the window. Telling someone to "try again,
   slower" when the driver could not speak to the sensor is how they end up
   swiping forty times at a reader that was never going to answer. An
   *undocumented* result string is treated as `driver`, not as a gesture.
2. **No target speed is baked in.** The window measures the user's own contacts
   and labels the ones that passed (`last accepted 0.35s`). The right dwell for
   a given sensor is not something this panel could honestly claim to know.
3. **A rejected attempt does not advance the counter**, because it genuinely
   does not.
4. **`Claim` is async.** It raises a polkit prompt and blocks for as long as a
   human takes to type a password; synchronously it froze the window before it
   had painted a frame. `EnrollStart`/`EnrollStop`/`Release` stay synchronous.
5. **A result closes the open contact at that instant** rather than waiting for
   an off-transition — a result can arrive while the driver still reports the
   finger down.
6. **The result vocabulary comes from the interface spec**, not from memory.
   The first version was missing `enroll-too-fast`, `enroll-duplicate` and
   `enroll-unknown-error` and printed the raw D-Bus string;
   `enroll-unknown-error` is exactly what this machine produces.
7. **A `driver` terminal restarts the enrolment instead of ending the
   session** (added §20k). The fault ends fprintd's enrolment, not the claim,
   so `EnrollStop` + `EnrollStart` keeps going without a second polkit prompt.
   It must run **before** `_stop()`, which would disconnect `g-signal` and
   leave the window hung with nothing in the log. Two caps, and the UI says
   which one tripped.

Source of truth for the vocabulary:
`/usr/share/dbus-1/interfaces/net.reactivated.Fprint.Device.xml`.

**Verified 2026-11-01** by driving `_handle_result` with synthetic results —
the path a real finger had never reached:

| check | result |
|---|---|
| every `enroll-*` in the spec is mapped, and nothing invented | ✅ both directions |
| rejection does not advance the stage | ✅ `passed` stays 0 |
| `last accepted` is measured, not constant | ✅ 0.35 s from the simulated contact |
| advice escalates on the third identical reason | ✅ |
| result arrives while the finger is still down | ✅ contact closed at that instant |
| driver fault does not blame the gesture | ✅ retry **and** terminal branch |
| unknown result string | ✅ classified `driver` |
| happy path 6/6 → `enroll-completed` | ✅ |
| cairo draw with and without data | ✅ no exception |
| teardown | ✅ no timer and no signal handler left behind |

⚠ Not verified: the **visual layout** (the session was locked when the
screenshot was attempted) and live `g-properties-changed` delivery of
`finger-present`, which needs a real finger.

### 20g. Why enrolment fails on this machine — 2026-11-01

⚠ **Revised by §20j**, written later the same day: a second round of attempts
produced journal lines this section did not have, which narrow its "no gesture
changes that" claim and add the image-device state machine. Read both.

`journalctl -u fprintd` across every attempt so far:

```
Device reported an error during enroll: The driver encountered a protocol error with the device.
Failed to detect minutiae: No minutiae found
Device reported an error during identify for enroll: The driver encountered a protocol error with the device.
```

**Not one `too-short` or `too-fast` in the lot.** These are
`FP_DEVICE_ERROR_PROTO` — driver and sensor disagreeing about the protocol. No
gesture changes that. The panel's polkit → Claim → EnrollStart path is proven
healthy by the same journals: hyprpolkitagent opened its dialog, the enrolment
ran, and `journalctl --user` holds no Python traceback.

Upstream context: `04f3:0c4f` **is** listed in libfprint's supported-devices
table under `elan`, but field reports for this family are consistently negative,
and the sibling `04f3:0c4b` has the identical symptom documented — the in-tree
driver claims the id and then speaks an older protocol than the sensor
revision. linux-hardware.org records no working driver for `04f3:0c4f`.

**USB autosuspend is ruled out** (tested 2026-11-01). `usbcore.autosuspend=2`
is set and the reader reads `power/control=auto`, which looked like a candidate:
it is a USB 1.1 full-speed device, and a suspend/resume inside a driver command
sequence is a classic source of protocol errors. It is not the cause here,
because an open file descriptor pins the device awake:

```
$ cat /sys/bus/usb/devices/3-9/power/runtime_status      # suspended
$ exec 3< /dev/bus/usb/003/003 ; sleep 5
$ cat /sys/bus/usb/devices/3-9/power/runtime_status      # active
$ exec 3<&- ; sleep 4
$ cat /sys/bus/usb/devices/3-9/power/runtime_status      # suspended
```

libfprint holds the device open for the whole duration of a claim, so it cannot
autosuspend mid-enrolment. **Do not add a `power/control=on` udev rule for this**
— one was written and then deleted once this test came back. If the status ever
reads `suspended` *while* an enrolment is running, this conclusion is wrong and
worth revisiting.

That leaves one lead: **a TOD driver.** Elan ships a closed-source *Touch OEM
Driver* used through `libfprint-tod`; that is how `04f3:0c4b` was made to work.
As of 2026-11-01 **no confirmed `0c4f` support was found** in
`libfprint-2-tod1-elan` or any community fork, so this is a search, not a
recipe. After installing one, check the id list in
`/usr/lib/udev/rules.d/60-libfprint-2-tod1-elan.rules` before swiping anything.

~~Until one of those lands the honest status is: the reader is detected, fully
wired, and cannot enrol.~~ **Wrong — superseded by §20l.** The reader enrolled
on 2026-11-01 with no driver change at all, and no TOD was ever installed. This
paragraph is left standing because the reasoning that produced it is the thing
worth not repeating: see §20l.

### 20h. Revert

Turn the switch off (removes the block), then `fprintd-delete $USER`. To drop
fingerprint `sudo` as well, remove the `pam_fprintd` line chwd put in
`/etc/pam.d/sudo` — validate with care, that file is lockout-class.

### 20i. Docs updated

2026-10-31: `ACTUAL-CONFIGURATION.md` §15 new row; `CLAUDE.md`;
`triton-panel/README.md`; this section.

2026-11-01: §20f/§20g added; the `elanmoc` claim in the intro corrected to
`elan`; `ACTUAL-CONFIGURATION.md` §15 row changed from "never used" to "cannot
enrol". A `configs/udev/rules.d/` autosuspend rule was written and then deleted
when the test in §20g ruled the hypothesis out.

2026-11-01 (second pass): §20j added and §20g annotated as revised by it.
`triton-panel/triton-panel` gained `EnrollWindow._cycle_hint()` — the lift
instruction the state machine requires, which the window never gave — and then
`AREA_SENSORS` + `info["gesture"]`, after the sensor was checked against the
chassis and the driver's `scan-type = swipe` turned out to be wrong: all seven
instruction sites and `hyprlock_set()` now read `gesture`, and §20d's claim
that the verb comes from `scan-type` was corrected. New `triton-panel/fp-debug.sh`
(the debug harness; not installed anywhere, run from the checkout).

2026-11-01 (fourth pass): **§20l added — it enrolled.** `§20` heading
⛔→✅; `§20g`'s closing verdict struck through as superseded; `§20` intro,
`§20e` note and `§20j`'s "test that has never been run" annotated; `§20k`'s
"zero captures accepted" closed out. `CLAUDE.md`'s fingerprint bullet rewritten
(the old ⛔ rule actively blocked the fix); `ACTUAL-CONFIGURATION.md` §15 row
resolved; `triton-panel/README.md` headline rewritten. The enrolment window's
pre-emptive driver banner and `ELAN_PROTOCOL_MISMATCH` deleted.

2026-11-01 (third pass): §20k added — the first press-gesture run's numbers (8
captures, 0 accepted), what was really ending each session (`enroll-unknown-error`
with `done = True`, not the `enroll-retry-scan` it was reported as), and the
restart loop that keeps the claim so a driver fault no longer costs a polkit
password. New `triton-panel/test-enroll.py` (40 assertions). §20j read-out table
annotated. `ACTUAL-CONFIGURATION.md` §15 row extended.
`ACTUAL-CONFIGURATION.md` §15 fingerprint row and `CLAUDE.md`'s fingerprint
bullet updated; `triton-panel/README.md` enrolment section updated.

### 20j. The lift step, the reference clients, and the test still unrun — 2026-11-01 (second pass)

§20g was written from the **summary** lines in `journalctl -u fprintd`. A second
round of attempts the same morning produced lines that had not appeared before,
and they move the diagnosis in **both** directions. Read this after §20g.

#### The new journal lines, verbatim

```
Nov 01 09:44:35 fprintd[2504]: Device reported an error during enroll: The driver encountered a protocol error with the device.
Nov 01 09:44:55 fprintd[2504]: Internal state machine issue: transition from FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_ON to FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_OFF should not happen!
Nov 01 09:45:05 fprintd[2504]: Internal state machine issue: transition from FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_ON to FPI_IMAGE_DEVICE_STATE_AWAIT_FINGER_OFF should not happen!
Nov 01 09:45:08 fprintd[2504]: Device reported an error during enroll: The driver encountered a protocol error with the device.
Nov 01 09:45:50 fprintd[2504]: Failed to detect minutiae: No minutiae found
Nov 01 09:46:23 fprintd[2504]: Device reported an error during identify for enroll: The driver encountered a protocol error with the device.
```

#### What they add

**1. The reader runs on libfprint's image-device layer, and the driver is
driving it out of order.** The `FPI_IMAGE_DEVICE_STATE_*` names come from
`fpi-image-device.c`, so `elan` here is an *image* driver: it captures frames,
stitches them, and hands a picture to NBIS for minutiae extraction. That layer
has one fixed cycle, and libfprint's own reference manual lists the only valid
transitions:

| from | to | triggered by |
|---|---|---|
| `IDLE` | `AWAIT_FINGER_ON` | libfprint, when it wants a capture |
| `AWAIT_FINGER_ON` | `CAPTURE` | driver calls `fpi_image_device_report_finger_status()` — finger arrived |
| `CAPTURE` | `AWAIT_FINGER_OFF` | driver calls `fpi_image_device_image_captured()` |
| `AWAIT_FINGER_OFF` | `IDLE` | driver calls `fpi_image_device_report_finger_status()` — finger **gone** |

`AWAIT_FINGER_ON → AWAIT_FINGER_OFF` is **not in that table**, which is why
libfprint prints "should not happen". The `elan` driver told libfprint the
finger was gone while libfprint was still waiting for it to *arrive*. Nothing
above the D-Bus boundary can cause or fix this — but record it, because it is
the mechanism behind the complaint *"I cannot lift my finger and finish the
enrolment"*: the lift is a real, mandatory step in the protocol, and on this
machine the driver mishandles it.

**2. `No minutiae found` means an image really was captured.** That message is
NBIS failing on a picture it was given — so the capture path *does* complete
sometimes, and what fails afterwards is minutiae extraction on an image that is
too small or has no ridge detail. §20g's *"no gesture changes that"* stands for
the `PROTO` lines and is **too absolute as a blanket claim**. Both readings are
live until the debug run below separates them. Do not flip the other way
either: six of these attempts still died in the driver.

#### The lift/place cycle belongs to libfprint, not to any UI

This is the answer to "how should an enrol/detect interface work", and it is
the same answer in every client, because the interesting part is not in the
client at all:

* **The cycle is mandatory.** Per the table above, the next capture cannot
  start until the driver has reported the finger **gone**. A finger left
  resting on the sensor stalls the run with **no error message** — which is
  exactly what "it does not go on to the next stage" looks like.
* **No client can skip or hurry it.** `EnrollStart` is called **once** for the
  whole enrolment, not once per stage. The client then just listens to
  `EnrollStatus` and counts `enroll-stage-passed` up to `num-enroll-stages`
  (6 here). There is no per-stage method to call.
* **`finger-present` is advisory.** It is a property to *display*, never to
  drive the flow.

Reference clients, read 2026-11-01:

| client | reacts to | tells the user when to lift? |
|---|---|---|
| `fprintd-enroll` (fprintd's own CLI) | `EnrollStatus` only | via the status string only |
| `gnome-control-center` `cc-fingerprint-dialog.c` | `EnrollStatus` + `notify::finger-present` (for styling) + ScreenSaver `ActiveChanged` | yes — status strings, plus the fallback *"Repeatedly lift and place your finger on the reader to enroll your fingerprint"* |
| hyprlock 0.9.6 | fprintd `VerifyStatus` over D-Bus | verify only, no enrolment |

And fprintd's canonical wording, from `enroll_result_str_to_msg()` in
`fingerprint-strings.h` (the same table `pam_fprintd` ships — the strings are
in `/usr/lib/security/pam_fprintd.so` on this machine):

| result | press sensor | swipe sensor |
|---|---|---|
| `enroll-stage-passed`, `enroll-retry-scan` | **"Lift then touch again"** | **"Swipe your finger again"** |
| `enroll-remove-and-retry` | "Remove your finger, and try touching the sensor again" | "Remove your finger, and try swiping your finger again" |
| `enroll-too-fast` | "Finger scan was too fast, try again" | "Swipe was too fast, try again" |
| `enroll-finger-not-centered` | "Your finger was not centered, try touching the sensor again" | "Your finger was not centered, try swiping your finger again" |

Note what the **success** row says: upstream's reply to a *passed* stage is
"lift then touch again". The lift is the instruction, on every single stage.

#### What Triton Panel was missing — fixed 2026-11-01

The enrolment window said, on a passed stage:

> Same finger, same part of the pad, once more.

It never said to **lift**. That is the one instruction the state machine
actually requires, and this panel was the only client of the three above that
omitted it. Now a single `_cycle_hint()` on `EnrollWindow` produces it from the
device's `scan-type`, and it is used on `enroll-stage-passed`, on every
`gesture` retry, and in the "How this works" guide (whose swipe branch also
never mentioned lifting).

⚠ This is **not** the thing `CLAUDE.md` warns against ("don't fix it with UI
copy telling the user to swipe differently"). That warning is about blaming the
gesture for a driver fault, and it still holds: the gesture/driver/fatal
classification is untouched, and a `driver` result still says in so many words
that no gesture will help. Stating a **precondition of the protocol** is a
different thing from giving technique advice.

#### The remaining hypothesis: a press sensor driven as a swipe sensor

Upstream analysis of the sibling **`04f3:0903`** argues that the physical part
is a static **press/area** pad (a small capacitive square, ~96×96 or 144×64),
while `elan.c` classifies the family as `FP_SCAN_TYPE_SWIPE` and runs
multi-frame motion assembly (`fpi_assemble_frames`). A static press produces no
displacement between frames, assembly yields nothing usable, and extraction
ends in *"No minutiae found"*. The same write-up claims a timed-out command is
not followed by a clear-halt or endpoint reset, so later transfers fail with
protocol errors, and that the only recovery is a USB unbind/rebind plus an
`fprintd` restart.

How well it fits this machine: the `No minutiae found` line, the `PROTO` lines
*after* a timeout, and the out-of-order finger reporting are all consistent
with it. What does **not** carry over for free: that is `0903`, not `0c4f`, the
claims are the author's own with no upstream fix behind them, and our
`scan-type` reads `swipe` (that author's read `press`) — from the suspect
driver, so it proves nothing either way.

**Settled by eye the same day: it is an area pad.** The part in this chassis is
a ~1 cm square in the corner of the touchpad. There is nothing to slide a
finger *along*, so `scan-type = swipe` is not merely "unconfirmed" as §20g had
it — it is **wrong**, and the press-sensor reading now has this machine's
hardware behind it rather than an analogy to `0903`.

What that changed in the panel:

| before | after |
|---|---|
| every verb built from `info["scan_type"]` | built from `info["gesture"]`, the physical type — `AREA_SENSORS = {"04f3:0c4f"}` keys it by **USB id**, never by the driver's reported name |
| guide: *"Slide the finger across the sensor in one continuous motion"* | the press branch, prefixed by a line saying what the driver claims, that it is wrong, and why |
| `_cycle_hint()`: *"then swipe again"* | *"then touch it again"* |
| `ready_message = (Swipe finger to unlock)` | `(Touch finger to unlock)` — §20d corrected, it asserted the opposite |
| sensor row: `… · swipe` | `… · swipe → really press` |

`scan_type` is **kept and still displayed**: what the driver claims is evidence
about the driver. It is simply never used to build an instruction again. Note
nothing was enrolled and the hyprlock switch was off, so no block carrying the
wrong verb was ever on disk — neither live nor in `configs/hypr/hyprlock.conf`.

What is still open is **frame counts**, and that is what the run below is for.

#### The test that has never been run

⚠ **Superseded by §20l.** The panel went on to enrol successfully, which
answers *"panel or driver?"* without this run. `fp-debug.sh` is still the right
tool if the protocol errors ever bite on **verify** rather than enrol — keep it
for that.

Every failed attempt so far went through Triton Panel, so *"panel or driver?"*
is still formally open, and the journal has only ever shown summary lines.
Both gaps close in one run. The script lives in the repo at
**`triton-panel/fp-debug.sh`** (next to `triton-ctl`) — it is not installed
anywhere, run it from the checkout.

⚠ **Run it from a terminal inside the Hyprland session, not from a bare tty.**
`Claim()` goes through polkit and the agent here is `hyprpolkitagent`, started
by `autostart.conf` *inside* the session. On `Ctrl+Alt+F2` there is no agent and
`fprintd-enroll` dies on an authorization error that reads exactly like a driver
fault. The script refuses to run without `WAYLAND_DISPLAY`/`DISPLAY` for that
reason, and warns if the agent is not up. "Close the panel" means close its
window.

What it does: refuses to run while Triton Panel holds the claim (matched on the
installed path `.local/bin/triton-panel` — a bare `pgrep -f triton-panel` also
matches the shell that launched the script from the `triton-panel/` directory),
writes
`Environment=G_MESSAGES_DEBUG=all` as a drop-in **under `/run`** (so it cannot
survive a reboot and needs no revert — do **not** use `systemctl edit`, it
opens an editor), restarts `fprintd`, captures `journalctl -u fprintd -f` to a
file, runs the **reference** client `fprintd-enroll -f right-index-finger`, and
removes the drop-in on every exit path.

```bash
./fp-debug.sh press     # flat, hold ~2s, LIFT CLEAR, wait for the prompt
./fp-debug.sh swipe     # ROLL edge to edge without losing contact, then lift
./fp-debug.sh rebind    # recover a wedged reader; no enrolment
```

Run both, separately — the comparison is the point, and now that the pad is
known the two runs mean something specific: `press` is what the **hardware**
wants, and `swipe` (a *roll* across the pad, since there is nowhere to swipe
along) manufactures the inter-frame displacement the **driver** wants. How to
read the result:

| what the debug log shows | reading |
|---|---|
| frame counts climbing, `TOO_SHORT` / assembly retries before each failure | gesture-and-geometry shaped; the press-sensor hypothesis gains |
| `PROTO` immediately after a device command, no frames at all | driver shaped; §20g stands |
| `fprintd-enroll` gets **further** than the panel ever did | the panel is the suspect; re-open §20f |
| `fprintd-enroll` fails **identically** | the panel is exonerated; stop looking at it |
| `press` keeps giving `No minutiae found` but the **roll** produces frames or a passed stage | the swipe-driver-on-an-area-pad reading is confirmed; the fix is a driver (a TOD, or an `elanpress`-style fork), never a gesture |
| `calibrat` lines failing repeatedly | `elan_calibrate`'s strict delta threshold, a third candidate |

Note since §20k: the panel now **restarts the session itself** after a driver
terminal, so a session no longer ends on the first `PROTO`. If it does hand you
a "Try again" button, one of the two caps tripped and the hint says which — it
is never the panel giving up on `No usable detail`, which has never stopped
anything.

`rebind` exists because a `PROTO` error may leave the USB endpoint halted, in
which case **every later attempt in the same session is doomed regardless of
gesture** — worth clearing before each run. Note the counter-evidence already
in hand: the `No minutiae found` at 09:45:50 arrived *after* two `PROTO` errors,
so the wedge is not always permanent.

#### Minor, noticed in the same journal

`EnrollStop` and `Release` were each refused with *"Device was not claimed
before use"* at 09:46:27, after a real run — `_stop()` reached D-Bus twice.
Harmless (fprintd just declines), and "safe to call twice" is true panel-side.
Only worth fixing if `_stop` is touched for another reason.

### 20k. The press gesture captures, the session kept dying, and the restart loop — 2026-11-01 (third pass)

First run after §20j's copy fix, enrolling right index through the panel with
the **press** gesture. `journalctl -u fprintd`, 10:19:02 → 10:21:34, counted:

| events in one 85-second session | count |
|---|---|
| `Failed to detect minutiae: No minutiae found` | **8** |
| `Device reported an error during identify for enroll: … protocol error` | 4 |
| `Device reported an error during enroll: … protocol error` | 3 |
| `enroll-stage-passed` | **0** |

Two things in that table matter.

**The press gesture works, as far as capture goes.** Eight images were
assembled and handed to NBIS, against **one** in the whole morning of swipe
attempts (§20j). That is the area-pad reading confirming itself a second time,
by behaviour this time rather than by looking at the chassis.

**And not one capture passed.** Every image was rejected for having no usable
minutiae. libfprint wants roughly ten minutiae to accept a stage, and a ~1 cm
pad does not give many — this is the small-sensor limit upstream describes,
now reached on real data. So the blocker has moved: it is no longer "nothing
is captured", it is "what is captured is too thin to count".

#### What was actually ending the session

Reported as: *"when the status is 'No usable detail' it should not stop the
program, we should continue until the 6 needed measurements."*

`No usable detail` is this panel's title for **`enroll-retry-scan`**, which
fprintd sends with `done = False`. It never stopped anything — the handler's
`if not done:` branch logs it and returns, and the run continues. What ended
each session was the **next** line down the journal: `Device reported an error
during enroll` is fprintd's `enroll_cb` catching a non-retry `GError`, and it
emits **`enroll-unknown-error` with `done = True`** — terminal. Three of those
in 85 seconds, and the old code answered each one with `_stop(release=True)`:
`EnrollStop`, `Release`, button to "Try again". Because the **claim** went back
too, "Try again" meant a fresh `Claim()` and therefore **another polkit password
prompt**. That is what made it feel like the program stopping: it did stop, on
a driver fault, and restarting cost a password each time.

#### The restart loop

A driver fault ends fprintd's *enrollment*; it does not end the *claim*, which
the window owns for its whole lifetime. So the window now restarts the
enrolment itself — `EnrollStop` then `EnrollStart`, claim untouched, no polkit
prompt — and keeps the tally and attempt log accumulating across restarts.

Three things in `_restart_enrollment()` worth keeping:

1. **It must not go through `_stop()`.** `_stop` disconnects the `g-signal`
   handler, so restarting after it would leave the next `EnrollStatus` with
   nowhere to go: the window would look hung with *nothing in the log*, which
   is worse than stopping. The restart branch therefore runs **before**
   `_stop` in the terminal path and touches neither handler nor tick.
2. **The stage count genuinely goes back to zero, and the UI says so.**
   fprintd discards the partial enrolment when the operation fails, so the
   next `EnrollStart` really does start at 0. A quiet reset would read as a
   glitch, so the hint names it: *"fprintd discarded the 3 stages already
   captured, so the count is back to 0 of 6."*
3. **Two caps, for the two failure shapes in the journal**, and the UI says
   which one tripped — "the panel gave up" and "the panel decided your gesture
   was wrong" look identical from outside and only one of them is ever true:

| cap | what it catches | on tripping |
|---|---|---|
| `MAX_DRY_RESTARTS = 3` | the fault arriving back-to-back with **no finger contact** between restarts — a wedged USB endpoint, which a restart cannot clear | stops, and points at `./fp-debug.sh rebind` |
| `MAX_RESTARTS = 15` | a hard ceiling, so an unattended window cannot loop for an hour | stops, saying it is not the gesture |

Contact between faults (the shape actually seen: PROTO every 2–4 captures with
real presses in between) resets the dry counter, so a working session is never
cut short. `fatal` results — `enroll-duplicate`, `enroll-data-full`,
`enroll-failed` — are **not** auto-restarted; looping on a duplicate or full
storage is pointless.

#### What this does and does not buy

It removes the password prompts and lets a session keep producing data. At the
time of writing it had not made a capture *pass* — zero accepted out of eight.

✅ **Ten minutes later one did, and then all six did.** 10:30:27 → 10:31:21:
two `No minutiae found`, **no protocol errors at all**, six stages accepted,
finger enrolled. So the restart loop was not what closed it — the instructions
were — but the loop is what kept a session alive long enough to get there.
§20l.

#### Verified 2026-11-01 — `triton-panel/test-enroll.py`

40 assertions, run with `python3 -I test-enroll.py` from `triton-panel/`. It
stubs the widgets and the D-Bus proxy and drives `_handle_result` with
synthetic `EnrollStatus` events — the path a real finger reaches only by
accident. Kept in the repo this time; §20f's equivalent harness was thrown
away and had to be rebuilt.

| check | result |
|---|---|
| a retry credits no stage, counts an attempt, does not stop | ✅ |
| retry status reads `… — still going, 0 of 6` | ✅ (the reported confusion) |
| a terminal driver fault calls exactly `EnrollStop` + `EnrollStart` | ✅ |
| `_stop` not called, both handlers and the tick still alive | ✅ |
| no `Claim`, so no second password prompt | ✅ |
| the **next** status after a restart still lands and credits a stage | ✅ `passed == 1` |
| a restart that loses stages names how many | ✅ |
| dry cap trips at 3 and points at `rebind` | ✅ |
| contact between faults resets the dry counter — 6 restarts, never stopped | ✅ |
| hard ceiling stops without blaming the gesture | ✅ |
| `enroll-duplicate` / `-data-full` / `-failed` not restarted | ✅ |
| a failing `EnrollStart` on restart releases and degrades cleanly | ✅ |
| success path still completes and releases | ✅ |
| tally shows restarts, singular and plural | ✅ |

⚠ Still not verified: the visual layout, and live `g-properties-changed`
delivery of `finger-present` (needs a real finger — the contact strip's data
source).

### 20l. ✅ It enrolled — and why §20g was wrong — 2026-11-01

```
$ fprintd-list isalgado
Fingerprints for user isalgado on ElanTech Fingerprint Sensor (swipe):
 - #0: right-index-finger
```

(`(swipe)` there is the **driver's claim**, not the hardware — §20j. The pad is
a press sensor and `fprintd-list` has no way to know better.)

The run, from `journalctl -u fprintd`, 10:30:27 → 10:31:21 (~54 s):

| events | count |
|---|---|
| `Failed to detect minutiae: No minutiae found` | 2 |
| `Device reported an error during enroll: … protocol error` | **0** |
| stages accepted | **6 of 6** |

No driver was changed. No TOD was installed. `libfprint 1.94.100` and the
in-tree `elan` driver are exactly what §20g declared incapable.

#### What changed, and what cannot be credited

Two instruction fixes went in earlier the same day:

1. **The gesture verb.** The driver declares `scan-type = swipe`; the part is a
   ~1 cm square pad. The window had been telling the user to *slide a finger
   across* a sensor that cannot be slid across. Fixed by `AREA_SENSORS` →
   `info["gesture"]` (§20j).
2. **The lift between stages.** libfprint's image-device cycle will not begin
   the next capture until the driver reports the finger **gone**, and the
   window never said so — it said *"Same finger, same part of the pad, once
   more."* Fixed by `_cycle_hint()` (§20j).

⚠ **Both were already in place for the 10:19 run that got 0 out of 8**
(§20k). The 6/6 run at 10:30 was the *same binary*, plus §20k's restart loop —
which never fired, because that run had **no protocol errors at all**. So the
code cannot be credited with the 6/6: what differed between 0/8 and 6/6 is
**not recorded**. Candidates, none distinguishable from here: the user's own
coverage and dwell converging, finger condition, or the device's state after
that morning's fifth `fprintd` restart. The corrected instructions are
necessary — the old ones asked for an impossible motion — but they have not
been shown sufficient.

**The reproducibility test is enrolling a second finger.** If that also reaches
6/6, the instructions were the fix. If it takes another twenty attempts, the
remaining variable is the pad's minutiae yield and the honest status is
"enrols, unreliably".

The §20k restart loop earns its place regardless: before it, every protocol
error ended the run and cost another polkit password, which is what made the
earlier sessions unworkable.

#### The inference that cost three sessions

§20g argued:

> **Not one `too-short` or `too-fast` in the lot.** These are
> `FP_DEVICE_ERROR_PROTO` — driver and sensor disagreeing about the protocol.
> No gesture changes that.

The premise was true and the conclusion did not follow. On an **area pad driven
as a swipe sensor**, a gesture failure does not surface as `too-short` or
`too-fast` — those come from a driver that is tracking a swipe it can measure.
It surfaces as frames with no displacement, nothing to assemble, and
**`No minutiae found` → `enroll-retry-scan`**. That line was in the journal the
whole time, in §20g's own quoted output, filed under the driver story.

Worse, the conclusion was promoted to a rule. `CLAUDE.md` carried *"This is not
a technique problem, so don't 'fix' it with UI copy telling the user to swipe
differently"* — which is precisely the fix, and the instruction file blocked it
for three sessions.

#### Three rules that generalise

1. **A driver-reported property is evidence about the driver, not about the
   hardware.** `scan-type` came from the same code that could not drive the
   sensor. Check the chassis.
2. **`No minutiae found` is a geometry result.** Image captured, too little
   ridge detail to use. Sensor size, coverage and motion reach it; it is not a
   verdict about the bus.
3. **`FP_DEVICE_ERROR_PROTO` here is intermittent, not blocking.** It still
   appears. The successful run had none of it. "Appears in the journal" and
   "prevents the operation" are different claims and §20g merged them.

The gesture/driver/fatal classification in `_handle_result` was **right** and
stays. What was wrong were two of its inputs.

#### Downstream, now that a finger exists

* **`pam_fprintd` in `/etc/pam.d/sudo` is live.** `chwd` put
  `auth sufficient pam_fprintd.so` there long ago (§20a) and it starts working
  the moment a print exists — which was 10:31. ⚠ Its prompt is built from the
  driver's `scan-type`, not from the panel's `gesture`, so `sudo` now says
  *"Swipe your right index finger across ElanTech Fingerprint Sensor"*. **Touch
  the pad.** It is `sufficient`, so pressing Enter falls through to the
  password and there is no lockout path. The panel still never edits that file.
* **The hyprlock switch was enabled 2026-11-01 10:31:40**, right after the
  enrolment, and the live `hyprlock.conf` now carries the managed block with
  `ready_message = (Touch finger to unlock)` — the corrected verb. As §20d
  warns, that write lands on the **live** file only, so
  `configs/hypr/hyprlock.conf` had drifted; it was pulled back into the mirror
  the same day. ⚠ Matching itself is **unmeasured**: a protocol error during
  *verify* is a real possibility and no `fprintd-verify` has been run. hyprlock
  keeps password auth on regardless, so there is no lockout path either way.

#### Still true from §20g / §20j

USB autosuspend remains ruled out (don't add the udev rule). The invalid
`AWAIT_FINGER_ON → AWAIT_FINGER_OFF` transition is still a real `elan` bug.
`fp-debug.sh` is still the right harness if the protocol errors ever bite on
verify.

#### Panel change

The enrolment window's pre-emptive banner — *"Known driver problem on
04f3:0c4f … Enrollment may fail with a driver fault no gesture can fix"* — was
**removed**, along with the `ELAN_PROTOCOL_MISMATCH` set that fed it. It stated
as fact the thing this section disproves, and it told the user nothing they
could act on. Per-result reporting in `_handle_result` already says whose
problem each attempt was.

### 20m. Verify measured for the first time — it fails 4/4 — 2026-11-01 (fifth pass)

§20l closed with matching **unmeasured** and `fprintd-verify` unrun. It was run
four times, 11:22–11:30:

| run | result | journal during the run |
|---|---|---|
| 1 | `verify-no-match (done)` | — |
| 2 | `verify-retry-scan` → `verify-disconnected (done)` | `Device reported an error during verify: … protocol error` |
| 3 | `verify-no-match (done)` | `Failed to detect minutiae: No minutiae found` ×1 |
| 4 | `verify-retry-scan` → `verify-disconnected (done)` | `No minutiae found` ×4, protocol error ×3 |

**Zero matches.** The enrolled `right-index-finger` template never matched the
finger it was enrolled from. Four findings, each with its evidence:

1. **`verify-disconnected` is not a disconnect.** The sensor enumerated **once**
   this boot, `usb 3-9` at 11:21:50, and there is **no** disconnect, re-enumerate,
   reset or `xhci` error afterwards — including across the 11:22:25→11:22:34
   s2idle. Every `verify-disconnected` has a matching `FP_DEVICE_ERROR_PROTO`
   line at the same second. fprintd translates a protocol error during *verify*
   into `verify-disconnected` and ends the session. So this is CLAUDE.md rule (3)
   — intermittent, not blocking — surfacing under a name that invites the wrong
   fix. ⚠ **Do not chase USB power management for this.** Autosuspend was already
   ruled out in §20g and the device never left the bus.

2. **⚠ The error asymmetry between enrol and verify is the thing that makes the
   feature unreliable.** At enrolment §20k's restart loop absorbs a protocol
   error (`EnrollStop` + `EnrollStart`, claim kept). At verify there is no such
   loop: hyprlock maps an unrecognised error to **"Fingerprint auth disabled
   (unknown error)"** and stops offering the fingerprint for the rest of that
   lock. **2 of 4 runs** hit it. Even once matching works, roughly every other
   lock would fall back to the password.

3. **`No minutiae found` dominates, and it is still a capture result.** Rule (2)
   again: geometry, not a driver verdict. Verify is **strictly harder than
   enrol** — enrolment stitches 6 accepted captures into the template, verify
   gets **one** capture per touch with no stitching — so the placement that
   passed 6/6 at 10:30 is not sufficient here. This is the small-sensor limit of
   §20k (~1 cm pad) showing up on the read side.

4. **No driver swap is available — the door is closed.** `elanmoc`
   (match-on-chip, which would move matching into the sensor and remove the
   minutiae problem entirely) **is** present in `libfprint 1.94.100`, but
   `04f3:0c4f` is in the **`elan`** image-driver id table, and the live device
   reports `has_storage = False` → host-side NBIS matching. Confirmed by probe,
   not inferred.

#### The stage count: 6 is right, 5 was a bad read

A probe via `FPrint.Context().enumerate()` returned `get_nr_enroll_stages() = 5`,
against the **6** recorded in §20e and the 6/6 of §20l. fprintd's own D-Bus
property is authoritative and says **6**:

```
gdbus call --system --dest net.reactivated.Fprint \
  --object-path /net/reactivated/Fprint/Device/0 \
  --method org.freedesktop.DBus.Properties.GetAll net.reactivated.Fprint.Device
# → {'num-enroll-stages': <6>, 'scan-type': <'swipe'>, …}
```

The 5 came from reading the property on a device that was only **enumerated,
never opened** — libfprint's image-device base class finalises the stage count at
open. **Don't "correct" the 6.** This is CLAUDE.md rule (1) in a new costume: a
property read in the wrong device state is evidence about the read, not about the
hardware. The panel is safe here — it reads `num-enroll-stages` over D-Bus from
fprintd, which opens the device.

#### Next step: a second finger, additively

The reproducibility test CLAUDE.md already asks for is now also the fix to try,
and it costs nothing to attempt:

```bash
fprintd-enroll -f left-index-finger     # or the panel's Fingerprint group
fprintd-verify                          # no -f → verifies against ANY enrolled finger
```

⚠ **Do not delete `right-index-finger` to do this.** It is the artifact of three
failed sessions, enrolling is additive, and `fprintd-verify` with no `-f` tries
every enrolled template — so a second finger puts two templates in play while
losing nothing. Only if the new finger verifies reliably **and** the old one
never does is re-enrolling the old one worth the risk, and that is the user's
call, not an automated step.

Technique, which verify demands more of than enrolment did: the **same** region
of the pad each time, flat, centred, held still until the message changes, lifted
fully between attempts. Touch — never swipe (§20j).

If the protocol errors are what persists after a second finger, the harness is
`triton-panel/fp-debug.sh`, kept for exactly this case since §20l.

### 20n. The question §20m could not answer, and the `verify` mode — 2026-11-01

§20m's recommendation — *enrol a second finger* — was challenged on the obvious
grounds: **the correct finger was already being used.** That objection is right,
and the recommendation was mis-framed. Enrolling a *different* finger is a
**control experiment**, not a fix: it cannot improve matching for the finger you
actually want to unlock with. §20m presented it as the next step without saying
so.

What §20m actually established is that two causes remain indistinguishable from
the summary journal:

| | hypothesis | its fix |
|---|---|---|
| **H1** | the stored template is marginal — 6 accepted captures with 2 rejections, on a ~1 cm pad | re-enrol (**destructive**) |
| **H2** | the *verify* captures are too thin — one capture per touch, no stitching, under the NBIS floor | none exists |

The asymmetry matters: H1's fix destroys the artifact of three sessions, and
H2's fix does not exist. **So neither may be acted on before measuring**, and
the only thing that separates them is the per-capture debug output.

#### `fp-debug.sh verify`

`fp-debug.sh` already did all the setup — the `G_MESSAGES_DEBUG=all` drop-in
under `/run`, the journal capture, the tty/polkit-agent guard, the
"panel must not hold the claim" guard, and a cleanup that removes the drop-in on
every exit path. It was **enrol-only**. It gained a `verify` mode that reuses all
of it and runs `fprintd-verify` instead. It enrols nothing, deletes nothing and
writes nothing, so it is safe to re-run freely. The read-out table is in the
script's own banner: a minutiae **count** well under the template's → H2;
healthy counts with `verify-no-match` → H1; protocol errors and little else →
neither, run `rebind` first.

⚠ If the `elan` driver prints no per-capture count, **record that** instead of
inferring one — the script's summary says so explicitly. This is the §20g
failure mode: an absent log line is not a measurement.

#### `sudo` now stalls on the reader — handled, not worked around

`pam_fprintd` in `/etc/pam.d/sudo` went live the moment a print existed (§20l),
so **every `sudo` now waits on the reader first**, prompting *"Swipe your right
index finger"* — the prompt is built from the driver's `scan-type`, so it names
a gesture the pad cannot perform — and blocking ~30 s before falling through to
the password. This was hit for real while inspecting `/var/lib/fprint`: the
command returned `Verification timed out`. `fp-debug.sh` makes six `sudo` calls,
so it now runs **one `sudo -v` up front** to cache the ticket, which also keeps
PAM from competing with the run for the device claim. `pam_fprintd` is
`sufficient`, so Enter falls through to the password. **Don't edit PAM for
this.**

#### The non-destructive fresh template: same finger, second slot

The finger *name* is only a **label**. fprintd accepts a fixed enum of slot
names (confirmed against `/usr/lib/fprintd`), and **nothing ties
`left-index-finger` to a physically left index finger.** So a fresh template of
the **correct** finger can be enrolled into a second slot:

```bash
fprintd-enroll -f left-index-finger    # enrolled with the RIGHT index
fprintd-verify                         # no -f -> tries EVERY enrolled template
```

That is what answers H1 without touching `right-index-finger` — and it is the
reproducibility test §20l asked for, finally pointed at something useful.
⚠ **Still do not delete `right-index-finger`.** Only if the debug run shows
healthy captures *and* a fresh template matches is the old one the proven
culprit, and removing it is the user's call at that point.

#### Status

Both steps are **unrun** — each needs a finger at the sensor. Order: measure
(`./fp-debug.sh verify`) before enrolling anything, because the measurement
decides whether the second step is worth the time at all.

---

### 20o. Measure matching before touching the print: the calibration phase — ✅ APPLIED 2026-11-01 (sixth pass)

§20n left two steps, both needing a finger at the sensor, and §20m's
recommendation had been mis-framed. The shape that came out of that: **the
panel should not treat "enrolled" as the goal.** A 6/6 enrolment whose template
matches nothing is exactly what happened on 2026-11-01, and *every number the
enrolment window showed read as success* — because they were all enrolment
signals, and enrolment passing says almost nothing about matching.

So `EnrollWindow` gained a **calibration phase** that runs first.

#### What it does

`VerifyStart("any")` in a loop, classifying each attempt by the one
distinction that matters:

| bucket | results | what it means |
|---|---|---|
| **scored** | `verify-match`, `verify-no-match` | the sensor produced an image **and** libfprint extracted minutiae, so the matcher ran and returned a number |
| **rejected** | `verify-retry-scan`, `-swipe-too-short`, `-too-fast`, `-finger-not-centered`, `-remove-and-retry` | the capture never reached the matcher |
| **driver** | `verify-disconnected`, `verify-unknown-error` | the device faulted; says nothing about the hand |

Why that split is the useful one: **a high scored rate with `no-match` every
time is evidence about the template (H1), not about the placement** — the hand
is delivering readable ridges and the stored print is what cannot be matched.
That is the one case where re-enrolling is worth doing. A low scored rate is
placement or the small-sensor ceiling (H2), and re-enrolling from captures that
thin would just build another unmatchable template. The window says so in as
many words, and in that state it labels the button **"Enroll anyway"** rather
than recommending it.

Driver faults are deliberately **kept out of the rolling window**. Counting
them would drag the score down for something the user cannot act on — the same
conflation of "driver" with "gesture" that sent §20g chasing the wrong thing
for three sessions.

#### The gate

At least **10** attempts, and at least **8 of the last 10** scored. A *rolling*
window, not a cumulative total, so the score reflects the placement the user
has converged on instead of being dragged down forever by the fumbling at the
start — finding a repeatable placement and then enrolling from it is the whole
point. ~~Then the enrol phase opens with *"use the SAME placement that passed
calibration on every stage"*, because a template stitched from six different
parts of the finger is precisely what one verify capture cannot match.~~

⚠ **That sentence was wrong — corrected the same day in §20q.** An enrolled
NBIS print is a `GPtrArray` of per-stage minutiae sets and `fpi_print_bz3_match`
succeeds on the **first** stored set to clear the threshold: one-of-N, not a
composite. Six identical placements therefore waste five of the six slots, and
six *different* regions are what make the template matchable. The error was
conflating the `elan` driver's frame stitching **within** a capture (§20j) with
how libfprint stores stages **across** an enrolment. The enrol phase now names
a different region after every stage. Kept here rather than deleted, because
the reasoning that produced it is the thing not to repeat.

**Not configurable.** A knob here would invite tuning the threshold until it
passes, which is the one thing that would make the measurement worthless.

#### ⚠ What "scored" is NOT

It is an **inference** about libfprint's flow — extraction fails → retry;
extraction succeeds → bozorth3 → match/no-match. It is consistent with the
2026-11-01 journal (one `No minutiae found` followed by a `verify-no-match` in
the same run) but it is **not** confirmed against a per-capture minutiae count;
`./fp-debug.sh verify` is the only thing that would print one. So the UI says
**"scored", never "good"**, and the card states what the number is and is not
evidence of. If a debug run ever contradicts it, the claim is already labelled
as the inference it is and nothing has to be retracted. This is §20g in
miniature: **a missing log line is not a measurement.**

#### Safety properties

* **Calibration writes nothing.** Verify neither enrols nor deletes, so it is
  safe to repeat indefinitely. The card says this.
* **The occupied-slot warning.** Enrolling into a slot that already holds a
  print **overwrites** it. The window now says so up front when the chosen
  finger is already enrolled, and points out that *the slot name is only a
  label* — so a free slot can hold the same physical finger, which is the
  non-destructive way to build a fresh template (§20n). The panel still never
  deletes anything on its own.
* **The verify loop honours fprintd's state machine.** `VerifyStop` is required
  before the next `VerifyStart` once a `VerifyStatus` has arrived with
  `done = True` — and **both** `verify-match` and `verify-no-match` are
  `done = True`. A retry is `done = False`, leaves the verify **open** with
  fprintd already waiting, and must **not** be cycled or the operation is
  thrown away mid-flight. That asymmetry is invisible from the UI and is
  exactly what a later edit breaks silently, so it is the first thing the
  regression test asserts.
* **No restart ceiling, but no spin either.** A calibration run is a deliberate
  loop the user ends, so it has no cap — except `MAX_CAL_DRY = 4` consecutive
  driver faults *with no finger contact between them*, which is a wedged
  endpoint rather than a placement problem and points at `fp-debug.sh rebind`.
* **`VerifyFingerSelected` is not an outcome.** fprintd emits it before the
  result to name the template it is about to score against; it is logged as an
  info row and never counted as an attempt.
* **One claim path.** Both phases claim identically, so the
  close-while-polkit-is-still-up release invariant is implemented once.
  `_stop()` now stops the operation the claim was actually being used for
  (`VerifyStop` vs `EnrollStop`) before releasing.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **81 assertions, ALL PASS** (was 40) |
| the loop invariant | `done=False` → no D-Bus call; `done=True` → exactly `["VerifyStop", "VerifyStart"]` |
| `no-match` bucketing | counts as **scored**, marked in blue, `cal_matched` stays 0 |
| driver fault bucketing | kept out of `cal_log`, still counted as an attempt, loop continues |
| dry-fault cap | stops at 4 and names `rebind`; contact between faults resets it |
| gate, rolling | `[True]*8` → not ready (under the floor); `[True]*8+[False]*2` → ready; `[False]*20+[True]*10` → ready |
| widget construction | smoke-tested for both an occupied and a free slot |
| deployed | `install -Dm755 triton-panel/triton-panel ~/.local/bin/triton-panel` |

⚠ **A real sensor session is still unrun** — it needs a finger, so it is the
user's to do. Nothing above measures the hardware; it measures the panel.

⚠ **And one of the properties above is asserted, not observed.** The
`VerifyStop` → `VerifyStart` cycle on a **held claim** is checked against a
stub in `test-enroll.py`; that fprintd *accepts* it on a verify has **not**
been seen. The only evidence that a Stop/Start on a held claim works at all is
§20k's enrol restart loop (`EnrollStop` + `EnrollStart`), and that was
*enrolment*. The four `fprintd-verify` runs of §20m each did exactly one
`VerifyStart` → terminal result → exit, so the loop itself has never touched
the daemon. The first real-finger calibration run is what closes that gap —
if the cycle is refused, the symptom will be a `VerifyStart failed` row
pointing at `fp-debug.sh rebind`, and the fix is to re-`Claim` per attempt
rather than keep the claim.

#### A bug the smoke test caught

`_calibration_card()` called `_update_cal()`, which paints the buttons — but
the cards are built **before** the bottom bar, so `start_button` did not exist
yet and construction crashed. The initial paint moved to the end of `_build()`,
and `_update_cal()` now reads both buttons through `getattr` so a future
reorder degrades instead of crashing. Worth recording because it was invisible
to `test-enroll.py`: the stubs hand it buttons that always exist, which is
precisely the thing the real constructor does not.

#### ⚠ Second defect, same day: it was measuring the panel's own loop

See §20r. Until that fix, every `done = True` re-armed the verify immediately,
so a finger left **resting** on the pad was re-captured every 1–3 s and each
garbage image appended another reject to the rolling window. The gate then
reported "Captures are too thin" about a placement the user had made **once**.
This section's claim that calibration measures *placement* was false whenever
the finger stayed down. The verify is now re-armed on the **lift**.

#### Defect in this section's own work, fixed same day: the Stages card went inert

Reported immediately: *"Stages ya no hace nada."* Correct, and it was caused by
adding the calibration card **without deciding who owned the shared status
labels**. `status_label`, `hint_label` and `tally_label` had always lived inside
the card titled **Stages**, where they read as part of it — but they were being
used as the window's *global* status surface. A second phase exposed that:

| symptom | cause |
|---|---|
| stage pills and count frozen at `0 / 6` through a whole calibration | correct — calibration captures no stages — but nothing *said* so, so the card read as broken |
| a calibration retry message (*"the capture had no readable ridges…"*) rendering under a heading about enrolment stages | `hint_label` was shared but visually owned by the Stages card |
| the attempts tally empty during calibration | `tally_label` renders `self.tally`, the **enrolment** tally; `cal_tally` was collected from the first version and **rendered nowhere** |
| the idle hint saying *"Press Start"* | there is no Start button any more — calibration split it into *Calibrate placement* and *Enroll* |

Fixed by separating the surfaces:

* **`_status_box()`** — `status_label` + `hint_label` moved out into the
  window's own headline, above the contact strip, owned by whichever phase is
  running. No longer inside any card.
* **`stages_note`** — a new line in the Stages card that says why the pills are
  not moving: *"Not in use — calibration measures matching and captures no
  stages"* while calibrating, *"One pill per accepted capture"* while idle, and
  **nothing** while enrolling or once stages have real history. The card was
  deliberately **not hidden**: a card that appears and vanishes makes the window
  jump, and it jumps precisely when the user is looking at their hand.
* **`cal_tally_label`** — the calibration card renders `cal_tally` at last:
  `4 attempts · 3x Scored, did not match · 1x No usable detail`.
* **`_set_idle_text`** now names the buttons that exist.
* `count_label` shows `— / 6` rather than `0 / 6` when no enrolment is running,
  so a dash means "not applicable" and a zero means "started, none accepted".

`_build` order matters and is commented: the status box and cards are built
first, then the buttons, then `_update_cal()` (needs the buttons) and
`_set_idle_text()` (needs `stages_note`). This is the third instance of the same
class of bug — a paint method running before the widgets it paints exist — and
the first two were caught only by a real construction smoke test, never by the
stubs.

Verification: `test-enroll.py` **115 assertions, all passing**, including a
direct regression for what was reported — *the calibration tally is rendered,
not just collected* — and that `stages_note` is correct in all four phase
states. A four-phase label dump (window opened → mid-calibration → calibrated →
enrolling) confirmed every surface in the live widget tree, which is the check
the stubs cannot do.

#### How to use it

```bash
triton-panel          # Fingerprint group -> pick the finger -> Enroll
```

1. **Calibrate placement** — touch the pad as if unlocking, 10+ times. Watch
   the scored rate.
2. If it says **"Matching works"**, stop: the print is usable and nothing needs
   re-enrolling.
3. If it says **"Calibrated — and nothing matched"**, the template is the
   suspect. Enrol **into a free slot** (the slot name is only a label — use the
   right index in, say, the Left index slot) with the placement that just
   passed, then calibrate again: `VerifyStart("any")` scores against both
   prints, so a match proves the new template fixed it.
4. Only then, if the fresh print works and the old one never does, is deleting
   `right-index-finger` justified — and that stays a deliberate action in the
   main Fingerprint group.
5. If it says **"Captures are too thin"**, do **not** enrol. Run
   `./fp-debug.sh verify` for the underlying counts.


### 20p. A Test button for a stored print — ✅ APPLIED 2026-11-01 (seventh pass)

The Fingerprint group could enrol, delete and switch hyprlock on, and it could
not answer the one question §20m turned into the important one: **does a stored
print actually match?** "Enrolled" and "works" are genuinely different states
here — §20l proved a print could be stored, §20m found it matched nothing — and
the group displayed only the first.

**Test a stored print** is a new row with a one-shot verify: `Claim` →
`VerifyStart("any")` → one `VerifyStatus` → report → `VerifyStop` → `Release`.
The verdict lands in the row's own subtitle.

It is deliberately **not** the calibration loop of §20o. Calibration measures
*placement* over many attempts to decide whether re-enrolling is worth it; this
answers *"does the print I have work?"* once, and it is the thing to press
before going anywhere near the enrolment window.

`"any"` rather than a finger name, which is what `fprintd-verify` with no `-f`
does: it scores against every enrolled template and `VerifyFingerSelected`
names whichever one fprintd picked, so a match reports *which* print worked.
⚠ What **hyprlock** passes is *not* established. Its binary does contain the
string `any` — visible only with `strings -n 3`, since three characters is
under the default minimum — but a three-character string turns up in a binary
for many reasons, and that is weak evidence, not confirmation. What can
honestly be said is that this mirrors **fprintd's own client**.

#### The hazard is the claim, not the verdict

fprintd grants **one claim at a time**, and a claim left behind leaves the next
`Super+L` with no fingerprint until fprintd times it out — the invariant
`EnrollWindow` was already built around. A verify that nobody ever touches
**does not end on its own**, so this path releases on *every* exit:

| exit | released by |
|---|---|
| a terminal `VerifyStatus` | `_test_end` from the result branch |
| **Cancel** (the button becomes Cancel while running) | `_on_fp_test` |
| Cancel pressed while polkit's dialog is still up | `_on_test_claimed` — the claim is granted server-side anyway, so it is released there; when Cancel ran there was nothing to release yet |
| the panel window closing | `_on_close`, next to the existing enrolment-window release |
| **nobody touches the sensor** | `TEST_TIMEOUT_MS = 30000` |

The hard timeout is a correctness requirement, not a nicety: without it a
forgotten test silently disables fingerprint unlock until fprintd gives up.

A retry result (`done = False`) must **not** release — fprintd keeps the verify
open and is already waiting for another finger — so those update the subtitle
and return. Same `done` asymmetry as §20o, enforced in a second place.

#### What it says

* **match** → `✓ Matched — Right index. This print works.` plus a toast.
* **no match** → `✗ No match.` and then the §20o framing: the sensor got
  readable ridges and the matcher scored them below the threshold, **so this
  points at the stored print, not your finger**, and calibration is where to
  measure it properly.
* **driver fault** → the `VERIFY_RESULTS` hint and `./fp-debug.sh rebind`. No
  "not your finger" appended: every driver hint already says whose problem it
  is, and a second copy read as the panel protesting too much.
* The row is **insensitive with nothing enrolled** ("Enroll a finger first"),
  since `VerifyStart` would fail with `NoEnrolledPrints`.
* `_fp_busy()` now covers the test control, so the enrolment window and a test
  cannot both reach for the claim.
* ⚠ `_refresh_fingerprint` is **not reachable while a test holds the claim**
  (its callers are startup, `_enroll_finished` and `_on_fp_delete`, and the
  latter two are behind disabled buttons), which is why its `elif not
  self._testing` guard is enough to protect the in-progress subtitle. If a
  future caller adds a path that *is* reachable mid-test, check first whether
  `ListEnrolledFingers` is allowed against a claim held by the same caller —
  that is undocumented here, and §20e only established that it raises when
  nothing is enrolled.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **107 assertions, ALL PASS** (81 before this, 40 originally) |
| retry (`done=False`) | **no** D-Bus call, still testing, subtitle updated |
| match | `["VerifyStop", "Release"]`, button back to "Test", names the finger, toast |
| no-match | released; subtitle says "stored print, not your finger" |
| driver fault | released; points at `rebind`; does not blame the hand |
| timeout | released, timer cleared |
| Cancel | released; `_test_end` twice is harmless |
| claim granted after Cancel | `["Release"]` only — never subscribed, never used |
| failing `VerifyStart` | released, not left in the testing state |
| widget construction | group smoke-tested against the live reader; `_fp_busy` locks the row |

⚠ **Still unrun against a real finger** — every check above is the panel, not
the sensor. The first press of **Test** is also the first time the live
`VerifyStart` path in this panel meets the daemon.


### 20q. One-of-N, not a composite: why §20o's enrolment advice was backwards — ✅ APPLIED 2026-11-01 (eighth pass)

Enrolment was still hard — *"obtengo pocas mediciones correctas del sensor"* —
so other projects were read for ideas. The most useful finding was not in any
of them: it was in libfprint's own print handling, and it **reverses** what
§20o told the user to do with their hand.

#### The finding

An enrolled NBIS print is **not one merged template**. It is a `GPtrArray` of
per-stage minutiae sets — `FpPrint` exposes it as **`fpi-prints`**, plural
(confirmed by introspection on this machine), and `fpi_print_add_print` appends
one entry per call:

```c
g_ptr_array_add (print->prints, g_memdup2 (add->prints->pdata[0], sizeof (struct xyt_struct)));
```

And `fpi_print_bz3_match` loops over **every** stored entry, returning on the
**first** one that clears the threshold:

```c
for (i = 0; i < template->prints->len; i++)
    score = bozorth_to_gallery (probe_len, pstruct, gstruct);
    if (score >= bz3_threshold)
      return FPI_MATCH_SUCCESS;
```

**That is a one-of-N match.** The bz3 threshold defaults to **40** and is
runtime-settable by a driver through `fpi_image_device_set_bz3_threshold()`
(the symbol is present in the installed `libfprint-2.so.2`).

#### What follows, and the mistake it exposes

| | |
|---|---|
| six **identical** placements | six near-duplicate candidates — **five of the six slots wasted** |
| six **different** regions | six independent chances for one verify capture to overlap one of them |

On a ~1 cm pad, where no single capture can hold much of the finger, that is
the difference between a template that can be matched and one that cannot. It
is also why phone enrolment asks you to shift the finger and then do the edges.

⚠ **§20o told the user the opposite** — *"Use the SAME placement that passed
calibration on every stage… A template stitched from six different parts of
the finger is what a single verify capture cannot match."* The second sentence
is false, and the reason it was written is worth keeping: it **conflated two
different things** —

* the `elan` driver stitching **frames** by displacement **within one capture**
  (§20j's finding — real), with
* how libfprint stores stages **across an enrolment** (not stitching at all).

The first is a property of this driver. The second is a property of libfprint,
and nothing about it merges the stages. Same family of error as §20g: a true
fact about one layer carried into a conclusion about another.

The **calibration** advice stays correct — it measures one placement's
readability. What changed is what you do with that placement afterwards:
**enrol around it, not at it six times.**

#### Applied in the panel

* `ENROLL_REGIONS` — six regions: centre, higher, lower, rolled left, rolled
  right, centre held longer.
* `_stage_hint()` replaces `_cycle_hint()` in the accepted-stage branch, so
  after every stage the window names **the next region** and says why
  (*"each stage is stored as its own candidate and unlocking succeeds if ANY
  one of them matches"*). No per-stage libfprint hook is needed — `self.passed`
  is enough, which §20j had already established is all any client gets.
* `_region_for()` indexes **modulo** the list and stops at the device's own
  stage count, so a reader reporting 5 or 8 stages instead of this one's 6
  still gets a region for each and never invents a seventh.
* The "SAME placement" copy in `_begin_enroll`, and *"keep using exactly this
  placement for every stage"* in the calibration card, are both replaced.

`test-enroll.py`: **130 assertions, all passing** — including that each stage
names a *different* next region, that the last stage falls back to the plain
cycle hint instead of inventing a stage 7, and the `stages=5` / `stages=8`
off-by-one cases.

#### Ideas from other projects, ranked by how well they are verified

⚠ Read the verification column before acting on any of these. They are listed
because they were asked for, not because they are established.

| idea | where from | verified how | relevance here |
|---|---|---|---|
| **bz3 threshold is 40 and a driver can lower it** | libfprint reference manual + `fpi_image_device_set_bz3_threshold` in the local `.so` | **Confirmed.** Default documented upstream; symbol present locally | Our `verify-no-match` means *scored below 40*. Lowering it is the most direct lever on matching — at a **false-accept cost**, and it needs a patched libfprint (an `fpi_` internal, no env var, no fprintd knob) |
| **`FP_SCAN_TYPE_PRESS` instead of SWIPE for elan** | [FCsab/Elan-04f3-0c6e fix](https://github.com/FCsab/Elan-04f3-0c6e-fingerprint-reader-fix) README; an [openSUSE `libfprint_elan.patch`](https://build.opensuse.org/projects/home:abuenameh/packages/libfprint/files/libfprint_elan.patch?expand=0) | **Two independent sources claim it; neither diff was read** (the README shows no code, the openSUSE file returned 403) | Exactly our confirmed physical diagnosis (§20j). Would remove the motion-assembly path a still press cannot feed — the direct cause of `No minutiae found` |
| **Image-based presence detection** — infer finger presence from image data instead of the hardware status byte | same 0c6e fork's README | **One README, code not read** | Would address §20j's *invalid* `AWAIT_FINGER_ON → AWAIT_FINGER_OFF` transition and the runs that stall with no error at all |
| **SIFT matcher replacing bozorth3** | same 0c6e fork's README | **One README, code not read** | The most interesting idea here: image-feature matching does not need a minutiae count, which is §20k's floor on a ~1 cm pad |
| **12 enrol presses instead of 6** | same 0c6e fork's README | **One README, code not read** | Now *motivated* rather than arbitrary: with one-of-N matching, more stages means more independent candidates |
| **Frame-assembly overflow fix** | [pbogut/libfprint](https://github.com/pbogut/libfprint) | Repo description only | We do see bozorth3 `qq[] overflow` warning strings in the local library |
| **`ELAN_NOT_ROTATED` quirk** | [iafilatov/libfprint `elan.h`](https://github.com/iafilatov/libfprint/blob/elan-github-msg/libfprint/drivers/elan.h) | Header read, but its id table is **0x0c01–0x0c33** and ours is **0x0c4f** | A **hypothesis only**: if frames are rotated on a device that should not be, assembly is garbage. What upstream does for 0c4f is unknown |
| **Enrol on Windows, verify on Linux** works for a sibling | [Elan-Fingerprint-0c4c-PoC issue](https://github.com/depau/Elan-Fingerprint-0c4c-PoC/issues/4) | A single issue comment | Weak, but it points the same way as everything above: the *enrolment data* is the weak link, not the matching |
| Same `No minutiae found` on sibling Elan `04f3:0c4d` | [Manjaro forum thread](https://forum.manjaro.org/t/fingerprint-enrollment-fails-on-manjaro-gnome-with-04f3-0c4d-sensor/169884) | Thread shows **no resolution** | Confirms the symptom is family-wide, offers no fix |

Nothing was found that targets **`04f3:0c4f`** specifically, and **no
match-on-chip driver covers it** (§20m).

#### ⚠ Everything in Layer B needs a patched libfprint — not started

The last six rows all mean *rebuild libfprint with a patch*. That was **not
done**, and it should not be done casually:

* `libfprint` is behind `pam_fprintd` in `/etc/pam.d/sudo` **and** hyprlock's
  unlock path. A broken build degrades both. (`pam_fprintd` is `sufficient`, so
  the password still works — that is the only reason this is recoverable.)
* It is a system package, so a `pacman -Syu` silently reverts the patch and the
  behaviour changes under you. Pinning it in `IgnorePkg` then freezes security
  updates to it.
* Rollback path to name **before** starting: the cached package,
  `sudo pacman -U /var/cache/pacman/pkg/libfprint-1.94.100-1.1-x86_64.pkg.tar.zst`.

If it is attempted, the order that matches the evidence is: **(1)** scan type
to press — it is the one change our own hardware diagnosis predicts; **(2)**
lower the bz3 threshold, measurable immediately with the panel's Test button;
**(3)** the 0c6e fork's presence detection and SIFT matcher, which are the
largest change and the least verified. Measure with `./fp-debug.sh verify`
between each, and the Test button after each.

#### Free thing to do first

The per-stage coverage change above costs nothing and is already deployed.
**Re-enrol into a free slot with it** (§20n: the slot name is only a label, so
a free slot can hold the right index finger) and press **Test**. If one-of-N
coverage is what was missing, that is where it shows up — and it needs no
patched library.


### 20r. One press is one measurement — ✅ APPLIED 2026-11-01 (ninth pass)

Reported: *"sale mucho el mensaje captures are too thin, **y yo no retiro el
dedo**."* That second clause is the whole diagnosis. The panel was reporting a
dozen failed measurements from a finger that had been placed **once**.

#### The evidence

`journalctl -u fprintd`, the user's own calibration session — **44 seconds** of
this, alternating every 1–3 s:

```
13:26:52  Failed to detect minutiae: No minutiae found
13:26:53  Device reported an error during verify: … protocol error
13:26:55  Failed to detect minutiae: No minutiae found
13:26:55  Device reported an error during verify: … protocol error
13:26:57  Failed to detect minutiae: No minutiae found
13:26:57  Device reported an error during verify: … protocol error
…                                        (through 13:27:36)
```

No human places a finger twenty times in forty-four seconds. The chain:

1. every `VerifyStatus` with `done = True` — which includes the protocol
   errors — called `_verify_cycle()` **immediately**;
2. each fresh `VerifyStart` captured the **same resting finger**;
3. a resting finger gives `elan`'s assembly nothing, so → `No minutiae found`
   → `verify-retry-scan` → **`cal_log.append(False)`**;
4. ten of those filled the rolling window in ~20 s, all from **one contact**;
5. the gate then announced **"Captures are too thin"** — about a placement the
   user had made once and never released.

So the message was not merely unhelpful, it was **measuring the panel's own
loop**. §20o's claim that calibration measures *placement* was false whenever
the finger stayed down.

⚠ `MAX_CAL_DRY` did not trip, and **was right not to**: it counts consecutive
driver faults *with no finger contact between them*, and here the finger was
very much there. It guards a wedged endpoint with nobody touching it. This was
the opposite case — a resting finger and a spinning loop — and nothing guarded
it.

#### ⚠ The fix below was itself a regression — see §20s

Making the **re-arm** wait for the lift left the device deaf for up to three
seconds after every result, and the user's touches were lost in the blackout
(*"a veces no detecta mi dedo"*). Counting and arming are different decisions
with opposite failure modes: a missed count is a wrong measurement, a missed
re-arm is a lost touch. The verify is now **always re-armed at once** and only
the *counting* waits on the lift. Read this section for the counting bug it
correctly identified; read §20s for how the arming was put back.

#### The fix: re-arm on the lift, not on `done`

Which is also what libfprint's own image-device cycle waits for
(`AWAIT_FINGER_OFF`, §20j). Three behaviours, by how much the reader can tell
us:

| condition | behaviour |
|---|---|
| `finger-present` supported **and** a lift seen since the last counted result | count it, re-arm |
| `finger-present` supported, **no** lift | **not counted** — `cal_log`, `cal_attempts` and the tally untouched, no `VerifyStart`. Status: *"Lift the finger clear"*, logged once per contact as `Same contact — not counted` |
| `finger-present` **never reported** by this reader | the old behaviour: count and re-arm at once, because there is no lift to gate on |

⚠ **The `CAL_REARM_MS = 3000` timer is not optional.** §20j recorded this
driver emitting an *invalid* `AWAIT_FINGER_ON → AWAIT_FINGER_OFF` transition —
it mishandles the lift — so `finger-present: false` may never arrive. Waiting
forever would hang calibration in silence, which is the §20j stall in a new
costume. The timer re-arms anyway, treats it as a lift for counting, and logs
**`Re-armed by timer`** so a later reader can tell *"the driver reported the
lift"* from *"we stopped waiting for it"*.

#### The trap that hid this

The lift is hooked on the real `finger-present → False` transition in
`_on_properties_changed`, **not** on `close_open_contact()`.
`close_open_contact()` is called artificially from the result handlers on
*every* result, whether or not the finger moved — which is exactly why a dozen
results from one unbroken press each came back with a **plausible-looking
contact duration**. The instrument that was supposed to make this visible was
reporting it as normal.

#### Also fixed: a journal line that reads like a claim leak and is not one

The same journal carried:

```
13:21:00  Authorization denied … to call method 'EnrollStop' … Device was not claimed before use
13:21:00  Authorization denied … to call method 'Release'    … Device was not claimed before use
```

A second `_stop()` — the one from close-request, after `_idle_buttons()` had
already reset `phase` — found `phase == "idle"`, guessed `EnrollStop`, and
asked fprintd to stop and release a device it no longer held. Harmless, every
error caught, but it is the single most misleading line this subsystem can
print: a claim leak is the one failure mode §20p is built around. Now `_stop`
records `_last_phase` and sets `_released`, so the second call is a **no-op**
and the line is gone.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **154 assertions, ALL PASS** (130 before) |
| a second result from the same press | `cal_log` untouched, `cal_attempts` stays 1, **no** `VerifyStart`, status says *Lift* |
| logging | `Same contact — not counted` appears **once per contact**, not once per result |
| the lift | re-arms `["VerifyStop", "VerifyStart"]` and the next press counts |
| `done` alone | does **not** re-arm; `_cal_rearm_pending` is set instead |
| reader with no `finger-present` | **not** gated — both results counted, re-armed at once |
| the timer | re-arms, counts again rather than hanging, and logs that it was the timer |
| `_stop` twice | second call is a no-op; no `Release` on an unclaimed device |

⚠ The existing tests had to be **rewritten to model the lift** — six of them
fired several `done = True` results in a row with no lift between, which was
only ever valid under the assumption this section removes. They now go through
a `press()` helper that lifts afterwards, like a hand does.


### 20s. §20r made the device deaf — counting and arming are different decisions — ✅ APPLIED 2026-11-01 (tenth pass)

Reported one minute after §20r shipped: *"ahora está peor: a veces no detecta
mi dedo."* Correct, and it was a regression I introduced.

#### The two journals, side by side

**Before §20r** (13:26:52 → 13:27:36, one continuous press):

```
13:26:52  No minutiae found
13:26:53  protocol error
13:26:55  No minutiae found        <- events every 1-3 s
13:26:55  protocol error
13:26:57  No minutiae found
13:26:57  protocol error
```

**After §20r** (13:34:31 → 13:35:16):

```
13:34:31  No minutiae found        <- the ONLY one in 45 seconds
13:34:32  protocol error
13:34:35  protocol error           <- +3 s
13:34:39  protocol error           <- +4 s
13:34:44  protocol error           <- +5 s
13:34:57  protocol error           <- +13 s
13:35:02  protocol error           <- +5 s
13:35:16  protocol error           <- +14 s
```

The gaps are `CAL_REARM_MS`, and the collapse from ~10 `No minutiae found` to
**one** is the finding: the device was not capturing, because no verify was
armed when the finger arrived. **The panel had gone deaf for up to three
seconds after every result**, and the user's touches fell into the blackout.

#### What was wrong in §20r, in one sentence

It coupled two decisions that have **opposite failure modes**:

| decision | cost of getting it wrong |
|---|---|
| miss a **count** | the measurement is wrong — recoverable, and visible in the tally |
| miss a **re-arm** | the touch is **lost**, and the hardware looks broken |

§20r made the re-arm wait on the lift to fix a counting bug. The verify is now
**always re-armed immediately**, for every bucket, and the lift gate decides
*only* whether a result is counted. `_arm_rearm`, `_on_rearm_timeout`,
`_cal_rearm_pending`, `_cancel_rearm` and `CAL_REARM_MS` are **deleted**, not
left dormant.

~~| `finger-present` supported, **no** lift | not counted … no `VerifyStart` |~~
⚠ That row of §20r's table is superseded: the suppression branch now still
re-arms before returning.

#### How "is this a new press?" is decided now

It cannot use the strip's open contact. `close_open_contact()` shuts it
**artificially on every result**, which is the same trap that made a dozen
results from one press each show a plausible duration — §20r named that trap
and then the first draft of this fix walked back into it. Two signals instead:

1. **Any `finger-present` transition since the last counted result.** A new
   press has to be *detected* to be captured at all, so the **ON** edge is the
   best available evidence that something moved — and it does not depend on the
   OFF edge, which §20j recorded this driver emitting *invalidly*.
2. **A wall-clock escape, `SAME_PRESS_S = 2.0`.** A result arriving later than
   that after the last counted one is counted regardless, so an unreliable
   `finger-present` can never suppress the measurement *forever*. It logs
   **`Counted without a reported lift`**, because "the driver reported a lift"
   and "we assumed one" must stay distinguishable.

A reader that never reports contact at all (`strip.supported is not True`) is
still not gated, as in §20r.

#### `fp-debug.sh presence` — the trace that should have come first

Two bugs in a row came from **guessing** at `finger-present`: §20r counted one
press as a dozen placements, and its fix made the device deaf. Neither would
have been written if this had existed, so it exists now:

```bash
./fp-debug.sh presence          # PASSES=4 by default
```

It needs **no sudo, no drop-in and no fprintd restart** — `finger-present`
arrives as an ordinary `PropertiesChanged` on the system bus, and skipping the
restart means the trace sees the daemon in the state the panel actually meets.
Every presence change is printed with a millisecond timestamp, interleaved with
each `VerifyStatus`, and the summary counts the two edges. Read it as:

| what the trace shows | conclusion |
|---|---|
| `true` with no matching `false` after a real lift | the driver does not report the lift; anything gated on it is unreliable (the §20j bug) |
| both edges, promptly | the signal is good and the panel can trust it |
| no `finger-present` lines at all | the reader never reports contact; the panel already detects this and stops gating |

⚠ **Still unrun.** It needs a finger. Until it is, `SAME_PRESS_S` is carrying
the design, and whether that is necessary or merely harmless is **not known**.

#### Verify — results 2026-11-01

| check | result |
|---|---|
| `test-enroll.py` | **154 assertions, ALL PASS** |
| suppression still re-arms | a same-press repeat ×3 → `cal_log` untouched **and** `["VerifyStop","VerifyStart"]` ×3 — never deaf |
| a terminal result | re-arms at once, no waiting |
| ON edge alone | counts the next result without any reported lift |
| the wall-clock escape | a fast repeat is suppressed; the same result 3 s later is counted and logged as assumed |
| reader with no `finger-present` | not gated |
| `_stop` twice | still a no-op |
| tests rewritten | §20r's two tests for the deleted waiting behaviour are **replaced**, not disabled |


#### Not changed

`hyprlock.conf` is untouched — the wiring is complete and correct, and §20e/§20l
already verified every link in it: the managed block is live and mirrored,
`hyprlock 0.9.6` carries `CFingerprint`/`VerifyStart` and the four
`auth:fingerprint:*` keys, `fprintd.service` runs,
`net.reactivated.fprint.device.verify` is `allow_active = yes` against an
`Active=yes` seat0 wayland session, and all three lock paths (`Super+L`,
hypridle `lock_cmd`, `loginctl lock-session`) launch hyprlock, which reads the
file at start. **Nothing in the configuration is missing.** What is missing is a
template that matches. Password auth stays on in hyprlock and `pam_fprintd` is
`sufficient` in `sudo`, so there is no lockout path in any of this.

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
