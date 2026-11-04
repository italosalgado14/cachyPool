-- Session autostart. hl.on("hyprland.start") replaces `exec-once` — and note
-- it does NOT re-fire on `hyprctl reload`, so after pushing a config change the
-- list below has to be started by hand (or by logging out and in).
local HOME = os.getenv("HOME") or ""
local SCRIPTS = HOME .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
  -- Elephant is Walker's backend hub. Its user unit is
  -- WantedBy=graphical-session.target, but this getty-autologin +
  -- start-hyprland session never activates that target, so it must be started
  -- explicitly. Every app Walker launches inherits elephant's env, and
  -- Hyprland's automatic systemd env import skips XDG_SESSION_TYPE — so push
  -- it FIRST, chained with && because separate calls race. Without it,
  -- Electron/Chromium apps fall back to XWayland and Discord never enables its
  -- PipeWire/portal screen share.
  hl.exec_cmd("dbus-update-activation-environment --systemd XDG_SESSION_TYPE && systemctl --user start elephant.service")
  hl.exec_cmd("walker --gapplication-service")

  hl.exec_cmd("waybar")
  hl.exec_cmd("mako")
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd("hypridle")

  -- hyprpolkitagent is not on $PATH (/usr/lib/hyprpolkitagent/...), so it goes
  -- through its user unit.
  hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

  -- swayosd-server runs as a systemd --user unit (Restart=always) rather than a
  -- bare exec: swayosd 0.3.1 aborts whenever the monitor set changes, and a
  -- bare exec never comes back — which kills the volume/brightness OSD and the
  -- media keys.
  hl.exec_cmd("systemctl --user start swayosd.service")

  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("nm-applet --indicator")

  -- Follow the power source: on battery drop eDP-1 to 60 Hz and switch the
  -- platform profile to power-saver; on AC restore 240 Hz and the profile that
  -- was active before. Toggled from Triton Panel ("Automatic power saving").
  hl.exec_cmd(SCRIPTS .. "/power-autoswitch.sh")

  -- ⚠ monitor-autoswitch.sh is NOT started: the monitor profile system is
  -- parked for the Lua migration (monitors.lua holds the geometry now).
  -- runbooks/monitors.md §16.
end)
