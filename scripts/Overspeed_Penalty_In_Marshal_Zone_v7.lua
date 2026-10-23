-- Overspeed_Penalty_In_Marshal_Zone | v7.3.0
-- v7.3.0: no warning / penalty once the pilot is cleared into the visual pattern:
--   CV_Comms phase ZIPLIP (after "see you at 10") or any later recovery phase
--   (FINAL .. GROOVE, bolter pattern). CV_Comms IDLE (no CV comms used) or not loaded:
--   none inside EXEMPT_NM of
--   the carrier (350 kt to the initial is standard CASE I/II). "(Ground Speed)"
--   dropped from the warning: the check is the 3D velocity vector (incl. climb/descent, wind-affected).
-- v7.2.0: messages no longer clear the screen (clearView false) and are throttled:
--   one message at the first penalty, then a summary every MSG_EVERY s, and a
--   closing summary when the speed is back below the limit. Scoring unchanged
--   (-1 every PENALTY_INTERVAL s after WARNING_DELAY). Every 5 s clearing message
--   was wiping CV_Comms / Comms_Director radio subtitles.
-- v7.1.0: player unit read from _G.TRT.PLAYER_NAME (default "Player_01");
-- hardcoded GROUP_NAME "CAS-1" removed - messages go to unit:getGroup().

local SPEED_THRESHOLD_MS = 355 * 0.514444
local WARNING_DELAY      = 20
local PENALTY_INTERVAL   = 5
local MSG_EVERY          = 30   -- s between penalty summaries (v7.2.0)
local PENALTY_FLAG       = 1908
local PLAYER_UNIT_NAME   = (_G.TRT and _G.TRT.PLAYER_NAME) or "Player_01"
local TRIGGER_ZONE_NAME  = "Marshal_Zone"
local ALTITUDE_FLOOR_M   = 366  -- 1200 ft MSL (~AGL), altında script devre dışı
local CARRIER_UNIT_NAME  = "CVN"
local EXEMPT_NM          = 10   -- v7.3.0: fallback when CV_Comms is not loaded
local EXEMPT_PHASES = {         -- v7.3.0: CV_Comms phases in the visual / final pattern
    ZIPLIP = true, FINAL = true, NEEDLES = true, BALLWAIT = true, BALL = true, GROOVE = true,
    B_UPWIND = true, B_DOWNWIND = true, B_ABEAM = true,
}

local function isExempt(unit)
    local cv = _G.TRT and _G.TRT.CV
    if cv and cv.phase then
        if EXEMPT_PHASES[cv.phase] then return true end
        if cv.phase ~= "IDLE" then return false end     -- Marshal / Approach control: rule applies
    end
    local c = Unit.getByName(CARRIER_UNIT_NAME)
    if not c or not c:isExist() then return false end
    local a, b = unit:getPoint(), c:getPoint()
    return math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2) / 1852 <= EXEMPT_NM
end

local warningShown    = false
local warningTime     = nil
local lastPenaltyTime = nil
local runPenalties    = 0     -- penalties in the current violation (v7.2.0)
local lastMsgTime     = nil

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
    trigger.action.outTextForGroup(grp:getID(), msg, duration, false)
end

local function closeRun(unit)
    if runPenalties > 0 and unit and unit:isExist() then
        local grp = unit:getGroup()
        if grp then
            sendGroupMessage(grp, string.format(
                "Speed violation ended: %d penalt%s (-%d). Total Score: %d",
                runPenalties, runPenalties == 1 and "y" or "ies", runPenalties,
                trigger.misc.getUserFlag(PENALTY_FLAG)), 10)
        end
    end
    runPenalties, lastMsgTime = 0, nil
end

local function checkMarshalSpeed()
    local unit = Unit.getByName(PLAYER_UNIT_NAME)
    local now  = timer.getTime()

    local altitude = unit and unit:isExist() and unit:getPoint().y or nil

    if not unit or not unit:isExist()
        or not isUnitInZone(unit, TRIGGER_ZONE_NAME)
        or altitude < ALTITUDE_FLOOR_M
        or isExempt(unit) then
        closeRun(unit)
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
                        "WARNING: Do not exceed 350 knots within the Marshal Zone!\n" ..
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
                    runPenalties = runPenalties + 1
                    local grp = unit:getGroup()
                    if grp and (not lastMsgTime or (now - lastMsgTime) >= MSG_EVERY) then
                        sendGroupMessage(grp, string.format(
                            "PENALTY: Speed violation in Marshal Zone! %d so far (-%d). Total Score: %d",
                            runPenalties, runPenalties, newVal), 8)
                        lastMsgTime = now
                    end
                    lastPenaltyTime = now
                end
            end
        else
            closeRun(unit)
            warningShown    = false
            warningTime     = nil
            lastPenaltyTime = nil
        end
    end

    return now + 1
end

timer.scheduleFunction(checkMarshalSpeed, nil, timer.getTime() + 5)