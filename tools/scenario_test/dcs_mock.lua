-- dcs_mock | v1.1.0
-- v1.1.0 (2026-11-04): late-activated groups (g.inactive, Unit:isActive, Group:activate), MOCK.missionFromGroups(),
--         world.VolumeType.
-- Minimal DCS mission-environment mock for tools/scenario_test/run.py (lupa, Lua 5.4).
-- Virtual clock, scheduled functions, units / groups, flags, text / radio capture, F10 commands.
-- Only what Menu_Manager, Comms_Director and JTAC_Controller touch; unknown API calls are no-ops.

-- Lua 5.1 compatibility (DCS) on Lua 5.4
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
math.pow = math.pow or function(a, b) return a ^ b end
math.mod = math.mod or math.fmod
unpack = unpack or table.unpack
loadstring = loadstring or load
table.getn = table.getn or function(t) return #t end

MOCK = { t = 0, timers = {}, nextId = 1, log = {}, texts = {}, tx = {}, flags = {}, units = {}, groups = {},
         handlers = {}, errors = {}, gid = 1000, uid = 5000 }
local M = MOCK

local function noop() end
local function lenient(t)
    return setmetatable(t or {}, { __index = function() return noop end })
end

-- ── clock ──────────────────────────────────────────────────────────────
timer = {
    getTime = function() return M.t end,
    getAbsTime = function() return 21600 + M.t end,   -- 06:00 local
    scheduleFunction = function(fn, arg, t)
        local id = M.nextId; M.nextId = M.nextId + 1
        M.timers[id] = { fn = fn, arg = arg, t = t }
        return id
    end,
    removeFunction = function(id) M.timers[id] = nil end,
    setFunctionTime = function(id, t) if M.timers[id] then M.timers[id].t = t end end,
}

--- run every function due at or before the current time (in time order)
function MOCK.runDue()
    for _ = 1, 10000 do
        local bestId, best
        for id, tm in pairs(M.timers) do
            if tm.t <= M.t + 1e-9 and (not best or tm.t < best.t or (tm.t == best.t and id < bestId)) then
                bestId, best = id, tm
            end
        end
        if not best then return end
        M.timers[bestId] = nil
        local ok, r = pcall(best.fn, best.arg, best.t)
        if not ok then
            M.errors[#M.errors + 1] = string.format("%.1f timer error: %s", M.t, tostring(r))
        elseif type(r) == "number" then
            M.timers[bestId] = { fn = best.fn, arg = best.arg, t = math.max(r, M.t + 0.001) }
        end
    end
end

function MOCK.advance(dt)
    local target = M.t + dt
    while M.t < target - 1e-9 do
        local step = math.min(0.1, target - M.t)
        M.t = M.t + step
        M.runDue()
    end
end

-- ── log / text / radio ──────────────────────────────────────────────────
local function L(s) M.log[#M.log + 1] = string.format("%8.1f %s", M.t, tostring(s)) end
env = { info = L, warning = L, error = function(s) L("ERROR " .. tostring(s)); M.errors[#M.errors + 1] = tostring(s) end,
        mission = { coalition = {}, date = { Year = 2026, Month = 11, Day = 3 } },
        getValueDictByKey = function(k) return k end }

trigger = {
    action = lenient({
        outTextForGroup = function(g, s, d, c) M.texts[#M.texts + 1] = { t = M.t, s = s } end,
        outTextForCoalition = function(c, s, d, cl) M.texts[#M.texts + 1] = { t = M.t, s = s } end,
        outText = function(s, d, c) M.texts[#M.texts + 1] = { t = M.t, s = s } end,
        radioTransmission = function(file, pos, mod, loop, hz, power, name)
            M.tx[#M.tx + 1] = { t = M.t, file = file, hz = hz, name = name }
        end,
        setUserFlag = function(f, v)
            if v == true then v = 1 elseif v == false then v = 0 end
            M.flags[tostring(f)] = v
        end,
    }),
    misc = lenient({
        getUserFlag = function(f) return M.flags[tostring(f)] or 0 end,
        getZone = function() return nil end,
    }),
}

-- ── objects ──────────────────────────────────────────────────────────────
local UnitMT = {}
UnitMT.__index = UnitMT
function UnitMT:isExist() return not self.removed and self.life > 0 end
function UnitMT:getLife() return self.life end
function UnitMT:getLife0() return 1 end
function UnitMT:getName() return self.name end
function UnitMT:getPoint() return { x = self.p.x, y = self.p.y, z = self.p.z } end
function UnitMT:getPosition()
    local h = self.hdg or 0
    return { p = self:getPoint(), x = { x = math.cos(h), y = 0, z = math.sin(h) }, y = { x = 0, y = 1, z = 0 },
             z = { x = -math.sin(h), y = 0, z = math.cos(h) } }
end
function UnitMT:getVelocity() return self.v or { x = 0, y = 0, z = 0 } end
function UnitMT:getGroup() return self.group end
function UnitMT:getTypeName() return self.type end
function UnitMT:getDesc()
    return self.desc or { category = self.cat or 2, typeName = self.type, displayName = self.type, attributes = {},
                          life = 1, massEmpty = 10000, fuelMassMax = 4900 }
end
function UnitMT:hasAttribute() return false end
function UnitMT:getCoalition() return self.coal end
function UnitMT:getCountry() return 2 end
function UnitMT:getCategory() return self.cat == 0 and 1 or 2 end
function UnitMT:inAir() return self.air and true or false end
function UnitMT:getFuel() return self.fuel or 0.6 end
function UnitMT:getAmmo() return self.ammo end
function UnitMT:getPlayerName() return self.player end
function UnitMT:getID() return self.id end
function UnitMT:getNumber() return 1 end
function UnitMT:getDrawArgumentValue() return 0 end
function UnitMT:getRadar() return false, nil end
function UnitMT:getSensors() return {} end
function UnitMT:getController() return lenient({ getDetectedTargets = function() return {} end }) end
function UnitMT:destroy() self.removed = true end
function UnitMT:getCallsign() return self.name end
function UnitMT:isActive() return not (self.group and self.group.inactive) end   -- late activation (pool)

local GroupMT = {}
GroupMT.__index = GroupMT
function GroupMT:getName() return self.name end
function GroupMT:getUnits()
    local out = {}
    for _, u in ipairs(self.units) do if u:isExist() then out[#out + 1] = u end end
    return out
end
function GroupMT:getUnit(i) local u = self.units[i]; return (u and u:isExist()) and u or nil end
function GroupMT:isExist()
    if self.removed then return false end
    for _, u in ipairs(self.units) do if u:isExist() then return true end end
    return false
end
function GroupMT:getID() return self.id end
function GroupMT:getSize() return #self:getUnits() end
function GroupMT:getInitialSize() return #self.units end
function GroupMT:getCoalition() return self.coal end
function GroupMT:getCategory() return self.cat or 2 end
function GroupMT:destroy() self.removed = true; for _, u in ipairs(self.units) do u.removed = true end end
function GroupMT:getController() return lenient({ getDetectedTargets = function() return {} end }) end
function GroupMT:activate() self.inactive = false end

--- MOCK.missionFromGroups(): env.mission.coalition from the mock groups (Tasking_Pick reads ME positions there)
function MOCK.missionFromGroups()
    local grp = {}
    for n, g in pairs(M.groups) do
        local us = {}
        for i, u in ipairs(g.units) do us[i] = { name = u.name, type = u.type, x = u.p.x, y = u.p.z } end
        grp[#grp + 1] = { name = n, x = us[1] and us[1].x or 0, y = us[1] and us[1].y or 0, units = us,
                          lateActivation = g.inactive or nil }
    end
    env.mission.coalition = { red = { country = { { name = "MOCK", vehicle = { group = grp } } } } }
end

--- MOCK.addGroup(name, coal, cat, units = { {name, type, x, z, y?}, ... }) -> group
function MOCK.addGroup(name, coal, cat, units)
    M.gid = M.gid + 1
    local g = setmetatable({ name = name, coal = coal, cat = cat, id = M.gid, units = {} }, GroupMT)
    for i, d in ipairs(units) do
        M.uid = M.uid + 1
        local u = setmetatable({ name = d.name or (name .. "-" .. i), type = d.type or "BTR-80", coal = coal,
            cat = cat, id = M.uid, life = 1, group = g, p = { x = d.x, y = d.y or 0, z = d.z } }, UnitMT)
        g.units[#g.units + 1] = u
        M.units[u.name] = u
    end
    M.groups[name] = g
    return g
end

Unit = {
    getByName = function(n) local u = M.units[n]; if u and u:isExist() then return u end return nil end,
    Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND_UNIT = 2, SHIP = 3, STRUCTURE = 4 },
}
Group = {
    getByName = function(n) local g = M.groups[n]; if g and not g.removed then return g end return nil end,
    Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4 },
}
StaticObject = { getByName = function() return nil end }
Airbase = { getByName = function() return nil end }
Object = { Category = { UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, CARGO = 6 } }
Weapon = { Category = { SHELL = 0, MISSILE = 1, ROCKET = 2, BOMB = 3 },
           MissileCategory = { AAM = 1, SAM = 2, BM = 3, ANTI_SHIP = 4, CRUISE = 5, OTHER = 6 } }

coalition = {
    side = { NEUTRAL = 0, RED = 1, BLUE = 2 },
    getGroups = function(side, cat)
        local out = {}
        for _, g in pairs(M.groups) do
            if g.coal == side and (cat == nil or g.cat == cat) and g:isExist() then out[#out + 1] = g end
        end
        return out
    end,
    addGroup = function(countryId, cat, data)
        local units = {}
        for _, u in ipairs(data.units or {}) do
            units[#units + 1] = { name = u.name, type = u.type, x = u.x, z = u.y }
        end
        local g = MOCK.addGroup(data.name, 2, (cat == 2 or cat == nil) and 2 or cat, units)
        return g
    end,
    getPlayers = function() return {} end,
    getAirbases = function() return {} end,
    getStaticObjects = function() return {} end,
}
country = { id = setmetatable({}, { __index = function() return 2 end }) }

world = {
    event = { S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_TAKEOFF = 3, S_EVENT_LAND = 4, S_EVENT_CRASH = 5,
              S_EVENT_EJECTION = 6, S_EVENT_REFUELING = 7, S_EVENT_DEAD = 8, S_EVENT_PILOT_DEAD = 9,
              S_EVENT_BASE_CAPTURED = 10, S_EVENT_REFUELING_STOP = 14, S_EVENT_BIRTH = 15,
              S_EVENT_ENGINE_STARTUP = 18, S_EVENT_ENGINE_SHUTDOWN = 19, S_EVENT_PLAYER_ENTER_UNIT = 20,
              S_EVENT_PLAYER_LEAVE_UNIT = 21, S_EVENT_KILL = 28, S_EVENT_UNIT_LOST = 30 },
    addEventHandler = function(h) M.handlers[#M.handlers + 1] = h end,
    removeEventHandler = noop,
    getAirbases = function() return {} end,
    searchObjects = noop,
    VolumeType = { SEGMENT = 0, BOX = 1, SPHERE = 2, PYRAMID = 3 },
}
function MOCK.event(e)
    for _, h in ipairs(M.handlers) do
        local ok, err = pcall(h.onEvent, h, e)
        if not ok then M.errors[#M.errors + 1] = string.format("%.1f event error: %s", M.t, tostring(err)) end
    end
end

land = { isVisible = function() return true end, getHeight = function() return 100 end,
         getSurfaceType = function() return 1 end, getIP = noop, profile = function() return {} end,
         SurfaceType = { LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5 } }
coord = {
    LOtoLL = function(p) return 35 + p.x / 111000, 36 + p.z / 91000, 0 end,
    LLtoLO = function(lat, lon, alt) return { x = (lat - 35) * 111000, y = alt or 0, z = (lon - 36) * 91000 } end,
    LLtoMGRS = function(lat, lon)
        return { UTMZone = "37S", MGRSDigraph = "BV", Easting = math.floor((lon - 30) * 91000) % 100000,
                 Northing = math.floor((lat - 30) * 111000) % 100000 }
    end,
    MGRStoLL = function(m) return 35.5, 36.2, 0 end,
}
Spot = { createLaser = function(src, ofs, tgt, code)
             return { destroy = noop, setPoint = noop, getPoint = function() return tgt end, setCode = noop }
         end,
         createInfraRed = function() return { destroy = noop, setPoint = noop } end }
radio = { modulation = { AM = 0, FM = 1 } }
atmosphere = { getWind = function() return { x = 0, y = 0, z = 0 } end,
               getWindWithTurbulence = function() return { x = 0, y = 0, z = 0 } end,
               getTemperatureAndPressure = function() return 288, 101325 end }
local function proxy()
    return setmetatable({}, { __index = function() return proxy() end, __call = function() return nil end })
end
AI = proxy()

-- ── F10 commands ──────────────────────────────────────────────────────────
local mh = 0
missionCommands = {
    addSubMenuForGroup = function(gid, name, parent) mh = mh + 1; return { "sub", mh, name } end,
    addCommandForGroup = function(gid, name, parent, fn, arg) mh = mh + 1; return { "cmd", mh, name } end,
    removeItemForGroup = noop,
    addSubMenu = function(name, parent) mh = mh + 1; return { "sub", mh, name } end,
    addCommand = function(name, parent, fn, arg) mh = mh + 1; return { "cmd", mh, name } end,
    removeItem = noop,
}
net = nil
