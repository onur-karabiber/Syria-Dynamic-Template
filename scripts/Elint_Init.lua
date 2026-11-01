-- Elint_Init | v1.0.1
-- v1.0.1: load-order note only (tools/add_elint.py puts both files at the end of OWN_SCRIPTS). No code change.
--[[
  Hound ELINT bootstrap — TRT Syria Dynamic Template (template-level module)

  Hound (scripts/HoundElint_0.5.2.lua, vendored unchanged) is used as an engine only:
  detection, triangulation, F10 map markers. Hound's own radio menu, controller,
  ATIS and notifier are NOT enabled: voice needs SRS (not used), and the text
  controller would add a second F10 root next to Menu_Manager's.

  What the player gets:
    * F10 map markers for every radar Hound has located (CFG.MARKER, default CIRCLE:
      per-radar uncertainty circle + site marker). A site that stops emitting stays
      on the map; after HOUND.CONTACT_TIMEOUT (900 s) silent, its marker fades.
    * F10 > INFO > "Show: ELINT picture": the CFG.LIST_MAX nearest located sites from
      the hero with magnetic bearing/range, lat/lon (DDM, for the UFC), ground
      elevation at the estimate, uncertainty and age.
    * One line to the hero when a new site gets a position (CFG.NOTIFY).

  Detection rule is Hound's: only radars that emit (unit:getRadar()) are heard.
  Skynet-dark sites stay unknown until they light up; an ambush site that has
  engaged once is located and stays on the map (decision 2026-11-01).

  Platforms (CFG.PLATFORMS): ME static towers ("Comms tower M" or "TV tower", BLUE
  country) named ELINT_TWR_n, plus OVERLORD-1-1 (E-2C). A name that is not in the
  mission is skipped and retried every CFG.RETRY_S (late activation / spawns), so a
  scenario can delete any of them. E-2C cannot resolve the low-band EWRs (55G6 /
  1L13: base error > 10 deg, Hound drops the bearing); the towers can. A single
  static platform gives a bearing only (no position), so fixing the EWRs needs
  BOTH towers in LOS of them (headless test 2026-11-01: one tower + E-2C located
  the SA-6 and SA-3, never the 55G6).

  Startup audit (CFG.AUDIT): per platform, which non-BLUE radar units are in LOS
  with a usable bearing — Hound's own HOUND.Utils.Geo.checkLOS and the < 10 deg
  precision gate of HOUND.ElintWorker:_sampleRadars, search-mode wavelength.
  Site survey (CFG.SURVEY.ENABLED): the same test from a grid around candidate
  points, without placing statics; logs the best point per candidate. Run it once
  to choose tower sites, then switch it off. Antenna height note: Hound puts a
  static platform's antenna at ground + 1.5 x its hitbox height (getPlatformData:
  +box/2 for statics, then +box again for every non-aerial platform). The audit
  line prints that height for each real tower; copy it into CFG.SURVEY.ANT_M.

  Load order (ME): HoundElint_0.5.2.lua anywhere before Elint_Init.lua; Elint_Init.lua after
  Menu_Manager. tools/add_elint.py appends both, in that order, to trigger "OWN_SCRIPTS".
  API: TRT.ELINT = { version, CFG, hound, picture() }
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.ELINT then
    env.info("[ELINT] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION         = "1.0.1",
    COALITION       = coalition.side.BLUE,
    PLAYER_UNIT     = "Player_01",
    PLATFORMS       = { "ELINT_TWR_1", "ELINT_TWR_2", "OVERLORD-1-1" },
    PREBRIEFED      = {},          -- group names intel already knows at start (exact position),
                                   -- e.g. { "SAM YD67 (SA-10)-1" }; optional code name: { "GROUP", "NAME" }
    MARKER          = "CIRCLE",    -- HOUND.MARKER key: NONE / SITE_ONLY / POINT / CIRCLE / DIAMOND ...
    MARKER_S        = 120,         -- marker refresh (Hound default 120)
    HOUND_LOG       = "warning",   -- Hound's own dcs.log level: error / warning / info / debug
    MAGVAR          = 5,           -- east; magnetic = true - MAGVAR (same as JTAC_Controller / Comms_Director)
    MENU_ORDER      = 30,          -- INFO section, below FA (12) / CD (20)
    LIST_MAX        = 8,
    PICTURE_DUR     = 30,
    LIVE_S          = 60,          -- "live" if heard within this many seconds
    NOTIFY          = true,
    NOTIFY_DUR      = 8,
    RETRY_S         = 30,          -- retry missing platforms
    AUDIT           = true,
    AUDIT_DELAY     = 5,
    SURVEY = {
        ENABLED = false,
        TYPE    = "Comms tower M", -- aperture taken from Hound's platform DB for this static type
        ANT_M   = 60,              -- antenna height above ground (see header note)
        GRID    = 7,               -- GRID x GRID points per candidate
        STEP_M  = 1500,
        TICK    = 0.1,             -- one grid point per tick
        -- lat/lon are approximate; the grid search and the logged ground elevation correct them
        POINTS  = {
            { name = "KELDAG",   lat = 35.952, lon = 35.969 },  -- Jebel Aqra, border summit over Latakia
            { name = "AMANOS",   lat = 36.560, lon = 36.270 },  -- Nur Daglari ridge east of Iskenderun
            { name = "KILIS",    lat = 36.720, lon = 37.120 },  -- plateau north of Aleppo
            { name = "BOZYAZI",  lat = 36.150, lon = 33.000 },  -- Taurus coast facing northern Cyprus
        },
    },
}

local E = { version = CFG.VERSION, CFG = CFG }
TRT.ELINT = E

local function Log(s) env.info("[ELINT] " .. s) end

if type(HoundElint) ~= "table" or type(HOUND) ~= "table" then
    Log("Hound not loaded (HoundElint_0.5.2.lua must load before Elint_Init.lua) - module off")
    return
end

-- ══════════════════════════════════════════════════════════════
--  UTILITIES
-- ══════════════════════════════════════════════════════════════
local function Hero()
    local u = Unit.getByName(CFG.PLAYER_UNIT)
    if u and u:isExist() then return u end
end
local function D2(a, b) local dx, dz = a.x - b.x, a.z - b.z return math.sqrt(dx * dx + dz * dz) end
local function BrgT(a, b) return math.deg(math.atan2(b.z - a.z, b.x - a.x)) % 360 end
local function Mag(t) return (t - CFG.MAGVAR) % 360 end
local function GroundM(p)
    local ok, h = pcall(land.getHeight, { x = p.x, y = p.z })
    return ok and h or 0
end

local function DDM(v, pos, neg, dw)
    local h = v >= 0 and pos or neg
    v = math.abs(v)
    local d = math.floor(v)
    local m = (v - d) * 60
    if m >= 59.995 then d, m = d + 1, 0 end
    return string.format("%s%0" .. dw .. "d %05.2f", h, d, m)
end
local function LLText(p)
    local ok, lat, lon = pcall(coord.LOtoLL, p)
    if not ok or not lat then return "LL ?" end
    return DDM(lat, "N", "S", 2) .. " " .. DDM(lon, "E", "W", 3)
end

local function Msg(text, dur)
    if TRT.Menu and TRT.Menu.Msg then
        TRT.Menu.Msg(text, dur)
    else
        local u = Hero()
        if u then trigger.action.outTextForGroup(u:getGroup():getID(), text, dur or 10) end
    end
end

-- Hound's NATO designation strips "SA-" ("SA-6 or SA-11" -> "6 or 11"); put it back
local function TypeLabel(t)
    t = tostring(t or "?")
    if t:match("^%d") then
        local s = ("SA-" .. t):gsub(" or (%d)", " or SA-%1")
        return s
    end
    return t
end

local function SafeName(obj)
    local ok, n = pcall(function() return obj:getName() end)
    return ok and tostring(n) or "?"
end

-- ══════════════════════════════════════════════════════════════
--  HOUND INSTANCE
-- ══════════════════════════════════════════════════════════════
if HOUND.Logger and HOUND.Logger.setBaseLevel and HOUND.Logger.LEVEL and HOUND.Logger.LEVEL[CFG.HOUND_LOG] then
    HOUND.Logger.setBaseLevel(HOUND.Logger.LEVEL[CFG.HOUND_LOG])
end

local H = HoundElint:create(CFG.COALITION)
if not H then
    Log("HoundElint:create failed - module off")
    return
end
E.hound = H

if HOUND.MARKER[CFG.MARKER] ~= nil then
    H:setMarkerType(HOUND.MARKER[CFG.MARKER])
else
    Log("unknown CFG.MARKER '" .. tostring(CFG.MARKER) .. "' - Hound default kept")
end
H:setTimerInterval("markers", CFG.MARKER_S)
H:setAlertOnLaunch(false)

-- platforms -------------------------------------------------------------------
local added, pending = {}, {}

local function TryAdd(name)
    local u = Unit.getByName(name)
    local obj = u or StaticObject.getByName(name)
    if not obj or not obj:isExist() then return nil, "not in mission" end
    if u and not u:isActive() then return nil, "not active yet" end
    if H:addPlatform(name) then return obj end
    return nil, string.format("rejected by Hound (type %s, coalition %s)", tostring(obj:getTypeName()), tostring(obj:getCoalition()))
end

for _, name in ipairs(CFG.PLATFORMS) do
    local obj, why = TryAdd(name)
    if obj then
        added[name] = true
        Log("platform " .. name .. " (" .. obj:getTypeName() .. ")")
    else
        pending[name] = true
        Log("platform " .. name .. " " .. why .. " - retry every " .. CFG.RETRY_S .. " s")
    end
end

if next(pending) then
    timer.scheduleFunction(function(_, t)
        for name in pairs(pending) do
            local ok, obj = pcall(TryAdd, name)
            if ok and obj then
                pending[name], added[name] = nil, true
                Log("platform " .. name .. " (" .. obj:getTypeName() .. ") added late")
            end
        end
        if next(pending) then return t + CFG.RETRY_S end
        return nil
    end, nil, timer.getTime() + CFG.RETRY_S)
end

-- pre-briefed contacts ----------------------------------------------------------
for _, pb in ipairs(CFG.PREBRIEFED) do
    local grp, code = pb, nil
    if type(pb) == "table" then grp, code = pb[1], pb[2] end
    local ok, err = pcall(H.preBriefedContact, H, grp, code)
    Log("pre-briefed " .. tostring(grp) .. (ok and "" or (" FAILED: " .. tostring(err))))
end

H:systemOn(false)

-- ══════════════════════════════════════════════════════════════
--  EVENTS (log + one-line notice)
-- ══════════════════════════════════════════════════════════════
local EV = HOUND.EVENTS
local EV_LOG = {
    [EV.SITE_CREATED]       = "site located",
    [EV.SITE_CLASSIFIED]    = "site classified",
    [EV.SITE_ASLEEP]        = "site asleep",
    [EV.SITE_ALIVE]         = "site alive",
    [EV.SITE_REMOVED]       = "site removed",
    [EV.RADAR_DESTROYED]    = "radar destroyed",
    [EV.PLATFORM_DESTROYED] = "PLATFORM DESTROYED",
    [EV.PLATFORM_REMOVED]   = "platform removed",
}

local function SiteSummary(site)
    local ok, s = pcall(function()
        local txt = TypeLabel(site:getDesignation(true)) .. " " .. site:getName()
        local hero = Hero()
        local p = site:getPos()
        if hero and p and p.x then
            local hp = hero:getPoint()
            txt = txt .. string.format(", %03d/%d NM", math.floor(Mag(BrgT(hp, p)) + 0.5) % 360,
                math.floor(D2(hp, p) / 1852 + 0.5))
        end
        return txt
    end)
    return ok and s or SafeName(site)
end

-- Hound dispatches subscriber events synchronously from inside its Process step:
-- an error here would abort Hound's cycle, so everything runs under pcall.
local function OnEvent(ev)
    if type(ev) ~= "table" or ev.houndId ~= H:getId() then return end
    local what = EV_LOG[ev.id]
    if not what then return end
    local isPlatform = (ev.id == EV.PLATFORM_DESTROYED or ev.id == EV.PLATFORM_REMOVED)
    local label = isPlatform and SafeName(ev.initiator) or SiteSummary(ev.initiator)
    Log(what .. ": " .. label)
    if CFG.NOTIFY and ev.id == EV.SITE_CREATED then
        Msg("ELINT: new emitter site " .. label .. "  (F10 > INFO > Show: ELINT picture)", CFG.NOTIFY_DUR)
    end
end

local Handler = {}
function Handler:onHoundEvent(ev)
    local ok, err = pcall(OnEvent, ev)
    if not ok then Log("event handler error: " .. tostring(err)) end
end
HOUND.addEventHandler(Handler)

-- ══════════════════════════════════════════════════════════════
--  PICTURE (F10 > INFO)
-- ══════════════════════════════════════════════════════════════
function E.picture()
    local okS, sites = pcall(H.getSites, H)
    local nPlat = 0
    pcall(function() nPlat = H:countPlatforms() end)
    if not okS or type(sites) ~= "table" then
        Log("getSites failed: " .. tostring(sites))
        return "ELINT: picture unavailable (see dcs.log)"
    end
    local hero = Hero()
    local hp = hero and hero:getPoint()
    local now = timer.getAbsTime()
    local rows = {}
    for _, kind in ipairs({ "sam", "ewr" }) do
        local list = sites[kind] and sites[kind].sites or {}
        for _, s in ipairs(list) do
            local em
            for _, e in ipairs(s.emitters or {}) do
                if e.pos and e.pos.x then em = e break end
            end
            if em then rows[#rows + 1] = { s = s, e = em, d = hp and D2(hp, em.pos) or 0 } end
        end
    end
    if #rows == 0 then
        if nPlat == 0 then return "ELINT: no platform up - no picture" end
        return string.format("ELINT: %d platform(s) up, no emitter located yet", nPlat)
    end
    table.sort(rows, function(a, b) return a.d < b.d end)

    local out = { string.format("ELINT PICTURE  %d platform(s) | %d site(s) located%s", nPlat, #rows,
        hp and "" or " | bearings n/a (hero not in jet)") }
    for i = 1, math.min(#rows, CFG.LIST_MAX) do
        local r = rows[i]
        local p = r.e.pos
        local where = hp and string.format("%03d/%3d NM", math.floor(Mag(BrgT(hp, p)) + 0.5) % 360,
            math.floor(r.d / 1852 + 0.5)) or "---/---"
        -- Hound's uncertainty "major" is the full ellipse axis (Estimator: major * 2), so +- is half of it
        local unc = (r.e.uncertenty and r.e.uncertenty.major) and string.format("+-%.1f NM", r.e.uncertenty.major / 2 / 1852)
            or tostring(r.e.accuracy or "")
        local age = r.s.last_seen and (now - r.s.last_seen) or nil
        local ageTxt = (age == nil) and "" or ((age <= CFG.LIVE_S) and "LIVE" or string.format("%d min ago", math.floor(age / 60)))
        out[#out + 1] = string.format("%-6s %-5s %s  %s  %5d ft  %s  %s",
            TypeLabel(r.s.Type), tostring(r.s.name), where, LLText(p),
            math.floor(GroundM(p) * 3.28084 + 0.5), unc, ageTxt)
    end
    if #rows > CFG.LIST_MAX then
        out[#out + 1] = string.format("(+%d more on the F10 map)", #rows - CFG.LIST_MAX)
    end
    return table.concat(out, "\n")
end

if TRT.Menu and TRT.Menu.Register then
    TRT.Menu.Register("INFO", "ELINT", function()
        return { { "Show: ELINT picture", function() Msg(E.picture(), CFG.PICTURE_DUR) end } }
    end, CFG.MENU_ORDER)
else
    Log("TRT.Menu missing (Menu_Manager not loaded) - no F10 item")
end

-- ══════════════════════════════════════════════════════════════
--  AUDIT / SURVEY (dcs.log only)
-- ══════════════════════════════════════════════════════════════
local MAX_RAD = math.rad(10)

local function RadarUnits()
    local list, groups = {}, {}
    for _, side in pairs(coalition.side) do
        if side ~= CFG.COALITION then
            for _, cat in ipairs({ Group.Category.GROUND, Group.Category.SHIP }) do
                for _, g in ipairs(coalition.getGroups(side, cat) or {}) do
                    for _, u in ipairs(g:getUnits() or {}) do
                        local db = u and u:isExist() and HOUND.DB.Radars[u:getTypeName()]
                        if db and db.Band and db.Band[false] then
                            local p = u:getPosition().p
                            local box = u:getDesc().box
                            local b = db.Band[false]
                            list[#list + 1] = {
                                g  = g:getName(),
                                wl = b[1] + b[2] * 0.5,          -- search-mode wavelength, mid band
                                p  = { x = p.x, y = p.y + ((box and box.max and box.max.y) or 0), z = p.z },
                            }
                            groups[g:getName()] = true
                        end
                    end
                end
            end
        end
    end
    local ng = 0
    for _ in pairs(groups) do ng = ng + 1 end
    return list, ng
end

-- covered units / covered group set from one antenna position
local function Coverage(pos, aperture, radars)
    local n, gs = 0, {}
    if not aperture or aperture <= 0 then return 0, gs end
    for _, r in ipairs(radars) do
        if (r.wl / aperture) < MAX_RAD and HOUND.Utils.Geo.checkLOS(pos, r.p) then
            n = n + 1
            gs[r.g] = true
        end
    end
    return n, gs
end

local function Count(set) local n = 0 for _ in pairs(set) do n = n + 1 end return n end

local function Audit()
    local radars, ng = RadarUnits()
    local hits = {}        -- group -> number of platforms that hear it
    for name in pairs(added) do
        local obj = Unit.getByName(name) or StaticObject.getByName(name)
        local pd = obj and HOUND.DB.getPlatformData(obj)
        if pd then
            local ap = HOUND.DB.getApertureSize(obj)
            local n, gs = Coverage(pd.pos, ap, radars)
            for g in pairs(gs) do hits[g] = (hits[g] or 0) + 1 end
            Log(string.format("AUDIT %s (%s%s): ground %d m, antenna +%d m, %s | %d/%d radar units, %d/%d groups",
                name, obj:getTypeName(), pd.isAerial and ", aircraft: position at audit time" or "",
                math.floor(GroundM(pd.pos) + 0.5), math.floor(pd.pos.y - GroundM(pd.pos) + 0.5),
                LLText(pd.pos), n, #radars, Count(gs), ng))
        end
    end
    -- a fix needs two bearings: two platforms, or one aircraft that moves (not judged here)
    local none, single, seen = {}, {}, {}
    local two = 0
    for _, r in ipairs(radars) do
        if not seen[r.g] then
            seen[r.g] = true
            local h = hits[r.g] or 0
            if h == 0 then none[#none + 1] = r.g
            elseif h == 1 then single[#single + 1] = r.g
            else two = two + 1 end
        end
    end
    table.sort(none)
    table.sort(single)
    Log(string.format("AUDIT union: %d/%d radar groups heard by >= 2 platforms, %d by one only (bearing only unless that one is a moving aircraft), %d by none",
        two, ng, #single, #none))
    local function Dump(tag, list)
        for i = 1, #list, 10 do
            local chunk = {}
            for j = i, math.min(i + 9, #list) do chunk[#chunk + 1] = list[j] end
            Log("AUDIT " .. tag .. ": " .. table.concat(chunk, " | "))
        end
    end
    Dump("one platform only", single)
    Dump("not covered", none)
end

local function Survey()
    local S = CFG.SURVEY
    local db = HOUND.DB.Platform[Object.Category.STATIC] and HOUND.DB.Platform[Object.Category.STATIC][S.TYPE]
    if not db then Log("SURVEY: '" .. tostring(S.TYPE) .. "' is not a Hound static platform - off") return end
    local aperture = db.antenna.size * db.antenna.factor * (HOUND.ANTENNA_FACTOR or 1)
    local radars, ng = RadarUnits()
    local jobs = {}
    local half = (S.GRID - 1) / 2
    for _, c in ipairs(S.POINTS) do
        local ok, ctr = pcall(coord.LLtoLO, c.lat, c.lon, 0)
        if ok and ctr then
            for i = -half, half do
                for j = -half, half do
                    jobs[#jobs + 1] = { c = c, x = ctr.x + i * S.STEP_M, z = ctr.z + j * S.STEP_M, centre = (i == 0 and j == 0) }
                end
            end
        end
    end
    Log(string.format("SURVEY start: %d points, type %s (aperture %d m), antenna +%d m, %d radar units in %d groups",
        #jobs, S.TYPE, aperture, S.ANT_M, #radars, ng))
    local best, centre, k = {}, {}, 0
    local function Report(c)
        local b, m = best[c.name], centre[c.name]
        if not b then return end
        Log(string.format("SURVEY %s best %s ground %d m: %d/%d units, %d/%d groups (given point: %s)",
            c.name, LLText(b.p), math.floor(b.p.y - S.ANT_M + 0.5), b.n, #radars, b.ng, ng,
            m and string.format("%d units, %d groups, ground %d m", m.n, m.ng, math.floor(m.p.y - S.ANT_M + 0.5)) or "?"))
    end
    timer.scheduleFunction(function(_, t)
        k = k + 1
        local job = jobs[k]
        if not job then return nil end
        local ok, err = pcall(function()
            local p = { x = job.x, z = job.z }
            p.y = GroundM(p) + S.ANT_M
            local n, gs = Coverage(p, aperture, radars)
            local rec = { p = p, n = n, ng = Count(gs) }
            local cur = best[job.c.name]
            if not cur or rec.ng > cur.ng or (rec.ng == cur.ng and rec.n > cur.n) then best[job.c.name] = rec end
            if job.centre then centre[job.c.name] = rec end
        end)
        if not ok then Log("SURVEY point error: " .. tostring(err)) end
        local nxt = jobs[k + 1]
        if not nxt or nxt.c ~= job.c then Report(job.c) end
        if not nxt then Log("SURVEY done") return nil end
        return t + S.TICK
    end, nil, timer.getTime() + 1)
end

if CFG.AUDIT then
    timer.scheduleFunction(function()
        local ok, err = pcall(Audit)
        if not ok then Log("AUDIT error: " .. tostring(err)) end
        if CFG.SURVEY.ENABLED then
            local ok2, err2 = pcall(Survey)
            if not ok2 then Log("SURVEY error: " .. tostring(err2)) end
        end
    end, nil, timer.getTime() + CFG.AUDIT_DELAY)
elseif CFG.SURVEY.ENABLED then
    timer.scheduleFunction(function()
        local ok, err = pcall(Survey)
        if not ok then Log("SURVEY error: " .. tostring(err)) end
    end, nil, timer.getTime() + CFG.AUDIT_DELAY)
end

local nAdded = 0
for _ in pairs(added) do nAdded = nAdded + 1 end
Log(string.format("Elint_Init v%s online (Hound %s, %d platform(s) up, marker %s, survey %s)",
    CFG.VERSION, tostring(HOUND.VERSION), nAdded, tostring(CFG.MARKER), CFG.SURVEY.ENABLED and "ON" or "off"))
