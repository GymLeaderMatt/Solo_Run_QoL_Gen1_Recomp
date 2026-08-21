-- Repel reuse prompt: when a Repel wears off, offer another one.
--
-- Gold and later ask instead of making the player reopen the bag.  This
-- reproduces that with public events only -- no patching at all, which is
-- why it is the smallest file here.
--
--   world.stepped   fires BEFORE the engine counts the Repel down, so a
--                   reading of 1 means the wear-off textbox is coming on
--                   this step.  That arms the prompt.
--   screen.popped   tells us a state closed and hands us the state, so the
--                   prompt goes up as the wear-off box comes down.
--
-- The counter is re-checked at zero before prompting, so a box that closed
-- for any other reason cannot trigger it.
--
-- STRONGEST Repel first, which is a speedrun choice rather than the Gen 2
-- one.  A run buys an exact count of Super Repels and carries a single
-- plain Repel purely to hold a bag slot; spending the cheap one first
-- burns the slot-holder and leaves the counted Supers unspent, which
-- changes how full the bag is at every later check.  Preference is
-- positional -- the order of REPELS below is the whole rule -- so putting
-- MAX_REPEL first spends down from the top and leaves the filler alone.
--
-- An empty bag prompts nothing, exactly like Gen 2.
--
-- The cursor opens on YES.  Both answers are then one held button: A
-- confirms, B backs out, and neither needs a D-pad input first.
--
-- Follows johnjohto's jj_repel_prompt.

local feature = {}

local REPELS = { "MAX_REPEL", "SUPER_REPEL", "REPEL" }

function feature.install(mod, options)
  local K = options.KEYS

  local TextBox = mod.ui.TextBox
  local ItemEffects = require("src.inventory.ItemEffects")
  local Bag = require("src.inventory.Bag")

  local game
  local pending = false

  local function repelInBag(save)
    for _, id in ipairs(REPELS) do
      if (save.inventory or {})[id] then return id end
    end
    return nil
  end

  mod.events:on("game.ready", function(ev) game = (ev and ev.game) or game end)

  mod.events:on("world.stepped", function()
    if not options.on(mod, K.REPEL) then
      pending = false
      return
    end
    pending = game ~= nil and (game.save.repelSteps or 0) == 1
  end)

  mod.events:on("screen.popped", function(ev)
    if not pending then return end
    if not options.on(mod, K.REPEL) then
      pending = false
      return
    end
    local state = ev and ev.state
    -- not the wear-off box: leave pending armed, it may still be open
    if getmetatable(state) ~= TextBox then return end
    local g = state.game
    if not g or (g.save.repelSteps or 0) ~= 0 then return end
    pending = false

    local id = repelInBag(g.save)
    if not id then return end
    local def = g.data.items[id]
    g.stack:push(TextBox.new(g,
      ("Use another\n%s?"):format(def and def.name or id), nil, {
        choice = function(yes)
          if not yes then return end
          Bag.remove(g.save, id, 1)
          local _, payload = ItemEffects.use(g.data, g.save, id)
          if payload and payload[1] then
            g.stack:push(TextBox.new(g, payload[1]))
          end
        end,
      }))
  end)
end

return feature
