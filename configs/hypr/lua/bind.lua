-- bind(keys, description, action, opts) — the one wrapper every binding file
-- uses, modelled on Omarchy's `o.bind`.
--
-- The DESCRIPTION is not decoration: `hyprctl binds -j` publishes it, and
-- scripts/show-shortcuts.sh builds the Super+K cheatsheet out of exactly that,
-- so the cheatsheet can never drift from the binds again. A bind with no
-- description is left out of it on purpose (internal/overflow binds).
--
-- `action` is an HL.Dispatcher, a bare function, or a string — a string is run
-- as a command, which is the common case.
local function bind(keys, description, action, opts)
  local options = opts or {}

  if description then
    options.description = description
  end

  if type(action) == "string" then
    action = hl.dsp.exec_cmd(action)
  end

  return hl.bind(keys, action, options)
end

return bind
