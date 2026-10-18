-- Departure | v1.0.0
-- CASE-adaptive departure scoring. Replaces CASE_III_Departure.lua and
-- CASE_IorII_Departure.lua. Case is snapshotted at ARM time (takeoff) -
-- a departure procedure doesn't switch profile mid-transit in practice,
-- unlike the approach, which can span a longer window where weather
-- may actually change.
--
-- Load order: AFTER Core_Scoring.lua and CaseDeterminator.lua.

_G.TRT = _G.TRT or {}
local TRT = _G.TRT

local PLAYER_NAME = "Player_01"
local BRC = 355

-- CASE I/II profile (from CASE_IorII_Departure.lua)
local IORII_ALT_MIN, IORII_ALT_MAX = 400, 650
local IORII_SPD_MIN, IORII_SPD_MAX = 285, 330
local IORII_HDG_TOL_DEG = 12
local IORII_ARM_DIST_NM = 1.2

-- CASE III profile (from CASE_III_Departure.lua)
local III_SPD_MIN, III_SPD_MAX = 280, 320
local III_SPD_GRACE_SEC = 5
local III_5NM_MIN_ALT = 1500
local III_SPD_START_DIST_NM = 0.8

local FINAL_DIST_NM = 7
local NEAR_CARRIER_NM = 0.25

local DEP = {
    active = false, done = false, case = nil,
    good = false, bad = false,
    spdBadTime = 0, checked5nm = false, lastCheckTime = 0,
}

local function resetDeparture()
    DEP.active, DEP.done = false, false
    DEP.good, DEP.bad = false, false
    DEP.spdBadTime, DEP.checked5nm, DEP.lastCheckTime = 0, false, 0
end

-- Always resets on call - re-arms fresh on every takeoff so repeated
-- departures (touch-and-go, multiple sorties in one mission) each get
-- scored, matching CASE_IorII_Departure.lua's original behavior.
local function armDeparture()
    resetDeparture()
    DEP.active = true
    DEP.case = TRT.getCurrentCase()
    DEP.lastCheckTime = timer.getTime()
    trigger.action.outText("DEPARTURE: ARMED (CASE " .. DEP.case .. ")", 6)
end

local function nearCarrier(u)
    local c = TRT.uCarrier()
    if not c or not c:isExist() then return false end
    return TRT.distToCarrierNm(u, c) <= NEAR_CARRIER_NM
end

local function updateIorII(u, dist)
    local alt, spd = TRT.altFt(u), TRT.spdKts(u)
    local hdg = TRT.getHeading(u)
    local hdgDiff = math.abs(hdg - BRC)
    if hdgDiff > 180 then hdgDiff = 360 - hdgDiff end

    local altOK = alt >= IORII_ALT_MIN and alt <= IORII_ALT_MAX
    local spdOK = spd >= IORII_SPD_MIN and spd <= IORII_SPD_MAX
    local hdgOK = hdgDiff <= IORII_HDG_TOL_DEG

    if altOK and spdOK and hdgOK then DEP.good = true else DEP.bad = true end

    if dist >= FINAL_DIST_NM then
        if DEP.good and not DEP.bad then
            TRT.addScore(5, "Departure: Within parameters")
        else
            TRT.addScore(-5, "Departure: Out of parameters")
        end
        DEP.done = true
    end
end

local function updateIII(u, dist, dt)
    local alt, spd = TRT.altFt(u), TRT.spdKts(u)

    if dist >= III_SPD_START_DIST_NM and dist < FINAL_DIST_NM then
        if spd < III_SPD_MIN or spd > III_SPD_MAX then
            DEP.spdBadTime = DEP.spdBadTime + dt
            if DEP.spdBadTime >= III_SPD_GRACE_SEC then DEP.bad = true end
        else
            DEP.spdBadTime = 0
        end
    end

    if dist >= 5 and not DEP.checked5nm then
        if alt < III_5NM_MIN_ALT then
            DEP.bad = true
            trigger.action.outText(string.format("DEPARTURE: FAILED 5NM ALT (%.0f ft)", alt), 8)
        end
        DEP.checked5nm = true
    end

    if dist >= FINAL_DIST_NM then
        if DEP.bad then
            TRT.addScore(-5, "Departure: CASE III out of parameters")
        else
            TRT.addScore(5, "Departure: CASE III within parameters")
        end
        DEP.done = true
    end
end

local function updateDeparture()
    if not DEP.active or DEP.done then return end

    local u = TRT.uPlayer()
    local c = TRT.uCarrier()
    if not u or not u:isExist() or not c or not c:isExist() then return end

    local now = timer.getTime()
    local dt = TRT.clamp(now - DEP.lastCheckTime, 0, 2)
    DEP.lastCheckTime = now

    local dist = TRT.distToCarrierNm(u, c)
    if dist < 0.3 then return end

    if DEP.case == 3 then
        updateIII(u, dist, dt)
    else
        if dist < IORII_ARM_DIST_NM then return end
        updateIorII(u, dist)
    end
end

----------------------------------------------------------------
-- ARMING: TAKEOFF event, BIRTH-near-carrier (hot start), and an
-- airborne-heuristic fallback poll (carrier TAKEOFF events can be
-- flaky in DCS - kept from CASE_III_Departure.lua's original comment).
----------------------------------------------------------------
do
    local EH = {}
    function EH:onEvent(e)
        if not e or not e.initiator or not e.initiator.getName then return end
        if e.initiator:getName() ~= PLAYER_NAME then return end

        if e.id == world.event.S_EVENT_TAKEOFF then
            armDeparture()
        elseif e.id == world.event.S_EVENT_BIRTH and nearCarrier(e.initiator) then
            armDeparture()
        end
    end
    world.addEventHandler(EH)
end

timer.scheduleFunction(function()
    if not DEP.active and not DEP.done then
        local u = TRT.uPlayer()
        local c = TRT.uCarrier()
        if u and u:isExist() and c and c:isExist() then
            local dist = TRT.distToCarrierNm(u, c)
            local alt  = TRT.altFt(u)
            local spd  = TRT.spdKts(u)
            if dist > 0.3 and alt > 50 and spd > 80 then
                armDeparture()
            end
        end
    end

    updateDeparture()
    return timer.getTime() + 1
end, nil, timer.getTime() + 1)

env.info("[Departure] v1.0.0 loaded.")
