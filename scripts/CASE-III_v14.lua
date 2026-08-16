-- DEBUG: script load check
trigger.action.outText("CASE III v13 script loaded", 5)

----------------------------------------------------------------
-- TRT SYRIA RECOVERY FRAMEWORK
-- CASE I / CASE II / CASE III (Single Script)
-- v7 FIXED: Explicit 60NM activation (no airborne auto-start)
----------------------------------------------------------------

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local PLAYER_NAME   = "Player_01"
local CARRIER       = "CVN"
local FLAG          = 1908
-- Players who can earn landing points (unit names in ME)
local PLAYER_NAMES = {
    "Player_01",
    "Player_02",
}


----------------------------------------------------------------
-- FLAG EVENTS (Refuel / Landing / Zones / Targets)
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

local function setFlagON(flagNum)
    trigger.action.setUserFlag(flagNum, 1)
end
-- Zones (Mission Editor'da AYNEN bu isimlerle olmalı)
local IF_ZONE          = "InitialFix_Zone"
local HOLD_ZONE        = "Holding_Zone"
local ZONE_12NM_CASE2  = "12NMa_Zone"
local ZONE_12NM_CASE3  = "12NMb_Zone"
local ZONE_10NM        = "10NM_Zone"
local DEP_7NM_ZONE     = "7NM_Departure_Zone" -- sadece görsel, logic mesafe bazlı

-- CASE PROFILE SELECTOR (ONLY ONE TRUE)
local CASE_I_ENABLED   = false
local CASE_II_ENABLED  = false
local CASE_III_ENABLED = true

----------------------------------------------------------------
-- GLOBAL STATE
----------------------------------------------------------------
RECOVERY_ACTIVE = false
CASE_PHASE      = "NONE"     -- "NONE","ACTIVE","DEPARTURE","IF","HOLD","ARC12","TEN","FB","GROOVE","DONE"
BANKLER_MERGED  = false

----------------------------------------------------------------
-- SAFETY: ensure exactly one CASE enabled
----------------------------------------------------------------
do
    local n = 0
    if CASE_I_ENABLED then n = n + 1 end
    if CASE_II_ENABLED then n = n + 1 end
    if CASE_III_ENABLED then n = n + 1 end
    if n ~= 1 then
        trigger.action.outText("CASE CONFIG ERROR: enable exactly ONE of CASE I/II/III", 30, true)
    end
end

----------------------------------------------------------------
-- SCORE
----------------------------------------------------------------
local function addScore(delta, reason)
    local cur = trigger.misc.getUserFlag(FLAG) or 0
    local new = cur + delta
    trigger.action.setUserFlag(FLAG, new)

    local sign = (delta >= 0) and ("+" .. tostring(delta)) or tostring(delta)
    trigger.action.outText(
        tostring(reason) .. " (" .. sign .. ") [TOTAL " .. tostring(new) .. "]",
        8
    )
end

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function uPlayer()
    return Unit.getByName(PLAYER_NAME)
end

local function uCarrier()
    return Unit.getByName(CARRIER)
end

local function isTrackedPlayer(name)
    for _, n in ipairs(PLAYER_NAMES) do
        if name == n then return true end
    end
    return false
end

local function altFt(u)
    if not u or not u:isExist() then return 0 end
    local p = u:getPoint()
    return (p and p.y or 0) * 3.28084
end

-- Horizontal ground speed (X/Z only)
local function spdKts(u)
    if not u or not u:isExist() then return 0 end
    local v = u:getVelocity()
    if not v then return 0 end
    return math.sqrt((v.x or 0)^2 + (v.z or 0)^2) * 1.94384
end

local PLAYER_NAMES = {
    "Player_01",
    "Player_02",
}


----------------------------------------------------------------
-- ZONE ENTRY FLAGS (Conversation_3 / Conversation_6)
----------------------------------------------------------------
local zoneFlagDone = {
    ["Player_01"] = { conv3 = false, conv6 = false },
    ["Player_02"] = { conv3 = false, conv6 = false },
}

local function updateConversationZoneFlags()
    for _, pname in ipairs(PLAYER_NAMES) do
        local u = Unit.getByName(pname)
        if u and u:isExist() then
            -- Conversation_3
            if not zoneFlagDone[pname].conv3 and inZone(u, "Conversation_3") then
                zoneFlagDone[pname].conv3 = true
                if pname == "Player_01" then
                    setFlagON(FLAG_CONV3_P1)
                elseif pname == "Player_02" then
                    setFlagON(FLAG_CONV3_P2)
                end
            end

            -- Conversation_6
            if not zoneFlagDone[pname].conv6 and inZone(u, "Conversation_6") then
                zoneFlagDone[pname].conv6 = true
                if pname == "Player_01" then
                    setFlagON(FLAG_CONV6_P1)
                elseif pname == "Player_02" then
                    setFlagON(FLAG_CONV6_P2)
                end
            end
        end
    end
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

----------------------------------------------------------------
-- IFEI BRIGHTNESS CONFIRM (RADIO COMMAND)
----------------------------------------------------------------
local IFEI_DONE = false

do
    local function confirmIFEI()
        if IFEI_DONE then return end
        IFEI_DONE = true
        addScore(1, "IFEI brightness set (~10%)")
    end

    missionCommands.addCommandForCoalition(
        coalition.side.BLUE,
        "IFEI brightness set",
        nil,
        confirmIFEI
    )
end

-- Dummy (önceki kırpma faciasının intikamı: artık nil yok)
local function updateIFEI(_u)
    -- IFEI radio ile one-shot confirm ediliyor; loop'ta iş yok
end

----------------------------------------------------------------
-- GLOBAL: 60NM WARNING (independent, DISABLED BY DEFAULT)
----------------------------------------------------------------
local WARN60_ENABLED = false   -- <<< HERE Activate/Deactivate
local WARN60_DONE    = false

local function updateFarWarning(u)
    if not WARN60_ENABLED then return end
    if WARN60_DONE then return end

    local c = uCarrier()
    if not c or not c:isExist() then return end

    local d = distToCarrierNm(u, c)
    if d >= 60 then
        WARN60_DONE = true
        trigger.action.outText(
            "WARNING: 60 NM from mother. You're out in the weeds.",
            10
        )
    end
end

----------------------------------------------------------------
-- GROOVE FUEL SCORING (ONE-SHOT per unit)
----------------------------------------------------------------
local grooveDone = {}

local function updateGrooveFuel(u)
    if not u or not u:isExist() then return end
    local name = u:getName()
    if not name or grooveDone[name] then return end

    local c = uCarrier()
    if not c or not c:isExist() then return end

    -- Groove gate: close to ship + plausible alt/speed
    local dist = distToCarrierNm(u, c)
    if dist > 1.6 then return end

    local alt = altFt(u)
    if alt < 50 or alt > 900 then return end

    local spd = spdKts(u)
    if spd < 105 or spd > 210 then return end

    local frac = u:getFuel()
    if not frac then return end
    local lbs = frac * 11000 -- fallback scaling

    local delta, msg
    if lbs < 1500 then
        delta, msg = -8, string.format("Fuel state below recovery minimum: %.0f lbs", lbs)
    elseif lbs < 2000 then
        delta, msg = -5, string.format("Fuel CRITICAL: %.0f lbs", lbs)
    elseif lbs >= 2500 and lbs <= 3500 then
        delta, msg =  5, string.format("Fuel OPTIMAL: %.0f lbs", lbs)
    elseif lbs <= 5000 then
        delta, msg =  0, string.format("High fuel state in groove: %.0f lbs", lbs)
    else
        delta, msg =  0, string.format("Excess fuel for recovery: %.0f lbs", lbs)
    end

    grooveDone[name] = true
    if delta ~= 0 then
        addScore(delta, msg)
    else
        trigger.action.outText(msg, 8)
    end
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

    -- FLAG: Player_01 refuel success
    if PLAYER_NAME == "Player_01" then
        setFlagON(FLAG_REFUEL_P1)
    end
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

                -- FLAG: Player_02 refuel success (if applicable)
                if name == "Player_02" then
                    setFlagON(FLAG_REFUEL_P2)
                end
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
-- DEAD SCORING TABLE (FULL)
----------------------------------------------------------------
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
-- CASE II / CASE III CHART MODULE (IF + HOLD + 12NM)
----------------------------------------------------------------

-- CASE II / III shared state
local CASE2 = {
    ifDone     = false,
    holdEnter = nil,
    holdDone  = false,
    nm12Done  = false,
}

----------------------------------------------------------------
-- RESET (called on recovery activation)
----------------------------------------------------------------
local function resetCASE2()
    CASE2.ifDone     = false
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
-- UPDATE LOOP (IF -> HOLD -> 12NM) [SCORING]
----------------------------------------------------------------
local function updateCASEII(u, now)
    if not u or not u:isExist() then return end

    ------------------------------------------------------------
    -- IF CHECK (ONE-SHOT)
    ------------------------------------------------------------
    if not CASE2.ifDone and inZone(u, IF_ZONE) then
        local alt = altFt(u)
        local spd = spdKts(u)

        if alt >= 9600 and alt <= 10400 and spd >= 260 and spd <= 340 then
            addScore(5, "IF: Within parameters")
        else
            addScore(-5, "IF: Out of parameters")
        end

        CASE2.ifDone = true
        CASE_PHASE = "IF"
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
                addScore(5, "Holding duration correct (>=120s)")
                CASE2.holdDone = true
                CASE_PHASE = "HOLD"
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
            CASE_PHASE = "ARC12"
        end
    end
end

----------------------------------------------------------------
-- EXPLICIT RULES ACTIVATION (SINGLE-SHOT, 60NM)
----------------------------------------------------------------
local function checkRulesActivation()
    -- HARD GUARD: sadece bir kere çalışır
    if RECOVERY_ACTIVE then return end

    local u = uPlayer()
    local c = uCarrier()
    if not u or not u:isExist() or not c or not c:isExist() then return end

    local dist = distToCarrierNm(u, c)

    -- EXPLICIT ACTIVATION: 60 NM only
    local activate = (dist >= 60)

    if not activate then return end

    ------------------------------------------------------------
    -- ACTIVATE RECOVERY (ONE WAY)
    ------------------------------------------------------------
    RECOVERY_ACTIVE = true
    CASE_PHASE = "ACTIVE"

    ------------------------------------------------------------
    -- HARD RESET: CASE II / III chart state
    ------------------------------------------------------------
    resetCASE2()

    -- RESET GROOVE FUEL SCORING (per recovery)
    grooveDone = {}

    ------------------------------------------------------------
    -- HARD KILL: Bankler CASE III'te ASLA çalışmaz
    ------------------------------------------------------------
    if CASE_III_ENABLED then
        BANKLER_MERGED = true
    end

    ------------------------------------------------------------
    -- ANNOUNCE
    ------------------------------------------------------------
    if CASE_I_ENABLED then
        trigger.action.outText("Recovery Rules Activated: CASE I", 10)
    elseif CASE_II_ENABLED then
        trigger.action.outText("Recovery Rules Activated: CASE II", 10)
    else
        trigger.action.outText("Recovery Rules Activated: CASE III", 10)
    end
end

----------------------------------------------------------------
-- CASE I/II: BANKLER (minimal, robust)
----------------------------------------------------------------
local BANKLER = {
    armed = false,
    started = false,
    done = false,
}

local function armBankler()
    BANKLER.armed = true
    BANKLER.started = false
    BANKLER.done = false
end

local function updateBankler(u)
    if not (CASE_I_ENABLED or CASE_II_ENABLED) then return end
    if not BANKLER.armed or BANKLER.done then return end
    if not u or not u:isExist() then return end

    local c = uCarrier()
    if not c or not c:isExist() then return end

    -- Trigger: near ship + low alt + decent speed + enters IF zone (your workflow)
    local dist = distToCarrierNm(u, c)
    local alt  = altFt(u)
    local spd  = spdKts(u)

    if inZone(u, IF_ZONE) and dist <= 12 and alt <= 900 and spd >= 250 and spd <= 370 then
        if not BANKLER.started then
            BANKLER.started = true
            trigger.action.outText("Bankler: commence. Report platform.", 8)
            if CASE_II_ENABLED then
                trigger.action.outText("CASE II: expect 'see you at ten' at 12.", 8)
            end
        end
    end

    -- End bankler when in groove (rough)
    if dist <= 1.6 and alt <= 900 and spd >= 105 and spd <= 210 then
        if BANKLER.started and not BANKLER.done then
            BANKLER.done = true
            trigger.action.outText("Bankler complete.", 6)
        end
    end
end

-- Arm Bankler once airborne (for CASE I/II)
timer.scheduleFunction(function()
    if not (CASE_I_ENABLED or CASE_II_ENABLED) then return timer.getTime() + 2 end

    local u = uPlayer()
    local c = uCarrier()
    if not u or not u:isExist() or not c or not c:isExist() then
        return timer.getTime() + 2
    end

    if not BANKLER.armed then
        local dist = distToCarrierNm(u, c)
        local alt  = altFt(u)
        local spd  = spdKts(u)
        if dist > 0.3 and alt > 50 and spd > 80 then
            armBankler()
        end
    end

    return timer.getTime() + 2
end, nil, timer.getTime() + 2)

----------------------------------------------------------------
-- LANDING / FINAL SCORE (PLAYER + WINGMAN LOGIC)
----------------------------------------------------------------
local FINAL_SHOWN    = false
local WINGMAN_LANDED = false

world.addEventHandler({
    onEvent = function(_, e)
        if not e or e.id ~= world.event.S_EVENT_LAND then return end

        local u = e.initiator
        if not u or not u:isExist() or not u.getName then return end

        local uname = u:getName()
        if not isTrackedPlayer(uname) then return end

        local c = uCarrier()
        if not c or not c:isExist() then return end

        -- Must be an actual carrier landing
        if distToCarrierNm(u, c) > 0.15 then return end

        ----------------------------------------------------------------
        -- PLAYER_01 LANDING (MAIN FINAL)
        ----------------------------------------------------------------
        if uname == PLAYER_NAME then
            addScore(5, "Successful Carrier Landing: " .. uname)

                -- FLAG: Player_01 landed
                if uname == "Player_01" then
                    setFlagON(FLAG_LAND_P1)
                end

            if not FINAL_SHOWN then
                FINAL_SHOWN = true
                local final = trigger.misc.getUserFlag(FLAG) or 0
                trigger.action.outText(
                    "FINAL SCORE: " .. tostring(final),
                    15,
                    true
                )
            end
            return
        end

        ----------------------------------------------------------------
        -- PLAYER_02 LANDING (WINGMAN BONUS)
        ----------------------------------------------------------------
        if uname ~= PLAYER_NAME and not WINGMAN_LANDED then
            WINGMAN_LANDED = true

            addScore(5, "Wingman recovered: " .. uname)

                -- FLAG: Player_02 landed
                if uname == "Player_02" then
                    setFlagON(FLAG_LAND_P2)
                end

            local final = trigger.misc.getUserFlag(FLAG) or 0
            trigger.action.outText(
                "Wingman geri döndü. +5 Bonus puan ile YOUR FINAL SCORE: " .. tostring(final),
                15,
                true
            )
        end
    end
})

----------------------------------------------------------------
-- MAIN LOOP (1 Hz)
----------------------------------------------------------------
timer.scheduleFunction(function()
    local u = uPlayer()
    if not u or not u:isExist() then
        return timer.getTime() + 1
    end

    local now = timer.getTime()

    updateIFEI(u)
    updateFarWarning(u)

    -- EXPLICIT activation (60NM)
    checkRulesActivation()

-- Case-independent modules
updateBankler(u)

-- Inbound / recovery-only modules
if RECOVERY_ACTIVE then
    updateGrooveFuel(u)

    if CASE_II_ENABLED or CASE_III_ENABLED then
        updateCASEII(u, now)
    end
end

    return now + 1
end, nil, timer.getTime() + 1)
