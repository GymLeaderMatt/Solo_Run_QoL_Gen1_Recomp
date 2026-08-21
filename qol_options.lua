-- The MOD OPTIONS screen for Solo Run QoL.
--
-- Same two engine constraints as the modpack: only FOUR rows show at once,
-- and the font has no '%' glyph (letters, digits and ! ? . , - / : ; ' ( )
-- [ ] only), with about 17 characters fitting before a label overruns.
--
-- Conditional rows are handled three ways over, because `visible_if` only
-- exists from engine v0.1.95 and below that it is silently ignored:
--
--   1. visible_if is set, which does the whole job on 0.1.95 and later.
--   2. The schema is re-defined with dead rows filtered out, which fixes
--      the list for the next time the options screen is opened.
--   3. The screen currently on the stack is rebuilt in place, because (2)
--      alone leaves a stale row visible until you back out and return --
--      which reads as the toggle simply not working.
--
-- DEFAULTS is the backstop that keeps a filtered-out row reading as its
-- real value instead of nil, since a row removed from the schema takes its
-- default with it.
--
-- Run speed itself is deliberately not a row.  It is fixed at 2x on foot
-- with the bicycle scaled by the same multiplier, which is a choice about
-- how the game should feel rather than something worth a menu.

local options = {}

options.KEYS = {
  RUNNING     = "running_shoes",
  RUN_BUTTON  = "run_button",
  AUTO_SCROLL = "auto_scroll",
  HOLD_DELAY  = "hold_delay",
  REPEAT_SPEED = "repeat_speed",
  REPEL       = "repel_prompt",
}

local K = options.KEYS

options.DEFAULTS = {}

-- Hold-to-scroll's 1-5 ladder, in frames between repeats.  3 is the tuned
-- middle; each step is only two frames so the ends stay usable.
options.SPEED_FRAMES = { [1] = 14, [2] = 12, [3] = 10, [4] = 8, [5] = 6 }

local ROWS = {
  { key = K.RUNNING, label = "RUNNING SHOES", type = "toggle",
    default = true },
  { key = K.RUN_BUTTON, label = "RUN BUTTON", type = "choice",
    default = "hold",
    choices = { { "HOLD B", "hold" }, { "TOGGLE", "toggle" },
                { "ALWAYS", "always" } },
    visible_if = { key = K.RUNNING, equals = true } },

  { key = K.AUTO_SCROLL, label = "AUTO SCROLL", type = "toggle",
    default = true },
  { key = K.HOLD_DELAY, label = "HOLD DELAY", type = "number",
    default = 16, min = 5, max = 60, step = 1,
    visible_if = { key = K.AUTO_SCROLL, equals = true } },
  { key = K.REPEAT_SPEED, label = "REPEAT SPEED", type = "choice",
    default = 3,
    choices = { { "1", 1 }, { "2", 2 }, { "3", 3 }, { "4", 4 }, { "5", 5 } },
    visible_if = { key = K.AUTO_SCROLL, equals = true } },

  { key = K.REPEL, label = "REPEL PROMPT", type = "toggle", default = true },
}

local function rawValue(mod, key)
  local value = mod.options:get(key)
  if value == nil then value = options.DEFAULTS[key] end
  return value
end

local function rowVisible(mod, row)
  local condition = row.visible_if
  if condition == nil then return true end
  if type(condition) ~= "table" or type(condition.key) ~= "string" then
    return false
  end
  local value = rawValue(mod, condition.key)
  if condition.equals ~= nil then return value == condition.equals end
  if condition.not_equals ~= nil then return value ~= condition.not_equals end
  return false
end

function options.install(mod)
  options.DEFAULTS = {}
  local watched = {}
  for _, row in ipairs(ROWS) do
    options.DEFAULTS[row.key] = row.default
    if type(row.visible_if) == "table"
        and type(row.visible_if.key) == "string" then
      watched[row.visible_if.key] = true
    end
  end

  local game
  mod.events:on("game.ready", function(ev) game = (ev and ev.game) or game end)

  local function publish()
    local shown = {}
    for _, row in ipairs(ROWS) do
      if rowVisible(mod, row) then shown[#shown + 1] = row end
    end
    mod.options:define(shown)
    return shown
  end

  -- Re-defining the schema is enough for the NEXT time the options screen
  -- is opened, but the screen currently on the stack has already cached its
  -- rows -- so a row toggled while looking at it does not vanish until you
  -- back out and come in again.  From 0.1.95 the engine rebuilds those rows
  -- itself when a visibility key changes; below that nothing does.
  --
  -- This performs the same rebuild the engine's own refresh() performs, on
  -- the live screen, keeping the cursor on whichever row it was on.  Every
  -- step is guarded: on any engine where the shape differs, the fallback is
  -- the old behaviour of updating on reopen rather than an error.
  local function rebuildOpenMenu(schema)
    local ok, ManagerState = pcall(require, "src.mods.ManagerState")
    if not (ok and ManagerState) then return end
    local stack = game and game.stack
    local top = stack and stack.top and stack:top()
    if not (top and getmetatable(top) == ManagerState) then return end
    if top.screen ~= "options" then return end
    if type(top.buildOptionRows) ~= "function" then return end
    local record = top.currentMod
    if not (record and record.id == mod.id) then return end

    local rows = top.optionRows or {}
    local keep = rows[top.cursor] and rows[top.cursor].id
    top.optionRows = top:buildOptionRows(record, schema)
    local n = #top.optionRows
    if keep then
      for index, row in ipairs(top.optionRows) do
        if row.id == keep then top.cursor = index break end
      end
    end
    if top.cursor > n then top.cursor = n end
    if top.cursor < 1 then top.cursor = 1 end
  end

  publish()

  mod.events:on("mod.options_changed", function(ev)
    if not (ev and ev.mod == mod.id) then return end
    if not watched[ev.key] then return end
    local schema = publish()
    pcall(rebuildOpenMenu, schema)
  end)
end

function options.get(mod, key)
  return rawValue(mod, key)
end

function options.on(mod, key)
  return rawValue(mod, key) == true
end

-- A number row can hold a stale or out-of-range saved value; clamp on read
-- rather than trusting the stored one.
function options.number(mod, key, min, max, fallback)
  local value = tonumber(rawValue(mod, key))
  if value == nil then value = fallback end
  value = math.floor(value + 0.5)
  if value < min then value = min end
  if value > max then value = max end
  return value
end

return options
