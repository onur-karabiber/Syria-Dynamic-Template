-- DEBUG: script load check
trigger.action.outText("CASE II v14 script loaded", 5)

----------------------------------------------------------------
-- TRT SYRIA RECOVERY FRAMEWORK
-- CASE I / CASE II / CASE III (Single Script)
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

-- Zones
local IF_ZONE       = "InitialFix_Zone"
local HOLD_ZONE     = "Holding_Zone"
local ZONE_12NM_CASE2 = "12NMa_Zone"
local ZONE_12NM_CASE3 = "12NMb_Zone"
local ZONE_10NM     = "10NM_Zone"
BANKLER_MERGED = false

-- Commence fuel check (CASE II / CASE III)
local COMMENCE_MIN_FUEL_LBS = 3000
----------------------------------------------------------------
-- CASE PROFILE SELECTOR (ONLY ONE TRUE)
----------------------------------------------------------------
local CASE_I_ENABLED   = false
local CASE_II_ENABLED  = true
local CASE_III_ENABLED = false

do
    local n = 0
    if CASE_I_ENABLED then n = n + 1 end
    if CASE_II_ENABLED then n = n + 1 end
    if CASE_III_ENABLED then n = n + 1 end
    assert(n == 1, "ERROR: Only ONE CASE mode must be enabled!")
end

----------------------------------------------------------------
-- GLOBAL STATE
----------------------------------------------------------------
RECOVERY_ACTIVE = false
CASE_PHASE = "NONE"

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
-- UTILS
----------------------------------------------------------------
local function uPlayer()
    return Unit.getByName(PLAYER_NAME)
end

local function altFt(u)
    return (u:getPoint().y or 0) * 3.28084
end

local function spdKts(u)
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
    if not u or not c then return nil end
    local pu, pc = u:getPoint(), c:getPoint()
    local dx = pu.x - pc.x
    local dz = pu.z - pc.z
    return math.sqrt(dx*dx + dz*dz) / 1852
end

-- Fuel fraction (0..1) -> lbs (used for Commence Fuel Check)
local function commenceFuelLbs(u)
    if not u or not u:isExist() then return nil end

    local frac = u:getFuel()
    if not frac then return nil end

    local maxKg
    local ok, desc = pcall(function() return u:getDesc() end)
    if ok and desc and desc.fuelMassMax then
        maxKg = desc.fuelMassMax
    end

    -- Fallback: Hornet internal fuel ~10–11k lbs
    if not maxKg then
        return frac * 11000
    end

    local maxLbs = maxKg * 2.2046226218
    return frac * maxLbs
end

----------------------------------------------------------------
-- HARD DECK (PLAYER-ONLY, MULTI-ZONE, ESCALATING PENALTY)
-- FIXED: hd state + takeoff reset handler are in the SAME scope (no nil hd)
----------------------------------------------------------------
do
    -- CONFIG
    local HARD_DECK_ENABLED       = true

    -- Tek zone yerine liste
    local HARD_DECK_ZONES = {
        "SA15_1",
        "SA15_2",
        "SA8_1",
        "SA8_2",
        "SA8_3",
        "SA8_4",
        "ENGAGEMENT_ZONE"
    }

    local HARD_DECK_MIN_FT        = 21000

    local HARD_DECK_GRACE_SEC     = 3        -- initial warning delay
    local HARD_DECK_PENALTY_DELAY = 30       -- penalty starts after warning
    local HARD_DECK_PENALTY_TICK  = 3        -- -1 point interval

    -- STATE (must stay in this block)
    local hd = {
        belowSince   = nil,
        lastWarn     = 0,
        lastPenalty  = 0
    }

    local function resetHD()
        hd.belowSince  = nil
        hd.lastWarn    = 0
        hd.lastPenalty = 0
    end

    -- helper: inside any zone?
    local function inAnyHardDeckZone(u)
        for _, zname in ipairs(HARD_DECK_ZONES) do
            if inZone(u, zname) then
                return true
            end
        end
        return false
    end

    function _G.TRT_UpdateHardDeck(u, now)
        if not HARD_DECK_ENABLED then return end
        if not u or not u:isExist() then return end
        if not now then now = timer.getTime() end

        -- Outside all zones -> hard reset
        if not inAnyHardDeckZone(u) then
            resetHD()
            return
        end

        local alt = altFt(u)

        -- Above hard deck -> reset
        if alt >= HARD_DECK_MIN_FT then
            resetHD()
            return
        end

        -- First descent below hard deck
        if not hd.belowSince then
            hd.belowSince = now
            return
        end

        local elapsed = now - hd.belowSince

        --------------------------------------------------------
        -- WARNING (after GRACE, throttled)
        --------------------------------------------------------
        if elapsed >= HARD_DECK_GRACE_SEC then
            if now - hd.lastWarn >= 3 then
                trigger.action.outTextForCoalition(
                    coalition.side.BLUE,
                    string.format(
                        "HARD DECK VIOLATION! Maintain above %.0f feet MSL!",
                        HARD_DECK_MIN_FT
                    ),
                    3,
                    false
                )
                hd.lastWarn = now
            end
        end

        --------------------------------------------------------
        -- PENALTY (after GRACE + DELAY, every TICK)
        --------------------------------------------------------
        if elapsed >= (HARD_DECK_GRACE_SEC + HARD_DECK_PENALTY_DELAY) then
            if now - hd.lastPenalty >= HARD_DECK_PENALTY_TICK then
                addScore(
                    -1,
                    "Below hard deck inside threat area (-1 penalty point)"
                )
                hd.lastPenalty = now
            end
        end
    end

    ----------------------------------------------------------------
    -- Reset on takeoff (new sortie) - FIXED SCOPE
    ----------------------------------------------------------------
    local HDEH = {}
    function HDEH:onEvent(e)
        if not e or e.id ~= world.event.S_EVENT_TAKEOFF then return end
        if not e.initiator or not e.initiator.getName then return end
        if e.initiator:getName() ~= PLAYER_NAME then return end
        resetHD()
    end
    world.addEventHandler(HDEH)
end

----------------------------------------------------------------
-- GROOVE FUEL SCORING (ONE-SHOT, LBS-BASED)
----------------------------------------------------------------
do
    -- CONFIG
    local GROOVE_ENABLED        = true

    -- "Groove" yaklaşımını yakalamak için pratik kapı:
    -- Carrier'a yakın + düşük irtifa + yaklaşım hızı bandı
    local GROOVE_DIST_NM        = 1.6      -- ~1.3-1.6nm güvenli
    local GROOVE_ALT_MIN_FT     = 50
    local GROOVE_ALT_MAX_FT     = 900
    local GROOVE_SPD_MIN_KTS    = 105
    local GROOVE_SPD_MAX_KTS    = 240

    -- FUEL RULES (lbs)
    local FUEL_EMERGENCY_LBS    = 1500     -- <1500 => -8
    local FUEL_LOW_LBS          = 2000     -- <2000 => -5
    local FUEL_GOOD_MIN_LBS     = 2500     -- 2500-3500 => +5
    local FUEL_GOOD_MAX_LBS     = 3500

    local SCORE_EMERGENCY       = -8
    local SCORE_LOW             = -5
    local SCORE_GOOD            =  5

    -- Per-unit one-shot gate
    local grooveDone = {}

    local function distNm(u, c)
        local pu, pc = u:getPoint(), c:getPoint()
        local dx = pu.x - pc.x
        local dz = pu.z - pc.z
        return math.sqrt(dx*dx + dz*dz) / 1852
    end

    -- Fuel fraction (0..1) -> lbs using unit desc fuelMassMax (kg)
    local function fuelLbs(u)
        local frac = u:getFuel()
        if not frac then return nil end

        local maxKg
        local ok, desc = pcall(function() return u:getDesc() end)
        if ok and desc and desc.fuelMassMax then
            maxKg = desc.fuelMassMax
        end

        -- Fallback: Hornet internal fuel ~10-11k lbs bandı
        -- (desc gelmezse gerçekçilik yerine çalışırlık)
        if not maxKg then
            local fallbackMaxLbs = 11000
            return frac * fallbackMaxLbs
        end

        local maxLbs = maxKg * 2.2046226218
        return frac * maxLbs
    end

    local function isInGrooveGate(u, c)
        if not u or not u:isExist() or not c or not c:isExist() then return false end

        local d = distNm(u, c)
        if d > GROOVE_DIST_NM then return false end

        local alt = altFt(u)
        if alt < GROOVE_ALT_MIN_FT or alt > GROOVE_ALT_MAX_FT then return false end

        local spd = spdKts(u)
        if spd < GROOVE_SPD_MIN_KTS or spd > GROOVE_SPD_MAX_KTS then return false end

        return true
    end

    -- Call this from main loop
    function _G.TRT_UpdateGrooveFuel(u)
        if not GROOVE_ENABLED then return end
        if not u or not u:isExist() then return end

        local uname = u:getName()
        if not uname then return end
        if grooveDone[uname] then return end

        local c = Unit.getByName(CARRIER)
        if not c then return end

        if not isInGrooveGate(u, c) then return end

        local lbs = fuelLbs(u)
        if not lbs then return end

        -- Exclusive evaluation order (most severe first)
        local delta, msg = nil, nil

        if lbs < FUEL_EMERGENCY_LBS then
            delta = SCORE_EMERGENCY
            msg = string.format(
                "Fuel state below recovery minimum (<%d lbs): %.0f lbs",
                FUEL_EMERGENCY_LBS, lbs
            )

        elseif lbs < FUEL_LOW_LBS then
            delta = SCORE_LOW
            msg = string.format(
                "Fuel state critical for recovery (<%d lbs): %.0f lbs",
                FUEL_LOW_LBS, lbs
            )

        elseif lbs >= FUEL_GOOD_MIN_LBS and lbs <= FUEL_GOOD_MAX_LBS then
            delta = SCORE_GOOD
            msg = string.format(
                "Fuel state within recovery limits (%d–%d lbs): %.0f lbs",
                FUEL_GOOD_MIN_LBS, FUEL_GOOD_MAX_LBS, lbs
            )
        end

        -- Mark done regardless (tek tetik)
        if delta and msg then
            grooveDone[uname] = true
            addScore(delta, msg)
        end
    end

    -- Reset gate on takeoff (new sortie / new cycle)
    local GEH = {}
    function GEH:onEvent(e)
        if not e or not e.initiator then return end
        if e.id ~= world.event.S_EVENT_TAKEOFF then return end
        local u = e.initiator
        if not u or not u.getName then return end
        grooveDone[u:getName()] = nil
    end
    world.addEventHandler(GEH)
end
----------------------------------------------------------------
-- CASE II / CASE III CHART MODULE (IF + HOLD + 12NM)
----------------------------------------------------------------

-- CASE II / III shared state
local CASE2 = {
    ifDone               = false,
    commenceFuelChecked  = false,
    holdEnter = nil,
    holdDone  = false,
    nm12Done  = false,
}

----------------------------------------------------------------
-- RESET (called on recovery activation)
----------------------------------------------------------------
local function resetCASE2()
    CASE2.ifDone     = false
    CASE2.commenceFuelChecked  = false
    CASE2.holdEnter = nil
    CASE2.holdDone  = false
    CASE2.nm12Done  = false
end

----------------------------------------------------------------
-- Select correct 12NM zone by CASE
----------------------------------------------------------------
local function get12nmZoneForActiveCase()
    if CASE_II_ENABLED then
        return ZONE_12NM_CASE2
    end
    if CASE_III_ENABLED then
        return ZONE_12NM_CASE3
    end
    return nil
end

----------------------------------------------------------------
-- UPDATE LOOP
----------------------------------------------------------------
local function updateCASEII(u, now)
    if not u or not u:isExist() then return end

    ------------------------------------------------------------
    -- IF CHECK (ONE-SHOT)
    ------------------------------------------------------------
    if not CASE2.ifDone and inZone(u, IF_ZONE) then
        local alt = altFt(u)
        local spd = spdKts(u)

        if alt >= 9800 and alt <= 10200 and spd >= 260 and spd <= 330 then
            addScore(5, "Initial Fix: Within parameters")
        else
            addScore(-5, "Inintial Fix: Out of parameters")
        end

        ------------------------------------------------------------
        -- COMMENCE FUEL CHECK (AFTER IF, ONE-SHOT)
        ------------------------------------------------------------
        if not CASE2.commenceFuelChecked then
            local lbs = commenceFuelLbs(u)
            if lbs then
                if lbs < COMMENCE_MIN_FUEL_LBS then
                    trigger.action.outTextForCoalition(
                        coalition.side.BLUE,
                        string.format(
                            "Commence fuel check: MIN %d lbs, you have %.0f lbs – Proceed to tanker",
                            COMMENCE_MIN_FUEL_LBS, lbs
                        ),
                        12,
                        false
                    )
                else
                    trigger.action.outTextForCoalition(
                        coalition.side.BLUE,
                        string.format(
                            "Commence fuel check: MIN %d lbs, you have %.0f lbs",
                            COMMENCE_MIN_FUEL_LBS, lbs
                        ),
                        8,
                        false
                    )
                end
            end
            CASE2.commenceFuelChecked = true
        end

        CASE2.ifDone = true
        return
    end

    ------------------------------------------------------------
    -- HOLD CHECK (120s INSIDE HOLD ZONE AFTER IF)
    ------------------------------------------------------------
    if CASE2.ifDone and not CASE2.holdDone then
        local insideHold = inZone(u, HOLD_ZONE)

        -- first entry
        if insideHold and not CASE2.holdEnter then
            CASE2.holdEnter = now
        end

        -- timer running
        if CASE2.holdEnter then
            local dur = now - CASE2.holdEnter

            if dur >= 120 then
                addScore(5, "Holding duration correct")
                CASE2.holdDone = true
            end
        end

        return
    end

    ------------------------------------------------------------
    -- 12NM CHECK (ONLY AFTER IF + HOLD)
    ------------------------------------------------------------
    if CASE2.ifDone and CASE2.holdDone and not CASE2.nm12Done then
        local zone12 = get12nmZoneForActiveCase()
        if not zone12 then return end

        if inZone(u, zone12) then
            local alt = altFt(u)
            local spd = spdKts(u)

            local label = CASE_III_ENABLED and "CASE III" or "CASE II"

            if alt >= 1100 and alt <= 1400 and spd >= 220 and spd <= 270 then
                addScore(5, label .. " 12NM: Within parameters")
            else
                addScore(-5, label .. " 12NM: Out of parameters")
            end

            CASE2.nm12Done = true
        end
    end
end


----------------------------------------------------------------
-- RULES ACTIVATION (SINGLE-SHOT, CASE-CLEAN)
-- Recovery activates if:
-- 1) Player_01 is ≥ 60 NM from carrier
-- OR
-- 2) Player_01 is alive inside Incirlik zone
-- OR
-- 3) TOMCAT-2-1 is alive inside Incirlik zone
----------------------------------------------------------------

local function unitAliveInZone(unitName, zoneName)
    local u = Unit.getByName(unitName)
    if not u or not u:isExist() then return false end
    return inZone(u, zoneName)
end

local function checkRulesActivation()
    -- HARD GUARD: sadece bir kere çalışır
    if RECOVERY_ACTIVE then return end

    local u = Unit.getByName(PLAYER)
    local c = Unit.getByName(CARRIER)
    if not u or not c then return end

    local dist = distToCarrierNm(u, c)

    local activate =
        dist >= 60
        or unitAliveInZone("Player_01", "Incirlik_Zone")
        or unitAliveInZone("TOMCAT-2-1", "Incirlik_Zone")

    if not activate then return end

    ------------------------------------------------------------
    -- ACTIVATE RECOVERY (ONE WAY)
    ------------------------------------------------------------
    RECOVERY_ACTIVE = true

    ------------------------------------------------------------
    -- HARD RESET: CASE II / III chart state
    ------------------------------------------------------------
    if resetCASE2 then
        resetCASE2()
    end

    ------------------------------------------------------------
    -- HARD KILL: Bankler CASE III'te ASLA çalışmaz
    ------------------------------------------------------------
    if CASE_III_ENABLED then
        BANKLER_MERGED = true
    end

    ------------------------------------------------------------
    -- SET CASE PHASE (INFORMATIONAL)
    ------------------------------------------------------------
    if CASE_I_ENABLED then
        CASE_PHASE = "CASE_I"
        trigger.action.outText("Recovery Rules Activated: CASE I", 10)

    elseif CASE_II_ENABLED then
        CASE_PHASE = "CASE_II"
        trigger.action.outText("Recovery Rules Activated: CASE II", 10)

    elseif CASE_III_ENABLED then
        CASE_PHASE = "CASE_III"
        trigger.action.outText("Recovery Rules Activated: CASE III", 10)
    end
end
----------------------------------------------------------------
-- DEAD SCORING
----------------------------------------------------------------
local DEAD_SCORES = {

    -- POP-UP strike targets
    ["POPUP_TARGET1"] = 9,
    ["SAM 5 (9-13)-1"] = 5,
    ["SAM 5 (9-13)-2"] = 2,
    ["SAM 5 (9-13)-3"] = 5,
    ["SAM 5 (9-13)-4"] = 2,
    ["SAM 5 (9-13)-5"] = 2,
    ["SAM 5 (9-13)-6"] = 2,
    ["SAM 21 (13)-2"] = 1,
    ["SAM 21 (13)-1"] = 1,
    ["SAM 9 (13)-4"] = 1,
    ["SAM 9 (13)-6"] = 1,
    ["SAM 6 (8)-4"] = 2,
    ["SAM 4 (8-13)-1"] = 1,
    ["SAM 4 (8-13)-2"] = 1,
    ["SAM 4 (8-13)-3"] = 1,
    ["SAM 4 (8-13)-4"] = 1,
    ["Ground-10-7"] = 1,
    ["Ground-10-8"] = 1,
    ["Ground-10-9"] = 1,

    -- F-14 Strike mission
    ["AKROTIRI_Chemical_Factory"] = 10,

    -- for Player_01
    ["STRIKE1_TRG1"] = 10,
    ["STRIKE1_TRG2"] = 9,

    ["TANKER-1-1"] = -8,
    ["TANKER-2-1"] = -8,
    ["TANKER-3-1"] = -8,
    ["TANKER-4-1"] = -8,
    ["ARCO-5-1"] = -8,
    ["TANKER-6-1"] = -8,

    ["MAGIC-2-1"] = -10,
    ["OVERLORD-1-1"] = -10,
}

----------------------------------------------------------------
-- DEAD SCORING (UNIT-BASED, DCS-CORRECT, MERGE-SAFE)
----------------------------------------------------------------
do
    local deadHandled = {}

    local DEH = {}

    function DEH:onEvent(e)
        if not e then return end
        if e.id ~= world.event.S_EVENT_DEAD then return end

        -- DCS GERÇEĞİ: ÖLEN OBJE = initiator
        local tgt = e.initiator
        if not tgt or not tgt.getName then return end

        local unitName = tgt:getName()
        if not unitName then return end

        -- Aynı unit ikinci kez sayılmasın
        if deadHandled[unitName] then return end

        local delta = DEAD_SCORES[unitName]

        -- Prefix fallback (Ground-6-5-1 gibi saçmalıklar için)
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
        addScore(delta, "TARGET DESTROYED: "..unitName)
    end

    world.addEventHandler(DEH)
end

----------------------------------------------------------------
-- REFUEL SCORING (PLAYER ZONE-BASED + AI TREND-BASED, EVENT-INDEPENDENT)
----------------------------------------------------------------
local REFUEL_UNITS = {}
local lastFuel, baseline, rewarded = {}, {}, {}

-- Player zone refuel gate
local PLAYER_REFUEL_ZONES = {
    "TANKER_1_SAFE_ZONE",
    "TANKER_2_SAFE_ZONE",
    "TANKER_5_SAFE_ZONE"
}
local playerRefuel = {
    inZone   = false,
    baseline = nil,
    done     = false
}

timer.scheduleFunction(function()
    local groups = coalition.getGroups(coalition.side.BLUE, Group.Category.AIRPLANE) or {}
    for _, g in ipairs(groups) do
        for _, u in ipairs(g:getUnits() or {}) do
            if u and u:isExist() then
                local n = u:getName()
                if n then REFUEL_UNITS[n] = true end
            end
        end
    end
    return timer.getTime() + 10
end, nil, timer.getTime() + 1)

local function inAnyRefuelZone(u)
    for _, zn in ipairs(PLAYER_REFUEL_ZONES) do
        if inZone(u, zn) then
            return true
        end
    end
    return false
end

local function updatePlayerZoneRefuel()
    if playerRefuel.done then return end

    local u = Unit.getByName(PLAYER_NAME)
    if not u or not u:isExist() then return end

    local f = u:getFuel()
    if not f then return end

    local inside = inAnyRefuelZone(u)

    -- Zone entry -> capture baseline
    if inside and not playerRefuel.inZone then
        playerRefuel.inZone   = true
        playerRefuel.baseline = f
        return
    end

    -- Zone exit -> reset
    if not inside and playerRefuel.inZone then
        playerRefuel.inZone   = false
        playerRefuel.baseline = nil
        return
    end

    -- While inside: +20% from entry baseline -> reward (one-shot)
    if inside and playerRefuel.baseline and (f - playerRefuel.baseline) >= 0.2 then
        playerRefuel.done = true
        addScore(7, "Aerial Refuel Complete: " .. PLAYER_NAME)
    end
end

timer.scheduleFunction(function()
    -- PLAYER (zone-based, deterministic)
    updatePlayerZoneRefuel()

    -- AI (trend-based, original logic; excludes player)
    for name in pairs(REFUEL_UNITS) do
        if name ~= PLAYER_NAME then
            local u = Unit.getByName(name)
            if u and u:isExist() then
                local f = u:getFuel()
                if f then
                    if lastFuel[name] == nil then
                        lastFuel[name] = f
                        baseline[name] = nil
                        rewarded[name] = false
                    else
                        local df = f - lastFuel[name]

                        -- fuel decreasing -> reset cycle
                        if df < -0.005 then
                            baseline[name] = nil
                            rewarded[name] = false
                        end

                        -- first positive trend -> capture baseline
                        if df > 0 and not baseline[name] then
                            baseline[name] = lastFuel[name]
                        end

                        -- +3% from baseline -> reward
                        if baseline[name] and not rewarded[name] and (f - baseline[name]) >= 0.03 then
                            rewarded[name] = true
                            addScore(7, "Aerial Refuel Complete: " .. name)
                        end

                        lastFuel[name] = f
                    end
                end
            end
        end
    end
    return timer.getTime() + 1
end, nil, timer.getTime() + 1)

-- Reset on takeoff (new sortie / new cycle)
do
    local REH = {}
    function REH:onEvent(e)
        if not e or not e.initiator then return end
        if e.id ~= world.event.S_EVENT_TAKEOFF then return end

        local u = e.initiator
        if not u or not u.getName then return end
        local n = u:getName()
        if not n then return end

        -- Player: clear zone gate for a fresh refuel later
        if n == PLAYER_NAME then
            playerRefuel.inZone   = false
            playerRefuel.baseline = nil
            playerRefuel.done     = false
        end

        -- AI: clear trend trackers for that unit
        lastFuel[n] = nil
        baseline[n] = nil
        rewarded[n] = false
    end
    world.addEventHandler(REH)
end

----------------------------------------------------------------
-- CASE I MODULE
----------------------------------------------------------------
local CASE1 = {
    armed = false,
    done  = false
}

local function updateCASEI(u)
    if CASE1.done then return end

    local c = Unit.getByName(CARRIER)
    if not u or not c then return end

    local dist = distToCarrierNm(u, c)

    if not CASE1.armed then
                 if RECOVERY_ACTIVE then
                         CASE1.armed = true
                end
               return
    end

    if not inZone(u, ZONE_10NM) then return end

    local alt = altFt(u)
    local spd = spdKts(u)

    if alt >= 1900 and alt <= 2150 and spd >= 275 and spd <= 320 then
        addScore(5, "CASE I 10NM: Within parameters")
    else
        addScore(-5, "CASE I 10NM: Out of parameters")
    end

    CASE1.done = true
end
----------------------------------------------------------------
-- LANDING +5 (CARRIER TRAP, UNIT-FILTERED, BUG-SAFE)
----------------------------------------------------------------

local TARGET_UNITS = {
    ["LANDER-8-1"] = true,
    ["LANDER-6-1"] = true,
    ["CAS-1-1"] = true,
    ["TOMCAT-2-1"] = true,
    ["TOMCAT-1-1"] = true,
    ["Player_01"] = true,
}

local LANDING_DONE = {}

local LAND_EH = {}

function LAND_EH:onEvent(e)
    if not e or e.id ~= world.event.S_EVENT_LAND then return end
    if not e.initiator or not e.initiator.getName then return end

    local u = e.initiator
    local uname = u:getName()

    if not TARGET_UNITS[uname] then return end
    if LANDING_DONE[uname] then return end

    local c = Unit.getByName(CARRIER)
    if not c or not c:isExist() then return end

    local dist = distToCarrierNm(u, c)

    if dist <= 0.15 then
        LANDING_DONE[uname] = true
        addScore(5, "Successful carrier landing")
    end
end

world.addEventHandler(LAND_EH)
----------------------------------------------------------------
-- BANKLER MERGE
----------------------------------------------------------------

local function mergeBankler()
    -- HARD KILL: CASE III'te merge ASLA olmayacak
    if CASE_III_ENABLED then
        BANKLER_MERGED = true
        return nil
    end

    if BANKLER_MERGED then return nil end
    if not traptrainer or not traptrainer.PlayerData then
        return timer.getTime() + 5
    end

    local b = traptrainer.PlayerData.score or 0
    if b == 0 then return timer.getTime() + 5 end

    local cur = trigger.misc.getUserFlag(FLAG) or 0
    local new = cur + b
    trigger.action.setUserFlag(FLAG, new)

    trigger.action.outTextForCoalition(
        coalition.side.BLUE,
        "Bankler score merged (+"..b..") FINAL: "..new,
        15,
        false
    )

    BANKLER_MERGED = true
    return nil
end

-- Schedule sadece CASE III değilken
if CASE_I_ENABLED then
    timer.scheduleFunction(mergeBankler, nil, timer.getTime() + 30)
end

----------------------------------------------------------------
-- MAIN LOOP
----------------------------------------------------------------
local function mainLoop()
    local u = uPlayer()
    if not u then
        return timer.getTime() + 1
    end

    local now = timer.getTime()

    ------------------------------------------------------------
    -- Inbound activation (60 NM / zone logic)
    ------------------------------------------------------------
    checkRulesActivation()

    ------------------------------------------------------------
    -- HARD DECK (SA-8 threat rule)
    ------------------------------------------------------------
    if TRT_UpdateHardDeck then
        TRT_UpdateHardDeck(u, now)
    end

    ------------------------------------------------------------
    -- Groove fuel scoring (CASE-independent)
    ------------------------------------------------------------
    if TRT_UpdateGrooveFuel then
        TRT_UpdateGrooveFuel(u)
    end

    ------------------------------------------------------------
    -- INBOUND PHASE
    ------------------------------------------------------------
    if RECOVERY_ACTIVE then
        if CASE_I_ENABLED then
            updateCASEI(u)

        elseif CASE_II_ENABLED or CASE_III_ENABLED then
            -- CASE III = CASE II chart checks (IF + HOLD + 12NM)
            updateCASEII(u, now)
        end
    end

    return now + 1
end

timer.scheduleFunction(mainLoop, nil, timer.getTime() + 1)

