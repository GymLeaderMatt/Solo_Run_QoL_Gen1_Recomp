-- Hold to scroll: hold a D-pad direction in menus to repeat.
--
-- TWO PATHS, BECAUSE MENUS READ INPUT TWO DIFFERENT WAYS
--
--   ui.list_menu   turns on the engine's own ListMenu key repeat with the
--                  player's timing.  Covers the bag, shops, PC lists, the
--                  dex, and any ListMenu another mod builds.
--   input.step     injects synthetic press edges for everything else --
--                  the start menu, the party screen, ChoiceBox, the battle
--                  cursor, and the mod manager's own option rows, all of
--                  which poll input:wasPressed rather than owning a clock.
--
-- The second path is why this reaches the MOD OPTIONS screen at all, which
-- matters more than it sounds: Solo Run Modpack's NEW STARTER row lists
-- every species in the game and is otherwise the worst scroll in the set.
--
-- A ListMenu that already owns keyRepeat is skipped by path 2 so the two
-- clocks cannot both fire and double-step.  The overworld never repeats --
-- holding a direction walks, it does not re-trigger.
--
-- Timing is SNAPSHOTTED when a hold begins rather than read live each
-- frame.  Reading it live makes the delay reachable on every subsequent
-- frame once it has elapsed, so the repeat runs away and one axis ends up
-- far faster than the other.
--
-- Follows WizzStar's hold_to_scroll_ui, MIT licensed; the notice ships
-- alongside this file as LICENSE-hold_to_scroll_ui.txt.

local feature = {}

local DEFAULT_DELAY = 16 -- frames, about 0.27s at 60Hz; matches ListMenu
local DEFAULT_SPEED = 3
local DEFAULT_RATE = 10

-- Minigames where a held direction should not repeat.
local DENY_SCREEN_IDS = {
  SlotMachine = true,
  SurfingMinigame = true,
}

function feature.install(mod, options)
  local K = options.KEYS

  local function enabled() return options.on(mod, K.AUTO_SCROLL) end

  local function delayFrames()
    return options.number(mod, K.HOLD_DELAY, 5, 60, DEFAULT_DELAY)
  end

  local function rateFrames()
    local level = options.number(mod, K.REPEAT_SPEED, 1, 5, DEFAULT_SPEED)
    return options.SPEED_FRAMES[level] or DEFAULT_RATE
  end

  -- True when the live stack top is something we should help scroll.
  local function isMenuContext(game)
    if not (game and game.stack and game.stack.top) then return false end
    local top = game.stack:top()
    if not top then return false end
    if top.isOverworld then return false end
    if top.noDpadRepeat == true then return false end
    if top.dpadRepeat == false then return false end
    local id = top.screenId
    if id and DENY_SCREEN_IDS[id] then return false end
    return true
  end

  -- One direction at a time.  Vertical wins over horizontal so a diagonal
  -- press still scrolls the list rather than stepping an option row.
  local function heldDir(input)
    local up, down = input:isDown("up"), input:isDown("down")
    if up and not down then return "up" end
    if down and not up then return "down" end
    local left, right = input:isDown("left"), input:isDown("right")
    if left and not right then return "left" end
    if right and not left then return "right" end
    return nil
  end

  mod.exports.isMenuContext = isMenuContext
  mod.exports.denyScreen = function(screenId)
    if type(screenId) == "string" then DENY_SCREEN_IDS[screenId] = true end
  end
  mod.exports.allowScreen = function(screenId)
    if type(screenId) == "string" then DENY_SCREEN_IDS[screenId] = nil end
  end

  -- Path 1: native ListMenu repeat.
  mod.hooks:wrap("ui.list_menu", function(nextFn, opts, ctx)
    opts = nextFn(opts, ctx) or opts
    if not enabled() then return opts end
    if opts.noDpadRepeat == true then return opts end
    opts.keyRepeat = true
    opts.repeatDelay = delayFrames()
    opts.repeatRate = rateFrames()
    return opts
  end)

  -- Path 2: synthetic edges for edge-only menus.
  local holdDir, holdFrames = nil, 0
  local holdDelay, holdRate = DEFAULT_DELAY, DEFAULT_RATE

  local function resetHold()
    holdDir, holdFrames = nil, 0
    holdDelay, holdRate = DEFAULT_DELAY, DEFAULT_RATE
  end

  mod.hooks:wrap("input.step", function(nextFn, game, dt)
    if not enabled() then
      resetHold()
      return nextFn(game, dt)
    end
    local input = game and game.input
    if not (input and type(input.isDown) == "function") then
      resetHold()
      return nextFn(game, dt)
    end
    if not isMenuContext(game) then
      resetHold()
      return nextFn(game, dt)
    end
    -- a list with its own repeat clock is already handled by path 1
    local top = game.stack:top()
    if top and top.keyRepeat == true then
      resetHold()
      return nextFn(game, dt)
    end

    local dir = heldDir(input)
    if dir ~= holdDir then
      holdDir, holdFrames = dir, 0
      if dir then
        holdDelay, holdRate = delayFrames(), rateFrames()
      end
    end
    if not dir then return nextFn(game, dt) end

    holdFrames = holdFrames + 1
    local afterDelay = holdFrames - holdDelay
    -- frame 1 is the physical press, which is already queued; the first
    -- repeat lands once the delay has elapsed
    if holdFrames > 1 and afterDelay >= 0 and afterDelay % holdRate == 0 then
      local queue = input.pressQueue
      if type(queue) == "table" then queue[#queue + 1] = dir end
    end

    return nextFn(game, dt)
  end)
end

return feature
