#!/usr/bin/env bash
# hyprmon-edit.sh — open hyprmon (AUR hyprmon-bin) as the visual EDITOR for the
# monitor-mode.sh profiles, with the parts of hyprmon that break this setup
# neutered.
#
# Workflow: drag the screens (or arrows / Shift+arrows), `A` to preview live,
# then `P` and save under a mode name — desktop, read, trio, onescreen, laptop.
# monitor-mode.sh applies ~/.config/hyprmon/profiles/<mode>.json whenever it
# covers exactly the connected monitors (see apply_from_profile there). On quit
# this wrapper re-applies the current mode, so a just-saved profile shows up
# immediately and any `A` experiments are undone by the real applier.
#
# Entry points: Super+Shift+M menu (monitor-menu.sh), the "Hyprmon" Walker entry
# (~/.local/share/applications/hyprmon.desktop overrides the packaged one, whose
# Exec bypasses this wrapper), or run it from a terminal.
#
# What the wrapper neuters, all verified against hyprmon 0.0.17's source:
#   * `S` rewrites `monitor=` lines in hyprland.conf. Ours has none (they live
#     in monitors.conf), so hyprmon would APPEND port-bound lines after the
#     `source` lines and override monitors.conf at every boot. HYPRLAND_CONFIG
#     points it at a scratch file nothing sources (absolute path, must exist).
#   * `S` then runs `hyprctl reload`, which snaps the live layout back to the
#     monitors.conf boot geometry. hyprmon finds hyprctl through $PATH, so a
#     shim placed first in $PATH turns `reload` into a no-op. Everything else
#     passes through to the real hyprctl.
#   * `A` sets transforms with a bare `hyprctl keyword monitor` — the
#     stale-layout-box bug (see apply_monitor_tf in monitor-mode.sh). The
#     re-apply on quit cycles any output whose transform drifted.
# Residual gaps: switching an EXTERNAL off with `A` makes monitor-autoswitch.sh
# revert it ~3s later (it looks like an unplug), and toggling a monitor off/on
# and then rotating it back to the profile's transform can leave a stale box
# that the quit re-apply won't detect — Super+M twice fixes that.
# Never run `hyprmon --profile`: it does the bare-keyword apply + config write
# + reload on every switch.

set -uo pipefail

# Launched from Walker / a keybind there is no terminal attached: relaunch inside
# a floating Kitty window (class 'hyprmon-edit' is floated + sized by
# windowrules.conf). Run from a shell (stdout is a tty) → run inline.
if [ ! -t 1 ]; then
  exec kitty --class hyprmon-edit --title "Hyprmon" -e "$0" "$@"
fi

if ! command -v hyprmon >/dev/null 2>&1; then
  echo "hyprmon is not installed — run:  paru -S hyprmon-bin"
  echo "(note: AUR 'hyprmon' without -bin is an unrelated Rust project)"
  read -rn1 -p "Press any key to close… " _
  exit 1
fi

MODE_SCRIPT="$HOME/.config/hypr/scripts/monitor-mode.sh"
STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr-monitor-mode"
WORK="${XDG_STATE_HOME:-$HOME/.local/state}/hyprmon"
SCRATCH="$WORK/scratch.conf"
SHIM="$WORK/shim"

mkdir -p "$WORK" "$SHIM"
touch "$SCRATCH"

cat > "$SHIM/hyprctl" <<'EOF'
#!/bin/sh
# Written by hyprmon-edit.sh — blocks hyprmon's `hyprctl reload`, passes the rest.
if [ "${1:-}" = reload ]; then
  notify-send -t 4000 "Hyprmon" "Reload blocked: save layouts with P (profile), not S" 2>/dev/null
  exit 0
fi
exec /usr/bin/hyprctl "$@"
EOF
chmod +x "$SHIM/hyprctl"

reapplied=0
reapply() {
  (( reapplied )) && return
  reapplied=1
  # hyprmon backs up the scratch file on every `S` and never prunes; the
  # backups of a scratch file are worthless.
  rm -f "$SCRATCH".bak.* 2>/dev/null
  if [[ -s "$STATE" ]]; then
    "$MODE_SCRIPT" "$(cat "$STATE")" >/dev/null 2>&1
  fi
}
trap reapply EXIT
trap 'reapply; exit 0' HUP INT TERM

# No "$@" on purpose: `hyprmon --profile` / `hyprmon profiles` apply profiles
# the bare-keyword way. This wrapper only ever opens the editor.
PATH="$SHIM:$PATH" HYPRLAND_CONFIG="$SCRATCH" hyprmon
