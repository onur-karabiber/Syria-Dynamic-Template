-- Recovery_Approach | v1.0.4
-- v1.0.4: on arming (flag 101) the planned recovery case (flag 102) is applied first
-- via TRT.CaseSync.ApplyRecoveryCase (Airboss_CaseSync v1.0.7), so "Recovery Rules
-- Activated: CASE N" shows the recovery case, not the departure case.
-- v1.0.3: CASE I 10NM speed window 275-320 -> 230-270 kt. No source gives a 10 NM
-- speed; the CASE I stack is flown at 250 KIAS (masterarms CASE 1), so the check is
-- centred on the holding speed. Speed is still the 3D velocity (wind-affected).
-- CASE-adaptive inbound/approach scoring. Replaces the per-file
-- CASE_I_ENABLED/II/III switches from CASE-I/II/III_v14.lua: reads the
-- LIVE case (TRT.getCurrentCase) at each checkpoint instead of a value
-- fixed at mission load, so a weather change mid-recovery (fog rolling
-- in, ceiling lifting) is reflected without swapping files.
--
-- v1.0.1: 12NM chart check now uses a single zone (12NMa_Zone) for both
-- CASE II and CASE III. Post-hold, CASE II aligns to the carrier's FB,
-- not BRC - same corridor CASE III uses - so the two zones sat on the
-- same map location. 12NMb_Zone is retired; remove it from the ME.
--
-- v1.0.2: recovery arming is now MANUAL. The old auto-arm (raw
-- distance >= 60NM OR inside Incirlik_Zone) fired on ANY 60NM crossing,
-- including outbound on departure/ingress - it had no way to tell
-- outbound from inbound. Replaced with flag 101 ("Commence Recovery"):
-- set it from an ME trigger (FLAG VALUE action) whenever YOU decide
-- the sortie has transitioned to the recovery phase - gate that
-- trigger on distance/waypoint/time/F10 menu/whatever fits the
-- mission. This script no longer computes or guesses that transition;
-- it only watches the flag. ACTIVATION_DIST_NM/ACTIVATION_ZONE are
-- removed - if you still want a distance floor, build it into the ME
-- trigger that sets flag 101, not into this script.
--
-- Load order: AFTER Core_Scoring.lua and CaseDeterminator.lua.

_G.TRT = _G.TRT or {}
local TRT = _G.TRT

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local ZONE_10NM        = "10NM_Zone"           -- Case I
local IF_ZONE          = "InitialFix_Zone"     -- Case II/III
local HOLD_ZONE        = "Holding_Zone"        -- Case II/III
-- Post-hold 12NM chart corridor for BOTH CASE II and CASE III: after
-- the hold, CASE II aligns to FB (same as CASE III), not BRC - so the
-- corridor is geographically identical for both cases. One zone.
local ZONE_12NM_CHART  = "12NMa_Zone"

-- Manual recovery-arm gate (v1.0.2). Set flag 101 = 1 from an ME
-- trigger (FLAG VALUE action) when you want recovery rules to arm.
-- Put whatever condition set belongs to your mission (distance,
-- waypoint, time, F10 menu press) on THAT trigger - this script does
-- not infer it.
local COMMENCE_FLAG = 101

local COMMENCE_MIN_FUEL_LBS = 3000
local HOLD_DURATION_SEC     = 120

-- IF-fix window: source files disagreed (CASE-II: 9800-10200/260-330,
-- CASE-III: 9600-10400/260-340). Merged to the wider CASE-III values -
-- tighten back to CASE-II's numbers here if that was the intended one.
local IF_ALT_MIN, IF_ALT_MAX = 9600, 10400
local IF_SPD_MIN, IF_SPD_MAX = 260, 340

local NM12_ALT_MIN, NM12_ALT_MAX = 1100, 1400
local NM12_SPD_MIN, NM12_SPD_MAX = 220, 270

local CASE1_ALT_MIN, CASE1_ALT_MAX = 1900, 2150
local CASE1_SPD_MIN, CASE1_SPD_MAX = 230, 270   -- v1.0.3 (was 275, 320)

----------------------------------------------------------------
-- STATE
----------------------------------------------------------------
RECOVERY_ACTIVE = false
CASE_PHASE = "NONE"

local CASE1 = { done = false }
local CHART = {
    ifDone = false, holdEnter = nil, holdDone = false,
    nm12Done = false, commenceFuelChecked = false,
}

local function resetChart()
    CHART.ifDone, CHART.holdEnter, CHART.holdDone = false, nil, false
    CHART.nm12Done, CHART.commenceFuelChecked = false, false
end

local function commenceFuelLbs(u)
    local frac = u:getFuel()
    if not frac then return nil end
    local ok, desc = pcall(function() return u:getDesc() end)
    if ok and desc and desc.fuelMassMax then
        return frac * desc.fuelMassMax * 2.2046226218
    end
    return frac * 11000
end



----------------------------------------------------------------
-- ACTIVATION (single-shot latch, matches source files' "ONE WAY" design)
-- Gated entirely on flag 101 - see COMMENCE_FLAG above. No distance or
-- zone math here; that decision belongs to the ME trigger that sets
-- the flag, not to this script.
----------------------------------------------------------------
local function checkRulesActivation()
    if RECOVERY_ACTIVE then return end
    if not TRT.flagTrue(COMMENCE_FLAG) then return end

    RECOVERY_ACTIVE = true
    CASE_PHASE = "ACTIVE"
    resetChart()
    CASE1.done = false

    if TRT.CaseSync and TRT.CaseSync.ApplyRecoveryCase then pcall(TRT.CaseSync.ApplyRecoveryCase) end
    local case = TRT.getCurrentCase()
    trigger.action.outText("Recovery Rules Activated: CASE " .. case, 10)
end

----------------------------------------------------------------
-- CASE I: 10NM ONE-SHOT
----------------------------------------------------------------
local function updateCase1(u)
    if CASE1.done then return end
    if not TRT.inZone(u, ZONE_10NM) then return end

    local alt, spd = TRT.altFt(u), TRT.spdKts(u)
    if alt >= CASE1_ALT_MIN and alt <= CASE1_ALT_MAX
       and spd >= CASE1_SPD_MIN and spd <= CASE1_SPD_MAX then
        TRT.addScore(5, "CASE I 10NM: Within parameters")
    else
        TRT.addScore(-5, "CASE I 10NM: Out of parameters")
    end
    CASE1.done = true
    CASE_PHASE = "DONE"
end

----------------------------------------------------------------
-- CASE II/III: IF -> HOLD -> 12NM CHART
----------------------------------------------------------------
local function updateChart(u, now, case)
    if not CHART.ifDone and TRT.inZone(u, IF_ZONE) then
        local alt, spd = TRT.altFt(u), TRT.spdKts(u)
        if alt >= IF_ALT_MIN and alt <= IF_ALT_MAX
           and spd >= IF_SPD_MIN and spd <= IF_SPD_MAX then
            TRT.addScore(5, "Initial Fix: Within parameters")
        else
            TRT.addScore(-5, "Initial Fix: Out of parameters")
        end

        if not CHART.commenceFuelChecked then
            local lbs = commenceFuelLbs(u)
            if lbs then
                local msg = string.format(
                    "Commence fuel check: MIN %d lbs, you have %.0f lbs%s",
                    COMMENCE_MIN_FUEL_LBS, lbs,
                    (lbs < COMMENCE_MIN_FUEL_LBS) and " - Proceed to tanker" or "")
                trigger.action.outTextForCoalition(coalition.side.BLUE, msg, 10, false)
            end
            CHART.commenceFuelChecked = true
        end

        CHART.ifDone = true
        CASE_PHASE = "IF"
        return
    end

    if CHART.ifDone and not CHART.holdDone then
        if TRT.inZone(u, HOLD_ZONE) then
            if not CHART.holdEnter then CHART.holdEnter = now end
            if now - CHART.holdEnter >= HOLD_DURATION_SEC then
                TRT.addScore(5, "Holding duration correct")
                CHART.holdDone = true
                CASE_PHASE = "HOLD"
            end
        end
        return
    end

    if CHART.ifDone and CHART.holdDone and not CHART.nm12Done then
        if not TRT.inZone(u, ZONE_12NM_CHART) then return end

        local alt, spd = TRT.altFt(u), TRT.spdKts(u)
        local label = "CASE " .. case
        if alt >= NM12_ALT_MIN and alt <= NM12_ALT_MAX
           and spd >= NM12_SPD_MIN and spd <= NM12_SPD_MAX then
            TRT.addScore(5, label .. " 12NM: Within parameters")
        else
            TRT.addScore(-5, label .. " 12NM: Out of parameters")
        end
        CHART.nm12Done = true
        CASE_PHASE = "ARC12"
    end
end

----------------------------------------------------------------
-- MAIN LOOP (1 Hz) - branch selected by LIVE case, re-read every tick
----------------------------------------------------------------
local function mainLoop()
    local u = TRT.uPlayer()
    if not u or not u:isExist() then return timer.getTime() + 1 end
    local now = timer.getTime()

    checkRulesActivation()
    TRT.updateGrooveFuel(u)

    if RECOVERY_ACTIVE then
        local case = TRT.getCurrentCase()
        if case == 1 then
            updateCase1(u)
        else
            updateChart(u, now, case)
        end
    end

    return now + 1
end

timer.scheduleFunction(mainLoop, nil, timer.getTime() + 1)
env.info("[Recovery_Approach] v1.0.4 loaded.")
