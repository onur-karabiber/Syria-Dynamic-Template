-- JTAC_Laser | v1.0.0
--[[
  Scripted laser backup for JTACs whose native DCS lasing fails (CAS-1 tests 2026-10-28:
  Eyeball 11 / JTAC-2 never lased in two flights; LOS audit OK, task settings identical to
  JTAC-1 / JTAC-8, no trigger interfering - cause inside the DCS JTAC AI, not found).

  For every JTAC group named in CFG.ASSIST that has an ME FAC_AttackGroup task, while the
  hero is airborne within CFG.RANGE_NM of that task's target group, a laser spot
  (Spot.createLaser, the task's laser code) is held from the JTAC unit on one alive unit of
  the target group, re-aimed every CFG.TICK s (moving targets). When that unit dies the next
  alive unit is taken; when the group is dead or the hero leaves the range the spot is
  removed. The native JTAC dialogue (9-line, "cleared hot") is untouched; if the native JTAC
  does lase, both spots carry the same code.

  Target choice inside the group: CFG.PRIORITY type order first (SAM / radar before escorts),
  then ME unit order.
  Log: "[JTAC_LASER] ON / MOVE / OFF ..." with unit, code, distance.

  Not verified in DCS yet: Spot.createLaser from an invisible (SetInvisible) ground JTAC and
  LGB guidance on it (used by MOOSE AUTOLASE / CTLD JTAC, same API).
  Load order: free (reads env.mission at load, hero lazily). API: TRT.JL.version, TRT.JL.CFG
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.JL then env.info("[JTAC_LASER] already loaded, second copy ignored") return end

local CFG = {
    VERSION   = "1.0.0",
    ASSIST    = { ["JTAC-2"] = true },   -- JTAC group names that get the scripted laser
    RANGE_NM  = 12,                      -- hero <-> target group (2D)
    TICK      = 1.0,                     -- s
    SRC_OFF   = { x = 0, y = 3, z = 0 }, -- laser source offset on the JTAC (local frame)
    TGT_UP    = 1.0,                     -- m above the target unit's origin
    PRIORITY  = { "Osa 9A33 ln", "Strela-10M3", "Tor 9A331", "Kub 1S91 str", "Kub 2P25 ln",
                  "2S6 Tunguska", "ZSU-23-4 Shilka" },
}

local JL = { version = CFG.VERSION, CFG = CFG, pairs = {} }
TRT.JL = JL

local function log(s) env.info("[JTAC_LASER] " .. s) end
local function hero()
    local u = Unit.getByName(TRT.PLAYER_NAME or "Player_01")
    if u and u:isExist() then return u end
end
local function d2(a, b) local dx, dz = a.x - b.x, a.z - b.z return math.sqrt(dx * dx + dz * dz) end
local function dstr(s) return (env.getValueDictByKey and env.getValueDictByKey(s)) or s end

-- ME scan: FAC_AttackGroup tasks of the ASSIST groups
do
    local byId, jt = {}, {}
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
        if t.id == "FAC_AttackGroup" and t.params and t.params.groupId then out[#out + 1] = t.params end
        for _, v in pairs(t) do scan(v, out) end
    end
    local ok, err = pcall(function()
        each(function(g) if g.groupId and g.name then byId[g.groupId] = dstr(g.name) end end)
        each(function(g)
            local n = g.name and dstr(g.name)
            if n and CFG.ASSIST[n] then
                local ts = {}
                scan(g.route, ts); scan(g.tasks, ts)
                for _, p in ipairs(ts) do
                    local tg = byId[p.groupId]
                    if tg then jt[#jt + 1] = { jtac = n, target = tg, code = tonumber(p.laserCode) or 1688 } end
                end
            end
        end)
    end)
    if not ok then log("ME scan error: " .. tostring(err)) end
    JL.pairs = jt
    for _, p in ipairs(jt) do log(string.format("assist %s -> %s, code %d", p.jtac, p.target, p.code)) end
    if #jt == 0 then log("no ASSIST JTAC with a FAC_AttackGroup task found") end
end

local PRIO = {}
for i, t in ipairs(CFG.PRIORITY) do PRIO[t] = i end

local function pickUnit(gname)
    local g = Group.getByName(gname)
    if not g then return nil end
    local best, bestP
    for i, u in ipairs(g:getUnits() or {}) do
        local ok, alive = pcall(function() return u:isExist() and u:getLife() > 1 end)
        if ok and alive then
            local p = PRIO[u:getTypeName()] or (100 + i)
            if not bestP or p < bestP then best, bestP = u, p end
        end
    end
    return best
end

local function jtacUnit(gname)
    local g = Group.getByName(gname)
    if not g then return nil end
    for _, u in ipairs(g:getUnits() or {}) do
        if u and u:isExist() then return u end
    end
end

local function off(p, why)
    if p.spot then pcall(p.spot.destroy, p.spot) end
    if p.spot then log(string.format("OFF %s -> %s (%s)", p.jtac, p.target, why)) end
    p.spot, p.unit = nil, nil
end

timer.scheduleFunction(function(_, t)
    local ok, err = pcall(function()
        local h = hero()
        local air = h and h:inAir()
        for _, p in ipairs(JL.pairs) do
            local ju = jtacUnit(p.jtac)
            local tu = pickUnit(p.target)
            if not (h and air) then off(p, "hero not airborne")
            elseif not ju then off(p, "JTAC gone")
            elseif not tu then off(p, "target group dead")
            else
                local tp = tu:getPoint()
                local d = d2(h:getPoint(), tp) / 1852
                if d > CFG.RANGE_NM then
                    off(p, string.format("hero %.1f NM", d))
                else
                    local aim = { x = tp.x, y = tp.y + CFG.TGT_UP, z = tp.z }
                    if not p.spot then
                        local okS, s = pcall(Spot.createLaser, ju, CFG.SRC_OFF, aim, p.code)
                        if okS and s then
                            p.spot, p.unit = s, tu:getName()
                            log(string.format("ON %s -> %s [%s] code %d, hero %.1f NM",
                                p.jtac, p.unit, tu:getTypeName(), p.code, d))
                        else
                            log("createLaser failed: " .. tostring(s))
                        end
                    else
                        pcall(p.spot.setPoint, p.spot, aim)
                        if p.unit ~= tu:getName() then
                            p.unit = tu:getName()
                            log(string.format("MOVE %s -> %s [%s]", p.jtac, p.unit, tu:getTypeName()))
                        end
                    end
                end
            end
        end
    end)
    if not ok then log("tick error: " .. tostring(err)) end
    return t + CFG.TICK
end, nil, timer.getTime() + 5)

log("v" .. CFG.VERSION .. " loaded, " .. #JL.pairs .. " JTAC(s) assisted")
