-- Score_Display | v1.1.1
--[[
  Picture score cards (CAS (L) only; not part of the template build).

  v1.1.1: plane captain cards top-left, 24 % (Onur, test 2026-10-28). They share the corner
          with the CRT score card; the two do not overlap in time in CAS-1 (cards: deck only).
          Verified 2026-10-28: clearView=true removes earlier pictures (blank.png clears S4).

  v1.1.0: plane captain step cards for PlaneCaptain_Carrier v1.3.0+:
          pcHas(id) / pcCard(id) / pcClear(). Cards PlaneCaptain/<id>.png (CFG.PC.IDS),
          shown with clearView=true so each card replaces the previous one;
          pcClear() shows PlaneCaptain/blank.png with clearView=true to remove the last card.

  CRT card    every score change: frame + total (orange) + delta (green / red),
              top-left, CFG.CRT. Deltas arriving within CFG.AGG s are summed
              into one card. Sound: reward (delta > 0) / penalty (delta < 0).
  Medal card  once, when Deck_Park reports the post-trap engine shutdown
              (flag 1910 -> 1 in spot / 2 outside spot), CFG.MEDAL_DELAY s
              later so the parking delta settles first. Sound: mission_end.
              No medal for 3 (not completed) or a land-based landing.

  Hooks TRT.addScore (Core_Scoring): the original runs first, unchanged (text
  message, flag 1908), then the card is queued. Every current scorer calls
  TRT.addScore(...) through the table; a module caching the function in a
  local before this file loads would bypass the card.

  Mechanics (verified 2026-10-27 with Score_Display_Test v0.1.1-0.1.2):
    * trigger.action.outPicture* does not exist. Pictures go through
      net.dostring_in("mission", 'a_out_picture_s("blue", file, dur, clearView,
      delay, "hAlign", "vAlign", size, "sizeUnits")') - the ME action, same
      route as MOOSE UTILS.ShowPictureToCoalition.
    * File names resolve from the .miz root ("ScoreCards/x.png") or as
      "l10n/DEFAULT/x.png"; a bare "x.png" does not. ScoreCards/ and
      Sounds/SCORE/ survive a Mission Editor save.
    * Layers called later draw on top; same-size layers with identical
      align/size arguments overlay exactly.
    * Score cards use clearView=false, so they never wipe outText messages
      (JTAC 9-line etc.). A newer card covers an older one at the same spot.
      Plane captain cards (deck only) use clearView=true, see v1.1.0.
  hAlign 0 left 1 centre 2 right | vAlign 0 top 1 centre 2 bottom |
  sizeUnits 0 % of image, 1 % of window.

  Assets: tools/score_cards (make_cards.py, make_sfx.py); installed into the
  .miz by tools/score_cards/install_score_display.py.
  Load order: after Core_Scoring.lua (and Deck_Park.lua for the medal).

  API: TRT.ScoreDisplay.crt(total, delta) | .medal(total)
       | .pcHas(id) | .pcCard(id) | .pcClear() | .version
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT

local VERSION = "1.1.1"

local CFG = {
    DIR         = "ScoreCards/",
    SND_DIR     = "Sounds/SCORE/",
    COALITION   = "blue",                  -- a_out_picture_s coalition name
    SIDE        = coalition.side.BLUE,     -- outSoundForCoalition
    FLAG_SCORE  = 1908,                    -- Core_Scoring FLAG_SCORE
    FLAG_PARK   = 1910,                    -- Deck_Park FLAG_RESULT
    AGG         = 1.2,                     -- s
    POLL        = 1,                       -- s, flag 1910 poll
    MEDAL_DELAY = 3,                       -- s after the park result
    SOUND       = true,
    CRT         = { dur = 6,  h = 0, v = 0, size = 22, units = 1 },
    MED         = { dur = 12, h = 1, v = 1, size = 50, units = 1 },
    PC          = { dir = "PlaneCaptain/", dur = 600, h = 0, v = 0, size = 24, units = 1,
                    -- must match tools/score_cards/out/PlaneCaptain (make_pc_cards.py IDS present)
                    IDS = { "S00", "S0P", "S2", "S2W", "S3", "S3W", "S4",
                            "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10",
                            "C11", "C12", "C13", "C14" } },
}

local function log(s) env.info("Score_Display | " .. s) end

if TRT.ScoreDisplay then
    log("already loaded, second copy ignored")
    return
end

----------------------------------------------------------------
-- LOW LEVEL
----------------------------------------------------------------
local canPic = (net ~= nil) and (type(net.dostring_in) == "function")
if not canPic then log("net.dostring_in not available -> pictures OFF, sounds only") end

local function pic(file, lay, clear)
    if not canPic then return false end
    local code = string.format('a_out_picture_s(%q, %q, %d, %s, 0, "%d", "%d", %d, "%d")',
        CFG.COALITION, file, lay.dur, clear and "true" or "false", lay.h, lay.v, lay.size, lay.units)
    local ok, res, okd = pcall(net.dostring_in, "mission", code)
    if not ok or okd == false then
        log("picture failed: " .. tostring(res) .. " | " .. code)
        return false
    end
    return true
end

local function sound(name)
    if not CFG.SOUND then return end
    local f = CFG.SND_DIR .. name .. ".ogg"
    local ok, err = pcall(trigger.action.outSoundForCoalition, CFG.SIDE, f)
    if not ok then log("sound failed '" .. f .. "': " .. tostring(err)) end
end

local GL = { ["+"] = "p", ["-"] = "m" }

-- char i of a string of length n -> slot 2(i-1)-(n-1)+3 (0..6), centred
local function layerFiles(set, text, out)
    local n = #text
    for i = 1, n do
        local ch = text:sub(i, i)
        out[#out + 1] = string.format("%s%s_%s_%d.png", CFG.DIR, set, GL[ch] or ch,
            2 * (i - 1) - (n - 1) + 3)
    end
    return out
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function round(v) return math.floor(v + 0.5) end
local function fmtTotal(v) return tostring(clamp(round(v), -999, 9999)) end
local function fmtDelta(v)
    local d = clamp(round(v), -999, 999)
    return (d >= 0) and ("+" .. d) or tostring(d)
end

local function scoreNow()
    return tonumber(trigger.misc.getUserFlag(CFG.FLAG_SCORE)) or 0
end

----------------------------------------------------------------
-- CARDS
----------------------------------------------------------------
local function crt(total, delta)
    local files = layerFiles("crt_t", fmtTotal(total), { CFG.DIR .. "crt_frame.png" })
    if delta and round(delta) ~= 0 then
        layerFiles(delta > 0 and "crt_dp" or "crt_dn", fmtDelta(delta), files)
    end
    for _, f in ipairs(files) do pic(f, CFG.CRT) end
    log(string.format("CRT total=%s delta=%s", fmtTotal(total), delta and fmtDelta(delta) or "-"))
end

local function medal(total)
    local files = layerFiles("med_t", fmtTotal(total), { CFG.DIR .. "med_frame.png" })
    for _, f in ipairs(files) do pic(f, CFG.MED) end
    sound("mission_end")
    log("MEDAL total=" .. fmtTotal(total))
end

----------------------------------------------------------------
-- AGGREGATION
----------------------------------------------------------------
local Q = { pending = 0, armed = false }

local function flush()
    Q.armed = false
    local d = Q.pending
    Q.pending = 0
    local ok, err = pcall(function()
        crt(scoreNow(), d)
        if d > 0 then sound("reward") elseif d < 0 then sound("penalty") end
    end)
    if not ok then log("flush: " .. tostring(err)) end
    return nil
end

local function push(delta)
    Q.pending = Q.pending + delta
    if not Q.armed then
        Q.armed = true
        timer.scheduleFunction(flush, nil, timer.getTime() + CFG.AGG)
    end
end

----------------------------------------------------------------
-- HOOK
----------------------------------------------------------------
if type(TRT.addScore) == "function" then
    local orig = TRT.addScore
    TRT.addScore = function(delta, reason)
        orig(delta, reason)
        local d = tonumber(delta)
        if d and d ~= 0 then push(d) end
    end
    log("TRT.addScore hooked")
else
    log("ERROR: TRT.addScore missing - load Score_Display.lua after Core_Scoring.lua")
end

----------------------------------------------------------------
-- MEDAL TRIGGER (Deck_Park result flag)
----------------------------------------------------------------
local medalDone = false
timer.scheduleFunction(function(_, t)
    if medalDone then return nil end
    local r = tonumber(trigger.misc.getUserFlag(CFG.FLAG_PARK)) or 0
    if r == 1 or r == 2 then
        medalDone = true
        log("park result " .. r .. " -> medal in " .. CFG.MEDAL_DELAY .. " s")
        timer.scheduleFunction(function()
            local ok, err = pcall(function() medal(scoreNow()) end)
            if not ok then log("medal: " .. tostring(err)) end
            return nil
        end, nil, timer.getTime() + CFG.MEDAL_DELAY)
        return nil
    end
    return t + CFG.POLL
end, nil, timer.getTime() + CFG.POLL)

----------------------------------------------------------------
-- PLANE CAPTAIN CARDS (v1.1.0)
----------------------------------------------------------------
local PCSET = {}
for _, id in ipairs(CFG.PC.IDS) do PCSET[id] = true end
local pcShown = false

local function pcHas(id) return canPic and PCSET[id] == true end

local function pcCard(id)
    if not pcHas(id) then return false end
    local ok = pic(CFG.PC.dir .. id .. ".png", CFG.PC, true)
    pcShown = pcShown or ok
    return ok
end

local function pcClear()
    if not (canPic and pcShown) then return end
    pic(CFG.PC.dir .. "blank.png", { dur = 1, h = CFG.PC.h, v = CFG.PC.v, size = 1, units = 1 }, true)
    pcShown = false
end

TRT.ScoreDisplay = { crt = crt, medal = medal, pcHas = pcHas, pcCard = pcCard, pcClear = pcClear,
                     version = VERSION }
log("v" .. VERSION .. " loaded (pictures " .. (canPic and "ON" or "OFF") .. ")")
