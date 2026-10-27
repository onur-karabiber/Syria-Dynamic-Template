-- Flight_Timeline | v1.0.0
--[[
  CAS-1 timing (ATO) and timing score — TRT Syria Dynamic Template (template-level module)
  Design: project doc claude/cas1-timing-design-2026-10-27.md (v0.2, decisions 2026-10-27).

  Measures, logs and (with CFG.SCORING = true) scores the hero's timeline against a plan built
  at mission start from CFG offsets and the Mission Editor route of CFG.GROUP:

    code  event                                            plan                      points
    M1    engines running (PlaneCaptain START phase done;  L - 20:00                 on time +2, else 0
          without PlaneCaptain: first S_EVENT_ENGINE_STARTUP)
    M2    BEFORE TAXI checks done (PlaneCaptain CHECKS)    L - 10:00                 on time +3, else 0
    T1    cat shot (S_EVENT_TAKEOFF / airborne fallback)   L = T0 + 30:00            L-1:00..L+2:00 +2 | ..+5:00 0
                                                                                     | ..+10:00 -2 | later -4
    T2    CP: first entry within CP_RADIUS_NM of the       L + (ETA_cp - ETA_wp1)    |d| <= 2:00 +3 | <= 5:00 0
          route point named CFG.CP_WP_NAME                 (ME route of CFG.GROUP)   | late -3 | early -1
    T3    VUL END: JTAC-2 target dead (Comms_Director)     CP + 35:00                on time +2 | <= +10:00 0
                                                                                     | later (or still on station) -2
    T4    fuel below BINGO(position) while on station      -                         -1 per full minute, cap -5
          (<= STATION_NM of the CP, before RTB, not while refuelling); settled when the station ends

  The sum of all items is clipped to [CAP_MIN, CAP_MAX] = [-12, +9]. Commence vs EAT stays in CV_Comms.
  Note: the raw best case is +12 (2+3+2+3+2), so a perfect sortie is clipped to +9 (decision 2026-10-27).

  Credit (stop-clock): every plan time is evaluated as plan + credit accrued so far.
    threat  : 1:1 while a RED missile aimed at the hero is in flight (<= MISSILE_TTL s each), a RED fighter
              is airborne within THREAT_CLOSE_NM, or INJ-1 abort is active (flag 201 = 1). Cap THREAT_CREDIT_MAX.
    failure : FAIL_CREDIT_S once per ME failure with enable = true and prob >= 100, when its start time is
              reached. hh:mm is read as time after mission start (CFG.FAIL_TIME_BASE) - UNVERIFIED, test it.
              No on-screen text (it would announce the failure); log only.
  Void: OVERLORD "mission abort" (Comms_Director CD.aborted) voids every item not yet settled (T2, T3, T4).
        T1, M1, M2 and the recovery scoring are not affected.

  v1.0.0 ships in SHADOW mode (CFG.SCORING = false): everything is computed, logged ("[TL]") and shown as
  "[TL shadow]" text; nothing is added to flag 1908. T4 additionally needs CFG.BINGO_CALIBRATED = true:
  BURN_LB_PER_NM, JOKER_MARGIN_LB and BURN_ON_STATION_LB_MIN are placeholders until measured from the
  "[TL] FUEL" log lines.

  Flags (latched 1): 3100 cat shot · 3101 CP reached · 3102 JOKER · 3103 BINGO · 3104 VUL END passed.
  Menu: F10 > INFO > "Show: flight card", "Show: timeline" (Menu_Manager).
  Reads, never writes: TRT.CD (Comms_Director >= v1.5.1: phase, aborted, deadJ2, j2.tot),
                       TRT.PlaneCaptain.milestones (PlaneCaptain_Carrier >= v1.2.2).
  Load order: after Core_Scoring, Menu_Manager and Comms_Director (and PlaneCaptain, if the mission has it).
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.TL then
    env.info("[TL] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION        = "1.0.0",
    PLAYER_UNIT    = TRT.PLAYER_NAME or "Player_01",
    GROUP          = "CAS-1",          -- ME group whose route builds the ATO
    CARRIER        = "CVN",
    CP_WP_NAME     = "Contact JTAC",   -- ME route point name of the CP (fallback: last route point)
    CP_NAME        = "CP TIGER",
    CP_ETE_FALLBACK = 2460,            -- s, used only if the route cannot be read
    CP_POS_FALLBACK = { x = 73640, z = -39914 },

    SCORING        = false,            -- v1.0.0: shadow mode (log + text only)
    SHADOW_MSG     = true,             -- show "[TL shadow]" lines on screen
    BINGO_CALIBRATED = false,          -- T4 scores only when true
    FUEL_CALLS     = false,            -- on-screen JOKER / BINGO text (off while numbers are placeholders)

    TICK           = 2,                -- s
    FUEL_LOG_EVERY = 60,               -- s, "[TL] FUEL" line after launch
    AMMO_EVERY     = 10,               -- s, A/G store count (WINCHESTER)

    -- ATO offsets (s)
    LAUNCH_AFTER_T0 = 1800,            -- L = T0 + 30:00  (T0 = mission start = man-up)
    ENG_BY          = -1200,           -- M1 by L - 20:00
    CHECKS_BY       = -600,            -- M2 by L - 10:00
    VUL_LEN         = 2100,            -- VUL END = CP + 35:00  (placeholder until J1/J2 durations are measured)

    -- geometry (NM)
    CP_RADIUS_NM   = 5,
    STATION_NM     = 40,               -- "on station" for T4
    STATION_LEFT_NM = 60,              -- beyond this after the CP: station ended (T4 settles)

    -- points
    M1_PTS = 2, M2_PTS = 3,
    T1_EARLY = -60, T1_GOOD = 120, T1_LATE1 = 300, T1_LATE2 = 600,
    T1_PTS_GOOD = 2, T1_PTS_LATE1 = -2, T1_PTS_LATE2 = -4,
    T2_GOOD = 120, T2_OK = 300, T2_PTS_GOOD = 3, T2_PTS_LATE = -3, T2_PTS_EARLY = -1,
    T3_LATE = 600, T3_PTS_GOOD = 2, T3_PTS_LATE = -2,
    T4_PTS_PER_MIN = -1, T4_CAP = -5,
    CAP_MIN = -12, CAP_MAX = 9,

    -- credit
    THREAT_CLOSE_NM   = 20,            -- same value as Comms_Director CFG.THREAT_CLOSE_NM
    MISSILE_TTL       = 90,            -- s per missile
    THREAT_CREDIT_MAX = 600,           -- s per sortie
    FIGHTER_ATTRS     = { "Fighters", "Interceptors", "Multirole fighters" },
    INJ1_FLAG         = 201,
    FAIL_CREDIT_S     = 300,           -- s per deterministic ME failure
    FAIL_TIME_BASE    = "elapsed",     -- hh:mm = time after mission start (UNVERIFIED)

    -- fuel (lb). PLACEHOLDERS except ARR_RESERVE_LB (= middle of Core_Scoring's 2500-3500 groove window)
    ARR_RESERVE_LB         = 3000,
    BURN_LB_PER_NM         = 11,       -- PLACEHOLDER (assumed 3500-4500 lb/h at 350-420 kt GS, unverified)
    JOKER_MARGIN_LB        = 1000,     -- PLACEHOLDER
    BURN_ON_STATION_LB_MIN = 70,       -- PLACEHOLDER, only for the TOS estimate on the card
    FUEL_FALLBACK_LB       = 10860,    -- internal fuel if getDesc() has no fuelMassMax

    FLAGS = { LAUNCH = 3100, CP = 3101, JOKER = 3102, BINGO = 3103, VUL = 3104 },
    MENU_ORDER = 30,
    DEBRIEF_DELAY = 20, DEBRIEF_DUR = 45,
}

local NAMES = {
    M1 = "ENGINES RUNNING", M2 = "CHECKS DONE", T1 = "CAT SHOT",
    T2 = CFG.CP_NAME, T3 = "VUL END (JTAC-2)", T4 = "BINGO ON STATION",
}
local ORDER = { "M1", "M2", "T1", "T2", "T3", "T4" }

local MISSION_PH = {
    STRIKE_OUT = true, STRIKE_CHK = true, OVL_OUT = true, ENROUTE = true, JTAC1 = true, J1_OFF = true,
    JTAC2 = true, J2_OFF = true, REFUEL = true, TKR_DONE = true,
}
local STATION_PH = { JTAC1 = true, J1_OFF = true, JTAC2 = true }
local END_PH = { RTB = true, STRIKE_IN = true, INBOUND = true, RECOVERY = true, DONE = true }

-- ══════════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════════
local TL = {
    startAbs = timer.getAbsTime() - timer.getTime(),
    ato = nil,
    credit = { threat = 0, fail = 0 },
    fails = {},              -- { id, at, done }
    missiles = {},           -- { w, t0, desc }
    engaged = false, engagedWhy = nil,
    m = {},                  -- code -> { state, plan, act, dt, pts, applied, note }
    sum = 0,
    launched = nil, landed = nil, aborted = nil, birth = nil,
    engEvt = nil,
    cpReached = nil,
    phase = nil, phaseT = {},
    bingoSec = 0, t4Mark = nil,
    refueling = false, refuelT = nil,
    joker = false, bingo = false,
    ag = nil, agMax = nil, winchester = nil,
    lastTick = nil, lastFuelLog = nil, lastAmmo = nil, fuelInit = false,
}
for _, c in ipairs(ORDER) do TL.m[c] = {} end
TRT.TL = TL

-- ══════════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════════
local function log(s) env.info("[TL] " .. s) end
local function now() return timer.getTime() end

local function hero()
    local u = Unit.getByName(CFG.PLAYER_UNIT)
    if u and u:isExist() then return u end
    return nil
end

local function credit() return TL.credit.threat + TL.credit.fail end

local function clock(t)
    if not t then return "--:--:--" end
    local a = math.floor(TL.startAbs + t + 0.5) % 86400
    return string.format("%02d:%02d:%02dL", math.floor(a / 3600), math.floor((a % 3600) / 60), a % 60)
end

local function mmss(d)
    if not d then return "--:--" end
    local sign = (d < 0) and "-" or "+"
    d = math.floor(math.abs(d) + 0.5)
    return string.format("%s%d:%02d", sign, math.floor(d / 60), d % 60)
end

local function absToElapsed(a)
    if type(a) ~= "number" then return nil end
    local d = a - TL.startAbs
    if d < -43200 then d = d + 86400 end
    return d
end

local function msg(text, dur)
    local u = hero()
    if u then
        trigger.action.outTextForGroup(u:getGroup():getID(), text, dur or 10, false)
    else
        trigger.action.outText(text, dur or 10, false)
    end
end

local function setFlag(id) trigger.action.setUserFlag(tostring(id), 1) end

local function dictStr(s)
    if type(s) ~= "string" then return s end
    if env.getValueDictByKey then
        local ok, r = pcall(env.getValueDictByKey, s)
        if ok and type(r) == "string" and r ~= "" then return r end
    end
    return s
end

local function distNm(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz) / 1852
end

local function carrierDistNm(p)
    local c = Unit.getByName(CFG.CARRIER)
    if not (c and c:isExist()) then return nil end
    return distNm(p, c:getPoint())
end

local function fuelLb(u)
    local f = u:getFuel()
    if not f then return nil end
    local ok, d = pcall(function() return u:getDesc() end)
    local maxKg = ok and d and d.fuelMassMax or nil
    if not maxKg then return f * CFG.FUEL_FALLBACK_LB, f, nil end
    return f * maxKg * 2.2046226218, f, maxKg
end

local function bingoLb(dNm) return CFG.ARR_RESERVE_LB + dNm * CFG.BURN_LB_PER_NM end

local function cdState()
    local cd = TRT.CD
    if type(cd) == "table" then return cd end
    return nil
end

-- ══════════════════════════════════════════════════════════════
--  ATO
-- ══════════════════════════════════════════════════════════════
local function findRoute(gname)
    local co = env.mission and env.mission.coalition
    if type(co) ~= "table" then return nil end
    for _, side in pairs(co) do
        if type(side) == "table" and type(side.country) == "table" then
            for _, c in pairs(side.country) do
                for _, cat in ipairs({ "plane", "helicopter" }) do
                    local gs = c[cat] and c[cat].group
                    if type(gs) == "table" then
                        for _, g in pairs(gs) do
                            if dictStr(g.name) == gname then return g.route and g.route.points end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function buildATO()
    local A = { T0 = 0 }
    A.L  = CFG.LAUNCH_AFTER_T0
    A.M1 = A.L + CFG.ENG_BY
    A.M2 = A.L + CFG.CHECKS_BY
    local pts = findRoute(CFG.GROUP)
    local cp, src = nil, nil
    if type(pts) == "table" and pts[1] then
        for i = 1, #pts do
            if dictStr(pts[i].name) == CFG.CP_WP_NAME then cp, src = pts[i], string.format("WP%d '%s'", i, CFG.CP_WP_NAME) end
        end
        if not cp and #pts >= 2 then cp, src = pts[#pts], string.format("last WP%d", #pts) end
    end
    if cp and type(cp.ETA) == "number" and type(pts[1].ETA) == "number" and cp.x and cp.y then
        A.ete   = cp.ETA - pts[1].ETA
        A.cpPos = { x = cp.x, z = cp.y }     -- ME x = north -> vec3.x, ME y = east -> vec3.z
    else
        A.ete, A.cpPos, src = CFG.CP_ETE_FALLBACK, CFG.CP_POS_FALLBACK, "CFG fallback (route of '" .. CFG.GROUP .. "' not read)"
    end
    A.CP  = A.L + A.ete
    A.VUL = A.CP + CFG.VUL_LEN
    A.src = src
    return A
end

local function readFailures()
    local f = env.mission and env.mission.failures
    if type(f) ~= "table" then return end
    for k, v in pairs(f) do
        if type(v) == "table" and v.enable == true and (tonumber(v.prob) or 0) >= 100 then
            local at = (tonumber(v.hh) or 0) * 3600 + (tonumber(v.mm) or 0) * 60
            TL.fails[#TL.fails + 1] = { id = v.id or k, at = at, done = false }
            log(string.format("failure credit armed: %s at T0+%s (%s, mmint %s) -> +%d s",
                tostring(v.id or k), mmss(at), CFG.FAIL_TIME_BASE, tostring(v.mmint), CFG.FAIL_CREDIT_S))
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  SCORING CORE
-- ══════════════════════════════════════════════════════════════
local function award(code, pts, label, r)
    local before = TL.sum
    local after = math.max(CFG.CAP_MIN, math.min(CFG.CAP_MAX, before + pts))
    local applied = after - before
    TL.sum = after
    r.pts, r.applied = pts, applied
    local clip = (applied ~= pts) and string.format(" [cap: %+d]", applied) or ""
    local line = string.format("TIMING %s %s: %s%s", code, NAMES[code], label, clip)
    if CFG.SCORING then
        if applied ~= 0 and TRT.addScore then
            TRT.addScore(applied, line)
        else
            msg(line .. " (0)", 8)
        end
    elseif CFG.SHADOW_MSG then
        msg(string.format("[TL shadow] %s -> %+d", line, applied), 8)
    end
    log(string.format("SCORE %s pts=%+d applied=%+d sum=%+d scoring=%s | %s",
        code, pts, applied, TL.sum, tostring(CFG.SCORING), label))
end

local function settle(code, plan, act, pts, label)
    local r = TL.m[code]
    if r.state then return end
    r.state, r.plan, r.act = "done", plan, act
    r.dt = (plan and act) and (act - plan) or nil
    r.note = label
    log(string.format("%s %s plan=%s act=%s d=%s credit=%s", code, NAMES[code], clock(plan), clock(act),
        mmss(r.dt), mmss(credit())))
    award(code, pts, label, r)
end

local function mark(code, state, why, plan)
    local r = TL.m[code]
    if r.state then return end
    r.state, r.note, r.pts, r.applied, r.plan = state, why, 0, 0, plan
    log(string.format("%s %s %s: %s", code, NAMES[code], string.upper(state), why))
end

-- M1 / M2: reward only
local function scoreGround(code, t, base, pts, what, src)
    local plan = base + credit()
    local p = (t <= plan) and pts or 0
    settle(code, plan, t, p, string.format("%s at %s, due %s (%s) [%s]", what, clock(t), clock(plan), mmss(t - plan), src))
end

local function scoreT1(t)
    local plan = TL.ato.L + credit()
    local d = t - plan
    local p
    if d < CFG.T1_EARLY then p = 0
    elseif d <= CFG.T1_GOOD then p = CFG.T1_PTS_GOOD
    elseif d <= CFG.T1_LATE1 then p = 0
    elseif d <= CFG.T1_LATE2 then p = CFG.T1_PTS_LATE1
    else p = CFG.T1_PTS_LATE2 end
    settle("T1", plan, t, p, string.format("cat shot %s, L %s (%s)", clock(t), clock(plan), mmss(d)))
end

local function scoreT2(t)
    local plan = TL.ato.CP + credit()
    local d = t - plan
    local ad = math.abs(d)
    local p
    if ad <= CFG.T2_GOOD then p = CFG.T2_PTS_GOOD
    elseif ad <= CFG.T2_OK then p = 0
    elseif d > 0 then p = CFG.T2_PTS_LATE
    else p = CFG.T2_PTS_EARLY end
    settle("T2", plan, t, p, string.format("%s at %s, plan %s (%s)", CFG.CP_NAME, clock(t), clock(plan), mmss(d)))
end

local function scoreT3(t, stillOnStation)
    local plan = TL.ato.VUL + credit()
    local d = t - plan
    local p
    if stillOnStation then p = CFG.T3_PTS_LATE
    elseif d <= 0 then p = CFG.T3_PTS_GOOD
    elseif d <= CFG.T3_LATE then p = 0
    else p = CFG.T3_PTS_LATE end
    local what = stillOnStation and "JTAC-2 not complete, still on station" or ("JTAC-2 complete " .. clock(t))
    settle("T3", plan, t, p, string.format("%s, VUL END %s (%s)", what, clock(plan), mmss(d)))
    setFlag(CFG.FLAGS.VUL)
end

local function settleT4(reason)
    local r = TL.m.T4
    if r.state then return end
    if TL.aborted then mark("T4", "void", "mission abort"); return end
    local mins = math.floor(TL.bingoSec / 60)
    local p = math.max(CFG.T4_CAP, mins * CFG.T4_PTS_PER_MIN)
    local label = string.format("%d s below BINGO on station (%s)", math.floor(TL.bingoSec), reason)
    if not CFG.BINGO_CALIBRATED then
        settle("T4", nil, now(), 0, label .. string.format(", would %+d, BINGO uncalibrated", p))
    else
        settle("T4", nil, now(), p, label)
    end
end

local function voidOpen(why)
    if not TL.m.T2.state then mark("T2", "void", why) end
    if not TL.m.T3.state then mark("T3", "void", why) end
    settleT4(why)
end

-- ══════════════════════════════════════════════════════════════
--  TEXT: FLIGHT CARD / TIMELINE / DEBRIEF
-- ══════════════════════════════════════════════════════════════
local function bingoAtCP()
    local d = carrierDistNm(TL.ato.cpPos)
    if not d then return nil end
    return bingoLb(d)
end

local function cardText()
    local A, c = TL.ato, credit()
    local L = {}
    L[#L + 1] = string.format("CAS-1 FLIGHT CARD   local times   credit %s   [%s]", mmss(c),
        CFG.SCORING and "SCORING" or "SHADOW: logged, not scored")
    L[#L + 1] = string.format("T0  MAN-UP                %s", clock(A.T0))
    L[#L + 1] = string.format("M1  ENGINES RUNNING by    %s   +%d", clock(A.M1 + c), CFG.M1_PTS)
    L[#L + 1] = string.format("M2  CHECKS DONE by        %s   +%d", clock(A.M2 + c), CFG.M2_PTS)
    L[#L + 1] = string.format("L   CAT SHOT              %s   -1:00/+2:00 +%d", clock(A.L + c), CFG.T1_PTS_GOOD)
    L[#L + 1] = string.format("CP  %-21s %s   +/-2:00 +%d   (L%s, %s)", CFG.CP_NAME, clock(A.CP + c),
        CFG.T2_PTS_GOOD, mmss(A.ete), A.src)
    L[#L + 1] = string.format("VUL END (JTAC-2 done)     %s   +%d", clock(A.VUL + c), CFG.T3_PTS_GOOD)
    local bcp = bingoAtCP()
    L[#L + 1] = string.format("BINGO = %.1f + %.3f x NM to Mother (k lb)%s", CFG.ARR_RESERVE_LB / 1000,
        CFG.BURN_LB_PER_NM / 1000, CFG.BINGO_CALIBRATED and "" or "   [PLACEHOLDER, uncalibrated]")
    if bcp then
        L[#L + 1] = string.format("at %s: BINGO %.1f  JOKER %.1f", CFG.CP_NAME, bcp / 1000, (bcp + CFG.JOKER_MARGIN_LB) / 1000)
    end
    local u = hero()
    if u and TL.launched and not TL.landed then
        local lb = fuelLb(u)
        local d = carrierDistNm(u:getPoint())
        if lb and d then
            local b = bingoLb(d)
            local tos = math.max(0, math.floor((lb - b) / CFG.BURN_ON_STATION_LB_MIN))
            L[#L + 1] = string.format("NOW: state %.1f  BINGO %.1f  JOKER %.1f  TOS ~%d min", lb / 1000, b / 1000,
                (b + CFG.JOKER_MARGIN_LB) / 1000, tos)
        end
    end
    L[#L + 1] = string.format("Timing sum %+d   cap [%d, %+d]", TL.sum, CFG.CAP_MIN, CFG.CAP_MAX)
    return table.concat(L, "\n")
end

local function timelineText(title)
    local L = { title or string.format("CAS-1 TIMELINE   credit %s (threat %s, failure %s)", mmss(credit()),
        mmss(TL.credit.threat), mmss(TL.credit.fail)) }
    for _, code in ipairs(ORDER) do
        local r = TL.m[code]
        local st
        if r.state == "done" then
            st = string.format("plan %s  act %s  %s  %+d", clock(r.plan), clock(r.act), mmss(r.dt), r.applied or 0)
            if code == "T4" then st = string.format("%s  %+d", r.note or "", r.applied or 0) end
        elseif r.state then
            st = string.format("%s: %s", string.upper(r.state), r.note or "")
        else
            st = "open"
        end
        L[#L + 1] = string.format("%-3s %-17s %s", code, NAMES[code], st)
    end
    if TL.winchester then L[#L + 1] = "WINCHESTER (A/G)  " .. clock(TL.winchester) end
    if TL.phaseT.JTAC1 then L[#L + 1] = "JTAC-1 start      " .. clock(TL.phaseT.JTAC1) end
    if TL.phaseT.J1_OFF then L[#L + 1] = "JTAC-1 complete   " .. clock(TL.phaseT.J1_OFF) end
    if TL.phaseT.J2_OFF then L[#L + 1] = "JTAC-2 complete   " .. clock(TL.phaseT.J2_OFF) end
    if TL.refuelT then L[#L + 1] = "Refuel contact    " .. clock(TL.refuelT) end
    L[#L + 1] = string.format("TIMING SUM %+d  [%s]", TL.sum, CFG.SCORING and "scored" or "shadow, not scored")
    return table.concat(L, "\n")
end

local function debrief()
    local txt = timelineText("CAS-1 TIMING DEBRIEF")
    for line in string.gmatch(txt, "[^\n]+") do log("DEBRIEF " .. line) end
    timer.scheduleFunction(function() msg(txt, CFG.DEBRIEF_DUR) end, nil, now() + CFG.DEBRIEF_DELAY)
end

-- ══════════════════════════════════════════════════════════════
--  EVENTS
-- ══════════════════════════════════════════════════════════════
local function isHero(obj)
    if not obj or not obj.getName then return false end
    local ok, n = pcall(function() return obj:getName() end)
    return ok and n == CFG.PLAYER_UNIT
end

local function onLaunch(t, how)
    if TL.launched then return end
    TL.launched = t
    setFlag(CFG.FLAGS.LAUNCH)
    log(string.format("LAUNCH %s (%s)", clock(t), how))
    if not TL.m.M1.state then
        if TL.engEvt then
            scoreGround("M1", TL.engEvt, TL.ato.M1, CFG.M1_PTS, "engines", "S_EVENT_ENGINE_STARTUP")
        else
            mark("M1", "n/a", "no engine start seen", TL.ato.M1)
        end
    end
    if not TL.m.M2.state then
        mark("M2", "n/a", TRT.PlaneCaptain and "PlaneCaptain checks not completed" or "PlaneCaptain not loaded", TL.ato.M2)
    end
    scoreT1(t)
end

local function onLand(t, place)
    if not TL.launched or TL.landed then return end
    TL.landed = t
    log(string.format("LAND %s at %s", clock(t), tostring(place)))
    if not TL.m.T2.state then
        if TL.aborted then mark("T2", "void", "mission abort") else mark("T2", "n/a", CFG.CP_NAME .. " not reached") end
    end
    if not TL.m.T3.state then
        if TL.aborted then mark("T3", "void", "mission abort") else mark("T3", "n/a", "JTAC-2 not complete") end
    end
    settleT4("landed")
    log(string.format("SUMMARY sum=%+d credit=%s threat=%s fail=%s scoring=%s", TL.sum, mmss(credit()),
        mmss(TL.credit.threat), mmss(TL.credit.fail), tostring(CFG.SCORING)))
    debrief()
end

local EH = {}
function EH:onEvent(e)
    if not e then return end
    local ok, err = pcall(function()
        local id = e.id
        if id == world.event.S_EVENT_SHOT then
            local w = e.weapon
            if not w then return end
            local okC, side = pcall(function() return e.initiator:getCoalition() end)
            if not okC or side ~= coalition.side.RED then return end
            local okT, tgt = pcall(function() return w:getTarget() end)
            if okT and isHero(tgt) then
                local okN, wn = pcall(function() return w:getTypeName() end)
                local okI, iname = pcall(function() return e.initiator:getName() end)
                TL.missiles[#TL.missiles + 1] = { w = w, t0 = now() }
                log(string.format("THREAT missile at hero: %s from %s", okN and tostring(wn) or "?", okI and tostring(iname) or "?"))
            end
            return
        end
        if not isHero(e.initiator) then return end
        if id == world.event.S_EVENT_BIRTH then
            TL.birth = TL.birth or now()
            log("BIRTH " .. clock(now()))
        elseif id == world.event.S_EVENT_ENGINE_STARTUP then
            if not TL.engEvt then
                TL.engEvt = now()
                log("ENGINE_STARTUP " .. clock(TL.engEvt))
                -- without PlaneCaptain the event is the only engine source: settle now
                if not TRT.PlaneCaptain and not TL.m.M1.state and not TL.launched then
                    scoreGround("M1", TL.engEvt, TL.ato.M1, CFG.M1_PTS, "engines", "S_EVENT_ENGINE_STARTUP")
                end
            end
        elseif id == world.event.S_EVENT_TAKEOFF then
            onLaunch(now(), "S_EVENT_TAKEOFF")
        elseif id == world.event.S_EVENT_LAND then
            local pn = "?"
            if e.place and e.place.getName then
                local okP, n = pcall(function() return e.place:getName() end)
                if okP then pn = n end
            end
            onLand(now(), pn)
        elseif id == world.event.S_EVENT_REFUELING then
            TL.refueling = true
            TL.refuelT = TL.refuelT or now()
            log("REFUELING start " .. clock(now()))
        elseif id == world.event.S_EVENT_REFUELING_STOP then
            TL.refueling = false
            log("REFUELING stop " .. clock(now()))
        end
    end)
    if not ok then log("event error: " .. tostring(err)) end
end
world.addEventHandler(EH)

-- ══════════════════════════════════════════════════════════════
--  TICK
-- ══════════════════════════════════════════════════════════════
local function redFighterClose(pPos)
    local groups = coalition.getGroups(coalition.side.RED, Group.Category.AIRPLANE) or {}
    for _, g in ipairs(groups) do
        for _, u in ipairs(g:getUnits() or {}) do
            if u and u:isExist() and u:inAir() then
                local fighter = false
                for _, a in ipairs(CFG.FIGHTER_ATTRS) do
                    if u:hasAttribute(a) then fighter = true; break end
                end
                if fighter and distNm(pPos, u:getPoint()) <= CFG.THREAT_CLOSE_NM then
                    return u:getName()
                end
            end
        end
    end
    return nil
end

local function threatState(pPos, t)
    local alive = {}
    local why = nil
    for _, m in ipairs(TL.missiles) do
        local okE, ex = pcall(function() return m.w:isExist() end)
        if okE and ex and (t - m.t0) <= CFG.MISSILE_TTL then
            alive[#alive + 1] = m
            why = why or "missile in flight"
        end
    end
    TL.missiles = alive
    if not why and trigger.misc.getUserFlag(CFG.INJ1_FLAG) == 1 then why = "INJ-1 abort hold" end
    if not why and pPos then
        local n = redFighterClose(pPos)
        if n then why = "bandit " .. n .. " <= " .. CFG.THREAT_CLOSE_NM .. " NM" end
    end
    return why
end

local function agCount(u)
    local ok, ammo = pcall(function() return u:getAmmo() end)
    if not ok or type(ammo) ~= "table" then return nil end
    local W, MC = Weapon and Weapon.Category, Weapon and Weapon.MissileCategory
    if not W then return nil end
    local n = 0
    for _, a in ipairs(ammo) do
        local d = a.desc or {}
        local cat = d.category
        local ag = (cat == W.BOMB) or (cat == W.ROCKET)
            or (cat == W.MISSILE and not (MC and d.missileCategory == MC.AAM))
        if ag then n = n + (a.count or 0) end
    end
    return n
end

local function tick()
    local t = now()
    local dt = TL.lastTick and math.max(0, math.min(t - TL.lastTick, 10)) or 0
    TL.lastTick = t
    local u = hero()
    local p = u and u:getPoint() or nil

    -- failure credit (ME failures, deterministic)
    for _, f in ipairs(TL.fails) do
        if not f.done and t >= f.at then
            f.done = true
            TL.credit.fail = TL.credit.fail + CFG.FAIL_CREDIT_S
            log(string.format("CREDIT failure %s window reached %s: +%d s (total %s)", tostring(f.id), clock(t),
                CFG.FAIL_CREDIT_S, mmss(credit())))
        end
    end

    -- threat credit
    if u and not TL.landed then
        local why = threatState(p, t)
        if why then
            if TL.credit.threat < CFG.THREAT_CREDIT_MAX then
                TL.credit.threat = math.min(CFG.THREAT_CREDIT_MAX, TL.credit.threat + dt)
            end
            if not TL.engaged then log("ENGAGED start " .. clock(t) .. ": " .. why) end
        elseif TL.engaged then
            log(string.format("ENGAGED end %s, threat credit %s", clock(t), mmss(TL.credit.threat)))
        end
        TL.engaged, TL.engagedWhy = (why ~= nil), why
    end

    -- Comms_Director phase / abort / JTAC-2
    local cd = cdState()
    if cd then
        if cd.phase ~= TL.phase then
            TL.phase = cd.phase
            if not TL.phaseT[cd.phase] then TL.phaseT[cd.phase] = t end
            log("phase " .. tostring(cd.phase) .. " " .. clock(t))
        end
        if cd.aborted and not TL.aborted then
            TL.aborted = t
            log("MISSION ABORT " .. clock(t))
            voidOpen("mission abort")
        end
        if not TL.m.T3.state and not TL.aborted and cd.deadJ2 then
            local tj2 = absToElapsed(cd.j2 and cd.j2.tot) or t
            scoreT3(tj2, false)
        end
    end

    -- PlaneCaptain milestones (before launch)
    local PC = TRT.PlaneCaptain
    if not TL.launched and type(PC) == "table" and type(PC.milestones) == "table" then
        if not TL.m.M1.state and PC.milestones.START then
            scoreGround("M1", PC.milestones.START, TL.ato.M1, CFG.M1_PTS, "engines", "PlaneCaptain START")
        end
        if not TL.m.M2.state and PC.milestones.CHECKS then
            scoreGround("M2", PC.milestones.CHECKS, TL.ato.M2, CFG.M2_PTS, "checks", "PlaneCaptain CHECKS")
        end
    end

    if not u then return end

    -- launch fallback (carrier TAKEOFF events can be missing)
    if not TL.launched then
        local v = u:getVelocity()
        local spd = v and math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) or 0
        if u:inAir() and spd > 41 then onLaunch(t, "airborne fallback") end
        if not TL.launched then return end
    end
    if TL.landed then return end

    -- CP
    local dCP = distNm(p, TL.ato.cpPos)
    if not TL.cpReached and dCP <= CFG.CP_RADIUS_NM then
        TL.cpReached = t
        setFlag(CFG.FLAGS.CP)
        if TL.aborted then mark("T2", "void", "mission abort") else scoreT2(t) end
    end

    -- VUL END timeout: still on station 10 min after VUL END
    if not TL.m.T3.state and not TL.aborted and TL.cpReached then
        local plan = TL.ato.VUL + credit()
        local onStation = (cd and STATION_PH[cd.phase]) or (not cd and dCP <= CFG.STATION_NM)
        if onStation and t > plan + CFG.T3_LATE then scoreT3(t, true) end
        if t > plan then setFlag(CFG.FLAGS.VUL) end
    end

    -- fuel: log, JOKER/BINGO, T4
    local lb, raw, maxKg = fuelLb(u)
    local dCV = carrierDistNm(p)
    if lb and dCV then
        if not TL.fuelInit then
            TL.fuelInit = true
            log(string.format("FUEL INIT raw getFuel=%.4f fuelMassMax=%s kg -> %.0f lb", raw, tostring(maxKg), lb))
        end
        local bingo = bingoLb(dCV)
        local joker = bingo + CFG.JOKER_MARGIN_LB
        local phase = cd and cd.phase or "?"
        if not TL.lastFuelLog or t - TL.lastFuelLog >= CFG.FUEL_LOG_EVERY then
            TL.lastFuelLog = t
            local v = u:getVelocity()
            local gs = v and math.sqrt(v.x * v.x + v.z * v.z) * 1.94384 or 0
            log(string.format("FUEL %s lb=%.0f raw=%.4f distCVN=%.1f distCP=%.1f alt=%.0f gs=%.0f bingo=%.0f phase=%s",
                clock(t), lb, raw, dCV, dCP, p.y * 3.28084, gs, bingo, phase))
        end
        local inMission = (cd and MISSION_PH[cd.phase]) or (not cd)
        if inMission and not TL.aborted then
            if not TL.joker and lb < joker then
                TL.joker = true; setFlag(CFG.FLAGS.JOKER)
                log(string.format("JOKER %s lb=%.0f joker=%.0f", clock(t), lb, joker))
                if CFG.FUEL_CALLS then msg(string.format("[TL] JOKER, state %.1f", lb / 1000), 10) end
            end
            if not TL.bingo and lb < bingo then
                TL.bingo = true; setFlag(CFG.FLAGS.BINGO)
                log(string.format("BINGO %s lb=%.0f bingo=%.0f", clock(t), lb, bingo))
                if CFG.FUEL_CALLS then msg(string.format("[TL] BINGO, state %.1f", lb / 1000), 10) end
            end
        end
        -- T4: on station, below BINGO, not refuelling
        if not TL.m.T4.state and TL.cpReached then
            local ended = (cd and END_PH[cd.phase]) or dCP > CFG.STATION_LEFT_NM
            if ended then
                settleT4(cd and END_PH[cd.phase] and ("phase " .. cd.phase) or "left station")
            elseif dCP <= CFG.STATION_NM and not TL.refueling and not (cd and cd.phase == "REFUEL")
                and lb < bingo then
                TL.bingoSec = TL.bingoSec + dt
            end
        end
    end

    -- WINCHESTER (A/G stores)
    if not TL.lastAmmo or t - TL.lastAmmo >= CFG.AMMO_EVERY then
        TL.lastAmmo = t
        local n = agCount(u)
        if n then
            if not TL.agMax or n > TL.agMax then TL.agMax = n end
            if n ~= TL.ag then log(string.format("A/G stores %s -> %d", clock(t), n)) end
            TL.ag = n
            if n == 0 and (TL.agMax or 0) > 0 and not TL.winchester then
                TL.winchester = t
                log("WINCHESTER " .. clock(t))
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  START
-- ══════════════════════════════════════════════════════════════
TL.ato = buildATO()
readFailures()
log(string.format("v%s loaded. Player unit: %s. ATO (%s): T0 %s | M1 %s | M2 %s | L %s | CP %s (ETE %s) | VUL END %s | scoring=%s",
    CFG.VERSION, CFG.PLAYER_UNIT, TL.ato.src, clock(TL.ato.T0), clock(TL.ato.M1), clock(TL.ato.M2), clock(TL.ato.L),
    clock(TL.ato.CP), mmss(TL.ato.ete), clock(TL.ato.VUL), tostring(CFG.SCORING)))

timer.scheduleFunction(function(_, t)
    local ok, err = pcall(tick)
    if not ok then log("tick error: " .. tostring(err)) end
    return t + CFG.TICK
end, nil, timer.getTime() + 1)

if TRT.Menu and TRT.Menu.Register then
    TRT.Menu.Register("INFO", "TL", function()
        return {
            { "Show: flight card", function() msg(cardText(), 30) end },
            { "Show: timeline",    function() msg(timelineText(), 30) end },
        }
    end, CFG.MENU_ORDER)
else
    log("TRT.Menu missing (Menu_Manager not loaded before Flight_Timeline) -> no F10 items")
end

-- the briefing line the pilot sees once in the cockpit
timer.scheduleFunction(function()
    msg(cardText() .. "\nF10 > INFO > Show: flight card", 30)
end, nil, timer.getTime() + 15)

TL.card, TL.timeline = cardText, timelineText
