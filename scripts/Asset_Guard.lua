-- Asset_Guard | v1.1.0
--[[
  High-value air asset guard — TRT Syria Dynamic Template (template-level module)

  Measures, does not act: when a hostile FIGHTER is airborne within radius_nm of a
  guarded unit, or inside a guarded trigger zone, the guard's flag is set to 1
  (latched, once). The ME decides what happens (e.g. activate an escort CAP) — same
  flag-based split as the scoring scripts.

  Guard kinds:
    { unit = "NAME", radius_nm = N, flag = F }   circle around a unit (moves with it)
    { zone = "NAME", flag = F }                  ME trigger zone (circle); radius_nm
                                                 optional, default = the zone's radius
  v1.1.0: zone guards. An ME "part of coalition in zone" condition counts parked /
  uncontrolled aircraft and ground units too; a zone guard counts only airborne
  fighters.

  Counted: units of coalition `hostile` (default RED), group category AIRPLANE,
  active (late activation done), airborne, with attribute "Fighters",
  "Interceptors" or "Multirole fighters" (AWACS / tankers / bombers ignored).
  Distance is 2D. A guard whose unit is dead or never appears simply waits;
  after the unit has existed once and then dies, the guard stops (logged).

  Flags (Oct 2026): 3010 = TANKER-1 threatened (ME "TANKER-1_Guard_CAP_Activate"
  activates CAP-1 + CAP-2); 3011 = hostile fighter airborne in TANKER_DEFENDERS_ZONE
  (ME "Tanker_Defenders_Activate" activates INTER-2).

  Add a guard: one line in CFG.GUARDS. Pick a free flag first (flag scheme).
]]

_G.TRT = _G.TRT or {}

local CFG = {
    VERSION = "1.1.0",
    TICK    = 10,     -- s
    ATTRS   = { "Fighters", "Interceptors", "Multirole fighters" },
    GUARDS  = {
        { unit = "TANKER-1-1", radius_nm = 60, flag = 3010, hostile = coalition.side.RED },
        { zone = "TANKER_DEFENDERS_ZONE", flag = 3011, hostile = coalition.side.RED },
    },
}

local function Log(s) env.info("Asset_Guard | " .. s) end

local function IsFighter(u)
    for _, a in ipairs(CFG.ATTRS) do
        local ok, has = pcall(u.hasAttribute, u, a)
        if ok and has then return true end
    end
    return false
end

local function DistNM(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz) / 1852
end

--- Closest airborne hostile fighter to pos within radius: unit name, distance (nil if none).
local function Threat(side, pos, radius)
    local bestName, bestD
    for _, g in ipairs(coalition.getGroups(side, Group.Category.AIRPLANE) or {}) do
        for _, u in ipairs(g:getUnits() or {}) do
            if u and u:isExist() and u:isActive() and u:inAir() and IsFighter(u) then
                local d = DistNM(u:getPoint(), pos)
                if d <= radius and (not bestD or d < bestD) then bestName, bestD = u:getName(), d end
            end
        end
    end
    return bestName, bestD
end

for _, g in ipairs(CFG.GUARDS) do g.state = "WAIT" end   -- WAIT -> WATCH -> FIRED / LOST

local function Tick(_, t)
    local ok, err = pcall(function()
        for _, g in ipairs(CFG.GUARDS) do
            if g.zone and (g.state == "WAIT" or g.state == "WATCH") then
                local z = trigger.misc.getZone(g.zone)
                if not z or not z.point then
                    g.state = "LOST"
                    Log("zone " .. g.zone .. " not found -> guard stopped (flag " .. g.flag .. " untouched)")
                else
                    local radius = g.radius_nm or (z.radius / 1852)
                    if g.state == "WAIT" then
                        g.state = "WATCH"
                        Log(string.format("watching zone %s (%.1f NM)", g.zone, radius))
                    end
                    local name, d = Threat(g.hostile or coalition.side.RED, z.point, radius)
                    if name then
                        trigger.action.setUserFlag(g.flag, 1)
                        g.state = "FIRED"
                        Log(string.format("zone %s entered: %s at %.1f NM from centre (<= %.1f) -> flag %d = 1",
                            g.zone, name, d, radius, g.flag))
                    end
                end
            elseif g.state == "WAIT" or g.state == "WATCH" then
                local u = Unit.getByName(g.unit)
                if u and u:isExist() and u:getLife() > 0 then
                    if g.state == "WAIT" then g.state = "WATCH"; Log("watching " .. g.unit) end
                    local name, d = Threat(g.hostile or coalition.side.RED, u:getPoint(), g.radius_nm)
                    if name then
                        trigger.action.setUserFlag(g.flag, 1)
                        g.state = "FIRED"
                        Log(string.format("%s threatened: %s at %.1f NM (<= %d) -> flag %d = 1",
                            g.unit, name, d, g.radius_nm, g.flag))
                    end
                elseif g.state == "WATCH" then
                    g.state = "LOST"
                    Log(g.unit .. " lost before any threat -> guard stopped (flag " .. g.flag .. " untouched)")
                end
            end
        end
    end)
    if not ok then Log("tick error: " .. tostring(err)) end
    return t + CFG.TICK
end

timer.scheduleFunction(Tick, nil, timer.getTime() + 5)
Log("v" .. CFG.VERSION .. " loaded, " .. #CFG.GUARDS .. " guard(s)")
