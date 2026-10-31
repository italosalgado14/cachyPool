#!/usr/bin/env bash
# show-shortcuts.sh — pop up a curated cheatsheet of the most useful Hyprland /
# Walker shortcuts in a floating Kitty window.
#
# Entry points:
#   - The "Shortcuts" Walker launcher entry (~/.local/share/applications/
#     shortcuts.desktop, mirrored in configs/applications/).
#   - Super + / keybind (keybindings.conf).
#
# The FULL reference lives in shortcuts.md (§1 = every keybinding). This script
# only holds the "principal" subset — keep it in sync with shortcuts.md when
# bindings change.

set -euo pipefail

# Launched from Walker / a keybind there is no terminal attached: relaunch inside
# a floating Kitty window (class 'shortcuts-cheatsheet' is floated + centered by
# windowrules.conf). Run from a shell (stdout is a tty) → render inline.
if [ ! -t 1 ]; then
  exec kitty --class shortcuts-cheatsheet --title "Hyprland Shortcuts" -e "$0" "$@"
fi

b=$'\e[1m'; d=$'\e[2m'; c=$'\e[1;36m'; r=$'\e[0m'

render() {
cat <<EOF

  ${c}┌────────────────────────────────────────────────────────────┐${r}
  ${c}│   Hyprland · CachyOS — Shortcuts cheatsheet                 │${r}
  ${c}└────────────────────────────────────────────────────────────┘${r}
  ${d}Super = Windows/⌘ key.   Full reference: shortcuts.md (§1).${r}
  ${d}Scroll with ↑/↓ or the mouse · press q to close.${r}

  ${c}LAUNCH${r}
    Super + Enter            Open Kitty terminal
    Super + Space            Walker launcher (apps + fuzzy search)
    Super + Shift + Enter    Open Firefox
    Super + E                File manager (Yazi in Kitty)
    Super + /                This shortcuts cheatsheet
    Super + L                Lock screen (Hyprlock)

  ${c}WINDOWS${r}
    Super + Q                Close active window
    Super + F                Toggle fullscreen
    Super + V                Toggle floating
    Super + P                Pseudo-tile (keep size when moving)
    Super + J                Toggle dwindle split direction
    Super + ← ↑ ↓ →          Focus neighbor window
    Super + Shift + arrows   Move window in that direction
    Super + drag (L mouse)   Move window
    Super + drag (R mouse)   Resize window

  ${c}WORKSPACES${r}
    Super + 1 … 9            Switch to workspace N
    Super + Shift + 1 … 9    Send active window to workspace N
    Super + scroll           Cycle through workspaces
    ${d}DP-1: ws 1-3 · eDP-1: 4-5 · DP-2: 6-9${r}

  ${c}WALKER MODES${r}   ${d}(type the prefix into Walker)${r}
    Super + Space            Apps / fuzzy search (default)
    =                        Calculator
    /                        File search
    >                        Shell command runner
    :   (Super + Ctrl + V)   Clipboard history
    .   (Super + Ctrl + E)   Emoji / symbol picker
    @                        Web search
    ;                        List loaded Elephant providers

  ${c}SCREENSHOT${r}
    Print                    Region → satty → clipboard
    Shift + Print            Full screen → satty → clipboard

  ${c}AUDIO / BRIGHTNESS${r}   ${d}(SwayOSD popups)${r}
    Volume Up/Down/Mute      Output volume  (or scroll the Waybar 🔊)
    Mic Mute                 Toggle microphone
    Brightness Up/Down       Backlight
    Play / Next / Prev       Media (playerctl-aware apps)

  ${c}MONITORS${r}   ${d}(geometry: hyprmon profile if saved, else monitor-mode.sh)${r}
    Super + M                Toggle: read ↔ desktop (desk) · read ↔ trio (road)
    Super + Shift + M        Monitors menu: fitting profiles · Hyprmon editor · live layout
    ${d}Desk primary: Xiaomi 27" 4K 3840x2160@60 → runs at 3072x1728${r}
    ${d}  (scale 1.25). Replaced the Samsung FHD 24" on 2026-07-11.${r}

    ${d}Desktop profile (logical px · matched by EDID, never by DP-1/DP-2):${r}
      eDP-1    2560x1600@240   scale 1.25   x:0      ${d}laptop · ws 4-5${r}
      Xiaomi   3840x2160@60    scale 1.25   x:2048   ${d}desk primary · ws 1-3${r}
      AQ16H    2560x1600@120   scale 1.25   x:5120   ${d}portable QHD · ws 6-9${r}

    ${d}Profiles — monitor-mode.sh {desktop|read|laptop|onescreen|trio}:${r}
      desktop     3-across, all landscape        ${d}(manual · Super+M only)${r}
      read        desk ext landscape · QHD portrait · laptop off
      trio        FHD · laptop · QHD  (both 16" portables, on the road)
      onescreen   one external · laptop, side by side
      laptop      integrated screen only
    ${d}Edit a layout: menu → Hyprmon → drag, A to preview, P to save as the${r}
    ${d}  profile's name (never S). Saved: ~/.config/hyprmon/profiles/${r}

    ${d}Auto-switch on plug/unplug (never picks desktop):${r}
      ${d}2 externals + demoset FHD → trio · 2 externals → read${r}
      ${d}1 external → onescreen · none → laptop${r}
    ${d}Full details: shortcuts.md §3 · ACTUAL-CONFIGURATION.md §11${r}

  ${c}SESSION${r}
    Super + Shift + Q        Restart compositor (drops to tty1, re-execs Hyprland)
    ${d}Real logout: Ctrl+Alt+F2 → loginctl terminate-user isalgado${r}

EOF
}

render | less -R
