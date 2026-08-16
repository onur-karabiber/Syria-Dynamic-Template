-- DEBUG: script load check
trigger.action.outText("CASE III departure rules activated.", 5)

----------------------------------------------------------------
-- TRT CASE III DEPARTURE MODULE (External Script)
-- Extracted from CASE III v13 (SYN3 v10)
-- Self-contained: schedules itself and scores into the same FLAG.
----------------------------------------------------------------

-- ==============================
-- CONFIG (match your mission)
-- ==============================
local PLAYER_NAME = "Player_01"
local CARRIER     = "CVN"
local FLAG        = 1908

-- Enable/disable quickly
local ENABLED = true

-- ==============================
-- SCORE
-- ==============================
local function addScore(delta, reason)
    local cur = trigger.misc.getUserFlag(FLAG)
    if type(cur) ~= "number" then cur = 0 end

    local new = cur + delta
    trigger.action.setUserFlag(FLAG, new)

    local sign = (delta >= 0) and ("+" .. tostring(delta)) or tostring(delta)
    trigger.action.outText(
        tostring(reason) .. " (" .. sign .. ") [TOTAL " .. tostring(new) .. "]",
        8
    )
end

-- ==============================
-- UTILS
-- ==============================
local function uPlayer()
    return Unit.getByName(PLAYER_NAME)
end

local function uCarrier()
    return Unit.getByName(CARRIER)
end

local function altFt(u)
    if not u or not u:isExist() then return 0 end
    local p = u:getPoint()
    return (p and p.y or 0) * 3.28084
end

local function spdKts(u)
    if not u or not u:isExist() then return 0 end
    local v = u:getVelocity()
    if not v then return 0 end
    return math.sqrt((v.x or 0)^2 + (v.z or 0)^2) * 1.94384
end

local function distToCarrierNm(u, c)
    if not u or not u:isExist() or not c or not c:isExist() then return 99999 end
    local pu, pc = u:getPoint(), c:getPoint()
    if not pu or not pc then return 99999 end
    return ((((pu.x - pc.x)^2 + (pu.z - pc.z)^2)^0.5) / 1852)
end

local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

-- ==============================
-- DEPARTURE STATE
-- ==============================
local DEP = {
    active        = false,
    done          = false,
    failed        = false,
    checked5nm    = false,
    spdBadTime    = 0,
    lastCheckTime = 0,
}

-- PARAMETERS (same as your embedded version)
local DEP_SPEED_MIN           = 280        -- kts (horizontal GS)
local DEP_SPEED_MAX           = 320
local DEP_SPEED_GRACE_SEC     = 5
local DEP_5NM_MIN_ALT         = 1500       -- ft
local DEP_SPEED_START_DIST_NM = 0.8
local DEP_FINAL_DIST_NM       = 7

local function resetDeparture()
    DEP.active        = false
    DEP.done          = false
    DEP.failed        = false
    DEP.checked5nm    = false
    DEP.spdBadTime    = 0
    DEP.lastCheckTime = 0
end

local function armDeparture()
    if DEP.active or DEP.done then return end
    DEP.active        = true
    DEP.done          = false
    DEP.failed        = false
    DEP.checked5nm    = false
    DEP.spdBadTime    = 0
    DEP.lastCheckTime = timer.getTime()
    trigger.action.outText("CASE III DEPARTURE: ARMED", 6)
end

local function updateDeparture()
    if not ENABLED then return end
    if not DEP.active or DEP.done then return end

    local u = uPlayer()
    if not u or not u:isExist() then return end

    local c = uCarrier()
    if not c or not c:isExist() then return end

    local now = timer.getTime()
    local dt = now - (DEP.lastCheckTime or now)
    DEP.lastCheckTime = now
    dt = clamp(dt, 0, 2)

    local dist = distToCarrierNm(u, c)
    if dist < 0.3 then return end   -- cat shot noise

    local alt = altFt(u)
    local spd = spdKts(u)

    -- SPEED discipline 0.8–7nm
    if dist >= DEP_SPEED_START_DIST_NM and dist < DEP_FINAL_DIST_NM then
        if spd < DEP_SPEED_MIN or spd > DEP_SPEED_MAX then
            DEP.spdBadTime = DEP.spdBadTime + dt
            if DEP.spdBadTime >= DEP_SPEED_GRACE_SEC then
                DEP.failed = true
            end
        else
            DEP.spdBadTime = 0
        end
    end

    -- 5NM altitude gate (one-shot)
    if dist >= 5 and not DEP.checked5nm then
        if alt < DEP_5NM_MIN_ALT then
            DEP.failed = true
            trigger.action.outText(string.format("CASE III DEPARTURE: FAILED 5 NM ALT (%.0f ft)", alt), 8)
        else
            trigger.action.outText(string.format("CASE III DEPARTURE: 5 NM ALT OK (%.0f ft)", alt), 6)
        end
        DEP.checked5nm = true
    end

    -- final decision at 7nm
    if dist >= DEP_FINAL_DIST_NM then
        if DEP.failed then
            addScore(-5, "Departure: CASE III out of parameters")
        else
            addScore(5, "Departure: CASE III within parameters")
        end
        DEP.done = true
    end
end

-- ==============================
-- ARMING: takeoff event + airborne heuristic
-- ==============================
do
    local DEP_EH = {}
    function DEP_EH:onEvent(e)
        if not ENABLED then return end
        if not e or e.id ~= world.event.S_EVENT_TAKEOFF then return end
        if not e.initiator or not e.initiator.getName then return end
        if e.initiator:getName() ~= PLAYER_NAME then return end
        armDeparture()
    end
    world.addEventHandler(DEP_EH)

    -- Airborne fallback (carrier takeoff event can be flaky)
    timer.scheduleFunction(function()
        if not ENABLED then return timer.getTime() + 1 end
        if DEP.active or DEP.done then return timer.getTime() + 1 end

        local u = uPlayer()
        local c = uCarrier()
        if not u or not u:isExist() or not c or not c:isExist() then
            return timer.getTime() + 1
        end

        local dist = distToCarrierNm(u, c)
        local alt  = altFt(u)
        local spd  = spdKts(u)

        if dist > 0.3 and alt > 50 and spd > 80 then
            armDeparture()
        end

        return timer.getTime() + 1
    end, nil, timer.getTime() + 1)
end

-- ==============================
-- RESET ON TAKEOFF (new cycle)
-- ==============================
do
    local REH = {}
    function REH:onEvent(e)
        if not ENABLED then return end
        if not e or e.id ~= world.event.S_EVENT_TAKEOFF then return end
        if not e.initiator or not e.initiator.getName then return end
        if e.initiator:getName() ~= PLAYER_NAME then return end
        resetDeparture()
        -- then arm will happen via takeoff handler or airborne fallback
    end
    world.addEventHandler(REH)
end

-- ==============================
-- MAIN LOOP (1 Hz)
-- ==============================
timer.scheduleFunction(function()
    updateDeparture()
    return timer.getTime() + 1
end, nil, timer.getTime() + 1)
