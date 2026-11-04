# Shortcuts & Daily Usability — Hyprland on CachyOS

**Machine:** Acer Predator PT516-52s (Triton 500 SE) · **Last verified:** 2026-11-03
**Source of truth:** `~/.config/hypr/lua/bindings-*.lua` (mirrored in `configs/hypr/lua/`).
Press **`Super`+`K`** for the exhaustive list — it is generated from the binds' own
descriptions, so it cannot go out of date. This file is the curated version, with the *why*.

> **`Super`** = the Windows/⌘ key (a.k.a. `mainMod`). Every shortcut below uses Super as the anchor.

This is the day-to-day reference: the "memorize these first" cheatsheet up top, then the full keybinding tables, recommended workflows, app-specific tips, and troubleshooting.

---

## Quick reference — memorize these first

| Combo | Action |
|---|---|
| `Super` + `Enter` | Open Kitty terminal |
| `Super` + `Space` | Walker app launcher |
| `Super` + `Shift` + `Enter` | Open Firefox |
| `Super` + `E` or `Super` + `Shift` + `F` | File manager (Yazi in Kitty) |
| `Super` + `Q` or `Super` + `W` | Close active window |
| `Super` + `Ctrl` + `L` | Lock screen (Hyprlock). ⚠ **`Super`+`L` alone no longer locks** — it is left free for a future workspace-layout cycle, Omarchy's meaning for that key |
| `Super` + `M` | Minimize the window (parks it on a special workspace; `Super`+`Shift`+`M` brings them back) |
| `Super` + `grave` | Quake console — a terminal that drops over whatever workspace you are on |
| `Super` + `Ctrl` + `Delete` | Toggle the laptop panel (clamshell). ⚠ The five monitor **profiles** are parked — see §3 |
| `Super` + `Shift` + `Q` | Exit Hyprland (drops to tty1 → autologin re-`exec`s Hyprland; behaves like "restart compositor". To actually log out: `Ctrl+Alt+F2` → `loginctl terminate-user isalgado`) |

> The curated tables follow in §1 (**`Super`+`K`** prints the generated full list). Workflows
> in §2. Walker / Yazi / Kitty deep-dives in §4–§6.

---

## 1. All keybindings

Since 2026-11-03 this is **Omarchy's keymap** (their `quattro` branch), wired to this
machine's own apps and hardware. Three things to unlearn if your hands remember the old map:
`Super`+`L` no longer locks (`Super`+`Ctrl`+`L` does), `Super`+`V` no longer floats
(`Super`+`T` does — `V` is paste now), and `Super`+`Shift`+arrows **swaps** windows instead of
moving them. `Super`+`M` minimizes; it used to switch monitor profile.

> **`Super`+`K`** prints the full generated list from `hyprctl binds -j`. The tables below are
> the curated subset, in the same order as the modules in `configs/hypr/lua/`.

### 1.1 Launching things

| Combo | Action |
|---|---|
| `Super` + `Enter` | Open Kitty terminal |
| `Super` + `Space` | Walker app launcher |
| `Super` + `Shift` + `Enter` | Open Firefox |
| `Super` + `E` / `Super` + `Shift` + `F` | File manager (Yazi in Kitty) |
| `Super` + `grave` | Quake console (drops over the current workspace; seeded with Kitty on first open) |
| `Super` + `K` / `Super` + `/` | Shortcuts cheatsheet — generated from the binds (also a **Shortcuts** entry in Walker) |
| `Super` + `Ctrl` + `L` | Lock screen (Hyprlock) |
| `Super` + `Q` / `Super` + `W` | Close active window |
| `Super` + `Shift` + `Q` | Exit Hyprland (drops to tty1 → autologin re-`exec`s Hyprland; "restart compositor". Real logout: `Ctrl+Alt+F2` → `loginctl terminate-user isalgado`) |

### 1.2 Walker modes (also reachable by typing a prefix character into Walker)

| Combo | Mode | Prefix |
|---|---|---|
| `Super` + `Space` | Open Walker (default — apps + fuzzy search; type a prefix below to switch) | — |
| `Super` + `.` | Emoji / symbol picker | `.` |
| `Super` + `Ctrl` + `E` | Emoji / symbol picker | `.` |
| `Super` + `Ctrl` + `V` | Clipboard history (from cliphist) | `:` |
| (in Walker) type `=` | Calculator | `=` |
| (in Walker) type `/` | File search | `/` |
| (in Walker) type `>` | Shell command runner | `>` |
| (in Walker) type `:` | Clipboard history | `:` |
| (in Walker) type `@` | Web search (Walker 2.x default — *not* `?`) | `@` |
| (in Walker) type `;` | List all loaded Elephant providers | `;` |

### 1.3 Window management

| Combo | Action |
|---|---|
| `Super` + `T` | Toggle floating / tiling |
| `Super` + `F` | Fullscreen (covers the screen) |
| `Super` + `Alt` + `F` | Maximized (fills the tiled space) — two different things |
| `Super` + `P` | Pseudo-tile (preserve size when moving) |
| `Super` + `J` | Toggle dwindle split direction |
| `Super` + `M` | Minimize — parks the window on the `minimized` special workspace |
| `Super` + `Shift` + `M` | Show the minimized windows again |
| `Super` + `Backspace` | Toggle transparency on this window (a `transparent` tag plus an opacity rule) |
| `Super` + `Shift` + `Backspace` | Toggle gaps on/off |
| `Super` + `Ctrl` + `Z` / `Super` + `Ctrl` + `Alt` + `Z` | Zoom the screen in one step / reset |

**Window groups (tabs in one tile):**

| Combo | Action |
|---|---|
| `Super` + `G` | Toggle grouping on the active window |
| `Super` + `Alt` + arrows | Pull the window into the group in that direction |
| `Super` + `Alt` + `G` | Take it out of the group |
| `Super` + `Alt` + `Tab` / `Super` + `Alt` + `Shift` + `Tab` | Next / previous window inside the group |
| `Super` + `Alt` + `1`…`5` | Jump straight to the Nth window of the group |

### 1.4 Navigation (focus)

| Combo | Action |
|---|---|
| `Super` + `←` / `→` / `↑` / `↓` | Focus neighbour window |
| `Alt` + `Tab` / `Alt` + `Shift` + `Tab` | Cycle windows without thinking in directions |
| `Ctrl` + `Alt` + `Tab` / + `Shift` | Focus the next / previous **monitor** |
| `Super` + `Tab` / `Super` + `Shift` + `Tab` | Next / previous workspace **on this monitor** |
| `Super` + `Ctrl` + `Tab` | Back to the workspace you came from |
| `Super` + scroll | Cycle this monitor's workspaces |
| `Super` + drag (left mouse) | Move window |
| `Super` + drag (right mouse) | Resize window |

### 1.5 Moving windows

| Combo | Action |
|---|---|
| `Super` + `Shift` + `←` / `→` / `↑` / `↓` | **Swap** this window with the one in that direction |
| `Super` + `Shift` + `Ctrl` + arrows | Send the window to the monitor in that direction |
| `Super` + `Shift` + `Alt` + arrows | Send the whole **workspace** to the monitor in that direction |
| `Super` + `-` / `Super` + `=` | Resize horizontally by 100 px (`Shift` for vertical) |
| `Super` + `Alt` + `-` / `=` | …by 25 px, for fine work |
| `Super` + `Ctrl` + `-` / `=` | …by 300 px, for big moves |

### 1.6 Workspaces

Ten per monitor.

| Combo | Action |
|---|---|
| `Super` + `1`…`0` | The Nth workspace **of the screen you are looking at** |
| `Super` + `Shift` + `1`…`0` | Send the window to that slot and follow it |
| `Super` + `Shift` + `Alt` + `1`…`0` | Send it there silently, without following |
| `Super` + `S` / `Super` + `Alt` + `S` | Toggle the scratchpad / park the window on it |
| `Super` + `grave` / `Super` + `Shift` + `grave` | Toggle the Quake console / move the window onto it |

> Each panel owns a static block of ten ids anchored by EDID: **eDP-1 `1-10`**, **Xiaomi
> `11-20`**, **portable QHD `21-30`**, anything unknown `91-100`. So `Super`+`4` is your
> fourth workspace on whichever screen you are on, not "the laptop" as it used to be.
> Mechanism, and why Omarchy's own implementation was not imported:
> `runbooks/monitors.md` §21.

### 1.7 Screenshots

| Combo | Action |
|---|---|
| `Print` | Region capture → opens **satty** for annotation → copies to clipboard |
| `Shift` + `Print` | Full-screen capture → opens satty → copies to clipboard |
| `Super` + `Print` | Colour picker (`hyprpicker -a`). ⚠ **Not installed yet** — waits for the next `paru -Syu` |

### 1.8 Audio / brightness (via SwayOSD popups)

| Key | Action |
|---|---|
| `Fn` + Volume Up/Down/Mute | Adjust output volume |
| `Fn` + Mic Mute | Toggle microphone |
| `Fn` + Brightness Up/Down | Backlight (`nvidia_wmi_ec_backlight`) |
| Media keys (Play/Next/Prev) | Control playerctl-aware apps (Spotify, browsers) |

**Notifications (mako):**

| Combo | Action |
|---|---|
| `Super` + `,` | Act on the last notification (`makoctl invoke`) |
| `Super` + `Alt` + `,` | Dismiss the last one |
| `Super` + `Shift` + `,` | Dismiss them all |
| `Super` + `Shift` + `Alt` + `,` | Restore the last dismissed one |

### 1.9 Touchpad gesture

| Input | Action |
|---|---|
| 3-finger horizontal swipe | Switch workspace |
| Closing the lid | Turns eDP-1 off **only if another screen is connected**; opening it puts the panel back and hands the refresh rate to `edp-rate.sh`. Suspend-on-lid stays with logind/hypridle |
| `Super` + `C` / `V` / `X` / `A` | Universal copy / paste / cut / select-all — sends `Ctrl+…` to normal windows and `Ctrl+Shift+…` to terminals, decided by the `terminal` tag in `lua/windowrules.lua` |

> The clipboard binds are the most fragile thing in this map: they inject synthetic key state,
> split down/up by 50 ms to work around Hyprland leaving keys stuck. If they misbehave, delete
> `lua/bindings-clipboard.lua` and its `require` — nothing else depends on it, and
> `Super`+`V` simply goes quiet.

---

## 2. Recommended daily workflows

### A. "Start a coding session"

1. `Super` + `Enter` → open Kitty
2. `cd ~/code/<project>` then `code .` (VS Code) — VS Code is installed (`visual-studio-code-bin`) and runs on Wayland via the `ELECTRON_OZONE_PLATFORM_HINT=auto` env in `env.conf`.
3. `Super` + `2` to keep VS Code on a clean workspace (Xiaomi, desk primary)
4. Another Kitty on `Super` + `3` for `git`/build commands.
5. If you need a side-by-side editor + browser:
   - VS Code on workspace `2` (Xiaomi)
   - Firefox (`Super` + `Shift` + `Enter`) → workspace `6` (HDMI right) for docs/MDN/preview
   - Workspace `4`/`5` on the laptop for logs / terminal output

### B. "I need to look something up fast"

- `Super` + `Space` → start typing. Walker fuzzy-matches installed apps + recents.
- Need to calculate something? `Super` + `Space`, then `=` → `2048 * 1.25` → `Enter` copies result.
- Insert an emoji into a chat? `Super` + `Ctrl` + `E` → type `smile` → `Enter` pastes.

### C. "I copied something earlier and lost it"

- `Super` + `Ctrl` + `V` → Walker opens with full clipboard history (powered by `cliphist`, fed by the two `wl-paste --watch` autostart entries).
- `cliphist` retains both text and images.

### D. "Manage tiling — I want this window over there"

The compositor is **dwindle**: every new window splits the focused space in half along its longer axis.

1. **Focus the window** you want to move (`Super` + arrows or click).
2. **`Super` + `Shift` + arrow** — slot it into a neighbor position.
3. To change *how* the split happened (vertical ↔ horizontal): focus the window, `Super` + `J`.
4. To break out of tiling for a single window: `Super` + `T` (toggle floating). Then drag with `Super` + left-mouse to move it freely, `Super` + right-mouse to resize.
5. To send a window to another monitor's workspace: `Super` + `Shift` + (`1`/`2`/`3` for the Xiaomi desk primary, `4`/`5` for laptop, `6`–`9` for the portable QHD). Then follow with `Super` + N to jump to that workspace.

### E. "Quick screenshot for a bug report / Slack"

- Region: `Print` → drag to select → satty opens. Annotate with arrows/text/blur → press `Ctrl`+`C` (or close) → result is on your clipboard, ready to paste.
- Full screen: `Shift` + `Print`.

### F. "I'm done for the day"

- `Super` + `Ctrl` + `L` → lock immediately. Hyprlock shows a blurred wallpaper + clock + password input.
- Or just walk away — Hypridle handles it:
  - 5 min idle → lock screen
  - 10 min idle → monitors sleep (DPMS off)
  - 20 min idle → system suspend — **only on battery** (since 2026-07-12; on AC/USB-C power the machine stays awake because resume from long s2idle can crash the NVIDIA driver). Dormant while the battery was out; armed again on **2026-10-31**

### G. "Bluetooth headphones / mouse"

- Tray icon in Waybar (right cluster) — click to open Blueman.
- Or CLI: `bluetoothctl scan on` → `pair XX:XX:...` → `connect XX:XX:...`.

### H. "WiFi / Network"

- `nm-applet` tray icon (right cluster) → click → list of networks.
- Or CLI: `nmcli device wifi list` / `nmcli device wifi connect <SSID> password <pw>`.

---

## 3. Multi-monitor layout (current)

> ⚠ **2026-11-03: the profile system described below is parked.** Hyprland 0.57.1 removed
> `hyprctl keyword`, which is how `monitor-mode.sh` and the hotplug autoswitcher apply a
> layout. Nothing auto-switches, no key opens the menu or Hyprmon, and the live geometry is
> the static 3-across in `~/.config/hypr/lua/monitors.lua`. `Super`+`Ctrl`+`Delete` toggles
> the laptop panel natively. The rest of this section is what the port has to restore —
> `runbooks/monitors.md` §16.

**Live right now** is the `read` profile (the desk auto-picks it): the **Xiaomi 27" 4K**
landscape-left @ 3072×1728 (scale 1.25) · portable QHD rotated **portrait**-right (1280×2048
logical) · laptop off.

The portable is a **VCHANCE AQ16H** 16", running native **2560×1600@120**. Hyprland labels it
`Invalid Vendor Codename - RTK HDMI` because its Realtek scaler sends no vendor string — that
is the panel's normal appearance, not a fault.

The static `desktop` 3-across profile below is the reference layout. It was **re-fitted for
the Xiaomi on 2026-08-03** (it previously held the retired Samsung's geometry):

```
[ eDP-1 laptop ]  [ Xiaomi 27" 4K centre ]  [ portable QHD right ]
  2048 × 1280         3072 × 1728              2048 × 1280
   scale 1.25          scale 1.25               scale 1.25
   0 – 2048px          2048 – 5120px            5120 – 7168px
   240 Hz              60 Hz                    120 Hz
```

- **Desk primary is the Xiaomi 27" 4K** (replaced the Samsung FHD 24", 2026-07-11) — workspace 1 lives there, new windows default to it.
- Workspaces 4 / 5 live on the laptop · 6–9 on the portable QHD (right).
- Monitors **and workspaces are bound by EDID description** (`desc:`), not by `DP-1`/`DP-2`.
  Port names float here — both externals are DP tunnels over one Thunderbolt connector, so
  whichever trains first takes the low number. Until 2026-08-03 the name-bound rules had
  quietly put workspaces 1–3 on the 16" portable and 6–9 on the Xiaomi.
- Move the cursor straight across the seam to traverse monitors.

The layout above is the static `desktop` profile. As of 2026-06-10 a hotplug daemon
(`~/.config/hypr/scripts/monitor-autoswitch.sh`, started from `autostart.conf`) picks
the layout automatically from what's plugged in:

| Connected | Auto profile | Arrangement (left → right) |
|---|---|---|
| Two externals incl. the **demoset** FHD portable | `trio` | FHD · **laptop (center)** · QHD — all landscape |
| Two externals (e.g. Xiaomi 4K + portable QHD) | `read` | desk external landscape (Xiaomi @ 3072×1728) · portable QHD **rotated portrait** · **laptop off** |
| One external | `onescreen` | external · laptop |
| Integrated screen only | `laptop` | laptop alone |
| — | `desktop` | never auto — `Super` + `M` only |

- `Super` + `M` toggles by hand: **read ↔ desktop** at the desk, **read ↔ trio** on the
  road (it prefers `trio` when the demoset FHD portable is connected). The choice holds
  until the next **external** plug/unplug, when the daemon re-asserts the automatic profile.
- Apply any profile directly: `~/.config/hypr/scripts/monitor-mode.sh {desktop|read|laptop|onescreen|trio}`.
- **All** profiles pick panels by capability (QHD = whichever external does `2560×1600`),
  so they also work on the road where DP-1/DP-2 swap with plug order. `desktop` and
  `onescreen` joined `read`/`trio` in this on 2026-08-03 — before that they forced the
  retired Samsung's `1920×1080` onto whatever landed on `DP-1`.
- The daemon is **debounced**: it waits for the hotplug burst to go quiet (~2 s) and for the
  monitor set to hold still before applying anything, so a brief display blink — a dock
  renegotiation, a resume, a USB device faulting on the shared controller — no longer
  reshuffles your layout. A real plug/unplug takes ~3 s to take effect.
- **Switching into or out of `read` blanks the portable (VCHANCE AQ16H) for about a second.**
  That's deliberate, not a glitch: Hyprland only rebuilds a monitor's tiling geometry when the
  output is cycled off and on, so rotating without the cycle left windows sized for landscape
  on the portrait screen — content running off the right edge. Fixed 2026-08-04; profiles that
  don't change the rotation switch instantly as before.
- **`Super` + `Shift` + `M` opens the Monitors menu** (also **Monitors** in Walker): pick
  a profile (the current one is marked `●`), open the Hyprmon editor, or show the live
  layout as a notification. It only lists the profiles that fit what's plugged in: `read`/
  `desktop` at the desk, `trio`/`read` with the demoset portable, `onescreen` with one
  external, `laptop` with none. The others overlap screens on the wrong set. Picking a
  profile is a manual override, same as `Super` + `M`.
- **Rearranging screens, macOS-style (since 2026-10-15):** menu → *Edit layout (Hyprmon)*
  opens Hyprmon in a floating Kitty. Drag the screens with the mouse (or arrows / `hjkl`;
  `G` grid size, `Shift`+`L` snapping, `R` scale, `C` advanced settings incl. rotation), press
  `A` to preview live, then `P` and type the **profile's name** (`desktop`, `read`, `trio`, `onescreen`, `laptop`). Quit
  with `Q`: the current profile is re-applied straight away, so a layout saved under the
  **current** profile's name shows up immediately. One saved under another name shows
  next time you switch to it. Saved so far: `desktop` and `read` (seeded from the hand-written
  geometry, so nothing changed visually).
  - **Never press `S`** in Hyprmon. In this setup it only writes a scratch file and its
    `hyprctl reload` is blocked, but `P` is the key that saves a profile.
  - Skip `O` (Hyprmon's own profile menu): it applies profiles the bare-keyword way. If you
    use it anyway, quitting re-applies the current profile properly.
  - Type the profile name; don't paste it. Hyprmon's name box only accepts one key at a time.
  - Don't switch an **external** monitor off inside Hyprmon: the auto-switcher reads that
    as an unplug and re-applies a profile ~3 s later.
  - A saved profile only applies when **exactly** its monitors are connected (matched by
    EDID, never by `DP-1`/`DP-2`). With any other set, e.g. a hotel monitor, the profile
    falls back to the hand-written capability-based layout, so new screens still work.
  - Hyprmon is AUR **`hyprmon-bin`**. Plain `hyprmon` on the AUR is an unrelated project.
- Geometry: a saved Hyprmon profile (`~/.config/hyprmon/profiles/<name>.json`, mirrored in
  `configs/hyprmon/profiles/`) wins; otherwise `monitor-mode.sh`'s hand-written layout.
  Full details in `ACTUAL-CONFIGURATION.md` §11 "Monitor profiles & auto-switching".

> If you want bigger UI on the laptop later: bump `eDP-1` scale to `1.333333` (2560 ÷ 1.333333 = **1920** logical) and shift the two externals right by the same 128 px — Xiaomi `@ 1920x0`, portable QHD `@ 4992x0` (1920 + 3072). Easiest now: do it in Hyprmon (`R` or `[`/`]` for scale, drag the others left) and save with `P` as `desktop`. For the boot default, also edit `monitors.conf`. See `runbooks/monitors.md` §5 for the math.

---

## 4. Walker — how to drive it

Walker (`Super` + `Space`) replaces rofi/wofi/krunner. Behaviors that are easy to miss:

- **Empty input** → recent apps + applications list
- **Type a partial name** → fuzzy match across apps + calculator results inline
- **Prefix character at start** switches mode (Walker 2.x / Elephant defaults):
  - `.foo` → emoji/symbol named "foo" (provider: `symbols`)
  - `=2+2` → calculator (provider: `calc`, via `qalc`)
  - `:` → clipboard history (provider: `clipboard`, fed by `cliphist`)
  - `/Pictures` → file search under home dir (provider: `files`)
  - `>htop` → run as shell command (provider: `runner`)
  - `@rust async` → web search (provider: `websearch`)
  - `;` → list all loaded Elephant providers (provider: `providerlist`)
- **Enter** activates the highlighted item
- **Shift + Enter** activates AND keeps Walker open (launch multiple apps in a row)
- **Escape** cancels
- **Up / Down** or **Ctrl-K / Ctrl-J** navigate the list
- **Type `Shortcuts`** (or `cheatsheet` / `hotkeys` / `keys`) → a **Shortcuts** app entry that opens this cheatsheet in a floating Kitty window. It's a normal `.desktop` app (`~/.local/share/applications/shortcuts.desktop`, mirrored in `configs/applications/`) backed by `~/.config/hypr/scripts/show-shortcuts.sh`; the same script is bound to `Super` + `K` (and `Super` + `/`). Since 2026-11-03 it is **generated** from `hyprctl binds -j`, so there is no curated subset left to keep in sync — give a bind a `description` in `configs/hypr/lua/` and it appears.

### 4.1 Architecture (matters when things break)

Walker 2.x is a thin GTK4 frontend; the actual capability comes from **Elephant**, a separate background daemon that loads each provider as a `.so` module. On this machine Elephant runs as a user systemd unit (`~/.config/systemd/user/elephant.service`) — see `runbooks/desktop-apps.md` §7e for the install path.

- Frontend daemon (autostart): `walker --gapplication-service` — keeps the GTK window pre-warmed.
- Backend daemon (user unit): `elephant.service` — must be `active` for any prefix or `walker -m <mode>` to return results. If it's down you'll see `Please install elephant.` on `walker -m clipboard` from a terminal.
- The `menus` provider loads but isn't shown by `elephant listproviders` — it's a separate subsystem invoked via `elephant menu …`, not a query provider.

---

## 5. Yazi — terminal file manager

`Super` + `E` opens Yazi inside Kitty. Vim-style by default.

Common keys (Yazi defaults — no custom config needed):

| Key | Action |
|---|---|
| `h` / `l` | Up a directory / enter directory |
| `j` / `k` | Down / up |
| `gg` / `G` | Top / bottom of list |
| `Space` | Toggle selection |
| `Enter` | Open file (text → micro / images → default viewer) |
| `y` / `x` / `p` | Yank (copy) / cut / paste |
| `d` | Delete (to trash) |
| `D` | Permanent delete |
| `a` | New file/dir (end in `/` for dir) |
| `r` | Rename |
| `.` | Toggle hidden files |
| `q` | Quit |

Image previews render in the right pane via Kitty's graphics protocol.

---

## 6. Kitty — terminal tips

The terminal uses JetBrains Mono Nerd Font 12pt + Catppuccin Mocha theme + 95% background opacity. Useful built-ins:

| Combo | Action |
|---|---|
| `Ctrl` + `Shift` + `T` | New tab |
| `Ctrl` + `Shift` + `Enter` | New split (window) inside Kitty |
| `Ctrl` + `Shift` + `]` / `[` | Next / previous split |
| `Ctrl` + `Shift` + `C` / `V` | Copy / paste |
| `Ctrl` + `Shift` + `+` / `-` | Font size up / down |
| `Ctrl` + `Shift` + `F2` | Edit kitty.conf live |
| `kitten icat IMAGE` | Show an image inline in the terminal |

---

## 7. Lock screen / idle

- **Manual lock:** `Super` + `Ctrl` + `L`
- **Auto-lock:** 5 minutes of input idle
- **Screen off:** 10 minutes
- **Suspend:** 20 minutes, **battery only** (will require password to resume). On AC/USB-C power the machine stays awake — changed 2026-07-12 after a resume-from-suspend NVIDIA crash (see `ACTUAL-CONFIGURATION.md` §15, GSP row).
- **Lid close:** ignored on external power (AC, USB-C PD, dock) and whenever docked with external monitors. Only on battery **and** undocked does it suspend, locking first. logind: `HandleLidSwitchExternalPower=ignore` in `/etc/systemd/logind.conf.d/50-no-suspend-on-external-power.conf`, written 2026-07-12 but only live since **2026-10-12**. ⚠ **Live again since 2026-10-31:** with the replacement pack fitted the machine can be on battery, so lid-close-on-battery and hypridle's 20-min suspend both fire for the first time since 2026-10-12 — that is the NVIDIA GSP resume-crash path (`ACTUAL-CONFIGURATION.md` §15).
- **Using it lid-closed on the dock:** works, and the TB4 monitors keep running. Stay in the `read` profile, which already turns the laptop panel off. In `desktop`, eDP-1 stays enabled behind the lid, holding workspaces 4–5, and the cursor can wander onto it. Idle lock (5 min) and screen-off (10 min) still apply with the lid closed; external keyboard or mouse input resets them.

To customize timeouts: edit `~/.config/hypr/hypridle.conf`, then restart the daemon: `pkill hypridle; hyprctl dispatch exec hypridle` (`hyprctl reload` does **not** re-read hypridle.conf).

---

## 8. Sound / mic

- PipeWire is the audio server (PulseAudio compatibility layer also active).
- Volume keys handled by SwayOSD → on-screen popup.
- Click the Pulseaudio icon in Waybar to open `pavucontrol` for routing, app-level volumes, default device.
- Current default output: **Samson Go Mic** (USB) — change in pavucontrol if you plug in different headphones.

---

## 9. Troubleshooting quick reference

| Symptom | Fix |
|---|---|
| Waybar disappeared | `pkill waybar; waybar & disown` |
| Wallpaper gone | `pkill hyprpaper; hyprpaper & disown` |
| Tray icon missing | Check `nm-applet`/`blueman-applet` is in `autostart.conf` and running |
| Walker won't open | `pkill walker; walker --gapplication-service & disown` |
| Walker opens but prefixes return "No results" / "Please install elephant." | `systemctl --user restart elephant.service`, then re-test `walker -m clipboard` from a terminal. Check `systemctl --user is-active elephant.service`. |
| Need to reload everything | `hyprctl reload` (re-reads all configs without logout) |
| Brightness key not working | `brightnessctl set 50%` to verify backlight works; check `swayosd-server` is running |
| Audio not working | `systemctl --user restart pipewire wireplumber pipewire-pulse` |

Check daemon liveness anytime:
```fish
for p in waybar mako hyprpaper hypridle hyprpolkitagent swayosd-server cliphist walker elephant nm-applet
  pgrep -af $p > /dev/null; and echo "$p: OK"; or echo "$p: DOWN"
end
```

---

## 10. What I don't use but it's there

- **Dolphin** (`dolphin`) — KDE's GUI file manager, installed because KDE-Desktop is the safety-net DE. Useful for "I need to drag-and-drop files" moments.
- **Micro** (`micro`) — terminal text editor with sane defaults; opened by Yazi's `Enter` on text files.
- **KDE apps** (Konsole, KCalc, etc.) — installed via the KDE fallback, can be launched from Walker if needed.

---

## 11. The three files you'll edit most

| File | What it controls |
|---|---|
| `~/.config/hypr/lua/bindings-*.lua` | Add/remove keyboard shortcuts (give each one a `description`) |
| `~/.config/hypr/lua/monitors.lua` | The layout, full stop — the profile system is parked (§3). ⚠ Saving a `.lua` reloads **nothing**: run `hyprctl reload` yourself |
| `~/.config/hypr/autostart.conf` | What launches when you log in |

After any change: `hyprctl reload` (no logout needed). Tracked copies live in `configs/hypr/` in this repo.

---

*Merged 2026-05-23: this file replaces the previous split between `shortcuts.md` (one-page cheatsheet) and `USABILITY.md` (daily reference). Verified live `~/.config/hypr/*` matches the mirrored `configs/hypr/*` in this repo, and live `hyprctl monitors` matches the layout in §3.*
