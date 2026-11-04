#!/usr/bin/env bash
# show-shortcuts.sh — the shortcuts cheatsheet, GENERATED from the live binds.
#
# Omarchy's B1: `hyprctl binds -j` publishes a `description` field, and
# configs/hypr/lua/bind.lua puts one on every binding worth showing. So this
# script no longer holds a hand-written list that drifts — it reads the binds
# that are actually loaded. A bind with no description is left out on purpose
# (aliases, the z-order halves of Alt+Tab, overflow resize steps).
#
# Entry points:
#   - Super + K (and Super + / for muscle memory) — bindings-utilities.lua
#   - The "Shortcuts" Walker entry (~/.local/share/applications/shortcuts.desktop)
#
# The full narrative reference is still shortcuts.md.
set -euo pipefail

# Launched from Walker or a keybind there is no terminal attached: relaunch in a
# floating Kitty window (class 'shortcuts-cheatsheet' is floated and centred by
# lua/windowrules.lua). Run from a shell (stdout is a tty) → render inline.
if [ ! -t 1 ]; then
  exec kitty --class shortcuts-cheatsheet --title "Hyprland Shortcuts" -e "$0" "$@"
fi

b=$'\e[1m'; d=$'\e[2m'; c=$'\e[1;36m'; r=$'\e[0m'

binds() {
  hyprctl binds -j | jq -r '
    def bit(m; n): ((m / n) | floor) % 2 == 1;
    def chord:
      [ (if bit(.modmask; 64) then "Super" else empty end),
        (if bit(.modmask; 4)  then "Ctrl"  else empty end),
        (if bit(.modmask; 8)  then "Alt"   else empty end),
        (if bit(.modmask; 1)  then "Shift" else empty end),
        (if (.key // "") != "" then .key
         else ({ "10":"1","11":"2","12":"3","13":"4","14":"5","15":"6",
                 "16":"7","17":"8","18":"9","19":"0","20":"-","21":"=" }
               [.keycode | tostring]) // ("code:" + (.keycode | tostring))
         end) ]
      | join(" + ");
    .[]
    | select((.description // "") != "")
    | "  \(chord)\t\(.description)"
  ' | column -t -s $'\t'
}

render() {
  cat <<EOF

  ${c}┌──────────────────────────────────────────────────────────────┐${r}
  ${c}│   Hyprland · CachyOS — shortcuts (Omarchy keymap)            │${r}
  ${c}└──────────────────────────────────────────────────────────────┘${r}
  ${d}Super = Windows/⌘ key.  Generated from \`hyprctl binds -j\` — if a bind${r}
  ${d}is missing here it has no description in configs/hypr/lua/.${r}
  ${d}Scroll with ↑/↓ or the mouse · press q to close.${r}

$(binds)

  ${c}NOT IN THE BIND LIST${r}
  ${d}Walker modes — type the prefix into the launcher (Super + Space):${r}
    =                        Calculator
    /                        File search
    >                        Shell command runner
    :                        Clipboard history   ${d}(also Super + Ctrl + V)${r}
    .                        Emoji / symbols     ${d}(also Super + Ctrl + E)${r}
    @                        Web search
    ;                        Loaded Elephant providers

  ${d}Workspaces are PER MONITOR (configs/hypr/lua/workspaces.lua):${r}
    ${d}Super + 1..0 is always "the Nth workspace of the screen you are on".${r}
    ${d}eDP-1 owns ids 1-10 · Xiaomi 11-20 · AQ16H portable 21-30.${r}

  ${d}Monitors: geometry lives in configs/hypr/lua/monitors.lua. The five${r}
  ${d}layout profiles (monitor-mode.sh) and the hotplug autoswitcher are${r}
  ${d}PARKED for the Lua migration — runbooks/monitors.md §16.${r}
    ${d}Super + Ctrl + Delete    toggle the laptop panel (clamshell)${r}
    ${d}Super + Ctrl + D         Hyprmon layout editor (save with P, never S)${r}

  ${d}Real logout: Ctrl+Alt+F2 → loginctl terminate-user isalgado${r}

EOF
}

render | less -R
