-- Comms_Director | v1.2.0
--[[
  CAS-1 Communications State Machine — Syria Dynamic Template
  Scope: Departure→Strike→OVERLORD hand-offs · JTAC hand-offs · INFLTREP · TANKER
         · RTB (OVERLORD→Strike→Marshal) · INJ-1..4
  Out of scope: JTAC comms themselves (native DCS JTAC check-in / 9-line / clearance
                preserved, do not touch)

  v1.2.0 — realistic C2 flow (JP 3-09.3 Ch V + CV ops practice)
    * Pilot-initiated check-ins via F10. No agency talks to the player until the
      player has checked in on its frequency. Only directive hand-offs ("switch X"),
      threat/abort calls and corridor violations are controller-initiated.
    * Hand-offs are position-gated, not time-gated:
        Departure → Strike    ≥ DEP_HANDOFF_NM from the carrier
        OVERLORD  → JTAC      ≤ JTAC_HANDOFF_NM from CP TIGER (ME WP2)
        OVERLORD  → Strike    ≤ RTB_STRIKE_NM from the carrier
        Strike    → Marshal   ≤ RECOVERY_NM from the carrier (AIRBOSS takes over)
    * Agencies corrected: CP / JTAC / tanker / RTB tasking = OVERLORD (C2 agency).
      Strike = Mode 4 / Kilo outbound, corridor + Marshal hand-off inbound.
    * Hard deck: single value, 23,000 ft MSL, engagement area (flag 200 = 1).
    * INFLTREP (JP 3-09.3 Fig V-17) to OVERLORD after JTAC-2, then tanker assignment.
    * Feet dry / feet wet reports offered in F10 when the coastline is crossed
      (land.getSurfaceType).
    * Fix: Bearing() used atan2(dx, dz) → mirrored about 045°; now atan2(dz, dx).
    * Removed: unsolicited 4-min OVERLORD "no change" calls.

  PHASE FLOW
  ──────────────────────────────────────────────────────────────
    IDLE ─airborne→ DEPARTURE ─≥20 NM→ STRIKE_OUT ─F10→ STRIKE_CHK ─Mode 4 sweet→
    OVL_OUT ─F10→ ENROUTE ─≤20 NM CP→ JTAC1 ─tgt dead→ J1_OFF ─F10→ JTAC2
    ─tgt dead→ J2_OFF ─F10 INFLTREP→ REFUEL ─refuel done→ TKR_DONE ─F10→ RTB
    ─≤90 NM CVN→ STRIKE_IN ─F10→ INBOUND ─≤50 NM CVN→ RECOVERY
    (J2_OFF / REFUEL / TKR_DONE / RTB fall through to STRIKE_IN at ≤ RTB_STRIKE_NM)

  INJECTS
    INJ-1  Abort (30%, JTAC-2 / pass 2-3):     Eyeball "abort, abort, abort"
    INJ-2  IFF sour (15%, Strike check-in):    Strike "Mode 4 SOUR, recycle"
    INJ-3  MANPADS (25%, JTAC-2 before p3):    Eyeball threat call, hard deck reminder
    INJ-4  Corridor dev (auto, 80-50 NM):      Strike "outside corridor"
    INJ-1/3 are armed once the player is within INJ_ARM_NM of JTAC-2's targets.

  FLAGS  (no ME trigger reads 200-205 as of v1.2.0)
    100  = departure CASE (3 = CASE III — pre-set, DO NOT WRITE)
    200  = hard deck  0 = not in effect   1 = in effect, 23,000 ft MSL
    201  = INJ-1 state     0=clear  1=abort active  2=re-cleared
    202  = INJ-2 fired
    203  = INJ-3 fired (MANPADS)
    204  = INJ-4 fired (corridor deviation)
    205  = RTB corridor passed clean

  LOADING
    scripts/Comms_Director.lua, referenced by ME "Do Script File" (ResKey_Action_313).
    Embedded by build.py. Requires: DCS base Lua API, coord.*, land.* (no libraries).
]]

-- ══════════════════════════════════════════════════════════════
--  CONFIG  — update unit/group names to match ME exactly
-- ══════════════════════════════════════════════════════════════
local CFG = {
    -- ME unit / group names
    PLAYER_UNIT    = "Player_01",
    CARRIER_UNIT   = "CVN",
    TANKER_UNIT    = "TANKER-1-1",    -- KC-130, Texaco 11
    CS             = "HORNET 51",

    -- Mission numbers (kneeboard 01 ADMIN)
    MSN_J1         = "4101",
    MSN_J2         = "4102",

    -- CP TIGER = CAS-1 route point 3 in src/mission (ME shows it as WP2).
    -- DCS world coords (ME x = north -> vec3.x, ME y = east -> vec3.z).
    CP_NAME        = "CP TIGER",
    CP_POS         = { x = 73640, z = -39914 },   -- update if the WP is moved in ME

    -- JTAC target groups
    JTAC1_TGT_GROUP = "SAM BV51 (SA-13)-1",       -- Pointer 11, 2 units
    JTAC2_TGT_GROUP = "SAM YE53 (SA-8)-1",        -- Eyeball 11, 4 units
    JTAC2_POS      = { x = 59271, z = -1176 },    -- fallback; live centroid preferred
    INJ_ARM_NM     = 20,

    -- Hand-off geometry (NM)
    DEP_HANDOFF_NM  = 20,    -- Departure → Strike (outbound, on departure radial)
    JTAC_HANDOFF_NM = 20,    -- OVERLORD → JTAC, distance to CP TIGER
    RTB_STRIKE_NM   = 90,    -- OVERLORD → Strike (inbound)
    RECOVERY_NM     = 50,    -- Strike → Marshal (AIRBOSS)

    -- Airborne detection
    DEP_ALT_M      = 100,    -- ~330 ft MSL
    DEP_SPD_MS     = 41,     -- ~80 kt

    -- RTB corridor (TRUE degrees; Syria mag var ≈ +5° E → 050M = 055T)
    CORRIDOR_TRUE  = 55,     -- bearing FROM carrier TO player (true)
    CORRIDOR_HALF  = 15,
    CORRIDOR_OUT   = 80,
    CORRIDOR_IN    = 50,

    MAGVAR         = 5,      -- east; magnetic = true − MAGVAR
    HARD_DECK_FT   = 23000,  -- MSL, engagement area
    INTERNAL_FUEL_LB = 10860,

    FREQ = {
        DEP     = "127.60",
        STRIKE  = "265.00",
        J1      = "333.30",
        J2      = "333.40",
        OVL     = "251.10",
        TKR     = "252.10",
        MARSHAL = "305.00 FM",
    },

    -- Inject probabilities (integer 0–100)
    PROB_INJ1      = 30,
    PROB_INJ2      = 15,
    PROB_INJ3      = 25,

    TICK           = 5,      -- main tick (s)
    REPLY_GAP      = 2,      -- gap between pilot call and controller reply (s)
    PILOT_HOLD     = 2,      -- pilot call "airtime" before the reply gap starts (s)

    DUR_PILOT      = 7,
    DUR_SHORT      = 8,
    DUR_LONG       = 16,
    DUR_URGENT     = 12,
}

-- ══════════════════════════════════════════════════════════════
--  MODULE STATE
-- ══════════════════════════════════════════════════════════════
local CD = {
    phase         = "IDLE",
    queue         = {},
    qPlaying      = false,
    seenJ1 = false, seenJ2 = false,
    deadJ1 = false, deadJ2 = false,
    j1 = { pos = nil, size = 0, tot = nil },   -- INFLTREP data
    j2 = { pos = nil, size = 0, tot = nil },
    j2Armed       = false,
    tkrCheckedIn  = false,
    refuelDone    = false,
    corridorDone  = false,
    surf          = nil,      -- "LAND" / "WATER" (debounced)
    surfCand      = nil,
    surfCount     = 0,
    feetPending   = nil,      -- "DRY" / "WET" — report offered in F10
    awaiting      = false,    -- pilot call made, controller reply pending
    inj           = { i1 = false, i2 = false, i3 = false },
    menu          = { gid = nil, root = nil },
}

-- Phases in which the player is (or should be) working OVERLORD
local OVL_PHASES = {
    ENROUTE = true, JTAC1 = true, J1_OFF = true, JTAC2 = true,
    J2_OFF = true, REFUEL = true, TKR_DONE = true, RTB = true,
}

-- ══════════════════════════════════════════════════════════════
--  UTILITIES
-- ══════════════════════════════════════════════════════════════
local function MtoNM(m)   return m / 1852 end
local function Roll(pct)  return math.random(1, 100) <= pct end

local function Player()   return Unit.getByName(CFG.PLAYER_UNIT)  end
local function Carrier()  return Unit.getByName(CFG.CARRIER_UNIT) end
local function Tanker()   return Unit.getByName(CFG.TANKER_UNIT)  end

local function Dist2D(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return MtoNM(math.sqrt(dx * dx + dz * dz))
end

--- True bearing (°) from A to B. Vec3: x = north, z = east.
local function Bearing(a, b)
    return math.deg(math.atan2(b.z - a.z, b.x - a.x)) % 360
end

local function BrgMag(a, b)
    return (Bearing(a, b) - CFG.MAGVAR) % 360
end

local function ADiff(a, b)
    local d = (a - b + 360) % 360
    return (d > 180) and (d - 360) or d
end

--- "bears 043 for 37"
local function BrgRng(from, to)
    return string.format("bears %03d for %d",
        math.floor(BrgMag(from, to) + 0.5) % 360, math.floor(Dist2D(from, to) + 0.5))
end

local function Angels(u)
    return math.floor(u:getPoint().y * 3.28084 / 1000 + 0.5)
end

local function State(u)
    local f = u:getFuel() or 0
    return string.format("%.1f", f * CFG.INTERNAL_FUEL_LB / 1000)
end

local function MGRS(pos)
    local ok, s = pcall(function()
        local lat, lon = coord.LOtoLL(pos)
        local m = coord.LLtoMGRS(lat, lon)
        return string.format("%s %s %04d %04d", m.UTMZone, m.MGRSDigraph,
            math.floor(m.Easting / 10), math.floor(m.Northing / 10))
    end)
    return ok and s or "unknown"
end

local function Clock(abs)
    if not abs then return "unknown" end
    local t = math.floor(abs) % 86400
    return string.format("%02d%02dL", math.floor(t / 3600), math.floor((t % 3600) / 60))
end

local function Msg(text, dur, clear)
    local p = Player(); if not p then return end
    trigger.action.outTextForGroup(p:getGroup():getID(), text, dur or CFG.DUR_SHORT, clear or false)
end

local function SetFlag(f, v)  trigger.action.setUserFlag(tostring(f), v) end

local HD_TEXT = "hard deck two-three thousand MSL in the engagement area"

-- ══════════════════════════════════════════════════════════════
--  CLIP QUEUE
-- ══════════════════════════════════════════════════════════════
--- Push a clip to the end of the queue.
-- @param text   Radio call subtitle.
-- @param dur    Display duration (s).
-- @param after  Gap after the PREVIOUS clip ends before this one fires (s).
-- @param fn     Optional callback run when this clip fires (phase change etc.).
-- @param hold   Time from this clip's start until the next clip may start
--               (default = dur). Shorter than dur → next clip overlaps on screen.
local function Q(text, dur, after, fn, hold)
    table.insert(CD.queue, { text = text, dur = dur or CFG.DUR_SHORT, after = after or 1,
                             fn = fn, hold = hold })
end

local function QFire()
    if #CD.queue == 0 then CD.qPlaying = false; return end
    local clip = table.remove(CD.queue, 1)
    if clip.after > 0 and not clip.waited then
        -- honour the pre-gap before showing the clip
        clip.waited = true
        table.insert(CD.queue, 1, clip)
        CD.qPlaying = true
        timer.scheduleFunction(function() QFire() end, nil, timer.getTime() + clip.after)
        return
    end
    Msg(clip.text, clip.dur)
    if clip.fn then pcall(clip.fn) end
    CD.qPlaying = true
    timer.scheduleFunction(function() CD.qPlaying = false; QFire() end,
        nil, timer.getTime() + (clip.hold or clip.dur))
end

local function QPlay()
    if not CD.qPlaying and #CD.queue > 0 then QFire() end
end

local function QClear()
    CD.queue = {}
end

--- Pilot transmission followed by controller reply(ies).
local function Pilot(text)
    -- pilot text stays DUR_PILOT s; the reply may start PILOT_HOLD s after it
    Q("[" .. CFG.CS .. "] " .. text, CFG.DUR_PILOT, 0, nil, CFG.PILOT_HOLD)
end

-- forward declarations
local SetPhase, MenuRebuild

-- ══════════════════════════════════════════════════════════════
--  RADIO CALLS — controller-initiated (hand-offs / threats)
-- ══════════════════════════════════════════════════════════════
local function C_DepSwitchStrike()
    Q(string.format("[DEPARTURE] %s, Departure. Switch Strike, %s.", CFG.CS, CFG.FREQ.STRIKE),
        CFG.DUR_SHORT + 2, 0)
end

local function C_OvlContactPointer(p)
    Q(string.format("[OVERLORD] %s, Overlord. %s %s. Pointer 11 is on station. "
        .. "Contact Pointer 11, %s. Return to this frequency on check-out.",
        CFG.CS, CFG.CP_NAME, BrgRng(p:getPoint(), CFG.CP_POS), CFG.FREQ.J1), CFG.DUR_LONG, 0)
end

local function C_OvlSwitchStrike(p)
    local c = Carrier()
    local mother = c and (", Mother " .. BrgRng(p:getPoint(), c:getPoint())) or ""
    Q(string.format("[OVERLORD] %s, Overlord%s. Switch Strike, %s.",
        CFG.CS, mother, CFG.FREQ.STRIKE), CFG.DUR_SHORT + 4, 0)
end

local function C_StrikeSwitchMarshal()
    Q(string.format("[STRIKE] %s, Strike. Switch Marshal, %s.", CFG.CS, CFG.FREQ.MARSHAL),
        CFG.DUR_SHORT + 2, 0)
end

-- Urgent calls bypass the queue: shown immediately, queued routine traffic is dropped.
local function C_Abort()
    QClear()
    Msg(string.format("[EYEBALL 11] %s, abort, abort, abort. Civilian vehicle in target area.", CFG.CS),
        CFG.DUR_URGENT + 2)
    SetFlag(201, 1)
end

local function C_Rearm()
    Q(string.format("[EYEBALL 11] %s, target area clear. Continue as briefed.", CFG.CS), 10, 6)
    SetFlag(201, 2)
end

local function C_Manpads()
    Msg(string.format("[EYEBALL 11] %s, MANPADS launch observed one klick east of the target. "
        .. "Remain at or above hard deck, two-three thousand MSL.", CFG.CS), CFG.DUR_URGENT + 1)
    SetFlag(203, 1)
end

local function C_CorridorDev()
    Msg(string.format("[STRIKE] %s, Strike. You are outside the return corridor. "
        .. "Turn now for the 050 radial.", CFG.CS), CFG.DUR_URGENT + 1)
    SetFlag(204, 1)
end

-- ══════════════════════════════════════════════════════════════
--  F10 ACTIONS — pilot-initiated
-- ══════════════════════════════════════════════════════════════
local function A_StrikeCheckInOut()
    local p = Player(); if not p then return end
    SetPhase("STRIKE_CHK")
    Pilot(string.format("Strike, %s, checking in outbound, passing angels %d, Kilo.", CFG.CS, Angels(p)))
    Q(string.format("[STRIKE] %s, Strike, radar contact. Check Mode 4.", CFG.CS), CFG.DUR_SHORT, CFG.REPLY_GAP)
    local sweetToOvl = function()
        Q(string.format("[STRIKE] %s, Mode 4 sweet. Kilo copied. Switch Overlord, %s.",
            CFG.CS, CFG.FREQ.OVL), CFG.DUR_SHORT + 2, 3, function() SetPhase("OVL_OUT") end)
    end
    if not CD.inj.i2 and Roll(CFG.PROB_INJ2) then
        CD.inj.i2 = true
        SetFlag(202, 1)
        Q(string.format("[STRIKE] %s, Mode 4 sour. Recycle.", CFG.CS), CFG.DUR_URGENT, 4)
        Q(string.format("[STRIKE] %s, Strike. Mode 4 sweet now.", CFG.CS), CFG.DUR_SHORT, 16)
        Q(string.format("[STRIKE] %s, Kilo copied. Switch Overlord, %s.", CFG.CS, CFG.FREQ.OVL),
            CFG.DUR_SHORT + 2, 2, function() SetPhase("OVL_OUT") end)
    else
        sweetToOvl()
    end
    QPlay()
end

local function A_OvlCheckIn()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, checking in as fragged, mission %s and %s, angels %d, state %s.",
        CFG.CS, CFG.MSN_J1, CFG.MSN_J2, Angels(p), State(p)))
    Q(string.format("[OVERLORD] %s, Overlord, radar contact. Picture clean. "
        .. "Mission as fragged, Pointer 11 and Eyeball 11 on station. Proceed %s, %s. "
        .. "SAM activity reported in both target areas, %s. Report feet dry.",
        CFG.CS, CFG.CP_NAME, BrgRng(p:getPoint(), CFG.CP_POS), HD_TEXT),
        CFG.DUR_LONG + 4, CFG.REPLY_GAP, function() SetPhase("ENROUTE") end)
    QPlay()
end

local function A_OvlOffPointer()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, off Pointer 11, mission %s complete, angels %d, state %s. "
        .. "Ready for retasking.", CFG.CS, CFG.MSN_J1, Angels(p), State(p)))
    Q(string.format("[OVERLORD] %s, Overlord, copy. Return to %s, %s. "
        .. "Eyeball 11 is on station. Contact Eyeball 11, %s.",
        CFG.CS, CFG.CP_NAME, BrgRng(p:getPoint(), CFG.CP_POS), CFG.FREQ.J2),
        CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("JTAC2") end)
    QPlay()
end

local function A_Inflrep()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, INFLTREP.\n"
        .. "Line 1, %s.\nLine 2, mission %s and %s.\nLine 3, %s and %s.\n"
        .. "Line 4, time on target %s and %s.\nLine 5, %d and %d vehicles destroyed.\n"
        .. "Remarks, SAM activity in both target areas.",
        CFG.CS, CFG.CS, CFG.MSN_J1, CFG.MSN_J2,
        CD.j1.pos and MGRS(CD.j1.pos) or "unknown", CD.j2.pos and MGRS(CD.j2.pos) or "unknown",
        Clock(CD.j1.tot), Clock(CD.j2.tot), CD.j1.size, CD.j2.size))
    -- INFLTREP is long — give it time on screen
    CD.queue[#CD.queue].dur  = CFG.DUR_LONG + 4
    CD.queue[#CD.queue].hold = 8
    local t = Tanker()
    local tkr = t and string.format("Texaco 11 %s, angels %d", BrgRng(p:getPoint(), t:getPoint()), Angels(t))
                or "Texaco 11 on station"
    Q(string.format("[OVERLORD] %s, Overlord, copy INFLTREP. %s, TACAN 21 Yankee. Switch Texaco, %s.",
        CFG.CS, tkr, CFG.FREQ.TKR), CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("REFUEL") end)
    QPlay()
end

local function A_TexacoCheckIn()
    local p = Player(); if not p then return end
    CD.tkrCheckedIn = true
    Pilot(string.format("Texaco 11, %s, checking in, angels %d, state %s.", CFG.CS, Angels(p), State(p)))
    Q(string.format("[TEXACO 11] %s, Texaco 11, angels 15. Cleared to join, left observation. "
        .. "Port drogue, call pre-contact.", CFG.CS), CFG.DUR_LONG - 2, CFG.REPLY_GAP)
    QPlay()
    MenuRebuild()
end

local function A_OvlRTB()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    local c = Carrier()
    local from = (CD.phase == "TKR_DONE") and "off Texaco" or "no tanker required"
    Pilot(string.format("Overlord, %s, %s, RTB, angels %d, state %s.", CFG.CS, from, Angels(p), State(p)))
    local mother = c and (" Mother " .. BrgRng(p:getPoint(), c:getPoint()) .. ".") or ""
    Q(string.format("[OVERLORD] %s, Overlord, RTB approved.%s Recover via the 050 return corridor. "
        .. "Report feet wet.", CFG.CS, mother), CFG.DUR_LONG, CFG.REPLY_GAP,
        function() SetPhase("RTB") end)
    QPlay()
end

local function A_StrikeCheckInIn()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Strike, %s, inbound, angels %d, state %s.", CFG.CS, Angels(p), State(p)))
    Q(string.format("[STRIKE] %s, Strike, radar contact, Mode 4 sweet. Continue the 050 corridor. "
        .. "Switch Marshal at 50 miles, %s.", CFG.CS, CFG.FREQ.MARSHAL),
        CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("INBOUND") end)
    QPlay()
end

local function A_FeetReport()
    local kind = CD.feetPending; if not kind then return end
    CD.feetPending = nil
    local word = (kind == "DRY") and "feet dry" or "feet wet"
    Pilot(string.format("Overlord, %s, %s.", CFG.CS, word))
    Q(string.format("[OVERLORD] %s, Overlord, copy %s.", CFG.CS, word), CFG.DUR_SHORT, CFG.REPLY_GAP)
    QPlay()
    MenuRebuild()
end

local function A_Picture()
    if not OVL_PHASES[CD.phase] then
        Msg("[CAS-1] Not checked in with OVERLORD.", 7); return
    end
    Pilot(string.format("Overlord, %s, request picture.", CFG.CS))
    Q(string.format("[OVERLORD] %s, Overlord, picture clean. SAM activity reported in the target areas.",
        CFG.CS), CFG.DUR_SHORT + 2, CFG.REPLY_GAP)
    QPlay()
end

-- "What is my next call?" — single-line hint per phase
local NEXT = {
    IDLE       = "Launch. CASE III departure on Departure " .. CFG.FREQ.DEP .. ".",
    DEPARTURE  = "On Departure " .. CFG.FREQ.DEP .. ". Hand-off to Strike at "
                 .. CFG.DEP_HANDOFF_NM .. " NM.",
    STRIKE_OUT = "Check in with STRIKE " .. CFG.FREQ.STRIKE .. " (F10).",
    STRIKE_CHK = "Stand by, Strike working Mode 4.",
    OVL_OUT    = "Check in with OVERLORD " .. CFG.FREQ.OVL .. " (F10).",
    ENROUTE    = "Proceed " .. CFG.CP_NAME .. ". OVERLORD hands you to Pointer 11 at "
                 .. CFG.JTAC_HANDOFF_NM .. " NM.",
    JTAC1      = "Work Pointer 11 " .. CFG.FREQ.J1 .. " (native JTAC menu).",
    J1_OFF     = "Check out with Pointer 11, report to OVERLORD (F10).",
    JTAC2      = "Work Eyeball 11 " .. CFG.FREQ.J2 .. " (native JTAC menu).",
    J2_OFF     = "Check out with Eyeball 11, pass INFLTREP to OVERLORD (F10).",
    REFUEL     = "Check in with TEXACO 11 " .. CFG.FREQ.TKR .. " (F10), refuel.",
    TKR_DONE   = "Report RTB to OVERLORD (F10).",
    RTB        = "RTB via 050 corridor. OVERLORD hands you to Strike at "
                 .. CFG.RTB_STRIKE_NM .. " NM.",
    STRIKE_IN  = "Check in with STRIKE " .. CFG.FREQ.STRIKE .. " inbound (F10).",
    INBOUND    = "Switch Marshal " .. CFG.FREQ.MARSHAL .. " at " .. CFG.RECOVERY_NM .. " NM.",
    RECOVERY   = "Marshal / AIRBOSS.",
}

-- ══════════════════════════════════════════════════════════════
--  F10 MENU (rebuilt on every phase change)
-- ══════════════════════════════════════════════════════════════
local function PhaseActions()
    local ph, a = CD.phase, {}
    if CD.awaiting then return a end
    if ph == "STRIKE_OUT" then a[#a+1] = { "Check in: STRIKE " .. CFG.FREQ.STRIKE, A_StrikeCheckInOut } end
    if ph == "OVL_OUT"    then a[#a+1] = { "Check in: OVERLORD " .. CFG.FREQ.OVL, A_OvlCheckIn } end
    if ph == "J1_OFF"     then a[#a+1] = { "OVERLORD: off Pointer 11, ready for retasking", A_OvlOffPointer } end
    if ph == "J2_OFF"     then a[#a+1] = { "OVERLORD: INFLTREP", A_Inflrep } end
    if ph == "REFUEL" and not CD.tkrCheckedIn then
        a[#a+1] = { "Check in: TEXACO 11 " .. CFG.FREQ.TKR, A_TexacoCheckIn }
    end
    if ph == "REFUEL" or ph == "TKR_DONE" then
        a[#a+1] = { (ph == "TKR_DONE") and "OVERLORD: RTB" or "OVERLORD: RTB (no tanker)", A_OvlRTB }
    end
    if ph == "STRIKE_IN"  then a[#a+1] = { "Check in: STRIKE " .. CFG.FREQ.STRIKE .. " inbound", A_StrikeCheckInIn } end
    if CD.feetPending and OVL_PHASES[ph] then
        a[#a+1] = { "OVERLORD: " .. ((CD.feetPending == "DRY") and "feet dry" or "feet wet"), A_FeetReport }
    end
    return a
end

MenuRebuild = function()
    local p = Player(); if not p then return false end
    local gid = p:getGroup():getID()
    if CD.menu.root then pcall(missionCommands.removeItemForGroup, CD.menu.gid, CD.menu.root) end
    CD.menu.gid  = gid
    CD.menu.root = missionCommands.addSubMenuForGroup(gid, "CAS-1 COMMS")
    local root = CD.menu.root

    for _, it in ipairs(PhaseActions()) do
        missionCommands.addCommandForGroup(gid, it[1], root, it[2])
    end

    if OVL_PHASES[CD.phase] then
        missionCommands.addCommandForGroup(gid, "OVERLORD: request picture", root, A_Picture)
    end

    missionCommands.addCommandForGroup(gid, "Show: next call", root, function()
        Msg("[CAS-1] " .. (NEXT[CD.phase] or CD.phase), CFG.DUR_SHORT)
    end)

    missionCommands.addCommandForGroup(gid, "Show: hard deck", root, function()
        local on = trigger.misc.getUserFlag("200") == 1
        Msg(string.format("[CAS-1] Hard deck %d ft MSL, engagement area — %s",
            CFG.HARD_DECK_FT, on and "IN EFFECT" or "not in effect (transit)"), CFG.DUR_SHORT)
    end)

    missionCommands.addCommandForGroup(gid, "Show: comm ladder", root, function()
        Msg(
            "── CAS-1 COMM LADDER ──────────────────\n"
         .. "COMM1-01  127.60 AM   DEPARTURE\n"
         .. "COMM1-03  265.00 AM   STRIKE\n"
         .. "COMM1-04  333.30 AM   POINTER 11  (JTAC-1)\n"
         .. "COMM1-05  333.40 AM   EYEBALL 11  (JTAC-2)\n"
         .. "COMM1-06  251.10 AM   OVERLORD\n"
         .. "COMM1-07  252.10 AM   TEXACO 11\n"
         .. "COMM2-01  305.00 FM   MARSHAL\n"
         .. "── FLOW ───────────────────────────────\n"
         .. "DEP → (20 NM) STRIKE → OVERLORD → (CP-20 NM) POINTER\n"
         .. "→ OVERLORD → EYEBALL → OVERLORD INFLTREP → TEXACO\n"
         .. "→ OVERLORD RTB → (90 NM) STRIKE → (50 NM) MARSHAL",
            CFG.DUR_LONG + 4)
    end)
    return true
end

-- ══════════════════════════════════════════════════════════════
--  INJECTS (JTAC-2)
-- ══════════════════════════════════════════════════════════════
local function ArmJ2Injects()
    if not CD.inj.i3 then
        local d3 = 55 + math.random(0, 20)
        timer.scheduleFunction(function()
            if CD.phase == "JTAC2" and not CD.inj.i3 and Roll(CFG.PROB_INJ3) then
                CD.inj.i3 = true
                C_Manpads()
            end
        end, nil, timer.getTime() + d3)
    end
    if not CD.inj.i1 then
        local d1 = 85 + math.random(0, 60)
        timer.scheduleFunction(function()
            if CD.phase == "JTAC2" and not CD.inj.i1 and Roll(CFG.PROB_INJ1) then
                CD.inj.i1 = true
                C_Abort()
                timer.scheduleFunction(function()
                    if CD.phase == "JTAC2" or CD.phase == "J2_OFF" then C_Rearm(); QPlay() end
                end, nil, timer.getTime() + 45)
            end
        end, nil, timer.getTime() + d1)
    end
end

-- ══════════════════════════════════════════════════════════════
--  CORRIDOR MONITOR  (RTB / STRIKE_IN / INBOUND)
-- ══════════════════════════════════════════════════════════════
local function CorridorCheck(pPos, cPos)
    if CD.corridorDone then return end
    local dist = Dist2D(pPos, cPos)
    if dist > CFG.CORRIDOR_OUT then return end
    if dist < CFG.CORRIDOR_IN then
        SetFlag(205, 1)
        CD.corridorDone = true
        return
    end
    local delta = math.abs(ADiff(Bearing(cPos, pPos), CFG.CORRIDOR_TRUE))
    if delta > CFG.CORRIDOR_HALF then
        CD.corridorDone = true
        C_CorridorDev()
    end
end

-- ══════════════════════════════════════════════════════════════
--  FEET DRY / WET MONITOR
-- ══════════════════════════════════════════════════════════════
local function SurfaceCheck(pPos)
    local ok, st = pcall(land.getSurfaceType, { x = pPos.x, y = pPos.z })
    if not ok or not st then return end
    local s = (st == land.SurfaceType.WATER or st == land.SurfaceType.SHALLOW_WATER) and "WATER" or "LAND"
    if s == CD.surf then CD.surfCand, CD.surfCount = nil, 0; return end
    if s ~= CD.surfCand then CD.surfCand, CD.surfCount = s, 1; return end
    CD.surfCount = CD.surfCount + 1
    if CD.surfCount < 2 then return end              -- debounce: 2 ticks
    local prev = CD.surf
    CD.surf, CD.surfCand, CD.surfCount = s, nil, 0
    if prev and OVL_PHASES[CD.phase] then
        CD.feetPending = (s == "LAND") and "DRY" or "WET"
        MenuRebuild()
    end
end

-- ══════════════════════════════════════════════════════════════
--  PHASE STATE MACHINE
-- ══════════════════════════════════════════════════════════════
SetPhase = function(new)
    if CD.phase == new then return end
    CD.awaiting = false
    env.info(string.format("[CD] %s → %s", CD.phase, new))
    CD.phase = new

    if new == "JTAC1" or new == "JTAC2" or new == "J1_OFF" or new == "J2_OFF" then
        SetFlag(200, 1)
    else
        SetFlag(200, 0)
    end

    if new == "J1_OFF" then
        Msg("[CAS-1] Pointer 11 tasking complete. Check out, then report to OVERLORD (F10).", CFG.DUR_SHORT)
    elseif new == "J2_OFF" then
        Msg("[CAS-1] Eyeball 11 tasking complete. Check out, then INFLTREP to OVERLORD (F10).", CFG.DUR_SHORT)
    elseif new == "RECOVERY" then
        env.info("[CD] RECOVERY phase — AIRBOSS active, CD standing down after Marshal hand-off.")
    end

    MenuRebuild()
end

local function GroupAlive(name)
    local g = Group.getByName(name)
    if not g or not g:isExist() then return false end
    for _, u in ipairs(g:getUnits() or {}) do
        if u and u:isExist() and u:getLife() > 0 then return true end
    end
    return false
end

--- Centroid + initial size of a live group (for INFLTREP / inject arming).
local function Snapshot(name, rec)
    local g = Group.getByName(name)
    if not g then return end
    local sx, sz, n = 0, 0, 0
    for _, u in ipairs(g:getUnits() or {}) do
        if u and u:isExist() then
            local p = u:getPoint(); sx, sz, n = sx + p.x, sz + p.z, n + 1
        end
    end
    if n > 0 then rec.pos = { x = sx / n, y = 0, z = sz / n } end
    local ok, sz0 = pcall(function() return g:getInitialSize() end)
    rec.size = (ok and sz0) or n
end

local function TrackTargets()
    if not CD.deadJ1 then
        if GroupAlive(CFG.JTAC1_TGT_GROUP) then
            if not CD.seenJ1 then CD.seenJ1 = true; Snapshot(CFG.JTAC1_TGT_GROUP, CD.j1) end
        elseif CD.seenJ1 then
            CD.deadJ1 = true; CD.j1.tot = timer.getAbsTime()
            env.info("[CD] JTAC-1 target group destroyed: " .. CFG.JTAC1_TGT_GROUP)
        end
    end
    if not CD.deadJ2 then
        if GroupAlive(CFG.JTAC2_TGT_GROUP) then
            if not CD.seenJ2 then CD.seenJ2 = true; Snapshot(CFG.JTAC2_TGT_GROUP, CD.j2) end
        elseif CD.seenJ2 then
            CD.deadJ2 = true; CD.j2.tot = timer.getAbsTime()
            env.info("[CD] JTAC-2 target group destroyed: " .. CFG.JTAC2_TGT_GROUP)
        end
    end
end

local function EvalPhase(pUnit, cUnit)
    local pPos = pUnit:getPoint()
    local cPos = cUnit and cUnit:getPoint()
    local ph   = CD.phase

    if ph == "IDLE" then
        local v = pUnit:getVelocity()
        local spd = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        if pPos.y > CFG.DEP_ALT_M and spd > CFG.DEP_SPD_MS then SetPhase("DEPARTURE") end

    elseif ph == "DEPARTURE" then
        if cPos and Dist2D(pPos, cPos) >= CFG.DEP_HANDOFF_NM then
            C_DepSwitchStrike(); QPlay()
            SetPhase("STRIKE_OUT")
        end

    elseif ph == "ENROUTE" then
        if Dist2D(pPos, CFG.CP_POS) <= CFG.JTAC_HANDOFF_NM then
            C_OvlContactPointer(pUnit); QPlay()
            SetPhase("JTAC1")
        end

    elseif ph == "JTAC1" then
        if CD.deadJ1 then SetPhase("J1_OFF") end

    elseif ph == "JTAC2" then
        if not CD.j2Armed then
            local tgt = CD.j2.pos or CFG.JTAC2_POS
            if Dist2D(pPos, tgt) <= CFG.INJ_ARM_NM then CD.j2Armed = true; ArmJ2Injects() end
        end
        if CD.deadJ2 then SetPhase("J2_OFF") end

    elseif ph == "REFUEL" then
        if CD.refuelDone then
            Q(string.format("[TEXACO 11] %s, Texaco 11, offload complete. Cleared to depart, "
                .. "return to Overlord, %s.", CFG.CS, CFG.FREQ.OVL), CFG.DUR_SHORT + 4, 0)
            QPlay()
            SetPhase("TKR_DONE")
        end
    end

    -- Inbound: OVERLORD → Strike (also catches a skipped INFLTREP / tanker / RTB call)
    ph = CD.phase
    if (ph == "J2_OFF" or ph == "REFUEL" or ph == "TKR_DONE" or ph == "RTB")
        and cPos and Dist2D(pPos, cPos) <= CFG.RTB_STRIKE_NM then
        C_OvlSwitchStrike(pUnit); QPlay()
        SetPhase("STRIKE_IN")
    end

    ph = CD.phase
    if (ph == "RTB" or ph == "STRIKE_IN" or ph == "INBOUND") and cPos then
        CorridorCheck(pPos, cPos)
        if Dist2D(pPos, cPos) <= CFG.RECOVERY_NM then
            QClear()
            C_StrikeSwitchMarshal(); QPlay()
            SetPhase("RECOVERY")
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  MAIN TICK
-- ══════════════════════════════════════════════════════════════
local function CD_Tick(_, t)
    if CD.phase == "DONE" or CD.phase == "RECOVERY" then return end
    TrackTargets()
    local p = Player()
    if not p then return t + CFG.TICK end
    if not CD.menu.root then MenuRebuild() end
    EvalPhase(p, Carrier())
    if OVL_PHASES[CD.phase] or CD.phase == "DEPARTURE" then SurfaceCheck(p:getPoint()) end
    return t + CFG.TICK
end

-- ══════════════════════════════════════════════════════════════
--  INIT
-- ══════════════════════════════════════════════════════════════
local function CD_Init()
    pcall(math.randomseed, timer.getAbsTime())

    -- Core_Scoring refuel-complete callback (TRT.onRefuelComplete); retry until TRT exists.
    local function HookRefuel(_, tm)
        if _G.TRT then
            local prev = _G.TRT.onRefuelComplete
            _G.TRT.onRefuelComplete = function(name, ...)
                if prev then pcall(prev, name, ...) end
                if name == CFG.PLAYER_UNIT then
                    CD.refuelDone = true
                    env.info("[CD] refuel complete reported for " .. tostring(name))
                end
            end
            env.info("[CD] hooked TRT.onRefuelComplete")
            return nil
        end
        return tm + 2
    end
    timer.scheduleFunction(HookRefuel, nil, timer.getTime() + 2)

    SetFlag(200, 0)
    timer.scheduleFunction(CD_Tick, nil, timer.getTime() + CFG.TICK)
    env.info("[CD] Comms_Director v1.2.0 online — CAS-1 Syria")
end

CD_Init()
