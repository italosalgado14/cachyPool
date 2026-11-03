# Desktop and Userland Apps

> Part of the `cachyPool` runbooks. Section numbers are **preserved** from
> `finish-installation-commands.md`, dissolved 2026-11-03 — a `§N` reference
> anywhere in this repo still resolves by number. Index and conventions:
> `README.md`. Live-state history: `../CHANGELOG.md`.

Terminal, file manager, lock-screen styling, the Walker/Elephant launcher stack, and the per-app workarounds this session needs (VS Code keyring, Ghostty vs Kitty).

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

**Why this is its own subsection now.** Walker 2.x is a thin GTK4 frontend over a separate backend daemon called **Elephant**. Each capability (apps, calculator, clipboard, symbols, files, runner, websearch, etc.) is delivered by a discrete `elephant-<provider>` package. The previous one-liner (`walker --gen-config`) doesn't reflect any of this — without Elephant running and the right providers installed, the keybindings in `keybindings.conf` (`Super+Ctrl+E` → symbols, `Super+Ctrl+V` → clipboard, etc.) silently no-op or fall back to the desktopapplications default. `../ACTUAL-CONFIGURATION.md` §12 currently claims "using upstream defaults"; in practice that means most of Walker's advertised capabilities aren't actually wired up.

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

> **Default web-search prefix is `@`, not `?`.** Walker 2.x's default prefix changed from the older `?`. If you specifically want `?` back, replace the `websearch` prefix block above with `prefix = "?"` *and* update `../shortcuts.md` §1.2 / §4 to match (currently those reflect the `@` default).

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

After 7e.i–iii are applied (the minimum to make Walker functional), update `../ACTUAL-CONFIGURATION.md`:

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


---

## Issue history

Moved here 2026-11-03 from `../ACTUAL-CONFIGURATION.md` §15, verbatim. Those table
cells had grown into multi-kilobyte incident analyses; §15 is now a status table
and the reasoning lives beside the runbook it explains.

### Discord screen share can't capture the screen / Wayland windows

🔧 Fix applied 2026-09-28, pending a live share test — the portal stack was **healthy all along** (`xdg-desktop-portal-hyprland 1.4.1` running, `[screencopy] init successful`, `hyprland-portals.conf` → `hyprland;gtk`, `hyprland-share-picker` present; the 2026-09-27 23:51 xdph core-dumps coincide with a compositor exit, not a share). **Cause:** Discord (`discord 1:1.0.159`, launched from Walker) is a child of `elephant`, whose env had `WAYLAND_DISPLAY` + `XDG_CURRENT_DESKTOP` but **no `XDG_SESSION_TYPE`** — Hyprland sets `XDG_SESSION_TYPE=wayland` for its own children (waybar/mako have it) but its automatic systemd `--user` env import skips it. Discord's `discord_voice-1/discord_voice/index.js` declares `native_screenshare_picker` (the PipeWire/`org.freedesktop.portal.ScreenCast` path) only when `XDG_SESSION_TYPE` starts with `wayland` **and** `WAYLAND_DISPLAY` is set, so it fell back to X11 capture, which only sees XWayland windows. It was also running under XWayland (`--ozone-platform=x11`, `xwayland=true`). **Fix:** `autostart.conf` now runs `dbus-update-activation-environment --systemd XDG_SESSION_TYPE && systemctl --user start elephant.service` (chained so it can't race elephant). Live-applied via `systemctl --user set-environment XDG_SESSION_TYPE=wayland` + `restart elephant.service`; elephant's env verified. Nothing needed installing. **Side effect:** every Walker-launched app now sees a Wayland session, so Electron/Chromium/Qt apps that auto-detect may move from XWayland to native Wayland (usually sharper at scale 1.25). If one misbehaves, pin it back with `--ozone-platform=x11` in a `~/.local/share/applications/` override. **Verify:** quit Discord fully (tray → Quit), relaunch from Walker, then run `hyprctl clients -j \| jq '.[]\|select(.class=="discord").xwayland'` and click Share Screen → `hyprland-share-picker` should open. Screen-share **audio** from the official client is unverified; `vesktop-bin` (cachyos repo) is the fallback if audio is missing.

### Walker config

✅ Elephant-backed (2026-05-23) — hub + 9 providers (apps, calc, runner, files, symbols, clipboard, websearch, providerlist, menus) from AUR; user unit at `~/.config/systemd/user/elephant.service`. Verified: `walker -m clipboard` and `walker -m symbols` open working UIs. `~/.config/walker/config.toml` and `~/.config/elephant/*.toml` not yet written — running on Elephant defaults (websearch prefix is `@`; `../shortcuts.md` §1.2 and §4 reflect this). §7e.iv–v below pins these if desired. **Startup fix 2026-05-26:** the unit was `enabled` but `WantedBy=graphical-session.target`, which never activates under this getty+`start-hyprland` session, so elephant never started and Walker hung on "Waiting for elephant". Now started explicitly via `exec-once = systemctl --user start elephant.service` in autostart.conf (see §7e.ii–iii).

### Volume/brightness OSD + media keys dead after a monitor switch

✅ Resolved 2026-06-17 — root cause was `swayosd-server` 0.3.1 SIGABRTing whenever the monitor set changes (backtrace: `gtk_layer_init_for_window` → `wl_display_roundtrip_queue` → `abort`, fired from the GTK "monitors changed" signal). It runs fine *sitting* in any layout but dies *during* the transition, so switching into the `read` profile (which disables `eDP-1`) — or any hotplug — left the server dead and, since it was a bare `exec-once`, nothing revived it: no OSD, and the media keys (which route through `swayosd-client` → server) stopped changing volume entirely. **Fix:** moved it to a `Restart=always` systemd `--user` unit (`~/.config/systemd/user/swayosd.service`, mirrored in `configs/systemd/user/`), launched via `exec-once = systemctl --user start swayosd.service`; `monitor-mode.sh` also runs `systemctl --user restart swayosd.service` after applying each layout so a healthy server is bound to the new monitor set. Verified by simulating the crash (`kill -ABRT`) → systemd revived it; restart path and `swayosd-client` volume both confirmed. Also wired the Waybar `pulseaudio` module's scroll (and middle-click mute) through `swayosd-client` so scrolling the bar shows the OSD too. Upstream bug — re-evaluate the workaround if a newer swayosd survives monitor hotplug.
