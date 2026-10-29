-- JTAC_Controller | v0.4.0
--[[
  v0.4.0 (TEST-J1 flight #3, 2026-10-29): threat-aware FAH and IP. The keyhole IP 220/10 sent the hero
         straight at the YD67 SA-10 (34 NM SW of the target, FireGate distance gate 30 NM): shot at
         25 NM. JP 3-09.3: route aircraft away from known threats; the IP / offset keep aircrews away
         from them. Now:
           * threats = RED ground groups with a SAM launcher type in CFG.THREAT.TYPES whose ceiling is
             above CFG.THREAT.HARD_DECK_FT; a SAM_FireGate (>= v1.5.4, TRT.FG) rule overrides: distance
             gate -> radius gateNM (fire opens there; the hysteresis only delays closing), ceiling gate
             -> ceiling ceilingFt + hysteresisFt
             (YE53 SA-3 / BV22 SA-6 / HS02 SA-6 at 19,500 ft drop out above the 20,000 ft deck).
           * a FAH window is rejected when the run-in (reciprocal of its centre / edges, CFG.THREAT.PATH_NM)
             passes within radius + MARGIN_NM of a threat; with no clean window the least-risk one is
             taken and logged as WARN.
           * a pre-briefed IP is used only if its run-in fits the FAH and is clear; otherwise a keyhole
             IP at 10 / 8 / 12 / 6 NM, the first with a clear run-in.
           * sitrep / remarks name the threats whose ring reaches within CFG.THREAT.REMARK_NM of the target.
  v0.3.2: hard deck 20,000 ft MSL in the remarks (Comms_Director v1.6.3).
  v0.3.1 (flight #2 menu case): no menu change without a press where avoidable - the JTAC items no
         longer disappear while the JTAC is transmitting (busy), and LASER ON stays offered after
         TEN SECONDS until it is pressed (v0.3.0 reverted it to TEN SECONDS after 30 s, which rebuilt
         the menu 5 s before a misrouted press). LASER_TIMEOUT_S 120 -> 180 (Maverick set-ups from
         the hard deck start lasing earlier).
  v0.3.0 (TEST-J1 flight 2026-10-29 #2):
    * Observation post search widened: sector op.brg +/- op.sector deg, op.dmin..op.dmax m from the
      target, ~op.step m grid; among the points with LOS to every target unit the JTAC prefers high
      ground, then closeness to <brg, m>. The log gives the rejection counts (surface / too close /
      LOS). v0.2.0 found nothing within 800 m of 2.5 km SW / W (197 points each) -> JTACs stayed
      300 / 350 m from their targets and Pointer's FAH came out 205-235 against an IP heading of 107.
    * IP / FAH consistency: when the pre-briefed IP's run-in is more than CFG.IP_MAX_OFF deg from the
      FAH centre, Line 1 becomes a keyhole IP (JFIRE fig 7: target = Echo, "brg/NM" from Echo,
      magnetic), on the reciprocal of the FAH centre at CFG.KEYHOLE_NM. Lines 2 / 3 follow it.
    * "OFF (dry)" offered after IN / CLEARED HOT when nothing was released; it closes the clearance,
      the next pass needs a new IN (flight #2: no way to end a dry pass, clearance stayed open).
    * CFG.VERSION was left at 0.1.0 in v0.2.0 (log said v0.1.0) - fixed.
  v0.2.0 (CAS-1 test flight 2026-10-29, Pointer 11):
    * JTAC observation post (CFG.JTACS[k].op): at mission start the JTAC group is moved to the
      land / road point nearest to <brg, m> from its target group (search radius r, step 100 m)
      that has terrain LOS to every target unit and is at least min_tgt_m from all of them, by
      destroying the ME group and spawning the same type / name there (invisible, immortal, weapon
      hold). Reason: Pointer 11 sat 300 m east of its target, so every sensible run-in from CP
      TIGER pointed at the JTAC; Eyeball 11 sat 350 m from the SA-8s. No point found -> ME position.
    * IP LYNX moved onto the CP TIGER - target line, 12 NM from the target (37S BV 4071 2864).
      With the JTAC south-west of the target the FAH search now yields 080-110 (mag) for Pointer.
    * Unauthorized release (not cleared, or after an abort): 1st -> "you were not cleared, hold
      fire" + on-screen [CAS-1] note; 2nd -> the JTAC terminates control ("cleared off, return to
      Overlord"), phase TERMINATED (laser off after the weapon in flight lands). Comms_Director
      >= v1.6.2 treats TERMINATED like a finished tasking.
  Scripted JTAC (replaces the native DCS JTAC) — TRT Syria Dynamic Template (template-level module)
  Plan: project doc claude/jtac-plan-2026-10-29.md (J2 = this version: text only, no voice yet).
  Doctrine: JP 3-09.3 (2009) Ch V, JFIRE (Nov 2023) CAS section, brevity and laser examples.

  FLOW PER JTAC (hero only; state is kept per JTAC key so more flights can be added later)
    IDLE ─hand-off→ CHECKIN ─F10 check-in→ SITREP ─F10 ready→ GAMEPLAN ─F10 ready→ NINE
    ─F10 ready→ READBACK (multiple choice: Line 4 → Line 6 → restrictions) ─correct→ ATTACK
    ATTACK: IP INBOUND → CONTINUE · IN (direction auto) → CLEARED HOT | CONTINUE | ABORT <code> ×3
            release (S_EVENT_SHOT) → "rifle" / "one away" · OFF (direction auto)
            weapon impact → good hits / "from your hits, <dir> <m>" → next aim unit (re-attack, no new 9-line)
            all target groups dead → SALT-R BDA → DONE (Comms_Director moves on to OVERLORD)
    Correlation (F10): TALLY / CAPTURED / NO JOY. BOT needs TALLY or CAPTURED before CLEARED HOT.
    Laser (F10, pilot-commanded, JFIRE examples): TEN SECONDS → LASER ON → JTAC "LASING <code>"
            → SPOT | NEGATIVE LASER → SHIFT (aim unit changed) → CEASE LASER. The spot
            (Spot.createLaser from the JTAC unit) exists only between LASER ON and CEASE LASER;
            CFG.LASER_TIMEOUT_S switches it off if CEASE LASER never comes (logged).
  Type of control: "auto" = Type 1 only if day, hero within CFG.TYPE1.max_nm, below max_agl_ft and
  JTAC terrain LOS to the hero at the game plan; otherwise Type 2. With the CAS-1 hard deck
  (20,000 ft MSL) this is always Type 2.
  Abort code: challenge-reply. Pilot passes CFG.ABORT.challenge at check-in; the JTAC aborts with
  the reply letter from CFG.AUTH (kneeboard 06 AUTH): row = 1st challenge letter, reply = the letter
  to the RIGHT of the 2nd challenge letter in that row (wraps). Simplified DRYAD-style, not a real system.
  Readback quiz: 4 options per item (correct + numeric distractors), CFG.RB_PROMPT_S -> "say readback".
  Troops in contact: when Comms_Director picks the TIC JTAC (TRT.CD.tic), the friendly group
  CFG.FRIENDLY ("Bravo 2-1") is spawned near that JTAC's target (invisible, immortal, weapon hold);
  it is then that JTAC's Line 8 friendlies. Otherwise Line 8 = the JTAC unit itself.
  FAH: window of 2*CFG.FAH_HALF deg, every heading in it at least CFG.LASER_SAFE deg off the laser-target
  line and at most CFG.LASER_MAX deg off it (JP V-73), and at least CFG.FRIEND_SEP deg off the
  target-friendlies axis; among those the one closest to the IP->target heading.

  NOT IN v0.1.0 (plan J3-J5): scoring (events are logged "[JC] ..." and published via TRT.JC.on),
  voice clips, danger close, AI flights in the stack, native|scripted switch in the template.
  Native JTAC must be removed from the JTAC groups in the ME (tools/strip_native_jtac.py), otherwise
  both talk.

  Integration: Comms_Director >= v1.6.0 exports TRT.CD_RADIO (shared radio queue) and stands down
  its own readback / laser calls / release calls / INJ-1 abort while TRT.JC.active. Without
  Comms_Director (CFG.HANDOFF = "RANGE") the hand-off is the hero within CFG.HANDOFF_NM of the target.
  Menu: F10 > COMMS via Menu_Manager (order 15, before Comms_Director).
  API: TRT.JC.version, .active, .st[key], .on(fn) -> fn(ev, data), .aimUnit(key)
  Load order: after Menu_Manager; any order relative to Comms_Director.
  Unverified in DCS [V]: coord.MGRStoLL input format, Spot.createLaser seen by the Hornet LST and the
  AGM-65E, coalition.addGroup country of the JTAC unit, atmosphere.getWind sign.
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.JC then env.info("[JC] already loaded, second copy ignored") return end

-- ══════════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════════
local CFG = {
    VERSION      = "0.4.0",
    PLAYER_UNIT  = "Player_01",
    CS           = "HORNET 51",
    NUM_TYPE     = "one Hornet",
    CAPS         = "ATFLIR, laser spot tracker",
    MAGVAR       = 5,            -- east; magnetic = true - MAGVAR (same as Comms_Director)
    TICK         = 1.0,
    HANDOFF      = "CD",         -- "CD" (TRT.CD.phase == jtac.cdPhase) | "RANGE"
    HANDOFF_NM   = 25,
    REATTACK_NM  = 30,           -- items stay offered (re-attack after abort / tanker) within this range
    CP           = { name = "CP TIGER", pos = { x = 73640, z = -39914 } },
    INTERNAL_FUEL_LB = 10860,
    BINGO_LB     = 5000,         -- playtime estimate only (placeholder)
    BURN_LB_MIN  = 80,
    DAY          = { from = 6 * 3600, to = 18 * 3600 },   -- crude day window (local mission time)
    TYPE1        = { max_nm = 5, max_agl_ft = 15000 },
    RB_PROMPT_S  = 45,
    FAH_HALF     = 15,
    LASER_SAFE   = 10,
    LASER_MAX    = 60,
    FRIEND_SEP   = 25,           -- 30 left no window when the JTAC is both designator and friendly
    LASER_TIMEOUT_S = 180,
    LASER_SRC    = { x = 0, y = 3, z = 0 },
    EYE_M        = 2.5,
    IMPACT_WAIT_S = 3,
    THREAT_NM    = 8,
    -- v0.4.0: threats to the run-in (typical envelopes, NM / ft MSL; not verified against DCS models)
    THREAT = {
        HARD_DECK_FT = 20000, MARGIN_NM = 2, PATH_NM = 14, REMARK_NM = 15,
        TYPES = {
            ["S-300PS 5P85C ln"] = { nm = 40, ceil = 90000, label = "SA-10" },
            ["S-300PS 5P85D ln"] = { nm = 40, ceil = 90000, label = "SA-10" },
            ["5p73 s-125 ln"]    = { nm = 13, ceil = 60000, label = "SA-3" },
            ["5p73 V-601P ln"]   = { nm = 13, ceil = 60000, label = "SA-3" },
            ["Kub 2P25 ln"]      = { nm = 13, ceil = 46000, label = "SA-6" },
            ["SA-11 Buk LN 9A310M1"] = { nm = 19, ceil = 72000, label = "SA-11" },
            ["CHAP_TorM2"]       = { nm = 8,  ceil = 33000, label = "SA-15 (M2)" },
            ["Tor 9A331"]        = { nm = 6.5, ceil = 19700, label = "SA-15" },
            ["Osa 9A33 ln"]      = { nm = 5.5, ceil = 16500, label = "SA-8" },
        },
    },
    IP_MAX_OFF   = 45,          -- deg: pre-briefed IP run-in vs FAH centre, beyond -> keyhole IP
    KEYHOLE_NM   = 10,
    ABORT        = { challenge = "BR" },
    -- kneeboard 06 AUTH (tools/make_kneeboard.py AUTH, same seed 20261029) - keep identical
    AUTH = {
        A = "BSIAZTXKDGPQVEMCNWFJYLUHOR", B = "AXYSFZJLHPVECBNDRQTWMOGIUK", C = "GDSIVRKUXELOCFHWJQBZYANMPT",
        D = "TVYMLCBUWEHRDGKAFJQZIXSNPO", E = "GWFIYONQJDATVUZCLMSBKPHEXR", F = "YBOLUVNIPHTKAFQDSRXMEGJZCW",
        G = "BFMUPEQNRLKSDZXAGVOITCHJWY", H = "MLARHQFGXKSZYIWVPJEONBCTUD", I = "LGOXJHDCEWMSYNTFARVIKBUPQZ",
        J = "MHFEZPQKCXVJRLOIYUWBNAGTDS", K = "EUQKCOBNGAYHLPTMFRWXJIZSVD", L = "THVCREZAGYBFQXIUNLOPMJDWSK",
        M = "PVJCEWGTSYHIMZONLDRQKAXUBF", N = "ATWGDVJHPBLOXMICSNUEFQKYZR", O = "UABNFJQGLPIEZTXOMVCSKYDRHW",
        P = "XMSTRKLFOGVBQWZEDUPJACHIYN", Q = "TULZBGPAXRHWFYJKSOQENVDIMC", R = "CSUIOLMHNFXQGDWZPAJETVBYRK",
        S = "FDNESUCBQIXZMVJKTWLRYHGOAP", T = "HVAJXUYTEKLWGISDOFMPQRZCBN", U = "TZGCEPRHIVAQXBFSYUJDWMLKON",
        V = "QXCGHNDVZTOJAUESBYMFPWRLIK", W = "FIZAVYBLSJQHEXMKWNPOTRUDCG", X = "XCSJZBDMTHQEAUFLRGPOINWKYV",
        Y = "MNFYBDGIUHLJZSKRPQOWCATXVE", Z = "MBSLRJTUINYWQDCXPVHEZFOKAG",
    },
    -- aim order inside a target group (SAM / radar first), then ME order
    PRIORITY = { "Osa 9A33 ln", "Strela-10M3", "Tor 9A331", "Kub 1S91 str", "Kub 2P25 ln",
                 "2S6 Tunguska", "ZSU-23-4 Shilka" },
    LABEL = {
        ["Osa 9A33 ln"] = "SA-8 launcher", ["Strela-10M3"] = "SA-13 launcher", ["Tor 9A331"] = "SA-15",
        ["Kub 1S91 str"] = "SA-6 radar", ["Kub 2P25 ln"] = "SA-6 launcher", ["2S6 Tunguska"] = "SA-19",
        ["ZSU-23-4 Shilka"] = "ZSU-23-4", ["SA-14 Strela-3 manpad"] = "SA-14 MANPADS",
        ["Igla manpad INS"] = "SA-18 MANPADS", ["p-19 s-125 sr"] = "SA-3 radar", ["snr s-125 tr"] = "SA-3 radar",
        ["5p73 s-125 ln"] = "SA-3 launcher", ["5p73 V-601P ln"] = "SA-3 launcher",
        ["T-55"] = "T-55 tank", ["T-72B"] = "T-72 tank", ["BTR-80"] = "BTR", ["BMP-1"] = "BMP", ["BMP-2"] = "BMP",
        ["Ural-4320T"] = "truck", ["Infantry AK"] = "infantry", ["Infantry AK ver2"] = "infantry",
    },
    FRIENDLY = { name = "Bravo 2-1", cs = "BRAVO 2-1",
                 units = { "M-2 Bradley", "M-2 Bradley", "Soldier M4", "Soldier M4", "Soldier M4" } },
    DUR = { pilot = 8, short = 9, long = 18, nine = 28, hold_pilot = 2.5, hold = 5,
            fast_after = 0.2, fast_hold = 1.5 },   -- attack / laser calls: short gaps (time critical)

    JTACS = {
        J1 = { cs = "POINTER 11", disp = "Pointer 11", group = "JTAC-1", cdPhase = "JTAC1", btn = 4,
               msn = "4101", targets = { "SAM BV51 (SA-13)-1" },
               ip = { name = "LYNX", mgrs = "37S BV 4071 2864" }, egress = "north to TIGER",
               mark = { kind = "laser", code = 1688 }, control = "auto", method = "BOT",
               ord = "one AGM-65E", friendly_ofs = { brg = 200, m = 1200 }, abort_inject = 0,
               op = { brg = 238, m = 2500, sector = 60, dmin = 1500, dmax = 4000, step = 150 } },
        J2 = { cs = "EYEBALL 11", disp = "Eyeball 11", group = "JTAC-2", cdPhase = "JTAC2", btn = 5,
               msn = "4102", targets = { "SAM YE53 (SA-8)-1" },
               ip = { name = "PUMA", mgrs = "36S YE 4714 5182" }, egress = "northwest, feet wet",
               mark = { kind = "laser", code = 1688 }, control = "auto", method = "BOT",
               ord = "one GBU-12", friendly_ofs = { brg = 200, m = 1000 }, abort_inject = 30,
               op = { brg = 250, m = 2500, sector = 60, dmin = 1500, dmax = 4000, step = 150 } },
    },
    ORDER = { "J1", "J2" },
}

local PHON = { A = "Alfa", B = "Bravo", C = "Charlie", D = "Delta", E = "Echo", F = "Foxtrot", G = "Golf",
    H = "Hotel", I = "India", J = "Juliett", K = "Kilo", L = "Lima", M = "Mike", N = "November", O = "Oscar",
    P = "Papa", Q = "Quebec", R = "Romeo", S = "Sierra", T = "Tango", U = "Uniform", V = "Victor",
    W = "Whiskey", X = "X-ray", Y = "Yankee", Z = "Zulu" }
local NUMW = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten" }
local DIR8_TXT = { "north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest" }

-- ══════════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════════
local JC = { version = CFG.VERSION, active = true, CFG = CFG, st = {}, subs = {}, queue = {}, qBusy = false }
TRT.JC = JC
for _, k in ipairs(CFG.ORDER) do JC.st[k] = { phase = "IDLE" } end

local function Log(s) env.info("[JC] " .. s) end
function JC.on(fn) JC.subs[#JC.subs + 1] = fn end
local function Emit(ev, data)
    Log("EVENT " .. ev)
    for _, fn in ipairs(JC.subs) do
        local ok, err = pcall(fn, ev, data)
        if not ok then Log("subscriber error: " .. tostring(err)) end
    end
end

-- ══════════════════════════════════════════════════════════════
--  UTILITIES
-- ══════════════════════════════════════════════════════════════
local function Hero()
    local u = Unit.getByName(CFG.PLAYER_UNIT)
    if u and u:isExist() then return u end
end
local function Alive(u) return u and u:isExist() and u:getLife() >= 1 end
local function D2(a, b) local dx, dz = a.x - b.x, a.z - b.z return math.sqrt(dx * dx + dz * dz) end
local function NM(m) return m / 1852 end
local function BrgT(a, b) return math.deg(math.atan2(b.z - a.z, b.x - a.x)) % 360 end
local function Mag(t) return (t - CFG.MAGVAR) % 360 end
local function AngD(a, b) return math.abs((a - b + 180) % 360 - 180) end
local function Dir8(brg) return DIR8_TXT[math.floor(((brg % 360) + 22.5) / 45) % 8 + 1] end
local function R5(v) return (math.floor(v / 5 + 0.5) * 5) % 360 end
local function H3(v) return string.format("%03d", math.floor(v + 0.5) % 360) end
local function GroundY(p) local ok, h = pcall(land.getHeight, { x = p.x, y = p.z }) return ok and h or (p.y or 0) end
local function Eye(p, h) return { x = p.x, y = GroundY(p) + (h or CFG.EYE_M), z = p.z } end
local function Clock(abs)
    local t = math.floor(abs or timer.getAbsTime()) % 86400
    return string.format("%02d%02d", math.floor(t / 3600), math.floor((t % 3600) / 60))
end
local function Word(n) return NUMW[n] or tostring(n) end

local function MGRS(pos, digits)
    local ok, s = pcall(function()
        local lat, lon = coord.LOtoLL(pos)
        local m = coord.LLtoMGRS(lat, lon)
        local div = (digits == 5) and 1 or 10
        local fmt = (digits == 5) and "%s %s %05d %05d" or "%s %s %04d %04d"
        return string.format(fmt, m.UTMZone, m.MGRSDigraph, math.floor(m.Easting / div), math.floor(m.Northing / div))
    end)
    return ok and s or "unknown"
end

--- "37S BV 8009 0816" -> vec3 (nil on failure). Grid digits are scaled to metres.
local function MGRStoPos(str)
    local z, d, e, n = str:match("^(%d+%a)%s+(%a%a)%s+(%d+)%s+(%d+)$")
    if not z then return nil end
    local function m(s) return tonumber(s) * 10 ^ (5 - #s) end
    local ok, pos = pcall(function()
        local lat, lon = coord.MGRStoLL({ UTMZone = z, MGRSDigraph = d, Easting = m(e), Northing = m(n) })
        return coord.LLtoLO(lat, lon, 0)
    end)
    if ok and pos then return pos end
    Log("MGRS parse failed: " .. str .. " " .. tostring(pos))
end

local function Msg(text, dur)
    local u = Hero()
    if u then trigger.action.outTextForGroup(u:getGroup():getID(), text, dur or 10) end
end

local function MenuRefresh() if TRT.Menu then pcall(TRT.Menu.Refresh) end end

-- ══════════════════════════════════════════════════════════════
--  RADIO (shared Comms_Director queue when present, own text queue otherwise)
-- ══════════════════════════════════════════════════════════════
local function OwnFire()
    local it = table.remove(JC.queue, 1)
    if not it then JC.qBusy = false; return end
    JC.qBusy = true
    timer.scheduleFunction(function()
        Msg(it.text, it.dur)
        if it.fn then pcall(it.fn) end
        timer.scheduleFunction(function() OwnFire() end, nil, timer.getTime() + (it.hold or it.dur))
    end, nil, timer.getTime() + (it.after or 0) + 0.01)
end

--- text, display s, gap before (s), callback at start, hold (s until the next may start)
local function Say(text, dur, after, fn, hold)
    local cd = TRT.CD_RADIO
    if cd and cd.Q then
        cd.Q(text, dur, after, fn, hold)
        cd.QPlay()
        return
    end
    JC.queue[#JC.queue + 1] = { text = text, dur = dur, after = after, fn = fn, hold = hold }
    if not JC.qBusy then OwnFire() end
end

local function J(k) return CFG.JTACS[k] end
local function Pilot(text, fn)
    Say("[" .. CFG.CS .. "] " .. text, CFG.DUR.pilot, 0.3, fn, CFG.DUR.hold_pilot)
end
local function Jtac(k, text, dur, fn, hold)
    Say("[" .. J(k).cs .. "] " .. text, dur or CFG.DUR.short, 1.5, fn, hold or CFG.DUR.hold)
end
--- time-critical attack / laser traffic
local function PilotF(text, fn)
    Say("[" .. CFG.CS .. "] " .. text, CFG.DUR.pilot, CFG.DUR.fast_after, fn, CFG.DUR.fast_hold)
end
local function JtacF(k, text, fn)
    Say("[" .. J(k).cs .. "] " .. text, CFG.DUR.short, 0.8, fn, CFG.DUR.fast_hold)
end

-- ══════════════════════════════════════════════════════════════
--  TARGETS / GEOMETRY
-- ══════════════════════════════════════════════════════════════
local function JtacUnit(k)
    local g = Group.getByName(J(k).group)
    if not g or not g:isExist() then return nil end
    for _, u in ipairs(g:getUnits() or {}) do if Alive(u) then return u end end
end

local function TargetUnits(k)
    local out = {}
    for _, gn in ipairs(J(k).targets) do
        local g = Group.getByName(gn)
        if g and g:isExist() then
            for _, u in ipairs(g:getUnits() or {}) do if Alive(u) then out[#out + 1] = u end end
        end
    end
    return out
end

local function Centroid(units)
    if #units == 0 then return nil end
    local sx, sz = 0, 0
    for _, u in ipairs(units) do local p = u:getPoint(); sx, sz = sx + p.x, sz + p.z end
    return { x = sx / #units, y = 0, z = sz / #units }
end

local PRIO = {}
for i, t in ipairs(CFG.PRIORITY) do PRIO[t] = i end
function JC.aimUnit(k)
    local best, bp
    for i, u in ipairs(TargetUnits(k)) do
        local p = PRIO[u:getTypeName()] or (100 + i)
        if not bp or p < bp then best, bp = u, p end
    end
    return best
end

local function Label(t) return CFG.LABEL[t] or t end

--- labels -> "SA-13 launcher and T-55 tank" / "two SA-8 launchers, BTR and T-72 tank"
local function DescribeLabels(labels)
    local cnt, order = {}, {}
    for _, l in ipairs(labels) do
        if not cnt[l] then cnt[l] = 0; order[#order + 1] = l end
        cnt[l] = cnt[l] + 1
    end
    local parts = {}
    for _, l in ipairs(order) do
        local pl = (l == "infantry" or l:find("MANPADS")) and l or (l .. "s")
        parts[#parts + 1] = (cnt[l] > 1) and (Word(cnt[l]) .. " " .. pl) or l
    end
    if #parts == 0 then return "nothing" end
    if #parts == 1 then return parts[1] end
    return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end

local function Describe(units)
    local labels = {}
    for _, u in ipairs(units) do labels[#labels + 1] = Label(u:getTypeName()) end
    return DescribeLabels(labels)
end

local function FriendlyUnit(k)
    local st = JC.st[k]
    if st.tic then
        local g = Group.getByName(CFG.FRIENDLY.name)
        if g and g:isExist() then
            local tp = Centroid(TargetUnits(k))
            local best, bd
            for _, u in ipairs(g:getUnits() or {}) do
                if Alive(u) then
                    local d = tp and D2(u:getPoint(), tp) or 0
                    if not bd or d < bd then best, bd = u, d end
                end
            end
            if best then return best, CFG.FRIENDLY.cs end
        end
    end
    return JtacUnit(k), J(k).disp
end

-- ── v0.4.0 threats ──────────────────────────────────────────────────────────────────
local function FGRule(gname)
    local fg = TRT.FG
    for _, r in ipairs((fg and fg.groups) or {}) do if r.name == gname then return r end end
end

--- Live threats that reach above the hard deck: { name, label, pos, nm, ceil }
local function Threats()
    local out = {}
    local T = CFG.THREAT
    for _, gr in ipairs(coalition.getGroups(coalition.side.RED, Group.Category.GROUND) or {}) do
        local sx, sz, n, ty = 0, 0, 0, nil
        for _, u in ipairs(gr:getUnits() or {}) do
            local d = Alive(u) and T.TYPES[u:getTypeName()]
            if d then
                local p = u:getPoint(); sx, sz, n = sx + p.x, sz + p.z, n + 1
                if not ty or d.nm > ty.nm then ty = d end
            end
        end
        if n > 0 then
            local th = { name = gr:getName(), label = ty.label, pos = { x = sx / n, y = 0, z = sz / n },
                         nm = ty.nm, ceil = ty.ceil }
            local r = FGRule(th.name)
            if r and r.mode == "distance" then th.nm, th.ceil, th.gate = r.gateNM or th.nm, 1e9, "distance"
            elseif r and r.mode == "ceiling" then th.ceil, th.gate = (r.ceilingFt or 0) + (r.hysteresisFt or 0), "ceiling" end
            if th.ceil > T.HARD_DECK_FT then out[#out + 1] = th end
        end
    end
    return out
end

--- Worst penetration (NM, > 0 = inside radius + margin) of the run-in that ends at aimPos on true
--- heading hdg, from len NM out (inbound path only).
local function PathRisk(threats, aimPos, hdg, len)
    local worst, who = -1e9, nil
    local r = math.rad((hdg + 180) % 360)
    for d = 0, len, 1 do
        local p = { x = aimPos.x + math.cos(r) * d * 1852, z = aimPos.z + math.sin(r) * d * 1852 }
        for _, t in ipairs(threats) do
            local pen = t.nm + CFG.THREAT.MARGIN_NM - NM(D2(p, t.pos))
            if pen > worst then worst, who = pen, t end
        end
    end
    return worst, who
end

local function WindowRisk(threats, aimPos, c)
    local w, who = -1e9, nil
    for _, h in ipairs({ c - CFG.FAH_HALF, c, c + CFG.FAH_HALF }) do
        local r, t = PathRisk(threats, aimPos, h % 360, CFG.THREAT.PATH_NM)
        if r > w then w, who = r, t end
    end
    return w, who
end

--- "SA-10 southwest 34" for threats whose ring reaches within REMARK_NM of the target
local function LongThreatText(threats, tp)
    local out = {}
    for _, t in ipairs(threats) do
        local d = NM(D2(tp, t.pos))
        if d - t.nm <= CFG.THREAT.REMARK_NM then
            out[#out + 1] = string.format("%s %s %d", t.label, Dir8(BrgT(tp, t.pos)), math.floor(d + 0.5))
        end
    end
    return out
end

--- FAH window (true degrees): centre, lo, hi.
local function ComputeFAH(k, aimPos, ipPos)
    local ju = JtacUnit(k)
    local laser = J(k).mark.kind == "laser" and ju
    local ltl = laser and BrgT(ju:getPoint(), aimPos) or nil
    local fu = FriendlyUnit(k)
    local bf = fu and BrgT(aimPos, fu:getPoint()) or nil
    local iph = ipPos and BrgT(ipPos, aimPos) or nil
    local threats = Threats()
    local best, bs
    local riskBest, riskC, riskWho      -- least-risk fallback among laser / friendly-valid windows
    for c = 0, 355, 5 do
        local ok = true
        for h = c - CFG.FAH_HALF, c + CFG.FAH_HALF, 5 do
            if ltl then
                local d = AngD(h, ltl)
                if d < CFG.LASER_SAFE or d > CFG.LASER_MAX then ok = false end
            end
            if bf and math.min(AngD(h, bf), AngD(h, bf + 180)) < CFG.FRIEND_SEP then ok = false end
        end
        if ok then
            local risk, who = WindowRisk(threats, aimPos, c)
            if not riskBest or risk < riskBest then riskBest, riskC, riskWho = risk, c, who end
            if risk <= 0 then
                local s = iph and AngD(c, iph) or (ltl and AngD(c, ltl + 35) or 0)
                if not bs or s < bs then best, bs = c, s end
            end
        end
    end
    if not best and riskC then
        best = riskC
        Log(string.format("WARN FAH %s: every valid window's run-in is inside a threat ring; least risk %03d true, "
            .. "%.1f NM inside %s (%s)", k, best, riskBest, riskWho and riskWho.label or "?", riskWho and riskWho.name or "?"))
    end
    if not best then
        best = ltl and ((ltl + 35) % 360) or (iph or 0)
        Log(string.format("FAH %s: no window satisfies laser/friendly limits, fallback %d", k, best))
    end
    return best, (best - CFG.FAH_HALF) % 360, (best + CFG.FAH_HALF) % 360, ltl, threats
end

local function ThreatText(tp, exclude)
    local out = {}
    for _, gr in ipairs(coalition.getGroups(coalition.side.RED, Group.Category.GROUND) or {}) do
        local gn = gr:getName()
        if not exclude[gn] then
            for _, u in ipairs(gr:getUnits() or {}) do
                if Alive(u) then
                    local ok, ad = pcall(u.hasAttribute, u, "Air Defence")
                    local p = u:getPoint()
                    if ok and ad and NM(D2(p, tp)) <= CFG.THREAT_NM then
                        local lab = Label(u:getTypeName())
                        local key = lab .. Dir8(BrgT(tp, p))
                        if not out[key] then
                            out[key] = string.format("%s %s %.0f", lab, Dir8(BrgT(tp, p)), math.max(1, NM(D2(p, tp))))
                            out[#out + 1] = out[key]
                        end
                        break
                    end
                end
            end
        end
        if #out >= 3 then break end
    end
    return out
end

local function WindText(p)
    local ok, w = pcall(atmosphere.getWind, Eye(p, 10))
    if not ok or not w then return "unknown" end
    local spd = math.sqrt(w.x * w.x + w.z * w.z) * 1.94384
    if spd < 3 then return "calm" end
    local from = (math.deg(math.atan2(w.z, w.x)) + 180) % 360   -- vector = blowing TO
    return string.format("%s at %d", H3(Mag(from)), math.floor(spd + 0.5))
end

local function IsDay()
    local t = timer.getAbsTime() % 86400
    return t >= CFG.DAY.from and t < CFG.DAY.to
end

local function JtacSees(k, pos)
    local ju = JtacUnit(k)
    if not ju then return false end
    return land.isVisible(Eye(ju:getPoint()), pos)
end

local function HeroHdgT(u)
    local p = u:getPosition()
    return math.deg(math.atan2(p.x.z, p.x.x)) % 360
end

-- ══════════════════════════════════════════════════════════════
--  ABORT CODE
-- ══════════════════════════════════════════════════════════════
local function AbortReply()
    local c = CFG.ABORT.challenge
    local row = CFG.AUTH[c:sub(1, 1)]
    local i = row and row:find(c:sub(2, 2), 1, true)
    if not i then return nil end
    return row:sub(i % #row + 1, i % #row + 1)
end
local function ChallengeTxt()
    local t = {}
    for ch in CFG.ABORT.challenge:gmatch("%a") do t[#t + 1] = PHON[ch:upper()] end
    return table.concat(t, " ")
end

-- ══════════════════════════════════════════════════════════════
--  FRIENDLY GROUP (troops in contact)
-- ══════════════════════════════════════════════════════════════
local function SpawnFriendly(k)
    if Group.getByName(CFG.FRIENDLY.name) then return end
    local tp, ju = Centroid(TargetUnits(k)), JtacUnit(k)
    if not (tp and ju) then Log("friendly spawn skipped: no target / JTAC for " .. k); return end
    local o = J(k).friendly_ofs
    local r = math.rad(o.brg)
    local cx, cz = tp.x + math.cos(r) * o.m, tp.z + math.sin(r) * o.m
    local units = {}
    for i, typ in ipairs(CFG.FRIENDLY.units) do
        units[#units + 1] = { type = typ, name = CFG.FRIENDLY.name .. "-" .. i, skill = "Average",
            x = cx + (i - 1) * 12 * math.cos(r + math.pi / 2), y = cz + (i - 1) * 12 * math.sin(r + math.pi / 2),
            heading = math.rad((o.brg + 180) % 360), playerCanDrive = false }
    end
    local ok, err = pcall(coalition.addGroup, ju:getCountry(), Group.Category.GROUND,
        { name = CFG.FRIENDLY.name, task = "Ground Nothing", visible = false, units = units,
          route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0 } } } })
    if not ok then Log("friendly spawn failed: " .. tostring(err)); return end
    timer.scheduleFunction(function()
        local g = Group.getByName(CFG.FRIENDLY.name)
        if not g then return end
        local c = g:getController()
        pcall(c.setCommand, c, { id = "SetInvisible", params = { value = true } })
        pcall(c.setCommand, c, { id = "SetImmortal", params = { value = true } })
        pcall(c.setOption, c, AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
    end, nil, timer.getTime() + 1)
    Log(string.format("friendly %s spawned for %s: %s %d m from target (%s)", CFG.FRIENDLY.name, k,
        Dir8(o.brg), o.m, MGRS({ x = cx, y = 0, z = cz })))
end

-- ══════════════════════════════════════════════════════════════
--  BRIEFING CONTENT
-- ══════════════════════════════════════════════════════════════
local function Ordnance(u)
    local cnt, order, gun = {}, {}, false
    for _, a in ipairs(u:getAmmo() or {}) do
        local d = a.desc or {}
        if d.category == Weapon.Category.SHELL then
            gun = true
        elseif d.category == Weapon.Category.BOMB or d.category == Weapon.Category.ROCKET
            or (d.category == Weapon.Category.MISSILE and d.missileCategory ~= Weapon.MissileCategory.AAM) then
            local n = d.displayName or d.typeName or "unknown"
            if not cnt[n] then cnt[n] = 0; order[#order + 1] = n end
            cnt[n] = cnt[n] + (a.count or 0)
        end
    end
    local parts = {}
    for _, n in ipairs(order) do parts[#parts + 1] = Word(cnt[n]) .. " " .. n end
    if gun then parts[#parts + 1] = "gun" end
    return (#parts > 0) and table.concat(parts, ", ") or "no air-to-ground ordnance"
end

local function Position(u)
    local p, cp = u:getPoint(), CFG.CP.pos
    local d = NM(D2(cp, p))
    local where = (d < 3) and ("overhead " .. CFG.CP.name)
        or string.format("%s %s for %d", CFG.CP.name, H3(Mag(BrgT(cp, p))), math.floor(d + 0.5))
    return string.format("%s, angels %d", where, math.floor(p.y * 3.28084 / 1000 + 0.5))
end

local function Playtime(u)
    local lb = (u:getFuel() or 0) * CFG.INTERNAL_FUEL_LB
    return math.max(0, math.floor((lb - CFG.BINGO_LB) / CFG.BURN_LB_MIN / 5) * 5)
end

--- Builds the 9-line + restrictions for the current aim unit into st.nine.
local function BuildNine(k)
    local st, j = JC.st[k], J(k)
    local au = JC.aimUnit(k)
    if not au then return nil end
    local ap = au:getPoint()
    local ipPos = st.ipPos
    local n = { aim = au:getName(), aimPos = ap }
    n.ip = j.ip.name
    n.hdg = ipPos and H3(Mag(BrgT(ipPos, ap))) or "N/A"
    n.dist = ipPos and string.format("%.1f", NM(D2(ipPos, ap))) or "N/A"
    n.elev = math.floor(GroundY(ap) * 3.28084 + 0.5)
    n.desc = Describe(TargetUnits(k))
    n.grid = MGRS(ap, (j.method == "BOC") and 5 or 4)
    n.mark = (j.mark.kind == "laser") and ("laser " .. j.mark.code) or j.mark.kind
    local fu, fcs = FriendlyUnit(k)
    if fu then
        local fp = fu:getPoint()
        local m = math.max(100, math.floor(D2(ap, fp) / 100 + 0.5) * 100)
        n.fr = string.format("%s %d%s", Dir8(BrgT(ap, fp)), m, st.tic and ", troops in contact" or "")
        n.frCs = fcs
    else
        n.fr = "none"
    end
    n.egress = j.egress
    local c, lo, hi, ltl, threats = ComputeFAH(k, ap, ipPos)
    n.fahC, n.fahLo, n.fahHi = Mag(c), R5(Mag(lo)), R5(Mag(hi))
    n.threats = LongThreatText(threats or {}, ap)
    -- v0.3.0 / v0.4.0: keyhole IP when the pre-briefed IP does not fit the FAH or its run-in is threatened
    local ipRisk = ipPos and PathRisk(threats or {}, ap, BrgT(ipPos, ap), NM(D2(ipPos, ap))) or 1
    if not ipPos or AngD(BrgT(ipPos, ap), c) > CFG.IP_MAX_OFF or ipRisk > 0 then
        local kb = R5(Mag((c + 180) % 360))
        local knm = CFG.KEYHOLE_NM
        for _, d in ipairs({ CFG.KEYHOLE_NM, 8, 12, 6 }) do
            if PathRisk(threats or {}, ap, c, d) <= 0 then knm = d; break end
        end
        n.ip = string.format("keyhole %s/%d", H3(kb), knm)
        n.hdg = H3(R5(Mag(c)))
        n.dist = string.format("%.1f", knm)
        n.keyhole = true
        Log(string.format("IP %s: %s run-in %s is %.0f deg off the FAH centre, threat %.1f NM -> %s", k, j.ip.name,
            ipPos and H3(Mag(BrgT(ipPos, ap))) or "?", ipPos and AngD(BrgT(ipPos, ap), c) or 0, ipRisk, n.ip))
    end
    n.fah = string.format("%s-%s", H3(n.fahLo), H3(n.fahHi))
    n.ltl = ltl and H3(Mag(ltl)) or nil
    st.nine = n
    Log(string.format("9-LINE %s: %s/%s/%s/%d/%s/%s/%s/%s/egress %s | FAH %s LTL %s aim %s [%s]", k, n.ip,
        n.hdg, n.dist, n.elev, n.desc, n.grid, n.mark, n.fr, n.egress, n.fah, tostring(n.ltl), n.aim,
        au:getTypeName()))
    return n
end

local function ChooseType(k)
    local j = J(k)
    if j.control ~= "auto" then return tonumber(j.control) or 2 end
    local u, ju = Hero(), JtacUnit(k)
    if not (u and ju and IsDay()) then return 2 end
    local p = u:getPoint()
    local agl = (p.y - GroundY(p)) * 3.28084
    local slant = NM(math.sqrt(D2(p, ju:getPoint()) ^ 2 + (p.y - ju:getPoint().y) ^ 2))
    if slant <= CFG.TYPE1.max_nm and agl <= CFG.TYPE1.max_agl_ft and JtacSees(k, p) then return 1 end
    return 2
end

-- ══════════════════════════════════════════════════════════════
--  READBACK QUIZ
-- ══════════════════════════════════════════════════════════════
local function Shuffle(t)
    for i = #t, 2, -1 do local r = math.random(1, i); t[i], t[r] = t[r], t[i] end
    return t
end

local function Uniq(correct, cands, n)
    local seen, out = { [correct] = true }, { correct }
    for _, c in ipairs(Shuffle(cands)) do
        if #out >= n then break end
        if c and not seen[c] then seen[c] = true; out[#out + 1] = c end
    end
    return Shuffle(out)
end

local function SwapAdj(s, i) return s:sub(1, i - 1) .. s:sub(i + 1, i + 1) .. s:sub(i, i) .. s:sub(i + 2) end
local function Bump(s, i, d)
    local v = (tonumber(s:sub(i, i)) + d) % 10
    return s:sub(1, i - 1) .. v .. s:sub(i + 1)
end

local function ElevOptions(e)
    local s = tostring(e)
    local c = { tostring(math.floor(e / 3.28084 + 0.5)), tostring(e + 100), tostring(math.max(0, e - 100)),
                tostring(e + 10), tostring(math.max(0, e - 10)) }
    for i = 1, #s - 1 do
        if s:sub(i, i) ~= s:sub(i + 1, i + 1) then c[#c + 1] = tostring(tonumber(SwapAdj(s, i))) end
    end
    return Uniq(s, c, 4)
end

local function NextLetter(ch, d)
    local abc = "ABCDEFGHJKLMNPQRSTUVWXYZ"   -- MGRS letters (no I / O)
    local i = abc:find(ch, 1, true) or 1
    return abc:sub((i - 1 + d) % #abc + 1, (i - 1 + d) % #abc + 1)
end

local function GridOptions(g)
    local z, d, e, n = g:match("^(%S+) (%a%a) (%d+) (%d+)$")
    if not z then return { g } end
    local c = {}
    local function mk(dd, ee, nn) return string.format("%s %s %s %s", z, dd, ee, nn) end
    for _ = 1, 2 do
        local i = math.random(1, #e); c[#c + 1] = mk(d, Bump(e, i, (math.random(0, 1) == 0) and 1 or -1), n)
        i = math.random(1, #n); c[#c + 1] = mk(d, e, Bump(n, i, (math.random(0, 1) == 0) and 1 or -1))
    end
    local i = math.random(1, #e - 1)
    if e:sub(i, i) ~= e:sub(i + 1, i + 1) then c[#c + 1] = mk(d, SwapAdj(e, i), n) end
    i = math.random(1, #n - 1)
    if n:sub(i, i) ~= n:sub(i + 1, i + 1) then c[#c + 1] = mk(d, e, SwapAdj(n, i)) end
    c[#c + 1] = mk(d, n, e)
    c[#c + 1] = mk(d:sub(1, 1) .. NextLetter(d:sub(2, 2), 1), e, n)
    return Uniq(g, c, 4)
end

local function FahOptions(n)
    local function w(lo, hi) return string.format("%s-%s", H3(lo % 360), H3(hi % 360)) end
    local lo, hi = n.fahLo, n.fahHi
    local c = { w(lo + 180, hi + 180), w(lo + 30, hi + 30), w(lo - 30, hi - 30), w(lo + 90, hi + 90) }
    return Uniq(n.fah, c, 4)
end

local function NewQuiz(k)
    local st = JC.st[k]
    local n = st.nine
    st.quiz = { step = 1, ans = {},
        items = {
            { key = "elev", label = "Line 4 elevation (ft MSL)", correct = tostring(n.elev), opts = ElevOptions(n.elev) },
            { key = "grid", label = "Line 6 grid", correct = n.grid, opts = GridOptions(n.grid) },
            { key = "fah",  label = "restriction: final attack heading", correct = n.fah, opts = FahOptions(n) },
        } }
end

-- ══════════════════════════════════════════════════════════════
--  LASER
-- ══════════════════════════════════════════════════════════════
local function LaserOff(k, why)
    local st = JC.st[k]
    if st.spot then pcall(st.spot.destroy, st.spot) end
    if st.spot then Log(string.format("LASER OFF %s (%s) after %.0f s", k, why, timer.getTime() - (st.laserT0 or 0))) end
    st.spot, st.laserT0, st.laserUnit = nil, nil, nil
end

local function LaserOn(k)
    local st, ju = JC.st[k], JtacUnit(k)
    local au = JC.aimUnit(k)
    if not (ju and au) then return false, "no JTAC / target" end
    local tp = au:getPoint()
    tp = { x = tp.x, y = tp.y + 1, z = tp.z }
    if not land.isVisible(Eye(ju:getPoint(), CFG.LASER_SRC.y), tp) then return false, "no line of sight" end
    LaserOff(k, "re-aim")
    local ok, spot = pcall(Spot.createLaser, ju, CFG.LASER_SRC, tp, J(k).mark.code)
    if not ok or not spot then return false, tostring(spot) end
    st.spot, st.laserT0, st.laserUnit = spot, timer.getTime(), au:getName()
    Log(string.format("LASER ON %s -> %s [%s] code %d", k, au:getName(), au:getTypeName(), J(k).mark.code))
    return true
end

local function LaserTick(k, now)
    local st = JC.st[k]
    if not st.spot then return end
    local u = Unit.getByName(st.laserUnit or "")
    if Alive(u) then
        local p = u:getPoint()
        pcall(st.spot.setPoint, st.spot, { x = p.x, y = p.y + 1, z = p.z })
    end
    if now - st.laserT0 > CFG.LASER_TIMEOUT_S then
        LaserOff(k, "timeout")
        Emit("LASER_TIMEOUT", { key = k })
        Jtac(k, string.format("%s, %s, laser off, %d seconds without cease laser.", CFG.CS, J(k).disp,
            CFG.LASER_TIMEOUT_S))
        MenuRefresh()
    end
end

-- ══════════════════════════════════════════════════════════════
--  FLOW ACTIONS
-- ══════════════════════════════════════════════════════════════
local function SetPhase(k, ph)
    local st = JC.st[k]
    if st.phase ~= ph then Log(string.format("%s %s -> %s", k, st.phase, ph)) end
    st.phase = ph
    MenuRefresh()
end

local function Busy(k, v) JC.st[k].busy = v end   -- v0.3.1: no menu rebuild (items stay)
local function Free(k) return function() Busy(k, false) end end

local function A_CheckIn(k)
    local st, j, u = JC.st[k], J(k), Hero()
    if not u then return end
    Busy(k, true)
    Pilot(string.format("%s, %s, mission %s, %s, %s, %s, playtime %d, %s, abort code %s.", j.disp, CFG.CS,
        j.msn, CFG.NUM_TYPE, Position(u), Ordnance(u), Playtime(u), CFG.CAPS, ChallengeTxt()))
    local tp = Centroid(TargetUnits(k)) or (JtacUnit(k) and JtacUnit(k):getPoint())
    local excl = {}
    for _, gn in ipairs(j.targets) do excl[gn] = true end
    local thr = tp and ThreatText(tp, excl) or {}
    if tp then for _, t in ipairs(LongThreatText(Threats(), tp)) do thr[#thr + 1] = t end end   -- v0.4.0
    local tgt = Describe(TargetUnits(k))
    local fu, fcs = FriendlyUnit(k)
    local frTxt = "unknown"
    if fu and tp then
        frTxt = string.format("%s, all friendlies %s of the target", (fcs == CFG.FRIENDLY.cs)
            and "Bravo 2-1, mech platoon, in contact" or "my team only", Dir8(BrgT(tp, fu:getPoint())))
    end
    Jtac(k, string.format("%s, %s, copy all, abort code noted. Situation update: threat, the target itself%s. "
        .. "Enemy, %s. Friendlies, %s. No artillery. Hazards, winds on the deck %s. Remarks, I have a laser, "
        .. "no IR pointer. Request IN with heading. Advise when ready for game plan.",
        CFG.CS, j.disp, (#thr > 0) and (", plus " .. table.concat(thr, ", ")) or "", tgt, frTxt,
        tp and WindText(tp) or "unknown"), CFG.DUR.long, Free(k), 8)
    st.checkinT = timer.getTime()
    SetPhase(k, "SITREP")
end

local function A_ReadyGamePlan(k)
    local st, j = JC.st[k], J(k)
    Busy(k, true)
    Pilot(string.format("%s, %s, ready to copy.", j.disp, CFG.CS))
    st.type = ChooseType(k)
    Jtac(k, string.format("%s, Type %d control, %s, %s. Advise when ready for 9-line.", CFG.CS, st.type,
        (j.method == "BOC") and "bomb on coordinate" or "bomb on target", j.ord), CFG.DUR.short, Free(k))
    Log(string.format("GAME PLAN %s: Type %d %s %s", k, st.type, j.method, j.ord))
    SetPhase(k, "GAMEPLAN")
end

local function A_ReadyNine(k)
    local st, j = JC.st[k], J(k)
    local n = BuildNine(k)
    if not n then Msg("[JC] " .. j.disp .. ": no live target.", 8); return end
    Busy(k, true)
    Pilot(string.format("%s, %s, ready to copy.", j.disp, CFG.CS))
    Jtac(k, string.format("%s\n  %s\n  %s\n  %s\n  %d\n  %s\n  %s\n  %s\n  %s\n  egress %s\n"
        .. "Advise when ready for remarks.", CFG.CS .. ",", n.ip, n.hdg, n.dist, n.elev, n.desc, n.grid,
        n.mark, n.fr, n.egress), CFG.DUR.nine, Free(k), 8)
    SetPhase(k, "NINE")
end

local function A_ReadyRemarks(k)
    local st, j = JC.st[k], J(k)
    local n = st.nine
    Busy(k, true)
    Pilot("Ready to copy remarks.")
    local rem = {}
    if n.ltl then rem[#rem + 1] = string.format("laser-to-target line %s", n.ltl) end
    if n.threats and #n.threats > 0 then rem[#rem + 1] = "threat " .. table.concat(n.threats, ", ") end   -- v0.4.0
    rem[#rem + 1] = "request " .. j.ord
    rem[#rem + 1] = "hard deck two-zero thousand in effect"
    Jtac(k, string.format("%s, remarks: %s. Restrictions: final attack heading %s to %s. Report IP inbound.",
        CFG.CS, table.concat(rem, ", "), H3(n.fahLo), H3(n.fahHi)), CFG.DUR.long, function()
            st.rbT0, st.rbPrompted = timer.getTime(), 0
            Busy(k, false)
        end, 6)
    NewQuiz(k)
    st.rbTries = 0
    SetPhase(k, "READBACK")
end

local function A_Quiz(k, choice)
    local st, j = JC.st[k], J(k)
    local q = st.quiz
    local it = q.items[q.step]
    q.ans[it.key] = choice
    if q.step < #q.items then q.step = q.step + 1; MenuRefresh(); return end
    -- all three chosen -> transmit
    st.rbTries = (st.rbTries or 0) + 1
    local a = q.ans
    local dt = timer.getTime() - (st.rbT0 or timer.getTime())
    Busy(k, true)
    Pilot(string.format("%s, %s, %s, final attack heading %s to %s.", j.disp, a.elev, a.grid,
        a.fah:sub(1, 3), a.fah:sub(5, 7)))
    local wrong = {}
    for _, i in ipairs(q.items) do if q.ans[i.key] ~= i.correct then wrong[#wrong + 1] = i end end
    local data = { key = k, try = st.rbTries, seconds = dt, wrong = #wrong }
    if #wrong == 0 then
        st.rbOk = true
        Log(string.format("READBACK %s correct (try %d, %.0f s)", k, st.rbTries, dt))
        Emit("READBACK", data)
        local laser = (j.mark.kind == "laser")
        Jtac(k, string.format("%s, readback correct.%s Report IP inbound.", CFG.CS,
            laser and string.format(" Laser-to-target line %s, call for laser.", st.nine.ltl or "")
            or ""), CFG.DUR.short, Free(k))
        st.att = { ipIn = false, inCalled = false, cleared = false, aborted = false, corr = nil }
        SetPhase(k, "ATTACK")
    else
        local fix = {}
        for _, i in ipairs(wrong) do
            if i.key == "elev" then fix[#fix + 1] = "elevation " .. i.correct
            elseif i.key == "grid" then fix[#fix + 1] = "grid " .. i.correct
            else fix[#fix + 1] = "final attack heading " .. i.correct:sub(1, 3) .. " to " .. i.correct:sub(5, 7) end
        end
        Log(string.format("READBACK %s WRONG (try %d, %.0f s): %d item(s)", k, st.rbTries, dt, #wrong))
        Emit("READBACK", data)
        Jtac(k, string.format("%s, negative. %s. Read back.", CFG.CS, table.concat(fix, ", ")), CFG.DUR.short,
            function() st.rbT0, st.rbPrompted = timer.getTime(), 0; Busy(k, false) end)
        NewQuiz(k)
    end
end

-- attack -----------------------------------------------------------------
local function AimPos(k)
    local au = JC.aimUnit(k)
    return au and au:getPoint() or (JC.st[k].nine and JC.st[k].nine.aimPos)
end

local function HdgInFah(k, u)
    local n = JC.st[k].nine
    local h = Mag(HeroHdgT(u))
    local lo, hi = n.fahLo, n.fahHi
    local inside = AngD(h, (lo + AngD(lo, hi) / 2) % 360) <= AngD(lo, hi) / 2 + 0.5
    return inside, h
end

local function Abort(k, reason)
    local st = JC.st[k]
    local r = AbortReply()
    local w = r and ("ABORT " .. PHON[r]:upper()) or "ABORT"
    st.att.cleared, st.att.inCalled, st.att.aborted, st.att.abortT = false, false, true, timer.getTime()
    Say(string.format("[%s] %s, %s, %s, %s.%s", J(k).cs, CFG.CS, w, w, w, reason and (" " .. reason) or ""),
        CFG.DUR.short, 0, nil, 4)
    Log(string.format("ABORT %s (%s)", k, tostring(reason)))
    Emit("ABORT", { key = k, reason = reason })
    MenuRefresh()
end

local function TryClear(k)
    local st, j, u = JC.st[k], J(k), Hero()
    local a = st.att
    if not (u and a.inCalled) or a.cleared then return end
    local inside, h = HdgInFah(k, u)
    if not inside then
        Abort(k, string.format("Outside final attack heading, heading %s.", H3(h)))
        return
    end
    if st.type == 1 and not (IsDay() and JtacSees(k, u:getPoint())) then
        JtacF(k, string.format("%s, blind. Continue.", CFG.CS))
        Log("CONTINUE " .. k .. " (Type 1, JTAC blind)")
        return
    end
    if j.method == "BOT" and not (a.corr == "TALLY" or a.corr == "CAPTURED") then
        JtacF(k, string.format("%s, continue. Say when tally or captured.", CFG.CS))
        Log("CONTINUE " .. k .. " (BOT, no correlation)")
        return
    end
    a.cleared, a.clearT = true, timer.getTime()
    JtacF(k, string.format("%s, CLEARED HOT.", CFG.CS))
    Log(string.format("CLEARED HOT %s (Type %d, heading %s)", k, st.type, H3(h)))
    Emit("CLEARED", { key = k })
    if (j.abort_inject or 0) > 0 and not st.injDone and math.random(1, 100) <= j.abort_inject then
        st.injDone = true
        local t0 = a.clearT
        timer.scheduleFunction(function()
            if st.att.cleared and st.att.clearT == t0 and not st.att.released then
                Abort(k, "Civilian vehicle entering the target area.")
                timer.scheduleFunction(function()
                    if st.phase == "ATTACK" then
                        Jtac(k, string.format("%s, %s, target area clear. Report IN.", CFG.CS, J(k).disp))
                    end
                end, nil, timer.getTime() + 40)
            end
        end, nil, timer.getTime() + math.random(3, 6))
    end
    MenuRefresh()
end

local function A_IpInbound(k)
    local st = JC.st[k]
    st.att.ipIn = true
    PilotF(string.format("%s, IP inbound.", CFG.CS))
    JtacF(k, string.format("%s, continue.", CFG.CS))
    MenuRefresh()
end

local function A_In(k)
    local st, u = JC.st[k], Hero()
    if not u then return end
    local tp = AimPos(k)
    local dir = tp and Dir8(BrgT(tp, u:getPoint())) or "unknown"
    st.att.inCalled, st.att.aborted, st.att.released = true, false, false
    st.att.inT = timer.getTime()
    PilotF(string.format("%s, IN from the %s.", CFG.CS, dir), function()
        timer.scheduleFunction(function() TryClear(k) end, nil, timer.getTime() + 1.5)
    end)
    Log(string.format("IN %s from the %s, heading %s", k, dir, H3(Mag(HeroHdgT(u)))))
    MenuRefresh()
end

local function A_Off(k)
    local st, u = JC.st[k], Hero()
    local dir = u and Dir8(HeroHdgT(u)) or "north"
    PilotF(string.format("%s, off %s%s.", CFG.CS, dir, st.att.released and "" or ", dry"))
    if st.att.cleared and not st.att.released then Log("CLEARANCE closed " .. k .. " (dry pass)") end
    st.att.inCalled, st.att.cleared, st.att.released, st.att.aborted = false, false, false, false
    st.att.offPending = false
    MenuRefresh()
end

local function A_Corr(k, what)
    local st, j = JC.st[k], J(k)
    st.att.corr = what
    if what == "NO JOY" then
        Pilot(string.format("%s, no joy.", CFG.CS))
        local tp, fu, fcs = AimPos(k), FriendlyUnit(k)
        local au = JC.aimUnit(k)
        local txt = string.format("%s, target is the %s.", CFG.CS, au and Label(au:getTypeName()) or "target")
        if tp and fu then
            local fp = fu:getPoint()
            txt = txt .. string.format(" From %s, %s %d meters.", (fcs == CFG.FRIENDLY.cs) and "Bravo 2-1" or "my position",
                Dir8(BrgT(fp, tp)), math.floor(D2(fp, tp) / 100 + 0.5) * 100)
        end
        if j.mark.kind == "laser" then txt = txt .. " Call for laser." end
        Jtac(k, txt, CFG.DUR.short)
    else
        PilotF(string.format("%s, %s.", CFG.CS, what:lower()))
        if st.att.inCalled and not st.att.cleared then
            timer.scheduleFunction(function() TryClear(k) end, nil, timer.getTime() + 1.5)
        end
    end
    Log(string.format("CORRELATION %s %s", k, what))
    MenuRefresh()
end

local function A_Laser(k, call)
    local st, j = JC.st[k], J(k)
    if call == "TEN" then
        st.att.tenT = timer.getTime()
        PilotF(string.format("%s, ten seconds.", CFG.CS))
    elseif call == "ON" or call == "SHIFT" then
        PilotF((call == "ON") and string.format("%s, laser on.", j.disp) or string.format("%s, shift.", j.disp))
        local ok, why = LaserOn(k)
        st.att.tenT = nil
        if ok then
            st.att.laserCalled = true
            JtacF(k, string.format("%s, lasing %d.", j.disp, j.mark.code))
        else
            Jtac(k, string.format("%s, unable laser, %s.", CFG.CS, why), CFG.DUR.short)
            Log("LASER FAIL " .. k .. ": " .. tostring(why))
        end
    elseif call == "SPOT" then
        PilotF(string.format("%s, spot.", CFG.CS))
        st.att.spotSaid = true
    elseif call == "NEG" then
        PilotF(string.format("%s, negative laser.", CFG.CS))
        Jtac(k, string.format("%s, laser on, code %d, laser-to-target line %s.", CFG.CS, j.mark.code,
            st.nine and st.nine.ltl or "unknown"), CFG.DUR.short)
    elseif call == "CEASE" then
        PilotF(string.format("%s, cease laser.", j.disp))
        LaserOff(k, "cease laser")
        st.att.tenT = nil
        JtacF(k, string.format("%s, laser off.", j.disp))
        st.att.spotSaid = false
    end
    Log(string.format("LASER CALL %s %s", k, call))
    MenuRefresh()
end

-- release / impact ----------------------------------------------------------
local function ActiveKey(u)
    local best, bd
    for _, k in ipairs(CFG.ORDER) do
        local ph = JC.st[k].phase
        if ph ~= "IDLE" and ph ~= "DONE" then   -- TERMINATED stays: releases are still logged
            local tp = Centroid(TargetUnits(k))
            local d = tp and NM(D2(u:getPoint(), tp)) or 999
            if d <= CFG.REATTACK_NM and (not bd or d < bd) then best, bd = k, d end
        end
    end
    return best
end

local function Assess(k)
    local st, j = JC.st[k], J(k)
    local pass = st.pass
    st.pass = nil
    if not pass then return end
    local alive = TargetUnits(k)
    if st.phase == "TERMINATED" then
        LaserOff(k, "control terminated")
        if #alive == 0 then Emit("DONE", { key = k }) end
        return
    end
    if st.phase ~= "ATTACK" and #alive > 0 then
        Log(string.format("ASSESS %s skipped (phase %s, release not part of an attack)", k, st.phase))
        return
    end
    local aimDead = not Alive(Unit.getByName(pass.aim or ""))
    local last = pass.impacts[#pass.impacts]
    local lasing = st.spot ~= nil
    if #alive == 0 then
        -- SALT-R BDA, reported only for units the JTAC can see ("if you do not see it, do not report it")
        local seen, unseen = {}, 0
        local ju = JtacUnit(k)
        for _, s in ipairs(st.units or {}) do
            if ju and land.isVisible(Eye(ju:getPoint()), Eye(s.pos, 2)) then seen[#seen + 1] = s.label
            else unseen = unseen + 1 end
        end
        LaserOff(k, "target destroyed")
        local sz = (#seen > 0) and (Word(#seen) .. " destroyed, " .. DescribeLabels(seen)) or "unknown"
        Jtac(k, string.format("%s, %s, %sgood hits. BDA: size, %s%s. Activity, none observed. Location, %s. "
            .. "Time, %s local. Remarks, mission %s, successful. Cleared to depart, return to Overlord.", CFG.CS,
            j.disp, lasing and "splash, " or "", sz, (unseen > 0) and string.format(", %s not observed", Word(unseen)) or "",
            st.units and st.units[1] and MGRS(st.units[1].pos) or "unknown", Clock(), j.msn), CFG.DUR.long)
        Log(string.format("BDA %s: %d seen destroyed, %d not observed", k, #seen, unseen))
        Emit("DONE", { key = k })
        SetPhase(k, "DONE")
        return
    end
    local nau = JC.aimUnit(k)
    local corr = ""
    if last and nau then
        local np = nau:getPoint()
        corr = string.format(" From your hits, %s %d.", Dir8(BrgT(last, np)), math.floor(D2(last, np) / 10 + 0.5) * 10)
    end
    if aimDead then
        Jtac(k, string.format("%s, %s, %sgood hits. Next target, %s.%s%s Report IN.", CFG.CS, j.disp,
            lasing and "splash, " or "", Label(nau:getTypeName()), corr,
            lasing and " Call shift." or ""), CFG.DUR.short + 2)
    else
        local miss = last and D2(last, AimPos(k)) or 0
        Jtac(k, string.format("%s, %s, miss.%s Report IN.", CFG.CS, j.disp, corr), CFG.DUR.short)
        Log(string.format("MISS %s %.0f m", k, miss))
    end
    if st.nine then st.nine.aim = nau:getName() end
end

local function TrackWeapon(k, w, rec)
    local pass = JC.st[k].pass
    timer.scheduleFunction(function(_, t)
        local ok, ex = pcall(w.isExist, w)
        if ok and ex then
            local okp, p = pcall(w.getPoint, w)
            if okp and p then rec.last = p end
            return t + 0.1
        end
        if pass then
            pass.pending = pass.pending - 1
            if rec.last then pass.impacts[#pass.impacts + 1] = rec.last end
            Log(string.format("IMPACT %s %s at %s (pending %d)", k, rec.type, rec.last and MGRS(rec.last) or "?",
                pass.pending))
            Emit("IMPACT", { key = k, type = rec.type, pos = rec.last })
            if pass.pending <= 0 then
                timer.scheduleFunction(function() Assess(k) end, nil, timer.getTime() + CFG.IMPACT_WAIT_S)
            end
        end
        return nil
    end, nil, timer.getTime() + 0.1)
end

local function OnShot(w)
    local d = w:getDesc()
    if type(d) ~= "table" then return end
    local tn = tostring(d.typeName or "")
    local kind
    if d.category == Weapon.Category.BOMB then kind = "bomb"
    elseif d.category == Weapon.Category.MISSILE and d.missileCategory ~= Weapon.MissileCategory.AAM
        and d.missileCategory ~= Weapon.MissileCategory.SAM and not tn:find("AGM_88") then kind = "rifle"
    elseif d.category == Weapon.Category.ROCKET then kind = "rocket" end
    if not kind then return end
    local u = Hero(); if not u then return end
    local k = ActiveKey(u); if not k then return end
    local st, now = JC.st[k], timer.getTime()
    local a = st.att or {}
    local inside, h = false, Mag(HeroHdgT(u))
    if st.nine then inside, h = HdgInFah(k, u) end
    local rec = { type = d.displayName or tn, kind = kind, t = now, cleared = a.cleared == true,
        afterAbort = a.aborted == true and a.abortT and (now - a.abortT) < 60, fah = inside, hdg = h,
        readback = st.rbOk == true, laser = st.spot ~= nil, phase = st.phase }
    Log(string.format("RELEASE %s %s cleared=%s afterAbort=%s fah=%s(%s) readback=%s laser=%s phase=%s", k,
        rec.type, tostring(rec.cleared), tostring(rec.afterAbort), tostring(inside), H3(h), tostring(rec.readback),
        tostring(rec.laser), st.phase))
    Emit("RELEASE", rec)
    a.released, a.offPending = true, true
    if st.phase == "TERMINATED" then
        Log("RELEASE after TERMINATED " .. k)
    elseif rec.afterAbort or not rec.cleared then
        st.viol = (st.viol or 0) + 1
        Emit("VIOLATION", { key = k, n = st.viol, afterAbort = rec.afterAbort })
        if st.viol >= 2 then
            JtacF(k, string.format("%s, %s, second unauthorized release. Terminating control. "
                .. "Cleared off, return to Overlord.", CFG.CS, J(k).disp))
            Msg(string.format("[CAS-1] %s terminated control after two unauthorized releases (ROE). "
                .. "Check out with OVERLORD.", J(k).disp), 15)
            Log("TERMINATED " .. k .. " (2 unauthorized releases)")
            SetPhase(k, "TERMINATED")
            Emit("TERMINATED", { key = k })
        else
            JtacF(k, string.format("%s, %s, %s Hold fire.", CFG.CS, J(k).disp,
                rec.afterAbort and "weapon released after abort." or "you were not cleared."))
            Msg(string.format("[CAS-1] Unauthorized release logged (ROE). A second one ends %s's control.",
                J(k).disp), 12)
        end
    end
    if TRT.CD then TRT.CD.relCallUntil = now + 10 end   -- Pilot_Banter drops its own "weapon away"
    -- pass bookkeeping (ripple / pairs within 2 s = one call)
    local p = st.pass
    if p and now - p.t0 <= 2 then
        p.n, p.pending = p.n + 1, p.pending + 1
    else
        p = { t0 = now, n = 1, pending = 1, impacts = {}, aim = (st.nine and st.nine.aim), kind = kind }
        st.pass = p
        timer.scheduleFunction(function()
            local txt = (p.kind == "rifle") and ("rifle" .. ((p.n > 1) and (", " .. Word(p.n)) or ""))
                or (Word(p.n) .. " away")
            PilotF(string.format("%s, %s.", CFG.CS, txt))
        end, nil, now + 2)
    end
    TrackWeapon(k, w, rec)
    MenuRefresh()
end

-- ══════════════════════════════════════════════════════════════
--  F10 MENU
-- ══════════════════════════════════════════════════════════════
local function Offered(k, u)
    local st = JC.st[k]
    if st.phase == "IDLE" or st.phase == "DONE" or st.phase == "TERMINATED" then return false end
    local cd = TRT.CD
    if CFG.HANDOFF == "CD" and cd and cd.phase == J(k).cdPhase then return true end
    local tp = Centroid(TargetUnits(k))
    return tp and u and NM(D2(u:getPoint(), tp)) <= CFG.REATTACK_NM or false
end

local function Items(_)
    local out, u = {}, Hero()
    for _, k in ipairs(CFG.ORDER) do
        if Offered(k, u) then
            local st, j = JC.st[k], J(k)
            local P = j.disp:upper() .. ": "
            local ph = st.phase
            if ph == "CHECKIN" then
                out[#out + 1] = { P .. "check in (btn " .. j.btn .. ")", function() A_CheckIn(k) end }
            elseif ph == "SITREP" then
                out[#out + 1] = { P .. "ready for game plan", function() A_ReadyGamePlan(k) end }
            elseif ph == "GAMEPLAN" then
                out[#out + 1] = { P .. "ready for 9-line", function() A_ReadyNine(k) end }
            elseif ph == "NINE" then
                out[#out + 1] = { P .. "ready for remarks", function() A_ReadyRemarks(k) end }
            elseif ph == "READBACK" and st.quiz then
                local q = st.quiz
                local it = q.items[q.step]
                local sub = {}
                for _, o in ipairs(it.opts) do sub[#sub + 1] = { o, function() A_Quiz(k, o) end } end
                out[#out + 1] = { string.format("%sREADBACK %d/3: %s", P, q.step, it.label), sub = sub }
            elseif ph == "ATTACK" then
                local a = st.att
                if a.offPending or a.aborted or (a.inCalled and not a.released) then   -- v0.3.0: dry pass
                    out[#out + 1] = { P .. "OFF" .. (a.released and "" or " (dry)"), function() A_Off(k) end }
                elseif not a.ipIn then
                    out[#out + 1] = { P .. "IP INBOUND", function() A_IpInbound(k) end }
                elseif not a.inCalled then
                    out[#out + 1] = { P .. "IN (direction auto)", function() A_In(k) end }
                end
                if j.mark.kind == "laser" then
                    if not st.spot then
                        if not a.tenT then   -- v0.3.1: LASER ON stays until pressed
                            out[#out + 1] = { P .. "TEN SECONDS", function() A_Laser(k, "TEN") end }
                        else
                            out[#out + 1] = { P .. "LASER ON", function() A_Laser(k, "ON") end }
                        end
                    else
                        local au = JC.aimUnit(k)
                        if au and au:getName() ~= st.laserUnit then
                            out[#out + 1] = { P .. "SHIFT (laser to next target)", function() A_Laser(k, "SHIFT") end }
                        elseif not a.spotSaid then
                            out[#out + 1] = { P .. "SPOT", function() A_Laser(k, "SPOT") end }
                            out[#out + 1] = { P .. "NEGATIVE LASER", function() A_Laser(k, "NEG") end }
                        end
                        out[#out + 1] = { P .. "CEASE LASER", function() A_Laser(k, "CEASE") end }
                    end
                end
                out[#out + 1] = { P .. "correlation", sub = {
                    { "TALLY", function() A_Corr(k, "TALLY") end },
                    { "CAPTURED", function() A_Corr(k, "CAPTURED") end },
                    { "NO JOY", function() A_Corr(k, "NO JOY") end } } }
            end
        end
    end
    return out
end

local NEXT_TXT = {
    CHECKIN  = "Check in with %s (F10 > COMMS): mission, position, ordnance, playtime, abort code.",
    SITREP   = "%s: F10 'ready for game plan'.",
    GAMEPLAN = "%s: F10 'ready for 9-line'. Copy Line 4 / Line 6 into the HSI.",
    NINE     = "%s: F10 'ready for remarks'. Restrictions are mandatory readback.",
    READBACK = "%s: read back Line 4, Line 6 and restrictions FROM YOUR SYSTEM (F10 > COMMS > READBACK).",
    ATTACK   = "%s: IP INBOUND -> IN -> CLEARED HOT. Laser: TEN SECONDS -> LASER ON -> SPOT -> CEASE LASER. OFF after release.",
}
local function NextText()
    local u = Hero()
    for _, k in ipairs(CFG.ORDER) do
        local st = JC.st[k]
        if NEXT_TXT[st.phase] and Offered(k, u) then return string.format(NEXT_TXT[st.phase], J(k).disp) end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════
--  OBSERVATION POST (v0.2.0)
-- ══════════════════════════════════════════════════════════════
local function SetupGround(gname, skill)
    timer.scheduleFunction(function()
        local g = Group.getByName(gname)
        if not g then return end
        local c = g:getController()
        pcall(c.setCommand, c, { id = "SetInvisible", params = { value = true } })
        pcall(c.setCommand, c, { id = "SetImmortal", params = { value = true } })
        pcall(c.setOption, c, AI.Option.Ground.id.ROE, AI.Option.Ground.val.ROE.WEAPON_HOLD)
    end, nil, timer.getTime() + 1)
end

local function Relocate(k)
    local j = J(k)
    local op = j.op
    if not op then return end
    local ju, tus = JtacUnit(k), TargetUnits(k)
    if not ju or #tus == 0 then Log("RELOCATE " .. k .. ": no JTAC / target, ME position kept"); return end
    local tp = Centroid(tus)
    local tgtH = GroundY(tp)
    local best, bs, bd = nil, nil, nil
    local n, nSurf, nNear, nLos = 0, 0, 0, 0
    local step, sec = op.step or 150, op.sector or 60
    for d = op.dmin or 1500, op.dmax or 4000, step do
        local da = math.max(2, math.deg(step / d))
        for a = -sec, sec, da do
            n = n + 1
            local r = math.rad(op.brg + a)
            local p = { x = tp.x + math.cos(r) * d, y = 0, z = tp.z + math.sin(r) * d }
            local okS, sf = pcall(land.getSurfaceType, { x = p.x, y = p.z })
            if not (okS and (sf == land.SurfaceType.LAND or sf == land.SurfaceType.ROAD)) then
                nSurf = nSurf + 1
            else
                local eye, ok, near = Eye(p), true, false
                for _, u in ipairs(tus) do
                    local up = u:getPoint()
                    if D2(p, up) < (op.dmin or 1500) then near = true; break end
                    if not land.isVisible(eye, Eye(up, 1.5)) then ok = false; break end
                end
                if near then nNear = nNear + 1
                elseif not ok then nLos = nLos + 1
                else
                    -- high ground first (1 point per 50 m above the target), then closeness to <brg, m>
                    local score = (GroundY(p) - tgtH) / 50 - math.abs(a) / 30 - math.abs(d - op.m) / 1000
                    if not bs or score > bs then best, bs, bd = p, score, D2(p, { x = tp.x + math.cos(math.rad(op.brg)) * op.m, z = tp.z + math.sin(math.rad(op.brg)) * op.m }) end
                end
            end
        end
    end
    if not best then
        Log(string.format("RELOCATE %s: no point with LOS in %s +/-%d deg, %d-%d m (%d tried: surface %d, too close %d, "
            .. "no LOS %d), ME position kept", k, Dir8(op.brg), sec, op.dmin or 1500, op.dmax or 4000, n, nSurf, nNear, nLos))
        return
    end
    Log(string.format("RELOCATE %s: %d tried (surface %d, too close %d, no LOS %d), best %.0f m above the target",
        k, n, nSurf, nNear, nLos, GroundY(best) - tgtH))
    local old = ju:getPoint()
    if not best then
        Log(string.format("RELOCATE %s: no point with LOS within %d m of %s %d m (%d tried), ME position kept",
            k, op.r, Dir8(op.brg), op.m, tried))
        return
    end
    local typ, uname, country = ju:getTypeName(), ju:getName(), ju:getCountry()
    local g = Group.getByName(j.group)
    pcall(g.destroy, g)
    local ok, err = pcall(coalition.addGroup, country, Group.Category.GROUND, {
        name = j.group, task = "Ground Nothing",
        units = { { type = typ, name = uname, skill = "Excellent", playerCanDrive = false,
                    x = best.x, y = best.z, heading = math.rad(BrgT(best, tp)) } },
        route = { points = { { x = best.x, y = best.z, type = "Turning Point", action = "Off Road", speed = 0 } } } })
    if not ok then Log("RELOCATE " .. k .. ": spawn failed: " .. tostring(err)); return end
    SetupGround(j.group)
    Log(string.format("RELOCATE %s: %s -> %s, %s %.0f m from target, %.0f m off the requested point, LOS to %d units",
        k, MGRS(old), MGRS(best), Dir8(BrgT(tp, best)), D2(tp, best), bd, #tus))
end

-- ══════════════════════════════════════════════════════════════
--  HAND-OFF / TICK
-- ══════════════════════════════════════════════════════════════
local function Handoff(k)
    local st = JC.st[k]
    st.units = {}
    for _, u in ipairs(TargetUnits(k)) do
        st.units[#st.units + 1] = { name = u:getName(), type = u:getTypeName(), label = Label(u:getTypeName()), pos = u:getPoint() }
    end
    st.ipPos = MGRStoPos(J(k).ip.mgrs)
    local ju = JtacUnit(k)
    local los, n = 0, 0
    for _, s in ipairs(st.units) do
        n = n + 1
        if ju and land.isVisible(Eye(ju:getPoint()), Eye(s.pos, 2)) then los = los + 1 end
    end
    Log(string.format("HANDOFF %s: %d target units, JTAC LOS %d/%d, IP %s %s", k, n, los, n, J(k).ip.name,
        st.ipPos and MGRS(st.ipPos) or "PARSE FAILED"))
    SetPhase(k, "CHECKIN")
end

local function Tick(_, now)
    local ok, err = pcall(function()
        local u = Hero()
        local cd = TRT.CD
        -- troops in contact: spawn the friendly group once Comms_Director has picked the JTAC
        if cd and cd.tic and not JC.ticDone then
            JC.ticDone = true
            if JC.st[cd.tic] then JC.st[cd.tic].tic = true; SpawnFriendly(cd.tic) end
        end
        for _, k in ipairs(CFG.ORDER) do
            local st = JC.st[k]
            if st.phase == "IDLE" and u then
                if CFG.HANDOFF == "CD" and cd then
                    if cd.phase == J(k).cdPhase then Handoff(k) end
                else
                    local tp = Centroid(TargetUnits(k))
                    if tp and NM(D2(u:getPoint(), tp)) <= CFG.HANDOFF_NM then Handoff(k) end
                end
            end
            LaserTick(k, now)
            if st.phase ~= "IDLE" and st.phase ~= "DONE" and st.phase ~= "TERMINATED"
                and #TargetUnits(k) == 0 and not st.pass then
                LaserOff(k, "target group dead")
                Log("target group dead outside a tracked pass: " .. k)
                Emit("DONE", { key = k })
                SetPhase(k, "DONE")
            end
            if st.phase == "READBACK" and st.rbT0 and not st.busy then
                local due = st.rbT0 + CFG.RB_PROMPT_S * ((st.rbPrompted or 0) + 1)
                if now >= due and (st.rbPrompted or 0) < 3 then
                    st.rbPrompted = (st.rbPrompted or 0) + 1
                    Jtac(k, string.format("%s, %s, say readback.", CFG.CS, J(k).disp), CFG.DUR.short)
                    Log(string.format("SAY READBACK %s (%d)", k, st.rbPrompted))
                end
            end
        end
    end)
    if not ok then Log("tick error: " .. tostring(err)) end
    return now + CFG.TICK
end

local EV = {}
function EV:onEvent(e)
    if not e or e.id ~= world.event.S_EVENT_SHOT or not e.weapon or not e.initiator then return end
    local ok, err = pcall(function()
        if e.initiator:getName() == CFG.PLAYER_UNIT then OnShot(e.weapon) end
    end)
    if not ok then Log("shot handler error: " .. tostring(err)) end
end

-- ══════════════════════════════════════════════════════════════
--  INIT
-- ══════════════════════════════════════════════════════════════
if TRT.Menu then
    TRT.Menu.Register("COMMS", "JC", Items, 15)
    TRT.Menu.RegisterNext("JC", NextText)
else
    Log("TRT.Menu missing (Menu_Manager.lua must load first) -> no F10 calls")
end
world.addEventHandler(EV)
timer.scheduleFunction(function()
    for _, k in ipairs(CFG.ORDER) do
        local ok, err = pcall(Relocate, k)
        if not ok then Log("RELOCATE " .. k .. " error: " .. tostring(err)) end
    end
    timer.scheduleFunction(Tick, nil, timer.getTime() + 2)
end, nil, timer.getTime() + 2)
do
    local r = AbortReply()
    Log(string.format("JTAC_Controller v%s online - abort challenge %s, reply %s", CFG.VERSION,
        CFG.ABORT.challenge, tostring(r)))
end
