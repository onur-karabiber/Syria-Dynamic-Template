-- DEBUG: script yüklendi mi?
env.info("Flaggers v1 loaded")   -- P1 2026-11-05: dcs.log only (no banner)

----------------------------------------------------------------
-- CASE III FLAG SCRIPT (Standalone)
-- Purpose: Only sets FLAGS ON for refuel / landing / zones / target deaths
-- Does NOT touch scoring or CASE III logic.
----------------------------------------------------------------

----------------------------------------------------------------
-- FLAGS
----------------------------------------------------------------
local FLAG_REFUEL_P1   = 2341
local FLAG_REFUEL_P2   = 2342

local FLAG_LAND_P1     = 2343
local FLAG_LAND_P2     = 2344

local FLAG_CONV3_P1    = 2443
local FLAG_CONV3_P2    = 2444
local FLAG_CONV6_P1    = 2446
local FLAG_CONV6_P2    = 2447

local FLAG_TRG1_DEAD   = 2541 -- STRIKE1_TRG1
local FLAG_TRG2_DEAD   = 2542 -- STRIKE1_TRG2

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local PLAYERS = { "Player_01", "Player_02" }

local REFUEL_ZONE_NAME = "TANKER_1_SAFE_ZONE"
local CONV3_ZONE_NAME  = "Conversation_3"
local CONV6_ZONE_NAME  = "Conversation_6"

-- Refuel detection tuning:
-- We detect refuel by seeing fuel increase while inside the tanker safe zone.
-- This avoids messing with your scoring logic.
local REFUEL_MIN_FUEL_DELTA = 0.2  -- in "tons" or whatever DCS returns; adjust if needed
local REFUEL_POLL_RATE_SEC  = 1

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------
local function setFlagON(flagNum)
    trigger.action.setUserFlag(flagNum, 1)
end

local function getUnit(name)
    local u = Unit.getByName(name)
    if u and u:isExist() then return u end
    return nil
end

local function getStatic(name)
    local s = StaticObject.getByName(name)
    if s then return s end
    return nil
end

local function getZone(name)
    return trigger.misc.getZone(name)
end

local function pointInZone(point, zone)
    if not zone or not zone.point then return false end
    local dx = point.x - zone.point.x
    local dz = point.z - zone.point.z
    return (dx * dx + dz * dz) <= (zone.radius * zone.radius)
end

----------------------------------------------------------------
-- ZONE ENTRY FLAGS
----------------------------------------------------------------
local zoneOnce = {
    ["Player_01"] = { conv3 = false, conv6 = false },
    ["Player_02"] = { conv3 = false, conv6 = false },
}

local function updateConversationZones()
    local z3 = getZone(CONV3_ZONE_NAME)
    local z6 = getZone(CONV6_ZONE_NAME)

    for _, pname in ipairs(PLAYERS) do
        local u = getUnit(pname)
        if u then
            local p = u:getPoint()

            if z3 and (not zoneOnce[pname].conv3) and pointInZone(p, z3) then
                zoneOnce[pname].conv3 = true
                if pname == "Player_01" then setFlagON(FLAG_CONV3_P1) end
                if pname == "Player_02" then setFlagON(FLAG_CONV3_P2) end
            end

            if z6 and (not zoneOnce[pname].conv6) and pointInZone(p, z6) then
                zoneOnce[pname].conv6 = true
                if pname == "Player_01" then setFlagON(FLAG_CONV6_P1) end
                if pname == "Player_02" then setFlagON(FLAG_CONV6_P2) end
            end
        end
    end
end

----------------------------------------------------------------
-- REFUEL FLAGS (Fuel increase inside Tanker_1_Safe_Zone)
----------------------------------------------------------------
local refuelState = {
    ["Player_01"] = { lastFuel = nil, done = false },
    ["Player_02"] = { lastFuel = nil, done = false },
}

local function updateRefuelFlags()
    local rz = getZone(REFUEL_ZONE_NAME)
    if not rz then return end

    for _, pname in ipairs(PLAYERS) do
        if not refuelState[pname].done then
            local u = getUnit(pname)
            if u then
                local p = u:getPoint()
                local inside = pointInZone(p, rz)

                -- DCS fuel is returned as a fraction of total fuel capacity
                -- via Unit:getFuel(), from 0.0 to 1.0.
                local fuel = u:getFuel()

                if inside then
                    if refuelState[pname].lastFuel ~= nil then
                        local delta = fuel - refuelState[pname].lastFuel

                        -- We only care about actual increase (refuel)
                        if delta >= (REFUEL_MIN_FUEL_DELTA / 100.0) then
                            refuelState[pname].done = true

                            if pname == "Player_01" then setFlagON(FLAG_REFUEL_P1) end
                            if pname == "Player_02" then setFlagON(FLAG_REFUEL_P2) end
                        end
                    end
                end

                refuelState[pname].lastFuel = fuel
            end
        end
    end
end

----------------------------------------------------------------
-- TARGET DEAD FLAGS
----------------------------------------------------------------
local deadDone = {
    ["STRIKE1_TRG1"] = false,
    ["STRIKE1_TRG2"] = false,
}

local function updateDeadStatics()
    if not deadDone["STRIKE1_TRG1"] then
        local s1 = getStatic("STRIKE1_TRG1")
        -- Static dead check: if object no longer exists OR life <= 0
        if (not s1) or (s1.getLife and s1:getLife() <= 0) then
            deadDone["STRIKE1_TRG1"] = true
            setFlagON(FLAG_TRG1_DEAD)
        end
    end

    if not deadDone["STRIKE1_TRG2"] then
        local s2 = getStatic("STRIKE1_TRG2")
        if (not s2) or (s2.getLife and s2:getLife() <= 0) then
            deadDone["STRIKE1_TRG2"] = true
            setFlagON(FLAG_TRG2_DEAD)
        end
    end
end

----------------------------------------------------------------
-- LANDING FLAGS (Carrier landing)
----------------------------------------------------------------
local landedOnce = {
    ["Player_01"] = false,
    ["Player_02"] = false,
}

local FlagEventHandler = {}
function FlagEventHandler:onEvent(e)
    if not e or not e.id then return end

    -- Landing: S_EVENT_LAND
    if e.id == world.event.S_EVENT_LAND and e.initiator then
        local u = e.initiator
        if not u or not u.getName then return end
        local uname = u:getName()

        if uname == "Player_01" and not landedOnce["Player_01"] then
            landedOnce["Player_01"] = true
            setFlagON(FLAG_LAND_P1)
        elseif uname == "Player_02" and not landedOnce["Player_02"] then
            landedOnce["Player_02"] = true
            setFlagON(FLAG_LAND_P2)
        end
    end
end

world.addEventHandler(FlagEventHandler)

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
local function mainLoop()
    updateConversationZones()
    updateRefuelFlags()
    updateDeadStatics()

    return timer.getTime() + REFUEL_POLL_RATE_SEC
end

timer.scheduleFunction(mainLoop, nil, timer.getTime() + 1)

env.info("Flaggers v1: flag script running")   -- P1: dcs.log only
