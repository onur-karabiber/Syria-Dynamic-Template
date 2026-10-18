-- DEBUG: script load check
trigger.action.outText("CASE I/II departure rules activated", 5)

----------------------------------------------------------------
-- TRT DEPARTURE MODULE (STANDALONE)
-- Purpose: Score carrier departure independent of CASE recovery mode
-- Arms on TAKEOFF (or BIRTH near carrier) and scores at 7 NM
----------------------------------------------------------------

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local PLAYER_NAME = "Player_01"
local CARRIER     = "CVN"
local FLAG        = 1908
local BRC         = 355

-- Arming: spawn/takeoff near carrier threshold
local ARM_DIST_NM = 0.25

----------------------------------------------------------------
-- SCORE (shares same FLAG with main script)
----------------------------------------------------------------
local function addScore(delta, reason)
    local cur = trigger.misc.getUserFlag(FLAG) or 0
    local new = cur + delta
    trigger.action.setUserFlag(FLAG, new)

    local sign = delta >= 0 and "(+"..delta..")" or "("..delta..")"
    local txt  = reason .. " " .. sign .. " [Total: "..new.."]"

    trigger.action.outTextForCoalition(coalition.side.BLUE, txt, 8, false)
end

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function altFt(u)
    return (u:getPoint().y or 0) * 3.28084
end

local function spdKts(u)
    local v = u:getVelocity()
    return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) * 1.94384
end

local function distToCarrierNm(u, c)
    if not u or not c then return nil end
    local pu, pc = u:getPoint(), c:getPoint()
    local dx = pu.x - pc.x
    local dz = pu.z - pc.z
    return math.sqrt(dx*dx + dz*dz) / 1852
end

local function getHeading(u)
    local pos = u:getPosition()
    if not pos or not pos.x then return 0 end
    local x = pos.x
    local hdg = math.deg(math.atan2(x.z, x.x))
    if hdg < 0 then hdg = hdg + 360 end
    return hdg
end

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
local DEP = {
    active = false,
    good   = false,
    bad    = false,
    done   = false
}

local function isPlayer(u)
    return u and u:isExist() and u.getName and (u:getName() == PLAYER_NAME)
end

local function nearCarrier(u)
    local c = Unit.getByName(CARRIER)
    if not c or not c:isExist() then return false end
    local d = distToCarrierNm(u, c)
    return d and d <= ARM_DIST_NM
end

local function armDeparture()
    DEP.active = true
    DEP.good   = false
    DEP.bad    = false
    DEP.done   = false
end

----------------------------------------------------------------
-- UPDATE LOOP
----------------------------------------------------------------
local function updateDeparture()
    if DEP.done or not DEP.active then return end

    local u = Unit.getByName(PLAYER_NAME)
    local c = Unit.getByName(CARRIER)
    if not u or not u:isExist() or not c or not c:isExist() then return end

    local dist = distToCarrierNm(u, c)
    if not dist then return end

    if dist < 1.2 then return end

    if dist >= 7 then
        if DEP.good and not DEP.bad then
            addScore(5, "Departure: Within parameters")
        else
            addScore(-5, "Departure: Out of parameters")
        end
        DEP.done = true
        return
    end

    local alt = altFt(u)
    local spd = spdKts(u)
    local hdg = getHeading(u)

    local hdgDiff = math.abs(hdg - BRC)
    if hdgDiff > 180 then hdgDiff = 360 - hdgDiff end

    local altOK = (alt >= 400 and alt <= 650)
    local spdOK = (spd >= 285 and spd <= 330)
    local hdgOK = (hdgDiff <= 12)

    if altOK and spdOK and hdgOK then
        DEP.good = true
    else
        DEP.bad = true
    end
end

timer.scheduleFunction(function()
    updateDeparture()
    return timer.getTime() + 1
end, nil, timer.getTime() + 1)

----------------------------------------------------------------
-- EVENT ARMING
----------------------------------------------------------------
do
    local DEPART_EH = {}

    function DEPART_EH:onEvent(e)
        if not e or not e.initiator or not e.initiator.getName then return end
        local u = e.initiator
        if not isPlayer(u) then return end

        if e.id == world.event.S_EVENT_TAKEOFF then
            if nearCarrier(u) then armDeparture() end
            return
        end

        if e.id == world.event.S_EVENT_BIRTH then
            if nearCarrier(u) then armDeparture() end
            return
        end
    end

    world.addEventHandler(DEPART_EH)
end
