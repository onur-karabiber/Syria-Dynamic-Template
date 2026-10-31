-- Field_Arrival | v1.0.0
--[[
  Divert / field arrival radio + procedure scoring - TRT Syria Dynamic Template (template-level module).
  Design: Onur's decisions 2026-10-31 (project doc claude/divert-arrival-2026-10-31.md).

  Replaces the native DCS tower for a divert. Comms_Director (>= v1.7.5) starts it from the OVERLORD divert
  branch with TRT.FA.Start("LTAG", { minFuel = <bool> }); any other module may do the same.
  v1.0.0 data: Incirlik (LTAG) only. Akrotiri (LCRA) = one more CFG.FIELDS entry + clips.

  CHAIN (LTAG; frequencies AIP TR ENR 2.1 + DCS terrain data; chart: Incirlik ILS or LOC Rwy 05):
    OVERLORD (CD)   "...proceed direct. Contact Ankara Control, 240.8."
    ANKARA 240.8    F10 check-in -> radar contact, squawk, direct DAN, FL150 (or present level, min FL110)
                    <= 50 NM (Adana MTMA radius, AIP) -> "contact Incirlik Approach 357.5"   (auto)
    APPROACH 357.5  F10 check-in -> QNH + altimeter, direct OSLUP, descend 8,000, expect ILS 05 via the arc
                    <= 20 DME DAN -> "cleared ILS 05 via the 15 DME arc, 3,800 until established" (auto)
                    established on the LOC <= 9 NM from THR 05 -> "contact Tower 360.1"         (auto)
    TOWER 360.1     F10 check-in -> wind, "runway 05, cleared to land" (+ de-arm if A/G stores remain)
                    after landing, < 40 kt -> "contact Ground 121.9"                            (auto)
    GROUND 121.9    F10 request taxi -> transient parking (via de-arm)                          -> DONE
  "Minimum fuel" (start option) is repeated to every new controller [OPNAV M-3710.7 6.2.6].
  A skipped controller is not penalised: the chain moves on by position (50 NM, LOC).
  Who talks when: a check-in is the pilot's call and waits on F10 (he retunes first); a hand-off is the
  controller's call and fires by position.

  SCORING (CFG.SCORING; TRT.addScore, each item once, CFG.PTS):
    ALT    assigned altitude (Ankara FL, Approach 8,000) not busted by > 300 ft for >= 5 s, until the arc /
           LOC: each bust -2 (cap -4); none +1. A floor arms when the hero first reaches it (or after 120 s).
    ARC    after the approach clearance, from 16.5 DME to LOC established: lowest altitude < 3,650 -> -2;
           else altitude at LOC established 3,650..4,100 -> +2; else 0.
    GOMSE  crossing 6.4 NM from THR 05 (GOMSE, D8.6 DAN): on the LOC and |alt - 2,300| <= 150 -> +2,
           <= 300 -> 0, else (or not on the LOC) -2.
    CLR    landing clearance before 1 NM final (or before touchdown): yes +1, no -3.
    FUEL   fuel at touchdown >= 2,000 lb +1 | >= 1,500 0 | lower -2 (2,000 = Flight_Timeline FIELD_RESERVE_LB).
  Altitudes are what the hero's altimeter shows: ISA pressure altitude from atmosphere pressure at the hero,
  referenced to 1013.25 hPa above the transition altitude (FL) and to the mission QNH below it.

  GEOMETRY: THR 05 from Airbase:getRunways() (course sign as in MOOSE AIRBASE:_InitRunways). DAN TACAN is
  placed 2.2 NM past THR 05 on the runway line (chart profile: GECEG D3.0 is 0.8 NM before THR) [V: the
  DCS beacon position is not readable from scripts]. LOC "established" = within 2.5 deg of the centreline
  seen from the runway far end, track within 45 deg of the runway, on the approach side.

  VOICE: tts/fa_clips.csv -> python tts/make_clips.py --set fa (src/Sounds/FA/; the AUDIO block below is
  rewritten in place). Pilot digits / squelch come from CV_Comms (cv:), "minimum fuel", "flight level",
  "thousand" from Comms_Director (cd:). A call is voiced only if every clip of it exists, else text only.

  Flags: 3300 active | 3301 Approach contacted | 3302 cleared to land | 3303 landed at the field (all latched 1)
  Exports: TRT.FA = { Start(key, opts), Supports(key), active, phase, field, items }
  Menu: F10 > COMMS (check-ins), INFO "Show: divert card" (Menu_Manager, order 12). Next-call text.
  Load order: after Menu_Manager and Core_Scoring (Score_Display hooks TRT.addScore at call time).
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.FA then
    env.info("[FA] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION          = "1.0.0",
    PLAYER_UNIT      = TRT.PLAYER_NAME or "Player_01",
    CS               = "HORNET 51",
    SCORING          = true,
    MAGVAR           = 5,          -- east; magnetic = true - MAGVAR (as Comms_Director)
    INTERNAL_FUEL_LB = 10860,
    TA_FT            = 10000,      -- transition altitude (chart)
    TICK             = 1,          -- s

    SND_DIR   = "Sounds/FA/",
    TX_POWER  = 1000,              -- W
    REPLY_GAP = 1.2,               -- s before a controller answers
    PILOT_GAP = 0.8,               -- s before a pilot readback / call
    AUDIO_PAD = 0.3,
    NO_AUDIO_CTL   = 4.0,          -- s assumed airtime of a text-only call
    NO_AUDIO_PILOT = 3.0,
    DUR_CTL   = 14,
    DUR_PILOT = 9,

    FLAGS = { ACTIVE = 3300, APP = 3301, CLEARED = 3302, LANDED = 3303 },

    PTS = {
        ALT_BUST = -2, ALT_CAP = -4, ALT_CLEAN = 1,
        ARC_LOW = -2, ARC_GOOD = 2,
        GOMSE_GOOD = 2, GOMSE_OK = 0, GOMSE_BAD = -2,
        CLR_YES = 1, CLR_NO = -3,
        FUEL_GOOD = 1, FUEL_OK = 0, FUEL_LOW = -2,
    },
    BUST_TOL_FT  = 300,
    BUST_HOLD_S  = 5,
    ARM_GRACE_S  = 120,
    ARC_LOW_FT   = 150,            -- below arcAlt by more than this = low
    ARC_HIGH_FT  = 300,            -- above arcAlt by at most this = good at LOC intercept
    GOMSE_GOOD_FT = 150,
    GOMSE_OK_FT   = 300,
    FUEL_GOOD_LB = 2000,
    FUEL_OK_LB   = 1500,
    TAXI_KT      = 40,             -- below this after touchdown: Tower -> Ground

    FIELDS = {
        LTAG = {
            key = "LTAG", name = "Incirlik", airbase = "Incirlik",
            lat = 37.00205, lon = 35.426083,
            rwy = "05", crsMag = 49,                 -- ILS 05 final approach course (chart)
            freq = { ANKARA = "240.800", APP = "357.500", TWR = "360.100", GND = "121.900" },
            label = { ANKARA = "ANKARA CONTROL", APP = "INCIRLIK APPROACH", TWR = "INCIRLIK TOWER",
                      GND = "INCIRLIK GROUND" },
            squawk   = "4627",
            ankFL    = 150, ankMinFL = 110,
            handAppNm = 50,                          -- Adana MTMA radius (AIP ENR 2.1)
            appAlt   = 8000, appLowFt = 7700,        -- OSLUP MHA 8,000; below 7,700 no descent instruction
            clrDme   = 20,
            arcAlt   = 3800, arcEntryDme = 16.5,
            fafNm    = 6.4, fafAlt = 2300,           -- GOMSE (D8.6 DAN) from THR 05
            danPastThrNm = 2.2,                      -- [V] see header
            twrHandNm = 9, twrHandFallbackNm = 7,
            clrWindowNm = 1.0,
            locHalfDeg = 2.5,
            tcn = "21X DAN", ils = "109.3 IDAN 049",
        },
    },

    -- BEGIN AUDIO (generated by tts/make_clips.py --set fa; do not edit by hand)
    AUDIO = {
        ank_rc                 = { ch = "ANKARA", len = 3.06 },
        ank_minfuel            = { ch = "ANKARA", len = 1.54 },
        ank_squawk             = { ch = "ANKARA", len = 0.54 },
        ank_0                  = { ch = "ANKARA", len = 0.54 },
        ank_1                  = { ch = "ANKARA", len = 0.37 },
        ank_2                  = { ch = "ANKARA", len = 0.39 },
        ank_3                  = { ch = "ANKARA", len = 0.43 },
        ank_4                  = { ch = "ANKARA", len = 0.36 },
        ank_5                  = { ch = "ANKARA", len = 0.38 },
        ank_6                  = { ch = "ANKARA", len = 0.52 },
        ank_7                  = { ch = "ANKARA", len = 0.50 },
        ank_8                  = { ch = "ANKARA", len = 0.40 },
        ank_9                  = { ch = "ANKARA", len = 0.45 },
        ank_direct_dan         = { ch = "ANKARA", len = 1.38 },
        ank_desc_fl            = { ch = "ANKARA", len = 1.87 },
        ank_climb_fl           = { ch = "ANKARA", len = 1.91 },
        ank_maint_fl           = { ch = "ANKARA", len = 1.23 },
        ank_handoff            = { ch = "ANKARA", len = 4.10 },
        p_fa_ank_ci            = { ch = "ANKARA", len = 4.04 },
        p_fa_squawk            = { ch = "ANKARA", len = 0.54 },
        p_fa_direct_dan        = { ch = "ANKARA", len = 0.58 },
        p_fa_desc_fl           = { ch = "ANKARA", len = 0.88 },
        p_fa_climb_fl          = { ch = "ANKARA", len = 0.99 },
        p_fa_maint_fl          = { ch = "ANKARA", len = 1.21 },
        p_fa_cs                = { ch = "ANKARA", len = 0.83 },
        p_fa_ank_hand_rb       = { ch = "ANKARA", len = 2.80 },
        app_rc                 = { ch = "LTAG_APP", len = 2.35 },
        app_minfuel            = { ch = "LTAG_APP", len = 1.08 },
        app_qnh                = { ch = "LTAG_APP", len = 1.08 },
        app_altimeter          = { ch = "LTAG_APP", len = 0.58 },
        app_0                  = { ch = "LTAG_APP", len = 0.50 },
        app_1                  = { ch = "LTAG_APP", len = 0.35 },
        app_2                  = { ch = "LTAG_APP", len = 0.33 },
        app_3                  = { ch = "LTAG_APP", len = 0.36 },
        app_4                  = { ch = "LTAG_APP", len = 0.40 },
        app_5                  = { ch = "LTAG_APP", len = 0.36 },
        app_6                  = { ch = "LTAG_APP", len = 0.50 },
        app_7                  = { ch = "LTAG_APP", len = 0.43 },
        app_8                  = { ch = "LTAG_APP", len = 0.48 },
        app_9                  = { ch = "LTAG_APP", len = 0.39 },
        app_osl                = { ch = "LTAG_APP", len = 5.40 },
        app_osl_low            = { ch = "LTAG_APP", len = 3.89 },
        app_clr                = { ch = "LTAG_APP", len = 5.96 },
        app_handoff            = { ch = "LTAG_APP", len = 3.31 },
        p_fa_app_ci            = { ch = "APP", len = 2.03 },
        p_fa_req_ils           = { ch = "APP", len = 2.34 },
        p_fa_app_rb            = { ch = "APP", len = 2.80 },
        p_fa_app_rb_low        = { ch = "APP", len = 1.76 },
        p_fa_altimeter         = { ch = "APP", len = 0.58 },
        p_fa_clr_rb            = { ch = "APP", len = 5.22 },
        p_fa_app_hand_rb       = { ch = "APP", len = 2.76 },
        twr_hello              = { ch = "LTAG_TWR", len = 1.92 },
        twr_wind               = { ch = "LTAG_TWR", len = 0.47 },
        twr_at                 = { ch = "LTAG_TWR", len = 0.29 },
        twr_calm               = { ch = "LTAG_TWR", len = 0.71 },
        twr_0                  = { ch = "LTAG_TWR", len = 0.59 },
        twr_1                  = { ch = "LTAG_TWR", len = 0.38 },
        twr_2                  = { ch = "LTAG_TWR", len = 0.43 },
        twr_3                  = { ch = "LTAG_TWR", len = 0.46 },
        twr_4                  = { ch = "LTAG_TWR", len = 0.44 },
        twr_5                  = { ch = "LTAG_TWR", len = 0.40 },
        twr_6                  = { ch = "LTAG_TWR", len = 0.47 },
        twr_7                  = { ch = "LTAG_TWR", len = 0.48 },
        twr_8                  = { ch = "LTAG_TWR", len = 0.31 },
        twr_9                  = { ch = "LTAG_TWR", len = 0.57 },
        twr_clr                = { ch = "LTAG_TWR", len = 1.76 },
        twr_dearm              = { ch = "LTAG_TWR", len = 2.37 },
        twr_ground             = { ch = "LTAG_TWR", len = 3.31 },
        p_fa_twr_ci            = { ch = "TWR", len = 1.55 },
        p_fa_ils_gear          = { ch = "TWR", len = 2.96 },
        p_fa_ils_gear_ord      = { ch = "TWR", len = 3.79 },
        p_fa_ctl_rb            = { ch = "TWR", len = 2.58 },
        p_fa_ctl_rb_dearm      = { ch = "TWR", len = 3.31 },
        p_fa_twr_gnd_rb        = { ch = "TWR", len = 2.51 },
        gnd_taxi               = { ch = "LTAG_GND", len = 2.56 },
        gnd_taxi_dearm         = { ch = "LTAG_GND", len = 3.84 },
        p_fa_gnd_ci            = { ch = "GND", len = 5.05 },
        p_fa_gnd_rb            = { ch = "GND", len = 2.30 },
        p_fa_gnd_rb_dearm      = { ch = "GND", len = 2.48 },
    },
    -- END AUDIO
}

-- ══════════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════════
local FA = {
    active = false, phase = "IDLE", field = nil, busy = false,
    queue = {}, qPlaying = false,
    minFuel = false, items = {}, altPts = 0, busts = 0,
    floor = nil,                 -- { kind = "FL"|"QNH", ft, t, armed, below, bust }
    appClr = false, arc = nil,   -- arc = { min, est }
    est = false, prevApp = nil, gomseDone = false, clrDone = false,
    cleared = false, landed = nil, ordn = 0,
}
TRT.FA = FA

local F                         -- active field table
local CH = {}                   -- channel key -> { hz, mod, label, f }
local GEO                       -- { thr, u, len, dan, loc } (DCS vec3 x north, z east)

local function Log(s) env.info("[FA] " .. s) end
local function Now() return timer.getTime() end
local function Hero()
    local u = Unit.getByName(CFG.PLAYER_UNIT)
    if u and u:isExist() then return u end
end
local function Msg(text, dur)
    if TRT.Menu and TRT.Menu.Msg then TRT.Menu.Msg(text, dur); return end
    local u = Hero(); if not u then return end
    trigger.action.outTextForGroup(u:getGroup():getID(), text, dur or 10)
end
local function Fq(x) local v = tostring(x):gsub("0+$", ""); return (v:gsub("%.$", ".0")) end   -- "357.500" -> "357.5"
local function SetFlag(f) trigger.action.setUserFlag(tostring(f), 1) end
local function MenuRefresh() if TRT.Menu then TRT.Menu.Refresh() end end

-- ══════════════════════════════════════════════════════════════
--  ATMOSPHERE / MEASUREMENT
-- ══════════════════════════════════════════════════════════════
local M2NM, FT = 1 / 1852, 3.28084

local function QnhPa()
    local w = env.mission and env.mission.weather
    local mm = w and tonumber(w.qnh)
    return (mm or 760) * 133.3224
end

local function PressAt(p)
    local ok, _, pr = pcall(atmosphere.getTemperatureAndPressure, p)
    if ok and type(pr) == "number" and pr > 0 then return pr end
end

--- Altimeter reading (ft) for reference pressure refPa (ISA); MSL if the pressure is unavailable.
local function AltFt(p, refPa)
    local pr = PressAt(p)
    if not pr then return p.y * FT end
    return 145366.45 * (1 - (pr / refPa) ^ 0.190284)
end
local function FLft(p)  return AltFt(p, 101325) end
local function QnhFt(p) return AltFt(p, QnhPa()) end

local function FuelLb(u) return (u:getFuel() or 0) * CFG.INTERNAL_FUEL_LB end
local function SpeedKt(u)
    local v = u:getVelocity() or { x = 0, y = 0, z = 0 }
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) * 1.94384
end
local function TrackDeg(u)
    local v = u:getVelocity() or { x = 0, z = 0 }
    if math.abs(v.x) + math.abs(v.z) < 1 then return nil end
    return math.deg(math.atan2(v.z, v.x)) % 360
end
local function ADiff(a, b) local d = (a - b + 360) % 360; return (d > 180) and (360 - d) or d end
local function Dist2D(a, b) local dx, dz = a.x - b.x, a.z - b.z; return math.sqrt(dx * dx + dz * dz) * M2NM end

local function AGCount(u)
    local ok, ammo = pcall(u.getAmmo, u)
    if not ok or type(ammo) ~= "table" then return 0 end
    local n = 0
    for _, a in ipairs(ammo) do
        local d = a.desc or {}
        local c = d.category
        if c == Weapon.Category.BOMB or c == Weapon.Category.ROCKET
           or (c == Weapon.Category.MISSILE and d.missileCategory ~= Weapon.MissileCategory.AAM) then
            n = n + (a.count or 0)
        end
    end
    return n
end

--- Wind at the field (10 m AGL): magnetic FROM direction rounded to 10 deg, knots. nil dir = calm.
local function FieldWind()
    if not GEO then return nil, 0 end
    local p = { x = GEO.thr.x, z = GEO.thr.z }
    p.y = land.getHeight({ x = p.x, y = p.z }) + 10
    local ok, v = pcall(atmosphere.getWind, p)
    if not ok or type(v) ~= "table" then return nil, 0 end
    local kt = math.sqrt(v.x * v.x + v.z * v.z) * 1.94384
    if kt < 2 then return nil, 0 end
    local from = (math.deg(math.atan2(-v.z, -v.x)) - CFG.MAGVAR) % 360
    local d = math.floor(from / 10 + 0.5) * 10
    if d == 0 then d = 360 end
    return d, math.floor(kt + 0.5)
end

-- ══════════════════════════════════════════════════════════════
--  GEOMETRY (runway 05 line, DAN, LOC)
-- ══════════════════════════════════════════════════════════════
local function BuildGeo(f)
    local crsT = (f.crsMag + CFG.MAGVAR) % 360
    local thr, hdg, len
    local ab = Airbase.getByName(f.airbase)
    local ok, rws = pcall(function() return ab and ab:getRunways() end)
    if ok and type(rws) == "table" then
        for _, r in ipairs(rws) do
            local h = (-math.deg(r.course or 0)) % 360          -- MOOSE: bearing = -course
            if ADiff(h, crsT) > 90 then h = (h + 180) % 360 end   -- the 05 direction of "05-23"
            if ADiff(h, crsT) <= 15 and r.position and r.length then
                hdg, len = h, r.length
                local u = { x = math.cos(math.rad(h)), z = math.sin(math.rad(h)) }
                thr = { x = r.position.x - u.x * len / 2, y = r.position.y, z = r.position.z - u.z * len / 2 }
                break
            end
        end
    end
    if not thr then
        local okc, c = pcall(coord.LLtoLO, f.lat, f.lon, 0)
        if not (okc and c) then return nil end
        hdg, len = crsT, 3048
        local u = { x = math.cos(math.rad(hdg)), z = math.sin(math.rad(hdg)) }
        thr = { x = c.x - u.x * len / 2, y = c.y, z = c.z - u.z * len / 2 }
        Log("runway data not found, THR from field centre + chart course [V]")
    end
    local u = { x = math.cos(math.rad(hdg)), z = math.sin(math.rad(hdg)) }
    local g = { thr = thr, u = u, hdg = hdg, len = len }
    g.dan = { x = thr.x + u.x * f.danPastThrNm * 1852, z = thr.z + u.z * f.danPastThrNm * 1852 }
    g.loc = { x = thr.x + u.x * len, z = thr.z + u.z * len }
    Log(string.format("geo %s THR05 x=%.0f z=%.0f hdg %.1fT len %.0f m", f.key, thr.x, thr.z, hdg, len))
    return g
end

--- app = NM from THR on the approach side (+), lat = NM off the centreline, dme = NM from DAN, locDev deg.
local function Rel(p)
    local dx, dz = p.x - GEO.thr.x, p.z - GEO.thr.z
    local along = dx * GEO.u.x + dz * GEO.u.z
    local lat = -dx * GEO.u.z + dz * GEO.u.x
    local app = -along * M2NM
    local dLoc = (GEO.len - along)
    local locDev = math.deg(math.atan2(math.abs(lat), math.max(dLoc, 1)))
    return app, math.abs(lat) * M2NM, Dist2D(p, GEO.dan), locDev
end

local function Established(u, app, locDev)
    if app < -0.5 or app > 25 or locDev > F.locHalfDeg then return false end
    local tr = TrackDeg(u)
    return tr ~= nil and ADiff(tr, GEO.hdg) <= 45
end

-- ══════════════════════════════════════════════════════════════
--  RADIO (chained token transmissions, one queue)
-- ══════════════════════════════════════════════════════════════
local function ClipOf(id)
    local set, cid = id:match("^(%a+):(.+)$")
    local tbl, dir
    if set == "cv" then
        tbl, dir = TRT.CV_AUDIO, TRT.CV_SND_DIR or "Sounds/CV/"
    elseif set == "cd" then
        tbl, dir = TRT.CD_AUDIO, TRT.CD_SND_DIR or "Sounds/CAS1/"
    else
        tbl, dir, cid = CFG.AUDIO, CFG.SND_DIR, id
    end
    local a = tbl and tbl[cid]
    if a then return a.len, dir .. cid .. ".ogg" end
end

local txn = 0
local function TxSeq(seq)
    if type(seq) ~= "table" then return 0 end
    local ch = CH[seq.ch]
    if not ch then return 0 end
    local t = 0
    txn = txn + 1
    for i, id in ipairs(seq) do
        if type(id) == "number" then
            t = t + id
        else
            local len, file = ClipOf(id)
            if len then
                local name = "FA_" .. txn .. "_" .. i
                timer.scheduleFunction(function()
                    local u = Hero(); if not u then return end
                    local pos = u:getPoint()
                    trigger.action.radioTransmission(file, { x = pos.x, y = pos.y + 30, z = pos.z },
                        ch.mod, false, ch.hz, CFG.TX_POWER, name)
                end, nil, Now() + t + 0.01)
                t = t + len + ((id == "cv:sq_up") and 0 or 0.03)
            end
        end
    end
    return t
end

--- Token sequence on channel ch wrapped in squelch; nil entries are skipped; nested tables flattened.
local function S(ch, ...)
    local out = { ch = ch, "cv:sq_up" }
    local function add(x)
        if type(x) == "table" then for _, y in ipairs(x) do add(y) end
        elseif x ~= nil and x ~= false then out[#out + 1] = x end
    end
    for i = 1, select("#", ...) do add((select(i, ...))) end
    out[#out + 1] = "cv:sq_dn"
    return out
end

--- seq if every clip exists, else nil (text only, never half-voiced).
local function Voiced(seq)
    if type(seq) ~= "table" then return nil end
    for _, id in ipairs(seq) do
        if type(id) == "string" and not ClipOf(id) then
            Log("text only, missing clip " .. id)
            return nil
        end
    end
    return seq
end

local function Dg(prefix, v)
    local t = {}
    for c in tostring(v):gmatch("%d") do t[#t + 1] = prefix .. c end
    return t
end
local function PD(v) return Dg("cv:p_", v) end

local QNext
local function Q(kind, ch, text, seq, gap, fn, after)
    FA.queue[#FA.queue + 1] = { kind = kind, ch = ch, text = text, seq = seq, gap = gap, fn = fn, after = after }
    if not FA.qPlaying then QNext() end
end

QNext = function()
    local x = table.remove(FA.queue, 1)
    if not x then FA.qPlaying = false; return end
    FA.qPlaying = true
    timer.scheduleFunction(function()
        local len = TxSeq(x.seq)
        local label = (x.kind == "PILOT") and CFG.CS or ((CH[x.ch] and CH[x.ch].label or x.ch)
            .. " " .. (CH[x.ch] and CH[x.ch].f or ""))
        local base = (x.kind == "PILOT") and CFG.DUR_PILOT or CFG.DUR_CTL
        Msg("[" .. label .. "] " .. x.text, math.max(base, len + 2))
        Log("RADIO " .. label .. ": " .. x.text .. ((len > 0) and "" or " (text)"))
        if x.fn then local ok, err = pcall(x.fn); if not ok then Log("fn error: " .. tostring(err)) end end
        local wait = (len > 0) and (len + CFG.AUDIO_PAD)
            or ((x.kind == "PILOT") and CFG.NO_AUDIO_PILOT or CFG.NO_AUDIO_CTL)
        timer.scheduleFunction(function()
            if x.after then local ok, err = pcall(x.after); if not ok then Log("after error: " .. tostring(err)) end end
            QNext()
        end, nil, Now() + wait)
    end, nil, Now() + (x.gap or CFG.REPLY_GAP))
end

local function Pilot(ch, text, seq, fn, after)
    Q("PILOT", ch, text, Voiced(seq), CFG.PILOT_GAP, fn, after)
end
local function Ctl(ch, text, seq, fn, after)
    Q("CTL", ch, text, Voiced(seq), CFG.REPLY_GAP, fn, after)
end

local function Begin() FA.busy = true; MenuRefresh() end
local function Done(phase)
    return function()
        if phase then FA.phase = phase end
        FA.busy = false
        MenuRefresh()
    end
end

-- ══════════════════════════════════════════════════════════════
--  SCORING
-- ══════════════════════════════════════════════════════════════
local function Score(item, pts, why)
    if FA.items[item] and item ~= "ALT" then return end
    FA.items[item] = FA.items[item] or {}
    FA.items[item].pts = (FA.items[item].pts or 0) + pts
    FA.items[item].why = why
    Log(string.format("SCORE %s %+d %s", item, pts, why))
    local reason = string.format("Divert %s: %s", F and F.key or "?", why)
    if CFG.SCORING and TRT.addScore and pts ~= 0 then
        TRT.addScore(pts, reason)
    else
        Msg(string.format("%s (%+d)%s", reason, pts, CFG.SCORING and "" or " [shadow]"), 8)
    end
end

local function SettleAlt(why)
    if FA.altSettled then return end
    FA.altSettled = true
    if FA.busts == 0 and FA.altArmedEver then
        Score("ALT", CFG.PTS.ALT_CLEAN, "assigned altitudes held" .. (why and (" (" .. why .. ")") or ""))
    elseif FA.busts == 0 then
        Log("ALT not scored (no assigned altitude was reached)")
    end
end

local function SetFloor(kind, ft)
    FA.floor = { kind = kind, ft = ft, t = Now(), armed = false, below = nil, bust = false }
    Log(string.format("floor %s %d ft", kind, ft))
end

local function SettleArc(alt)
    if not FA.arc or FA.arc.done then return end
    FA.arc.done = true
    local a = FA.arc
    if a.min < F.arcAlt - CFG.ARC_LOW_FT then
        Score("ARC", CFG.PTS.ARC_LOW, string.format("below %d on the arc (lowest %d ft)", F.arcAlt, math.floor(a.min)))
    elseif alt and alt >= F.arcAlt - CFG.ARC_LOW_FT and alt <= F.arcAlt + CFG.ARC_HIGH_FT then
        Score("ARC", CFG.PTS.ARC_GOOD, string.format("arc at %d, LOC intercept %d ft", F.arcAlt, math.floor(alt)))
    else
        Score("ARC", 0, string.format("arc not below %d, LOC intercept %s ft", F.arcAlt,
            alt and tostring(math.floor(alt)) or "n/a"))
    end
end

local function CheckClearance(why)
    if FA.clrDone then return end
    FA.clrDone = true
    if FA.cleared then
        Score("CLR", CFG.PTS.CLR_YES, "cleared to land before " .. why)
    else
        Score("CLR", CFG.PTS.CLR_NO, "no landing clearance at " .. why)
    end
end

local function Monitor(u, p, app, lat, dme, locDev, est)
    -- ALT: assigned floor (Ankara FL / Approach 8,000) until arc entry or LOC
    local fl = FA.floor
    if fl and not FA.altSettled then
        local alt = (fl.kind == "FL") and FLft(p) or QnhFt(p)
        if not fl.armed and (alt >= fl.ft - CFG.BUST_TOL_FT or Now() - fl.t >= CFG.ARM_GRACE_S) then
            fl.armed = true; FA.altArmedEver = true
            Log(string.format("floor %s %d armed at %d ft", fl.kind, fl.ft, math.floor(alt)))
        end
        if fl.armed then
            if alt < fl.ft - CFG.BUST_TOL_FT then
                fl.below = fl.below or Now()
                if not fl.bust and Now() - fl.below >= CFG.BUST_HOLD_S then
                    fl.bust = true
                    FA.busts = FA.busts + 1
                    local pts = math.max(CFG.PTS.ALT_BUST, CFG.PTS.ALT_CAP - FA.altPts)
                    FA.altPts = FA.altPts + pts
                    local what = (fl.kind == "FL") and string.format("FL%03d", fl.ft / 100)
                        or string.format("%d ft", fl.ft)
                    if pts ~= 0 then
                        Score("ALT", pts, string.format("below assigned %s (%d)", what, math.floor(alt)))
                    else
                        Log("ALT bust beyond cap: " .. what)
                    end
                end
            else
                fl.below, fl.bust = nil, false
            end
        end
    end

    -- arc segment (approach clearance given, inside the entry DME)
    if FA.appClr and not FA.arc and not est and dme <= F.arcEntryDme then
        FA.arc = { min = QnhFt(p), t = Now() }
        FA.floor = nil
        SettleAlt("arc")
        Log(string.format("arc entered, DME %.1f, alt %d", dme, math.floor(FA.arc.min)))
    end
    if FA.arc and not FA.arc.done then
        local a = QnhFt(p)
        if a < FA.arc.min then FA.arc.min = a end
    end

    -- LOC established
    if est and not FA.est then
        FA.est = true
        local a = QnhFt(p)
        Log(string.format("LOC established %.1f NM from THR, %d ft", app, math.floor(a)))
        FA.floor = nil
        SettleAlt("LOC")
        SettleArc(a)
    end

    -- GOMSE crossing
    if not FA.gomseDone and FA.prevApp and FA.prevApp > F.fafNm and app <= F.fafNm and app > 0 then
        FA.gomseDone = true
        local a = QnhFt(p)
        local d = a - F.fafAlt
        if not est then
            Score("GOMSE", CFG.PTS.GOMSE_BAD, string.format("not on the LOC at GOMSE (%.1f NM off)", lat))
        elseif math.abs(d) <= CFG.GOMSE_GOOD_FT then
            Score("GOMSE", CFG.PTS.GOMSE_GOOD, string.format("GOMSE %d ft (%+d)", math.floor(a), math.floor(d)))
        elseif math.abs(d) <= CFG.GOMSE_OK_FT then
            Score("GOMSE", CFG.PTS.GOMSE_OK, string.format("GOMSE %d ft (%+d)", math.floor(a), math.floor(d)))
        else
            Score("GOMSE", CFG.PTS.GOMSE_BAD, string.format("GOMSE %d ft (%+d)", math.floor(a), math.floor(d)))
        end
    end

    -- 1 NM final
    if not FA.clrDone and FA.prevApp and FA.prevApp > F.clrWindowNm and app <= F.clrWindowNm and app > -0.5
       and lat <= 0.5 then
        local agl = (p.y - land.getHeight({ x = p.x, y = p.z })) * FT
        if agl < 1500 then CheckClearance("1 NM final") end
    end
    FA.prevApp = app
end

-- ══════════════════════════════════════════════════════════════
--  CALLS
-- ══════════════════════════════════════════════════════════════
local function FLnow(p) return math.floor(FLft(p) / 1000 + 0.5) * 10 end   -- nearest 10 (FL)

--- Pilot "flight level 230" | "8 thousand"
local function PAltTokens(p)
    local fl = FLft(p)
    if fl >= CFG.TA_FT + 500 then
        local n = FLnow(p)
        return string.format("flight level %03d", n), { "cd:p_fl", PD(string.format("%03d", n)) }
    end
    local k = math.max(1, math.floor(QnhFt(p) / 1000 + 0.5))
    return string.format("%d thousand", k), { PD(k), "cd:p_thousand" }
end

local function A_Ankara()
    local u = Hero(); if not u then return end
    Begin()
    local p = u:getPoint()
    local fl = math.floor(FLft(p) / 100 + 0.5)                 -- FL (hundreds of ft)
    local asg = math.floor(fl / 10 + 0.5) * 10
    asg = math.max(F.ankMinFL, math.min(F.ankFL, asg))
    local verb = (fl > asg + 3) and "desc" or ((fl < asg - 3) and "climb" or "maint")
    local vtext = ({ desc = "descend and maintain", climb = "climb and maintain", maint = "maintain" })[verb]
    local ptext = ({ desc = "descend", climb = "climb", maint = "maintain" })[verb]
    local mf = FA.minFuel
    local atxt, atok = PAltTokens(p)
    Pilot("ANKARA", string.format("Ankara Control, %s, military, diverting %s, %s%s.", CFG.CS, F.name,
            mf and "minimum fuel, " or "", atxt),
        S("ANKARA", "p_fa_ank_ci", mf and "cd:p_min_fuel", atok))
    Ctl("ANKARA", string.format("%s, Ankara Control, radar contact.%s Squawk %s. Proceed direct DAN, %s flight level %03d.",
            CFG.CS, mf and " Roger, minimum fuel." or "", F.squawk, vtext, asg),
        S("ANKARA", "ank_rc", mf and "ank_minfuel", "ank_squawk", Dg("ank_", F.squawk), "ank_direct_dan",
            "ank_" .. verb .. "_fl", Dg("ank_", string.format("%03d", asg))),
        function() SetFloor("FL", asg * 100); FA.phase = "ANK" end)
    Pilot("ANKARA", string.format("Squawk %s, direct DAN, %s flight level %03d, %s.", F.squawk, ptext, asg, CFG.CS),
        S("ANKARA", "p_fa_squawk", PD(F.squawk), "p_fa_direct_dan", "p_fa_" .. verb .. "_fl",
            PD(string.format("%03d", asg)), "p_fa_cs"),
        nil, Done("ANK"))
end

local function A_AnkHandoff()
    Begin()
    Ctl("ANKARA", string.format("%s, contact %s Approach, %s.", CFG.CS, F.name, Fq(F.freq.APP)),
        S("ANKARA", "ank_handoff"))
    Pilot("ANKARA", string.format("%s, %s.", Fq(F.freq.APP), CFG.CS), S("ANKARA", "p_fa_ank_hand_rb"),
        nil, Done("APP_CI"))
end

local function A_Approach()
    local u = Hero(); if not u then return end
    Begin()
    local p = u:getPoint()
    local mf = FA.minFuel
    local atxt, atok = PAltTokens(p)
    local qnh = string.format("%04d", math.floor(QnhPa() / 100 + 0.5))
    local inhg = string.format("%04d", math.floor(QnhPa() / 3386.389 * 100 + 0.5))
    local low = QnhFt(p) < F.appLowFt
    Pilot("APP", string.format("%s Approach, %s, %s%s, request ILS runway %s, full stop.", F.name, CFG.CS,
            mf and "minimum fuel, " or "", atxt, F.rwy),
        S("APP", "p_fa_app_ci", mf and "cd:p_min_fuel", atok, "p_fa_req_ils"))
    Ctl("APP", string.format("%s, %s Approach, radar contact.%s %s QNH %s, altimeter %s.%s.%s Expect ILS runway %s via the 15 DME arc.",
            CFG.CS, F.name, mf and " Roger, minimum fuel." or "", F.name, qnh, inhg:sub(1, 2) .. "." .. inhg:sub(3, 4),
            " Proceed direct OSLUP", low and "" or string.format(" Descend and maintain %d.", F.appAlt), F.rwy),
        S("APP", "app_rc", mf and "app_minfuel", "app_qnh", Dg("app_", qnh), "app_altimeter", Dg("app_", inhg),
            low and "app_osl_low" or "app_osl"),
        function()
            if not low then SetFloor("QNH", F.appAlt) else FA.floor = nil end
            FA.phase = "APP"; SetFlag(CFG.FLAGS.APP)
        end)
    Pilot("APP", string.format("Direct OSLUP, %sexpect the arc, altimeter %s, %s.", low and "" or
            string.format("descend %d, ", F.appAlt), inhg:sub(1, 2) .. "." .. inhg:sub(3, 4), CFG.CS),
        S("APP", low and "p_fa_app_rb_low" or "p_fa_app_rb", "p_fa_altimeter", PD(inhg), "p_fa_cs"),
        nil, Done("APP"))
end

local function A_AppClear()
    Begin()
    Ctl("APP", string.format("%s, cleared ILS runway %s approach via the 15 DME arc. Maintain %d until established.",
            CFG.CS, F.rwy, F.arcAlt), S("APP", "app_clr"),
        function() FA.appClr = true; FA.phase = "APP_CLR" end)
    Pilot("APP", string.format("Cleared ILS runway %s via the arc, %d until established, %s.", F.rwy, F.arcAlt, CFG.CS),
        S("APP", "p_fa_clr_rb"), nil, Done("APP_CLR"))
end

local function A_AppHandoff()
    Begin()
    Ctl("APP", string.format("%s, contact %s Tower, %s.", CFG.CS, F.name, Fq(F.freq.TWR)), S("APP", "app_handoff"))
    Pilot("APP", string.format("%s, %s.", Fq(F.freq.TWR), CFG.CS), S("APP", "p_fa_app_hand_rb"), nil, Done("TWR_CI"))
end

local function A_Tower()
    local u = Hero(); if not u then return end
    Begin()
    local mf = FA.minFuel
    FA.ordn = AGCount(u)
    local ord = FA.ordn > 0
    Pilot("TWR", string.format("%s Tower, %s, %sILS runway %s, gear down, full stop%s.", F.name, CFG.CS,
            mf and "minimum fuel, " or "", F.rwy, ord and string.format(", unexpended ordnance (%d)", FA.ordn) or ""),
        S("TWR", "p_fa_twr_ci", mf and "cd:p_min_fuel", ord and "p_fa_ils_gear_ord" or "p_fa_ils_gear"))
    local dir, kt = FieldWind()
    local wtxt, wtok
    if dir then
        wtxt = string.format("wind %03d at %d", dir, kt)
        wtok = { "twr_wind", Dg("twr_", string.format("%03d", dir)), "twr_at", Dg("twr_", kt), 0.1 }
    else
        wtxt, wtok = "wind calm", { "twr_calm" }
    end
    Ctl("TWR", string.format("%s, %s Tower, %s, runway %s, cleared to land.%s", CFG.CS, F.name, wtxt, F.rwy,
            ord and " After landing, taxi to the de-arm area." or ""),
        S("TWR", "twr_hello", wtok, "twr_clr", ord and "twr_dearm"),
        function()
            FA.cleared = true; FA.clearedT = Now(); FA.phase = "TWR"; SetFlag(CFG.FLAGS.CLEARED)
            Log("cleared to land")
        end)
    Pilot("TWR", string.format("Cleared to land runway %s%s, %s.", F.rwy, ord and ", de-arm after landing" or "", CFG.CS),
        S("TWR", ord and "p_fa_ctl_rb_dearm" or "p_fa_ctl_rb"), nil, Done("TWR"))
end

local function A_TwrToGround()
    Begin()
    Ctl("TWR", string.format("%s, contact Ground, %s.", CFG.CS, Fq(F.freq.GND)), S("TWR", "twr_ground"))
    Pilot("TWR", string.format("Ground, %s, %s.", Fq(F.freq.GND), CFG.CS), S("TWR", "p_fa_twr_gnd_rb"), nil, Done("GND_CI"))
end

local function Summary()
    local order = { "ALT", "ARC", "GOMSE", "CLR", "FUEL" }
    local out, tot = { string.format("── DIVERT %s ──", F and F.key or "?") }, 0
    for _, k in ipairs(order) do
        local it = FA.items[k]
        if it then
            tot = tot + it.pts
            out[#out + 1] = string.format("%-6s %+d  %s", k, it.pts, it.why or "")
        else
            out[#out + 1] = string.format("%-6s  -  not scored", k)
        end
    end
    out[#out + 1] = string.format("TOTAL  %+d%s", tot, CFG.SCORING and "" or " (shadow)")
    return table.concat(out, "\n")
end

local function Finish(why)
    if FA.phase == "DONE" then return end
    FA.phase = "DONE"; FA.busy = false
    Log("DONE (" .. why .. ")\n" .. Summary())
    Msg(Summary(), 25)
    MenuRefresh()
end

local function A_Ground()
    local u = Hero(); if not u then return end
    Begin()
    local ord = FA.ordn > 0
    Pilot("GND", string.format("%s Ground, %s, clear of runway %s, request taxi to transient parking.", F.name, CFG.CS, F.rwy),
        S("GND", "p_fa_gnd_ci"))
    Ctl("GND", string.format("%s, %s Ground, %s", CFG.CS, F.name,
            ord and "taxi to the de-arm area, then transient parking." or "taxi to transient parking."),
        S("GND", ord and "gnd_taxi_dearm" or "gnd_taxi"))
    Pilot("GND", (ord and "De-arm, then transient parking, " or "Taxi to transient parking, ") .. CFG.CS .. ".",
        S("GND", ord and "p_fa_gnd_rb_dearm" or "p_fa_gnd_rb"), nil, function() Finish("ground readback") end)
end

-- ══════════════════════════════════════════════════════════════
--  TICK (position-driven hand-offs + scoring)
-- ══════════════════════════════════════════════════════════════
local function Tick()
    if not FA.active or FA.phase == "DONE" then return nil end
    local u = Hero()
    if not u then
        Log("hero gone, stand down"); FA.active = false; FA.phase = "DONE"; MenuRefresh()
        return nil
    end
    local p = u:getPoint()
    local fieldNm = Dist2D(p, GEO and GEO.thr or p)
    local app, lat, dme, locDev, est = 99, 99, 99, 90, false
    if GEO then
        app, lat, dme, locDev = Rel(p)
        est = u:inAir() and Established(u, app, locDev)
        if u:inAir() and not FA.landed then Monitor(u, p, app, lat, dme, locDev, est) end
    end
    local idle = not FA.busy and not FA.qPlaying

    if idle then
        local ph = FA.phase
        if FA.landed then
            if not FA.gndCalled and not u:inAir() and SpeedKt(u) < CFG.TAXI_KT then
                FA.gndCalled = true
                A_TwrToGround()
            end
        elseif ph == "ANK_CI" and fieldNm <= F.handAppNm then
            Log("Ankara skipped (inside the MTMA without check-in)")
            FA.phase = "APP_CI"; MenuRefresh()
        elseif ph == "ANK" and fieldNm <= F.handAppNm then
            A_AnkHandoff()
        elseif ph == "APP" and dme <= F.clrDme then
            A_AppClear()
        elseif (ph == "APP_CLR" or ph == "APP") and ((est and app <= F.twrHandNm)
                or (app <= F.twrHandFallbackNm and app > 0 and lat <= 1.5)) then
            A_AppHandoff()
        elseif ph == "APP_CI" and ((est and app <= F.twrHandNm) or (app <= F.twrHandFallbackNm and app > 0 and lat <= 1.5)) then
            Log("Approach skipped (on final without check-in)")
            FA.phase = "TWR_CI"; MenuRefresh()
        end
    end
    return Now() + CFG.TICK
end

-- ══════════════════════════════════════════════════════════════
--  EVENTS
-- ══════════════════════════════════════════════════════════════
local EH = {}
function EH:onEvent(e)
    if not FA.active or FA.phase == "DONE" then return end
    local u = Hero()
    if not (u and e.initiator and e.initiator == u) then return end
    -- protect the handler: an error here would kill every later event for this module
    local ok, err = pcall(function()
        if e.id == world.event.S_EVENT_LAND and not FA.landed then
            local place = e.place and e.place.getName and e.place:getName()
            local p = u:getPoint()
            local near = GEO and Dist2D(p, GEO.thr) <= 3
            if place == F.airbase or near then
                FA.landed = Now(); SetFlag(CFG.FLAGS.LANDED)
                local lb = FuelLb(u)
                Log(string.format("LAND %s, fuel %.0f lb", tostring(place), lb))
                CheckClearance("touchdown")
                if FA.arc and not FA.arc.done then SettleArc(nil) end
                SettleAlt("landing")
                if lb >= CFG.FUEL_GOOD_LB then
                    Score("FUEL", CFG.PTS.FUEL_GOOD, string.format("landed with %.0f lb", lb))
                elseif lb >= CFG.FUEL_OK_LB then
                    Score("FUEL", CFG.PTS.FUEL_OK, string.format("landed with %.0f lb", lb))
                else
                    Score("FUEL", CFG.PTS.FUEL_LOW, string.format("landed with %.0f lb", lb))
                end
            else
                Log("LAND elsewhere (" .. tostring(place) .. "), stand down")
                FA.active = false; FA.phase = "DONE"; MenuRefresh()
            end
        elseif e.id == world.event.S_EVENT_ENGINE_SHUTDOWN and FA.landed then
            Finish("engine shutdown")
        end
    end)
    if not ok then Log("event error: " .. tostring(err)) end
end
world.addEventHandler(EH)

-- ══════════════════════════════════════════════════════════════
--  API
-- ══════════════════════════════════════════════════════════════
function FA.Supports(key) return CFG.FIELDS[key] ~= nil end

--- Start the arrival chain for field key. opts.minFuel = pilot reports "minimum fuel" to every controller.
function FA.Start(key, opts)
    local f = CFG.FIELDS[key]
    if not f then Log("Start: no data for " .. tostring(key)); return false end
    if FA.active then Log("Start: already active (" .. tostring(FA.field) .. ")"); return true end
    F = f
    CH = {}
    for k, fq in pairs(f.freq) do
        CH[k] = { hz = tonumber(fq) * 1e6, mod = radio.modulation.AM, label = f.label[k], f = Fq(fq) }
    end
    local ok, g = pcall(BuildGeo, f)
    GEO = ok and g or nil
    if not GEO then Log("geometry unavailable: procedure scoring off (" .. tostring(g) .. ")") end
    FA.active, FA.field, FA.phase = true, key, "ANK_CI"
    FA.minFuel = (opts and opts.minFuel) and true or false
    FA.t0 = Now()
    SetFlag(CFG.FLAGS.ACTIVE)
    Log(string.format("START %s%s, scoring %s", key, FA.minFuel and " (minimum fuel)" or "",
        CFG.SCORING and "LIVE" or "shadow"))
    MenuRefresh()
    timer.scheduleFunction(function() local o, r = pcall(Tick); if o then return r end
        Log("tick error: " .. tostring(r)); return Now() + 5 end, nil, Now() + CFG.TICK)
    return true
end

-- ══════════════════════════════════════════════════════════════
--  MENU
-- ══════════════════════════════════════════════════════════════
local function Items()
    if not FA.active or FA.busy or FA.phase == "DONE" then return {} end
    local ph, fq = FA.phase, F.freq
    if FA.landed and ph ~= "GND_CI" then return {} end
    if ph == "ANK_CI" then return { { "ANKARA: check in (" .. Fq(fq.ANKARA) .. ")", A_Ankara } } end
    if ph == "APP_CI" then return { { "APPROACH: check in (" .. Fq(fq.APP) .. ")", A_Approach } } end
    if ph == "TWR_CI" then return { { "TOWER: check in (" .. Fq(fq.TWR) .. ")", A_Tower } } end
    if ph == "GND_CI" then return { { "GROUND: request taxi (" .. Fq(fq.GND) .. ")", A_Ground } } end
    return {}
end

local NEXT = {
    ANK_CI  = function() return string.format("Ankara Control %s (set manually): check in.%s", Fq(F.freq.ANKARA),
                  FA.minFuel and " Say minimum fuel." or "") end,
    ANK     = function() return string.format("Proceed direct DAN (TACAN %s). Ankara hands you to Approach at %d NM.",
                  F.tcn, F.handAppNm) end,
    APP_CI  = function() return string.format("%s Approach %s: check in.", F.name, Fq(F.freq.APP)) end,
    APP     = function() return string.format("Direct OSLUP (R-180 / D15 DAN), %d ft. Clearance for the arc at %d DME.",
                  F.appAlt, F.clrDme) end,
    APP_CLR = function() return string.format("15 DME arc at %d, ILS %s. GOMSE %d ft. Tower comes at ~%d NM.",
                  F.arcAlt, F.ils, F.fafAlt, F.twrHandNm) end,
    TWR_CI  = function() return string.format("%s Tower %s: check in before 1 NM final.", F.name, Fq(F.freq.TWR)) end,
    TWR     = function() return "Cleared to land. Land, slow below 40 kt for the Ground hand-off." end,
    GND_CI  = function() return string.format("%s Ground %s: request taxi.", F.name, Fq(F.freq.GND)) end,
}
local function NextText()
    if not FA.active or FA.phase == "DONE" then return nil end
    local f = NEXT[FA.phase]
    return f and f() or nil
end

local function Card()
    if not FA.active then return nil end
    return { lines = {
        string.format("DIVERT %s: ANKARA %s | APP %s | TWR %s | GND %s", F.key, Fq(F.freq.ANKARA), Fq(F.freq.APP),
            Fq(F.freq.TWR), Fq(F.freq.GND)),
        string.format("TCN %s | ILS %s | OSLUP R-180/D15 %d | ARC %d | GOMSE D8.6 %d | squawk %s",
            F.tcn, F.ils, F.appAlt, F.arcAlt, F.fafAlt, F.squawk),
    } }
end

local function InfoItems()
    if not FA.active and not next(FA.items) then return {} end
    return { { "Show: divert summary", function() Msg(Summary(), 20) end } }
end

if TRT.Menu then
    TRT.Menu.Register("COMMS", "FA", Items, 12)
    TRT.Menu.Register("INFO", "FA", InfoItems, 12)
    TRT.Menu.RegisterNext("FA", NextText)
    TRT.Menu.RegisterCard("FA", Card, 12)
else
    Log("TRT.Menu missing (Menu_Manager not loaded first): no F10 calls")
end

Log(string.format("Field_Arrival v%s online (fields: LTAG; scoring %s)", CFG.VERSION, CFG.SCORING and "LIVE" or "shadow"))
