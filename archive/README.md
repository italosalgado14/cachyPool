# Archive

Superseded material. **Do not follow these steps on the current system** — check
`../ACTUAL-CONFIGURATION.md` first, and `../runbooks/` for how a subsystem works now.

Nothing here is deleted, and that is a rule rather than an accident. The sharpest lesson
this repo has recorded is `../runbooks/fingerprint.md` §20g: a conclusion that was wrong —
"the fingerprint reader cannot enrol" — built on a premise that was true, which then became
a rule in `../CLAUDE.md` and blocked the actual fix for three sessions. The retracted
reasoning is worth more than the retraction. So superseded documents move here with a
banner; they do not get corrected into agreement with the present, because then they would
compete with the snapshot instead of dating themselves.

| File | What it was | When |
|---|---|---|
| `cachyos-hyprland-setup.md` | The original install plan and stack rationale | May 2026 |
| `system-state-findings.md` | Audit of the planned setup against the installed reality | 2026-05-21 |
| `spected-installation.md` | Pre-install reasoning for each package choice | 2026-05 |
| `install-remediation-2026-05.md` | §1 §2 §3 §4 §9 of the dissolved `finish-installation-commands.md`: the autostart fixes, the hyprpaper parser workaround, the Waybar drop-in, the `qt6ct` env var, and the final verification block — all applied once, in May 2026 | 2026-05-22 |

Known-stale claims in these files, so you recognise them on sight: SDDM or
plasma-login-manager as the display manager (there is none — `getty@tty1` autologins);
VA-API routed through the NVIDIA driver (moved to the Intel iGPU on 2026-07-02); the LTS
kernel entry missing modeset parameters (no entry has them, and none needs them); flat
`wallpaper =` lines in hyprpaper config (0.8.4 needs block syntax); and port names
`DP-1`/`DP-2` treated as stable (they float with plug order — bind by EDID `desc:`).

Section numbers are preserved from the files these came from — see `../runbooks/README.md`.
