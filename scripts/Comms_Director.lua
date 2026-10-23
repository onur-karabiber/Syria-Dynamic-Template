-- Comms_Director | v1.4.3
--[[
  CAS-1 Communications State Machine — Syria Dynamic Template
  Scope: Departure→Strike→OVERLORD hand-offs · JTAC hand-offs · INFLTREP · TANKER
         · RTB (OVERLORD→Strike→Marshal) · INJ-1..4
  Out of scope: JTAC comms themselves (native DCS JTAC check-in / 9-line / clearance
                preserved, do not touch)

  v1.4.3 — "SAM" was spelled letter by letter by Piper (es-ay-em); clips re-rendered
           with "Sam" (ovl_checkin_b, ovl_picture, i_rmk).

  v1.4.2 — F10 "OVERLORD: RTB (mission abort)" in ENROUTE / JTAC1 / J1_OFF / JTAC2 /
           J2_OFF (REFUEL / TKR_DONE keep their normal RTB item):
             HORNET 51: Overlord, Hornet 51, mission abort, RTB, angels N, state X.Y
             OVERLORD:  Hornet 51, Overlord, copy abort. RTB approved. Mother bears
                        XXX for YY. Recover via the 050 return corridor. Report feet wet.
           -> phase RTB (normal inbound flow: 90 NM Strike, 50 NM Marshal).

  v1.4.1 — ack timing: the hand-off ack waited for the controller's SUBTITLE time
           (dur, e.g. 10 s) instead of the end of its audio. Ack() now sets the
           preceding queued clip's hold to 0.1 s, so the ack starts ~0.8 s after
           the controller's voice ends (QFire waits max(hold, audio + AUDIO_PAD)).

  v1.4.0 — pilot hand-off acknowledgements + spoken numbers
    * Every controller hand-off gets an automatic, voiced pilot ack on the same
      frequency: "Hornet 51, switching." (Departure->Strike, Strike->Overlord,
      Overlord->Pointer / Eyeball / Texaco / Strike, Texaco->Overlord, Strike->Marshal);
      "Hornet 51, wilco." for Strike's inbound "switch Marshal at 50 miles".
    * Dynamic parts are voiced: pilot angels / state (all check-ins), Overlord
      "bears XXX for YY" (CP Tiger, Mother, Texaco + angels), full INFLTREP (MGRS in
      phonetic alphabet, TOT, vehicle counts). Clips are chained token sequences:
      Q(..., audio) accepts a table { ch = "<CHAN>", "<id>", <pause s>, ... }.
      Pilot digits / letters come from the CV_Comms set ("cv:p_*", TRT.CV_AUDIO);
      Overlord digits are o_* (tts/clips.csv). Text and voice now say the same thing
      (hard deck sentence included).
    * CASE III departure: CV_Comms v1.3.0 runs the Departure dialogue; this script
      waits for TRT.CV_DEP_CLEARED ("cleared to switch") instead of its own 20 NM
      "switch Strike". CASE I/II unchanged (20 NM).

  v1.3.5 — load log line carried a stale version ("v1.2.1 online"); now matches header.

  v1.3.4 — CV button plan (CV_Comms.lua): DEPARTURE 127.60 -> 269.00 AM (btn 2),
           MARSHAL 305.00 FM -> 261.00 AM (btn 16). str_switch_marshal / str_inbound
           re-rendered. Comm ladder lists the real COMM1 buttons.

  v1.3.3 — voices re-cast (make_clips v1.2.1): DEPARTURE and OVERLORD female
           (lessac, kristin), HORNET 51 = john. All 41 clips re-rendered, CFG.AUDIO
           lengths updated.

  v1.3.2 — HORNET 51 (pilot) calls voiced too: static part only (call sign, agency,
           request); angels / state / MGRS / TOT stay on-screen. Played on the called
           agency's frequency (CFG.AUDIO ch), voice = Piper ryan pitched down.

  v1.3.1 — clips re-rendered with make_clips.py v1.1.0 (~2x faster speech, heavier
           radio chain: squelch bursts, noise floor, soft-clip). CFG.AUDIO lengths updated.

  v1.3.0 — TTS voice for controller calls
    * Controller calls play a pre-rendered .ogg (Piper TTS, tts/make_clips.py) via
      trigger.action.radioTransmission on the agency frequency (CFG.CHAN); heard only
      when a radio is tuned to it. Pilot calls are not voiced. Dynamic content
      (bearing/range, angels, state, MGRS, TOT) stays text-only.
    * Clips: Sounds/CAS1/<id>.ogg (src/Sounds/CAS1/), table CFG.AUDIO (len = clip s).
    * Queue waits for the clip: next clip starts at max(hold or dur, len + AUDIO_PAD).
    * Urgent calls (abort / MANPADS / corridor) cut the clip on air and play at once.

  v1.2.1 — check-in reminders
    * If a pilot check-in / report is pending, the handing-off or monitoring agency
      repeats the call after REMIND_FIRST s, then every REMIND_EVERY s
      ("..., contact Strike 265.00, how copy?"), followed by an F10 hint line.
    * One-time F10 hint on takeoff. Hand-off calls stay on screen longer (DUR_HANDOFF).

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
    Embedded by build.py. Voice clips: src/Sounds/CAS1/*.ogg (regenerate with
    python tts/make_clips.py, then paste tts/audio_table.lua into CFG.AUDIO).
    Requires: DCS base Lua API, coord.*, land.* (no libraries).
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
        DEP     = "269.00",
        STRIKE  = "265.00",
        J1      = "333.30",
        J2      = "333.40",
        OVL     = "251.10",
        TKR     = "252.10",
        MARSHAL = "261.00",
    },

    -- Voice (v1.3.0). Transmitted from 30 m above the player → no range/LOS loss.
    SND_DIR   = "Sounds/CAS1/",
    TX_POWER  = 1000,    -- W
    AUDIO_PAD = 0.5,     -- s after a clip ends before the next clip may start
    CHAN = {             -- Hz, modulation
        DEPARTURE = { hz = 269.00e6, mod = radio.modulation.AM },
        STRIKE    = { hz = 265.00e6, mod = radio.modulation.AM },
        OVERLORD  = { hz = 251.10e6, mod = radio.modulation.AM },
        EYEBALL   = { hz = 333.40e6, mod = radio.modulation.AM },
        TEXACO    = { hz = 252.10e6, mod = radio.modulation.AM },
    },
    -- generated by tts/make_clips.py; len = clip length (s)
    AUDIO = {
        dep_switch_strike      = { ch = "DEPARTURE", len = 2.85 },
        str_switch_marshal     = { ch = "STRIKE", len = 2.64 },
        eye_area_clear         = { ch = "EYEBALL", len = 2.40 },
        str_radar_contact      = { ch = "STRIKE", len = 2.48 },
        str_m4_sweet_ovl       = { ch = "STRIKE", len = 3.42 },
        str_m4_sour            = { ch = "STRIKE", len = 1.94 },
        str_m4_sweet_now       = { ch = "STRIKE", len = 1.88 },
        str_kilo_ovl           = { ch = "STRIKE", len = 2.72 },
        tkr_checkin            = { ch = "TEXACO", len = 4.89 },
        tkr_done               = { ch = "TEXACO", len = 4.83 },
        str_inbound            = { ch = "STRIKE", len = 5.84 },
        ovl_feet_dry           = { ch = "OVERLORD", len = 2.11 },
        ovl_feet_wet           = { ch = "OVERLORD", len = 2.06 },
        ovl_picture            = { ch = "OVERLORD", len = 3.56 },
        ovl_say_int            = { ch = "OVERLORD", len = 2.18 },
        ovl_contact_strike     = { ch = "OVERLORD", len = 3.87 },
        dep_contact_strike     = { ch = "DEPARTURE", len = 3.52 },
        str_contact_ovl        = { ch = "STRIKE", len = 2.77 },
        ovl_say_status         = { ch = "OVERLORD", len = 2.16 },
        ovl_say_status_tkr     = { ch = "OVERLORD", len = 3.06 },
        ovl_texaco_freq        = { ch = "OVERLORD", len = 3.30 },
        eye_abort              = { ch = "EYEBALL", len = 2.99 },
        eye_manpads            = { ch = "EYEBALL", len = 4.44 },
        str_corridor           = { ch = "STRIKE", len = 3.63 },
        p_ovl_feet_dry         = { ch = "OVERLORD", len = 1.81 },
        p_ovl_feet_wet         = { ch = "OVERLORD", len = 1.69 },
        p_ovl_picture          = { ch = "OVERLORD", len = 1.94 },
        o_0                    = { ch = "OVERLORD", len = 0.40 },
        o_1                    = { ch = "OVERLORD", len = 0.33 },
        o_2                    = { ch = "OVERLORD", len = 0.33 },
        o_3                    = { ch = "OVERLORD", len = 0.43 },
        o_4                    = { ch = "OVERLORD", len = 0.34 },
        o_5                    = { ch = "OVERLORD", len = 0.62 },
        o_6                    = { ch = "OVERLORD", len = 0.39 },
        o_7                    = { ch = "OVERLORD", len = 1.02 },
        o_8                    = { ch = "OVERLORD", len = 0.30 },
        o_9                    = { ch = "OVERLORD", len = 0.33 },
        o_bears                = { ch = "OVERLORD", len = 0.42 },
        o_for                  = { ch = "OVERLORD", len = 0.42 },
        o_angels               = { ch = "OVERLORD", len = 0.51 },
        o_mother               = { ch = "OVERLORD", len = 0.32 },
        ovl_checkin_a          = { ch = "OVERLORD", len = 5.67 },
        ovl_checkin_b          = { ch = "OVERLORD", len = 5.11 },
        ovl_contact_pointer_a  = { ch = "OVERLORD", len = 1.95 },
        ovl_contact_pointer_b  = { ch = "OVERLORD", len = 4.67 },
        ovl_off_pointer_a      = { ch = "OVERLORD", len = 2.36 },
        ovl_off_pointer_b      = { ch = "OVERLORD", len = 3.25 },
        ovl_switch_strike_a    = { ch = "OVERLORD", len = 1.26 },
        ovl_switch_strike_b    = { ch = "OVERLORD", len = 1.82 },
        ovl_rtb_a              = { ch = "OVERLORD", len = 2.37 },
        ovl_rtb_b              = { ch = "OVERLORD", len = 2.81 },
        ovl_inflrep_a          = { ch = "OVERLORD", len = 2.34 },
        ovl_inflrep_b          = { ch = "OVERLORD", len = 2.60 },
        ovl_inflrep_nt         = { ch = "OVERLORD", len = 5.50 },
        p_str_out_a            = { ch = "PILOT", len = 2.79 },
        p_ovl_checkin_a        = { ch = "PILOT", len = 3.80 },
        p_ovl_off_pointer_a    = { ch = "PILOT", len = 3.32 },
        p_ovl_off_pointer_b    = { ch = "PILOT", len = 1.16 },
        p_tkr_checkin_a        = { ch = "PILOT", len = 1.88 },
        p_ovl_rtb_tkr_a        = { ch = "PILOT", len = 2.04 },
        p_ovl_rtb_notkr_a      = { ch = "PILOT", len = 2.91 },
        p_str_inbound_a        = { ch = "PILOT", len = 1.67 },
        p_switching            = { ch = "PILOT", len = 1.36 },
        p_wilco                = { ch = "PILOT", len = 1.01 },
        i_head                 = { ch = "PILOT", len = 1.97 },
        i_l1                   = { ch = "PILOT", len = 1.08 },
        i_l2                   = { ch = "PILOT", len = 2.97 },
        i_l3                   = { ch = "PILOT", len = 0.51 },
        i_l4                   = { ch = "PILOT", len = 1.13 },
        i_l5                   = { ch = "PILOT", len = 0.59 },
        i_l5b                  = { ch = "PILOT", len = 0.93 },
        i_rmk                  = { ch = "PILOT", len = 1.81 },
        p_ovl_abort_a          = { ch = "PILOT", len = 2.19 },
        ovl_abort_a            = { ch = "OVERLORD", len = 2.68 },
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
    DUR_HANDOFF    = 15,

    REMIND_FIRST   = 60,     -- s after a check-in becomes due before the first repeat
    REMIND_EVERY   = 120,    -- s between further repeats
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

--- Clip length + file for a token id. "cv:<id>" = CV_Comms clip set (TRT.CV_AUDIO).
local function ClipOf(id)
    local cvid = id:match("^cv:(.+)$")
    if cvid then
        local tbl = _G.TRT and _G.TRT.CV_AUDIO
        local a = tbl and tbl[cvid]
        return a and a.len, ((_G.TRT and _G.TRT.CV_SND_DIR) or "Sounds/CV/") .. cvid .. ".ogg"
    end
    local a = CFG.AUDIO[id]
    return a and a.len, CFG.SND_DIR .. id .. ".ogg"
end

local txn = 0
--- Chained transmission: seq = { ch = "<CHAN>", id | pause(s), ... }. Returns airtime (s).
local function TxSeq(seq)
    local ch, p = CFG.CHAN[seq.ch], Player()
    if not (ch and p) then return 0 end
    local t = 0
    txn = txn + 1
    for i, id in ipairs(seq) do
        if type(id) == "number" then
            t = t + id
        else
            local len, file = ClipOf(id)
            if len then
                local name = "CD_" .. txn .. "_" .. i
                timer.scheduleFunction(function()
                    local u = Player(); if not u then return end
                    local pos = u:getPoint()
                    trigger.action.radioTransmission(file, { x = pos.x, y = pos.y + 30, z = pos.z },
                        ch.mod, false, ch.hz, CFG.TX_POWER, name)
                end, nil, timer.getTime() + t + 0.01)
                t = t + len + ((id == "cv:sq_up") and 0 or 0.03)
            else
                env.info("[CD] missing clip " .. tostring(id))
            end
        end
    end
    return t
end

--- Play voice clip <id> (or a token sequence table) on its agency frequency.
-- Returns clip length (s), 0 if none.
-- @param cut  true → stop the clip currently on air first (urgent calls).
local function Tx(id, cut)
    if cut and CD.txName then pcall(trigger.action.stopRadioTransmission, CD.txName) end
    if type(id) == "table" then return TxSeq(id) end
    local a = id and CFG.AUDIO[id]; if not a then return 0 end
    local ch, p = CFG.CHAN[a.ch], Player()
    if not (ch and p) then return 0 end
    local pos = p:getPoint()
    CD.txName = "CD_" .. id
    trigger.action.radioTransmission(CFG.SND_DIR .. id .. ".ogg",
        { x = pos.x, y = pos.y + 30, z = pos.z }, ch.mod, false, ch.hz, CFG.TX_POWER, CD.txName)
    return a.len
end

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
-- @param audio  Optional voice clip id (CFG.AUDIO key). Next clip waits for it.
local function Q(text, dur, after, fn, hold, audio)
    table.insert(CD.queue, { text = text, dur = dur or CFG.DUR_SHORT, after = after or 1,
                             fn = fn, hold = hold, audio = audio })
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
    local len = Tx(clip.audio)
    if clip.fn then pcall(clip.fn) end
    CD.qPlaying = true
    local wait = clip.hold or clip.dur
    if len > 0 then wait = math.max(wait, len + CFG.AUDIO_PAD) end
    timer.scheduleFunction(function() CD.qPlaying = false; QFire() end,
        nil, timer.getTime() + wait)
end

local function QPlay()
    if not CD.qPlaying and #CD.queue > 0 then QFire() end
end

local function QClear()
    CD.queue = {}
end

--- Pilot transmission followed by controller reply(ies).
-- @param audio  Optional voice clip id (pilot side, CFG.AUDIO key).
--- Token sequence on channel ch, wrapped in squelch bursts.
local function S(ch, ...)
    local out = { ch = ch, "cv:sq_up" }
    local function add(x)
        if type(x) == "table" then for _, y in ipairs(x) do add(y) end
        elseif x ~= nil then out[#out + 1] = x end
    end
    for _, x in ipairs({ ... }) do add(x) end
    out[#out + 1] = "cv:sq_dn"
    return out
end

local function PD(v) local t = {}; for c in tostring(v):gmatch("%d") do t[#t + 1] = "cv:p_" .. c end; return t end
local function OD(v) local t = {}; for c in tostring(v):gmatch("%d") do t[#t + 1] = "o_" .. c end; return t end

--- Pilot "angels N, state X.Y".
local function PAS(u)
    local i, f = State(u):match("^(%d+)%.(%d)$")
    return { "cv:p_angels", PD(Angels(u)), 0.15, "cv:p_state", PD(i or "0"), "cv:p_point", PD(f or "0") }
end

--- Overlord "bears XXX for YY".
local function OBR(from, to)
    local b = string.format("%03d", math.floor(BrgMag(from, to) + 0.5) % 360)
    return { "o_bears", OD(b), "o_for", OD(math.floor(Dist2D(from, to) + 0.5)) }
end

--- Pilot spelling of an MGRS string: digits, phonetic letters, short pauses.
local function PSpell(str)
    if not str or str == "unknown" then return { "cv:p_unknown" } end
    local t = {}
    for c in str:gmatch(".") do
        if c:match("%d") then t[#t + 1] = "cv:p_" .. c
        elseif c:match("%a") then t[#t + 1] = "cv:p_l_" .. c:lower()
        elseif c == " " then t[#t + 1] = 0.12 end
    end
    return t
end

--- Pilot TOT "1423L" -> "one four two three local".
local function PClock(abs)
    if not abs then return { "cv:p_unknown" } end
    return { PD(Clock(abs):sub(1, 4)), "cv:p_local" }
end

local function Pilot(text, audio)
    -- pilot text stays DUR_PILOT s; the reply may start PILOT_HOLD s after it
    -- (or after the pilot clip ends, whichever is later)
    Q("[" .. CFG.CS .. "] " .. text, CFG.DUR_PILOT, 0, nil, CFG.PILOT_HOLD, audio)
end

--- Automatic pilot acknowledgement of a hand-off, on the controller's frequency.
local function Ack(ch, wilco)
    local prev = CD.queue[#CD.queue]
    if prev then prev.hold = 0.1 end   -- start after the controller's audio, not its subtitle time
    Q("[" .. CFG.CS .. "] " .. CFG.CS .. (wilco and ", wilco." or ", switching."),
        CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD, S(ch, wilco and "p_wilco" or "p_switching"))
end

-- forward declarations
local SetPhase, MenuRebuild, Remind

-- ══════════════════════════════════════════════════════════════
--  RADIO CALLS — controller-initiated (hand-offs / threats)
-- ══════════════════════════════════════════════════════════════
local function C_DepSwitchStrike()
    Q(string.format("[DEPARTURE] %s, Departure. Switch Strike, %s.", CFG.CS, CFG.FREQ.STRIKE),
        CFG.DUR_HANDOFF, 0, nil, nil, "dep_switch_strike")
    Ack("DEPARTURE")
end

local function C_OvlContactPointer(p)
    Q(string.format("[OVERLORD] %s, Overlord. %s %s. Pointer 11 is on station. "
        .. "Contact Pointer 11, %s. Return to this frequency on check-out.",
        CFG.CS, CFG.CP_NAME, BrgRng(p:getPoint(), CFG.CP_POS), CFG.FREQ.J1), CFG.DUR_LONG, 0, nil, nil,
        S("OVERLORD", "ovl_contact_pointer_a", OBR(p:getPoint(), CFG.CP_POS), 0.1, "ovl_contact_pointer_b"))
    Ack("OVERLORD")
end

local function C_OvlSwitchStrike(p)
    local c = Carrier()
    local mother = c and (", Mother " .. BrgRng(p:getPoint(), c:getPoint())) or ""
    Q(string.format("[OVERLORD] %s, Overlord%s. Switch Strike, %s.",
        CFG.CS, mother, CFG.FREQ.STRIKE), CFG.DUR_HANDOFF, 0, nil, nil,
        S("OVERLORD", "ovl_switch_strike_a", c and { "o_mother", OBR(p:getPoint(), c:getPoint()) }, 0.1,
          "ovl_switch_strike_b"))
    Ack("OVERLORD")
end

local function C_StrikeSwitchMarshal()
    Q(string.format("[STRIKE] %s, Strike. Switch Marshal, %s.", CFG.CS, CFG.FREQ.MARSHAL),
        CFG.DUR_SHORT + 2, 0, nil, nil, "str_switch_marshal")
    Ack("STRIKE")
end

-- Urgent calls bypass the queue: shown immediately, queued routine traffic is dropped.
local function C_Abort()
    QClear()
    Msg(string.format("[EYEBALL 11] %s, abort, abort, abort. Civilian vehicle in target area.", CFG.CS),
        CFG.DUR_URGENT + 2)
    Tx("eye_abort", true)
    SetFlag(201, 1)
end

local function C_Rearm()
    Q(string.format("[EYEBALL 11] %s, target area clear. Continue as briefed.", CFG.CS), 10, 6, nil, nil, "eye_area_clear")
    SetFlag(201, 2)
end

local function C_Manpads()
    Msg(string.format("[EYEBALL 11] %s, MANPADS launch observed one klick east of the target. "
        .. "Remain at or above hard deck, two-three thousand MSL.", CFG.CS), CFG.DUR_URGENT + 1)
    Tx("eye_manpads", true)
    SetFlag(203, 1)
end

local function C_CorridorDev()
    Msg(string.format("[STRIKE] %s, Strike. You are outside the return corridor. "
        .. "Turn now for the 050 radial.", CFG.CS), CFG.DUR_URGENT + 1)
    Tx("str_corridor", true)
    SetFlag(204, 1)
end

-- ══════════════════════════════════════════════════════════════
--  F10 ACTIONS — pilot-initiated
-- ══════════════════════════════════════════════════════════════
local function A_StrikeCheckInOut()
    local p = Player(); if not p then return end
    SetPhase("STRIKE_CHK")
    Pilot(string.format("Strike, %s, checking in outbound, passing angels %d, Kilo.", CFG.CS, Angels(p)),
        S("STRIKE", "p_str_out_a", PD(Angels(p)), 0.12, "cv:p_kilo"))
    Q(string.format("[STRIKE] %s, Strike, radar contact. Check Mode 4.", CFG.CS), CFG.DUR_SHORT, CFG.REPLY_GAP, nil, nil, "str_radar_contact")
    local sweetToOvl = function()
        Q(string.format("[STRIKE] %s, Mode 4 sweet. Kilo copied. Switch Overlord, %s.",
            CFG.CS, CFG.FREQ.OVL), CFG.DUR_SHORT + 2, 3, function() SetPhase("OVL_OUT") end, nil, "str_m4_sweet_ovl")
        Ack("STRIKE")
    end
    if not CD.inj.i2 and Roll(CFG.PROB_INJ2) then
        CD.inj.i2 = true
        SetFlag(202, 1)
        Q(string.format("[STRIKE] %s, Mode 4 sour. Recycle.", CFG.CS), CFG.DUR_URGENT, 4, nil, nil, "str_m4_sour")
        Q(string.format("[STRIKE] %s, Strike. Mode 4 sweet now.", CFG.CS), CFG.DUR_SHORT, 16, nil, nil, "str_m4_sweet_now")
        Q(string.format("[STRIKE] %s, Kilo copied. Switch Overlord, %s.", CFG.CS, CFG.FREQ.OVL),
            CFG.DUR_SHORT + 2, 2, function() SetPhase("OVL_OUT") end, nil, "str_kilo_ovl")
        Ack("STRIKE")
    else
        sweetToOvl()
    end
    QPlay()
end

local function A_OvlCheckIn()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, checking in as fragged, mission %s and %s, angels %d, state %s.",
        CFG.CS, CFG.MSN_J1, CFG.MSN_J2, Angels(p), State(p)), S("OVERLORD", "p_ovl_checkin_a", PAS(p)))
    Q(string.format("[OVERLORD] %s, Overlord, radar contact. Picture clean. "
        .. "Mission as fragged, Pointer 11 and Eyeball 11 on station. Proceed %s, %s. "
        .. "SAM activity reported in both target areas, %s. Report feet dry.",
        CFG.CS, CFG.CP_NAME, BrgRng(p:getPoint(), CFG.CP_POS), HD_TEXT),
        CFG.DUR_LONG + 4, CFG.REPLY_GAP, function() SetPhase("ENROUTE") end, nil,
        S("OVERLORD", "ovl_checkin_a", OBR(p:getPoint(), CFG.CP_POS), 0.15, "ovl_checkin_b"))
    QPlay()
end

local function A_OvlOffPointer()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, off Pointer 11, mission %s complete, angels %d, state %s. "
        .. "Ready for retasking.", CFG.CS, CFG.MSN_J1, Angels(p), State(p)),
        S("OVERLORD", "p_ovl_off_pointer_a", PAS(p), 0.15, "p_ovl_off_pointer_b"))
    Q(string.format("[OVERLORD] %s, Overlord, copy. Return to %s, %s. "
        .. "Eyeball 11 is on station. Contact Eyeball 11, %s.",
        CFG.CS, CFG.CP_NAME, BrgRng(p:getPoint(), CFG.CP_POS), CFG.FREQ.J2),
        CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("JTAC2") end, nil,
        S("OVERLORD", "ovl_off_pointer_a", OBR(p:getPoint(), CFG.CP_POS), 0.1, "ovl_off_pointer_b"))
    Ack("OVERLORD")
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
        Clock(CD.j1.tot), Clock(CD.j2.tot), CD.j1.size, CD.j2.size),
        S("OVERLORD", "i_head", "i_l1", "i_l2",
          "i_l3", PSpell(CD.j1.pos and MGRS(CD.j1.pos)), 0.1, "cv:p_and", PSpell(CD.j2.pos and MGRS(CD.j2.pos)), 0.25,
          "i_l4", PClock(CD.j1.tot), 0.1, "cv:p_and", PClock(CD.j2.tot), 0.25,
          "i_l5", PD(CD.j1.size), "cv:p_and", PD(CD.j2.size), "i_l5b", "i_rmk"))
    -- INFLTREP is long — give it time on screen
    CD.queue[#CD.queue].dur  = CFG.DUR_LONG + 4
    CD.queue[#CD.queue].hold = 8
    local t = Tanker()
    local tkr = t and string.format("Texaco 11 %s, angels %d", BrgRng(p:getPoint(), t:getPoint()), Angels(t))
                or "Texaco 11 on station"
    Q(string.format("[OVERLORD] %s, Overlord, copy INFLTREP. %s, TACAN 21 Yankee. Switch Texaco, %s.",
        CFG.CS, tkr, CFG.FREQ.TKR), CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("REFUEL") end, nil,
        t and S("OVERLORD", "ovl_inflrep_a", OBR(p:getPoint(), t:getPoint()), 0.08, "o_angels", OD(Angels(t)), 0.15,
                "ovl_inflrep_b")
          or S("OVERLORD", "ovl_inflrep_nt"))
    Ack("OVERLORD")
    QPlay()
end

local function A_TexacoCheckIn()
    local p = Player(); if not p then return end
    CD.tkrCheckedIn = true
    Pilot(string.format("Texaco 11, %s, checking in, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
        S("TEXACO", "p_tkr_checkin_a", PAS(p)))
    Q(string.format("[TEXACO 11] %s, Texaco 11, angels 15. Cleared to join, left observation. "
        .. "Port drogue, call pre-contact.", CFG.CS), CFG.DUR_LONG - 2, CFG.REPLY_GAP, nil, nil, "tkr_checkin")
    QPlay()
    MenuRebuild()
end

local function A_OvlRTB()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    local c = Carrier()
    local from = (CD.phase == "TKR_DONE") and "off Texaco" or "no tanker required"
    Pilot(string.format("Overlord, %s, %s, RTB, angels %d, state %s.", CFG.CS, from, Angels(p), State(p)),
        S("OVERLORD", (CD.phase == "TKR_DONE") and "p_ovl_rtb_tkr_a" or "p_ovl_rtb_notkr_a", PAS(p)))
    local mother = c and (" Mother " .. BrgRng(p:getPoint(), c:getPoint()) .. ".") or ""
    Q(string.format("[OVERLORD] %s, Overlord, RTB approved.%s Recover via the 050 return corridor. "
        .. "Report feet wet.", CFG.CS, mother), CFG.DUR_LONG, CFG.REPLY_GAP,
        function() SetPhase("RTB") end, nil,
        S("OVERLORD", "ovl_rtb_a", c and { "o_mother", OBR(p:getPoint(), c:getPoint()) }, 0.15, "ovl_rtb_b"))
    QPlay()
end

local function A_OvlAbort()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    local c = Carrier()
    Pilot(string.format("Overlord, %s, mission abort, RTB, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
        S("OVERLORD", "p_ovl_abort_a", PAS(p)))
    local mother = c and (" Mother " .. BrgRng(p:getPoint(), c:getPoint()) .. ".") or ""
    Q(string.format("[OVERLORD] %s, Overlord, copy abort. RTB approved.%s Recover via the 050 return corridor. "
        .. "Report feet wet.", CFG.CS, mother), CFG.DUR_LONG, CFG.REPLY_GAP,
        function() SetPhase("RTB") end, nil,
        S("OVERLORD", "ovl_abort_a", c and { "o_mother", OBR(p:getPoint(), c:getPoint()) }, 0.15, "ovl_rtb_b"))
    QPlay()
end

local function A_StrikeCheckInIn()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Strike, %s, inbound, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
        S("STRIKE", "p_str_inbound_a", PAS(p)))
    Q(string.format("[STRIKE] %s, Strike, radar contact, Mode 4 sweet. Continue the 050 corridor. "
        .. "Switch Marshal at 50 miles, %s.", CFG.CS, CFG.FREQ.MARSHAL),
        CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("INBOUND") end, nil, "str_inbound")
    Ack("STRIKE", true)
    QPlay()
end

local function A_FeetReport()
    local kind = CD.feetPending; if not kind then return end
    CD.feetPending = nil
    local word = (kind == "DRY") and "feet dry" or "feet wet"
    Pilot(string.format("Overlord, %s, %s.", CFG.CS, word), "p_ovl_feet_" .. kind:lower())
    Q(string.format("[OVERLORD] %s, Overlord, copy %s.", CFG.CS, word), CFG.DUR_SHORT, CFG.REPLY_GAP, nil, nil, "ovl_feet_" .. kind:lower())
    QPlay()
    MenuRebuild()
end

local function A_Picture()
    if not OVL_PHASES[CD.phase] then
        Msg("[CAS-1] Not checked in with OVERLORD.", 7); return
    end
    Pilot(string.format("Overlord, %s, request picture.", CFG.CS), "p_ovl_picture")
    Q(string.format("[OVERLORD] %s, Overlord, picture clean. SAM activity reported in the target areas.",
        CFG.CS), CFG.DUR_SHORT + 2, CFG.REPLY_GAP, nil, nil, "ovl_picture")
    QPlay()
end

-- "What is my next call?" — single-line hint per phase
local NEXT = {
    IDLE       = "Launch. CASE III departure on Departure " .. CFG.FREQ.DEP .. ".",
    DEPARTURE  = "On Departure " .. CFG.FREQ.DEP .. ". CASE III: airborne / 2.5 / arcing / established "
                 .. "are automatic, Popeye / on top via F10 > CV COMMS. CASE I/II: hand-off to Strike at "
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
    if ph == "ENROUTE" or ph == "JTAC1" or ph == "J1_OFF" or ph == "JTAC2" or ph == "J2_OFF" then
        a[#a+1] = { "OVERLORD: RTB (mission abort)", A_OvlAbort }
    end
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
         .. "COMM1-01  262.00 AM   TOWER / PADDLES (CASE I/II)\n"
         .. "COMM1-02  269.00 AM   DEPARTURE\n"
         .. "COMM1-03  265.00 AM   STRIKE\n"
         .. "COMM1-04  333.30 AM   POINTER 11  (JTAC-1)\n"
         .. "COMM1-05  333.40 AM   EYEBALL 11  (JTAC-2)\n"
         .. "COMM1-06  251.10 AM   OVERLORD\n"
         .. "COMM1-07  252.10 AM   TEXACO 11\n"
         .. "COMM1-15  263.00 AM   APPROACH (CASE II/III)\n"
         .. "COMM1-16  261.00 AM   MARSHAL\n"
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
    CD.dueSince, CD.nextRemind = timer.getTime(), nil
    env.info(string.format("[CD] %s → %s", CD.phase, new))
    CD.phase = new

    if new == "JTAC1" or new == "JTAC2" or new == "J1_OFF" or new == "J2_OFF" then
        SetFlag(200, 1)
    else
        SetFlag(200, 0)
    end

    if new == "DEPARTURE" then
        Msg("[CAS-1] All radio calls: F10 > CAS-1 COMMS. \"Show: next call\" lists the next step.", CFG.DUR_HANDOFF)
    elseif new == "J1_OFF" then
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
        local T = _G.TRT
        if T and T.CV and (T.CV.depActive or T.CV_DEP_CLEARED) then
            -- CASE III: CV_Comms runs the Departure dialogue ("cleared to switch")
            if T.CV_DEP_CLEARED then SetPhase("STRIKE_OUT") end
        elseif cPos and Dist2D(pPos, cPos) >= CFG.DEP_HANDOFF_NM then
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
                .. "return to Overlord, %s.", CFG.CS, CFG.FREQ.OVL), CFG.DUR_SHORT + 4, 0, nil, nil, "tkr_done")
            Ack("TEXACO")
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
-- Pending pilot call → repeated controller call (+ F10 hint)
local REMIND = {
    STRIKE_OUT = function() return string.format("[DEPARTURE] %s, Departure. Contact Strike, %s, how copy?", CFG.CS, CFG.FREQ.STRIKE), "dep_contact_strike" end,
    OVL_OUT    = function() return string.format("[STRIKE] %s, Strike. Contact Overlord, %s.", CFG.CS, CFG.FREQ.OVL), "str_contact_ovl" end,
    J1_OFF     = function() return string.format("[OVERLORD] %s, Overlord. Say status.", CFG.CS), "ovl_say_status" end,
    J2_OFF     = function() return string.format("[OVERLORD] %s, Overlord. Say status, advise when ready for tanker.", CFG.CS), "ovl_say_status_tkr" end,
    REFUEL     = function()
        if CD.tkrCheckedIn then return nil end
        return string.format("[OVERLORD] %s, Overlord. Texaco 11 is on %s.", CFG.CS, CFG.FREQ.TKR), "ovl_texaco_freq"
    end,
    TKR_DONE   = function() return string.format("[OVERLORD] %s, Overlord. Say intentions.", CFG.CS), "ovl_say_int" end,
    STRIKE_IN  = function() return string.format("[OVERLORD] %s, Overlord. Contact Strike, %s, how copy?", CFG.CS, CFG.FREQ.STRIKE), "ovl_contact_strike" end,
}

Remind = function(now)
    local f = REMIND[CD.phase]
    if not f or CD.awaiting or not CD.dueSince then return end
    if not CD.nextRemind then CD.nextRemind = CD.dueSince + CFG.REMIND_FIRST end
    if now < CD.nextRemind or CD.qPlaying then return end
    CD.nextRemind = now + CFG.REMIND_EVERY
    local txt, audio = f(); if not txt then return end
    Q(txt, CFG.DUR_HANDOFF, 0, nil, nil, audio)
    QPlay()
    Msg("[CAS-1] F10 > CAS-1 COMMS - " .. (NEXT[CD.phase] or ""), CFG.DUR_HANDOFF)
end

local function CD_Tick(_, t)
    if CD.phase == "DONE" or CD.phase == "RECOVERY" then return end
    TrackTargets()
    local p = Player()
    if not p then return t + CFG.TICK end
    if not CD.menu.root then MenuRebuild() end
    EvalPhase(p, Carrier())
    Remind(t)
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
    env.info("[CD] Comms_Director v1.4.3 online — CAS-1 Syria")
end

CD_Init()
