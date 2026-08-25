# Actual System Configuration

**Snapshot date:** 2026-05-21
**Last updated:** 2026-07-02 (Firefox-freeze root-cause + VA-API reroute: §3 refreshed — driver now `610.43.02`/`7.0.12-1`, KMS via driver-default + chwd early-KMS, dGPU confirmed **offload-only** with the compositor on the iGPU; `env.conf` `LIBVA_DRIVER_NAME` nvidia→iHD and `NVD_BACKEND` dropped; Firefox hardware decode paused via profile `user.js`; four new §15 rows — freeze incident, i915 `__gen8_ppgtt_clear` NULL-deref bug, NVIDIA GSP resume failure, iGPU-primary discovery. Details: `finish-installation-commands.md` §12). 2026-05-26 (Two fixes: (1) Elephant/Walker — `graphical-session.target` never activates under this getty+`start-hyprland` session, so `elephant.service` never auto-started and Walker hung on "Waiting for elephant"; fixed by adding `exec-once = systemctl --user start elephant.service` to autostart.conf, §10 + §15 reflect it, see `finish-installation-commands.md` §7e.ii–iii. (2) VS Code OS-keyring notification silenced via `~/.config/code-flags.conf` → `--password-store=basic`; §7 editor row + §15 reflect it, see `finish-installation-commands.md` §7f). 2026-05-23 (Walker Elephant backend installed — hub + 9 providers from AUR at `2.21.0-1`, `~/.config/systemd/user/elephant.service` user unit written + enabled; §5/§10/§12/§15 reflect new state. Earlier same-day: verified live state matches mirrored configs; phantom DP-0 EDID warning logged; display-manager row rewritten — system now boots via `getty@tty1` autologin + fish `exec start-hyprland`, plasmalogin disabled per `finish-installation-commands.md` §10)
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

Since **2026-08-03 nothing depends on the port name**: `monitors.conf` binds both
externals by EDID **description** (`desc:` — a prefix match), and *every* profile in
`monitor-mode.sh` resolves panels by capability. Before that change the name-bound
`workspace = N, monitor:DP-*` rules silently put workspaces **1–3 (the primary set) on
the 16" portable** and 6–9 on the Xiaomi. The live arrangement is chosen by a hotplug
daemon (`trio` / `read` / `onescreen` / `laptop`) — see §11 "Monitor profiles &
auto-switching".

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
| Kernel (running) | `7.0.9-1-cachyos` (BORE scheduler, performance-tuned) |
| Kernel (fallback) | `linux-cachyos-lts 6.18.32-1` |
| Architecture | x86_64 |
| Bootloader | **Limine** (not GRUB) |
| EFI partition | `/dev/nvme0n1p1` 4 GiB vfat at `/boot` |
| Root subvolume | `subvol=/@` on `nvme0n1p2` btrfs |
| Init | systemd |
| Boot time | ~22s total (5s firmware / 3.5s loader / 0.9s kernel / 3s initrd / 9.5s userspace) |
| Display manager | **None.** `getty@tty1` drop-in autologins `isalgado` (`/etc/systemd/system/getty@tty1.service.d/override.conf`); fish login shell sources `~/.config/fish/conf.d/99-hyprland-autostart.fish`, which `exec start-hyprland` on `XDG_VTNR=1`. `plasmalogin.service` is installed but **disabled and inactive** (kept for rollback per `finish-installation-commands.md` §10). |
| Session type | Wayland |
| Desktop env | Hyprland (with KDE Plasma as installer-bundled fallback) |
| Shell | Login shell is **`/bin/fish`** (per `/etc/passwd` for `isalgado`); fish, bash, zsh all installed. `$SHELL` may show `/usr/bin/zsh` inside non-login zsh subshells — that's inherited, not the login shell. See `finish-installation-commands.md` §10 for the fish-based Hyprland autostart path. |
| Audio | PipeWire 1.6.5 with `pipewire-pulse` and `wireplumber`; default sink: Samson Go Mic USB |

### Kernel command line

```
quiet nowatchdog splash rw rootflags=subvol=/@
root=UUID=d94a3435-f8db-4cc2-ade4-4ed01417dfd2
nvidia-drm.modeset=1 nvidia_drm.fbdev=1
```

> **Note:** `linux-cachyos-lts` entry in `/boot/limine.conf` does NOT have `nvidia-drm.modeset=1` — booting LTS will black-screen on Hyprland. Persistent fix lives in `/etc/default/limine`; see section 0 of `finish-installation-commands.md`.

---

## 3. NVIDIA Stack

| Item | Value |
|---|---|
| Driver | 610.43.02 (open GSP kernel modules, via `linux-cachyos-nvidia-open`) — updated 2026-07-02, was 595.71.05 |
| Kernel modules loaded | `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` |
| Module package | `linux-cachyos-nvidia-open 7.0.12-1` (CachyOS-specific; not `nvidia-dkms`) |
| Userspace | `nvidia-utils 610.43.02-3`, `lib32-nvidia-utils 610.43.02-1`, `egl-wayland 4:1.1.21`. `libva-nvidia-driver` removed 2026-07-02 (`finish-installation-commands.md` §12d) |
| Role | **Offload-only (discovered 2026-07-02).** The compositor and all three outputs run on the Intel iGPU — aquamarine primary DRM = `card2` (i915), renderer on `renderD129`; the dGPU (`card1`) is a secondary KMS backend whose own connectors (`eDP-2`, `HDMI-A-1`) are unused |
| KMS | ✅ enabled — `modeset` is the driver default on the 610 series, and the modules early-load from initramfs via `/etc/mkinitcpio.conf.d/10-chwd.conf` (`MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`). The kernel cmdline no longer carries `nvidia-drm.modeset=1` (verified `/proc/cmdline` 2026-07-02); the mechanism is kernel-agnostic, so it covers the LTS entry too |
| Hardware cursor | disabled in Hyprland config (`cursor.no_hardware_cursors = true` to avoid NVIDIA artifacts) |
| Wayland env vars (set in `env.conf`) | `LIBVA_DRIVER_NAME=iHD` (2026-07-02, was `nvidia`; `NVD_BACKEND=direct` dropped with the shim), `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `GBM_BACKEND=nvidia-drm`, `MOZ_ENABLE_WAYLAND=1`, `ELECTRON_OZONE_PLATFORM_HINT=auto`. ⚠ Only processes Hyprland spawns (keybinds/`exec-once`) see these — Walker/Elephant launches apps from the systemd `--user` manager, which doesn't (verified 2026-07-02: the running Firefox had none of them in its environ) |

---

## 4. Installed Packages — Hyprland Ecosystem

| Package | Version | Role |
|---|---|---|
| `hyprland` | 0.55.2-1.1 | Compositor (Wayland) |
| `hyprlock` | 0.9.5-3.1 | Lock screen |
| `hypridle` | 0.1.7-9.1 | Idle / lock / suspend daemon |
| `hyprpaper` | 0.8.4-1.1 | Wallpaper daemon |
| `hyprpolkitagent` | 0.1.3-7.1 | PolicyKit auth agent (binary at `/usr/lib/hyprpolkitagent/`) |
| `hyprshutdown` | 0.1.1-2.1 | Power menu helper |
| `xdg-desktop-portal-hyprland` | 1.3.12-2.1 | Portal (screensharing/file pickers) |

## 5. Installed Packages — UI / Daemons / Tools

| Package | Version | Role |
|---|---|---|
| `waybar` | 0.15.0-2.1 | Status bar |
| `mako` | 1.11.0-1.1 | Notifications |
| `kitty` | 0.46.2-1.2 | Terminal |
| `walker` | 2.16.2-1 | App launcher (runs as resident `--gapplication-service`; backed by Elephant — see below) |
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
| `libqalculate` | 5.10.0-1.1 | Calculator backend used by `elephant-calc` |
| `yazi` | 26.5.6-2.1 | TUI file manager |
| `swayosd` | 0.3.1-1.1 | Volume/brightness on-screen popups |
| `grim` | 1.5.0-2.1 | Wayland screenshot tool |
| `slurp` | 1.5.0-2.1 | Region selection |
| `satty` | 0.20.1-2.2 | Screenshot annotation |
| `wl-clipboard` | 2.3.0-1.1 | Wayland clipboard |
| `cliphist` | 0.7.0-2.1 | Clipboard history store |
| `brightnessctl` | 0.5.1-3 | CLI backlight control |
| `pavucontrol` | 6.2-1.1 | Audio mixer GUI |
| `playerctl` | 2.4.1-5.1 | Media key dispatcher |
| `network-manager-applet` | 1.36.0-2.1 | NetworkManager tray icon |
| `blueman` | 2.4.6-2.1 | Bluetooth tray + GUI |
| `bluez` / `bluez-utils` | 5.86-6.1 | Bluetooth stack |

## 6. Installed Packages — Fonts / Themes

| Package | Version |
|---|---|
| `ttf-jetbrains-mono-nerd` | 3.4.0-2 |
| `noto-fonts` | 2026.05.01-1 |
| `noto-fonts-emoji` | 2.051-1 |
| `noto-fonts-cjk` | 20240730-1 |
| `papirus-icon-theme` | 20250501-1 |
| `qt5-wayland` | 5.15.18-1.1 |
| `qt6-wayland` | 6.11.1-1.1 |
| `qt6ct` | 0.11-6.1 |
| `kvantum` | 1.1.7-1.1 |

## 7. Installed Packages — Editors / File Managers / Browser

| Package | Version | Notes |
|---|---|---|
| `visual-studio-code-bin` | 1.121.0-1 | Primary editor (runs on Wayland). `~/.config/code-flags.conf` carries `--password-store=basic` to silence the "OS keyring couldn't be identified" notification (no Secret Service in this session) — see `finish-installation-commands.md` §7f. |
| `micro` | 2.0.15-2.1 | Terminal text editor (Yazi's default for text files) |
| `dolphin` | 26.04.1-1.1 | KDE file manager (GUI fallback) |
| `firefox` | 150.0.3-1 | Default browser |
| `google-chrome` *(AUR)* | 150.0.7871.181-1 | Secondary browser. Installed 2026-07-23. Ships `/usr/share/applications/google-chrome.desktop` (+ `com.google.Chrome.desktop`), `Exec=/usr/bin/google-chrome-stable %U`. Unlike Obsidian, it did **not** hot-reload into Walker — elephant's desktopapplications cache was stale, so a `systemctl --user restart elephant.service` was needed to index it. Nothing added to `configs/applications/`; that mirror is only for custom entries like `shortcuts.desktop`. |
| `obsidian` | 1.12.7-3 | Markdown knowledge base / notes. Repo pkg (`extra`), installed 2026-07-08. Ships `/usr/share/applications/obsidian.desktop`, so it auto-appears in Walker — elephant hot-reloaded, no restart needed (verified via `elephant query 'desktopapplications;obsidian;5'`). Nothing added to `configs/applications/`; that mirror is only for custom entries like `shortcuts.desktop`. |
| `calibre` | 9.11.0-3.1 | E-book library manager / reader. Repo pkg, installed 2026-07-23 (pulled ~69 deps — Python/Qt stack). Ships four `/usr/share/applications/calibre-*.desktop` entries (`calibre-gui`, `-ebook-viewer`, `-ebook-edit`, `-lrfviewer`); "Calibre" (`calibre-gui.desktop`) is the main launcher. Auto-appeared in Walker — elephant hot-reloaded, no restart needed (verified via `elephant query 'desktopapplications;calibre;5'` → score 192). |

### Media players

| Package | Version | Notes |
|---|---|---|
| `vlc` | 3.0.23_2-9.1 | **Primary video player.** Installed 2026-07-31 (`vlc` + `vlc-gui-qt` + `vlc-cli` + `qt5-svg` + `qt5-x11extras` — only 5 packages, because `vlc-plugins-all` had already been installed since the original build, leaving a binary-less half-install). Ships `/usr/share/applications/vlc.desktop`; Elephant **hot-reloaded**, no restart needed (`elephant query 'desktopapplications;vlc;5'` → score 88). ⚠ Hardware decode deliberately **off** — see the note below. |
| `haruna` | 1.8.1-1.1 | Secondary video player (Qt/QML on `libmpv`, KDE). Was installed but undocumented until 2026-07-31; ships `org.kde.haruna.desktop`. Pulls `mpv 1:0.41.0-3.1` + `mpvqt`. Note: mpv/Haruna default to hardware decode too — if either becomes the daily driver, apply the same pin (`hwdec=no` in `~/.config/mpv/mpv.conf`). |
| `vlc-plugins-all` | 3.0.23_2-9.1 | Every VLC codec plugin. Predates the `vlc` install; `phonon-qt6-vlc` (KDE's multimedia backend) rides on the same libvlc, so don't remove it when uninstalling VLC. |

> ⚠ **VLC hardware decoding is pinned OFF** via `~/.config/vlc/vlcrc` (`[avcodec]` / `avcodec-hw=none`). VLC's default `avcodec-hw=any` routes VA-API → iHD → **the iGPU**, the same path that hung the video engine and tripped the i915 hang-recovery NULL deref on 2026-07-02 (§15). Firefox is pinned to software decode for the identical reason. Verified 2026-07-31 by verbose playback: `looking for hw decoder module matching "none" … no hw decoder modules matched` → software decode, kernel log clean. This can't live in `env.conf` — Walker/Elephant launches apps from the systemd `--user` manager, which never sees Hyprland's env vars. Re-enable together with Firefox's prefs once a kernel past `7.0.12-1-cachyos` proves stable: `finish-installation-commands.md` §13c / §12f.

> Not installed: `neovim`, `ghostty` (Ghostty is in CachyOS repos if you want to swap in for Kitty later).

### Graphics / image editing (added 2026-08-25)

| Package | Version | Notes |
|---|---|---|
| `inkscape` | 1.4.4-6.1 | **Vector editor — the tool for designing buttons/icons.** Repo pkg (`extra`), installed 2026-08-25. Draw once, export PNG at any exact size (32/64/128/512px) without resolution loss. Pulled ~21 deps (`lib2geom`, `libcdr`, `libvisio`, `libwpd`/`libwpg`, `scour`, `gsl`, `python-numpy`, `gspell`, `enchant`, `litehtml`). Ships `/usr/share/applications/org.inkscape.Inkscape.desktop` with `Name=Inkscape`, `Exec=inkscape %F`. Auto-appeared in Walker — Elephant **hot-reloaded**, no restart needed (`elephant query 'desktopapplications;inkscape;5'` → score 218, matched on `field:"text"`). |
| `gimp` | 3.2.4-2.1 | **Raster editor — crop, layers, alpha, retouch on existing PNGs.** Repo pkg (`extra`), installed 2026-08-25. GIMP 3.x line (native Wayland, single-window UI). Pulled ~10 deps (`gegl`, `babl`, `libgexiv2`, `lensfun`, `libmypaint`, `mypaint-brushes`, `suitesparse`, `libspiro`). ⚠ Walker display name is overridden — see below. |
| `graphicsmagick` | 1.3.48-1.1 | Pulled in as an Inkscape dependency, not chosen directly. Note the pre-existing `imagemagick` + `optipng` remain the CLI path for batch resize/convert/compress. |

> ⚠ **GIMP's Walker entry is overridden** by `~/.local/share/applications/gimp.desktop` (mirrored at `configs/applications/gimp.desktop`). The packaged `/usr/share/applications/gimp.desktop` sets `Name=GNU Image Manipulation Program`, so Walker listed it under "G-N-U…" and typing `gimp` only matched via the *subtext* (`gimp-3.2`, score 109). Because the override reuses the **same desktop ID**, it **shadows the packaged file entirely rather than merging** — so the packaged `MimeType=` line (44 types) is copied verbatim into it, or "Open with → GIMP" would silently break for the exotic formats. `Exec=gimp %U` deliberately uses the unversioned `/usr/bin/gimp` symlink (→ `gimp-3.2`) so a future 3.x bump can't break launching, unlike the packaged `Exec=gimp-3.2 %U`. Verified after writing: `elephant query 'desktopapplications;gimp;5'` → `text:"GIMP"`, `subtext:"Image Editor"`, single result, matched on `field:"text"` (score 114) — Elephant hot-reloaded the user dir, no service restart needed. `desktop-file-validate` clean.

> **Why these two and not Pinta:** Pinta (the usual lightweight Paint.NET-style pick) is AUR-only here as `pinta-git`/`pinta-gtk3-git` — a from-source .NET build, not worth the maintenance. The lighter fallback if GIMP ever feels excessive is `drawing` (4.6 MiB, in `extra`), but it has no layer support.

## 8. Installed Packages — Boot / Snapshots / Power

| Package | Version | Role |
|---|---|---|
| `limine` | 11.4.1-1 | Bootloader |
| `limine-mkinitcpio-hook` | 1.36.0-1 | Auto-regenerates `/boot/limine.conf` on kernel updates |
| `limine-snapper-sync` | 1.29.0-1 | Adds snapper snapshots as bootable Limine entries |
| `snapper` | 0.13.1-2.1 | btrfs snapshot manager (root config: `root`) |
| `snap-pac` | 3.0.1-3 | Automatic snapshots on pacman transactions |
| `btrfs-progs` | 7.0-1 | btrfs userspace tools |
| `plymouth` | 24.004.60-14.1 | Boot splash. **Removed from mkinitcpio `HOOKS=` on 2026-05-22** for TB boot fix (Section 6.0). Shutdown units (`plymouth-quit`, `-quit-wait`, `-poweroff`, `-reboot`) also masked. Package retained for possible future reintroduction. |
| `power-profiles-daemon` | 0.30-3 | Power profile switching (not TLP, not auto-cpufreq) |

## 9. Installed Packages — Counts

- **Explicitly installed (user-requested):** 274 (was 273; +`vlc` on 2026-07-31 — the other 4 packages it pulled are dependencies, not explicit. +`calibre` on 2026-07-23; +`google-chrome` earlier the same day; was 271 before that. Was 267 on 2026-05-23; +Obsidian on 2026-07-08, plus a few other installs in between)
- **Total installed (with dependencies):** 1432 (was 1427; +5 from `vlc` on 2026-07-31 — small because `vlc-plugins-all` had already pulled the whole codec stack. Was 1358 before `calibre`'s +69 Python/Qt stack on 2026-07-23)
- **Foreign / AUR packages:** 12 (`pacman -Qm`) — unchanged by the VLC install (repo package). Includes `elephant` + 9 providers (all `2.21.0-1`), `visual-studio-code-bin`, and `google-chrome` (added 2026-07-23). `calibre` is **not** here — it's a repo package. Obsidian is **not** here either — repo package from `extra`.

Get the full explicit list with `pacman -Qe`. Get only foreign packages (AUR/manual) with `pacman -Qm`.

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
| `walker --gapplication-service` | autostart (resident service for fast launches) |
| `elephant` | `exec-once = systemctl --user start elephant.service` (autostart.conf). The user unit at `~/.config/systemd/user/elephant.service` exists (written 2026-05-23; AUR pkg ships none) but is `WantedBy=graphical-session.target`, which **never activates** under this getty-autologin + `start-hyprland` session — so it's started explicitly from autostart.conf instead (fixed 2026-05-26; before that Walker hung on "Waiting for elephant"). Backs every Walker prefix/`-m <mode>` invocation. |
| `polkitd` | system (PolicyKit daemon) |
| `xdg-desktop-portal` + `xdg-desktop-portal-hyprland` | systemd user units |
| `pipewire`, `pipewire-pulse`, `wireplumber` | systemd user units (audio) |

All Hyprland-side autostarts are live and producing visible output (bar, wallpaper, tray icons).

---

## 11. Hyprland Config Layout

All under `~/.config/hypr/` and mirrored in this repo at `configs/hypr/`:

```
hyprland.conf      ← entrypoint, sources the others
env.conf           ← NVIDIA + Qt + cursor env vars
monitors.conf      ← 3-monitor layout, scale 1.25 on 2560×1600 outputs
input.conf         ← keyboard layout, touchpad, 3-finger gesture
look.conf          ← Catppuccin Mocha colors, dwindle, animations, blur+shadow
keybindings.conf   ← every shortcut (see shortcuts.md)
windowrules.conf   ← floats for dialogs (pavucontrol, blueman, polkit, PiP)
autostart.conf     ← exec-once for all daemons
hyprpaper.conf     ← block-syntax wallpaper bindings (workaround for 0.8.4 parser bug)
hyprlock.conf      ← Catppuccin password input + big clock + blurred wallpaper
hypridle.conf      ← 5m lock / 10m DPMS / 20m suspend
monitors-read.conf ← alternate "read" profile (portrait external, laptop OFF); NOT sourced, applied live
monitors-trio.conf ← alternate "trio" profile (both 16" portables + laptop centered); NOT sourced, reference only — monitor-mode.sh resolves the geometry by capability (added 2026-07-08)
scripts/monitor-mode.sh        ← apply a named layout: desktop|read|laptop|onescreen|trio|toggle
scripts/monitor-autoswitch.sh  ← daemon: auto-picks layout from connected displays (autostart.conf)
scripts/show-shortcuts.sh      ← curated keybinding cheatsheet in a floating Kitty window (Super+/ and the "Shortcuts" Walker entry; added 2026-06-17)
```

### Monitor profiles & auto-switching (added 2026-06-10)

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

## 12. Other Configs

```
~/.config/waybar/config.jsonc   ← bar layout + module configs (Catppuccin colors)
~/.config/waybar/style.css      ← bar CSS (purple workspace highlight, JetBrainsMono)
~/.config/kitty/kitty.conf      ← JetBrainsMono 12pt, 0.95 opacity, includes Catppuccin theme
~/.config/kitty/themes/Catppuccin-Mocha.conf  ← official Catppuccin theme file
~/.config/walker/               ← EMPTY (running on Elephant defaults; pin prefixes/providers via finish-installation-commands.md §7e.iv if desired)
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
  - `linux-cachyos` — has `nvidia-drm.modeset=1 nvidia_drm.fbdev=1` ✅
  - `linux-cachyos-lts` — MISSING modeset params ⚠ (would black-screen Hyprland)
  - Snapshots 7–12: same pattern (main has modeset, LTS doesn't)
  - Snapshot 6: pre-`cachyos-chwd` baseline (neither kernel has modeset)

---

## 14. Display Manager Reality Check

- The plan in `cachyos-hyprland-setup.md` section 7 talks about forcing **SDDM** into X11 mode. **SDDM is not installed.** `/etc/sddm.conf` is a leftover stub.
- This system **previously** ran **plasma-login-manager** (`plasmalogin.service`). It was disabled on 2026-05-22 per `finish-installation-commands.md` §10 to eliminate the phantom-cursor handoff bug; the package is still installed for rollback but the unit is `disabled` and `inactive`.
- **Current launch path:** `getty@tty1` drop-in (`/etc/systemd/system/getty@tty1.service.d/override.conf`) autologins `isalgado`; fish login shell runs `~/.config/fish/conf.d/99-hyprland-autostart.fish`, which `exec start-hyprland` (the package-shipped wrapper at `/usr/bin/start-hyprland`) on tty1 when no Wayland session is already attached.
- **Why `start-hyprland` not `Hyprland`:** Hyprland ≥ 0.53 emits a startup warning when launched bare; the wrapper sets up the systemd user session, D-Bus activation, and XDG session vars before exec'ing the compositor. Launching the compositor directly leaves `XDG_SESSION_TYPE=tty`, no `XDG_CURRENT_DESKTOP`, and breaks portals / polkit prompts / screen sharing for some apps. Fixed 2026-05-23.

---

## 15. Outstanding Issues

These are tracked in `system-state-findings.md` and `finish-installation-commands.md` (where applicable). Status as of this snapshot:

| Item | Status |
|---|---|
| Hyprland NVIDIA black-screen | ✅ Resolved (KMS + env vars) |
| Hyprland autostart daemons | ✅ All running (polkit fixed via systemd unit; hypridle started; nm-applet installed) |
| Waybar Catppuccin config | ✅ Applied (`~/.config/waybar/config.jsonc` + `style.css`) |
| Hyprpaper wallpaper binding | ✅ Resolved via block syntax (workaround for 0.8.4 config parser bug — see GitHub hyprwm/hyprpaper#204 + Arch forum thread) |
| Hyprlock styling | ✅ Catppuccin theme applied |
| Hypridle timeouts | ✅ Configured (5/10/20 min). **2026-07-12:** the 20-min suspend listener is now **battery-only** (`grep -q Discharging /sys/class/power_supply/BAT1/status && systemctl suspend` — `BAT1` status covers barrel AC, USB-C PD and dock power, unlike `ACAD/online`) after that day's resume-from-s2idle crash (GSP row below). On external power the machine still locks (5 min) + DPMS-off (10 min) but stays awake |
| qt6ct env var | ✅ Package installed, env var valid |
| Kitty Catppuccin theme | ✅ Applied |
| Yazi config | ✅ Working on defaults (no custom config needed; image previews via Kitty auto-detected) |
| Walker config | ✅ Elephant-backed (2026-05-23) — hub + 9 providers (apps, calc, runner, files, symbols, clipboard, websearch, providerlist, menus) from AUR; user unit at `~/.config/systemd/user/elephant.service`. Verified: `walker -m clipboard` and `walker -m symbols` open working UIs. `~/.config/walker/config.toml` and `~/.config/elephant/*.toml` not yet written — running on Elephant defaults (websearch prefix is `@`; `shortcuts.md` §1.2 and §4 reflect this). §7e.iv–v in `finish-installation-commands.md` pins these if desired. **Startup fix 2026-05-26:** the unit was `enabled` but `WantedBy=graphical-session.target`, which never activates under this getty+`start-hyprland` session, so elephant never started and Walker hung on "Waiting for elephant". Now started explicitly via `exec-once = systemctl --user start elephant.service` in autostart.conf (see §7e.ii–iii). |
| VS Code OS-keyring notification | ✅ Resolved — `~/.config/code-flags.conf` sets `--password-store=basic` so VS Code skips the missing Secret Service backend (no keyring daemon in this Hyprland session). Trade-off: secrets stored in an obfuscated local file, not keyring-encrypted. Details + revert path: `finish-installation-commands.md` §7f. |
| HiDPI scaling | ✅ Scale 1.25 on eDP-1, the portable QHD, and (since 2026-07-11) the Xiaomi 27" 4K (`3840×2160` → 3072×1728); positions recalculated |
| LTS kernel cmdline | 🔧 Reframed 2026-07-02 — the modeset worry is obsolete: `modeset` is the 610-series driver default and early-KMS comes from `/etc/mkinitcpio.conf.d/10-chwd.conf`, both kernel-agnostic; even the main entry's cmdline no longer carries `nvidia-drm.modeset=1`. Remaining: verify the LTS entry carries `thunderbolt.host_reset=0` + `mem_sleep_default=s2idle` (`sudo grep -i -B2 -A8 lts /boot/limine.conf`) and boot-test it once — LTS `6.18.35` is the escape hatch for the i915 `7.0.12` NULL-deref row below |
| Thunderbolt boot hang | ✅ Resolved 2026-05-22 — `thunderbolt.host_reset=0` on `linux-cachyos` cmdline, `plymouth` removed from `HOOKS=`, `quiet splash` dropped. TB4 dock now boots cleanly. Details: `finish-installation-commands.md` §6.0. ⚠ LTS entry still missing the same param. |
| `quiet splash` / plymouth regression | ✅ Re-reverted 2026-06-11 — both had been re-added that day (`KERNEL_CMDLINE[default]+=" quiet splash"` in `/etc/default/limine` + `plymouth` back in mkinitcpio `HOOKS=`) to hide boot-console text, which reintroduced boot problems. Removed both and ran `sudo limine-mkinitcpio` (rebuilt `linux-cachyos` + `linux-cachyos-lts`, regenerated `/boot/limine.conf`). Backups: `/etc/default/limine.bak-20260611`, `/etc/mkinitcpio.conf.bak-20260611`. Plymouth shutdown units remain masked. This restores the 2026-05-22 TB-boot-fix state — do not re-add `quiet splash` or the `plymouth` hook. |
| Thunderbolt shutdown hang | ✅ Resolved 2026-05-22 — `nvidia-{suspend,resume,hibernate}` enabled; `NVreg_PreserveVideoMemoryAllocations=1` + `/var/tmp` spill via `/etc/modprobe.d/nvidia-power-management.conf`; Plymouth shutdown units masked; `DefaultTimeoutStopSec=15s` (diagnostic). Details: `finish-installation-commands.md` §6.0. |
| NVIDIA black-screen on resume from suspend | 🔧 Fix applied 2026-05-26 — resume from **deep (S3)** suspend crashed the NVIDIA open module (595.71.05). On the 2026-05-26 21:38 resume: `nvidia-drm: Failed to detect display state` + **333 `NVRM:` MMU-walk assertion failures** (`mmuWalkUnmap`/`mmuWalkSparsify` → `NV_ERR_INVALID_STATE`) wedged the display engine → screen stayed black while the system kept running headless → forced power-off at 21:44 (journal ends mid-line on a WiFi rekey, no shutdown sequence). Same `Failed to detect display state` seen milder (2 errors, recovered) on the 2026-05-25 19:15 resume, so it's recurring. `NVreg_PreserveVideoMemoryAllocations=1`, `/var/tmp` spill, and `nvidia-{suspend,resume,hibernate}` were **all already correctly set** — this is a driver-level S3-resume bug, not a misconfig. **Fix:** force `s2idle` instead of S3 via `mem_sleep_default=s2idle` appended to the `linux-cachyos` cmdline in `/etc/default/limine`, then `sudo limine-mkinitcpio`. Live-applied 2026-05-26 (`/sys/power/mem_sleep` now `[s2idle] deep`); persist + verify steps in `finish-installation-commands.md` §11. ⚠ LTS entry not updated. Re-evaluate if a newer NVIDIA driver fixes S3 resume. **2026-07-02:** s2idle avoids the hard display wedge, but the 20:48 resume failed dGPU GSP re-init (`kgspWaitForRmInitDone → Reset required`) — dGPU dead until reboot; the session survives because the compositor runs on the iGPU. Tracked in the dedicated GSP row below. |
| Leftover Windows/Ubuntu partitions | ℹ️ Intentionally retained — `nvme1n1p3` (NTFS 559 GiB) + `nvme1n1p4` (ext4 393 GiB) keep other OS docks/data. Cleanup section removed from `finish-installation-commands.md` on 2026-05-22. |
| SDDM X11 workaround | N/A — no display manager (boot via `getty@tty1` autologin + fish `exec start-hyprland`); `plasmalogin` disabled 2026-05-22 per `finish-installation-commands.md` §10 |
| Phantom `DP-0` EDID warning at boot | ℹ️ Benign — NVIDIA logs `nvidia-modeset: WARNING: GPU:0: Unable to read EDID for display device DP-0` because nothing is plugged into that connector. The three real outputs (`eDP-1`, `DP-1`, `DP-2`) come up cleanly. No action needed. |
| Desktop 3-across profile not re-fitted for the Xiaomi | ✅ Resolved 2026-08-03 — the Samsung FHD 24" was swapped for a **Xiaomi Mi Monitor 27" 4K** (`3840×2160@60`) on 2026-07-11, but `monitors.conf`/`apply_desktop` kept hardcoding `DP-1 1920×1080@120` + a `DP-2 2560×1600` slot the Xiaomi can't do. **Fix:** `apply_desktop` now resolves both externals by capability (laptop left 0–2048 · desk external centre at its best mode/scale · QHD portable right), and `monitors.conf` carries the matching logical geometry `eDP-1 0–2048 · Xiaomi 2048–5120 · QHD 5120–7168` (total 7168) bound by `desc:` rather than `DP-*`. Same commit fixed `apply_onescreen` (identical Samsung hardcode) and `read`'s fallback. Live-verified: `hyprctl reload` placed the Xiaomi at `2048x0 3840×2160 scale 1.25` despite it being `DP-2`. All Samsung references are gone from the live config. |
| Rotated panel tiled with landscape geometry | ✅ Resolved 2026-08-04 — in `read`, the **VCHANCE AQ16H** rendered portrait but tiled landscape: a window came out **2028×1224 on the 1280×2048 screen**, spilling 758px past the right edge. Cause: `hyprctl keyword monitor …,transform,N` against an **already-enabled** output rotates the render pass but does **not** rebuild the monitor's layout box, and `hyprctl monitors` reports the new transform either way — so it read as correctly configured. **Symmetric**: leaving portrait stranded a 1280×2048 box on a 2048×1280 screen, so `desktop`/`trio`/`onescreen` were affected too. **Fix:** new `apply_monitor_tf()` in `monitor-mode.sh` cycles the output (disable → re-enable) whenever the target transform differs from the running one; all four profiles now set the AQ16H's transform through it, explicitly stating `transform,0` where landscape is wanted. Verified **not** to rebuild the box: `dispatch forcerendererreload`, `dispatch moveworkspacetomonitor`, and re-applying the identical spec. Since the cycle emits external hotplug events, a fingerprint handshake (`$XDG_RUNTIME_DIR/hypr-monitor-fingerprint`, `SELF_GRACE=15 s`) stops `monitor-autoswitch.sh` reverting a manual `Super+M` choice — see §11. Live-verified both directions: portrait → `1260×1992`, landscape → `2028×1224`, Waybar/swayosd survive, workspaces re-home, and a real unplug still switches profile. |
| RTK HDMI adapter reports garbage EDID | ℹ️ Hyprland shows `Invalid Vendor Codename - RTK HDMI 0x01010101` for the portable QHD — a **VCHANCE AQ16H 16"** (currently `DP-1`; port floats), whose Realtek scaler publishes no vendor string and a placeholder serial. Modes still detected correctly; runs at its native 2560×1600@120 as expected. (The Xiaomi on `DP-2` reports a clean `Xiaomi Corporation Mi Monitor` EDID.) **No longer purely cosmetic since 2026-08-03:** that string is now a `desc:` match key in `monitors.conf`, using the prefix `Invalid Vendor Codename - RTK HDMI`. The road-going **demoset** FHD portable is distinguished by `demoset` in its description, so the two don't collide — but re-check the prefix if a third generic RTK-adapter panel ever appears, and re-verify after any adapter swap. |
| Volume/brightness OSD + media keys dead after a monitor switch | ✅ Resolved 2026-06-17 — root cause was `swayosd-server` 0.3.1 SIGABRTing whenever the monitor set changes (backtrace: `gtk_layer_init_for_window` → `wl_display_roundtrip_queue` → `abort`, fired from the GTK "monitors changed" signal). It runs fine *sitting* in any layout but dies *during* the transition, so switching into the `read` profile (which disables `eDP-1`) — or any hotplug — left the server dead and, since it was a bare `exec-once`, nothing revived it: no OSD, and the media keys (which route through `swayosd-client` → server) stopped changing volume entirely. **Fix:** moved it to a `Restart=always` systemd `--user` unit (`~/.config/systemd/user/swayosd.service`, mirrored in `configs/systemd/user/`), launched via `exec-once = systemctl --user start swayosd.service`; `monitor-mode.sh` also runs `systemctl --user restart swayosd.service` after applying each layout so a healthy server is bound to the new monitor set. Verified by simulating the crash (`kill -ABRT`) → systemd revived it; restart path and `swayosd-client` volume both confirmed. Also wired the Waybar `pulseaudio` module's scroll (and middle-click mute) through `swayosd-client` so scrolling the bar shows the OSD too. Upstream bug — re-evaluate the workaround if a newer swayosd survives monitor hotplug. |
| Firefox freeze 2026-07-02 21:10 — whole session wedged | 🔧 Mitigated 2026-07-02 — journal (boot `8790fdd2`) shows two **independent** failures: (1) 20:48 resume → dGPU GSP re-init failed (dedicated row below) → 384 NVRM errors this boot (344/359 the two prior), incl. `vaspaceapiConstruct: Could not construct VA space` at 20:57 — a GPU *virtual-address-space* error on the dead dGPU, **not** the VA-API video shim. (2) At 21:10 Firefox's `MediaPD~der` hung the **iGPU** video engine 3× (`i915 GPU HANG ecode 12:4`) and i915's hang-recovery NULL-dereffed in `__gen8_ppgtt_clear` (row below) → GPU memory management wedged → freeze. Key finding: Walker/Elephant launches Firefox from the systemd `--user` env, so `LIBVA_DRIVER_NAME=nvidia` never reached it — Firefox was already hardware-decoding on the iGPU; the NVIDIA shim was dead config. **Fixes:** `env.conf` VA-API → `iHD` + `NVD_BACKEND` dropped (repo+live); Firefox hardware decode paused via `~/.config/mozilla/firefox/31yk9hxe.default-release/user.js` (`media.ffmpeg.vaapi.enabled=false`) until the i915 bug is fixed; `libva-nvidia-driver` removed (confirmed gone 2026-07-02). Details/verify/revert: `finish-installation-commands.md` §12 |
| i915 NULL deref in `__gen8_ppgtt_clear` during GPU-hang recovery | ⚠ Open — kernel `7.0.12-1-cachyos` bug: a video-engine hang should end in a context reset, but recovery crashed (`BUG: kernel NULL pointer dereference … RIP: __gen8_ppgtt_clear+0x1da [i915]`, 2026-07-02 21:10), wedging GPU memory management until reboot. Mitigation: keep Firefox on software decode (§12c of `finish-installation-commands.md`). Escape hatch: `linux-cachyos-lts 6.18.35`. Re-test hardware decode after the next kernel bump (§12f) |
| NVIDIA GSP "Reset required" after s2idle resume | ⚠ Open — driver `610.43.02` (open GSP modules): the 2026-07-02 20:48 resume failed `kgspWaitForRmInitDone` → dGPU unusable until reboot; every client touching it afterwards logs NVRM errors (384/344/359 across the last three suspend-cycle boots; a boot without a suspend logged 0). ~~Impact contained~~ **2026-07-12 escalation — no longer contained:** after ~4 h in s2idle (hypridle auto-suspend 14:22 → wake 18:24, kernel `7.1.2-3-cachyos`), resume failed `gpuPowerManagementResume: GSP boot failed at resume (bootMode 0x1): 0x62` and this time **crashed `nvidia_modeset` mid-resume** (page-fault oops in `FreeDeviceReference` inside `nvkms_resume`; `systemd-sleep` "exited with irqs disabled", SIGKILLed; `systemd-suspend.service` failed). Collateral: TB4 bridge `02:00.0` (Goshen Ridge dock) "not ready 1023ms after resume; giving up" → entire downstream tree (USB, r8152 Ethernet, dock displays) torn down; Hyprland lost all outputs (`hyprpolkitagent: There are no outputs`) → black screen on every panel incl. eDP-1; processes went SIGKILL-immune (`snapper-cleanup: Processes still around after SIGKILL`) → forced power-off ~18:52. i915 logged zero errors — purely the NVIDIA resume path. `PreserveVideoMemoryAllocations=1` + `/var/tmp` spill + nvidia-{suspend,resume} services all ran correctly; driver/firmware bug, not misconfig. **Mitigation 2026-07-12:** hypridle 20-min suspend is now battery-only (Hypridle row above), and logind lid-switch on external power set to ignore. Untried escalations if suspend-on-battery also crashes: `NVreg_EnableS0ixPowerManagement=1` (currently `0`; NVIDIA's recommended mode for s2idle laptops) or `NVreg_DynamicPowerManagement=0x00` (keep dGPU powered). Re-test on each driver update past 610.43.02 |
| VLC not installed (video playback) | ✅ Resolved 2026-07-31 — the machine had a binary-less half-install: `vlc-plugins-all` was explicit (libvlc + every codec plugin) but the `vlc` package and its Qt GUI never were, so no `vlc` on `$PATH`. Installed `vlc 3.0.23_2-9.1` — only 5 packages, since the plugin deps were already satisfied. Elephant hot-reloaded (score 88, no restart). **Hardware decode pinned off** in `~/.config/vlc/vlcrc` (`[avcodec]`/`avcodec-hw=none`): VLC's default `avcodec-hw=any` routes VA-API → iHD → the iGPU, the exact path that hung the video engine on 2026-07-02 (i915 row below), and `env.conf` can't reach it because Walker launches apps from the systemd `--user` env. Verified by verbose playback — `looking for hw decoder module matching "none" … no hw decoder modules matched` → software decode, 0 kernel GPU errors. Also confirmed VLC doesn't rewrite `vlcrc` on exit (md5 unchanged), so the hand-written config is stable. Details: `finish-installation-commands.md` §13. **Follow-up:** re-enable hardware decode together with Firefox's prefs (§12f) once a kernel past `7.0.12-1-cachyos` proves stable — and if `haruna`/mpv ever becomes the daily driver, pin it too (`hwdec=no`). |
| Compositor renders on the Intel iGPU, not the dGPU | ℹ️ Discovery 2026-07-02 — aquamarine log: `card2` (i915) "becomes primary drm", `CDRMRenderer on renderD129`; all three monitors are iGPU connectors. Older docs' "NVIDIA-primary" framing is wrong. Consequence: `GBM_BACKEND=nvidia-drm` + `__GLX_VENDOR_LIBRARY_NAME=nvidia` in `env.conf` force Hyprland-spawned GL clients onto a dGPU that's offload-only (cross-GPU copies; often dead post-resume) — left untouched for now, evaluate removing them separately |
| Plugging a USB device (Kobo e-reader) reshuffles the monitor layout | ✅ Resolved 2026-08-03 — **Topology:** every external pixel reaches this machine through **one** connector. Type-C `port0` (`/sys/devices/platform/USBC000:00/typec/port0`) binds `usb4_port1` → Thunderbolt `domain0` → **Plugable TBT4-UD5**, and both externals are DP tunnels over it (`card1-DP-1`, `card1-DP-2` on i915; the laptop's own `card0-HDMI-A-1` is NVIDIA and disconnected). That same connector's USB2 lane is `usb3-port4` on the **PCH xHCI `0000:00:14.0`**. The Kobo enumerated on **`usb 3-3` — root port 3 of that same controller**. **Kernel evidence** (23:13:35–23:14:08): four failed attempts with `error -71` (EPROTO), `usb usb3-port3: attempt power cycle`, two × `WARN: invalid context state for evaluate context command` (an xHCI **host-controller** fault, not device-level), `unable to enumerate USB device`, then a **30 s gap** before it finally came up on attempt 5. Failures were at full-speed (12M), the success at high-speed (480M) — the Kobo re-attaches its gadget after the on-device "Connect" prompt; the `-71` storm points at a marginal cable. When that controller fault reaches the Type-C side, the dock renegotiates and both DP tunnels drop/restore. **Amplifier (the actual damage):** `monitor-autoswitch.sh` acted on every raw event after a flat `sleep 0.5`, turning a sub-second blink into `remove → apply 'onescreen' → add → apply 'read'`, and `apply_onescreen` then still hardcoded the retired Samsung's `DP-1 1920×1080@120 scale 1`. **Fixes:** (1) daemon debounced — burst coalescing + two-sample stability check (§11); (2) `desktop`/`onescreen` made capability-based (row above); (3) `monitors.conf` monitors **and workspaces** bound by `desc:` (§1). Regression-tested offline with synthetic `.socket2` fixtures: a 6-event blink burst now yields exactly **one** apply, eDP-1-only and non-monitor events yield none, and an add re-applies even when the profile name is unchanged. ⚠ **Scope caveat:** on the 2026-08-03 plug the displays did **not** actually drop — zero DRM hotplug in the kernel log, zero monitor events in `hyprland.log` after startup, and `swayosd` `NRestarts=0` proves `monitor-mode.sh` never re-ran. The fault→tunnel-drop step is the mechanism *when* it fires, not something observed that evening; the amplifier bugs it would have hit were real and are what got fixed. **Mitigations:** plug the Kobo into a **dock** USB-A port (bus 2, controller `0000:00:0d.0` — a different xHCI, so a failed enumeration can't power-cycle a port beside the Thunderbolt connector), and use a known-good data cable. |

---

## 16. Repo Layout

```
cachyPool/
├── cachyos-hyprland-setup.md          ← original install guide (May 2026)
├── spected-installation.md            ← expected/recommended stack
├── system-state-findings.md           ← scan report after install
├── finish-installation-commands.md    ← step-by-step remediation
├── shortcuts.md                        ← daily shortcuts + workflows + Walker/Yazi/Kitty + troubleshooting (merged 2026-05-23, replaces the old USABILITY.md)
├── ACTUAL-CONFIGURATION.md            ← this file
└── configs/                           ← live copies of all dotfiles
    ├── hypr/
    │   ├── autostart.conf
    │   ├── env.conf
    │   ├── hypridle.conf
    │   ├── hyprland.conf
    │   ├── hyprlock.conf
    │   ├── hyprpaper.conf
    │   ├── input.conf
    │   ├── keybindings.conf
    │   ├── look.conf
    │   ├── monitors.conf
    │   ├── monitors-read.conf         ← alternate "read" profile (not sourced)
    │   ├── windowrules.conf
    │   └── scripts/
    │       ├── monitor-mode.sh        ← apply a named layout
    │       ├── monitor-autoswitch.sh  ← hotplug auto-switch daemon
    │       └── show-shortcuts.sh      ← keybinding cheatsheet popup (Super+/ + Walker "Shortcuts")
    ├── waybar/
    │   ├── config.jsonc
    │   └── style.css
    ├── kitty/
    │   ├── kitty.conf
    │   └── themes/
    ├── vlc/                           ← mirrors ~/.config/vlc/
    │   └── vlcrc                      ← hardware decode pinned off (avcodec-hw=none) — see §7 media note
    ├── applications/                  ← mirrors ~/.local/share/applications/
    │   ├── gimp.desktop               ← override: Name=GIMP (shadows the packaged entry) — §7
    │   └── shortcuts.desktop          ← "Shortcuts" Walker launcher entry
    └── systemd/user/                  ← mirrors ~/.config/systemd/user/
        └── swayosd.service            ← Restart=always OSD server (survives monitor switches)
            └── Catppuccin-Mocha.conf
```

---

## 17. How to Replicate This Setup Elsewhere

If you ever rebuild this machine (or set up a second one), the minimal sequence:

1. Install CachyOS, pick **Hyprland + KDE-Desktop**, btrfs, Limine.
2. Boot, run `sudo cachyos-chwd -a` to install NVIDIA correctly.
3. Verify `cat /proc/cmdline | grep modeset` shows `nvidia-drm.modeset=1`. If not, add via `/etc/default/limine` + `sudo limine-mkinitcpio`.
4. Install the full Hyprland stack (see section 4–8 above, or `cachyos-hyprland-setup.md` section 4).
5. Restore dotfiles: `cp -r configs/hypr ~/.config/`, same for `waybar/` and `kitty/`.
6. Wallpaper: `mkdir -p ~/Pictures/Wallpapers && cp wall.jpg ~/Pictures/Wallpapers/` (or download from a Catppuccin wallpaper repo).
7. Apply `finish-installation-commands.md` §10 to disable `plasmalogin.service` and switch to `getty@tty1` autologin + fish `exec start-hyprland`. (Or skip §10 to keep the PlasmaLogin greeter — pick Hyprland session at the greeter and log in.)
8. Verify: `hyprctl version`, `hyprctl monitors`, `nvidia-smi`.
9. The autostart entries in `~/.config/hypr/autostart.conf` bring up bar, wallpaper, notifications, polkit, clipboard, network/BT tray, and the walker resident service automatically.

---

*Generated 2026-05-21 from live system scan; refreshed 2026-05-22 after Section 6 TB fix landed. Update this file whenever a major change lands (kernel upgrade, new daemon, new monitor, etc.) by re-running the verification block in section 9 of `finish-installation-commands.md`.*
