-- Tasking_Pick | v1.3.0
--[[
  v1.3.0 - JTAC roster (P3, CAS_PACK >= v1.3.0 with four JTACs): CAS_PACK.tasked = the sortie's two taskings
           (written here when the pack has none: the first two of CAS_PACK.order; P4 will draw them). The weapons
           check counts only the tasked JTACs; every JTAC with a pool still gets its pick (its world stays
           consistent). Forced-pick flags J3 223 / J4 224. A pool with one weighted entry is picked without a
           math.random draw (the later modules see the same random sequence whatever the roster size).
  v1.2.0 - effects-based tasking: the picked entry's objective goes into the pack (jtacs[k].objective); weapons
           check before anything is activated: the objectives of all picked entries together <= loadout MAV + LGB - 2
           (one spare per type, decision Onur 2026-11-04), random picks re-drawn up to CFG.TRIES times ("[PICK]
           weapons check" line); forced picks (flags) are kept even when over.
  v1.1.0 - audit mode (ME flag 221 > 0, tools/make_test_variant.py --audit): the site check runs for EVERY pool entry
           of every JTAC (not only the picked one), and JTAC_Controller (>= v0.14.2) runs its post search dry for every
           entry ("[JC] AUDIT ..."). One mission load audits the whole pool. TRT.PICK.audit, TRT.PICK.meUnits(name).
  CAS-1 target pool pick (B3, decisions Onur 2026-11-04: ME late-activated groups, sets B + C per JTAC; plan
  claude/target-pool-tasking-pack-plan-2026-11-04.md).
  Runs once at load, right after CAS_Pack.lua in the MOOSE trigger, i.e. BEFORE Skynet init and before every
  reader of the pack (Comms_Director, JTAC_Controller, Core_Scoring through TRT.JC.CFG):
    * per JTAC with CAS_PACK.jtacs[k].pool: picks one entry - ME flag CFG.FLAG[k] = 1..n forces entry n (tests,
      tools/make_test_variant.py --pick), otherwise weighted random over the entries with w > 0
    * writes the pick into the pack: jtacs[k].targets, .ord (if the entry has one), .pick, .pick_name,
      .tgt_fallback (target group centre from env.mission)
    * activates the picked entry's late-activated groups; destroys the groups / statics of every entry NOT
      picked that are active at start (set A, the always-present SHORAD sites) - before Skynet sees them
    * site check of the picked entry (dcs.log, "[PICK] site"): surface type, slope over +/-10 m, scenery
      objects within 12 m of every unit. The terrain under the tool-placed sets was not known when they were
      placed (tools/add_pool_sets.py): a CHECK line means the set should be moved before its weight goes > 0.
  Randomness [V]: DCS is reported to seed math.random before the mission runs (cfrag, forum.dcs.world topic
  319829); others reported repeats. The first math.random value is logged ("[PICK] rng") - identical values over
  several mission starts mean the ME RANDOM condition has to supply the entropy instead.
  API: TRT.PICK = { J1 = { idx, id, name, forced }, ... }
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.PICK then env.info("[PICK] already loaded, second copy ignored") return end

local CFG = {
    VERSION   = "1.3.0",
    TRIES     = 20,                       -- v1.2.0 re-draws for the weapons check
    AUDIT_FLAG = 221,                     -- v1.1.0 > 0: audit every pool entry
    FLAG      = { J1 = 217, J2 = 219, J3 = 223, J4 = 224 },   -- forced entry index (0 = random)
    SLOPE_MAX = 12,                       -- deg; steeper -> CHECK
    SCENERY_R = 12,                       -- m
}

local P = _G.CAS_PACK
local function Log(s) env.info("[PICK] " .. s) end
if type(P) ~= "table" or type(P.jtacs) ~= "table" then
    env.error("[PICK] CAS_PACK missing (Do Script File CAS_Pack.lua before Tasking_Pick.lua) - no pick")
    return
end

local function Copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = Copy(v) end
    return o
end

local function MeGroup(name)       -- group table from env.mission (also for late-activated groups)
    for _, side in pairs((env.mission or {}).coalition or {}) do
        for _, c in pairs(side.country or {}) do
            for _, cat in ipairs({ "vehicle", "ship", "helicopter", "plane", "static" }) do
                for _, g in pairs((c[cat] or {}).group or {}) do
                    if g.name == name then return g end
                end
            end
        end
    end
end

local function Flag(n)
    local ok, v = pcall(trigger.misc.getUserFlag, tostring(n))
    return ok and tonumber(v) or 0
end

local function IsActive(g)
    local u = g and g:getUnit(1)
    if not u then return false end
    local ok, a = pcall(u.isActive, u)
    return ok and a ~= false
end

local SURF = {}
for k, v in pairs((land and land.SurfaceType) or {}) do SURF[v] = k end

local function SiteCheck(k, e)
    for _, gname in ipairs(e.targets or {}) do
        local g = MeGroup(gname)
        for i, u in ipairs((g and g.units) or {}) do
            local x, z = u.x, u.y
            local st = land.getSurfaceType({ x = x, y = z })
            local h0 = land.getHeight({ x = x, y = z })
            local dx = math.abs(land.getHeight({ x = x + 10, y = z }) - land.getHeight({ x = x - 10, y = z }))
            local dz = math.abs(land.getHeight({ x = x, y = z + 10 }) - land.getHeight({ x = x, y = z - 10 }))
            local slope = math.deg(math.atan(math.max(dx, dz) / 20))
            local n = "?"
            if world.VolumeType and world.searchObjects then
                n = 0
                pcall(world.searchObjects, Object.Category.SCENERY,
                    { id = world.VolumeType.SPHERE, params = { point = { x = x, y = h0, z = z }, radius = CFG.SCENERY_R } },
                    function() n = n + 1; return true end)
            end
            local ok = (SURF[st] == "LAND" or SURF[st] == "ROAD") and slope <= CFG.SLOPE_MAX and (n == 0 or n == "?")
            Log(string.format("site %s-%s %s unit %d %s: %s, elev %.0f m, slope %.1f deg, scenery %s -> %s",
                k, e.id, gname, i, tostring(u.type), tostring(SURF[st] or st), h0, slope, tostring(n), ok and "OK" or "CHECK"))
        end
    end
end

TRT.PICK = { version = CFG.VERSION }
TRT.PICK.meUnits = function(name) local g = MeGroup(name); return g and g.units or {} end   -- v1.1.0
TRT.PICK.audit = Flag(CFG.AUDIT_FLAG) > 0
if TRT.PICK.audit then Log("AUDIT mode (flag " .. CFG.AUDIT_FLAG .. "): site check of every pool entry") end
Log(string.format("rng %.6f (first math.random value this mission)", math.random()))

--- one entry index for JTAC k: forced by flag, else weighted random (w > 0), else 1
local function Choose(k, pool)
    local f = CFG.FLAG[k] and Flag(CFG.FLAG[k]) or 0
    if f >= 1 and f <= #pool then return f, true end
    local sum, nOn, only = 0, 0, nil
    for i, e in ipairs(pool) do
        sum = sum + math.max(0, e.w or 0)
        if (e.w or 0) > 0 then nOn, only = nOn + 1, i end
    end
    if nOn == 1 then return only, false end   -- v1.3.0: one candidate, no draw (math.random sequence unchanged)
    if sum > 0 then
        local r, acc = math.random() * sum, 0
        for i, e in ipairs(pool) do
            acc = acc + math.max(0, e.w or 0)
            if r < acc and (e.w or 0) > 0 then return i, false end
        end
    end
    return 1, false
end

local function ObjN(j, e) return ((e and e.objective) or j.objective or {}).n or 0 end

-- v1.2.0: choose every JTAC's entry first, then the weapons check (objectives together <= MAV + LGB - 2,
-- one spare per type; decision Onur 2026-11-04), re-drawing the random picks up to CFG.TRIES times
local picks, keys = {}, {}
for _, k in ipairs(P.order or {}) do
    local j = P.jtacs[k]
    if j and type(j.pool) == "table" and #j.pool > 0 then keys[#keys + 1] = k end
end
-- v1.3.0: the two taskings of this sortie (Comms_Director CD.tasked reads it)
if type(P.tasked) ~= "table" then P.tasked = { (P.order or {})[1], (P.order or {})[2] } end
local tasked = {}
for _, k in ipairs(P.tasked) do tasked[k] = true end
Log("tasked: " .. table.concat(P.tasked, " "))
local L = P.loadout or {}
local cap = (L.MAV and L.LGB) and (L.MAV + L.LGB - 2) or nil
local settled = false
for try = 1, CFG.TRIES do
    local need, anyRandom = 0, false
    for _, k in ipairs(keys) do
        local j = P.jtacs[k]
        local idx, forced = Choose(k, j.pool)
        picks[k] = { idx = idx, forced = forced }
        if tasked[k] then                                   -- v1.3.0
            need = need + ObjN(j, j.pool[idx])
            anyRandom = anyRandom or not forced
        end
    end
    if not cap or need <= cap or not anyRandom then
        Log(string.format("weapons check: objectives %d, cap %s (try %d)%s", need, tostring(cap), try,
            (cap and need > cap) and " -> OVER, forced picks kept" or ""))
        settled = true
        break
    end
    Log(string.format("weapons check: objectives %d > cap %d (try %d), re-draw", need, cap, try))
end
if not settled then Log("weapons check: no pick within the cap after " .. CFG.TRIES .. " tries -> last draw kept (OVER)") end

for _, k in ipairs(keys) do
    local j = P.jtacs[k]
    local pool = j.pool
    local idx, forced = picks[k].idx, picks[k].forced
    local e = pool[idx]
    j.targets = Copy(e.targets)
    if e.ord then j.ord = e.ord end
    if e.objective then j.objective = Copy(e.objective) end   -- v1.2.0
    j.pick, j.pick_name = e.id, e.name
    local g0 = MeGroup(e.targets[1])
    if g0 then j.tgt_fallback = { x = g0.x, z = g0.y } end
    for i, o in ipairs(pool) do
        for _, gname in ipairs(o.targets or {}) do
            local g = Group.getByName(gname)
            if i == idx then
                if g and not IsActive(g) then g:activate(); Log(k .. ": activated " .. gname) end
                if not g then env.error("[PICK] " .. k .. ": picked group missing in the mission: " .. gname) end
            elseif g and IsActive(g) then
                g:destroy(); Log(k .. ": removed " .. gname .. " (entry " .. tostring(o.id) .. " not picked)")
            end
        end
        if i ~= idx then
            for _, sname in ipairs(o.statics or {}) do
                local s = StaticObject.getByName(sname)
                if s then s:destroy(); Log(k .. ": removed static " .. sname) end
            end
        end
    end
    TRT.PICK[k] = { idx = idx, id = e.id, name = e.name, forced = forced, objective = ObjN(j, e) }
    Log(string.format("%s -> %s %s (%s, entry %d of %d, objective %d)", k, tostring(e.id), tostring(e.name),
        forced and ("forced by flag " .. CFG.FLAG[k]) or "random", idx, #pool, ObjN(j, e)))
    for i, o in ipairs(pool) do
        if i == idx or TRT.PICK.audit then
            local ok, err = pcall(SiteCheck, k, o)
            if not ok then Log("site check failed: " .. tostring(err)) end
        end
    end
end
Log("Tasking_Pick v" .. CFG.VERSION .. " done")
