-- Trap_Weight | v1.0.0
--[[
  Carrier bring-back weight and stores jettison (decision Onur 2026-11-07, flight 2026-11-06: JTAC-2 cleared him
  to depart with 2 GBU-12 left, he trapped with them).

  Rule (real world): unexpended ordnance is normally brought back aboard; the limit is the maximum trap weight,
  not a ban. Jettisoning weapons at sea is the exception (too costly, financially and environmentally).
  Source for the numbers: USNI Proceedings, May 1998, "Super Hornet: Sailors' Aircraft on Track": an F/A-18C "can
  trap with only 5,600 pounds of fuel, weapons, and external sensors"; with 4,000 lb of fuel reserved for the
  landing, 1,600 lb is left for stores. The figure is lot / NATOPS-edition dependent [V]; CFG.ALLOWANCE_LB.

  Measured: PAYLOAD = fuel (Unit:getFuel() x desc.fuelMassMax, external tanks included) + weapons on board
  (Unit:getAmmo(), gun shells and countermeasures not counted) + pods / external tanks from the hero's mission
  payload (CLSID table; a jettisoned tank is still counted [V]). Pylons, racks and launchers are part of the
  basic aircraft here (not "weapons and external sensors"). Masses: CFG.STORE_LB / CFG.POD_LB, unknown -> by
  category (CFG.UNKNOWN_LB) and logged "[TW] unknown store".

  Scoring (TRT.addScore):
    TRAP     S_EVENT_LAND on the carrier, first landing only: PAYLOAD > ALLOWANCE_LB
             -> PTS_OVER (-10) "Carrier landing weight: ..." (Trap & deck); within the limit: log only.
    JETTISON a drop of the store count with no S_EVENT_SHOT of that type within SHOT_MATCH_S, airborne:
             inside the jettison area and REQUIRED (stores + TRAP_FUEL_LB > ALLOWANCE_LB)   PTS_JETT_OK (+2)
             inside the jettison area, not required (the stores would have fitted)            PTS_JETT_UNNEEDED (-2)
             outside the jettison area                                                        PTS_JETT_OUT (-5)
             with a missile engagement on the hero (Missile_Defense) or TL engaged: emergency, no score.
             One booking per jettison burst (JETT_BURST_S).
    Jettison area (CFG.JETT): Mother's R-120 (magnetic) / 25 DME, radius 5 NM - open sea between the R-050
    inbound corridor and the R-196 marshal radial. Moves with the carrier. Not real-world data: the CV NATOPS /
    CVW SOP rule (position, altitude, radio calls) was not found [V].
  Whether DCS fires S_EVENT_SHOT for a selective / emergency jettison is unverified [V]: the first jettison logs
  every SHOT seen around it ("[TW] jettison check").

  Exports TRT.TW (state, payload(), last). Load after Core_Scoring (add_script.py default).
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.TW then
    env.info("[TW] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION        = "1.0.0",
    HERO           = TRT.PLAYER_NAME or "Player_01",
    CARRIER        = "CVN",
    KG2LB          = 2.20462,
    ALLOWANCE_LB   = 5600,      -- fuel + weapons + external sensors at the trap (USNI 1998, F/A-18C)
    TRAP_FUEL_LB   = 4000,      -- fuel reserved for the landing (same source) -> "required" jettison test
    PTS_OVER       = -10,
    PTS_JETT_OK    = 2,
    PTS_JETT_UNNEEDED = -2,
    PTS_JETT_OUT   = -5,
    TICK           = 1.0,       -- s
    SHOT_MATCH_S   = 4,         -- a store-count drop within this time of an S_EVENT_SHOT of that type = a release
    JETT_BURST_S   = 10,        -- drops within this window = one jettison (one booking)
    MAGVAR_E       = 5,         -- deg east (Syria / eastern Med); true = magnetic + MAGVAR_E
    JETT           = { RADIAL_MAG = 120, DME = 25, RADIUS_NM = 5 },
    -- weapon typeName (Unit:getAmmo desc.typeName) -> lb
    STORE_LB = {
        GBU_12 = 611, GBU_16 = 1092, GBU_10 = 2055, GBU_38 = 558, GBU_32 = 1013, GBU_31 = 2036,
        Mk_82 = 531, Mk_83 = 1014, Mk_84 = 2039, MK_82 = 531, MK_83 = 1014, MK_84 = 2039,
        CBU_99 = 490, Mk_20 = 490,
        AGM_65E = 645, AGM_65F = 670, AGM_65G = 670, AGM_88 = 796, AGM_88C = 796,
        AGM_154A = 1065, AGM_154C = 1065, AGM_84D = 1145, AGM_84E = 1385, AGM_84H = 1490,
        AIM_9 = 190, AIM_9M = 190, AIM_9X = 186, ["AIM-9L"] = 190, AIM_120 = 345, AIM_120C = 356, AIM_7 = 510,
    },
    UNKNOWN_LB = { bomb = 600, missile = 400, rocket = 25, other = 300 },
    -- payload CLSID -> lb (pods; external tanks EMPTY - their fuel is in getFuel())
    POD_LB = {
        ["{AN_ASQ_228}"]       = 420,   -- AN/ASQ-228 ATFLIR
        ["{FPU_8A_FUEL_TANK}"] = 290,   -- FPU-8A 330 gal tank, empty [V]
    },
}

local TW = { version = CFG.VERSION, CFG = CFG, last = nil, trapDone = false, jetts = {} }
TRT.TW = TW

local function log(s) env.info("[TW] " .. s) end
local function now() return timer.getTime() end
local function safe(f, ...) local ok, v = pcall(f, ...); if ok then return v end return nil end

local function hero()
    local u = Unit.getByName(CFG.HERO)
    if u and u:isExist() then return u end
    return nil
end

local function isShell(d)
    if not d then return true end
    if d.category == 0 then return true end                                -- Weapon.Category.SHELL
    local n = tostring(d.typeName or ""):lower()
    return n:find("chaff") or n:find("flare") or false
end

local unknownLogged = {}
local function storeLb(d)
    local n = tostring(d.typeName or "?")
    local lb = CFG.STORE_LB[n]
    if lb then return lb end
    local c = d.category
    local k = (c == 3 and "bomb") or (c == 1 and "missile") or (c == 2 and "rocket") or "other"
    if not unknownLogged[n] then
        unknownLogged[n] = true
        log(string.format("unknown store %s (category %s) -> %d lb (CFG.STORE_LB)", n, tostring(c), CFG.UNKNOWN_LB[k]))
    end
    return CFG.UNKNOWN_LB[k]
end

-- pods / tanks from the hero's mission payload (static: read once)
local POD = nil
local function podsLb()
    if POD then return POD.lb end
    POD = { lb = 0, list = {} }
    local function walk(t, depth)
        if type(t) ~= "table" or depth > 12 then return nil end
        if t.name == CFG.HERO and type(t.payload) == "table" then return t end
        for _, v in pairs(t) do
            local r = walk(v, depth + 1)
            if r then return r end
        end
        return nil
    end
    local u = env.mission and walk(env.mission.coalition, 0)
    local py = u and u.payload and u.payload.pylons
    if type(py) == "table" then
        for st, p in pairs(py) do
            local lb = p and p.CLSID and CFG.POD_LB[p.CLSID]
            if lb then
                POD.lb = POD.lb + lb
                POD.list[#POD.list + 1] = string.format("st%s %s %d", tostring(st), p.CLSID, lb)
            end
        end
    end
    log("pods / tanks from the payload: " .. ((#POD.list > 0) and table.concat(POD.list, ", ") or "none")
        .. string.format(" = %d lb", POD.lb))
    return POD.lb
end

local function stores(u)
    local ammo = safe(u.getAmmo, u) or {}
    local lb, counts, parts = 0, {}, {}
    for _, a in ipairs(ammo) do
        local d = a.desc
        if d and not isShell(d) then
            local n, c = tostring(d.typeName or "?"), a.count or 0
            local m = storeLb(d)
            lb = lb + m * c
            counts[n] = (counts[n] or 0) + c
            parts[#parts + 1] = string.format("%dx %s", c, n)
        end
    end
    return lb, counts, parts
end

local function fuelLb(u)
    local f = safe(u.getFuel, u) or 0
    local d = safe(u.getDesc, u) or {}
    local maxKg = d.fuelMassMax or 4900
    return f * maxKg * CFG.KG2LB
end

--- payload table: { total, fuel, weapons, pods, parts }
function TW.payload(u)
    u = u or hero()
    if not u then return nil end
    local w, _, parts = stores(u)
    local p = podsLb()
    local f = fuelLb(u)
    return { total = f + w + p, fuel = f, weapons = w, pods = p, parts = parts }
end

local function fmtP(P)
    return string.format("payload %.0f lb = fuel %.0f + weapons %.0f (%s) + pods/tanks %.0f; limit %d",
        P.total, P.fuel, P.weapons, (#P.parts > 0) and table.concat(P.parts, ", ") or "none", P.pods, CFG.ALLOWANCE_LB)
end

-- ── jettison area ────────────────────────────────────────────────
local function carrierPos()
    local c = Unit.getByName(CFG.CARRIER)
    return c and c:isExist() and safe(c.getPoint, c) or nil
end

local function radialDme(p)
    local c = carrierPos()
    if not (c and p) then return nil end
    local dx, dz = p.x - c.x, p.z - c.z
    local tr = math.deg(math.atan2(dz, dx)) % 360
    return (tr - CFG.MAGVAR_E) % 360, math.sqrt(dx * dx + dz * dz) / 1852
end

local function inJettArea(p)
    local c = carrierPos()
    if not (c and p) then return false, nil end
    local J = CFG.JETT
    local tb = math.rad(J.RADIAL_MAG + CFG.MAGVAR_E)
    local ax, az = c.x + J.DME * 1852 * math.cos(tb), c.z + J.DME * 1852 * math.sin(tb)
    local d = math.sqrt((p.x - ax) ^ 2 + (p.z - az) ^ 2) / 1852
    return d <= J.RADIUS_NM, d
end
TW.inJettArea = inJettArea

local function underThreat()
    local MD = TRT.MD
    if MD and type(MD.eng) == "table" then
        for _, eg in pairs(MD.eng) do
            if (eg.live or 0) > 0 or (eg.t0 and now() - eg.t0 < 60) then return "missile engagement" end
        end
    end
    if TRT.TL and TRT.TL.engaged then return "engaged" end
    return nil
end

-- ── state ────────────────────────────────────────────────────────
local S = { counts = nil, shots = {}, burst = nil, shotLog = {} }

local function onShot(e)
    local w = e.weapon
    local d = w and safe(w.getDesc, w)
    local n = d and tostring(d.typeName or "?") or "?"
    S.shots[#S.shots + 1] = { n = n, t = now(), used = false }
    S.shotLog[#S.shotLog + 1] = string.format("%.1f %s", now(), n)
    if #S.shotLog > 20 then table.remove(S.shotLog, 1) end
end

local function takeShot(n)
    for _, s in ipairs(S.shots) do
        if not s.used and s.n == n and now() - s.t <= CFG.SHOT_MATCH_S then s.used = true; return true end
    end
    return false
end

local function book(B)
    local u = hero()
    local p = u and safe(u.getPoint, u)
    local rad, dme = radialDme(p)
    local inside, dA = inJettArea(p)
    local stLb = B.before                                                   -- weapons + pods before the burst
    local need = stLb + CFG.TRAP_FUEL_LB > CFG.ALLOWANCE_LB
    local thr = underThreat()
    local where = (rad and string.format("R-%03d/%.0f DME", math.floor(rad + 0.5), dme)) or "position n/a"
    local what = table.concat(B.items, ", ")
    local pts, txt
    if thr then
        pts, txt = 0, "emergency (" .. thr .. ")"
    elseif not inside then
        pts, txt = CFG.PTS_JETT_OUT, string.format("Jettison outside the jettison area: %s at %s (area R-%03d/%d, %d NM)",
            what, where, CFG.JETT.RADIAL_MAG, CFG.JETT.DME, CFG.JETT.RADIUS_NM)
    elseif need then
        pts, txt = CFG.PTS_JETT_OK, string.format("Jettison in the jettison area: %s (stores %.0f + %d fuel > %d)",
            what, stLb, CFG.TRAP_FUEL_LB, CFG.ALLOWANCE_LB)
    else
        pts, txt = CFG.PTS_JETT_UNNEEDED, string.format("Jettison not required: %s (stores %.0f + %d fuel <= %d)",
            what, stLb, CFG.TRAP_FUEL_LB, CFG.ALLOWANCE_LB)
    end
    log(string.format("JETTISON %s at %s (area %s, %.1f NM from its centre), stores before %.0f lb, required %s -> %+d %s",
        what, where, inside and "inside" or "outside", dA or -1, stLb, tostring(need), pts, txt))
    log("jettison check: SHOT events seen before it: " .. ((#S.shotLog > 0) and table.concat(S.shotLog, " | ") or "none"))
    TW.jetts[#TW.jetts + 1] = { what = what, where = where, inside = inside, need = need, pts = pts }
    if pts ~= 0 and TRT.addScore then TRT.addScore(pts, txt) end
end

local function tick()
    local u = hero()
    if not u then S.counts = nil; return end
    local air = safe(u.inAir, u)
    local w, counts = stores(u)
    if S.counts and air then
        for n, c0 in pairs(S.counts) do
            local drop = c0 - (counts[n] or 0)
            for _ = 1, math.max(0, drop) do
                if not takeShot(n) then
                    if not S.burst then
                        S.burst = { t = now(), items = {}, before = S.wLb + podsLb() }
                    end
                    S.burst.items[#S.burst.items + 1] = n
                end
            end
        end
    end
    if S.burst and now() - S.burst.t >= CFG.JETT_BURST_S then
        local B = S.burst
        S.burst = nil
        local agg = {}
        for _, n in ipairs(B.items) do agg[n] = (agg[n] or 0) + 1 end
        B.items = {}
        for n, c in pairs(agg) do B.items[#B.items + 1] = c .. "x " .. n end
        book(B)
    end
    S.counts, S.wLb = counts, w
    -- drop old shots
    local keep = {}
    for _, s in ipairs(S.shots) do if now() - s.t <= 30 then keep[#keep + 1] = s end end
    S.shots = keep
end

local function onLand(e)
    if TW.trapDone then return end
    local place = e.place
    local pn = place and safe(place.getName, place)
    local onCv = pn == CFG.CARRIER
    if not onCv then
        local u, c = hero(), carrierPos()
        local p = u and safe(u.getPoint, u)
        onCv = c and p and math.sqrt((p.x - c.x) ^ 2 + (p.z - c.z) ^ 2) < 500 or false
    end
    if not onCv then return end
    TW.trapDone = true
    local P = TW.payload()
    if not P then return end
    TW.last = P
    local over = P.total - CFG.ALLOWANCE_LB
    log(string.format("TRAP %s -> %s", fmtP(P), (over > 0) and string.format("OVER by %.0f lb", over) or "within"))
    if over > 0 and TRT.addScore then
        TRT.addScore(CFG.PTS_OVER, string.format("Carrier landing weight: %.0f lb over the bring-back limit (%.0f / %d lb)",
            over, P.total, CFG.ALLOWANCE_LB))
    end
end

local EH = {}
function EH:onEvent(e)
    if not e or not e.initiator then return end
    local n = safe(e.initiator.getName, e.initiator)
    if n ~= CFG.HERO then return end
    local ok, err = pcall(function()
        if e.id == world.event.S_EVENT_SHOT then onShot(e)
        elseif e.id == world.event.S_EVENT_LAND then onLand(e)
        elseif e.id == world.event.S_EVENT_BIRTH then
            TW.trapDone, S.counts, S.burst, S.shots = false, nil, nil, {}
        end
    end)
    if not ok then log("event error: " .. tostring(err)) end
end
world.addEventHandler(EH)

timer.scheduleFunction(function(_, t)
    local ok, err = pcall(tick)
    if not ok then log("tick error: " .. tostring(err)) end
    return t + CFG.TICK
end, nil, now() + 5)

timer.scheduleFunction(function()
    local P = TW.payload()
    if P then log("start " .. fmtP(P)) end
end, nil, now() + 8)

log(string.format("Trap_Weight v%s loaded (hero %s, limit %d lb, jettison area R-%03d/%d DME r %d NM)",
    CFG.VERSION, CFG.HERO, CFG.ALLOWANCE_LB, CFG.JETT.RADIAL_MAG, CFG.JETT.DME, CFG.JETT.RADIUS_NM))
