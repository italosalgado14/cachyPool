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

---

*All commands above are reversible. Take a snapper snapshot before section 6 or 10 if you want belt-and-suspenders safety:*
```bash
sudo snapper -c root create --description "before TB fix / DM switch"
```
