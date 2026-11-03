# Runbooks

One file per subsystem. Each is the **sole owner** of its ground: the failure modes, the
diagnosis, the fix, the verification, and the incident history that explains why the config
looks the way it does.

This is the shape `bluetooth.md` already had, and it is why that file never needed a place
in a source-of-truth ranking — it had **scope** instead of **rank**. The rest of this
directory was created on 2026-11-03 by dissolving `finish-installation-commands.md`
(213 KB, 21 sections), which had become an unscoped accumulator that everything new landed
in. See `../CHANGELOG.md` for the move and the old-section mapping.

| Runbook | Owns | Sections |
|---|---|---|
| `bluetooth.md` | Sony WH-1000XM4 pairing, the `br-connection-key-missing` half-bond, codecs | — |
| `boot-suspend.md` | Limine cmdline, the Thunderbolt boot/shutdown hang, `getty@tty1` autologin, `s2idle`, logind lid | §0 §6 §10 §11 §15 |
| `desktop-apps.md` | Kitty/Yazi/hyprlock polish, Walker + Elephant, VS Code keyring, SwayOSD, portals | §7 §8 |
| `fingerprint.md` | The `04f3:0c4f` ELAN area pad: enrolment, calibration, verify, hyprlock unlock | §20 |
| `gpu-video.md` | The 2026-07-02 Firefox freeze, VA-API on the iGPU, paused hardware decode, video players | §12 §13 |
| `monitors.md` | Per-panel scaling, layout profiles, Hyprmon as editor / `monitor-mode.sh` as applier | §5 §16 |
| `power-battery.md` | The 80% charge cap, `predator_v4` fans + platform profile, the power-source daemon | §14 §17 §19 |
| `triton-panel.md` | Deploying the panel: privileged helper, sudoers, desktop entry | §18 |

## Section numbers are preserved

Every section kept the number it had in `finish-installation-commands.md`. That was
deliberate: a `§N` reference anywhere in this repo — in a doc, a script comment, or a git
message — still resolves, even where the filename beside it was not updated.

```bash
grep -rn '§20g' runbooks/ archive/     # find a section by number, whatever moved
```

Numbering is therefore **not contiguous** inside a file: `boot-suspend.md` runs §0, §6, §10,
§11, §15. That is the cost of keeping references alive, and it is the cheaper side of the
trade. A **new** runbook starts its own numbering from §1; do not extend the old sequence.

Each runbook ends with an unnumbered `## Issue history` section — the incident analyses that
used to be stuffed into `../ACTUAL-CONFIGURATION.md` §15 table cells, one of which had reached
22 KB. §15 is now a status table whose rows point back here.

## Where things go

| | |
|---|---|
| What the machine **is** right now | `../ACTUAL-CONFIGURATION.md` |
| What **changed** and when | `../CHANGELOG.md` |
| How to **drive** it day to day | `../shortcuts.md` |
| How a subsystem **works, breaks and gets fixed** | here |
| Superseded material, kept for the record | `../archive/` |

New state lands in **two** places: one `../CHANGELOG.md` entry and the owning runbook. Not in a
document's header, and not in a table cell.

---

## Running the commands in these runbooks

This note applied to every section of the dissolved file and so applies to every runbook
here. Where it says "below" or "this doc", read: any runbook in this directory.

> **fish-shell users — heredoc note.** Code blocks below use bash/zsh heredoc syntax (`cat >file <<'EOF' … EOF`, `sudo tee file <<'EOF' … EOF`). **fish does not support heredocs** and will error with `Expected a string, but found a redirection`. Three ways to handle it:
> 1. **Run heredoc blocks inside `bash` interactively.** Type just `bash` (with **no arguments**) at the fish prompt to enter a bash subshell, paste the multi-line block as-is, then type `exit` to return to fish. ⚠ Do **not** try `bash "<heredoc>"` or `bash -c "<heredoc>"` — bash with a string arg treats it as a filename / inline script and the heredoc terminator handling will surprise you. Recommended for the long file-creation heredocs in §1, §3, §7.
> 2. **Replace the heredoc with fish-native `echo`.** Pattern: `echo 'line1\nline2…' >file`. Single quotes keep `$VAR` literal, which is what you want when writing config files. Multi-line literals work inside fish single-quoted strings. §10.d uses this pattern as its primary path; copy that style for the others if you prefer staying in fish.
> 3. **Open the target file in an editor.** `nano <path>` / `nvim <path>` and paste the heredoc body (everything between the `<<'EOF'` and the closing `EOF`). Works in any shell.
>
> For the rest of this doc, plain non-heredoc commands (`sudo pacman`, `sudo systemctl`, `cp`, `grep`, etc.) run identically in fish and bash — no translation needed.
