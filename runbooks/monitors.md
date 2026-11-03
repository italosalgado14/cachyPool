# Monitors: Scaling, Profiles and the Hyprmon Editor

> Part of the `cachyPool` runbooks. Section numbers are **preserved** from
> `finish-installation-commands.md`, dissolved 2026-11-03 — a `§N` reference
> anywhere in this repo still resolves by number. Index and conventions:
> `README.md`. Live-state history: `../CHANGELOG.md`.

Per-panel scaling, and how monitor layouts are edited and applied — Hyprmon as the visual editor, `monitor-mode.sh` as the only applier.

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

- `../ACTUAL-CONFIGURATION.md`: header, §5 `hyprmon-bin` row, §11 file list and profile bullets, §15 new row, §16 repo layout.
- `../shortcuts.md`: Quick reference and §1.1 `Super+Shift+M`, §3 editing workflow, §11 `monitors.conf` row.
- `../CLAUDE.md`: monitor section notes the profile JSONs and the "never `S` / `--profile`" rule.

---


---

## Issue history

Moved here 2026-11-03 from `../ACTUAL-CONFIGURATION.md` §15, verbatim. Those table
cells had grown into multi-kilobyte incident analyses; §15 is now a status table
and the reasoning lives beside the runbook it explains.

### Plugging a USB device (Kobo e-reader) reshuffles the monitor layout

✅ Resolved 2026-08-03 — **Topology:** every external pixel reaches this machine through **one** connector. Type-C `port0` (`/sys/devices/platform/USBC000:00/typec/port0`) binds `usb4_port1` → Thunderbolt `domain0` → **Plugable TBT4-UD5**, and both externals are DP tunnels over it (`card1-DP-1`, `card1-DP-2` on i915; the laptop's own `card0-HDMI-A-1` is NVIDIA and disconnected). That same connector's USB2 lane is `usb3-port4` on the **PCH xHCI `0000:00:14.0`**. The Kobo enumerated on **`usb 3-3` — root port 3 of that same controller**. **Kernel evidence** (23:13:35–23:14:08): four failed attempts with `error -71` (EPROTO), `usb usb3-port3: attempt power cycle`, two × `WARN: invalid context state for evaluate context command` (an xHCI **host-controller** fault, not device-level), `unable to enumerate USB device`, then a **30 s gap** before it finally came up on attempt 5. Failures were at full-speed (12M), the success at high-speed (480M) — the Kobo re-attaches its gadget after the on-device "Connect" prompt; the `-71` storm points at a marginal cable. When that controller fault reaches the Type-C side, the dock renegotiates and both DP tunnels drop/restore. **Amplifier (the actual damage):** `monitor-autoswitch.sh` acted on every raw event after a flat `sleep 0.5`, turning a sub-second blink into `remove → apply 'onescreen' → add → apply 'read'`, and `apply_onescreen` then still hardcoded the retired Samsung's `DP-1 1920×1080@120 scale 1`. **Fixes:** (1) daemon debounced — burst coalescing + two-sample stability check (`../ACTUAL-CONFIGURATION.md` §11); (2) `desktop`/`onescreen` made capability-based (row above); (3) `monitors.conf` monitors **and workspaces** bound by `desc:` (`../ACTUAL-CONFIGURATION.md` §1). Regression-tested offline with synthetic `.socket2` fixtures: a 6-event blink burst now yields exactly **one** apply, eDP-1-only and non-monitor events yield none, and an add re-applies even when the profile name is unchanged. ⚠ **Scope caveat:** on the 2026-08-03 plug the displays did **not** actually drop — zero DRM hotplug in the kernel log, zero monitor events in `hyprland.log` after startup, and `swayosd` `NRestarts=0` proves `monitor-mode.sh` never re-ran. The fault→tunnel-drop step is the mechanism *when* it fires, not something observed that evening; the amplifier bugs it would have hit were real and are what got fixed. **Mitigations:** plug the Kobo into a **dock** USB-A port (bus 2, controller `0000:00:0d.0` — a different xHCI, so a failed enumeration can't power-cycle a port beside the Thunderbolt connector), and use a known-good data cable.

### Monitor layouts only editable as hand-written coordinates

✅ Resolved 2026-10-15/16. `hyprmon-bin 0.0.17-1` installed and verified, except a real drag-and-save, which nobody has done yet. **Before:** rearranging screens meant editing offsets like `$((2048 + EXT_OTHER_W))` in `monitor-mode.sh`, and there was no quick way into monitor settings. Omarchy has the same gap: its *Setup > Monitors* opens `monitors.lua` in an editor, and its manual points at Hyprmon (not installed by default). **Fix:** a hybrid. Hyprmon is the visual editor; `monitor-mode.sh` applies its profiles through `apply_from_profile` when the monitor set matches exactly, and falls back to the capability code otherwise. `hyprmon-edit.sh` blocks hyprmon's config write and reload. There is a `Super+Shift+M` / Walker "Monitors" menu. **Verified** with the JSON path live: `read` ↔ `desktop` give identical geometry to before, and the box test was portrait `1260×1992` and landscape `2028×1224`. The daemon held the manual choice. **After install (2026-10-16):** `hyprmon --list-profiles` shows `desktop` and `read *`, and `--active-profile` → `read`, so hyprmon accepts the seeded JSON as its own. A scripted session through the wrapper did `P` → `S` → `Q`. `P` wrote a profile identical to `read.json` on every applied field (`hardware_id`, mode, `X`/`Y`, scale, transform, active); only the Hz decimals differ. `S` wrote port-bound `monitor=` lines into the scratch file, which is what it would have appended to `hyprland.conf`. Geometry was unchanged while hyprmon was still open, so the reload was blocked. Quitting re-applied `read`, and the `.bak` copies were removed. A dry run fed the hyprmon-written JSON emitted the same specs as the seed. Rejected: adopting hyprmon wholesale, because its profile apply brings back the stale-layout-box bug, rewrites a config and reloads on every switch, has no auto-switch, and only knows specific monitors. Details: `../ACTUAL-CONFIGURATION.md` §11, §16.

### Desktop 3-across profile not re-fitted for the Xiaomi

✅ Resolved 2026-08-03 — the Samsung FHD 24" was swapped for a **Xiaomi Mi Monitor 27" 4K** (`3840×2160@60`) on 2026-07-11, but `monitors.conf`/`apply_desktop` kept hardcoding `DP-1 1920×1080@120` + a `DP-2 2560×1600` slot the Xiaomi can't do. **Fix:** `apply_desktop` now resolves both externals by capability (laptop left 0–2048 · desk external centre at its best mode/scale · QHD portable right), and `monitors.conf` carries the matching logical geometry `eDP-1 0–2048 · Xiaomi 2048–5120 · QHD 5120–7168` (total 7168) bound by `desc:` rather than `DP-*`. Same commit fixed `apply_onescreen` (identical Samsung hardcode) and `read`'s fallback. Live-verified: `hyprctl reload` placed the Xiaomi at `2048x0 3840×2160 scale 1.25` despite it being `DP-2`. All Samsung references are gone from the live config.

### Rotated panel tiled with landscape geometry

✅ Resolved 2026-08-04 — in `read`, the **VCHANCE AQ16H** rendered portrait but tiled landscape: a window came out **2028×1224 on the 1280×2048 screen**, spilling 758px past the right edge. Cause: `hyprctl keyword monitor …,transform,N` against an **already-enabled** output rotates the render pass but does **not** rebuild the monitor's layout box, and `hyprctl monitors` reports the new transform either way — so it read as correctly configured. **Symmetric**: leaving portrait stranded a 1280×2048 box on a 2048×1280 screen, so `desktop`/`trio`/`onescreen` were affected too. **Fix:** new `apply_monitor_tf()` in `monitor-mode.sh` cycles the output (disable → re-enable) whenever the target transform differs from the running one; all four profiles now set the AQ16H's transform through it, explicitly stating `transform,0` where landscape is wanted. Verified **not** to rebuild the box: `dispatch forcerendererreload`, `dispatch moveworkspacetomonitor`, and re-applying the identical spec. Since the cycle emits external hotplug events, a fingerprint handshake (`$XDG_RUNTIME_DIR/hypr-monitor-fingerprint`, `SELF_GRACE=15 s`) stops `monitor-autoswitch.sh` reverting a manual `Super+M` choice — see §11. Live-verified both directions: portrait → `1260×1992`, landscape → `2028×1224`, Waybar/swayosd survive, workspaces re-home, and a real unplug still switches profile.

### RTK HDMI adapter reports garbage EDID

ℹ️ Hyprland shows `Invalid Vendor Codename - RTK HDMI 0x01010101` for the portable QHD — a **VCHANCE AQ16H 16"** (currently `DP-1`; port floats), whose Realtek scaler publishes no vendor string and a placeholder serial. Modes still detected correctly; runs at its native 2560×1600@120 as expected. (The Xiaomi on `DP-2` reports a clean `Xiaomi Corporation Mi Monitor` EDID.) **No longer purely cosmetic since 2026-08-03:** that string is now a `desc:` match key in `monitors.conf`, using the prefix `Invalid Vendor Codename - RTK HDMI`. The road-going **demoset** FHD portable is distinguished by `demoset` in its description, so the two don't collide — but re-check the prefix if a third generic RTK-adapter panel ever appears, and re-verify after any adapter swap.
