# Boot, Autologin, Suspend and Thunderbolt

> Part of the `cachyPool` runbooks. Section numbers are **preserved** from
> `finish-installation-commands.md`, dissolved 2026-11-03 — a `§N` reference
> anywhere in this repo still resolves by number. Index and conventions:
> `README.md`. Live-state history: `../CHANGELOG.md`.

How this machine boots and how it sleeps: the Limine kernel command line, the Thunderbolt boot-and-shutdown hang, the `getty@tty1` autologin path that replaced the display manager, the `s2idle` forcing that keeps resume from killing the NVIDIA module, and the logind lid behaviour on external power.

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

> **NVIDIA driver patch level — already satisfied.** Per `../ACTUAL-CONFIGURATION.md` §3, the installed driver is **595.71.05**, which is past **595.58.03** — the version that fixed the `nvidia_modeset` NULL-deref on 2-monitor TB-dock disconnect (NVIDIA bug 5871511, forum thread 359280). So you don't need to chase that specific bug. If `nvidia-smi` shows something older, upgrade before doing anything else here.

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
> `sudo systemctl mask --now plymouth-start.service`. See the `plymouthd` row in `../ACTUAL-CONFIGURATION.md`
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
- **Update `../ACTUAL-CONFIGURATION.md` §2** once this is applied: ✅ Done 2026-05-23. Display-manager row, §14, §15 row, and the §17 boot flow now reflect the `getty@tty1` autologin + fish `exec start-hyprland` path.

### 10.j References

- [Hyprland Discussions #13464 — phantom cursor handoff bug from KDE login manager](https://github.com/hyprwm/Hyprland/discussions/13464) — the original motivation for this change.
- [Arch Wiki — Automatic login to virtual console](https://wiki.archlinux.org/title/Getty#Automatic_login_to_virtual_console) — canonical `getty@tty1` override pattern.
- [Arch Wiki — Start X / Wayland at login](https://wiki.archlinux.org/title/Start_X_at_login) — login-shell guard conventions (both `.zlogin` and fish `status is-login`).
- [fish docs — Initialization files](https://fishshell.com/docs/current/language.html#initialization-files) — confirms `conf.d/*.fish` is sourced on every startup and `status is-login` is the correct login-shell guard.
- [Hyprland Wiki — starting Hyprland](https://wiki.hypr.land/Getting-Started/Master-Tutorial/) — confirms Hyprland is greeter-agnostic. As of Hyprland 0.53, the supported launch is `exec start-hyprland` (the package-shipped wrapper that initializes the systemd user session and XDG env before exec'ing the compositor); `exec Hyprland` still works but emits a startup warning and skips that setup.
- [Omarchy install scripts](https://github.com/basecamp/omarchy) — reference implementation of the no-DM Hyprland pattern this section follows.

---

## 11. NVIDIA black-screen on resume from suspend — force `s2idle` (CONFIRMED ISSUE)

**Why this exists.** Resuming from **deep (S3)** suspend crashes the NVIDIA open kernel module (595.71.05) and leaves the screen black while the system keeps running headless. Diagnosed 2026-05-26 from the journal of the session that ended in a forced power-off — see `../ACTUAL-CONFIGURATION.md` §15 ("NVIDIA black-screen on resume from suspend").

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

## 15. logind: ignore lid close on external power — ✅ APPLIED 2026-10-12 (written 2026-07-12, never installed until then)

**Why:** resuming from s2idle can crash `nvidia_modeset` on this machine, ending in a black screen and a forced power-off (GSP row in `../ACTUAL-CONFIGURATION.md` §15). The 2026-07-12 mitigation had two halves: hypridle's 20-min suspend became battery-only, and closing the lid on external power was to be ignored by logind. The first half went live. The second was only committed to the repo as `configs/systemd/logind.conf.d/50-no-suspend-on-external-power.conf`. `/etc/systemd/logind.conf.d/` never existed, and `../shortcuts.md` §7 and the GSP row described a setting that was not there.

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

- `../ACTUAL-CONFIGURATION.md`: GSP row annotated, new §15 row, §16 repo layout gained `configs/systemd/logind.conf.d/`.
- `../shortcuts.md` §7: lid-close line corrected. It used to say the lid "locks, then suspends", but nothing locks on lid close unless the machine actually suspends. Closed-lid tips added.
- `../CLAUDE.md`: note that `configs/` also mirrors two system paths whose live copies must be checked.

---


---

## Issue history

Moved here 2026-11-03 from `../ACTUAL-CONFIGURATION.md` §15, verbatim. Those table
cells had grown into multi-kilobyte incident analyses; §15 is now a status table
and the reasoning lives beside the runbook it explains.

### `plymouthd` spinning forever with nothing to draw

✅ **Resolved 2026-11-02** — `plymouth-start.service` was `active running` 35 minutes into a boot that has **no splash at all**: `plymouth` is out of mkinitcpio `HOOKS=`, `quiet splash` is off the cmdline, and there is no display manager. §6.3.c masked `plymouth-quit` and `plymouth-quit-wait` for the TB4 shutdown hang — so nothing was left to tell `plymouthd` to exit, and it busy-looped for the life of the session. **Measured** at 16 ticks per 5 s ≈ 3.2 % of a core; systemd's own accounting on stop confirmed it independently: `Consumed 1min 616ms CPU time over 35min 3.668s wall clock time` = **2.88 % of a core, sustained, for nothing** — which also keeps the package out of its deeper idle states. **Fix:** `sudo systemctl mask --now plymouth-start.service`. The unit is `static` (pulled in by `sysinit.target`), so `disable` does not apply; it is `Type=forking` with `KillMode=mixed` and `plymouthd` lives in the unit's cgroup, so `--now` kills it cleanly without going through the `plymouth quit` IPC path that §6.3.c distrusts. Verified: `/etc/systemd/system/plymouth-start.service → /dev/null`, unit `inactive`, no `plymouthd` process. Reversible with `unmask`. Alternative not used: `plymouth.enable=0` via `/etc/default/limine` + `sudo limine-mkinitcpio`, which is the unit's own `ConditionKernelCommandLine` and would also cover the LTS entry, but touches the bootloader. ⚠ Note this was a **consequence of the repo's own fix**: masking the quit units without also stopping the start unit leaves the daemon orphaned. §6.3.c

### NVIDIA GSP "Reset required" after s2idle resume

⚠ Open — driver `610.43.02` (open GSP modules): the 2026-07-02 20:48 resume failed `kgspWaitForRmInitDone` → dGPU unusable until reboot; every client touching it afterwards logs NVRM errors (384/344/359 across the last three suspend-cycle boots; a boot without a suspend logged 0). ~~Impact contained~~ **2026-07-12 escalation — no longer contained:** after ~4 h in s2idle (hypridle auto-suspend 14:22 → wake 18:24, kernel `7.1.2-3-cachyos`), resume failed `gpuPowerManagementResume: GSP boot failed at resume (bootMode 0x1): 0x62` and this time **crashed `nvidia_modeset` mid-resume** (page-fault oops in `FreeDeviceReference` inside `nvkms_resume`; `systemd-sleep` "exited with irqs disabled", SIGKILLed; `systemd-suspend.service` failed). Collateral: TB4 bridge `02:00.0` (Goshen Ridge dock) "not ready 1023ms after resume; giving up" → entire downstream tree (USB, r8152 Ethernet, dock displays) torn down; Hyprland lost all outputs (`hyprpolkitagent: There are no outputs`) → black screen on every panel incl. eDP-1; processes went SIGKILL-immune (`snapper-cleanup: Processes still around after SIGKILL`) → forced power-off ~18:52. i915 logged zero errors — purely the NVIDIA resume path. `PreserveVideoMemoryAllocations=1` + `/var/tmp` spill + nvidia-{suspend,resume} services all ran correctly; driver/firmware bug, not misconfig. **Mitigation 2026-07-12:** hypridle 20-min suspend is now battery-only (Hypridle row above), and logind lid-switch on external power set to ignore. ⚠ That logind half was only committed to the repo on 2026-07-12; it went live on **2026-10-12** ("logind lid drop-in" row below). Untried escalations if suspend-on-battery also crashes: `NVreg_EnableS0ixPowerManagement=1` (currently `0`; NVIDIA's recommended mode for s2idle laptops) or `NVreg_DynamicPowerManagement=0x00` (keep dGPU powered). Re-test on each driver update past 610.43.02. **2026-10-31 — first re-test since the incident, and it passed, but it does not close this row.** The driver has moved 610.43.02 → **615.71.09**. At 09:49:15 the machine auto-suspended on its own (hypridle's 20-min listener, armed again by the new battery) and resumed at 09:57 **clean**: zero `NVRM|GSP|nvidia_modeset|Xid` matches in the kernel log since the suspend, `systemd-suspend.service` `Result=success`, `nvidia-suspend`/`nvidia-resume` both success, dGPU alive afterwards (`nvidia-smi` answering, 39 °C). **But the incident conditions were not reproduced:** that was ~4 h in s2idle **with the TB4 dock attached**; this was ~8 min and **undocked**. Still open: (1) a long suspend, >2 h, on battery, and (2) a cycle with the Plugable TBT4-UD5 connected. Verify after any resume with `journalctl -k --since <suspend-time> | grep -iE 'NVRM|GSP|nvidia_modeset|Xid'` plus `systemctl show -p Result --value systemd-suspend.service`

### logind lid drop-in committed but never installed

✅ Resolved 2026-10-12 — `configs/systemd/logind.conf.d/50-no-suspend-on-external-power.conf` (`HandleLidSwitchExternalPower=ignore`) was committed on 2026-07-12 as half of the GSP mitigation, and `../shortcuts.md` §7 plus the GSP row described it as live. But `/etc/systemd/logind.conf.d/` did not exist: live `HandleLidSwitchExternalPower` was unset, falling back to `HandleLidSwitch=suspend`. Closing the lid at the desk still did nothing only because logind counted the TB4 monitors as docked (`HandleLidSwitchDocked=ignore`). **Exposure:** logind keeps re-evaluating while the lid is closed, so a dock blink with the lid shut would read as undocked on external power and suspend, which is the GSP resume-crash path. The Plugable TBT4-UD5 did drop both DP tunnels for ~5 s with no host-side trigger on 2026-10-07 22:14:46 and 2026-10-12 20:22:59, about a minute after boot each time. No such suspend happened: zero lid events in the journal (retained from 2026-09-30) before the fix. **Fix:** installed the repo file to `/etc/systemd/logind.conf.d/` and sent `systemctl kill -s HUP systemd-logind` (`Config file reloaded.`). **Verified 2026-10-12:** `HandleLidSwitchExternalPower` = `ignore`; a real lid close at 21:16:17 with the dock attached logged only `Lid closed.`, both TB4 monitors stayed on, no suspend. With the battery removed, `OnExternalPower` is always true, so the lid never suspends the machine until the replacement pack is fitted. **Lesson:** files mirrored from `/etc` can sit in the repo without being live; check the live path too. Steps: §15.

### Hypridle timeouts

✅ Configured (5/10/20 min). **2026-07-12:** the 20-min suspend listener is now **battery-only** (`grep -q Discharging /sys/class/power_supply/BAT1/status && systemctl suspend` — `BAT1` status covers barrel AC, USB-C PD and dock power, unlike `ACAD/online`) after that day's resume-from-s2idle crash (GSP row below). On external power the machine still locks (5 min) + DPMS-off (10 min) but stays awake. **2026-10-31:** dormant since 2026-10-12 because there was no `BAT1` node to read; with the replacement pack fitted it is **armed again**, so the GSP resume path below is live once more

### LTS kernel cmdline

🔧 Reframed 2026-07-02 — the modeset worry is obsolete: `modeset` is the 610-series driver default and early-KMS comes from `/etc/mkinitcpio.conf.d/10-chwd.conf`, both kernel-agnostic; even the main entry's cmdline no longer carries `nvidia-drm.modeset=1`. Remaining: verify the LTS entry carries `thunderbolt.host_reset=0` + `mem_sleep_default=s2idle` (`sudo grep -i -B2 -A8 lts /boot/limine.conf`) and boot-test it once — LTS `6.18.35` is the escape hatch for the i915 `7.0.12` NULL-deref row below

### `quiet splash` / plymouth regression

✅ Re-reverted 2026-06-11 — both had been re-added that day (`KERNEL_CMDLINE[default]+=" quiet splash"` in `/etc/default/limine` + `plymouth` back in mkinitcpio `HOOKS=`) to hide boot-console text, which reintroduced boot problems. Removed both and ran `sudo limine-mkinitcpio` (rebuilt `linux-cachyos` + `linux-cachyos-lts`, regenerated `/boot/limine.conf`). Backups: `/etc/default/limine.bak-20260611`, `/etc/mkinitcpio.conf.bak-20260611`. Plymouth shutdown units remain masked. This restores the 2026-05-22 TB-boot-fix state — do not re-add `quiet splash` or the `plymouth` hook.

### NVIDIA black-screen on resume from suspend

🔧 Fix applied 2026-05-26 — resume from **deep (S3)** suspend crashed the NVIDIA open module (595.71.05). On the 2026-05-26 21:38 resume: `nvidia-drm: Failed to detect display state` + **333 `NVRM:` MMU-walk assertion failures** (`mmuWalkUnmap`/`mmuWalkSparsify` → `NV_ERR_INVALID_STATE`) wedged the display engine → screen stayed black while the system kept running headless → forced power-off at 21:44 (journal ends mid-line on a WiFi rekey, no shutdown sequence). Same `Failed to detect display state` seen milder (2 errors, recovered) on the 2026-05-25 19:15 resume, so it's recurring. `NVreg_PreserveVideoMemoryAllocations=1`, `/var/tmp` spill, and `nvidia-{suspend,resume,hibernate}` were **all already correctly set** — this is a driver-level S3-resume bug, not a misconfig. **Fix:** force `s2idle` instead of S3 via `mem_sleep_default=s2idle` appended to the `linux-cachyos` cmdline in `/etc/default/limine`, then `sudo limine-mkinitcpio`. Live-applied 2026-05-26 (`/sys/power/mem_sleep` now `[s2idle] deep`); persist + verify steps in §11. ⚠ LTS entry not updated. Re-evaluate if a newer NVIDIA driver fixes S3 resume. **2026-07-02:** s2idle avoids the hard display wedge, but the 20:48 resume failed dGPU GSP re-init (`kgspWaitForRmInitDone → Reset required`) — dGPU dead until reboot; the session survives because the compositor runs on the iGPU. Tracked in the dedicated GSP row below.
