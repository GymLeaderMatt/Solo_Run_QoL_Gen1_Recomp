-- Running shoes: double speed on foot, with the bicycle scaled to match.
--
-- THE NUMBERS
--
-- A tile takes 16 frames on foot and 8 on the bicycle -- the bike is
-- already twice walking speed in vanilla.  Every mode gets the same 2x
-- multiplier, applied to its own baseline:
--
--     on foot   16 -> 8 frames per tile, WHILE THE RUN TRIGGER IS ACTIVE
--     bicycle    8 -> 4 frames per tile, always
--     surfing   16 -> 8 frames per tile, always
--
-- The bike therefore keeps its 2:1 lead over a runner rather than being
-- caught by one.
--
-- THE RUN TRIGGER ONLY APPLIES ON FOOT, WHICH IS THE FIX FOR TWO BUGS
--
-- Gating the bike on the run trigger meant B made an already-doubled bike
-- twice as fast again -- a 4x bicycle nobody asked for, and off-trigger it
-- silently dropped back to vanilla.  Riding and surfing are modes, not
-- efforts: they are simply fast, and the button does nothing in them.
--
-- So `hurried` is true unconditionally while riding or surfing, and only
-- consults the trigger on foot.  One consequence worth stating: the
-- RUNNING SHOES row is the master switch for all three.  Turn it off and
-- every mode is vanilla again, bicycle and water included.
--
-- TWO SEAMS
--
--   speed      movement.speed is the engine's own hook for exactly this
--              ("running shoes, dash" -- src/world/Player.lua:149).  It is
--              handed the step length in frames and the mod divides it.
--   animation  the leg cadence has no hook, so Player.update is patched.
--              The engine ticks animClock once per real frame, so a
--              shortened step would land mid-cycle and read as a slide.
--              Paying the clock the step's UNHURRIED length across the
--              short step -- by the same Bresenham step the engine uses for
--              its pixel offset -- advances the legs at exactly the
--              multiplier.  On foot that is one full cycle per tile, so the
--              mirror flip keeps alternating per tile the way walking does.
--
-- Nothing else moves.  Encounters, poison and daycare exp all fire from
-- OverworldState:onStepComplete, once per tile rather than per frame, so
-- covering ground faster does not touch a single rate.
--
-- Follows johnjohto's jj_running_shoes, which worked the maths out first.

local feature = {}

local RUN_MULTIPLIER = 2
local BIKE_MULTIPLIER = 1.25
local SURF_MULTIPLIER = 2

-- Modes that are fast in their own right; the run trigger is not consulted
-- in them and holding B changes nothing.
local UNTRIGGERED = { surfing = true, onBike = true }

-- One full leg cycle in animation-clock ticks.  Player:walkPhase reads
-- animClock % 16 and pose() derives the mirror flip from
-- floor(animClock / 16), so 16 is the cycle both agree on.
local CYCLE = 16

-- Ticks owed by the frame carrying a step from progress-1 to progress,
-- where `base` is the step length this mode would have had unhurried.
local function animTicks(progress, stepLen, base)
  base = base or CYCLE
  return math.floor(progress * base / stepLen)
       - math.floor((progress - 1) * base / stepLen)
end

function feature.install(mod, options)
  local K = options.KEYS

  local Player = require("src.world.Player")
  local Game = require("src.core.Game")

  -- The TOGGLE latch. Deliberately not saved: a run state that survived a
  -- reload would leave the player at double speed with no memory of asking.
  local toggled = false

  local function multiplier(ctx)
    if ctx.surfing then return SURF_MULTIPLIER end
    if ctx.onBike then return BIKE_MULTIPLIER end
    return RUN_MULTIPLIER
  end

  local function running(ctx)
    if not options.on(mod, K.RUNNING) then return false end
    if multiplier(ctx) <= 1 then return false end
    -- surfing is checked first: the sea is crossed on the water sprite
    -- whatever the player was riding when they stepped in
    if ctx.surfing then return UNTRIGGERED.surfing end
    if ctx.onBike then return UNTRIGGERED.onBike end
    local button = options.get(mod, K.RUN_BUTTON) or "hold"
    if button == "always" then return true end
    if button == "toggle" then return toggled end
    local input = ctx.input
    return input ~= nil and input.isDown ~= nil and input:isDown("b") == true
  end

  -- nextFn first, so a sibling speed mod still gets its say and this one
  -- scales whatever it settled on.
  mod.hooks:wrap("movement.speed", function(nextFn, frames, ctx)
    frames = nextFn(frames, ctx)
    local hurried = running(ctx)
    local player = ctx.player
    -- read by the patch below; written on every step so they cannot go
    -- stale.  srRunBase is this mode's unhurried step length, which is what
    -- the animation clock is paid in: 16 on foot, 8 on the bicycle.
    if player then
      player.srRunning = hurried
      player.srRunBase = frames
    end
    if not hurried then return frames end
    return math.max(1, math.floor(frames / multiplier(ctx)))
  end)

  -- Player is a required singleton and survives an F5 reload while this
  -- environment does not, so marker+slot rather than a boolean guard.
  local slot = rawget(Player, "__soloRunShoes")
  if not slot then
    slot = {}
    Player.__soloRunShoes = slot
    local original = Player.update
    Player.update = function(self, ...)
      if slot.onFrame then slot.onFrame() end
      -- captured before the vanilla step, which advances progress itself
      local stepLen = self.srRunning and self.moving and self.stepFramesCur
      local progress = stepLen and (self.progress or 0)
      local landed = original(self, ...)
      if progress and slot.animExtra then
        local extra = slot.animExtra(progress + 1, stepLen, self.srRunBase)
        if extra > 0 then self.animClock = (self.animClock or 0) + extra end
      end
      if landed then
        self.srRunning = false
        -- Hand the unhurried step length back.  A scripted step
        -- (OverworldState:scriptMove -- Oak walking the player to the lab,
        -- and every other cutscene) sets moving/progress directly and never
        -- calls tryMove, so movement.speed never fires for it: it inherits
        -- whatever stepFramesCur the last free-roam step left behind.  Left
        -- hurried, the player crosses a scripted tile in half the frames
        -- while the NPC being followed is pinned to its own step length,
        -- and walks straight past them.
        if self.srRunBase then self.stepFramesCur = self.srRunBase end
      end
      return landed
    end
  end

  -- The toggle latch flips here rather than in the speed hook, which only
  -- fires on a step that actually starts -- a tap while standing still has
  -- to count.  StateStack updates the top state only, so this runs in the
  -- free-roam overworld alone: the B that backs out of a menu or a battle
  -- never reaches the latch.
  slot.onFrame = function()
    if not options.on(mod, K.RUNNING) then return end
    if options.get(mod, K.RUN_BUTTON) ~= "toggle" then return end
    local input = Game.input
    if input and input.wasPressed and input:wasPressed("b") then
      toggled = not toggled
    end
  end

  slot.animExtra = function(progress, stepLen, base)
    return animTicks(progress, stepLen, base) - 1
  end
end

return feature
