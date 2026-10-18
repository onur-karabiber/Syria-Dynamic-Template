-- DEBUG: script load check
trigger.action.outText("CASE I v14 script loaded", 5)

----------------------------------------------------------------
-- TRT SYRIA RECOVERY FRAMEWORK
-- CASE I (Single Script) v14
-- Author: Sen (inat), ben (temizlikçi)
----------------------------------------------------------------

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local PLAYER_NAME   = "Player_01"
local PLAYER        = "Player_01"
local CARRIER       = "CVN"
local FLAG          = 1908
local BRC           = 355

-- Zones (Mission Editor'da AYNEN bu isimlerle olmalı)
local ZONE_10NM             = "10NM_Zone"

BANKLER_MERGED = false

----------------------------------------------------------------
-- CASE PROFILE SELECTOR (ONLY ONE TRUE)
----------------------------------------------------------------
local CASE_I_ENABLED   = true
local CASE_II_ENABLED  = false
local CASE_III_ENABLED = false

do
    local n = 0
    if CASE_I_ENABLED then n = n + 1 end
    if CASE_II_ENABLED then n = n + 1 end
    if CASE_III_ENABLED then n = n + 1 end
    assert(n == 1, "ERROR: Only ONE CASE mode must be enabled!")
end

----------------------------------------------------------------
-- SCORE (SINGLE SOURCE OF TRUTH)
----------------------------------------------------------------
local function addScore(delta, reason)
    local cur = trigger.misc.getUserFlag(FLAG) or 0
    local new = cur + delta
    trigger.action.setUserFlag(FLAG, new)

    local sign = delta >= 0 and "(+"..delta..")" or "("..delta..")"
    local txt  = reason .. " " .. sign .. " [Total: "..new.."]"

    trigger.action.outTextForCoalition(
        coalition.side.BLUE,
        txt,
        8,
        false
    )
end


----------------------------------------------------------------
-- DEAD SCORING TABLE (FULL)
----------------------------------------------------------------
-- Not: STRIKE flag'leri (.miz) tarafında boş birer flag ID seçip buraya gir.
-- Mevcut senaryoda tanımlı değilse default verdim; çakışma varsa değiştir.
local FLAG_TRG1_DEAD = rawget(_G, "FLAG_TRG1_DEAD") or 1911
local FLAG_TRG2_DEAD = rawget(_G, "FLAG_TRG2_DEAD") or 1912

local DEAD_SCORES = {

    ["SAM 15 (8-13-15-19)-1"] = 10,
    ["SAM 15 (8-13-15-19)-2"] = 9,
    ["SAM 15 (8-13-15-19)-3"] = 8,
    ["SAM 15 (8-13-15-19)-4"] = 7,
    ["SAM 7 (13)-1"] = 5,
    ["SAM 7 (13)-2"] = 7,

    ["POPUP_TARGET1"] = 9, ["STRIKE1_TRG2"]  = 9,
    ["AKROTIRI_Chemical_Factory"] = 10, ["STRIKE1_TRG1"] = 10,

    ["TANKER-1-1"] = -8, ["TANKER-2-1"] = -8, ["TANKER-3-1"] = -8, ["TANKER-4-1"] = -8,
    ["ARCO-5-1"]   = -8, ["TANKER-6-1"] = -8,

    ["MAGIC-2-1"]    = -10,
    ["OVERLORD-1-1"] = -10,
}

do
    local deadHandled = {}
    local DEH = {}

    local function setFlagON(flagId)
        if not flagId then return end
        trigger.action.setUserFlag(flagId, 1)
    end

    function DEH:onEvent(e)
        if not e or e.id ~= world.event.S_EVENT_DEAD then return end
        local tgt = e.initiator
        if not tgt or not tgt.getName then return end

        local unitName = tgt:getName()
        if not unitName or deadHandled[unitName] then return end

        local delta = DEAD_SCORES[unitName]

        -- Prefix fallback
        if not delta then
            for key, val in pairs(DEAD_SCORES) do
                if string.find(unitName, key, 1, true) == 1 then
                    delta = val
                    break
                end
            end
        end
        if not delta then return end

        deadHandled[unitName] = true

        -- SPECIAL FLAGS: strike targets
        if unitName == "STRIKE1_TRG1" then
            setFlagON(FLAG_TRG1_DEAD)
        elseif unitName == "STRIKE1_TRG2" then
            setFlagON(FLAG_TRG2_DEAD)
        end

        addScore(delta, "TARGET DESTROYED: " .. unitName)
    end

    world.addEventHandler(DEH)
end


----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function uPlayer()
    return Unit.getByName(PLAYER_NAME)
end

local function altFt(u)
    if not u or not u:isExist() then return 0 end
    return (u:getPoint().y or 0) * 3.28084
end

local function spdKts(u)
    if not u or not u:isExist() then return 0 end
    local v = u:getVelocity()
    return math.sqrt(v.x*v.x + v.y*v.y + v.z*v.z) * 1.94384
end

local function inZone(u, zn)
    if not u or not u:isExist() then return false end
    local Z = trigger.misc.getZone(zn)
    if not Z then return false end
    local p = u:getPoint()
    local dx = p.x - Z.point.x
    local dz = p.z - Z.point.z
    return math.sqrt(dx*dx + dz*dz) <= Z.radius
end

local function distToCarrierNm(u, c)
    if not u or not c or not u:isExist() or not c:isExist() then return nil end
    local pu, pc = u:getPoint(), c:getPoint()
    local dx = pu.x - pc.x
    local dz = pu.z - pc.z
    return math.sqrt(dx*dx + dz*dz) / 1852
end

local function getHeading(u)
    local pos = u:getPosition()
    if not pos or not pos.x then return 0 end
    local hdg = math.deg(math.atan2(pos.x.z, pos.x.x))
    if hdg < 0 then hdg = hdg + 360 end
    return hdg
end

----------------------------------------------------------------
-- GROOVE FUEL SCORING
----------------------------------------------------------------
do
    local grooveDone={}
    function _G.TRT_UpdateGrooveFuel(u)
        local c=Unit.getByName(CARRIER)
        if not u or not c or grooveDone[u:getName()] then return end
        if distToCarrierNm(u,c)>1.6 then return end
        local alt,spd=altFt(u),spdKts(u)
        if alt<50 or alt>900 or spd<105 or spd>240 then return end

        local lbs=u:getFuel()*11000
        if lbs<1500 then addScore(-8,"Fuel emergency")
        elseif lbs<2000 then addScore(-5,"Fuel low")
        elseif lbs>=2500 and lbs<=3500 then addScore(5,"Fuel OK")
        end
        grooveDone[u:getName()]=true
    end

    local GEH={}
    function GEH:onEvent(e)
        if e and e.id==world.event.S_EVENT_TAKEOFF and e.initiator then
            grooveDone[e.initiator:getName()]=nil
        end
    end
    world.addEventHandler(GEH)
end

----------------------------------------------------------------
-- REFUEL SCORING (PLAYER + AI)
----------------------------------------------------------------
local REFUEL_UNITS={}
local lastFuel,baseline,rewarded={},{},{}

local PLAYER_REFUEL_ZONES={
    "TANKER_1_SAFE_ZONE",
    "TANKER_2_SAFE_ZONE",
    "TANKER_3_SAFE_ZONE"
}

local playerRefuel={inZone=false,baseline=nil,done=false}

timer.scheduleFunction(function()
    local groups=coalition.getGroups(coalition.side.BLUE,Group.Category.AIRPLANE) or {}
    for _,g in ipairs(groups) do
        for _,u in ipairs(g:getUnits() or {}) do
            if u and u:isExist() then REFUEL_UNITS[u:getName()]=true end
        end
    end
    return timer.getTime()+10
end,nil,timer.getTime()+1)

local function inAnyRefuelZone(u)
    for _,z in ipairs(PLAYER_REFUEL_ZONES) do
        if inZone(u,z) then return true end
    end
    return false
end

timer.scheduleFunction(function()
    local u=Unit.getByName(PLAYER_NAME)
    if u and not playerRefuel.done then
        local f=u:getFuel()
        local inside=inAnyRefuelZone(u)
        if inside and not playerRefuel.inZone then
            playerRefuel.inZone=true; playerRefuel.baseline=f
        elseif not inside and playerRefuel.inZone then
            playerRefuel.inZone=false; playerRefuel.baseline=nil
        elseif inside and playerRefuel.baseline and f-playerRefuel.baseline>=0.2 then
            playerRefuel.done=true
            addScore(7,"Aerial Refuel Complete: "..PLAYER_NAME)
        end
    end

    for name in pairs(REFUEL_UNITS) do
        if name~=PLAYER_NAME then
            local u=Unit.getByName(name)
            if u and u:isExist() then
                local f=u:getFuel()
                if lastFuel[name]==nil then
                    lastFuel[name]=f; baseline[name]=nil; rewarded[name]=false
                else
                    local df=f-lastFuel[name]
                    if df< -0.005 then baseline[name]=nil; rewarded[name]=false end
                    if df>0 and not baseline[name] then baseline[name]=lastFuel[name] end
                    if baseline[name] and not rewarded[name] and f-baseline[name]>=0.03 then
                        rewarded[name]=true
                        addScore(7,"Aerial Refuel Complete: "..name)
                    end
                    lastFuel[name]=f
                end
            end
        end
    end
    return timer.getTime()+1
end,nil,timer.getTime()+1)

----------------------------------------------------------------
-- CASE I 10NM (ZONE-BASED, SCORES ON RETURN ONLY)
-- Player kalkışta zone içinde olsa bile tetiklenmez.
-- Önce zone'dan çıkması (göreve gitmesi) gerekir;
-- dönüşte zone'a ilk girişte tek seferlik değerlendirilir.
----------------------------------------------------------------
local CASE1 = { done=false, wasIn=false, hasLeft=false }

local function updateCASEI(u)
    if CASE1.done then return end

    local inside = inZone(u, ZONE_10NM)

    -- Player bir kez zone dışına çıktığında bunu kaydet
    if not inside then
        CASE1.hasLeft = true
    end

    -- Dışarıdan içeri "giriş anı"nda VE daha önce dışarı çıkmışsa tetikle
    if inside and not CASE1.wasIn and CASE1.hasLeft then
        local alt, spd = altFt(u), spdKts(u)
        if alt>=1900 and alt<=2150 and spd>=275 and spd<=320 then
            addScore(5,"CASE I 10NM OK")
        else
            addScore(-5,"CASE I 10NM BAD")
        end
        CASE1.done = true
    end

    CASE1.wasIn = inside
end

----------------------------------------------------------------
-- LANDING SCORING MODULE (CARRIER + LAND BASE)
----------------------------------------------------------------

local TARGET_UNITS = {
    ["LANDER-8-1"]  = true,
    ["LANDER-6-1"]  = true,
    ["CAS-1-1"]     = true,
    ["TOMCAT-2-1"]  = true,
    ["TOMCAT-1-1"]  = true,
    ["Player_01"]   = true
}

-- One-time scoring per unit (either carrier or land base)
local LANDING_DONE = {}

local LEH = {}

function LEH:onEvent(e)
    -- Guard rails
    if not e or e.id ~= world.event.S_EVENT_LAND or not e.initiator then return end

    local unit = e.initiator
    local n = unit:getName()
    if not TARGET_UNITS[n] then return end
    if LANDING_DONE[n] then return end

    -- 1) Carrier landing check (specific carrier only)
    local carrier = Unit.getByName(CARRIER)
    if carrier then
        local d = distToCarrierNm(unit, carrier)
        if d and d <= 0.05 then
            LANDING_DONE[n] = true
            addScore(5, "Successful carrier landing")
            return
        end
    end

    -- 2) Land-base landing check (airport / FARPs count as BASE)
    -- e.place is the object you landed on/at (often an airbase or ship)
    local place = e.place
    if place and place.getCategory then
        local cat = place:getCategory()
        if cat == Object.Category.BASE then
            LANDING_DONE[n] = true
            addScore(2, "Successful land-based landing")
            return
        end
    end

    -- Otherwise: no score (you "landed" somewhere that's not a base and not near the carrier)
end

world.addEventHandler(LEH)

----------------------------------------------------------------
-- BANKLER MERGE
----------------------------------------------------------------
local function mergeBankler()
    if BANKLER_MERGED or not traptrainer or not traptrainer.PlayerData then
        return timer.getTime()+5
    end
    local b=traptrainer.PlayerData.score or 0
    if b>0 then
        local cur=trigger.misc.getUserFlag(FLAG) or 0
        trigger.misc.setUserFlag(FLAG,cur+b)
        trigger.action.outTextForCoalition(
            coalition.side.BLUE,
            "Bankler merged (+"..b..")",10,false)
        BANKLER_MERGED=true
    end
end
timer.scheduleFunction(mergeBankler,nil,timer.getTime()+30)

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
local function mainLoop()
    local u=uPlayer()
    if not u then return timer.getTime()+1 end
    local now=timer.getTime()

    TRT_UpdateGrooveFuel(u)
    updateCASEI(u)

    return now+1
end
timer.scheduleFunction(mainLoop,nil,timer.getTime()+1)
