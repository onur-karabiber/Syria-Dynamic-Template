-- Comms_Director | v1.0.1
--[[
  CAS-1 Communications State Machine — Syria Dynamic Template
  Scope: DEPARTURE check-in · OVERLORD picture · INJ-1..4 · RTB corridor
  Out of scope: JTAC comms (native DCS JTAC preserved, do not touch)

  PHASE FLOW
  ──────────────────────────────────────────────────────────────
    IDLE  →  DEPARTED  →  ENROUTE  →  CAS_ALPHA  →  CAS_BRAVO
      →  RTB  →  RECOVERY  →  DONE

  INJECTS
    INJ-1  Abort (30%, JTAC-2 / pass 2-3):   Eyeball "abort, abort, abort"
    INJ-2  IFF sour (15%, DEP check-in):      Strike "Mode 4 SOUR, recycle"
    INJ-3  MANPADS (25%, JTAC-2 before p3):  Eyeball hard-deck → 20 000 ft
    INJ-4  Corridor dev (auto, 80-50 NM):     Strike "outside corridor"

  FLAGS  (do not conflict with existing ME triggers)
    100  = departure CASE (3 = CASE III — pre-set, DO NOT WRITE)
    200  = hard-deck code  0=idle  1=JTAC1/12k  2=JTAC2/18k  3=JTAC2+MANPADS/20k
    201  = INJ-1 state     0=clear  1=abort active  2=re-cleared
    202  = INJ-2 fired
    203  = INJ-3 fired (MANPADS)
    204  = INJ-4 fired (corridor deviation)
    205  = RTB corridor passed clean (set when player exits inner boundary clean)

  LOADING
    Place Comms_Director.lua in scripts/.
    Add "Do Script File" → Comms_Director.lua in ME (ONCE, at mission start).
    Requires: DCS base Lua API, coord.*  (no external libraries).
]]

-- ══════════════════════════════════════════════════════════════
--  CONFIG  — update unit/group names to match ME exactly
-- ══════════════════════════════════════════════════════════════
local CFG = {
    -- ME unit / group names
    PLAYER_UNIT    = "CAS-1",         -- player aircraft unit name  [ME: group CAS-1, unit 1]
    CARRIER_UNIT   = "CVN",          -- carrier ship unit name     [ME: UNIT NAME = CVN]
    PLAYER_GRP     = "CAS-1",        -- player group name (for F10 menu)

    -- Target reference (tries unit first, falls back to lat/lon)
    -- Set to nil if no named unit; script will use lat/lon.
    TGT_A_UNIT     = nil,            -- e.g. "SA-13 Alpha-1"
    TGT_B_UNIT     = nil,            -- e.g. "SA-8 Bravo-1"

    -- Fallback lat/lon (degrees) — verify against ME placement
    -- BV 6187 2081 → approximate; adjust after confirming in ME
    TGT_A_LAT      =  36.521,
    TGT_A_LON      =  38.432,
    -- YE 5987 3843 → approximate
    TGT_B_LAT      =  36.142,
    TGT_B_LON      =  35.984,

    -- Phase proximity thresholds (NM)
    ALPHA_RADIUS   = 40,
    BRAVO_RADIUS   = 40,
    RECOVERY_NM    = 50,

    -- Departure detection
    DEP_ALT_M      = 100,            -- ~330 ft; altitude in metres
    DEP_SPD_MS     = 41,             -- ~80 kts; speed in m/s
    DEP_HOLD_SECS  = 20,             -- seconds airborne before firing dep seq
    DEP_ENROUTE_S  = 60,             -- seconds after departure before ENROUTE

    -- RTB corridor (TRUE degrees; Syria mag var ≈ +5° → 050M = 055T)
    CORRIDOR_TRUE  = 55,             -- bearing FROM carrier TO player (true)
    CORRIDOR_HALF  = 15,             -- ±15° tolerance
    CORRIDOR_OUT   = 80,             -- outer boundary (NM)
    CORRIDOR_IN    = 50,             -- inner boundary (NM) — AIRBOSS takes over

    -- Inject probabilities (integer 0–100)
    PROB_INJ1      = 30,
    PROB_INJ2      = 15,
    PROB_INJ3      = 25,

    -- Scheduler
    TICK           = 5,              -- main tick interval (seconds)

    -- Text display durations (seconds)
    DUR_SHORT      = 8,
    DUR_LONG       = 16,
    DUR_URGENT     = 12,
}

-- ══════════════════════════════════════════════════════════════
--  MODULE STATE
-- ══════════════════════════════════════════════════════════════
local CD = {
    phase         = "IDLE",
    depTs         = nil,             -- timer.getTime() when airborne confirmed
    departedTs    = nil,             -- timer.getTime() when DEPARTED phase entered
    queue         = {},              -- clip queue; each = {text, dur, after, audio}
    qPlaying      = false,
    qTimer        = nil,             -- timer handle (informational; not cancellable)
    tgtA          = nil,             -- vec3 position of Target Alpha (cached)
    tgtB          = nil,             -- vec3 position of Target Bravo (cached)
    visitedAlpha  = false,
    visitedBravo  = false,
    corridorArmed = false,
    corridorDone  = false,
    overlordClock = 0,
    inj           = { i1=false, i2=false, i3=false },  -- fired flags
}

-- ══════════════════════════════════════════════════════════════
--  UTILITIES
-- ══════════════════════════════════════════════════════════════
local function MtoNM(m)   return m  / 1852 end
local function NMtoM(nm)  return nm * 1852 end
local function Roll(pct)  return math.random(1, 100) <= pct end

local function Player()   return Unit.getByName(CFG.PLAYER_UNIT)  end
local function Carrier()  return Unit.getByName(CFG.CARRIER_UNIT) end

--- 2-D distance in NM between two DCS vec3 points (ignores altitude)
local function Dist2D(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return MtoNM(math.sqrt(dx * dx + dz * dz))
end

--- True bearing (°) from point A to point B (0 = north)
local function Bearing(a, b)
    return math.deg(math.atan2(b.x - a.x, b.z - a.z)) % 360
end

--- Signed angle difference, normalised to –180 … +180
local function ADiff(a, b)
    local d = (a - b + 360) % 360
    return (d > 180) and (d - 360) or d
end

--- Display text to player group only
local function Msg(text, dur, clear)
    local p = Player(); if not p then return end
    trigger.action.outTextForGroup(
        p:getGroup():getID(), text, dur or CFG.DUR_SHORT, clear or false)
end

--- DCS flag helpers
local function SetFlag(f, v)  trigger.action.setUserFlag(tostring(f), v) end
local function GetFlag(f)     return trigger.misc.getUserFlag(tostring(f)) end

-- ══════════════════════════════════════════════════════════════
--  CLIP QUEUE
-- ══════════════════════════════════════════════════════════════
--- Push a clip to the end of the queue.
-- @param text   String displayed as radio call subtitle.
-- @param dur    Display duration in seconds.
-- @param after  Gap after the PREVIOUS clip ends before this one fires (s).
-- @param audio  Optional .ogg filename. Uncomment outSoundForGroup line
--               once .ogg files are present in sounds/ inside the .miz.
local function Q(text, dur, after, audio)
    table.insert(CD.queue, {
        text  = text,
        dur   = dur   or CFG.DUR_SHORT,
        after = after or 1,
        audio = audio,
    })
end

--- Push a clip to the FRONT of the queue (priority / urgent).
local function QU(text, dur, audio)
    table.insert(CD.queue, 1, {
        text  = text,
        dur   = dur   or CFG.DUR_URGENT,
        after = 0,
        audio = audio,
    })
end

--- Fire the next clip.
local function QFire()
    if #CD.queue == 0 then
        CD.qPlaying = false
        return
    end
    local clip = table.remove(CD.queue, 1)
    Msg(clip.text, clip.dur)
    -- outSoundForGroup: enable when .ogg files are embedded in .miz
    -- if clip.audio then
    --     local p = Player()
    --     if p then trigger.action.outSoundForGroup(p:getGroup():getID(), clip.audio) end
    -- end
    CD.qPlaying = true
    local delay = clip.dur + clip.after
    timer.scheduleFunction(function(_, t)
        CD.qPlaying = false
        QFire()
    end, nil, timer.getTime() + delay)
end

--- Start queue if not already running.
local function QPlay()
    if not CD.qPlaying and #CD.queue > 0 then QFire() end
end

--- Flush queue (abort / emergency use only).
local function QClear()
    CD.queue    = {}
    CD.qPlaying = false
end

-- ══════════════════════════════════════════════════════════════
--  SCRIPTS (radio calls)
-- ══════════════════════════════════════════════════════════════
-- Departure ───────────────────────────────────────────────────
local function S_DepOpen()
    Q("[STRIKE] HORNET 51, STRIKE. Check Mode 4.", 9, 0)
end
local function S_IFFSour()
    QU("[STRIKE] HORNET 51, Mode 4 SOUR. Recycle.", 10)
end
local function S_IFFSweet()
    Q("[STRIKE] HORNET 51, Mode 4 sweet. Fragged: Target Alpha—Pointer 11, then Bravo—Eyeball 11.", 14, 3)
end
local function S_IFFSweetClean()   -- no prior sour
    Q("[STRIKE] HORNET 51, Mode 4 sweet.", 8, 0)
    Q("[STRIKE] Fragged: Target Alpha—Pointer 11, then Target Bravo—Eyeball 11. Good hunting.", 14, 2)
end

-- OVERLORD ────────────────────────────────────────────────────
local function S_OvldInitial()
    Q("[OVERLORD] HORNET 51, OVERLORD. Picture: SA-13 active BV 62, SA-8 active YE 53. "
    .."Remain above 18,000 feet transiting YE 53. Advise feet wet on egress.", 18, 4)
end
local function S_OvldUpdate()
    Q("[OVERLORD] HORNET 51, OVERLORD. SA-8 still active YE 53. No change to picture.", 12, 0)
end
local function S_OvldAlpha()
    Q("[OVERLORD] HORNET 51, threat update. SA-13 active BV 62. Pointer 11 on station.", 12, 0)
end
local function S_OvldRTB()
    Q("[OVERLORD] HORNET 51, feet wet. RTB 050 corridor, ±15. Check in with Strike.", 12, 0)
end

-- Strike RTB / tanker ─────────────────────────────────────────
local function S_StrikeRTB()
    Q("[STRIKE] HORNET 51, STRIKE. Good work. RTB 050 corridor. "
    .."Texaco 11 on station 252.1. Switch Marshal at 50 miles.", 16, 2)
end

-- Injects ─────────────────────────────────────────────────────
local function S_Abort()
    QClear()
    QU("[EYEBALL 11] HORNET 51, abort, abort, abort. Civilian vehicle in target area. Ceasefire.", 14)
    SetFlag(201, 1)
end
local function S_Rearm()
    Q("[EYEBALL 11] HORNET 51, area is clear. Resume as briefed.", 10, 6)
    SetFlag(201, 2)
end
local function S_Manpads()
    QU("[EYEBALL 11] HORNET 51, MANPADS threat 1 klick east. Hard deck now 20,000.", 13)
    SetFlag(200, 3)
    SetFlag(203, 1)
end
local function S_CorridorDev()
    QU("[STRIKE] HORNET 51, STRIKE. You are OUTSIDE the return corridor. Turn now for the 050 radial.", 13)
    SetFlag(204, 1)
end

-- ══════════════════════════════════════════════════════════════
--  INJECT EVALUATION
-- ══════════════════════════════════════════════════════════════
local function EvalInjects(phase)
    if phase == "DEPARTED" and not CD.inj.i2 then
        -- INJ-2: IFF sour on Strike check-in
        timer.scheduleFunction(function()
            if CD.phase ~= "DEPARTED" and CD.phase ~= "ENROUTE" then return end
            if Roll(CFG.PROB_INJ2) then
                CD.inj.i2 = true
                SetFlag(202, 1)
                S_IFFSour()
                QPlay()
                timer.scheduleFunction(function()
                    S_IFFSweet(); QPlay()
                end, nil, timer.getTime() + 16)
            else
                S_IFFSweetClean(); QPlay()
            end
        end, nil, timer.getTime() + 11)

    elseif phase == "ENROUTE" then
        timer.scheduleFunction(function()
            S_OvldInitial(); QPlay()
        end, nil, timer.getTime() + 6)

    elseif phase == "CAS_BRAVO" then
        -- INJ-3: MANPADS before pass 3 (~55-75s into Bravo phase)
        if not CD.inj.i3 then
            local d3 = 55 + math.random(0, 20)
            timer.scheduleFunction(function()
                if CD.phase == "CAS_BRAVO" and not CD.inj.i3 and Roll(CFG.PROB_INJ3) then
                    CD.inj.i3 = true
                    S_Manpads(); QPlay()
                end
            end, nil, timer.getTime() + d3)
        end
        -- INJ-1: Abort (pass 2 or 3; ~85-145s into Bravo phase)
        if not CD.inj.i1 then
            local d1 = 85 + math.random(0, 60)
            timer.scheduleFunction(function()
                if CD.phase == "CAS_BRAVO" and not CD.inj.i1 and Roll(CFG.PROB_INJ1) then
                    CD.inj.i1 = true
                    S_Abort(); QPlay()
                    -- Auto-rearm after 45s
                    timer.scheduleFunction(function()
                        if CD.phase == "CAS_BRAVO" or CD.phase == "RTB" then
                            S_Rearm(); QPlay()
                        end
                    end, nil, timer.getTime() + 45)
                end
            end, nil, timer.getTime() + d1)
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  OVERLORD PERIODIC
-- ══════════════════════════════════════════════════════════════
local OVLD_INTERVAL = 240   -- 4 minutes between unsolicited picture calls

local function OvldTick(dt)
    local p = CD.phase
    if p ~= "ENROUTE" and p ~= "CAS_ALPHA" then return end
    CD.overlordClock = CD.overlordClock + dt
    if CD.overlordClock >= OVLD_INTERVAL and not CD.qPlaying then
        CD.overlordClock = 0
        S_OvldUpdate(); QPlay()
    end
end

-- ══════════════════════════════════════════════════════════════
--  CORRIDOR MONITOR  (RTB phase only)
-- ══════════════════════════════════════════════════════════════
local function CorridorCheck()
    if CD.corridorDone then return end
    local p = Player(); local c = Carrier()
    if not p or not c then return end

    local pPos = p:getPoint()
    local cPos = c:getPoint()
    local dist = Dist2D(pPos, cPos)

    if dist > CFG.CORRIDOR_OUT then return end               -- not yet in window
    if dist < CFG.CORRIDOR_IN  then                          -- past inner boundary
        if not CD.corridorDone then
            SetFlag(205, 1)                                  -- passed clean
        end
        CD.corridorDone = true
        return
    end

    -- Inside 80-50 NM window: check radial
    CD.corridorArmed = true
    -- CORRIDOR_TRUE (55°T) is the bearing FROM carrier TO player.
    local brg   = Bearing(cPos, pPos)
    local delta = math.abs(ADiff(brg, CFG.CORRIDOR_TRUE))
    if delta > CFG.CORRIDOR_HALF then
        CD.corridorDone = true                               -- fire once
        S_CorridorDev(); QPlay()
    end
end

-- ══════════════════════════════════════════════════════════════
--  PHASE STATE MACHINE
-- ══════════════════════════════════════════════════════════════
local function SetPhase(new)
    if CD.phase == new then return end
    env.info(string.format("[CD] %s → %s", CD.phase, new))
    CD.phase = new

    if new == "DEPARTED" then
        CD.departedTs = timer.getTime()
        S_DepOpen(); QPlay()
        EvalInjects("DEPARTED")

    elseif new == "ENROUTE" then
        SetFlag(200, 0)
        EvalInjects("ENROUTE")

    elseif new == "CAS_ALPHA" then
        CD.visitedAlpha = true
        SetFlag(200, 1)   -- hard deck code: JTAC-1 / 12 000 ft
        S_OvldAlpha(); QPlay()

    elseif new == "CAS_BRAVO" then
        CD.visitedBravo = true
        SetFlag(200, 2)   -- hard deck code: JTAC-2 / 18 000 ft
        EvalInjects("CAS_BRAVO")

    elseif new == "RTB" then
        SetFlag(200, 0)
        S_OvldRTB(); QPlay()
        timer.scheduleFunction(function()
            S_StrikeRTB(); QPlay()
        end, nil, timer.getTime() + 14)

    elseif new == "RECOVERY" then
        QClear()
        -- AIRBOSS (native DCS, 305 FM) takes over from here.
        env.info("[CD] RECOVERY phase — AIRBOSS active, CD standing down.")
    end
end

local function EvalPhase(pUnit, cUnit, dt)
    local pPos = pUnit:getPoint()
    local vel  = pUnit:getVelocity()
    local spd  = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
    local alt  = pPos.y   -- DCS y = altitude (metres MSL; carrier deck ≈ 20 m)

    -- IDLE: wait for takeoff
    if CD.phase == "IDLE" then
        if alt > CFG.DEP_ALT_M and spd > CFG.DEP_SPD_MS then
            if not CD.depTs then
                CD.depTs = timer.getTime()
            elseif timer.getTime() - CD.depTs >= CFG.DEP_HOLD_SECS then
                SetPhase("DEPARTED")
            end
        else
            CD.depTs = nil
        end

    -- DEPARTED: hold until departure sequence has had time to play
    elseif CD.phase == "DEPARTED" then
        if CD.departedTs and timer.getTime() - CD.departedTs >= CFG.DEP_ENROUTE_S then
            SetPhase("ENROUTE")
        end

    -- ENROUTE: watch for Alpha proximity
    elseif CD.phase == "ENROUTE" then
        if CD.tgtA and Dist2D(pPos, CD.tgtA) <= CFG.ALPHA_RADIUS then
            SetPhase("CAS_ALPHA")
        end

    -- CAS_ALPHA: transition to Bravo when left Alpha AND entered Bravo
    elseif CD.phase == "CAS_ALPHA" then
        if CD.tgtA and CD.tgtB then
            local dA = Dist2D(pPos, CD.tgtA)
            local dB = Dist2D(pPos, CD.tgtB)
            if dA > CFG.ALPHA_RADIUS and dB <= CFG.BRAVO_RADIUS then
                SetPhase("CAS_BRAVO")
            end
        end

    -- CAS_BRAVO: transition to RTB when left Bravo area
    elseif CD.phase == "CAS_BRAVO" then
        if CD.tgtB and CD.visitedBravo then
            if Dist2D(pPos, CD.tgtB) > CFG.BRAVO_RADIUS then
                SetPhase("RTB")
            end
        end

    -- RTB: corridor monitor + recovery transition
    elseif CD.phase == "RTB" then
        CorridorCheck()
        if cUnit then
            local cPos = cUnit:getPoint()
            if Dist2D(pPos, cPos) <= CFG.RECOVERY_NM then
                SetPhase("RECOVERY")
            end
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  MAIN TICK
-- ══════════════════════════════════════════════════════════════
local CD_prevTick = 0

local function CD_Tick(_, t)
    if CD.phase == "DONE" or CD.phase == "RECOVERY" then return end

    local dt = t - CD_prevTick
    CD_prevTick = t

    local p = Player()
    if not p then return t + CFG.TICK end    -- not yet in slot / dead; retry

    EvalPhase(p, Carrier(), dt)
    OvldTick(dt)

    return t + CFG.TICK   -- reschedule
end

-- ══════════════════════════════════════════════════════════════
--  F10 MENU
-- ══════════════════════════════════════════════════════════════
local function BuildMenu()
    local p = Player(); if not p then return false end
    local gid = p:getGroup():getID()
    local root = missionCommands.addSubMenuForGroup(gid, "CAS-1 COMMS")

    missionCommands.addCommandForGroup(gid, "OVERLORD — request picture", root,
        function()
            local ph = CD.phase
            if ph=="ENROUTE" or ph=="CAS_ALPHA" or ph=="CAS_BRAVO" or ph=="RTB" then
                S_OvldUpdate(); QPlay(); CD.overlordClock = 0
            else
                Msg("[OVERLORD] Not available in current phase.", 7)
            end
        end)

    missionCommands.addCommandForGroup(gid, "TEXACO — check-in", root,
        function()
            local ph = CD.phase
            if ph=="RTB" or ph=="CAS_BRAVO" then
                Q("[TEXACO 11] HORNET 51, Texaco 11. Come right, heading 270. Call pre-contact.", 12, 0)
                QPlay()
            else
                Msg("[TEXACO 11] Not yet on station.", 7)
            end
        end)

    missionCommands.addCommandForGroup(gid, "Show: Current hard deck", root,
        function()
            local lut = {
                [0] = "Hard deck: transit / not CAS-active",
                [1] = "Hard deck: 12,000 ft AGL  (Target Alpha / JTAC-1)",
                [2] = "Hard deck: 18,000 ft AGL  (Target Bravo / JTAC-2)",
                [3] = "Hard deck: 20,000 ft AGL  (JTAC-2 + MANPADS active)",
            }
            Msg("[CAS-1] " .. (lut[GetFlag(200)] or "Unknown"), CFG.DUR_SHORT)
        end)

    missionCommands.addCommandForGroup(gid, "Show: Comm ladder", root,
        function()
            Msg(
                "── CAS-1 COMM LADDER ──────────────────\n"
             .. "COMM1-01  127.60 AM   DEPARTURE\n"
             .. "COMM1-03  265.00 AM   STRIKE\n"
             .. "COMM1-04  333.30 AM   POINTER 11  (JTAC-1)\n"
             .. "COMM1-05  333.40 AM   EYEBALL 11  (JTAC-2)\n"
             .. "COMM1-06  251.10 AM   OVERLORD\n"
             .. "COMM1-07  252.10 AM   TEXACO 11\n"
             .. "COMM2-01  305.00 FM   MARSHAL  (switch at 50 NM)",
            CFG.DUR_LONG)
        end)
    return true
end

-- ══════════════════════════════════════════════════════════════
--  INIT
-- ══════════════════════════════════════════════════════════════
local function CD_Init()
    pcall(math.randomseed, timer.getAbsTime()) -- DCS sandbox: randomseed may not be available

    -- Resolve target positions: named unit → coord.LLtoLO fallback
    local function TgtPos(unitName, lat, lon)
        if unitName then
            local u = Unit.getByName(unitName)
            if u then return u:getPoint() end
            env.warning("[CD] Unit '" .. unitName .. "' not found — using lat/lon fallback.")
        end
        local ok, v = pcall(coord.LLtoLO, lat, lon, 0)
        if ok then return v end
        env.error("[CD] coord.LLtoLO failed for lat=" .. lat .. " lon=" .. lon)
        return nil
    end

    CD.tgtA = TgtPos(CFG.TGT_A_UNIT, CFG.TGT_A_LAT, CFG.TGT_A_LON)
    CD.tgtB = TgtPos(CFG.TGT_B_UNIT, CFG.TGT_B_LAT, CFG.TGT_B_LON)

    if not CD.tgtA then env.warning("[CD] WARN: TGT_A position unavailable — CAS_ALPHA transition disabled.") end
    if not CD.tgtB then env.warning("[CD] WARN: TGT_B position unavailable — CAS_BRAVO transition disabled.") end

    -- Build F10 menu (retry until player is in slot)
    local function TryMenu(_, t)
        if not BuildMenu() then return t + 5 end   -- retry in 5 s
    end
    timer.scheduleFunction(TryMenu, nil, timer.getTime() + 5)

    -- Start main tick
    CD_prevTick = timer.getTime()
    timer.scheduleFunction(CD_Tick, nil, timer.getTime() + CFG.TICK)

    env.info("[CD] Comms_Director v1.0.0 online — CAS-1 Syria")
end

-- ═══════════════════════════ ENTRY ════════════════════════════
CD_Init()
