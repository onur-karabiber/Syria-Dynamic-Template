-- Overspeed_Penalty_In_Marshal_Zone | v7.1.0
-- v7.1.0: player unit read from _G.TRT.PLAYER_NAME (default "Player_01");
-- hardcoded GROUP_NAME "CAS-1" removed - messages go to unit:getGroup().

local SPEED_THRESHOLD_MS = 355 * 0.514444
local WARNING_DELAY      = 20
local PENALTY_INTERVAL   = 5
local PENALTY_FLAG       = 1908
local PLAYER_UNIT_NAME   = (_G.TRT and _G.TRT.PLAYER_NAME) or "Player_01"
local TRIGGER_ZONE_NAME  = "Marshal_Zone"
local ALTITUDE_FLOOR_M   = 366  -- 1200 ft MSL (~AGL), altında script devre dışı

local warningShown    = false
local warningTime     = nil
local lastPenaltyTime = nil

local function getUnitSpeed(unit)
    local vel = unit:getVelocity()
    return math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
end

local function isUnitInZone(unit, zoneName)
    local zone = trigger.misc.getZone(zoneName)
    if not zone or not unit or not unit:isExist() then return false end
    local uPos = unit:getPoint()
    local dx   = uPos.x - zone.point.x
    local dz   = uPos.z - zone.point.z
    return (dx * dx + dz * dz) <= (zone.radius * zone.radius)
end

local function sendGroupMessage(grp, msg, duration)
    trigger.action.outTextForGroup(grp:getID(), msg, duration, true)
end

local function checkMarshalSpeed()
    local unit = Unit.getByName(PLAYER_UNIT_NAME)
    local now  = timer.getTime()

    local altitude = unit and unit:isExist() and unit:getPoint().y or nil

    if not unit or not unit:isExist()
        or not isUnitInZone(unit, TRIGGER_ZONE_NAME)
        or altitude < ALTITUDE_FLOOR_M then
        warningShown    = false
        warningTime     = nil
        lastPenaltyTime = nil
    else
        local speed = getUnitSpeed(unit)

        if speed > SPEED_THRESHOLD_MS then
            if not warningShown then
                local grp = unit:getGroup()
                if grp then
                    sendGroupMessage(grp,
                        "WARNING: Do not exceed 350 knots (Ground Speed) within the Marshal Zone!\n" ..
                        "Otherwise, you will start receiving penalty points shortly.",
                        15)
                end
                warningShown    = true
                warningTime     = now
                lastPenaltyTime = now
            end

            if warningTime and (now - warningTime) >= WARNING_DELAY then
                if lastPenaltyTime and (now - lastPenaltyTime) >= PENALTY_INTERVAL then
                    local currentVal = trigger.misc.getUserFlag(PENALTY_FLAG)
                    local newVal     = currentVal - 1
                    trigger.action.setUserFlag(PENALTY_FLAG, newVal)
                    local grp = unit:getGroup()
                    if grp then
                        sendGroupMessage(grp,
                            "PENALTY (-1 point): Speed violation in Marshal Zone!\n" ..
                            "Total Score: " .. newVal,
                            8)
                    end
                    lastPenaltyTime = now
                end
            end
        else
            warningShown    = false
            warningTime     = nil
            lastPenaltyTime = nil
        end
    end

    return now + 1
end

timer.scheduleFunction(checkMarshalSpeed, nil, timer.getTime() + 5)