# GPU and Video Decode

> Part of the `cachyPool` runbooks. Section numbers are **preserved** from
> `finish-installation-commands.md`, dissolved 2026-11-03 — a `§N` reference
> anywhere in this repo still resolves by number. Index and conventions:
> `README.md`. Live-state history: `../CHANGELOG.md`.

The Firefox freeze of 2026-07-02 and what came out of it: VA-API moved off the NVIDIA shim onto the Intel iGPU, hardware video decode paused per-profile, and the video players that have to respect the same caveat.

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
- After the first suspend/resume: if the GSP `Reset required` burst returns, that's the separate open dGPU bug (`../ACTUAL-CONFIGURATION.md` §15 row) — the session should survive it since nothing critical runs on the dGPU.

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

`qt5-wayland` is already installed (§6 of `../ACTUAL-CONFIGURATION.md`), so no extra Wayland plumbing is needed.

### 13b. Make it appear in Walker

VLC ships `/usr/share/applications/vlc.desktop`. Elephant's `desktopapplications` provider **sometimes** hot-reloads and sometimes serves a stale cache (Obsidian hot-reloaded; Google Chrome did not — see §7 notes in `../ACTUAL-CONFIGURATION.md`).

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

- `../ACTUAL-CONFIGURATION.md` — §7 media table (VLC installed; `haruna` documented for the first time), §9 counts (explicit 273 → **274**, total 1427 → **1432**, AUR unchanged at 12), §15 row moved to ✅, §16 repo layout gained `configs/vlc/`.
- `../archive/spected-installation.md` — VLC added to the recommended stack as the video-player entry.
- `configs/vlc/vlcrc` — the decode pin is now mirrored in the repo. Restore path on a rebuild: `cp configs/vlc/vlcrc ~/.config/vlc/vlcrc`.

---


---

## Issue history

Moved here 2026-11-03 from `../ACTUAL-CONFIGURATION.md` §15, verbatim. Those table
cells had grown into multi-kilobyte incident analyses; §15 is now a status table
and the reasoning lives beside the runbook it explains.

### i915 NULL deref in `__gen8_ppgtt_clear` during GPU-hang recovery

⚠ Open — kernel `7.0.12-1-cachyos` bug: a video-engine hang should end in a context reset, but recovery crashed (`BUG: kernel NULL pointer dereference … RIP: __gen8_ppgtt_clear+0x1da [i915]`, 2026-07-02 21:10), wedging GPU memory management until reboot. Mitigation: keep Firefox on software decode (§12c below). Escape hatch: `linux-cachyos-lts 6.18.35`. Re-test hardware decode after the next kernel bump (§12f)

### Firefox freeze 2026-07-02 21:10 — whole session wedged

🔧 Mitigated 2026-07-02 — journal (boot `8790fdd2`) shows two **independent** failures: (1) 20:48 resume → dGPU GSP re-init failed (dedicated row below) → 384 NVRM errors this boot (344/359 the two prior), incl. `vaspaceapiConstruct: Could not construct VA space` at 20:57 — a GPU *virtual-address-space* error on the dead dGPU, **not** the VA-API video shim. (2) At 21:10 Firefox's `MediaPD~der` hung the **iGPU** video engine 3× (`i915 GPU HANG ecode 12:4`) and i915's hang-recovery NULL-dereffed in `__gen8_ppgtt_clear` (row below) → GPU memory management wedged → freeze. Key finding: Walker/Elephant launches Firefox from the systemd `--user` env, so `LIBVA_DRIVER_NAME=nvidia` never reached it — Firefox was already hardware-decoding on the iGPU; the NVIDIA shim was dead config. **Fixes:** `env.conf` VA-API → `iHD` + `NVD_BACKEND` dropped (repo+live); Firefox hardware decode paused via `~/.config/mozilla/firefox/31yk9hxe.default-release/user.js` (`media.ffmpeg.vaapi.enabled=false`) until the i915 bug is fixed; `libva-nvidia-driver` removed (confirmed gone 2026-07-02). Details/verify/revert: §12

### VLC not installed (video playback)

✅ Resolved 2026-07-31 — the machine had a binary-less half-install: `vlc-plugins-all` was explicit (libvlc + every codec plugin) but the `vlc` package and its Qt GUI never were, so no `vlc` on `$PATH`. Installed `vlc 3.0.23_2-9.1` — only 5 packages, since the plugin deps were already satisfied. Elephant hot-reloaded (score 88, no restart). **Hardware decode pinned off** in `~/.config/vlc/vlcrc` (`[avcodec]`/`avcodec-hw=none`): VLC's default `avcodec-hw=any` routes VA-API → iHD → the iGPU, the exact path that hung the video engine on 2026-07-02 (i915 row below), and `env.conf` can't reach it because Walker launches apps from the systemd `--user` env. Verified by verbose playback — `looking for hw decoder module matching "none" … no hw decoder modules matched` → software decode, 0 kernel GPU errors. Also confirmed VLC doesn't rewrite `vlcrc` on exit (md5 unchanged), so the hand-written config is stable. Details: §13. **Follow-up:** re-enable hardware decode together with Firefox's prefs (§12f) once a kernel past `7.0.12-1-cachyos` proves stable — and if `haruna`/mpv ever becomes the daily driver, pin it too (`hwdec=no`).

### Compositor renders on the Intel iGPU, not the dGPU

ℹ️ Discovery 2026-07-02 — aquamarine log: `card2` (i915) "becomes primary drm", `CDRMRenderer on renderD129`; all three monitors are iGPU connectors. Older docs' "NVIDIA-primary" framing is wrong. Consequence: `GBM_BACKEND=nvidia-drm` + `__GLX_VENDOR_LIBRARY_NAME=nvidia` in `env.conf` force Hyprland-spawned GL clients onto a dGPU that's offload-only (cross-GPU copies; often dead post-resume) — left untouched for now, evaluate removing them separately
