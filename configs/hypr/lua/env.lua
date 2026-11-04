-- Session environment. `hl.env` is the Lua form of hyprlang's `env =`, and it
-- carries the SAME LIMIT: these only reach processes Hyprland spawns (keybinds,
-- hl.exec_cmd). Walker/Elephant launch apps from the systemd --user manager,
-- which never sees them — never configure a Walker-launched app from here.
-- That is why Firefox's video-decode pause lives in its profile user.js
-- (runbooks/gpu-video.md §12), and why autostart.lua pushes XDG_SESSION_TYPE
-- into the systemd/D-Bus activation environment by hand.

-- VA-API: routed to the Intel iGPU's iHD driver since 2026-07-02. The
-- compositor and all three monitors run on the iGPU; the dGPU's GSP often dies
-- after suspend/resume, so decoding on it only produced NVRM spam.
hl.env("LIBVA_DRIVER_NAME", "iHD")

-- NVIDIA dGPU, offload-only. Read ACTUAL-CONFIGURATION.md §15 before touching.
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")

-- Wayland toolkit hints
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Cursor & theme
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Software cursors: the NVIDIA driver draws artefacted hardware cursors here.
-- 0.57 made this an int where 2 means "auto"; `true` forces it off. Do not
-- re-enable without testing on all three panels.
hl.config({
  cursor = {
    no_hardware_cursors = true,
  },
})
