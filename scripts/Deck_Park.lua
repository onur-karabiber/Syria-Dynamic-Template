-- Deck_Park | v1.0.0
-- TRT Syria Recovery Framework - post-trap deck parking score.
--
-- Rule (single-player, hero = TRT.PLAYER_NAME, default "Player_01"):
--   After a trap on CVN, the FIRST S_EVENT_ENGINE_SHUTDOWN of the hero:
--     inside the park spot  -> +PARK_PTS            (flag FLAG_RESULT = 1)
--     outside the park spot -> 0                    (flag FLAG_RESULT = 2)
--   Hero leaves the slot / dies / crashes / ejects after the trap but
--   before shutdown -> "NOT COMPLETED", no score   (flag FLAG_RESULT = 3)
--   FLAG_RESULT = 0 while pending. No alignment, time, taxi-speed or
--   distance-graded scoring (by design).
--
-- Park spot: a plain circular ME trigger zone (PARK_ZONE), drawn on the
-- empty deck spot while the carrier sits at its ME start position.
-- Do NOT link it to the carrier (no LINK UNIT): the script reads the raw
-- ME data (env.mission) for both the zone and the carrier's start pose,
-- converts the zone centre into a carrier body-frame offset once
-- (forward / starboard metres), and re-applies that offset to the
-- carrier's live position and heading at shutdown time. So the spot
-- moves and turns with the ship (AIRBOSS turning into the wind included).
--
-- Draw the zone where the aircraft ENDS UP: when deck parking completes,
-- DCS turns the nose around and repositions the aircraft itself; the
-- shutdown position is measured after that.
--
-- Load order: after Core_Scoring.lua (uses TRT.addScore).
--
-- UNVERIFIED, check dcs.log on the first test flight ("[Deck_Park]" lines):
--   * whether the Hornet fires ENGINE_SHUTDOWN once or once per engine
--     (every event is logged with a counter; only the first one scores);
--   * the measured distance between the aircraft and the spot centre at
--     shutdown, to size the zone radius.

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local VERSION = "v1.0.0"
local TAG     = "[Deck_Park " .. VERSION .. "] "

local CFG = {
    PARK_ZONE      = "CV_PARK_01",   -- ME trigger zone (circle)
    CARRIER        = "CVN",          -- carrier unit name (ME)
    PARK_PTS       = 5,
    FLAG_RESULT    = 1910,           -- 0 pending, 1 in spot, 2 outside, 3 not completed
    TRAP_RADIUS_NM = 0.15,           -- same as Core_Scoring TRAP_RADIUS_NM
    MSG_TIME       = 10,
}

_G.TRT = _G.TRT or {}
local TRT    = _G.TRT
local PLAYER = TRT.PLAYER_NAME or "Player_01"

local function log(s) env.info(TAG .. s) end

----------------------------------------------------------------
-- ME DATA LOOKUP (static t=0 data, independent of load time)
----------------------------------------------------------------
local function findMeUnit(name)
    local co = env.mission and env.mission.coalition
    if not co then return nil end
    for _, side in pairs(co) do
        for _, ctry in pairs(side.country or {}) do
            for _, g in pairs((ctry.ship and ctry.ship.group) or {}) do
                for _, u in pairs(g.units or {}) do
                    if u.name == name then return u end
                end
            end
        end
    end
    return nil
end

local function findMeZone(name)
    local zs = env.mission and env.mission.triggers and env.mission.triggers.zones
    for _, z in pairs(zs or {}) do
        if z.name == name then return z end
    end
    return nil
end

----------------------------------------------------------------
-- BODY FRAME
-- World: x = north, z = east (ME y == world z). Heading clockwise from +x.
-- forward = (cos h, sin h), starboard = (-sin h, cos h).
----------------------------------------------------------------
local function toBody(dx, dz, h)
    local c, s = math.cos(h), math.sin(h)
    return dx * c + dz * s, -dx * s + dz * c          -- fwd, stbd
end

local function carrierPose(cv)
    local p   = cv:getPoint()
    local pos = cv:getPosition()
    if not p or not pos or not pos.x then return nil end
    return p.x, p.z, math.atan2(pos.x.z, pos.x.x)
end

----------------------------------------------------------------
-- SPOT OFFSET (computed once at load)
----------------------------------------------------------------
local SPOT = nil   -- { fwd = m, stbd = m, r = m }

do
    local mz = findMeZone(CFG.PARK_ZONE)
    local mu = findMeUnit(CFG.CARRIER)
    if not mz then
        log("ERROR: ME zone '" .. CFG.PARK_ZONE .. "' not found - module inactive.")
    elseif mz.type and mz.type ~= 0 then
        log("ERROR: zone '" .. CFG.PARK_ZONE .. "' is not a circle (type " .. tostring(mz.type) .. ") - module inactive.")
    elseif not mu then
        log("ERROR: ME ship unit '" .. CFG.CARRIER .. "' not found - module inactive.")
    else
        local f, s = toBody(mz.x - mu.x, mz.y - mu.y, mu.heading or 0)
        SPOT = { fwd = f, stbd = s, r = mz.radius or 0 }
        log(string.format("spot '%s': fwd %.1f m, stbd %.1f m, radius %.1f m (carrier ME hdg %.1f deg)",
            CFG.PARK_ZONE, f, s, SPOT.r, math.deg(mu.heading or 0)))
        if SPOT.r <= 0 then log("WARNING: zone radius is 0.") end
    end
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local ST_IDLE, ST_ARMED, ST_DONE = 0, 1, 2
local state      = ST_IDLE
local nShutdown  = 0

trigger.action.setUserFlag(CFG.FLAG_RESULT, 0)

local function say(text)
    trigger.action.outTextForCoalition(coalition.side.BLUE, text, CFG.MSG_TIME, false)
end

local function score(delta, reason)
    if TRT.addScore then
        TRT.addScore(delta, reason)
    else
        log("WARNING: TRT.addScore missing (Core_Scoring not loaded?) - " .. reason)
        say(reason)
    end
end

-- Returns distance (m) from aircraft to the spot centre, plus body offsets.
local function measure(u)
    local cv = Unit.getByName(CFG.CARRIER)
    if not cv or not cv:isExist() then return nil end
    local cx, cz, h = carrierPose(cv)
    if not cx then return nil end
    local p = u:getPoint()
    local f, s = toBody(p.x - cx, p.z - cz, h)
    local d = math.sqrt((f - SPOT.fwd)^2 + (s - SPOT.stbd)^2)
    return d, f, s
end

local function finishIncomplete(why)
    state = ST_DONE
    trigger.action.setUserFlag(CFG.FLAG_RESULT, 3)
    log("NOT COMPLETED: " .. why)
    say("Deck park: NOT COMPLETED (" .. why .. ")")
end

----------------------------------------------------------------
-- EVENTS
----------------------------------------------------------------
local EV = world.event
local H = {}

function H:onEvent(e)
    if not SPOT or not e or not e.initiator then return end
    local u = e.initiator
    if not u.getName then return end
    local ok, n = pcall(u.getName, u)
    if not ok or n ~= PLAYER then return end

    if e.id == EV.S_EVENT_LAND then
        local cv = Unit.getByName(CFG.CARRIER)
        local near = false
        if cv and cv:isExist() then
            local a, b = u:getPoint(), cv:getPoint()
            near = math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2) <= CFG.TRAP_RADIUS_NM * 1852
        end
        if state == ST_IDLE and near then
            state, nShutdown = ST_ARMED, 0
            trigger.action.setUserFlag(CFG.FLAG_RESULT, 0)
            log("armed (trap on " .. CFG.CARRIER .. ")")
        end

    elseif e.id == EV.S_EVENT_TAKEOFF then
        if state == ST_ARMED then log("disarmed (takeoff)") end
        if state ~= ST_DONE then state = ST_IDLE end

    elseif e.id == EV.S_EVENT_ENGINE_SHUTDOWN then
        nShutdown = nShutdown + 1
        local d, f, s = measure(u)
        log(string.format("ENGINE_SHUTDOWN #%d t=%.1f state=%d  ac fwd %s stbd %s  dist-to-spot %s m",
            nShutdown, timer.getTime(), state,
            f and string.format("%.1f", f) or "?", s and string.format("%.1f", s) or "?",
            d and string.format("%.1f", d) or "?"))
        if state ~= ST_ARMED then return end
        if not d then log("carrier not found at shutdown - no result"); return end

        state = ST_DONE
        if d <= SPOT.r then
            trigger.action.setUserFlag(CFG.FLAG_RESULT, 1)
            score(CFG.PARK_PTS, "Deck park: shut down in assigned spot")
        else
            trigger.action.setUserFlag(CFG.FLAG_RESULT, 2)
            score(0, string.format("Deck park: shut down outside assigned spot (%.0f m off)", d))
        end

    elseif state == ST_ARMED then
        if e.id == EV.S_EVENT_PLAYER_LEAVE_UNIT then finishIncomplete("left the aircraft before shutdown")
        elseif e.id == EV.S_EVENT_CRASH or e.id == EV.S_EVENT_DEAD then finishIncomplete("aircraft lost")
        elseif e.id == EV.S_EVENT_EJECTION then finishIncomplete("ejected") end
    end
end

world.addEventHandler(H)
log("loaded, hero '" .. PLAYER .. "'" .. (SPOT and "" or " (INACTIVE)"))
