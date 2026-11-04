# Actual System Configuration

**Snapshot date:** 2026-05-21
**Last updated:** 2026-11-03 — history in `CHANGELOG.md`.
**Hostname:** triton500se
**User:** isalgado

This is an honest dump of the current state of the machine: hardware, OS, kernel, all installed software groups, services, configs, and the live Hyprland session. Use it as a reference snapshot before/after big changes and as a basis for replicating this setup elsewhere.

> Live config files are mirrored in `configs/` in this repo so they can be tracked in git.

---

## 1. Hardware

| Component | Spec |
|---|---|
| Model | Acer Predator PT516-52s (Triton 500 SE) |
| CPU | 12th Gen Intel Core i9-12900H (20 logical CPUs, Alder Lake) |
| iGPU | Intel Iris Xe Graphics |
| dGPU | NVIDIA GeForce RTX 3080 Ti Laptop GPU (16 GB) |
| RAM | 31 GiB DDR5 |
| Disk 1 | `nvme0n1` 953.9 GiB — CachyOS root (btrfs `/home`) + EFI (vfat `/boot`) |
| Disk 2 | `nvme1n1` 953.9 GiB — leftover Windows EFI/MSR/NTFS + old Ubuntu ext4 (unmounted, reclaim candidate) |
| Swap | 31 GiB zram (`zram0`) |
| Backlight | `nvidia_wmi_ec_backlight` (255 max, currently ~77/30%) |
| Battery | **Replacement fitted 2026-10-31.** Getac `AP20BHU`, serial `41378`, `cycle_count` 0, `energy_full` 101.67 Wh against a 99.99 Wh design (factory variance on a new pack, not drift). The original died 2026-10-12 — likely months docked at 100%, plus heat. **The 80% charge cap is now verified working**, see §15. With `BAT1` back, hypridle's battery-only suspend and lid-close-on-battery are armed again for the first time since 2026-10-12 |

### Display setup (live from `hyprctl monitors`)

| Output | Model | Native | Scale | Effective | Rate |
|---|---|---|---|---|---|
| `eDP-1` | BOE 0x0AB5 (built-in 16") | 2560×1600 | 1.25 | 2048×1280 | 240 Hz |
| desk primary | **Xiaomi Mi Monitor 27" 4K** (replaced Samsung LS24F32xG FHD 24", 2026-07-11) | 3840×2160 | 1.25 | 3072×1728 | 60 Hz |
| portable | **VCHANCE AQ16H** QHD 16" (RTK-adapter EDID) | 2560×1600 | 1.25 | 2048×1280¹ | 120 Hz |

¹ 1280×2048 (portrait) when rotated in the `read` layout.

The portable is a **VCHANCE AQ16H** (16" 16:10, ~189 PPI), running at its **native
2560×1600@120** — the top of the 21 modes it advertises. Its Realtek scaler publishes no
vendor string, so Hyprland labels it `Invalid Vendor Codename - RTK HDMI 0x01010101`
(placeholder serial); model name recorded here because that EDID string is the `desc:`
match key in `monitors.conf` and identifies nothing on its own. At scale 1.25 it lands at
~151 effective PPI, identical to `eDP-1` (same 2560×1600 over 16"); the Xiaomi at ~163 PPI
native / ~130 effective renders noticeably larger, which is expected, not a misconfiguration.

**Port names float** with plug order — currently Xiaomi = `DP-2`, portable = `DP-1`.
Both externals arrive as **DP tunnels over the single Thunderbolt connector** (Plugable
TBT4-UD5 on `typec port0`), so whichever tunnel trains first takes the low number.

Since **2026-08-03 nothing depends on the port name**: both externals are bound by EDID
**description** (`desc:` — a prefix match) — now in `lua/monitors.lua` for the geometry and
`lua/workspaces.lua` for the workspace blocks. Before that change the name-bound
`workspace = N, monitor:DP-*` rules silently put workspaces **1–3 (the primary set) on
the 16" portable** and 6–9 on the Xiaomi. ⚠ Since **2026-11-03** the live arrangement is
**not** chosen by a hotplug daemon: the profile system is parked and `lua/monitors.lua` is
the static layout — see §11 and `runbooks/monitors.md` §16. Workspaces are **per monitor**
(ten slots each, `runbooks/monitors.md` §21), not the old global 1–9 split.

The static 3-across `desktop` profile was **re-fitted for the Xiaomi on 2026-08-03**
(logical geometry): `eDP-1` 0–2048 · Xiaomi 2048–5120 (3072 wide) · portable QHD
5120–7168. Verify current descriptions with:

```bash
hyprctl monitors -j | jq -r '.[] | "\(.name) = \(.description)"'
```

---

## 2. Operating System

| Item | Value |
|---|---|
| Distro | CachyOS Linux (rolling, Arch-based) |
| Kernel (running) | `7.2.8-1-cachyos` (BORE scheduler, performance-tuned) |
| Kernel (fallback) | `linux-cachyos-lts 6.18.52-1` |
| Architecture | x86_64 |
| Bootloader | **Limine** (not GRUB) |
| EFI partition | `/dev/nvme0n1p1` 4 GiB vfat at `/boot` |
| Root subvolume | `subvol=/@` on `nvme0n1p2` btrfs |
| Init | systemd |
| Boot time | ~25s total (4.9s firmware / 5.8s loader / 0.8s kernel / 4.0s initrd / 9.5s userspace; `systemd-analyze`, 2026-11-03) |
| Display manager | **None.** `getty@tty1` drop-in autologins `isalgado` (`/etc/systemd/system/getty@tty1.service.d/override.conf`); fish login shell sources `~/.config/fish/conf.d/99-hyprland-autostart.fish`, which `exec start-hyprland` on `XDG_VTNR=1`. `plasmalogin.service` is installed but **disabled and inactive** (kept for rollback per `runbooks/boot-suspend.md` §10). |
| Session type | Wayland |
| Desktop env | Hyprland (with KDE Plasma as installer-bundled fallback) |
| Shell | Login shell is **`/bin/fish`** (per `/etc/passwd` for `isalgado`); fish, bash, zsh all installed. `$SHELL` may show `/usr/bin/zsh` inside non-login zsh subshells — that's inherited, not the login shell. See `runbooks/boot-suspend.md` §10 for the fish-based Hyprland autostart path. |
| Audio | PipeWire 1.6.9 with `pipewire-pulse` and `wireplumber`; default sink: built-in speakers (`alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Speaker__sink`) |

### Kernel command line

```
mem_sleep_default=s2idle thunderbolt.host_reset=0 nowatchdog rw rootflags=subvol=/@ root=UUID=d94a3435-f8db-4cc2-ade4-4ed01417dfd2
```

> Live from `/proc/cmdline`, 2026-11-03. **No `nvidia-drm.modeset=1`** — KMS comes from the
> driver default plus early module loading, see §3. **No `quiet splash`** — Plymouth was
> dropped from `HOOKS=` (§15). The two parameters that *are* here both exist for hardware
> bugs: `thunderbolt.host_reset=0` for the dock boot/shutdown hang
> (`runbooks/boot-suspend.md` §6) and `mem_sleep_default=s2idle` to keep resume from killing
> `nvidia_modeset` (`runbooks/boot-suspend.md` §11).
>
> These live in `KERNEL_CMDLINE[default]` in `/etc/default/limine`, which Limine applies to
> **every** entry — the main kernel, the LTS escape hatch and the Snapper snapshots alike.
> The old warning here, that the LTS entry lacked modeset params and would black-screen, was
> obsolete from 2026-07-02 and is removed: there are no modeset params on any entry, and the
> ones that exist are shared.

---

## 3. NVIDIA Stack

| Item | Value |
|---|---|
| Driver | 615.71.09 (open GSP kernel modules, via `linux-cachyos-nvidia-open`) — updated since 2026-07-02, was 610.43.02, originally 595.71.05 |
| Kernel modules loaded | `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` |
| Module package | `linux-cachyos-nvidia-open 7.2.8-1` (CachyOS-specific; not `nvidia-dkms`). Main kernel `linux-cachyos 7.2.8-1`, LTS escape hatch `linux-cachyos-lts 6.18.52-1` |
| Userspace | `nvidia-utils 615.71.09-1`, `egl-wayland`. `libva-nvidia-driver` removed 2026-07-02 (`runbooks/gpu-video.md` §12d) |
| Role | **Offload-only (discovered 2026-07-02).** The compositor and all three outputs run on the Intel iGPU — aquamarine primary DRM = `card2` (i915), renderer on `renderD129`; the dGPU (`card1`) is a secondary KMS backend whose own connectors (`eDP-2`, `HDMI-A-1`) are unused |
| KMS | ✅ enabled — `modeset` is the driver default on the 610 series, and the modules early-load from initramfs via `/etc/mkinitcpio.conf.d/10-chwd.conf` (`MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`). The kernel cmdline no longer carries `nvidia-drm.modeset=1` (verified `/proc/cmdline` 2026-07-02); the mechanism is kernel-agnostic, so it covers the LTS entry too |
| Hardware cursor | disabled in Hyprland config (`cursor.no_hardware_cursors = true` to avoid NVIDIA artifacts) |
| Wayland env vars (set in `env.conf`) | `LIBVA_DRIVER_NAME=iHD` (2026-07-02, was `nvidia`; `NVD_BACKEND=direct` dropped with the shim), `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `MOZ_ENABLE_WAYLAND=1`, `ELECTRON_OZONE_PLATFORM_HINT=auto`. ⚠ Only processes Hyprland spawns (keybinds/`exec-once`) see these — Walker/Elephant launches apps from the systemd `--user` manager, which doesn't (verified 2026-07-02: the running Firefox had none of them in its environ) |

---

## 4. Installed Packages — Hyprland Ecosystem

| Package | Version | Role |
|---|---|---|
| `hyprland` | 0.56.2-3.1 | Compositor (Wayland) |
| `hyprlock` | 0.9.6-3.1 | Lock screen |
| `hypridle` | 0.1.8-2.1 | Idle / lock / suspend daemon |
| `hyprpaper` | 0.8.4-9.1 | Wallpaper daemon |
| `hyprpolkitagent` | 0.2.0-1.1 | PolicyKit auth agent (binary at `/usr/lib/hyprpolkitagent/`) |
| `hyprshutdown` | 0.1.1-8.1 | Power menu helper |
| `xdg-desktop-portal-hyprland` | 1.4.1-2.1 | Portal (screensharing/file pickers) |

## 5. Installed Packages — UI / Daemons / Tools

| Package | Version | Role |
|---|---|---|
| `waybar` | 0.15.0-3.1 | Status bar |
| `mako` | 1.11.0-1.1 | Notifications |
| `kitty` | 0.49.1-1.1 | Terminal |
| `walker` | 2.17.1-1 | App launcher (runs as resident `--gapplication-service`; backed by Elephant — see below) |
| `elephant` *(AUR)* | 2.21.0-1 | Walker backend / provider hub. Started by `~/.config/systemd/user/elephant.service` (user-managed; AUR pkg ships no unit). |
| `elephant-desktopapplications` *(AUR)* | 2.21.0-1 | Provider — `.desktop` apps (183 indexed at last load) |
| `elephant-calc` *(AUR)* | 2.21.0-1 | Provider — calculator (`=` prefix, uses `libqalculate`/`qalc`) |
| `elephant-runner` *(AUR)* | 2.21.0-1 | Provider — `$PATH` runner (`>` prefix; 3361 executables indexed) |
| `elephant-files` *(AUR)* | 2.21.0-1 | Provider — filesystem search (`/` prefix) |
| `elephant-symbols` *(AUR)* | 2.21.0-1 | Provider — emoji/symbol picker (`.` prefix; 1948 entries) |
| `elephant-clipboard` *(AUR)* | 2.21.0-1 | Provider — clipboard history (`:` prefix; consumes `cliphist` store) |
| `elephant-websearch` *(AUR)* | 2.21.0-1 | Provider — web search (`@` prefix; default engine = upstream default until `~/.config/elephant/websearch.toml` is written) |
| `elephant-providerlist` *(AUR)* | 2.21.0-1 | Provider — meta-provider listing all loaded providers (`;` prefix) |
| `elephant-menus` *(AUR)* | 2.21.0-1 | Subsystem — custom menus via `elephant menu …`. **Note:** doesn't appear in `elephant listproviders` output by design; presence confirmed via `journalctl --user -u elephant.service \| grep 'providers loaded=menus'`. |
| `libqalculate` | 5.12.0-1.1 | Calculator backend used by `elephant-calc` |
| `yazi` | 26.9.1-2.1 | TUI file manager |
| `swayosd` | 0.3.2-1.1 | Volume/brightness on-screen popups |
| `hyprmon-bin` *(AUR)* | 0.0.17-1 (installed 2026-10-15) | TUI monitor-layout editor ([erans/hyprmon](https://github.com/erans/hyprmon), the one Omarchy's manual recommends). Used **only** as the visual editor for `monitor-mode.sh` profiles, always through `scripts/hyprmon-edit.sh`. Never `hyprmon --profile` or its `S` key (§11). ⚠ AUR `hyprmon` without `-bin` is an unrelated Rust project with the same name. PKGBUILD reviewed: installs the upstream release binary (pinned sha256), a `.desktop` and an icon. The packaged `.desktop` is shadowed by `~/.local/share/applications/hyprmon.desktop` |
| `grim` | 1.5.0-2.1 | Wayland screenshot tool |
| `slurp` | 1.5.0-2.1 | Region selection |
| `satty` | 0.22.0-1.1 | Screenshot annotation |
| `wl-clipboard` | 1:2.3.0-1.1 | Wayland clipboard |
| `cliphist` | 1:0.7.0-2.1 | Clipboard history store |
| `brightnessctl` | 0.5.1-3 | CLI backlight control |
| `pavucontrol` | 1:6.2-1.1 | Audio mixer GUI |
| `playerctl` | 2.4.1-5.1 | Media key dispatcher |
| `network-manager-applet` | 1.36.0-2.1 | NetworkManager tray icon |
| `blueman` | 2.4.6-2.1 | Bluetooth tray + GUI |
| `bluez` / `bluez-utils` | 5.86-6.1 | Bluetooth stack |

## 6. Installed Packages — Fonts / Themes

| Package | Version |
|---|---|
| `ttf-jetbrains-mono-nerd` | 3.5.1-2 |
| `noto-fonts` | 1:2026.09.01-1 |
| `noto-fonts-emoji` | 1:2.051-1 |
| `noto-fonts-cjk` | 20240730-1 |
| `papirus-icon-theme` | 20260801-1 |
| `qt5-wayland` | 5.15.19+kde+r55-1.1 |
| `qt6-wayland` | 6.11.2-1.1 |
| `qt6ct` | 0.11-8.1 |
| `kvantum` | 1.1.8-1.1 |

## 7. Installed Packages — Editors / File Managers / Browser

| Package | Version | Notes |
|---|---|---|
| `visual-studio-code-bin` | 1.121.0-1 | Primary editor (runs on Wayland). `~/.config/code-flags.conf` carries `--password-store=basic` to silence the "OS keyring couldn't be identified" notification (no Secret Service in this session) — see `runbooks/desktop-apps.md` §7f. |
| `micro` | 2.0.15-3.1 | Terminal text editor (Yazi's default for text files) |
| `dolphin` | 26.08.1-1.1 | KDE file manager (GUI fallback) |
| `firefox` | 156.0.1-1.1 | Default browser |
| `google-chrome` *(AUR)* | 150.0.7871.181-1 | Secondary browser. Installed 2026-07-23. Ships `/usr/share/applications/google-chrome.desktop` (+ `com.google.Chrome.desktop`), `Exec=/usr/bin/google-chrome-stable %U`. Unlike Obsidian, it did **not** hot-reload into Walker — elephant's desktopapplications cache was stale, so a `systemctl --user restart elephant.service` was needed to index it. Nothing added to `configs/applications/`; that mirror is only for custom entries like `shortcuts.desktop`. |
| `obsidian` | 1.13.7-2 | Markdown knowledge base / notes. Repo pkg (`extra`), installed 2026-07-08. Ships `/usr/share/applications/obsidian.desktop`, so it auto-appears in Walker — elephant hot-reloaded, no restart needed (verified via `elephant query 'desktopapplications;obsidian;5'`). Nothing added to `configs/applications/`; that mirror is only for custom entries like `shortcuts.desktop`. |
| `calibre` | 9.14.0-1.1 | E-book library manager / reader. Repo pkg, installed 2026-07-23 (pulled ~69 deps — Python/Qt stack). Ships four `/usr/share/applications/calibre-*.desktop` entries (`calibre-gui`, `-ebook-viewer`, `-ebook-edit`, `-lrfviewer`); "Calibre" (`calibre-gui.desktop`) is the main launcher. Auto-appeared in Walker — elephant hot-reloaded, no restart needed (verified via `elephant query 'desktopapplications;calibre;5'` → score 192). |

### Media players

| Package | Version | Notes |
|---|---|---|
| `vlc` | 3.0.23_2-16.1 | **Primary video player.** Installed 2026-07-31 (`vlc` + `vlc-gui-qt` + `vlc-cli` + `qt5-svg` + `qt5-x11extras` — only 5 packages, because `vlc-plugins-all` had already been installed since the original build, leaving a binary-less half-install). Ships `/usr/share/applications/vlc.desktop`; Elephant **hot-reloaded**, no restart needed (`elephant query 'desktopapplications;vlc;5'` → score 88). ⚠ Hardware decode deliberately **off** — see the note below. |
| `haruna` | 1.8.1-2.1 | Secondary video player (Qt/QML on `libmpv`, KDE). Was installed but undocumented until 2026-07-31; ships `org.kde.haruna.desktop`. Pulls `mpv 1:0.41.0-3.1` + `mpvqt`. Note: mpv/Haruna default to hardware decode too — if either becomes the daily driver, apply the same pin (`hwdec=no` in `~/.config/mpv/mpv.conf`). |
| `vlc-plugins-all` | 3.0.23_2-16.1 | Every VLC codec plugin. Predates the `vlc` install; `phonon-qt6-vlc` (KDE's multimedia backend) rides on the same libvlc, so don't remove it when uninstalling VLC. |

> ⚠ **VLC hardware decoding is pinned OFF** via `~/.config/vlc/vlcrc` (`[avcodec]` / `avcodec-hw=none`). VLC's default `avcodec-hw=any` routes VA-API → iHD → **the iGPU**, the same path that hung the video engine and tripped the i915 hang-recovery NULL deref on 2026-07-02 (§15). Firefox is pinned to software decode for the identical reason. Verified 2026-07-31 by verbose playback: `looking for hw decoder module matching "none" … no hw decoder modules matched` → software decode, kernel log clean. This can't live in `env.conf` — Walker/Elephant launches apps from the systemd `--user` manager, which never sees Hyprland's env vars. Re-enable together with Firefox's prefs once a kernel past `7.0.12-1-cachyos` proves stable: `runbooks/gpu-video.md` §13c / §12f.

> Not installed: `neovim`, `ghostty` (Ghostty is in CachyOS repos if you want to swap in for Kitty later).

### Graphics / image editing (added 2026-08-25)

| Package | Version | Notes |
|---|---|---|
| `inkscape` | 1.4.4-6.1 | **Vector editor — the tool for designing buttons/icons.** Repo pkg (`extra`), installed 2026-08-25. Draw once, export PNG at any exact size (32/64/128/512px) without resolution loss. Pulled ~21 deps (`lib2geom`, `libcdr`, `libvisio`, `libwpd`/`libwpg`, `scour`, `gsl`, `python-numpy`, `gspell`, `enchant`, `litehtml`). Ships `/usr/share/applications/org.inkscape.Inkscape.desktop` with `Name=Inkscape`, `Exec=inkscape %F`. Auto-appeared in Walker — Elephant **hot-reloaded**, no restart needed (`elephant query 'desktopapplications;inkscape;5'` → score 218, matched on `field:"text"`). |
| `gimp` | 3.2.6-2.1 | **Raster editor — crop, layers, alpha, retouch on existing PNGs.** Repo pkg (`extra`), installed 2026-08-25. GIMP 3.x line (native Wayland, single-window UI). Pulled ~10 deps (`gegl`, `babl`, `libgexiv2`, `lensfun`, `libmypaint`, `mypaint-brushes`, `suitesparse`, `libspiro`). ⚠ Walker display name is overridden — see below. |
| `graphicsmagick` | 1.3.48-1.1 | Pulled in as an Inkscape dependency, not chosen directly. Note the pre-existing `imagemagick` + `optipng` remain the CLI path for batch resize/convert/compress. |
| `blender` | 17:5.2.2-2 | **3D modeling / animation / rendering.** Repo pkg (`extra`), installed 2026-09-26, 383 MiB. Ships `/usr/share/applications/blender.desktop` with `Name=Blender`, `Exec=blender %f`. Auto-appeared in Walker, no override needed (`elephant query 'desktopapplications;blender;5'` → `text:"Blender"`, `subtext:"3D modeler"`, score 192, matched on `field:"text"`). ⚠ The packaged entry sets `PrefersNonDefaultGPU=true`, but Elephant 2.21 **ignores that key** (no reference to it in `desktopapplications.so`), so a Walker launch runs the UI/viewport on the Intel iGPU. That's the safe default here — the dGPU can be dead after resume (§15). For GPU renders, pick CUDA/OptiX under *Preferences → System → Cycles Render Devices*; that doesn't need PRIME offload. For an NVIDIA-rendered viewport, launch with `prime-run blender` from a terminal. |

> ⚠ **GIMP's Walker entry is overridden** by `~/.local/share/applications/gimp.desktop` (mirrored at `configs/applications/gimp.desktop`). The packaged `/usr/share/applications/gimp.desktop` sets `Name=GNU Image Manipulation Program`, so Walker listed it under "G-N-U…" and typing `gimp` only matched via the *subtext* (`gimp-3.2`, score 109). Because the override reuses the **same desktop ID**, it **shadows the packaged file entirely rather than merging** — so the packaged `MimeType=` line (44 types) is copied verbatim into it, or "Open with → GIMP" would silently break for the exotic formats. `Exec=gimp %U` deliberately uses the unversioned `/usr/bin/gimp` symlink (→ `gimp-3.2`) so a future 3.x bump can't break launching, unlike the packaged `Exec=gimp-3.2 %U`. Verified after writing: `elephant query 'desktopapplications;gimp;5'` → `text:"GIMP"`, `subtext:"Image Editor"`, single result, matched on `field:"text"` (score 114) — Elephant hot-reloaded the user dir, no service restart needed. `desktop-file-validate` clean.

> **Why these two and not Pinta:** Pinta (the usual lightweight Paint.NET-style pick) is AUR-only here as `pinta-git`/`pinta-gtk3-git` — a from-source .NET build, not worth the maintenance. The lighter fallback if GIMP ever feels excessive is `drawing` (4.6 MiB, in `extra`), but it has no layer support.

## 8. Installed Packages — Boot / Snapshots / Power

| Package | Version | Role |
|---|---|---|
| `limine` | 12.9.0-1 | Bootloader |
| `limine-mkinitcpio-hook` | 1.39.0-1 | Auto-regenerates `/boot/limine.conf` on kernel updates |
| `limine-snapper-sync` | 1.32.0-1 | Adds snapper snapshots as bootable Limine entries |
| `snapper` | 0.13.2-1.1 | btrfs snapshot manager (root config: `root`) |
| `snap-pac` | 3.0.1-3 | Automatic snapshots on pacman transactions |
| `btrfs-progs` | 7.1-1 | btrfs userspace tools |
| `plymouth` | 26.134.222-2.1 | Boot splash. **Removed from mkinitcpio `HOOKS=` on 2026-05-22** for TB boot fix (Section 6.0). Shutdown units (`plymouth-quit`, `-quit-wait`, `-poweroff`, `-reboot`) also masked. Package retained for possible future reintroduction. |
| `power-profiles-daemon` | 0.30-3 | Power profile switching (not TLP, not auto-cpufreq) |
| `acer-wmi-battery-dkms` | 0.2.0-2 (AUR) | Out-of-tree driver for Acer's battery-health WMI interface. Caps charging at 80% through `enable_health_mode=1` in `/etc/modprobe.d/acer-wmi-battery.conf` (mirror: `configs/modprobe.d/`). Installed 2026-10-12 and autoloads at boot. **Verified working 2026-10-31** with the replacement pack: charging stops at 80% (§15) |
| `dkms` | 3.4.3-1 (`cachyos` repo) | Rebuilds `acer-wmi-battery` for both kernels on every kernel or headers update, and adds `LLVM=1` by itself for the clang-built main kernel. Pulled in on 2026-10-12 as a dependency |

## 9. Installed Packages — Counts

| | Count | Regenerate with |
|---|---|---|
| Explicitly installed (user-requested) | 280 | `pacman -Qe \| wc -l` |
| Total installed (with dependencies) | 1533 | `pacman -Q \| wc -l` |
| Foreign / AUR | 15 | `pacman -Qm \| wc -l` |

Live as of 2026-11-03. Full lists: `pacman -Qe`, `pacman -Qm`.

`litehtml0.9 0.9-2.1` shows up under `pacman -Qm` but is **not** an AUR package: it was
installed 2026-06-16 as a dependency, nothing requires it any more, and it has since left
the sync repos — so it reads as foreign. Still an orphan and a removal candidate
(confirmed 2026-11-03; `pacman -Qdtq` lists it).

The per-recount history that used to live in this section is in `CHANGELOG.md`.

---

## 10. Running Daemons (live)

Captured via `pgrep -af`:

| Daemon | Started via |
|---|---|
| `waybar` | `exec-once = waybar` (autostart.conf) |
| `mako` | `exec-once = mako` |
| `hyprpaper` | `exec-once = hyprpaper` |
| `hypridle` | `exec-once = hypridle` |
| `hyprpolkitagent` | `exec-once = systemctl --user start hyprpolkitagent.service` |
| `swayosd-server` | `exec-once = systemctl --user start swayosd.service` (autostart.conf). **Changed 2026-06-17** from a bare `exec-once = swayosd-server`: swayosd 0.3.1 SIGABRTs on every monitor-set change (gtk4-layer-shell re-init on the GdkDisplay "monitors changed" signal), so the `read` profile disabling eDP-1 — or any hotplug — killed it, and a bare exec-once never came back, taking the volume/brightness OSD and the media keys with it. Now a `Restart=always` user unit at `~/.config/systemd/user/swayosd.service` (mirrored in `configs/systemd/user/`); `monitor-mode.sh` also restarts it after each switch. See §15. |
| `wl-paste --type text --watch cliphist store` | autostart |
| `wl-paste --type image --watch cliphist store` | autostart |
| `nm-applet --indicator` | autostart |
| `monitor-autoswitch.sh` (+ child `socat` on `.socket2`) | `exec-once = ~/.config/hypr/scripts/monitor-autoswitch.sh` (autostart.conf). Long-lived; auto-selects the monitor profile (`trio` / `read` / `onescreen` / `laptop`) on each hotplug event. See §11 "Monitor profiles & auto-switching". Added 2026-06-10. |
| `power-autoswitch.sh` | `exec-once = ~/.config/hypr/scripts/power-autoswitch.sh` (autostart.conf). Long-lived 5 s poll loop, single-instance. On battery: eDP-1 to `2560x1600@60` + platform profile `power-saver`. On AC: 240 Hz + the profile saved before. Publishes `$XDG_RUNTIME_DIR/triton-power-mode` (incl. its own `pid`) for Triton Panel, which toggles it via `~/.config/triton-panel/power-auto` + SIGUSR1. Added 2026-10-31; see §11 and `runbooks/power-battery.md` §19. |
| `walker --gapplication-service` | autostart (resident service for fast launches) |
| `elephant` | `exec-once = systemctl --user start elephant.service` (autostart.conf). The user unit at `~/.config/systemd/user/elephant.service` exists (written 2026-05-23; AUR pkg ships none) but is `WantedBy=graphical-session.target`, which **never activates** under this getty-autologin + `start-hyprland` session — so it's started explicitly from autostart.conf instead (fixed 2026-05-26; before that Walker hung on "Waiting for elephant"). Backs every Walker prefix/`-m <mode>` invocation. |
| `polkitd` | system (PolicyKit daemon) |
| `xdg-desktop-portal` + `xdg-desktop-portal-hyprland` | systemd user units |
| `pipewire`, `pipewire-pulse`, `wireplumber` | systemd user units (audio) |

All Hyprland-side autostarts are live and producing visible output (bar, wallpaper, tray icons).

---

## 11. Hyprland Config Layout

**The config is Lua since 2026-11-03** — Hyprland 0.57.1 removed the `hyprlang` parser, so
the `.conf` files below are **inert** and kept for reference only (`runbooks/updates.md` §4).
All under `~/.config/hypr/` and mirrored in this repo at `configs/hypr/`:

```
hyprland.lua       ← entrypoint: sets package.path from its own path, requires lua/
lua/env.lua        ← NVIDIA + Qt + cursor env vars (hl.env), software cursors
lua/monitors.lua   ← the ONLY owner of geometry now: static 3-across, scale 1.25
lua/workspaces.lua ← per-monitor workspace blocks (runbooks/monitors.md §21)
lua/input.lua      ← keyboard layout, touchpad, 3-finger gesture
lua/look.lua       ← Catppuccin Mocha colors, dwindle, animations, blur+shadow, groupbar
lua/windowrules.lua← floats for dialogs (pavucontrol, blueman, polkit, PiP) + the terminal tag
lua/qconsole.lua   ← the Quake console's special workspace, dim and per-monitor refit
lua/bind.lua       ← bind(keys, description, action) — the description feeds Super+K
lua/bindings-apps.lua       ← terminal, browser, launcher, file manager, close, exit
lua/bindings-tiling.lua     ← tiling, workspaces, monitors, groups, scratchpad, console
lua/bindings-utilities.lua  ← cheatsheet, lock, notifications, toggles, zoom, capture, lid, media
lua/bindings-clipboard.lua  ← universal clipboard (Super+C/V/X/A)
lua/autostart.lua  ← hl.on("hyprland.start") for all daemons
hyprpaper.conf     ← block-syntax wallpaper bindings (workaround for 0.8.4 parser bug)
hyprlock.conf      ← Catppuccin password input + big clock + blurred wallpaper
hypridle.conf      ← 5m lock / 10m DPMS / 20m suspend
*.conf (the rest)  ← INERT: env/monitors/input/look/keybindings/windowrules/autostart and the
                     monitors-read / monitors-trio profiles. Nothing reads them
scripts/monitor-mode.sh        ← apply a named layout: desktop|read|laptop|onescreen|trio|toggle
scripts/monitor-autoswitch.sh  ← daemon: auto-picks layout from connected displays (autostart.conf)
scripts/power-autoswitch.sh    ← daemon: follows the power source — 60 Hz + power-saver on battery,
                                 240 Hz + the previous profile on AC (autostart.lua; added 2026-10-31)
scripts/edp-rate.sh            ← the only owner of eDP-1's refresh rate; applies with `hyprctl eval`
                                 (added 2026-11-03, lifted out of the parked monitor-mode.sh)
scripts/monitor-menu.sh        ← Walker dmenu "Setup > Monitors": fitting profiles · Hyprmon editor · live layout (Super+Shift+M and the "Monitors" Walker entry; added 2026-10-15)
scripts/hyprmon-edit.sh        ← launches hyprmon as the profile editor with its config write + reload neutered (added 2026-10-15)
scripts/show-shortcuts.sh      ← keybinding cheatsheet in a floating Kitty window, GENERATED from
                                 `hyprctl binds -j` descriptions (Super+K, Super+/ and the "Shortcuts"
                                 Walker entry; added 2026-06-17, made generated 2026-11-03)
```

Outside `~/.config/hypr/`: `~/.config/hyprmon/profiles/{desktop,read}.json` (mirrored in `configs/hyprmon/profiles/`) hold the Hyprmon-edited geometry for those two profiles.

**⚠ The monitor profile system is parked (2026-11-03).** `monitor-mode.sh`,
`monitor-autoswitch.sh`, `monitor-menu.sh` and `hyprmon-edit.sh` all drive the layout through
`hyprctl keyword`, which 0.57.1 removed. They are not started and no key is bound to them;
`lua/monitors.lua` holds the geometry and there is no profile switching or hotplug reconcile.
`runbooks/monitors.md` §16 has the port plan.

**eDP-1's refresh rate has exactly one owner (since 2026-10-31, re-homed 2026-11-03):**
`scripts/edp-rate.sh`, which resolves `2560x1600@240` or `@60` from the power source and the
`~/.config/triton-panel/power-auto` toggle. Every site that emits an eDP-1 spec calls it —
there is no `2560x1600@240` literal left in that script, and `apply_from_profile` overrides
eDP-1's Hz with `--argjson edphz` because the hyprmon JSON carries `240.00301` (the profiles
were saved while docked on AC). Before this, the rate was hardcoded at 8 sites plus that 9th
JSON path, so anything setting it from outside was undone by the next profile apply, hotplug
autoswitch or `hyprctl reload`. `edp-rate.sh` is the reconcile hook
`power-autoswitch.sh` calls; it is not a layout and deliberately touches neither `$STATE` nor
the fingerprint handshake. See `runbooks/power-battery.md` §19.

### Monitor profiles & auto-switching (added 2026-06-10) — ⚠ PARKED 2026-11-03

> Kept as the description of what the profile system does, and what the port has to restore.
> None of it is running: see the note above and `runbooks/monitors.md` §16.

`monitors.conf` still defines the static 3-across "desktop" layout, but the live layout
is now driven by **`scripts/monitor-autoswitch.sh`**, a daemon launched from
`autostart.conf` (`exec-once`). It listens to Hyprland's `.socket2` for monitor
hotplug events and applies a profile based on what is connected:

| Connected displays | Auto-applied profile | Arrangement (left → right) |
|---|---|---|
| Two externals incl. the **demoset** FHD portable | **`trio`** (added 2026-07-08) | FHD portable · **laptop (center)** · portable QHD — all landscape |
| Two externals otherwise (desk external + portable QHD) | **`read`** | desk external landscape (now the **Xiaomi 27" 4K** @ 3072×1728, scale 1.25) · portable QHD **rotated 270° (portrait)** · **laptop OFF** |
| Exactly one external | **`onescreen`** | that external (landscape) · laptop |
| No externals (integrated only) | **`laptop`** | `eDP-1` alone at `0×0` |
| — | **`desktop`** | **never auto** — manual only, via `Super+M` |

Externals are counted as "any monitor that isn't `eDP-1`"; the demoset portable is matched by its EDID `description` (not by port name).

- Geometry for every profile lives in **`scripts/monitor-mode.sh`** (single source of
  truth; the daemon only decides *which* profile to call). It can also be run by hand:
  `~/.config/hypr/scripts/monitor-mode.sh {desktop|read|laptop|onescreen|trio}`.
- **All** profiles **resolve the externals by capability, not port name** (the QHD portable
  is whichever external can do `2560×1600`; the other external takes its best
  resolution+refresh). This keeps them correct on the road, where DP-1/DP-2 shift with plug
  order. **Extended to `desktop` and `onescreen` on 2026-08-03** — until then both
  hardcoded the retired Samsung's `DP-1 1920×1080@120 scale 1`, so any panel that happened
  to enumerate as `DP-1` was forced to 1080p at the wrong scale. `read`'s no-QHD fallback
  was rewritten at the same time and no longer disables `eDP-1` when there is no external
  to fall back to (that path could black the session when `read` was reached via `Super+M`).
- **`Super+M`** (in `keybindings.conf`) toggles manually: **read ↔ desktop** at the desk,
  **read ↔ trio** on the road (it prefers `trio` over `desktop` when the demoset FHD
  portable is connected). A manual choice holds until the next *external* hotplug event,
  when the daemon re-asserts the automatic profile. `eDP-1` add/remove events are ignored,
  so toggling the laptop panel between profiles isn't instantly reverted.
- `read` rotates the QHD portable with `transform, 3` → 1280×2048 logical column for
  reading pages (laptop off). `trio` is both 16" portables plus the laptop, three across
  with the laptop centered. `onescreen` keeps whichever single external in landscape.
- **Rotation changes go through `apply_monitor_tf()` (added 2026-08-04).** Hyprland applies
  a `transform` given by `hyprctl keyword monitor` to an *already-enabled* output to the
  render pass only — the monitor's **layout box keeps its pre-rotation dimensions**, so the
  tiling engine hands out landscape geometry on a portrait panel (a window came out
  2028×1224 on the AQ16H's 1280×2048 screen, overflowing 758px past the right edge) while
  `hyprctl monitors` reported `transform 3` throughout. The bug is **symmetric** — leaving
  portrait strands a 1280×2048 box on a 2048×1280 screen — so *every* profile that sets the
  AQ16H's transform routes through the helper, including the ones wanting `transform 0`.
  Only a **disable → re-enable cycle** rebuilds the box; `forcerendererreload`,
  `moveworkspacetomonitor`, and re-applying the identical spec were each verified **not** to
  work. The helper cycles **only when the transform actually changes**.
- State is tracked in `$XDG_RUNTIME_DIR/hypr-monitor-mode`; the daemon re-applies when the
  desired profile differs from the current one **or when a monitor was added** (a returning
  output is configured from `monitors.conf`, so an unchanged profile name would otherwise
  leave the wrong geometry on screen). At startup it applies **unconditionally**, because
  the state file survives a compositor restart (`Super+Shift+Q`).
- **Debounced since 2026-08-03.** The daemon no longer reacts to each raw `.socket2` event
  after a flat `sleep 0.5`. An event burst is coalesced (`SETTLE=2 s` of socket quiet), then
  the monitor set must produce two identical fingerprints `CONFIRM=1 s` apart before any
  profile is applied. Rationale: both externals are DP tunnels over one Thunderbolt
  connector, and anything that upsets it drops and restores them within a second or two —
  the old loop turned that blink into `remove → apply 'onescreen' → add → apply 'read'`,
  forcing wrong geometry on the way through and scattering workspaces. See the dedicated
  §15 row. Cost: a real plug/unplug now takes ~3 s to take effect instead of ~0.5 s.
- **Self-inflicted hotplug events are filtered (added 2026-08-04).** `apply_monitor_tf`'s
  output cycle posts external `monitorremoved`+`monitoradded`, indistinguishable from a
  replug at the socket. Unfiltered, a manual `Super+M` → `desktop` would un-rotate the
  AQ16H, wake the daemon, and `desired_mode()` — which always answers `read` for two desk
  externals — would drag the layout back to `read` ~3 s later. `monitor-mode.sh` therefore
  records the monitor set it finished with in `$XDG_RUNTIME_DIR/hypr-monitor-fingerprint`
  **only when it actually cycled**, deleting the file otherwise; the daemon skips a settled
  burst when that file is both **fresh** (`SELF_GRACE=15 s`) **and matches** the current set.
  A real unplug changes the set and is still acted on inside the grace window; a display
  blink writes no fingerprint at all, so it still gets the forced re-apply it needs.
- `monitors.conf` binds monitors **and workspaces** by EDID `desc:` prefix rather than
  `DP-*` (2026-08-03) — see §1.
- **Hyprmon-edited profiles (added 2026-10-15).** Hyprmon is the visual **editor**,
  `monitor-mode.sh` stays the **applier**. Arrange the screens in Hyprmon, then save with `P`
  under a mode's name. The profile lands in `~/.config/hyprmon/profiles/<mode>.json`, and
  `P` writes only that JSON: no config write, no reload (checked in hyprmon 0.0.17's
  `saveProfile`). `apply_from_profile` in `monitor-mode.sh` uses it **only when the
  profile's monitor set equals the connected set**. Monitors are matched by hyprmon's own
  `hardware_id`, built from the EDID as `make/model/serial`, or `make/model` when the serial
  is empty. Here those are `BOE/0x0AB5`, `Xiaomi Corporation/Mi Monitor/6638000034671` and
  `Invalid Vendor Codename - RTK/HDMI/0x01010101`. Port names never enter into it. Any
  mismatch, unreadable JSON or missing file returns 1, and the hand-written capability-based
  `apply_<mode>` runs instead, so an unknown hotel monitor still gets `onescreen`. Every
  active output goes through `apply_monitor_tf` with the transform spelled out, so the
  rotation cycle and the `$FPFILE` handshake are unchanged. `vrr`/`bitdepth`/`cm` in the
  JSON are ignored on purpose. The notification says "(hyprmon profile)" when the JSON path
  ran. Seeded on 2026-10-15: `desktop` and `read`, generated from the existing geometry.
  The dry run emitted the same `hyprctl` specs as the hand-written code. `trio`, `onescreen`
  and `laptop` have no JSON: the demoset portable wasn't connected to capture its EDID, and
  `onescreen` is generic by nature.
  - **Why not hyprmon's own profile switching.** In 0.0.17, `applyProfile` and the `S` key
    set the transform with a bare `hyprctl keyword monitor` (the stale-layout-box bug above).
    They then rewrite the `monitor=` lines of `hyprland.conf`: ours has none, so hyprmon
    *appends* port-bound lines after the `source` lines. A `.bak.<timestamp>` copy is left
    behind and never pruned, only the profile's monitors are written, and every switch ends
    with `hyprctl reload`. hyprmon also has no hotplug auto-switching (still on its roadmap).
  - **`hyprmon-edit.sh`** launches it in a floating Kitty (`class hyprmon-edit`). It sets
    `HYPRLAND_CONFIG` to `~/.local/state/hyprmon/scratch.conf`, which nothing sources. It
    also puts a `hyprctl` shim first in `$PATH` that turns `reload` into a no-op plus a
    notification, and passes every other call through; hyprmon resolves `hyprctl` through
    `$PATH` at every call site. On quit it re-applies the current mode from `$STATE`. The
    packaged `hyprmon.desktop` (`Exec=uwsm app -- hyprmon`) is shadowed by a same-ID override
    pointing at the wrapper.
  - **Residual gaps:** switching an *external* off with Hyprmon's `A` looks like an unplug,
    so the daemon re-applies a profile ~3 s later. Toggling a monitor off/on and then
    rotating it back to the profile's transform can leave a stale layout box that the quit
    re-apply can't detect; `Super+M` twice fixes it.
- **Monitors menu (added 2026-10-15)**, after Omarchy's *Setup > Monitors*:
  `scripts/monitor-menu.sh`, a `walker --dmenu` list of the profiles that fit the connected
  set (current one marked) plus *Edit layout (Hyprmon)* and *Show current layout*. Bound to `Super+Shift+M`
  and exposed as the "Monitors" Walker entry (`~/.local/share/applications/monitors.desktop`).
  Walker-launched copies run under the systemd `--user` manager, and `hyprctl` works there
  because `HYPRLAND_INSTANCE_SIGNATURE` is in that environment (checked with
  `systemctl --user show-environment`).
- **Live-verified 2026-10-15**, with the repo pushed to live and the JSON path active:
  - `read`: Xiaomi `0,0`, AQ16H `3072,0 transform 3`, eDP-1 off; a test window on WS 7
    came out `1260×1992` (portrait).
  - `desktop`: `0 / 2048 / 5120`, all `transform 0`; the test window came out `2028×1224`
    (landscape). The daemon did **not** revert it within 15 s.
  - Back to `read`: the same values again, workspaces back in place, swayosd active.
  - Mismatched, corrupt or partial JSON profiles fell back to the hand-written path (dry run
    with a stub `hyprctl`).
  - **Side observation:** copying the `.conf` files to live triggered Hyprland's
    auto-reload, which did snap the screens to the `monitors.conf` boot geometry (eDP-1 on,
    AQ16H landscape at 5120) while `$STATE` still said `read`. Re-applying the profile fixed
    it. Any edit to a sourced Hyprland file does this.

## 12. Other Configs

```
~/.config/waybar/config.jsonc   ← bar layout + module configs (Catppuccin colors)
~/.config/waybar/style.css      ← bar CSS (purple workspace highlight, JetBrainsMono)
~/.config/kitty/kitty.conf      ← JetBrainsMono 12pt, 0.95 opacity, includes Catppuccin theme
~/.config/kitty/themes/Catppuccin-Mocha.conf  ← official Catppuccin theme file
~/.config/walker/               ← EMPTY (running on Elephant defaults; pin prefixes/providers via `runbooks/desktop-apps.md` §7e.iv if desired)
~/.config/elephant/             ← EMPTY (per-provider configs optional; §7e.v swaps websearch engine to DuckDuckGo when written)
~/.config/systemd/user/elephant.service  ← user unit written 2026-05-23 to start the Elephant hub (AUR pkg ships no unit; see §7e.ii)
~/.config/yazi/                 ← EMPTY (using upstream defaults — image previews via Kitty auto-detected)
~/.config/mako/                 ← EMPTY (using upstream defaults)
~/.config/fish/                 ← shell config exists (config.fish, conf.d/, functions/)
```

---

## 13. Bootloader Detail (Limine + Snapper)

- Limine reads `/boot/limine.conf` (root-readable only).
- `limine-mkinitcpio-hook` regenerates entries when a kernel/initramfs changes.
- `limine-snapper-sync` adds bootable entries for each btrfs snapshot under `subvol=/@/.snapshots/<N>/snapshot`.
- Persistent kernel cmdline params live in `/etc/default/limine` (preferred) — direct edits to `/boot/limine.conf` are wiped on next regen.
- Current entries (live snapshot):
  - The cmdline is **shared by every entry**: `KERNEL_CMDLINE[default]` in
    `/etc/default/limine` holds `nowatchdog rw rootflags=subvol=/@ root=UUID=…`,
    `thunderbolt.host_reset=0` and `mem_sleep_default=s2idle` (verified 2026-11-03).
  - No entry carries `nvidia-drm.modeset=1` any more, and none needs to — see §3. The
    2026-05 claim here, that the LTS entry was missing modeset params and would
    black-screen Hyprland, was obsolete from 2026-07-02 and is removed.
  - ⚠ Per-entry contents are **not re-verified** in this snapshot: `/boot/limine.conf` is
    root-readable only. `/etc/default/limine` is the source of truth for the cmdline; read
    the generated entries with `sudo grep cmdline /boot/limine.conf`.
  - The LTS entry still has not been **boot-tested** (§15).

---

## 14. Display Manager Reality Check

- The plan in `archive/cachyos-hyprland-setup.md` section 7 talks about forcing **SDDM** into X11 mode. **SDDM is not installed.** `/etc/sddm.conf` is a leftover stub.
- This system **previously** ran **plasma-login-manager** (`plasmalogin.service`). It was disabled on 2026-05-22 per `runbooks/boot-suspend.md` §10 to eliminate the phantom-cursor handoff bug; the package is still installed for rollback but the unit is `disabled` and `inactive`.
- **Current launch path:** `getty@tty1` drop-in (`/etc/systemd/system/getty@tty1.service.d/override.conf`) autologins `isalgado`; fish login shell runs `~/.config/fish/conf.d/99-hyprland-autostart.fish`, which `exec start-hyprland` (the package-shipped wrapper at `/usr/bin/start-hyprland`) on tty1 when no Wayland session is already attached.
- **Why `start-hyprland` not `Hyprland`:** Hyprland ≥ 0.53 emits a startup warning when launched bare; the wrapper sets up the systemd user session, D-Bus activation, and XDG session vars before exec'ing the compositor. Launching the compositor directly leaves `XDG_SESSION_TYPE=tty`, no `XDG_CURRENT_DESKTOP`, and breaks portals / polkit prompts / screen sharing for some apps. Fixed 2026-05-23. ⚠ Only half of that reaches the systemd `--user` manager: Hyprland gives its own children `XDG_SESSION_TYPE=wayland`, but its automatic env import skips that variable, so Walker/Elephant-launched apps didn't see a Wayland session until `autostart.conf` pushed it explicitly (2026-09-28, Discord screen-share row in §15).

---

## 15. Outstanding Issues

Running todo list. A row is a **status line only** — the reasoning behind it lives in the
owning runbook under *Issue history*, which is what the `→` points at. Move an item to ✅
when resolved; never delete one.

| Item | Status |
|---|---|
| Hyprland NVIDIA black-screen | ✅ Resolved (KMS + env vars) |
| Hyprland autostart daemons | ✅ All running (polkit fixed via systemd unit; hypridle started; nm-applet installed) |
| Waybar Catppuccin config | ✅ Applied (`~/.config/waybar/config.jsonc` + `style.css`) |
| Hyprpaper wallpaper binding | ✅ Resolved via block syntax (workaround for 0.8.4 config parser bug — see GitHub hyprwm/hyprpaper#204 + Arch forum thread) |
| Hyprlock styling | ✅ Catppuccin theme applied |
| Hypridle timeouts | ✅ Configured (5/10/20 min). **2026-07-12:** the 20-min suspend listener is now **battery-only** (`grep -q Discharging /sys/class/power_supply/BAT1/status && systemctl suspend` → `runbooks/boot-suspend.md`, *Issue history* |
| qt6ct env var | ✅ Package installed, env var valid |
| Kitty Catppuccin theme | ✅ Applied |
| Yazi config | ✅ Working on defaults (no custom config needed; image previews via Kitty auto-detected) |
| Walker config | ✅ Elephant-backed (2026-05-23) → `runbooks/desktop-apps.md`, *Issue history* |
| VS Code OS-keyring notification | ✅ Resolved — `~/.config/code-flags.conf` sets `--password-store=basic` so VS Code skips the missing Secret Service backend (no keyring daemon in this Hyprland session). Trade-off: secrets stored in an obfuscated local file, not keyring-encrypted. Details + revert path: `runbooks/desktop-apps.md` §7f. |
| HiDPI scaling | ✅ Scale 1.25 on eDP-1, the portable QHD, and (since 2026-07-11) the Xiaomi 27" 4K (`3840×2160` → 3072×1728); positions recalculated |
| LTS kernel cmdline | 🔧 Reframed 2026-07-02 → `runbooks/boot-suspend.md`, *Issue history* |
| Thunderbolt boot hang | ✅ Resolved 2026-05-22 — `thunderbolt.host_reset=0` on `linux-cachyos` cmdline, `plymouth` removed from `HOOKS=`, `quiet splash` dropped. TB4 dock now boots cleanly. Details: `runbooks/boot-suspend.md` §6.0. ⚠ LTS entry still missing the same param. |
| `quiet splash` / plymouth regression | ✅ Re-reverted 2026-06-11 → `runbooks/boot-suspend.md`, *Issue history* |
| Thunderbolt shutdown hang | ✅ Resolved 2026-05-22 — `nvidia-{suspend,resume,hibernate}` enabled; `NVreg_PreserveVideoMemoryAllocations=1` + `/var/tmp` spill via `/etc/modprobe.d/nvidia-power-management.conf`; Plymouth shutdown units masked; `DefaultTimeoutStopSec=15s` (diagnostic). Details: `runbooks/boot-suspend.md` §6.0. |
| NVIDIA black-screen on resume from suspend | 🔧 Fix applied 2026-05-26 → `runbooks/boot-suspend.md`, *Issue history* |
| Leftover Windows/Ubuntu partitions | ℹ️ Intentionally retained — `nvme1n1p3` (NTFS 559 GiB) + `nvme1n1p4` (ext4 393 GiB) keep other OS docks/data. Cleanup section removed from the remediation doc on 2026-05-22 (now `archive/install-remediation-2026-05.md`). |
| SDDM X11 workaround | N/A — no display manager (boot via `getty@tty1` autologin + fish `exec start-hyprland`); `plasmalogin` disabled 2026-05-22 per `runbooks/boot-suspend.md` §10 |
| Phantom `DP-0` EDID warning at boot | ℹ️ Benign — NVIDIA logs `nvidia-modeset: WARNING: GPU:0: Unable to read EDID for display device DP-0` because nothing is plugged into that connector. The three real outputs (`eDP-1`, `DP-1`, `DP-2`) come up cleanly. No action needed. |
| Desktop 3-across profile not re-fitted for the Xiaomi | ✅ Resolved 2026-08-03 → `runbooks/monitors.md`, *Issue history* |
| Rotated panel tiled with landscape geometry | ✅ Resolved 2026-08-04 → `runbooks/monitors.md`, *Issue history* |
| RTK HDMI adapter reports garbage EDID | ℹ️ Hyprland shows `Invalid Vendor Codename - RTK HDMI 0x01010101` for the portable QHD → `runbooks/monitors.md`, *Issue history* |
| Volume/brightness OSD + media keys dead after a monitor switch | ✅ Resolved 2026-06-17 → `runbooks/desktop-apps.md`, *Issue history* |
| Firefox freeze 2026-07-02 21:10 — whole session wedged | 🔧 Mitigated 2026-07-02 → `runbooks/gpu-video.md`, *Issue history* |
| Nothing reacted to the power source | ✅ Resolved 2026-10-31; **AC steady state verified 2026-11-03** (240 Hz + `balanced` + empty `saved_profile`). ⚠ The plug/unplug **transition** is still untested — no longer blocked on a charger → `runbooks/power-battery.md` §19 |
| `plymouthd` spinning forever with nothing to draw | ✅ **Resolved 2026-11-02** → `runbooks/boot-suspend.md`, *Issue history* |
| Fingerprint reader never used | ✅ **Resolved 2026-11-01** → `runbooks/fingerprint.md`, *Issue history* |
| Fingerprint unlock dies ~3 min into every lock | ⚠ Open 2026-11-03 — measured, no finger involved → `runbooks/fingerprint.md` §20t, *Issue history* |
| Panel scored an untouched pad every 10 s | ✅ **Resolved 2026-11-03** — presence measured, counting rule moved → `runbooks/fingerprint.md` §20u, *Issue history* |
| Fingerprint **verify** fails 7/7 | ⚠ Open 2026-11-03 — all `no-match` with minutiae extracted, so it is the template → `runbooks/fingerprint.md` §20m, §20q, §20u, *Issue history* |
| ⚠ **Enrolment blocked: protocol error between stages** | ⚠ Open 2026-11-03 — **cause found in `elan.c`**: the sensor's documented `0x00`/`0xaf` ("not ready" / "finger removed or sensor busy") are retried only for `ELAN_0C58` and are fatal for `0c4f`. Patch written, **not applied** — the 2026-11-03 upgrade ran, so what is owed is the reboot and four build packages → `patches/README.md`, `runbooks/fingerprint.md` §20w, §20x |
| ⚠ **Zero prints enrolled** | ⚠ Open 2026-11-03 — the 6/6 print was destroyed by starting an enrolment into its own slot; hyprlock switch turned itself **off** when the last print went → `runbooks/fingerprint.md` §20v, *Issue history* |
| Enroll window blocked its own recovery (Calibrate with no print, false "not claimed", log lost under Walker) | ✅ **Resolved 2026-11-03** → `runbooks/fingerprint.md` §20v, *Issue history* |
| Same-press gate swallowed driver faults + the thermal lockout | ✅ **Resolved 2026-11-03** → `runbooks/fingerprint.md` §20v, *Issue history* |
| i915 NULL deref in `__gen8_ppgtt_clear` during GPU-hang recovery | ⚠ Open → `runbooks/gpu-video.md`, *Issue history* |
| NVIDIA GSP "Reset required" after s2idle resume | ⚠ Open → `runbooks/boot-suspend.md`, *Issue history* |
| VLC not installed (video playback) | ✅ Resolved 2026-07-31 → `runbooks/gpu-video.md`, *Issue history* |
| Compositor renders on the Intel iGPU, not the dGPU | ℹ️ Discovery 2026-07-02 → `runbooks/gpu-video.md`, *Issue history* |
| Discord screen share can't capture the screen / Wayland windows | 🔧 Fix applied 2026-09-28, pending a live share test → `runbooks/desktop-apps.md`, *Issue history* |
| Plugging a USB device (Kobo e-reader) reshuffles the monitor layout | ✅ Resolved 2026-08-03 → `runbooks/monitors.md`, *Issue history* |
| logind lid drop-in committed but never installed | ✅ Resolved 2026-10-12 → `runbooks/boot-suspend.md`, *Issue history* |
| Laptop battery failed; 80% charge cap for the replacement | ✅ **Resolved 2026-10-31** → `runbooks/power-battery.md`, *Issue history* |
| Monitor layouts only editable as hand-written coordinates | ✅ Resolved 2026-10-15/16. → `runbooks/monitors.md`, *Issue history* |
| No fan RPM and no platform profile on this model | ✅ **Resolved 2026-10-31, reboot-verified 2026-11-03** — `predator_v4`=`Y` after a real boot, 5 profile states, `acer-isa-0ace` reading fans and temps, ppd mapping confirmed → `runbooks/power-battery.md` §17 |
| All of this only reachable from a terminal | ✅ **Resolved 2026-10-31, fully installed 2026-11-03** — the last outstanding piece, the sudoers rule, is live (`sudo -ln`) → `runbooks/triton-panel.md` §18 |
| Update backlog and `.pacnew` drift | ⚠ **Open 2026-11-03, partly cleared the same day.** ✅ The backlog is gone — `paru -Syu` moved **662 packages** at 18:47 (kernel 7.3.1, NVIDIA 615.78.08); ✅ `paccache.timer` enabled. ⚠ Still open: the **reboot** the new kernel needs, **11 `.pacnew`** unmerged — none added by this upgrade; the one that matters is `/etc/pam.d/sudo.pacnew` (2026-06-17, owned by `sudo`), which drops the `pam_fprintd` line — `snap-pac` at defaults so the kernel snapshot has no protected quota, and the rollback path still **never once booted**. *Found 2026-11-03: 648 pending, last upgrade 2026-09-26, 12 `.pacnew` with the oldest from April 2026.* → `runbooks/updates.md` |
| Hyprland is retiring `hyprlang` for a Lua config | ✅ **Resolved 2026-11-03** — 0.57.1 removed the parser; the config is now `hyprland.lua` + `lua/*.lua`, with Omarchy's keymap. Three of this repo's own predictions were wrong → `runbooks/updates.md` §4, §4g |
| ⚠ **Monitor profile system parked by the Lua migration** | ⚠ Open 2026-11-03 — 12 `hyprctl keyword` call sites to port; `lua/monitors.lua` is the static geometry meanwhile → `runbooks/monitors.md` §16 |
| ⚠ **The new monitor config is unverified with the externals** | ⚠ Open 2026-11-03 — the dock was disconnected all migration; only eDP-1 was exercised → `runbooks/monitors.md` §21 |
| `hyprpicker` missing for the new `Super+Print` bind | ⚠ Open 2026-11-03 — waits for the next full `paru -Syu` → `runbooks/updates.md` §1 |

---

## 16. Repo Layout

Restructured 2026-11-03 — three kinds of document, one owner per subsystem. The
conventions are in `README.md`; the move itself and the old-section mapping are in
`CHANGELOG.md`.

```
cachyPool/
├── README.md                          ← what this is, the map, the documentation conventions
├── CHANGELOG.md                       ← append-only live-state history, newest first
├── CLAUDE.md                          ← rules for Claude Code in this repo (imperatives + pointers)
├── ACTUAL-CONFIGURATION.md            ← this file: what the machine IS now. No history.
├── shortcuts.md                       ← daily driving: keybindings, workflows, Walker/Yazi/Kitty
├── runbooks/                          ← one per subsystem: failure → diagnosis → fix → verify
│   ├── README.md                      ← index, the preserved-§-numbers rule, the fish heredoc note
│   ├── bluetooth.md                   ← WH-1000XM4 pairing, br-connection-key-missing, why no LDAC
│   ├── boot-suspend.md                ← §0 §6 §10 §11 §15: Limine cmdline, TB hang, autologin, s2idle, lid
│   ├── desktop-apps.md                ← §7 §8: kitty/yazi/hyprlock polish, Walker+Elephant, VS Code keyring
│   ├── fingerprint.md                 ← §20: the 04f3:0c4f ELAN pad, enrolment, calibration, verify
│   ├── gpu-video.md                   ← §12 §13: Firefox freeze, VA-API on the iGPU, decode paused, VLC
│   ├── monitors.md                    ← §5 §16: scaling, profiles, Hyprmon as editor
│   ├── power-battery.md               ← §14 §17 §19: 80% cap, predator_v4 fans, power-source daemon
│   ├── triton-panel.md                ← §18: deploying the panel (helper, sudoers, desktop entry)
│   └── updates.md                     ← §1–§7: the upgrade gate, .pacnew deltas, moving premises, rollback
├── archive/                           ← superseded, kept not deleted. Do not follow these steps.
│   ├── README.md                      ← what "archive" means here and why nothing is deleted
│   ├── cachyos-hyprland-setup.md      ← original install guide (May 2026)
│   ├── install-remediation-2026-05.md ← §1 §2 §3 §4 §9 of the dissolved remediation doc
│   ├── spected-installation.md        ← pre-install stack rationale
│   └── system-state-findings.md       ← scan report after install (2026-05-21)
├── triton-panel/                      ← GTK4 hardware panel for this machine (source, not a mirror) — §15
│   ├── triton-panel                   ← the app
│   ├── triton-ctl                     ← privileged helper → /usr/local/bin, must be root-owned
│   ├── triton-panel.sudoers           ← → /etc/sudoers.d/ (validate with `visudo -cf` first)
│   ├── triton-panel.desktop           ← → ~/.local/share/applications/ (mirror: configs/applications/)
│   ├── test-enroll.py                 ← enrolment-window regression test, 81 assertions
│   ├── test-battery.py                ← battery graph / projection regression test
│   ├── fp-debug.sh                    ← fprintd enrol+verify harness (`runbooks/fingerprint.md` §20n)
│   ├── README.md                      ← what the app shows, privileges, the keyboard-backlight caveat
│   └── waybar/                        ← optional Waybar modules, same data in the bar (NOT applied)
├── patches/                           ← patches against third-party source. NOTHING here is applied.
│   ├── README.md                      ← the two rules, the build/test/rollback procedure
│   └── libfprint-elan-0c4f-busy-retry.patch  ← 3 lines; the enrolment blocker (`runbooks/fingerprint.md` §20x)
├── tests/                             ← regression tests for the scripts in configs/ (never pushed live)
│   ├── test-power-autoswitch.sh       ← the saved_profile invariant, 10 cases against the real branch text
│   ├── check-doc-refs.sh              ← every cross-document reference resolves (run after moving sections)
│   ├── check-live-system.sh           ← the machine still matches the docs (before/after every upgrade)
│   └── check-libfprint-patch.sh       ← the elan patch still applies and its flag bit still does not collide
└── configs/                           ← mirror of live dotfiles. Not the live config — push by hand.
    ├── hypr/
    │   ├── hyprland.conf              ← entrypoint, sources the rest
    │   ├── env.conf  input.conf  look.conf  windowrules.conf  autostart.conf
    │   ├── keybindings.conf
    │   ├── monitors.conf              ← boot-default layout + workspace bindings (by EDID `desc:`)
    │   ├── monitors-read.conf         ← alternate "read" profile (not sourced)
    │   ├── monitors-trio.conf         ← alternate "trio" profile (not sourced)
    │   ├── hypridle.conf  hyprlock.conf  hyprpaper.conf   ← sibling daemons, NOT reloaded by hyprctl
    │   └── scripts/
    │       ├── monitor-mode.sh        ← apply a named layout; sole owner of eDP-1's refresh rate
    │       ├── monitor-autoswitch.sh  ← debounced hotplug auto-switch daemon
    │       ├── power-autoswitch.sh    ← power-source daemon (60 Hz + power-saver on battery)
    │       ├── monitor-menu.sh        ← "Monitors" menu (Super+Shift+M + Walker "Monitors")
    │       ├── hyprmon-edit.sh        ← hyprmon as profile editor, config write + reload neutered
    │       └── show-shortcuts.sh      ← keybinding cheatsheet popup (Super+/ + Walker "Shortcuts")
    ├── hyprmon/profiles/              ← mirrors ~/.config/hyprmon/profiles/
    │   ├── desktop.json               ← 3-across geometry, edited in hyprmon (`P`), applied by monitor-mode.sh
    │   └── read.json                  ← Xiaomi + portrait AQ16H, laptop off
    ├── waybar/config.jsonc  waybar/style.css
    ├── kitty/kitty.conf  kitty/themes/Catppuccin-Mocha.conf
    ├── vlc/vlcrc                      ← hardware decode pinned off (avcodec-hw=none) — see §7 media note.
    │                                     ⚠ VLC rewrites this file wholesale on exit, so it drifts by design
    ├── applications/                  ← mirrors ~/.local/share/applications/
    │   ├── gimp.desktop               ← override: Name=GIMP (shadows the packaged entry) — §7
    │   ├── hyprmon.desktop            ← override: Exec → hyprmon-edit.sh (shadows the packaged entry) — §11
    │   ├── monitors.desktop           ← "Monitors" Walker entry → monitor-menu.sh
    │   ├── shortcuts.desktop          ← "Shortcuts" Walker launcher entry
    │   └── triton-panel.desktop       ← "Triton Panel" Walker entry → ~/.local/bin/triton-panel (§15)
    ├── modprobe.d/                    ← mirrors /etc/modprobe.d/ (push with `sudo install -Dm644`)
    │   ├── acer-wmi-battery.conf      ← enable_health_mode=1 → 80% charge cap, verified 2026-10-31 (§15)
    │   └── acer-wmi-predator-v4.conf  ← predator_v4=1 → fan RPM + 5-state platform_profile (§15)
    ├── systemd/
    │   ├── logind.conf.d/50-no-suspend-on-external-power.conf  ← lid ignored on external power (§15)
    │   └── user/swayosd.service       ← Restart=always OSD server (survives monitor switches)
    └── cachyOS-image.jpg  raspi.jpg   ← wallpapers referenced by hyprpaper.conf
```

---

## 17. How to Replicate This Setup Elsewhere

If you ever rebuild this machine (or set up a second one), the minimal sequence:

1. Install CachyOS, pick **Hyprland + KDE-Desktop**, btrfs, Limine.
2. Boot, run `sudo cachyos-chwd -a` to install NVIDIA correctly.
3. Verify KMS: `cat /sys/module/nvidia_drm/parameters/modeset` → `Y`. Do **not** add
   `nvidia-drm.modeset=1` to the cmdline — it is the driver default since the 610 series,
   and `/etc/mkinitcpio.conf.d/10-chwd.conf` early-loads the modules. See §3.
4. Install the full Hyprland stack (see section 4–8 above, or `archive/cachyos-hyprland-setup.md` section 4).
5. Restore dotfiles: `cp -r configs/hypr ~/.config/`, same for `waybar/` and `kitty/`.
6. Wallpaper: `mkdir -p ~/Pictures/Wallpapers && cp wall.jpg ~/Pictures/Wallpapers/` (or download from a Catppuccin wallpaper repo).
7. Apply `runbooks/boot-suspend.md` §10 to disable `plasmalogin.service` and switch to `getty@tty1` autologin + fish `exec start-hyprland`. (Or skip §10 to keep the PlasmaLogin greeter — pick Hyprland session at the greeter and log in.)
8. Verify: `hyprctl version`, `hyprctl monitors`, `nvidia-smi`.
9. The autostart entries in `~/.config/hypr/autostart.conf` bring up bar, wallpaper, notifications, polkit, clipboard, network/BT tray, and the walker resident service automatically.

---

*Generated 2026-05-21 from live system scan; refreshed 2026-05-22 after Section 6 TB fix landed. Update this file whenever a major change lands (kernel upgrade, new daemon, new monitor, etc.) by re-running the verification block in `archive/install-remediation-2026-05.md` §9.*
