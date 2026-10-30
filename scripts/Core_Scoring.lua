-- Core_Scoring | v1.4.4
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
function TRT.addScore(delta, reason)
    local cur = trigger.misc.getUserFlag(FLAG_SCORE)
    if type(cur) ~= "number" then cur = 0 end
    local new = cur + delta

    trigger.action.setUserFlag(FLAG_SCORE, new)
    env.info(string.format("[Core_Scoring] SCORE %+d (total %s) %s", delta, tostring(new), tostring(reason)))

    local sign = (delta >= 0) and ("+" .. tostring(delta)) or tostring(delta)
    trigger.action.outTextForCoalition(
        coalition.side.BLUE,
        string.format("%s (%s) [TOTAL %s]", tostring(reason), sign, tostring(new)),
        8, false
    )
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
local JTAC_BONUS_DELAY     = 3     -- s after the kill before counting the survivors

local function resolveEnemyScore(unitName, typeName, groupCategory, isStatic)
    local delta = UNIT_NAME_OVERRIDES[unitName]
    if delta then return delta, "name" end

    for key, val in pairs(UNIT_NAME_OVERRIDES) do
        if string.find(unitName, key, 1, true) == 1 then
            return val, "name-prefix"
        end
    end

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
end

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
        TRT.addScore(delta, "ASSET LOST: " .. name)
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
    local FUEL_GOOD_MIN_LBS  = 2500
    local FUEL_GOOD_MAX_LBS  = 3500

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

        local alt = TRT.altFt(u)
        if alt < GROOVE_ALT_MIN_FT or alt > GROOVE_ALT_MAX_FT then return end

        local spd = TRT.spdKts(u)
        if spd < GROOVE_SPD_MIN_KTS or spd > GROOVE_SPD_MAX_KTS then return end

        local lbs = fuelLbs(u)
        if not lbs then return end

        local delta, msg
        if lbs < FUEL_EMERGENCY_LBS then
            delta, msg = -8, string.format("Fuel state below recovery minimum: %.0f lbs", lbs)
        elseif lbs < FUEL_LOW_LBS then
            delta, msg = -5, string.format("Fuel state critical for recovery: %.0f lbs", lbs)
        elseif lbs >= FUEL_GOOD_MIN_LBS and lbs <= FUEL_GOOD_MAX_LBS then
            delta, msg =  5, string.format("Fuel state within recovery limits: %.0f lbs", lbs)
        end

        if delta then
            grooveDone[uname] = true
            TRT.addScore(delta, msg)
        end
    end

    local GEH = {}
    function GEH:onEvent(e)
        if e and e.id == world.event.S_EVENT_TAKEOFF and e.initiator then
            grooveDone[e.initiator:getName()] = nil
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
    local LEH = {}

    function LEH:onEvent(e)
        if not e or e.id ~= world.event.S_EVENT_LAND or not e.initiator then return end
        local unit = e.initiator
        local n = unit:getName()
        if not TARGET_UNITS[n] or LANDING_DONE[n] then return end

        local carrier = TRT.uCarrier()
        if carrier and TRT.distToCarrierNm(unit, carrier) <= TRAP_RADIUS_NM then
            LANDING_DONE[n] = true
            TRT.addScore(5, "Successful carrier landing")
            if TRT.onCarrierLanding then TRT.onCarrierLanding(n) end
            return
        end

        local place = e.place
        if place and place.getCategory and place:getCategory() == Object.Category.BASE then
            LANDING_DONE[n] = true
            TRT.addScore(2, "Successful land-based landing")
        end
    end
    world.addEventHandler(LEH)
end

----------------------------------------------------------------
-- BANKLER / TRAPTRAINER MERGE
-- Skipped for Case III - both source files hard-excluded this on
-- purpose (TrapTrainer scores an optical/visual pattern that a Case III
-- radar/GCA-style approach doesn't fly). Now driven by the LIVE case
-- flag instead of a hardcoded CASE_III_ENABLED check.
----------------------------------------------------------------
do
    local merged = false

    local function mergeBankler()
        if merged then return nil end

        local case = TRT.getCurrentCase and TRT.getCurrentCase()
        if case == 3 then
            merged = true
            return nil
        end

        if not traptrainer or not traptrainer.PlayerData then
            return timer.getTime() + 5
        end

        local b = traptrainer.PlayerData.score or 0
        if b == 0 then return timer.getTime() + 5 end

        merged = true
        TRT.addScore(b, "Bankler score merged")
        return nil
    end

    timer.scheduleFunction(mergeBankler, nil, timer.getTime() + 30)
end

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

env.info("[Core_Scoring] v1.4.1 loaded. Player unit: " .. PLAYER_NAME)
