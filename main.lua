-- Solo Run QoL: three comfort features that do not touch the rules.
--
-- Running shoes, hold-to-scroll menus, and the Repel reuse prompt, each in
-- its own file and each switched from one MOD OPTIONS screen.  Nothing here
-- changes an encounter rate, a stat, or a battle outcome -- that is what
-- Solo Run Modpack is for.  This one is safe to run with or without it.
--
-- Same three rules as the modpack, for the same reasons:
--
--   1. Patches install unconditionally and read the options at CALL time,
--      so a toggle never needs a restart.
--   2. Anything patched onto an engine module table uses marker+slot.
--      Module tables survive an F5 reload while the mod environment does
--      not, so a plain boolean guard stacks a second wrapper every reload.
--   3. Conditional rows are hidden by re-defining the schema, because
--      visible_if only exists from engine v0.1.95.
--
-- Credits: the running-shoes animation maths follows johnjohto's
-- jj_running_shoes, and the two-path menu repeat follows WizzStar's
-- hold_to_scroll_ui (MIT, see LICENSE-hold_to_scroll_ui.txt).

return function(mod)
  local compile = loadstring or load

  local function loadModule(path)
    local source, readError = mod:read(path)
    if not source then
      mod.log:error("cannot read %s: %s; reinstall the mod", path,
        tostring(readError))
      error("cannot read " .. path, 0)
    end
    local chunk, compileError = compile(source, "@" .. mod.path .. "/" .. path)
    if not chunk then
      mod.log:error("cannot compile %s: %s; reinstall the mod", path,
        tostring(compileError))
      error("cannot compile " .. path, 0)
    end
    return chunk()
  end

  local options = loadModule("qol_options.lua")
  options.install(mod)

  for _, path in ipairs({ "qol_running.lua", "qol_hold_scroll.lua",
                          "qol_repel.lua" }) do
    local feature = loadModule(path)
    local ok, err = pcall(feature.install, mod, options)
    if not ok then
      mod.log:error("%s failed to install: %s", path, tostring(err))
    end
  end

  mod.log:info("solo_run_qol: loaded")
end
