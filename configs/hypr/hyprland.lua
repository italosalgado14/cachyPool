-- ~/.config/hypr/hyprland.lua — entrypoint for the Lua config.
--
-- Hyprland 0.57.1 REMOVED the hyprlang parser. It reads hyprland.lua and
-- nothing else: an explicit `--config hyprland.conf` is handed to the Lua
-- parser too, and `hyprctl keyword` no longer exists as an IPC request (use
-- `hyprctl eval '<lua>'`). The modular .conf files this replaced are kept
-- beside it under configs/hypr/ for reference — see runbooks/updates.md §4.
--
-- Every file below is `require`d, so each gets its OWN SCOPE: a Lua error
-- takes out one file instead of the whole session. Order matters — monitors
-- before workspaces (the workspace rules name monitors), workspaces before
-- the bindings (they call into it).
--
-- package.path is derived from THIS FILE's location, so
--   Hyprland --verify-config -c <repo>/configs/hypr/hyprland.lua
-- verifies the repo's own siblings instead of silently reading the live ones.

local here = (debug and debug.getinfo(1, "S").source or ""):match("^@(.*)/")
  or ((os.getenv("HOME") or "") .. "/.config/hypr")

package.path = here .. "/lua/?.lua;" .. package.path

require("env")
require("monitors")
require("workspaces")
require("input")
require("look")
require("windowrules")
require("qconsole")
require("bindings-apps")
require("bindings-tiling")
require("bindings-utilities")
require("bindings-clipboard")
require("autostart")
