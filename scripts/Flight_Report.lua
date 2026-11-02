-- Flight_Report | v1.1.1
-- v1.1.1: long-grade glyph names "dash" / "dot" (make_report_cards.py >= v1.4.1); "d" / "m" collided with D / M
--         on case-insensitive file systems.
-- v1.1.0 (Onur 2026-11-02): LSO box shows AIRBOSS's long grade (grade.details, upper-cased, word-wrapped on a
--         LX_ROWS x LX_COLS character grid, lx_<glyph>_<k>.png) under the grade word; badges centred under the
--         card (n badges on half-pitch positions BADGE_SLOTS-n, +2, ...; achievements first, then demerits);
--         "-- (BOLTER)" maps to the BOLTER word. Needs FlightReport/ from make_report_cards.py >= v1.4.0.
--[[
  End-of-flight report card ("karne"), decisions Onur 2026-11-02 (project doc claude/report-card-design-2026-11-02.md):
    * TOTAL, EARNED, PENALTIES, MISSION LOSSES (tanker / AWACS lost: not in the pilot total)
    * 11 groups, earned / penalty each: Launch & departure, Mission timing, AAR, VUL / CAS procedure, Targets,
      Threat avoidance, ROE / friendly fire, Recovery, Trap & deck, Divert, Mission events
    * carrier (CASE I/II trap): AIRBOSS LSO grade, pass points, wire, groove time; Bankler score as is
      ("60/75, 80 %"), never added to the total
    * ROE stamp (Core_Scoring disposition 1..3)
    * overall grade SIERRA HOTEL / SAT / UNSAT from penalties and key outcomes, not from the raw total
    * badges only (no points), up to 8: achievements then demerits, centred under the card
  Shown at the hero's engine shutdown after a landing (carrier or field), at the loss of the aircraft, or from
  F10 > INFO > "FLIGHT REPORT: end sortie". F10 > INFO > "FLIGHT REPORT: score detail" prints the ledger.
  A one-line JSON ("[FR] JSON {...}") goes to dcs.log for tools/flight_report.py (HTML report).

  Card: full-canvas transparent PNG layers in FlightReport/ (tools/score_cards/make_report_cards.py), drawn
  with identical align/size (same mechanics as Score_Display: a_out_picture_s through net.dostring_in).
    frame.png · grade_<SH|SAT|UNSAT>.png · stamp_<1..3>.png · lso_<code>.png · carrier_na.png
    <field>_<glyph>_<slot>.png  glyph 0-9 | p (+) | m (-) | d (.), right-aligned in CFG.FIELDS[field] slots
    lx_<glyph>_<k>.png          LSO long grade, character k of the LX_ROWS x LX_COLS grid
    badge_<ID>_<pos>.png        pos 0..14 (half-pitch, centred)
  Number of layers on screen at once: ~40-90, plus one per long-grade character (up to ~100). Whether DCS draws that many pictures at once without a hitch
  is NOT verified [V]; the text report (F10) and the HTML report carry the same content.

  Reads (all optional, pcall-guarded): TRT.Score (Core_Scoring >= v1.5.1: ledger, incidents, disposition,
  losses, passes, lso), TRT.JC (JTAC_Controller >= v0.9.1), TRT.CD (Comms_Director >= v1.7.12), TRT.MD,
  TRT.AAR, TRT.CV_COMMENCE, TRT.getCurrentCase, Bankler's global PrintFinalScore (wrapped, score kept per pass).
  Load order: after Core_Scoring and Menu_Manager (any order relative to the others).
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.FlightReport then env.info("[FR] already loaded, second copy ignored") return end

local CFG = {
    VERSION   = "1.1.1",
    PLAYER    = TRT.PLAYER_NAME or "Player_01",
    CS        = "HORNET 51",
    DIR       = "FlightReport/",
    LAY       = { dur = 90, h = 1, v = 1, size = 82, units = 1 },   -- centred, 82 % of the window
    PICTURES  = true,
    SHOW_AFTER_LAND_S = 30,   -- the trap score (LSO grade) can take ~20 s after S_EVENT_LAND
    SHOW_DELAY_S      = 5,    -- after the engine shutdown (Deck_Park scores at the shutdown)
    LOST_DELAY_S      = 6,
    FLAG_SCORE        = 1908,
    HARD_DECK_FT      = 20000,
    HARD_DECK_NM      = 15,   -- engagement area: within this range of the active JTAC's targets
    HARD_DECK_BADGE_S = 30,
    TIC_BADGE_S       = 480,  -- TIC call -> first cleared release on that JTAC
    DEF_ACE_N         = 3,
    BANKLER_HI        = 70,   -- badge BANKLER_70 (>= 70 of 75), BANKLER_75 = full 75 / 75
    -- overall grade (penalties = sum of negative ledger entries, mission losses excluded)
    GRADE = { UNSAT_PEN = -50, SH_PEN = -5, SH_LSO_PTS = 4 },
    -- numeric fields: slots (right-aligned), see make_report_cards.py FIELDS (same names / slots)
    FIELDS = { tot = 5, earn = 4, pen = 4, loss = 4, lsopts = 3, wire = 1, tgr = 4, bk = 2, bkmax = 2, bkpct = 3 },
    GROUP_SLOTS = 4,
    BADGE_SLOTS = 8,          -- at most 8 badges; 2 * 8 - 1 half-pitch positions (centring)
    LX_ROWS = 3, LX_COLS = 34,   -- v1.1.0 LSO long-grade grid (make_report_cards.py LX_ROWS / LX_COLS)
}

-- groups: key, label; ledger category -> group (TIME split by the timing item code)
local GROUPS = {
    { key = "LAUNCH",   label = "Launch & departure" },
    { key = "TIMING",   label = "Mission timing" },
    { key = "AAR",      label = "Aerial refuelling" },
    { key = "CAS",      label = "VUL / CAS procedure" },
    { key = "KILL",     label = "Targets" },
    { key = "THREAT",   label = "Threat avoidance" },
    { key = "ROE",      label = "ROE / friendly fire" },
    { key = "RECOVERY", label = "Recovery" },
    { key = "TRAP",     label = "Trap & deck" },
    { key = "DIVERT",   label = "Divert" },
    { key = "MISSION",  label = "Mission events" },
}
local CAT2GROUP = { DEP = "LAUNCH", AAR = "AAR", CAS = "CAS", KILL = "KILL", THREAT = "THREAT", ROE = "ROE",
    RECOVERY = "RECOVERY", TRAP = "TRAP", DIVERT = "DIVERT", MISSION = "MISSION", OTHER = "MISSION", ASSET = "MISSION" }

-- badges: id, label, kind ("A" achievement / "D" demerit); order = priority when more than 8 qualify
local BADGES = {
    { "BLUE_ON_BLUE", "Blue on blue", "D" }, { "COWBOY", "Cowboy (ROE)", "D" },
    { "SPEED_DEMON", "Speed demon", "D" }, { "OFF_CORRIDOR", "Off corridor", "D" },
    { "HARD_DECK", "Below the hard deck", "D" }, { "BOLTER_CLUB", "Bolter club", "D" },
    { "HEAVY", "Heavy at the ramp", "D" }, { "FUMES", "On fumes", "D" },
    { "BANKLER_75", "Bankler 75/75", "A" }, { "BANKLER_70", "Bankler 70+", "A" },
    { "OK_PASS", "OK pass", "A" }, { "THREE_WIRE", "Three-wire", "A" },
    { "CLEAN_ROE", "Clean ROE", "A" }, { "SHACK", "Shack", "A" },
    { "TIC_RESPONSE", "TIC response", "A" }, { "READBACK_ACE", "Readback ace", "A" },
    { "DEFENSIVE_ACE", "Defensive ace", "A" }, { "GHOST", "Ghost", "A" },
    { "FIRST_PLUG", "First plug", "A" }, { "ON_THE_PLAN", "On the plan", "A" },
    { "TIME_HACK", "Time hack", "A" }, { "FUEL_DISCIPLINE", "Fuel discipline", "A" },
    { "PARKING_PRO", "Parking pro", "A" },
}
local GRADE_TXT = { SH = "SIERRA HOTEL", SAT = "SAT", UNSAT = "UNSAT" }
local LSO_CODE = { ["_OK_"] = "OK_U", ["OK"] = "OK", ["(OK)"] = "OKP", ["--"] = "NG", ["CUT"] = "C", ["C"] = "C",
    ["WO"] = "WO", ["WOP"] = "WO", ["OWO"] = "WO", ["WOFD"] = "WO", ["B"] = "B", ["-- (BOLTER)"] = "B",
    ["BOLTER"] = "B" }
-- v1.1.0 long-grade characters -> layer glyph names (make_report_cards.py LX_GLYPHS; J, Q, Z, digits: not drawn)
local LX_GLYPH = { ["A"] = "A", ["B"] = "B", ["C"] = "C", ["D"] = "D", ["E"] = "E", ["F"] = "F", ["G"] = "G", ["H"] = "H", ["I"] = "I", ["K"] = "K", ["L"] = "L", ["M"] = "M",
    ["N"] = "N", ["O"] = "O", ["P"] = "P", ["R"] = "R", ["S"] = "S", ["T"] = "T", ["U"] = "U", ["V"] = "V", ["W"] = "W", ["X"] = "X", ["Y"] = "Y",
    ["("] = "lp", [")"] = "rp", ["_"] = "us", ["/"] = "sl", ["\\"] = "bs", ["-"] = "dash", ["."] = "dot" }   -- v1.1.1: not "d" / "m" (lx_D vs lx_d on Windows)
local DISP_TXT = { [0] = "none", [1] = "Letter of Instruction", [2] = "Letter of Reprimand + FNAEB",
    [3] = "JAGMAN investigation, court-martial possible" }

local FR = { version = CFG.VERSION, CFG = CFG, bankler = {}, hdS = 0, lost = false, ended = false,
    land = nil, birthAbs = nil, rb = { ok = 0, bad = 0 }, ticRelT = nil, shown = 0 }
TRT.FlightReport = FR

local function Log(s) env.info("[FR] " .. s) end
local function Hero() local u = Unit.getByName(CFG.PLAYER); if u and u:isExist() then return u end end
local function SC() return TRT.Score end
local function round(x) return math.floor(x + 0.5) end

-- ══════════════════════════════════════════════════════════════
--  COLLECTORS
-- ══════════════════════════════════════════════════════════════
-- Bankler: wrap the global PrintFinalScore once it exists (TrapTraining loads late)
local function HookBankler()
    if FR.bkHooked then return true end
    local orig = _G.PrintFinalScore
    if type(orig) ~= "function" then return false end
    _G.PrintFinalScore = function(pd, duration, wire, ...)
        pcall(function()
            local u = pd and pd.unit
            local n = u and (u.UnitName or (u.GetName and u:GetName()))
            if n == CFG.PLAYER then
                FR.bankler[#FR.bankler + 1] = { score = tonumber(pd.score) or 0, max = tonumber(_G.maxScore) or 75,
                    wire = tonumber(wire), longDW = pd.longDownwind and true or false, settled = pd.didSettle and true or false }
                Log(string.format("Bankler pass %d: %s / %s (wire %s)", #FR.bankler, tostring(pd.score),
                    tostring(_G.maxScore), tostring(wire)))
            end
        end)
        return orig(pd, duration, wire, ...)
    end
    FR.bkHooked = true
    Log("Bankler PrintFinalScore hooked")
    return true
end

local function HookJC()
    if FR.jcHooked then return true end
    local jc = TRT.JC
    if not (jc and type(jc.on) == "function") then return false end
    jc.on(function(ev, data)
        if type(data) ~= "table" then return end
        if ev == "READBACK" then
            if data.wrong == 0 and data.try == 1 then FR.rb.ok = FR.rb.ok + 1 else FR.rb.bad = FR.rb.bad + 1 end
        elseif ev == "RELEASE" and data.cleared and not FR.ticRelT then
            local cd = TRT.CD
            if cd and cd.tic and data.key == cd.tic then FR.ticRelT = timer.getTime() end
        end
    end)
    FR.jcHooked = true
    Log("JTAC_Controller events subscribed")
    return true
end

-- hard deck: seconds below CFG.HARD_DECK_FT within CFG.HARD_DECK_NM of the active JTAC's targets
local function HardDeckTick()
    local u, cd, jc = Hero(), TRT.CD, TRT.JC
    if not (u and cd and jc and jc.st and u:inAir()) then return end
    local k = (cd.phase == "JTAC1" and "J1") or (cd.phase == "JTAC2" and "J2")
    local st = k and jc.st[k]
    if not (st and st.units and st.units[1] and st.units[1].pos) then return end
    local p, t = u:getPoint(), st.units[1].pos
    local nm = math.sqrt((p.x - t.x) ^ 2 + (p.z - t.z) ^ 2) / 1852
    if nm <= CFG.HARD_DECK_NM and p.y * 3.28084 < CFG.HARD_DECK_FT then FR.hdS = FR.hdS + 1 end
end

-- ══════════════════════════════════════════════════════════════
--  COMPUTE
-- ══════════════════════════════════════════════════════════════
local function GroupOf(e)
    if e.cat == "TIME" then
        return (e.reason:find("^TIMING M[12]") or e.reason:find("^TIMING T1")) and "LAUNCH" or "TIMING"
    end
    return CAT2GROUP[e.cat] or "MISSION"
end

local function Find(pattern, sign)
    local sc = SC()
    for _, e in ipairs((sc and sc.ledger) or {}) do
        if e.reason:find(pattern) and (not sign or (sign > 0 and e.d > 0) or (sign < 0 and e.d < 0)) then return e end
    end
end

local function JcTasks()
    local jc = TRT.JC
    if not (jc and jc.CFG and jc.CFG.ORDER and jc.st) then return nil, nil end
    local done = 0
    for _, k in ipairs(jc.CFG.ORDER) do if jc.st[k] and jc.st[k].phase == "DONE" then done = done + 1 end end
    return done, #jc.CFG.ORDER
end

function FR.compute()
    local sc = SC() or { ledger = {}, incidents = {}, losses = {}, passes = {} }
    local R = { groups = {}, earned = 0, pen = 0, badges = {}, notes = {} }
    for _, g in ipairs(GROUPS) do R.groups[g.key] = { e = 0, p = 0, label = g.label } end
    for _, e in ipairs(sc.ledger or {}) do
        local g = R.groups[GroupOf(e)]
        if e.d > 0 then g.e = g.e + e.d; R.earned = R.earned + e.d else g.p = g.p + e.d; R.pen = R.pen + e.d end
    end
    R.total = tonumber(trigger.misc.getUserFlag(CFG.FLAG_SCORE)) or (R.earned + R.pen)
    R.loss, R.lossNames = 0, {}
    for _, l in ipairs(sc.losses or {}) do R.loss = R.loss + (l.value or 0); R.lossNames[#R.lossNames + 1] = l.name end
    -- carrier
    R.case = TRT.getCurrentCase and TRT.getCurrentCase() or nil
    R.landing = FR.land and FR.land.kind or nil
    R.lso = sc.lso or ((sc.passes and #sc.passes > 0) and sc.passes[#sc.passes]) or nil
    local bk
    for i = #FR.bankler, 1, -1 do if (FR.bankler[i].wire or 0) > 0 then bk = FR.bankler[i]; break end end
    bk = bk or FR.bankler[#FR.bankler]
    R.bankler = bk
    -- ROE
    R.disp = sc.disposition
    if R.disp == nil then
        local w, n = 0, 0
        for _, i in ipairs(sc.incidents or {}) do w = math.max(w, i.sev or 1); if (i.sev or 1) >= 1 then n = n + 1 end end
        if w == 1 and n >= 2 then w = 2 end
        R.disp = w
    end
    R.tasksDone, R.tasksTotal = JcTasks()
    -- badges
    local has = {}
    local kinds = {}
    for _, i in ipairs(sc.incidents or {}) do kinds[i.kind] = true end
    local md, aar, jc, cd = TRT.MD, TRT.AAR, TRT.JC, TRT.CD
    has.BLUE_ON_BLUE = kinds.FF_HIT or kinds.FF_KILL
    has.COWBOY = kinds.UNAUTH or kinds.AFTER_ABORT or kinds.TERMINATED
    has.SPEED_DEMON = Find("^MARSHAL ZONE SPEED", -1) ~= nil
    has.OFF_CORRIDOR = cd and cd.corridorMz
    has.HARD_DECK = FR.hdS >= CFG.HARD_DECK_BADGE_S
    for _, p in ipairs(sc.passes or {}) do if not p.landed then has.BOLTER_CLUB = true end end
    has.HEAVY = Find("^Groove fuel: .*max trap", -1) ~= nil
    has.FUMES = not has.HEAVY and (Find("^Groove fuel: .*below", -1) ~= nil or Find("^Groove fuel: .*critical", -1) ~= nil)
    if bk and bk.max == 75 then
        if bk.score >= 75 then has.BANKLER_75 = true elseif bk.score >= CFG.BANKLER_HI then has.BANKLER_70 = true end
    end
    if R.lso and R.lso.landed ~= false and (R.lso.grade == "_OK_" or R.lso.grade == "OK") then has.OK_PASS = true end
    if R.lso and R.lso.wire == 3 then has.THREE_WIRE = true end
    local rbErr = Find("^READBACK", -1) ~= nil
    local anyBreach = false
    for _, i in ipairs(sc.incidents or {}) do if (i.sev or 1) >= 1 then anyBreach = true end end
    has.CLEAN_ROE = (R.tasksDone or 0) > 0 and not anyBreach and not rbErr
    has.SHACK = R.tasksTotal and R.tasksTotal > 0 and R.tasksDone == R.tasksTotal and jc and jc.stats and jc.stats.miss == 0
    has.READBACK_ACE = FR.rb.ok > 0 and FR.rb.bad == 0
    if cd and cd.ticState and cd.ticState.callT and FR.ticRelT then
        R.ticS = FR.ticRelT - cd.ticState.callT
        has.TIC_RESPONSE = R.ticS <= CFG.TIC_BADGE_S
    end
    has.DEFENSIVE_ACE = md and (md.defeated or 0) >= CFG.DEF_ACE_N
    has.GHOST = md and (md.n or 0) == 0 and (R.tasksDone or 0) > 0
    if aar and aar.sessions then
        local n, ok = 0, true
        for _, s in ipairs(aar.sessions) do
            if (s.contacts or 0) > 0 then
                n = n + 1
                local closOk = false
                for _, p in ipairs(s.points or {}) do if p.code == "CONTACT_CLOS" and p.pts > 0 then closOk = true end end
                if s.contacts ~= 1 or not closOk then ok = false end
            end
        end
        has.FIRST_PLUG = n > 0 and ok
    end
    do
        local pos, neg = 0, 0
        for _, e in ipairs(sc.ledger or {}) do
            if e.cat == "TIME" then if e.d > 0 then pos = pos + 1 elseif e.d < 0 then neg = neg + 1 end end
        end
        has.ON_THE_PLAN = pos >= 2 and neg == 0
    end
    local cm = TRT.CV_COMMENCE
    has.TIME_HACK = cm and cm.dt and math.abs(cm.dt) <= 5
    has.FUEL_DISCIPLINE = Find("^Groove fuel", 1) ~= nil
    has.PARKING_PRO = Find("^Deck park", 1) ~= nil
    local nA, nD = 0, 0
    for _, b in ipairs(BADGES) do
        if has[b[1]] then
            if #R.badges < CFG.BADGE_SLOTS then
                R.badges[#R.badges + 1] = { id = b[1], label = b[2], kind = b[3] }
                if b[3] == "A" then nA = nA + 1 else nD = nD + 1 end
            end
        end
    end
    R.nDemerit = nD
    -- overall grade
    local g = "SAT"
    if FR.lost or R.disp >= 2 or R.pen <= CFG.GRADE.UNSAT_PEN or (R.tasksTotal and R.tasksDone == 0) then
        g = "UNSAT"
    elseif R.disp == 0 and nD == 0 and R.pen >= CFG.GRADE.SH_PEN
        and (not R.tasksTotal or R.tasksDone == R.tasksTotal)
        and ((R.landing == "carrier" and R.lso and (R.lso.points or 0) >= CFG.GRADE.SH_LSO_PTS)
             or (R.landing == "field" and R.groups.DIVERT.p == 0)) then
        g = "SH"
    end
    R.grade = g
    return R
end

-- ══════════════════════════════════════════════════════════════
--  OUTPUT: text, JSON, pictures
-- ══════════════════════════════════════════════════════════════
local function sgn(v) v = round(v); return (v > 0) and ("+" .. v) or tostring(v) end

local function TextReport(R)
    local L = {}
    L[#L + 1] = string.format("FLIGHT REPORT - %s (%s)        GRADE: %s", CFG.CS, CFG.PLAYER, GRADE_TXT[R.grade])
    L[#L + 1] = string.format("TOTAL %d    earned %s    penalties %s    mission losses %s", round(R.total), sgn(R.earned),
        sgn(R.pen), (#R.lossNames > 0) and (sgn(R.loss) .. " (" .. table.concat(R.lossNames, ", ") .. ")") or "none")
    for _, g in ipairs(GROUPS) do
        local x = R.groups[g.key]
        if x.e ~= 0 or x.p ~= 0 then L[#L + 1] = string.format("  %-22s %4s / %4s", g.label, sgn(x.e), sgn(x.p)) end
    end
    if R.lso then
        L[#L + 1] = string.format("CARRIER: LSO %s (%s PT)%s%s%s", R.lso.grade, tostring(R.lso.points),
            R.lso.wire and string.format(", %d-wire", R.lso.wire) or "",
            R.lso.tgroove and string.format(", groove %.1f s", R.lso.tgroove) or "",
            (R.lso.details and R.lso.details ~= "") and ("\n  " .. R.lso.details) or "")
    end
    if R.bankler then
        L[#L + 1] = string.format("BANKLER (not in the total): %d / %d (%d %%)", R.bankler.score, R.bankler.max,
            round(100 * R.bankler.score / math.max(1, R.bankler.max)))
    end
    L[#L + 1] = "ROE: " .. DISP_TXT[R.disp or 0]
    local b = {}
    for _, x in ipairs(R.badges) do b[#b + 1] = (x.kind == "D" and "[-] " or "[+] ") .. x.label end
    L[#L + 1] = "BADGES: " .. ((#b > 0) and table.concat(b, ", ") or "none")
    if FR.hdS > 0 then L[#L + 1] = string.format("Hard deck: %d s below %d ft in the engagement area (not scored)", FR.hdS, CFG.HARD_DECK_FT) end
    return table.concat(L, "\n")
end

local function J(v)   -- minimal JSON encoder (strings, numbers, booleans, arrays, objects)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return (math.floor(v) == v) and string.format("%d", v) or string.format("%.3f", v)
    end
    if t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" end
            return string.format("\\u%04x", c:byte())
        end) .. '"'
    end
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local o = {}
            for i = 1, #v do o[i] = J(v[i]) end
            return "[" .. table.concat(o, ",") .. "]"
        end
        local o = {}
        for k, x in pairs(v) do if type(k) == "string" then o[#o + 1] = J(k) .. ":" .. J(x) end end
        table.sort(o)
        return "{" .. table.concat(o, ",") .. "}"
    end
    return "null"
end

local function Json(R)
    local sc = SC() or {}
    local grp = {}
    for _, g in ipairs(GROUPS) do grp[#grp + 1] = { key = g.key, label = g.label, e = R.groups[g.key].e, p = R.groups[g.key].p } end
    local badges = {}
    for _, b in ipairs(R.badges) do badges[#badges + 1] = { id = b.id, label = b.label, kind = b.kind } end
    return J({
        version = CFG.VERSION, cs = CFG.CS, player = CFG.PLAYER, grade = GRADE_TXT[R.grade],
        total = R.total, earned = R.earned, penalties = R.pen, loss = R.loss, losses = sc.losses or {},
        groups = grp, case = R.case, landing = R.landing, lso = R.lso, passes = sc.passes or {},
        bankler = R.bankler, bankler_passes = FR.bankler, disposition = R.disp, incidents = sc.incidents or {},
        badges = badges, ledger = sc.ledger or {}, hard_deck_s = FR.hdS, tic_s = R.ticS,
        tasks_done = R.tasksDone, tasks_total = R.tasksTotal, lost = FR.lost,
        birth_abs = FR.birthAbs, end_abs = timer.getAbsTime(),
        mission_date = env.mission and env.mission.date or nil,
    })
end

local canPic = (net ~= nil) and (type(net.dostring_in) == "function")
local function Pic(file, clear)
    if not (CFG.PICTURES and canPic) then return false end
    local L = CFG.LAY
    local code = string.format('a_out_picture_s(%q, %q, %d, %s, 0, "%d", "%d", %d, "%d")',
        "blue", CFG.DIR .. file, L.dur, clear and "true" or "false", L.h, L.v, L.size, L.units)
    local ok, res, okd = pcall(net.dostring_in, "mission", code)
    if not ok or okd == false then Log("picture failed: " .. tostring(res) .. " | " .. code); return false end
    return true
end

--- right-aligned value string into a field's slots: "p"/"m" sign, "d" dot
local function Field(files, field, str, slots)
    slots = slots or CFG.FIELDS[field]
    if #str > slots then str = str:sub(#str - slots + 1) end
    local off = slots - #str
    for i = 1, #str do
        local ch = str:sub(i, i)
        local g = (ch == "+" and "p") or (ch == "-" and "m") or (ch == "." and "d") or ch
        files[#files + 1] = string.format("%s_%s_%d.png", field, g, off + i - 1)
    end
end

--- v1.1.0 long grade -> lx_ layers: word wrap on spaces, tokens longer than a row are split, extra rows dropped
local function LxFiles(files, text)
    local rows, cur = {}, ""
    for word in tostring(text or ""):upper():gmatch("%S+") do
        local tok = word
        while #tok > CFG.LX_COLS do
            if cur ~= "" then rows[#rows + 1] = cur; cur = "" end
            rows[#rows + 1] = tok:sub(1, CFG.LX_COLS); tok = tok:sub(CFG.LX_COLS + 1)
        end
        if cur == "" then cur = tok
        elseif #cur + 1 + #tok <= CFG.LX_COLS then cur = cur .. " " .. tok
        else rows[#rows + 1] = cur; cur = tok end
    end
    if cur ~= "" then rows[#rows + 1] = cur end
    for r = 1, math.min(#rows, CFG.LX_ROWS) do
        for c = 1, #rows[r] do
            local g = LX_GLYPH[rows[r]:sub(c, c)]
            if g then files[#files + 1] = string.format("lx_%s_%d.png", g, (r - 1) * CFG.LX_COLS + c - 1) end
        end
    end
end

local function Card(R)
    local files = {}
    files[#files + 1] = "grade_" .. R.grade .. ".png"
    Field(files, "tot", tostring(math.max(-9999, math.min(99999, round(R.total)))))
    Field(files, "earn", (round(R.earned) > 0) and ("+" .. math.min(999, round(R.earned))) or "0")
    Field(files, "pen", (round(R.pen) < 0) and tostring(math.max(-999, round(R.pen))) or "0")
    Field(files, "loss", (round(R.loss) < 0) and tostring(math.max(-999, round(R.loss))) or "0")
    for i, g in ipairs(GROUPS) do
        local x = R.groups[g.key]
        Field(files, "g" .. i .. "e", (x.e > 0) and ("+" .. math.min(999, round(x.e))) or "0", CFG.GROUP_SLOTS)
        Field(files, "g" .. i .. "p", (x.p < 0) and tostring(math.max(-999, round(x.p))) or "0", CFG.GROUP_SLOTS)
    end
    if R.lso and R.landing ~= "field" then
        files[#files + 1] = "lso_" .. (LSO_CODE[R.lso.grade] or "NONE") .. ".png"
        if R.lso.details and R.lso.details ~= "" then LxFiles(files, R.lso.details) end   -- v1.1.0
        if R.lso.points then Field(files, "lsopts", string.format("%.1f", R.lso.points)) end
        if R.lso.wire and R.lso.wire >= 1 and R.lso.wire <= 4 then Field(files, "wire", tostring(R.lso.wire)) end
        if R.lso.tgroove then Field(files, "tgr", string.format("%.1f", math.min(99.9, R.lso.tgroove))) end
    else
        files[#files + 1] = (R.landing == "field") and "lso_DIV.png" or "carrier_na.png"
    end
    if R.bankler then
        Field(files, "bk", tostring(math.max(0, math.min(99, R.bankler.score))))
        Field(files, "bkmax", tostring(math.min(99, R.bankler.max)))
        Field(files, "bkpct", tostring(math.max(0, math.min(100, round(100 * R.bankler.score / math.max(1, R.bankler.max))))))
    end
    if (R.disp or 0) >= 1 then files[#files + 1] = "stamp_" .. math.min(3, R.disp) .. ".png" end
    -- v1.1.0 badges centred under the card: achievements first, then demerits, on half-pitch positions
    local list = {}
    for _, b in ipairs(R.badges) do if b.kind == "A" then list[#list + 1] = b end end
    for _, b in ipairs(R.badges) do if b.kind ~= "A" then list[#list + 1] = b end end
    local n = math.min(#list, CFG.BADGE_SLOTS)
    for i = 1, n do
        files[#files + 1] = string.format("badge_%s_%d.png", list[i].id, CFG.BADGE_SLOTS - n + 2 * (i - 1))
    end
    Pic("frame.png", true)
    for _, f in ipairs(files) do Pic(f, false) end
    return #files + 1
end

function FR.show(why)
    local ok, R = pcall(FR.compute)
    if not ok then Log("compute error: " .. tostring(R)); return end
    FR.ended, FR.shown = true, FR.shown + 1
    local txt = TextReport(R)
    trigger.action.outTextForCoalition(coalition.side.BLUE, txt, CFG.LAY.dur, false)
    Log("REPORT (" .. tostring(why) .. ")\n" .. txt)
    local okJ, js = pcall(Json, R)
    if okJ then env.info("[FR] JSON " .. js) else Log("json error: " .. tostring(js)) end
    local okC, n = pcall(Card, R)
    Log(okC and string.format("card: %d layers", n) or ("card error: " .. tostring(n)))
    pcall(trigger.action.outSoundForCoalition, coalition.side.BLUE, "Sounds/SCORE/mission_end.ogg")
end

function FR.detail()
    local sc = SC()
    local L = { "SCORE DETAIL (ledger)" }
    for _, e in ipairs((sc and sc.ledger) or {}) do
        local t = math.floor(e.t) % 86400
        L[#L + 1] = string.format("%02d:%02d  %4s  %-8s %s", math.floor(t / 3600), math.floor((t % 3600) / 60), sgn(e.d), e.cat, e.reason)
    end
    if #L == 1 then L[#L + 1] = "(no score changes yet)" end
    trigger.action.outTextForCoalition(coalition.side.BLUE, table.concat(L, "\n"), 60, false)
end

-- ══════════════════════════════════════════════════════════════
--  EVENTS / TICK / MENU
-- ══════════════════════════════════════════════════════════════
local EV = world.event
local LOST = { [EV.S_EVENT_CRASH] = true, [EV.S_EVENT_EJECTION] = true, [EV.S_EVENT_PILOT_DEAD] = true,
               [EV.S_EVENT_DEAD] = true }
local H = {}
function H:onEvent(e)
    if not e or not e.initiator then return end
    local ok, n = pcall(function() return e.initiator:getName() end)
    if not ok or n ~= CFG.PLAYER then return end
    if e.id == EV.S_EVENT_BIRTH then
        FR.birthAbs = FR.birthAbs or timer.getAbsTime()
    elseif e.id == EV.S_EVENT_LAND then
        local kind = "field"
        pcall(function()
            local c = Unit.getByName("CVN")
            if c and c:isExist() then
                local a, b = e.initiator:getPoint(), c:getPoint()
                if math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) / 1852 <= 0.3 then kind = "carrier" end
            end
        end)
        FR.land = { kind = kind, t = timer.getTime() }
        Log("landing: " .. kind)
    elseif e.id == EV.S_EVENT_ENGINE_SHUTDOWN and FR.land and not FR.ended then
        local wait = math.max(CFG.SHOW_DELAY_S, CFG.SHOW_AFTER_LAND_S - (timer.getTime() - FR.land.t))
        Log(string.format("engine shutdown after a %s landing -> report in %.0f s", FR.land.kind, wait))
        timer.scheduleFunction(function() FR.show("engine shutdown") end, nil, timer.getTime() + wait)
    elseif LOST[e.id] and not FR.lost and not FR.ended then
        local air = true
        pcall(function() air = e.initiator:inAir() end)
        if e.id ~= EV.S_EVENT_DEAD or air then
            FR.lost = true
            Log("aircraft lost (event " .. tostring(e.id) .. ")")
            timer.scheduleFunction(function() if not FR.ended then FR.show("aircraft lost") end end, nil,
                timer.getTime() + CFG.LOST_DELAY_S)
        end
    end
end
world.addEventHandler(H)

timer.scheduleFunction(function(_, t)
    pcall(HookBankler); pcall(HookJC); pcall(HardDeckTick)
    return t + 1
end, nil, timer.getTime() + 2)

local function InfoItems()
    return {
        { "FLIGHT REPORT: end sortie (show report)", function() FR.show("F10") end },
        { "FLIGHT REPORT: score detail", function() FR.detail() end },
    }
end
if TRT.Menu and TRT.Menu.Register then
    TRT.Menu.Register("INFO", "FR", InfoItems, 30)
else
    Log("TRT.Menu missing (Menu_Manager.lua must load first) -> no F10 items")
end

Log(string.format("Flight_Report v%s loaded (hero %s, pictures %s)", CFG.VERSION, CFG.PLAYER,
    (CFG.PICTURES and canPic) and "ON" or "OFF"))
