# Triton Panel — Deployment

> Part of the `cachyPool` runbooks. Section numbers are **preserved** from
> `finish-installation-commands.md`, dissolved 2026-11-03 — a `§N` reference
> anywhere in this repo still resolves by number. Index and conventions:
> `README.md`. Live-state history: `../CHANGELOG.md`.

Installing and wiring the GTK4 panel for this machine's own hardware: the privileged helper, the sudoers rule, the desktop entry. What the app *does* is documented in `../triton-panel/README.md`; this is the system side.

---

## 18. `triton-panel` — a GUI for this machine's own hardware — ✅ APPLIED 2026-10-31, fully installed 2026-11-03

**Why:** everything `power-battery.md` §14 and §17 unlocked was reachable only by `cat`-ing sysfs. No general-purpose tool covers it — `mission-center` shows no fans, `coolercontrol` is a fan *control* front end for hardware that has no PWM here, `psensor` graphs RPM but cannot touch the charge cap or the platform profile, and `powerprofilesctl` reaches three of the five states.

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

✅ **Fully installed, verified 2026-11-03.** The app, the `.desktop`, `/usr/local/bin/triton-ctl` (root-owned) **and the sudoers rule** are all in place: `sudo -ln` reports `(root) NOPASSWD: /usr/local/bin/triton-ctl`, so the charge-cap switch and the `quiet`/`balanced-performance` entries work rather than raising a toast. (`/etc/sudoers.d/` is not world-readable, so `sudo -ln` — what is in effect for this user — is the check, not an `ls`.)

### 18c. Verify

```bash
triton-panel &                       # fans, temps and the profile selector must be populated
# Walker: Super+Space, type "triton"
```

If the fan and profile groups read "unavailable", `power-battery.md` §17 is not in effect. If the cap switch raises a toast about sudoers, the two `sudo` lines in 18a were skipped.

### 18d. Revert

```bash
rm ~/.local/bin/triton-panel ~/.local/share/applications/triton-panel.desktop
sudo rm /usr/local/bin/triton-ctl /etc/sudoers.d/triton-panel
```

Then drop the `dev.isalgado.TritonPanel` block from `windowrules.conf`.

### 18e. Docs updated 2026-10-31

- `../triton-panel/README.md`: the full reference — install, privileges, design notes, troubleshooting, and the keyboard-backlight caveat.
- `../README.md`: repo index gains `triton-panel/` and the note that it is the one directory holding source rather than docs or mirrors.
- `../ACTUAL-CONFIGURATION.md`: §15 new row, §16 repo layout.
- `configs/applications/triton-panel.desktop`, `configs/hypr/windowrules.conf`: new mirror and new rule block.
- `triton-panel/waybar/`: optional Waybar modules showing the same data in the bar. **Not applied** — the live Waybar config is untouched; see that directory's README.

---


---

## Issue history

Moved here 2026-11-03 from `../ACTUAL-CONFIGURATION.md` §15, verbatim. Those table
cells had grown into multi-kilobyte incident analyses; §15 is now a status table
and the reasoning lives beside the runbook it explains.

### All of this only reachable from a terminal

✅ **Resolved 2026-10-31** — new `triton-panel/`: a small GTK4/libadwaita app, launched from Walker, that shows temperature and fan graphs, CPU/memory/iGPU/dGPU, the power source and dock, and battery health — and drives the two things that need root, the 80% charge cap and (once a driver for it exists) the keyboard backlight. Chosen over mission-center (shows no fans), CoolerControl (a fan *control* front end, and this machine has no PWM) and psensor (cannot touch the cap or the profile). Unprivileged except for a strict `triton-ctl` helper behind one NOPASSWD sudoers line. **Hard dependency on the `predator_v4` row above:** without it the fan and profile groups show as unavailable. Notable design point: the dGPU is never woken — `nvidia-smi` is an open of the device, so polling it would hold an idle 3080 Ti out of D3cold. Install, privileges and caveats: `../triton-panel/README.md`. ⚠ At the time of writing the app, its `.desktop` and the root-owned `/usr/local/bin/triton-ctl` are installed, but the `/etc/sudoers.d/triton-panel` rule is **not** — so the cap switch raises a toast until it is added (§18a). Since 2026-11-02 the **Battery** group also answers how much has been used and how long is left: history and projection on one time axis, the draw as a short EMA (a single `current_now` is too noisy to divide by), the run average as a cross-check, a charge projected to 80% while the cap is on, and the pre-launch part of the curve seeded from upower because this is a window and not a daemon. Window rules so the panel floats are in `configs/hypr/windowrules.conf`. `triton-panel/waybar/` holds optional Waybar modules with the same data — **not applied**, the live bar is untouched.
