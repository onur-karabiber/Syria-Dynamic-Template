-- Core_Scoring | v1.5.2
-- v1.5.2 (effects-based tasking, 2026-11-04): JTAC_Controller >= v0.15.0 gives the objective bonus itself
--         (JC.objectiveBonus) -> its target groups are no longer merged into the group-destroyed bonus (no double +5).
-- v1.5.1 (report card decisions, Onur 2026-11-02):
--   * Friendly asset lost (tanker / AWACS, any cause) is a MISSION LOSS, not a pilot penalty: recorded in
--     TRT.Score.losses { t, name, value } (value = the old -8 / -10), text + log, flag 1908 untouched.
--   * The hero's AIRBOSS LSO grades are kept in TRT.Score.passes { t, grade, points, wire, tgroove, details }
--     (every graded pass, bolters / wave-offs included); TRT.Score.lso = the trap's grade.
--   * Carrier landing points only for the hero: the old TARGET_UNITS AI names (LANDER-8-1, ...) added +5 to the
--     hero's total when they landed. Land-based +2 likewise hero only.
--   * The dead "Bankler score merged" path is removed (decision: Bankler shown as is, not in the total;
--     Flight_Report captures it).
-- v1.5.0 (scoring review 2026-11-02, decisions Onur; project doc claude/scoring-review-2026-11-02.md):
--   * Score ledger: every TRT.addScore(delta, reason[, cat]) is kept in TRT.Score.ledger
--     { t, d, reason, cat } (cat inferred from the reason when not given: DEP AAR TIME CAS KILL THREAT ROE
--     ASSET RECOVERY TRAP DIVERT MISSION OTHER) for the end-of-flight report card. TRT.Score.sum(cat).
--   * Flag 1908 changed outside TRT.addScore (ME triggers, e.g. template "DEAD SCORE-1/-2" a_inc_flag +15)
--     is detected within 1 s and re-booked through TRT.addScore ("MISSION EVENT", log + card + ledger).
--   * Friendly fire: the hero's S_EVENT_KILL on a unit / static of his own coalition FF_KILL (-50), the
--     first S_EVENT_HIT on each such object FF_HIT (-20). Every one is an incident (TRT.Score.incident).
--   * Incident registry TRT.Score.incidents (JTAC_Controller >= v0.9.0 reports into it) and a ROE / FRIENDLY
--     FIRE REPORT REPORT_S after the hero's landing is confirmed, with the disposition of the worst incident:
--     1 counseling / Letter of Instruction, 2 Letter of Reprimand + FNAEB, 3 JAGMAN investigation, court-martial.
--   * Groove fuel follows the recovery fuel plan (Flight_Timeline thresholds RECOVERY: BINGO, max trap) and is
--     graded in the groove only (AIRBOSS step "Groove*"; geometric fallback without AIRBOSS), once per sortie
--     (reset at the landing, not at a bolter's takeoff): > max trap +1,000 -5 / > max trap +300 -2 /
--     BINGO-300 .. max trap+300 +3 / >= 2,000 -2 / >= 1,500 -5 / less -8.
--   * Carrier landing without an AIRBOSS grade: +2 (= "--", No Grade) instead of +5.
--   * Name-prefix kill matching: longest prefix first (was pairs() order).
-- v1.4.7 (Onur, 2026-11-02): the hero's carrier landing score follows the AIRBOSS LSO grade of the trap pass
--   instead of a flat +5: _OK_ +5, OK +4, (OK) +3, -- +2, CUT 0 (AIRBOSS's own pass points, rounded, 0..5).
--   2026-11-02 sortie: "--" (no grade, 2.0 PT) still earned +5. The grade comes from AIRBOSS OnAfterLSOGrade
--   (hooked here, chained; Pilot_Banter chains after it), ~6 s after S_EVENT_LAND; the award waits up to
--   GRADE_WAIT_S after the LAND_CONFIRM_S check. No grade by then -> flat +5 as before (logged). AI / other
--   TARGET_UNITS keep the flat +5; land-based landings keep +2.
-- v1.4.6 (CAS (L) sortie 2026-11-02, Onur):
--   * No kill points for a weapon released without clearance / after an abort. 2026-11-02: the GBU-12
--     released without CLEARED HOT (-15 ROE) still earned +10 +2 for its kills (net -3). The kill handler
--     now asks JTAC_Controller (TRT.JC.unauthKill(weapon, victim), >= v0.8.1) and logs
--     "kill NOT scored (unauthorized release)" instead; no JTAC group bonus from such a kill either.
--   * JTAC group bonus also for the JTAC_Controller target groups (TRT.JC.CFG.JTACS[*].targets). The ME
--     FAC_AttackGroup scan only found the native JTAC targets (BASE YE55, BV53) while the scripted JTACs
--     worked BV51 / YE53, so no +5 fired. Merged 2 s after load and again at the first kill.
-- v1.4.5: landing score is confirmed LAND_CONFIRM_S (8 s) after S_EVENT_LAND. 2026-10-31: the hero hit an
-- SH-60B parked on the CVN landing area; S_EVENT_LAND fired at touchdown and +5 "Successful carrier landing" was
-- awarded for the crash (Deck_Park saw the loss 2 s later). Now S_EVENT_CRASH / DEAD / EJECTION / PILOT_DEAD /
-- UNIT_LOST inside the window, or a unit that no longer exists / has life < 1, cancels the award (logged
-- "landing NOT scored"). Land-based landings use the same check.
-- v1.4.4: the player's TRT.onRefuelComplete call is skipped when AAR_Monitor owns it
-- (TRT.AAR.callsRefuelComplete, AAR_Monitor >= v1.1.0 live). Without the Monitor (or in its shadow mode) it fires as before.
-- v1.4.3: player aerial refuel score disabled (PLAYER_REFUEL_SCORE = false). AAR test flights
-- 2026-10-30 (TEST-AAR / TEST-AAR-S): the +7 fired when getFuel() rose by 0.2 of the internal
-- capacity (~2,160 lb), i.e. about a third of a 6,500-6,900 lb onload, while the transfer was
-- still running. AAR_Monitor.lua (scores on disconnect + onload) replaces it. The zone/0.2 detector
-- still runs and still calls TRT.onRefuelComplete (unchanged behaviour for CD/TL); only the points
-- are gone, and a "[Core_Scoring] player refuel detected (no score)" line is logged instead.
-- v1.4.2: JTAC group bonus never fired (CAS-1 test 2026-10-28 night: BV51 and YE53 both
-- wiped out by the hero, no "+5 JTAC TARGET GROUP DESTROYED"): victim:getGroup() on the
-- unit of an S_EVENT_KILL returns nothing, so the group name was never found. The JTAC
-- target groups' unit names are now mapped to their group from the ME data at load.
-- Also the "DEAD without a matching KILL" debug line was false: S_EVENT_DEAD arrives
-- ~1 s AFTER the KILL, so a unit already scored by a KILL is no longer reported.
-- v1.4.1: every TRT.addScore is logged ("[Core_Scoring] SCORE +d (total) reason") - the
-- 2026-10-28 evening flight could not be audited (two +6 cards for the BV51 group, no +5
-- group bonus, and the debug line said both units died without a matching KILL).
-- v1.4.0: kill scoring rebalanced (CAS-1 test 2026-10-28: every ground unit
-- scored 1, so an SA-13 TEL = a truck). TYPE_SCORES now covers every RED
-- type in CAS (L) and the template, tiered: SAM radars / CP 10-12,
-- self-contained SAM 10-12, launchers 5-8, AAA 3-6, MANPADS 3, tanks 3-6,
-- IFV/APC 2-4, artillery 3-6, trucks 2, infantry 1, aircraft 4-15.
-- Unlisted ground type: 2 (was 1). New: JTAC_GROUP_BONUS when the hero's
-- kill leaves a JTAC target group (ME FAC_AttackGroup task) with no unit alive.
-- v1.3.2: AI refuels no longer score. Only a unit with a human player
-- (getPlayerName) earns the +7; AI refuels are logged and still call
-- TRT.onRefuelComplete. (CAS-1 test 2026-10-28: 4 CAP refuels = +28 to
-- the hero's score.)
-- TRT Syria Recovery Framework - CASE-independent scoring core.
-- Consolidates: dead-target scoring, refuel scoring (player+AI),
-- landing scoring, groove fuel scoring, Bankler/TrapTrainer merge,
-- and (as of v1.1.0) the active-case getter (TRT.getCurrentCase).
-- Loaded ONCE regardless of active recovery case. Creates the shared
-- _G.TRT namespace used by Recovery_Approach.lua and Departure.lua.
--
-- v1.1.0: CaseDeterminator.lua (weather-based auto-detection) is
-- retired. Case is now a manual mission flag (100), set from a Mission
-- Editor trigger - see the ACTIVE CASE section below. Do not load
-- CaseDeterminator.lua anymore.
--
-- v1.2.1: added TRT.flagTrue(id) - shared helper for scripts that gate
-- on a manually-set ME flag (same doctrine as flag 100: no automatic
-- inference, full authorship in the Mission Editor). First consumer is
-- Recovery_Approach.lua's commence-recovery gate; Hard Deck logic will
-- likely want the same helper when it's written.
--
-- v1.3.0: dead-target scoring reworked. The old DEAD_SCORES table
-- conflated two different mechanics; they are now split:
--   1) ENEMY KILL SCORING (new) - S_EVENT_KILL, gated on
--      initiator == PLAYER_NAME. Resolves a point value through a
--      priority chain: exact unit name -> name prefix (handles DCS's
--      auto " #001" suffix on duplicate names) -> unit type name ->
--      group category -> flat default. Every RED-coalition kill
--      scores now, not just names present in a curated table.
--   2) FRIENDLY ASSET LOSS PENALTY (was: the negative entries in the
--      old DEAD_SCORES table) - still S_EVENT_DEAD, still
--      unattributed, because a lost tanker/AWACS is bad regardless of
--      who or what killed it.
-- DEAD_SCORES is retired; entries split between UNIT_NAME_OVERRIDES
-- and FRIENDLY_LOSS_PENALTIES below. S_EVENT_KILL's reliability on
-- StaticObject targets is UNVERIFIED for this project - see the
-- DEBUG_LOG_UNATTRIBUTED_DEATHS note in that section before trusting
-- static HVT scoring (e.g. the factory case) blind.
--
-- v1.3.1: hero unit name is no longer hardcoded. PLAYER_NAME comes from
-- _G.TRT.PLAYER_NAME (default "Player_01") and is published back to the
-- same field so later modules agree. To use another slot in a given .miz,
-- run this one-liner in a Do Script trigger BEFORE any script is loaded:
--   _G.TRT = _G.TRT or {}; _G.TRT.PLAYER_NAME = "Player_03"
-- The hero's landing TARGET_UNITS entry follows PLAYER_NAME.
--
-- Load order requirement: load AFTER mist, BEFORE Recovery_Approach.lua
-- and Departure.lua.

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
_G.TRT = _G.TRT or {}
local PLAYER_NAME = _G.TRT.PLAYER_NAME or "Player_01"
_G.TRT.PLAYER_NAME = PLAYER_NAME
local CARRIER     = "CVN"
local FLAG_SCORE  = 1908

local TRAP_RADIUS_NM = 0.15
-- Source files used 0.05 (CASE-I) and 0.15 (CASE-II/III) inconsistently.
-- Standardized to the majority value. Change here if 0.05 was the
-- intended tuning - it's a single constant now, not a per-file guess.

----------------------------------------------------------------
-- NAMESPACE
-- Everything cross-module now lives under one _G.TRT table instead of
-- scattered globals (_G.TRT_UpdateGrooveFuel, _G.TRT_UpdateHardDeck, ...).
-- That scatter is what let CASE-II silently overwrite functions CASE-III
-- had already defined if both ever got loaded in the same session.
----------------------------------------------------------------
_G.TRT = _G.TRT or {}
local TRT = _G.TRT

----------------------------------------------------------------
-- SCORE
----------------------------------------------------------------
-- v1.5.0: ledger + categories (end-of-flight report card)
TRT.Score = TRT.Score or { ledger = {}, incidents = {}, expected = nil, losses = {}, passes = {} }
local SC = TRT.Score
local CAT_RULES = {   -- first match wins (reason, case-sensitive Lua patterns)
    { "^MISSION EVENT", "MISSION" }, { "^FRIENDLY FIRE", "ROE" }, { "^ROE", "ROE" },
    { "^READBACK", "CAS" }, { "^TARGET DESTROYED", "KILL" }, { "^JTAC TARGET GROUP", "KILL" },
    { "^MISSILE DEFEATED", "THREAT" }, { "^ASSET LOST", "ASSET" }, { "^Aerial Refuel", "AAR" },
    { "^TIMING", "TIME" }, { "^Departure", "DEP" }, { "^Divert", "DIVERT" },
    { "land%-based", "DIVERT" }, { "^Carrier landing", "TRAP" }, { "^Successful carrier", "TRAP" },
    { "^Groove fuel", "TRAP" }, { "^Deck park", "TRAP" }, { "^MARSHAL ZONE", "RECOVERY" },
    { "^Established", "RECOVERY" }, { "^Commenced", "RECOVERY" }, { "^No established", "RECOVERY" },
    { "^No commencing", "RECOVERY" }, { "12NM", "RECOVERY" }, { "10NM", "RECOVERY" },
}
function SC.category(reason)
    local r = tostring(reason or "")
    for _, x in ipairs(CAT_RULES) do if r:find(x[1]) then return x[2] end end
    return "OTHER"
end
function SC.sum(cat, sign)   -- sign: nil all, 1 positives only, -1 negatives only
    local n = 0
    for _, e in ipairs(SC.ledger) do
        if (not cat or e.cat == cat) and (not sign or (sign > 0 and e.d > 0) or (sign < 0 and e.d < 0)) then n = n + e.d end
    end
    return n
end

function TRT.addScore(delta, reason, cat)
    local cur = trigger.misc.getUserFlag(FLAG_SCORE)
    if type(cur) ~= "number" then cur = 0 end
    local new = cur + delta

    trigger.action.setUserFlag(FLAG_SCORE, new)
    SC.expected = new
    cat = cat or SC.category(reason)
    SC.ledger[#SC.ledger + 1] = { t = timer.getAbsTime(), d = delta, reason = tostring(reason), cat = cat }
    env.info(string.format("[Core_Scoring] SCORE %+d (total %s) [%s] %s", delta, tostring(new), cat, tostring(reason)))

    local sign = (delta >= 0) and ("+" .. tostring(delta)) or tostring(delta)
    trigger.action.outTextForCoalition(
        coalition.side.BLUE,
        string.format("%s (%s) [TOTAL %s]", tostring(reason), sign, tostring(new)),
        8, false
    )
end

-- v1.5.0: flag 1908 changed by anything else (ME a_inc_flag etc.) -> re-book through TRT.addScore
timer.scheduleFunction(function()
    local cur = trigger.misc.getUserFlag(FLAG_SCORE)
    if type(cur) == "number" then
        if SC.expected == nil then
            SC.expected = cur
        elseif cur ~= SC.expected then
            local d = cur - SC.expected
            trigger.action.setUserFlag(FLAG_SCORE, SC.expected)
            env.info(string.format("[Core_Scoring] flag %d changed outside addScore by %+d", FLAG_SCORE, d))
            TRT.addScore(d, "MISSION EVENT (trigger)", "MISSION")
        end
    end
    return timer.getTime() + 1
end, nil, timer.getTime() + 1)

-- v1.5.0: incident registry (severity 0 note, 1 ROE breach, 2 serious, 3 friendly casualties)
local DISPOSITION = {
    [0] = "No action.",
    [1] = "Formal counseling, Letter of Instruction. The release is reviewed with CAG.",
    [2] = "Letter of Reprimand. Grounded pending a Field Naval Aviator Evaluation Board (FNAEB); command investigation.",
    [3] = "Friendly casualties: JAGMAN investigation and FNAEB; UCMJ action up to court-martial possible.",
}
function SC.incident(kind, sev, detail, src)
    local t = math.floor(timer.getAbsTime()) % 86400
    SC.incidents[#SC.incidents + 1] = { kind = kind, sev = sev or 1, detail = tostring(detail), src = src,
        clock = string.format("%02d%02d", math.floor(t / 3600), math.floor((t % 3600) / 60)) }
    env.info(string.format("[Core_Scoring] INCIDENT %s sev %d (%s): %s", kind, sev or 1, tostring(src), tostring(detail)))
end
function SC.report()
    if SC.reported or #SC.incidents == 0 then return end
    SC.reported = true
    local worst, lines = 0, { "ROE / FRIENDLY FIRE REPORT" }
    for _, i in ipairs(SC.incidents) do
        worst = math.max(worst, i.sev)
        lines[#lines + 1] = string.format("- %sL  %s", i.clock, i.detail)
    end
    local nBreach = 0
    for _, i in ipairs(SC.incidents) do if i.sev >= 1 then nBreach = nBreach + 1 end end
    if worst == 1 and nBreach >= 2 then worst = 2 end
    lines[#lines + 1] = "Disposition: " .. DISPOSITION[worst]
    SC.disposition = worst
    local txt = table.concat(lines, "\n")
    trigger.action.outTextForCoalition(coalition.side.BLUE, txt, 60, false)
    env.info("[Core_Scoring] REPORT\n" .. txt)
end

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
function TRT.uPlayer()
    return Unit.getByName(PLAYER_NAME)
end

function TRT.uCarrier()
    return Unit.getByName(CARRIER)
end

-- Reads a manually-set ME flag as a boolean, regardless of which ME
-- action set it: "FLAG ON" writes a Lua boolean, "FLAG VALUE" writes a
-- number. Mirrors the ME's own "FLAG IS TRUE" condition semantics -
-- boolean true, or any non-zero number, counts as true. Does not
-- infer anything; the flag's value is whatever the mission's own
-- triggers decided.
function TRT.flagTrue(flagId)
    local v = trigger.misc.getUserFlag(flagId)
    return v == true or (type(v) == "number" and v ~= 0)
end

function TRT.altFt(u)
    if not u or not u:isExist() then return 0 end
    local p = u:getPoint()
    return (p and p.y or 0) * 3.28084
end

function TRT.spdKts(u)
    if not u or not u:isExist() then return 0 end
    local v = u:getVelocity()
    if not v then return 0 end
    return math.sqrt((v.x or 0)^2 + (v.y or 0)^2 + (v.z or 0)^2) * 1.94384
end

function TRT.distToCarrierNm(u, c)
    c = c or TRT.uCarrier()
    if not u or not u:isExist() or not c or not c:isExist() then return 99999 end
    local pu, pc = u:getPoint(), c:getPoint()
    if not pu or not pc then return 99999 end
    return math.sqrt((pu.x - pc.x)^2 + (pu.z - pc.z)^2) / 1852
end

function TRT.inZone(u, zoneName)
    if not u or not u:isExist() then return false end
    local Z = trigger.misc.getZone(zoneName)
    if not Z then return false end
    local p = u:getPoint()
    local dx, dz = p.x - Z.point.x, p.z - Z.point.z
    return math.sqrt(dx*dx + dz*dz) <= Z.radius
end

function TRT.getHeading(u)
    if not u or not u:isExist() then return 0 end
    local pos = u:getPosition()
    if not pos or not pos.x then return 0 end
    local hdg = math.deg(math.atan2(pos.x.z, pos.x.x))
    if hdg < 0 then hdg = hdg + 360 end
    return hdg
end

function TRT.clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

----------------------------------------------------------------
-- ENEMY KILL SCORING
-- Fires on S_EVENT_KILL, not DEAD - KILL is the only event carrying
-- both initiator (killer) and target (victim). DEAD only tells you
-- what died, not who did it. Gated on initiator name == PLAYER_NAME:
-- only kills YOU personally get credit. Only RED-coalition targets
-- score, so a wrong-target or blue-on-blue hit can't add points.
--
-- UNVERIFIED: community reports on S_EVENT_KILL are mixed for
-- StaticObject targets - some report it does not fire reliably for
-- statics, only S_EVENT_DEAD does. This directly affects your
-- "factory" HVT case (#2 in your request). DEBUG_LOG_UNATTRIBUTED_DEATHS
-- exists to let you check this empirically: it logs any RED death DEAD
-- saw that never got a matching PLAYER_01 KILL, so you can read the
-- dcs.log after a test hop and see whether your static targets are
-- being missed. Set it false once you've confirmed coverage.
--
-- Resolution priority (first match wins):
--   1. UNIT_NAME_OVERRIDES  - exact unit/static name
--   2. UNIT_NAME_OVERRIDES  - name prefix (handles DCS's auto " #001"
--      suffix when a unit/static name is duplicated in the ME)
--   3. TYPE_SCORES          - unit:getTypeName(); matches the ME's
--      "TYPE" field (e.g. "Infantry AK-74 Rus ver1")
--   4. GROUP_CATEGORY_SCORES - unit:getGroup():getCategory(); statics
--      have no getGroup() and go straight to STATIC_DEFAULT_SCORE
--   5. DEFAULT_ENEMY_SCORE  - flat fallback, nothing scores nil/0 silently
--
-- The ME's "CATEGORY / SUB. CAT." fields (Infantry / All, etc.) are
-- Mission-Editor placement-browser taxonomy - not queryable at runtime
-- in that exact form. TYPE_SCORES (exact type name) is the practical
-- runtime equivalent of "Sub. Cat."; group category is the equivalent
-- of the coarse "Category" level.
----------------------------------------------------------------
local DEBUG_LOG_UNATTRIBUTED_DEATHS = true

local UNIT_NAME_OVERRIDES = {
    -- Migrated 1:1 from the old DEAD_SCORES table's positive entries.
    -- These now ALSO require PLAYER_NAME to be the killer - before this
    -- rework, ANY death of these names scored regardless of who or what
    -- killed them. Confirm that behavior change is what you want.
    ["SAM 15 (8-13-15-19)-1"] = 10,
    ["SAM 15 (8-13-15-19)-2"] = 9,
    ["SAM 15 (8-13-15-19)-3"] = 8,
    ["SAM 15 (8-13-15-19)-4"] = 7,
    ["SAM 7 (13)-1"] = 5,
    ["SAM 7 (13)-2"] = 7,

    ["POPUP_TARGET1"] = 9,
    ["STRIKE1_TRG2"]  = 9,
    ["AKROTIRI_Chemical_Factory"] = 10,
    ["STRIKE1_TRG1"] = 10,
}
-- NOTE: you flagged these unit names as outdated - update this table
-- when you rebuild the target list for your current mission.

local TYPE_SCORES = {
    -- v1.4.0: tiered table built from every RED unit type in CAS (L) and the
    -- template (2026-10-28 inventory). Keyed by unit:getTypeName() (= ME TYPE).
    -- Types not listed fall back to GROUP_CATEGORY_SCORES / STATIC_DEFAULT_SCORE.

    -- SAM fire control / tracking radars, command posts (the node that matters)
    ["Kub 1S91 str"] = 12, ["snr s-125 tr"] = 12, ["SNR_75V"] = 12, ["RD_75"] = 12,
    ["S-300PS 40B6M tr"] = 12, ["S-300PS 5H63C 30H6_tr"] = 12, ["S-300PS 54K6 cp"] = 12,
    -- search / early warning radars
    ["S-300PS 64H6E sr"] = 10, ["S-300PS 40B6MD sr"] = 10, ["S-300PS 40B6MD sr_19J6"] = 10,
    ["p-19 s-125 sr"] = 10, ["1L13 EWR"] = 10, ["55G6 EWR"] = 10, ["GCI_station_MiG29"] = 10,
    ["SAMPT_MGE"] = 10,
    -- self-contained SAM (own radar on the vehicle)
    ["Tor 9A331"] = 12, ["CHAP_TorM2"] = 12, ["Osa 9A33 ln"] = 10, ["2S6 Tunguska"] = 10,
    -- SAM launchers (need an external radar) / IR SAM vehicles
    ["S-300PS 5P85C ln"] = 8, ["S-300PS 5P85D ln"] = 8,
    ["Kub 2P25 ln"] = 6, ["5p73 s-125 ln"] = 6, ["5p73 V-601P ln"] = 6,
    ["S_75M_Volhov"] = 6, ["S_75M_Volhov_V759"] = 6,
    ["Strela-10M3"] = 6, ["Strela-1 9P31"] = 5, ["generator_5i57"] = 3,
    -- AAA
    ["ZSU-23-4 Shilka"] = 6, ["ZU-23 Emplacement"] = 4, ["Ural-375 ZU-23 Insurgent"] = 4,
    ["HL_DSHK"] = 3, ["HL_KORD"] = 3, ["tt_DSHK"] = 3, ["tt_KORD"] = 3,
    -- MANPADS teams
    ["SA-14 Strela-3 manpad"] = 3, ["SA-18 Igla manpad"] = 3, ["SA-18 Igla-S manpad"] = 3,
    ["SA-24 Igla-S manpad"] = 3, ["Igla manpad INS"] = 3,
    -- tanks
    ["T-90"] = 6, ["T-72B3"] = 5, ["T-72B"] = 5, ["T62M"] = 4, ["T-55"] = 4, ["PT_76"] = 3,
    -- IFV / APC / scout
    ["BMP-3"] = 4, ["BMP-1"] = 3, ["BTR-82A"] = 3, ["BTR-80"] = 3, ["AAV7"] = 3,
    ["BTR-70"] = 2, ["BTR-60"] = 2, ["BRDM-2"] = 2, ["Tigr_233036"] = 2,
    -- artillery / MLRS
    ["CHAP_TOS1A"] = 6, ["Uragan_BM-27"] = 5, ["SAU Msta"] = 5, ["Grad-URAL"] = 4,
    ["SAU Akatsia"] = 4, ["SAU Gvozdika"] = 4, ["SpGH_Dana"] = 4, ["SAU 2-C9"] = 3,
    -- command / logistics
    ["Ural-375 PBU"] = 3,
    ["ATZ-10"] = 2, ["ATZ-5"] = 2, ["ATZ-60_Maz"] = 2, ["ATMZ-5"] = 2,
    ["ZIL-131 KUNG"] = 2, ["ZiL-131 APA-80"] = 2, ["Ural-375"] = 2, ["Ural-4320-31"] = 2,
    ["Ural-4320T"] = 2, ["GAZ-66"] = 2, ["KAMAZ Truck"] = 2, ["KrAZ6322"] = 2, ["ZIL-135"] = 2,
    ["UAZ-469"] = 1,
    -- infantry
    ["Infantry AK"] = 1, ["Infantry AK ver2"] = 1, ["Infantry AK ver3"] = 1, ["Infantry AK Ins"] = 1,
    ["Infantry AK-74 Rus ver1"] = 1, ["Soldier AK"] = 1, ["Soldier M249"] = 1, ["Soldier RPG"] = 1,
    -- aircraft (air-to-air or on the ground)
    ["A-50"] = 15, ["Tu-95MS"] = 10, ["Tu-142"] = 10, ["IL-78M"] = 8,
    ["MiG-29 Fulcrum"] = 10, ["MiG-29A"] = 10, ["MiG-29S"] = 10, ["Su-27"] = 10, ["Su-33"] = 10,
    ["MiG-23MLD"] = 8, ["Ka-50"] = 8, ["Ka-50_3"] = 8, ["Mi-8MT"] = 5, ["UH-1H"] = 4,
    -- statics worth more than STATIC_DEFAULT_SCORE
    [".Command Center"] = 10, ["ERO_S300_Reload"] = 3, ["ammo_cargo"] = 3,
}

local GROUP_CATEGORY_SCORES = {
    -- Verify these constant names against your DCS version if this
    -- layer ever resolves to nil unexpectedly.
    [Group.Category.GROUND]     = 2,   -- v1.4.0: unlisted ground type (was 1)
    [Group.Category.SHIP]       = 5,
    [Group.Category.AIRPLANE]   = 8,
    [Group.Category.HELICOPTER] = 8,
    [Group.Category.TRAIN]      = 3,
}

local STATIC_DEFAULT_SCORE = 2
local DEFAULT_ENEMY_SCORE  = 1
local JTAC_GROUP_BONUS     = 5     -- v1.4.0: hero's kill finishes a JTAC target group
local FF_KILL              = -50   -- v1.5.0 friendly unit / static destroyed by the hero
local FF_HIT               = -20   -- v1.5.0 first hit on each friendly object (no kill needed)
local JTAC_BONUS_DELAY     = 3     -- s after the kill before counting the survivors

local function resolveEnemyScore(unitName, typeName, groupCategory, isStatic)
    local delta = UNIT_NAME_OVERRIDES[unitName]
    if delta then return delta, "name" end

    local best, bestVal                       -- v1.5.0: longest prefix wins (pairs() order was arbitrary)
    for key, val in pairs(UNIT_NAME_OVERRIDES) do
        if string.find(unitName, key, 1, true) == 1 and (not best or #key > #best or (#key == #best and key < best)) then
            best, bestVal = key, val
        end
    end
    if best then return bestVal, "name-prefix" end

    if typeName and TYPE_SCORES[typeName] then
        return TYPE_SCORES[typeName], "type"
    end

    if isStatic then
        return STATIC_DEFAULT_SCORE, "static-default"
    end

    if groupCategory and GROUP_CATEGORY_SCORES[groupCategory] then
        return GROUP_CATEGORY_SCORES[groupCategory], "group-category"
    end

    return DEFAULT_ENEMY_SCORE, "default"
end

-- v1.4.0: JTAC target groups = groupId of every FAC_AttackGroup task in the ME data
local JTAC_TARGETS, jtacBonusDone = {}, {}
local JTAC_UNIT_GROUP = {}   -- v1.4.2: unit name -> JTAC target group name (ME data)
local AddJtacTarget          -- v1.4.6: (group name) -> true if new; maps its ME units
do
    local byId = {}
    local function each(fn)
        for _, side in pairs((env.mission and env.mission.coalition) or {}) do
            for _, c in pairs(side.country or {}) do
                for _, cat in ipairs({ "vehicle", "plane", "helicopter", "ship" }) do
                    for _, g in pairs((c[cat] and c[cat].group) or {}) do fn(g) end
                end
            end
        end
    end
    local function scan(t, out)
        if type(t) ~= "table" then return end
        if t.id == "FAC_AttackGroup" and t.params and t.params.groupId then out[#out + 1] = t.params.groupId end
        for _, v in pairs(t) do scan(v, out) end
    end
    local ids = {}
    local ok = pcall(function()
        each(function(g) if g.groupId and g.name then byId[g.groupId] = env.getValueDictByKey(g.name) or g.name end end)
        each(function(g) scan(g.tasks, ids); scan(g.route, ids) end)
    end)
    local names = {}
    for _, id in ipairs(ids) do
        local n = byId[id]
        if n and not JTAC_TARGETS[n] then JTAC_TARGETS[n] = true; names[#names + 1] = n end
    end
    pcall(function()
        each(function(g)
            local gn = g.name and (env.getValueDictByKey(g.name) or g.name)
            if gn and JTAC_TARGETS[gn] then
                for _, u in pairs(g.units or {}) do
                    if u.name then JTAC_UNIT_GROUP[env.getValueDictByKey(u.name) or u.name] = gn end
                end
            end
        end)
    end)
    env.info("[Core_Scoring] JTAC target groups (" .. #names .. "): " .. table.concat(names, ", ")
        .. (ok and "" or " [scan error]"))
    AddJtacTarget = function(gname)
        if type(gname) ~= "string" or JTAC_TARGETS[gname] then return false end
        JTAC_TARGETS[gname] = true
        pcall(function()
            each(function(g)
                local gn = g.name and (env.getValueDictByKey(g.name) or g.name)
                if gn == gname then
                    for _, u in pairs(g.units or {}) do
                        if u.name then JTAC_UNIT_GROUP[env.getValueDictByKey(u.name) or u.name] = gn end
                    end
                end
            end)
        end)
        return true
    end
end

-- v1.4.6: JTAC_Controller target groups (it loads after this file)
local function MergeJcTargets()
    local jc = TRT.JC
    if not (jc and jc.CFG and type(jc.CFG.JTACS) == "table") then return end
    if jc.objectiveBonus then return end   -- v1.5.2: JTAC_Controller scores the objective itself
    local added = {}
    for _, j in pairs(jc.CFG.JTACS) do
        for _, gn in ipairs(j.targets or {}) do
            if AddJtacTarget(gn) then added[#added + 1] = gn end
        end
    end
    if #added > 0 then env.info("[Core_Scoring] JTAC target groups + JTAC_Controller: " .. table.concat(added, ", ")) end
end
timer.scheduleFunction(function() pcall(MergeJcTargets) end, nil, timer.getTime() + 2)

do
    local killHandled = {}
    local deadSeen = {}
    local KEH = {}

    function KEH:onEvent(e)
        if not e then return end

        -- Debug capture: any RED death, independent of KILL attribution.
        if DEBUG_LOG_UNATTRIBUTED_DEATHS and e.id == world.event.S_EVENT_DEAD
           and e.initiator and e.initiator.getName then
            local okN, n = pcall(function() return e.initiator:getName() end)
            local okC, c = pcall(function() return e.initiator:getCoalition() end)
            if okN and n and okC and c == coalition.side.RED and not killHandled[n] then
                deadSeen[n] = true
            end
        end

        if e.id ~= world.event.S_EVENT_KILL then return end

        local killer, victim = e.initiator, e.target
        if not killer or not killer.getName or not victim or not victim.getName then return end

        local okK, killerName = pcall(function() return killer:getName() end)
        if not okK or killerName ~= PLAYER_NAME then return end

        local okV, victimName = pcall(function() return victim:getName() end)
        if not okV or not victimName or killHandled[victimName] then return end

        local okCo, victimCoalition = pcall(function() return victim:getCoalition() end)
        local okKC, killerCoalition = pcall(function() return killer:getCoalition() end)
        if okCo and okKC and victimCoalition == killerCoalition then          -- v1.5.0 friendly fire
            killHandled[victimName] = true
            local okTN, tn = pcall(function() return victim:getTypeName() end)
            local what = string.format("%s (%s)", victimName, okTN and tn or "?")
            TRT.addScore(FF_KILL, "FRIENDLY FIRE: destroyed " .. what, "ROE")
            SC.incident("FF_KILL", 3, "Friendly fire: " .. what .. " destroyed by " .. PLAYER_NAME, "Core_Scoring")
            return
        end
        if not okCo or victimCoalition ~= coalition.side.RED then return end

        local okCat, cat = pcall(function() return victim:getCategory() end)
        local isStatic = okCat and cat == Object.Category.STATIC

        local typeName = nil
        local okT, tn = pcall(function() return victim:getTypeName() end)
        if okT then typeName = tn end

        local groupCategory = nil
        if not isStatic then
            local okG, grp = pcall(function() return victim:getGroup() end)
            if okG and grp then
                local okGC, gc = pcall(function() return grp:getCategory() end)
                if okGC then groupCategory = gc end
            end
        end

        -- v1.4.6: weapon released without clearance / after an abort earns nothing
        local jc = TRT.JC
        if jc and type(jc.unauthKill) == "function" then
            local okU, unauth = pcall(jc.unauthKill, e.weapon, victim)
            if okU and unauth then
                killHandled[victimName] = true
                deadSeen[victimName] = nil
                env.info("[Core_Scoring] kill NOT scored (unauthorized release): " .. victimName)
                return
            end
        end
        pcall(MergeJcTargets)

        local delta, source = resolveEnemyScore(victimName, typeName, groupCategory, isStatic)
        killHandled[victimName] = true
        deadSeen[victimName] = nil
        TRT.addScore(delta, string.format("TARGET DESTROYED [%s]: %s", source, victimName))

        -- v1.4.0: JTAC target group finished by this kill -> bonus (once per group)
        if not isStatic then
            local gname = JTAC_UNIT_GROUP[victimName]   -- v1.4.2 (getGroup() is empty here)
            local okN = gname ~= nil
            if okN and gname and JTAC_TARGETS[gname] and not jtacBonusDone[gname] then
                timer.scheduleFunction(function()
                    if jtacBonusDone[gname] then return nil end
                    local g2 = Group.getByName(gname)
                    local alive = 0
                    if g2 then
                        for _, u in ipairs(g2:getUnits() or {}) do
                            local okE, ex = pcall(function() return u:isExist() and u:getLife() > 1 end)
                            if okE and ex then alive = alive + 1 end
                        end
                    end
                    if alive == 0 then
                        jtacBonusDone[gname] = true
                        TRT.addScore(JTAC_GROUP_BONUS, "JTAC TARGET GROUP DESTROYED: " .. gname)
                    end
                    return nil
                end, nil, timer.getTime() + JTAC_BONUS_DELAY)
            end
        end
    end

    world.addEventHandler(KEH)

    -- v1.5.0: friendly fire, damage (first hit per friendly object)
    local ffHit = {}
    local HEH = {}
    function HEH:onEvent(e)
        if not e or e.id ~= world.event.S_EVENT_HIT or not e.initiator or not e.target then return end
        pcall(function()
            if e.initiator:getName() ~= PLAYER_NAME then return end
            local tgt = e.target
            if not tgt.getCoalition or tgt:getCoalition() ~= e.initiator:getCoalition() then return end
            local n = tgt:getName()
            if not n or ffHit[n] or killHandled[n] then return end
            ffHit[n] = true
            local okTN, tn = pcall(function() return tgt:getTypeName() end)
            local wn = (e.weapon_name) or (e.weapon and e.weapon.getTypeName and e.weapon:getTypeName()) or "?"
            local what = string.format("%s (%s)", n, okTN and tn or "?")
            TRT.addScore(FF_HIT, "FRIENDLY FIRE: hit " .. what, "ROE")
            SC.incident("FF_HIT", 2, string.format("Friendly fire: %s hit by %s (%s)", what, PLAYER_NAME, wn), "Core_Scoring")
        end)
    end
    world.addEventHandler(HEH)

    if DEBUG_LOG_UNATTRIBUTED_DEATHS then
        timer.scheduleFunction(function()
            for name in pairs(deadSeen) do
                env.info("[Core_Scoring] DEAD without a matching " .. PLAYER_NAME ..
                    " KILL: " .. name .. " - check whether this should have scored.")
            end
            deadSeen = {}
            return timer.getTime() + 15
        end, nil, timer.getTime() + 15)
    end
end

----------------------------------------------------------------
-- FRIENDLY ASSET LOSS PENALTY
-- The negative half of the old DEAD_SCORES table. Kept on
-- S_EVENT_DEAD with NO attribution check by design - a lost
-- tanker/AWACS is a mission-state fact regardless of who or what
-- killed it. Do not merge this back into the enemy-kill handler above,
-- and do not add a second S_EVENT_DEAD/KILL scoring handler elsewhere
-- in the framework or kills/losses will double-count.
----------------------------------------------------------------
local FRIENDLY_LOSS_PENALTIES = {
    ["TANKER-1-1"] = -8, ["TANKER-2-1"] = -8, ["TANKER-3-1"] = -8, ["TANKER-4-1"] = -8,
    ["ARCO-5-1"]   = -8, ["TANKER-6-1"] = -8,

    ["MAGIC-2-1"]    = -10,
    ["OVERLORD-1-1"] = -10,
}

do
    local lossHandled = {}
    local LEH2 = {}

    function LEH2:onEvent(e)
        if not e or e.id ~= world.event.S_EVENT_DEAD then return end
        local obj = e.initiator
        if not obj or not obj.getName then return end

        local ok, name = pcall(function() return obj:getName() end)
        if not ok or not name or lossHandled[name] then return end

        local delta = FRIENDLY_LOSS_PENALTIES[name]
        if not delta then return end

        lossHandled[name] = true
        -- v1.5.1: mission loss, not the pilot's score
        SC.losses[#SC.losses + 1] = { t = timer.getAbsTime(), name = name, value = delta }
        env.info(string.format("[Core_Scoring] MISSION LOSS %s (%d, not in the pilot total)", name, delta))
        trigger.action.outTextForCoalition(coalition.side.BLUE, "MISSION LOSS: " .. name, 10, false)
    end

    world.addEventHandler(LEH2)
end

----------------------------------------------------------------
-- GROOVE FUEL SCORING (one-shot per sortie)
----------------------------------------------------------------
do
    local GROOVE_DIST_NM     = 1.6
    local GROOVE_ALT_MIN_FT  = 50
    local GROOVE_ALT_MAX_FT  = 900
    local GROOVE_SPD_MIN_KTS = 105
    local GROOVE_SPD_MAX_KTS = 240
    -- CASE-III used 105-210. Standardized to the majority value (2 of 3
    -- source files used 240). Its extra "high fuel / excess fuel"
    -- zero-score informational messages were dropped for simplicity -
    -- they never affected score, only chat text.

    local FUEL_EMERGENCY_LBS = 1500
    local FUEL_LOW_LBS       = 2000
    -- v1.5.0: 2,500-3,500 "good" band retired; the plan comes from Flight_Timeline
    local GROOVE_BINGO_FALLBACK   = 4100   -- recovery BINGO (TL v1.1.5, LCRA ~110 NM) when TL is missing
    local GROOVE_MAXTRAP_FALLBACK = 4300   -- 33,000 - ZFW 28,700
    local GROOVE_TOL_LB           = 300

    local grooveDone = {}

    local function fuelLbs(u)
        local frac = u:getFuel()
        if not frac then return nil end

        local maxKg
        local ok, desc = pcall(function() return u:getDesc() end)
        if ok and desc and desc.fuelMassMax then
            maxKg = desc.fuelMassMax
        end

        if not maxKg then
            return frac * 11000 -- Hornet-class fallback
        end
        return frac * maxKg * 2.2046226218
    end

    function TRT.updateGrooveFuel(u)
        if not u or not u:isExist() then return end
        local uname = u:getName()
        if not uname or grooveDone[uname] then return end

        local c = TRT.uCarrier()
        if not c or not c:isExist() then return end
        if TRT.distToCarrierNm(u, c) > GROOVE_DIST_NM then return end

        -- v1.5.0: in the groove = AIRBOSS step "Groove ..." for the hero; geometric window only without AIRBOSS
        local ab, inGroove = TRT.Airboss, nil
        if type(ab) == "table" and type(ab.players) == "table" then
            inGroove = false
            for _, pd in pairs(ab.players) do
                if type(pd) == "table" and pd.unitname == uname then
                    inGroove = type(pd.step) == "string" and pd.step:find("^Groove") ~= nil
                end
            end
        end
        if inGroove == false then return end
        if inGroove == nil then
            local alt = TRT.altFt(u)
            if alt < GROOVE_ALT_MIN_FT or alt > GROOVE_ALT_MAX_FT then return end
            local spd = TRT.spdKts(u)
            if spd < GROOVE_SPD_MIN_KTS or spd > GROOVE_SPD_MAX_KTS then return end
        end

        local lbs = fuelLbs(u)
        if not lbs then return end

        -- v1.5.0: bands from the recovery fuel plan (Flight_Timeline thresholds, RECOVERY zone)
        local bingo, maxTrap = GROOVE_BINGO_FALLBACK, GROOVE_MAXTRAP_FALLBACK
        local tl = TRT.TL
        if tl and type(tl.thresholds) == "function" then
            local okT, th = pcall(tl.thresholds, u:getPoint(), { phase = "RECOVERY" }, nil)
            if okT and type(th) == "table" then
                bingo = tonumber(th.bingo) or bingo
                maxTrap = tonumber(th.maxTrap) or maxTrap
            end
        end
        local delta, why
        if lbs > maxTrap + 1000 then
            delta, why = -5, string.format("%.0f lb, over max trap %.0f by %.0f", lbs, maxTrap, lbs - maxTrap)
        elseif lbs > maxTrap + GROOVE_TOL_LB then
            delta, why = -2, string.format("%.0f lb, above max trap %.0f", lbs, maxTrap)
        elseif lbs >= bingo - GROOVE_TOL_LB then
            delta, why = 3, string.format("%.0f lb, on plan (BINGO %.0f .. max trap %.0f)", lbs, bingo, maxTrap)
        elseif lbs >= FUEL_LOW_LBS then
            delta, why = -2, string.format("%.0f lb, below recovery BINGO %.0f", lbs, bingo)
        elseif lbs >= FUEL_EMERGENCY_LBS then
            delta, why = -5, string.format("%.0f lb, critical", lbs)
        else
            delta, why = -8, string.format("%.0f lb, below the recovery minimum", lbs)
        end
        grooveDone[uname] = true
        TRT.addScore(delta, "Groove fuel: " .. why, "TRAP")
    end

    local GEH = {}
    function GEH:onEvent(e)   -- v1.5.0: once per sortie (reset at the landing; a bolter's takeoff keeps it)
        if e and e.id == world.event.S_EVENT_LAND and e.initiator then
            local ok, n = pcall(function() return e.initiator:getName() end)
            if ok and n then grooveDone[n] = nil end
        end
    end
    world.addEventHandler(GEH)
end

----------------------------------------------------------------
-- REFUEL SCORING (player zone-based + AI trend-based)
----------------------------------------------------------------
do
    local PLAYER_REFUEL_ZONES = {
        "TANKER_1_SAFE_ZONE",
        "TANKER_2_SAFE_ZONE",
        "TANKER_5_SAFE_ZONE",
        -- CASE-I used zone "3" instead of "5". Uncomment if your current
        -- mission still places a tanker safe-zone named TANKER_3_SAFE_ZONE:
        -- "TANKER_3_SAFE_ZONE",
    }

    local PLAYER_REFUEL_SCORE = false   -- v1.4.3: off until AAR_Monitor.lua owns AAR scoring

    local REFUEL_UNITS = {}
    local lastFuel, baseline, rewarded = {}, {}, {}
    local playerRefuel = { inZone = false, baseline = nil, done = false }

    local function inAnyRefuelZone(u)
        for _, zn in ipairs(PLAYER_REFUEL_ZONES) do
            if TRT.inZone(u, zn) then return true end
        end
        return false
    end

    timer.scheduleFunction(function()
        local groups = coalition.getGroups(coalition.side.BLUE, Group.Category.AIRPLANE) or {}
        for _, g in ipairs(groups) do
            for _, u in ipairs(g:getUnits() or {}) do
                if u and u:isExist() then REFUEL_UNITS[u:getName()] = true end
            end
        end
        return timer.getTime() + 10
    end, nil, timer.getTime() + 1)

    local function updatePlayerZoneRefuel()
        if playerRefuel.done then return end
        local u = TRT.uPlayer()
        if not u or not u:isExist() then return end

        local f = u:getFuel()
        if not f then return end

        local inside = inAnyRefuelZone(u)

        if inside and not playerRefuel.inZone then
            playerRefuel.inZone, playerRefuel.baseline = true, f
            return
        end
        if not inside and playerRefuel.inZone then
            playerRefuel.inZone, playerRefuel.baseline = false, nil
            return
        end
        if inside and playerRefuel.baseline and (f - playerRefuel.baseline) >= 0.2 then
            playerRefuel.done = true
            if PLAYER_REFUEL_SCORE then
                TRT.addScore(7, "Aerial Refuel Complete: " .. PLAYER_NAME)
            else
                env.info("[Core_Scoring] player refuel detected (no score, PLAYER_REFUEL_SCORE=false): " .. PLAYER_NAME)
            end
            if TRT.onRefuelComplete and not (TRT.AAR and TRT.AAR.callsRefuelComplete) then
                TRT.onRefuelComplete(PLAYER_NAME)
            end
        end
    end

    timer.scheduleFunction(function()
        updatePlayerZoneRefuel()

        for name in pairs(REFUEL_UNITS) do
            if name ~= PLAYER_NAME then
                local u = Unit.getByName(name)
                if u and u:isExist() then
                    local f = u:getFuel()
                    if f then
                        if lastFuel[name] == nil then
                            lastFuel[name], baseline[name], rewarded[name] = f, nil, false
                        else
                            local df = f - lastFuel[name]
                            if df < -0.005 then baseline[name], rewarded[name] = nil, false end
                            if df > 0 and not baseline[name] then baseline[name] = lastFuel[name] end
                            if baseline[name] and not rewarded[name] and (f - baseline[name]) >= 0.03 then
                                rewarded[name] = true
                                local okP, pn = pcall(u.getPlayerName, u)        -- v1.3.2
                                if okP and pn then
                                    if PLAYER_REFUEL_SCORE then TRT.addScore(7, "Aerial Refuel Complete: " .. name) end
                                else
                                    env.info("[Core_Scoring] AI refuel complete (no score): " .. name)
                                end
                                if TRT.onRefuelComplete then TRT.onRefuelComplete(name) end
                            end
                            lastFuel[name] = f
                        end
                    end
                end
            end
        end
        return timer.getTime() + 1
    end, nil, timer.getTime() + 1)

    local REH = {}
    function REH:onEvent(e)
        if not e or not e.initiator or e.id ~= world.event.S_EVENT_TAKEOFF then return end
        local u = e.initiator
        if not u or not u.getName then return end
        local n = u:getName()
        if n == PLAYER_NAME then
            playerRefuel.inZone, playerRefuel.baseline, playerRefuel.done = false, nil, false
        end
        lastFuel[n], baseline[n], rewarded[n] = nil, nil, false
    end
    world.addEventHandler(REH)
end

----------------------------------------------------------------
-- LANDING SCORING (carrier trap + land-base)
----------------------------------------------------------------
do
    local TARGET_UNITS = {
        ["LANDER-8-1"] = true, ["LANDER-6-1"] = true, ["CAS-1-1"] = true,
        ["TOMCAT-2-1"] = true, ["TOMCAT-1-1"] = true, [PLAYER_NAME] = true,
    }
    local LANDING_DONE = {}
    local LAND_CONFIRM_S = 8          -- v1.4.5
    local GRADE_WAIT_S   = 12         -- v1.4.7: extra wait for the AIRBOSS LSO grade after the confirm
    local REPORT_S       = 20         -- v1.5.0: ROE / friendly fire report this long after the landing confirm
    local LAST_GRADE     = nil        -- v1.4.7: { t, grade, points, wire } of the hero's last graded pass

    -- v1.4.7: AIRBOSS LSO grade hook (chained; later hooks, e.g. Pilot_Banter, chain to this one)
    local function hookGrade()
        local ab = TRT.Airboss
        if type(ab) ~= "table" then return false end
        if ab.__trtCsGrade then return true end
        local prev = ab.OnAfterLSOGrade
        ab.OnAfterLSOGrade = function(self, From, Event, To, pd, grade, ...)
            if prev then
                local okP, errP = pcall(prev, self, From, Event, To, pd, grade, ...)
                if not okP then env.info("[Core_Scoring] previous OnAfterLSOGrade error: " .. tostring(errP)) end
            end
            pcall(function()
                if type(pd) == "table" and pd.unitname == PLAYER_NAME and type(grade) == "table" then
                    LAST_GRADE = { t = timer.getTime(), grade = tostring(grade.grade), points = tonumber(grade.points),
                                   wire = grade.wire }
                    SC.passes[#SC.passes + 1] = { t = timer.getAbsTime(), grade = tostring(grade.grade),   -- v1.5.1
                        points = tonumber(grade.points), wire = tonumber(grade.wire), tgroove = tonumber(grade.Tgroove),
                        details = tostring(grade.details or ""), landed = pd.landed and true or false }
                    env.info(string.format("[Core_Scoring] LSO grade %s (%s PT, wire %s)", LAST_GRADE.grade,
                        tostring(LAST_GRADE.points), tostring(LAST_GRADE.wire)))
                end
            end)
        end
        ab.__trtCsGrade = true
        env.info("[Core_Scoring] AIRBOSS OnAfterLSOGrade hooked")
        return true
    end
    if not hookGrade() then
        timer.scheduleFunction(function() if hookGrade() then return nil end return timer.getTime() + 5 end,
            nil, timer.getTime() + 5)
    end

    --- v1.4.7: hero carrier landing points from the LSO grade (t0 = S_EVENT_LAND time)
    local function awardTrap(n, t0, tEnd)
        local g = LAST_GRADE
        if g and g.t >= t0 - 2 and g.points then
            local pts = math.max(0, math.min(5, math.floor(g.points + 0.5)))
            local wire = tonumber(g.wire) and string.format(", %d-wire", g.wire) or ""
            SC.lso = SC.passes[#SC.passes]   -- v1.5.1
            if pts > 0 then
                TRT.addScore(pts, string.format("Carrier landing, LSO %s%s", g.grade, wire))
            else
                env.info(string.format("[Core_Scoring] carrier landing, LSO %s: 0 points", g.grade))
                trigger.action.outTextForCoalition(coalition.side.BLUE,
                    string.format("Carrier landing, LSO %s%s: no landing points", g.grade, wire), 8, false)
            end
            return nil
        end
        if timer.getTime() < tEnd then return timer.getTime() + 1 end
        env.info("[Core_Scoring] no LSO grade " .. GRADE_WAIT_S .. " s after the landing confirm - scored as No Grade")
        TRT.addScore(2, "Carrier landing, not graded (No Grade)", "TRAP")   -- v1.5.0 (was +5)
        return nil
    end
    local PENDING = {}                -- name -> { kind, lost }
    local LEH = {}
    local EV = world.event
    local LOST_EV = { [EV.S_EVENT_CRASH] = true, [EV.S_EVENT_DEAD] = true, [EV.S_EVENT_EJECTION] = true,
                      [EV.S_EVENT_PILOT_DEAD] = true }
    if EV.S_EVENT_UNIT_LOST then LOST_EV[EV.S_EVENT_UNIT_LOST] = true end

    local function confirm(n)
        local p = PENDING[n]
        PENDING[n] = nil
        if not p or LANDING_DONE[n] then return nil end
        local u = Unit.getByName(n)
        local alive = u and u:isExist() and (u:getLife() or 0) >= 1
        if p.lost or not alive then
            env.info(string.format("[Core_Scoring] %s landing NOT scored: aircraft lost within %d s (%s)", p.kind,
                LAND_CONFIRM_S, n))
            return nil
        end
        LANDING_DONE[n] = true
        if n == PLAYER_NAME then   -- v1.5.0: ROE / friendly fire report after the landing
            timer.scheduleFunction(function() pcall(SC.report) end, nil, timer.getTime() + REPORT_S)
        end
        if n ~= PLAYER_NAME then   -- v1.5.1: AI / other slots never score for the hero
            env.info(string.format("[Core_Scoring] %s landing of %s (not the hero): not scored", p.kind, n))
            return nil
        end
        if p.kind == "carrier" then
            local tEnd = timer.getTime() + GRADE_WAIT_S   -- v1.4.7: points from the LSO grade
            timer.scheduleFunction(function() return awardTrap(n, p.t0, tEnd) end, nil, timer.getTime() + 0.1)
            if TRT.onCarrierLanding then TRT.onCarrierLanding(n) end
        else
            TRT.addScore(2, "Successful land-based landing")
        end
        return nil
    end

    function LEH:onEvent(e)
        if not e or not e.initiator then return end
        if LOST_EV[e.id] then
            local ok, n = pcall(function() return e.initiator:getName() end)
            if ok and n and PENDING[n] then PENDING[n].lost = true end
            return
        end
        if e.id ~= EV.S_EVENT_LAND then return end
        local unit = e.initiator
        local n = unit:getName()
        if not TARGET_UNITS[n] or LANDING_DONE[n] or PENDING[n] then return end

        local kind
        local carrier = TRT.uCarrier()
        if carrier and TRT.distToCarrierNm(unit, carrier) <= TRAP_RADIUS_NM then
            kind = "carrier"
        else
            local place = e.place
            if place and place.getCategory and place:getCategory() == Object.Category.BASE then kind = "land-based" end
        end
        if not kind then return end
        PENDING[n] = { kind = kind, lost = false, t0 = timer.getTime() }
        timer.scheduleFunction(function() confirm(n) end, nil, timer.getTime() + LAND_CONFIRM_S)
    end
    world.addEventHandler(LEH)
end

----------------------------------------------------------------
-- BANKLER: v1.5.1 the merge into the total is removed (it never fired: it read a "traptrainer"
-- global that does not exist). Bankler's pass score is shown as is by Flight_Report.lua.
----------------------------------------------------------------

----------------------------------------------------------------
-- ACTIVE CASE (MANUAL, MISSION-EDITOR CONTROLLED)
-- Case selection is a plain mission flag now, not weather-derived -
-- set flag 100 directly from a Mission Editor trigger (FLAG VALUE
-- action). Add further triggers (time/zone-based) if you want the
-- case to change mid-mission (e.g. fog rolling in on the way back).
----------------------------------------------------------------
do
    local warnedMissing = false

    function TRT.getCurrentCase()
        local c = trigger.misc.getUserFlag(100)
        if type(c) ~= "number" or c < 1 or c > 3 then
            if not warnedMissing then
                warnedMissing = true
                env.info("[Core_Scoring] WARNING: flag 100 not set (or invalid) - defaulting to CASE 1. Set flag 100 in a Mission Editor trigger (FLAG VALUE action).")
                trigger.action.outText(
                    "WARNING: Recovery Case flag (100) not set - defaulting to CASE I. Check mission triggers.",
                    15
                )
            end
            return 1
        end
        return c
    end
end

----------------------------------------------------------------
-- CASE-CHANGE ANNOUNCER
-- Watches flag 100 (set manually via Mission Editor triggers - see
-- the ACTIVE CASE section above) and announces every time its value
-- changes, no matter what set it. Does not announce the initial read
-- at mission start, only actual transitions.
----------------------------------------------------------------
do
    local lastSeen = nil

    local function watchCaseChange()
        local case = TRT.getCurrentCase()
        if case ~= lastSeen then
            if lastSeen ~= nil then
                trigger.action.outTextForCoalition(
                    coalition.side.BLUE,
                    string.format("RECOVERY CASE CHANGED: CASE %d -> CASE %d", lastSeen, case),
                    12, false
                )
            end
            lastSeen = case
        end
        return timer.getTime() + 5
    end

    timer.scheduleFunction(watchCaseChange, nil, timer.getTime() + 1)
end

env.info("[Core_Scoring] v1.5.2 loaded. Player unit: " .. PLAYER_NAME)
