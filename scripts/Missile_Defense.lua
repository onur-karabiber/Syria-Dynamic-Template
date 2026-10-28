-- Missile_Defense | v1.0.0
--[[
  Score for a defeated missile (Onur, CAS-1 test 2026-10-28): a RED surface-to-air or
  air-to-air missile launched at the hero that stops existing without hitting him
  earns MD.CFG.PTS through TRT.addScore (so Score_Display shows the card).

  What counts as "launched at the hero" (S_EVENT_SHOT, RED shooter, weapon category
  MISSILE, missileCategory AAM or SAM):
    * weapon:getTarget() is the hero  -> tracked (radar / command guided, most AAM), or
    * no target at launch (IR SAM / MANPADS often report none) and the hero within
      CFG.NOTGT_LAUNCH_NM of the shooter -> tracked, but it only counts if it came
      inside CFG.NOTGT_CLOSE_M of the hero (a missile that never got near was not a threat).
  Salvo rule: missiles from the same shooter within CFG.SALVO_S of the first one are one
  engagement -> one score. An engagement is settled when its last missile is gone:
    defeated  -> + PTS ("MISSILE DEFEATED: <shooter type>")
    hit       -> nothing here (any S_EVENT_HIT on the hero by one of its missiles)
    hero dead / not airborne / gone -> nothing
  Hit detection compares weapon object ids (id_); an S_EVENT_HIT on the hero from the
  same shooter during the engagement also marks it hit (proximity fuze cases where the
  weapon in the event differs).

  Not verified in DCS yet: getTarget() values for each SAM type (logged per shot:
  "[MD] shot ..."), and whether every missile fires S_EVENT_HIT on a proximity hit.
  The log line per engagement says why it scored or not.

  Load order: after Core_Scoring.lua (uses TRT.addScore, TRT.PLAYER_NAME).
  API: TRT.MD.version, TRT.MD.CFG
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.MD then
    env.info("[MD] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION          = "1.0.0",
    PTS              = 5,       -- per defeated engagement
    SALVO_S          = 15,      -- s: same shooter, missiles inside this window = one engagement
    TICK             = 0.5,     -- s
    NOTGT_LAUNCH_NM  = 12,      -- no-target missile tracked only if the hero is this close to the shooter
    NOTGT_CLOSE_M    = 3000,    -- ... and it only counts if it came this close to the hero
    MAX_FLIGHT_S     = 180,     -- safety: a tracked missile older than this is dropped
}

local MD = { version = CFG.VERSION, CFG = CFG, eng = {}, byWeapon = {}, n = 0 }
TRT.MD = MD

local function log(s) env.info("[MD] " .. s) end
local function now() return timer.getTime() end
local function heroName() return TRT.PLAYER_NAME or "Player_01" end

local function hero()
    local u = Unit.getByName(heroName())
    if u and u:isExist() then return u end
    return nil
end

local function oid(o)
    if not o then return nil end
    local ok, id = pcall(function() return o.id_ end)
    if ok and id then return id end
    return tostring(o)
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function safe(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

----------------------------------------------------------------
-- SHOT
----------------------------------------------------------------
local function onShot(e)
    local w, s = e.weapon, e.initiator
    if not w or not s then return end
    if safe(s.getCoalition, s) ~= coalition.side.RED then return end
    local desc = safe(w.getDesc, w)
    if not desc or desc.category ~= Weapon.Category.MISSILE then return end
    local mc = desc.missileCategory
    if mc ~= Weapon.MissileCategory.AAM and mc ~= Weapon.MissileCategory.SAM then return end

    local h = hero()
    if not h or not safe(h.inAir, h) then return end
    local tgt = safe(w.getTarget, w)
    local tgtName = tgt and safe(tgt.getName, tgt) or nil
    local sName = safe(s.getName, s) or "?"
    local sType = safe(s.getTypeName, s) or "?"
    local wType = safe(w.getTypeName, w) or (desc.typeName or "?")
    local hp, sp = safe(h.getPoint, h), safe(s.getPoint, s)
    local range = (hp and sp) and dist(hp, sp) or nil

    local mode
    if tgtName == heroName() then
        mode = "target"
    elseif tgt == nil and range and range <= CFG.NOTGT_LAUNCH_NM * 1852 then
        mode = "notgt"
    end
    log(string.format("shot %s (%s) by %s [%s] target=%s range=%s -> %s",
        wType, mc == Weapon.MissileCategory.SAM and "SAM" or "AAM", sName, sType,
        tostring(tgtName), range and string.format("%.1f NM", range / 1852) or "?", mode or "ignored"))
    if not mode then return end

    -- engagement = same shooter inside the salvo window
    local eg = MD.eng[sName]
    if not eg or eg.settled or now() - eg.t0 > CFG.SALVO_S then
        MD.n = MD.n + 1
        eg = { id = MD.n, shooter = sName, sType = sType, wType = wType, t0 = now(),
               missiles = {}, live = 0, hit = false, settled = false, counts = false }
        MD.eng[sName] = eg
    end
    local m = { w = w, id = oid(w), mode = mode, t0 = now(), minD = range or math.huge }
    eg.missiles[#eg.missiles + 1] = m
    eg.live = eg.live + 1
    if mode == "target" then eg.counts = true end
    MD.byWeapon[m.id] = eg
end

----------------------------------------------------------------
-- HIT on the hero
----------------------------------------------------------------
local function onHit(e)
    local t = e.target
    if not t or safe(t.getName, t) ~= heroName() then return end
    local eg = e.weapon and MD.byWeapon[oid(e.weapon)]
    if not eg and e.initiator then
        local sName = safe(e.initiator.getName, e.initiator)
        local cand = sName and MD.eng[sName]
        if cand and not cand.settled then eg = cand end
    end
    if eg and not eg.hit then
        eg.hit = true
        log(string.format("engagement #%d (%s): HERO HIT", eg.id, eg.shooter))
    end
end

local EH = {}
function EH:onEvent(e)
    if not e then return end
    if e.id == world.event.S_EVENT_SHOT then pcall(onShot, e)
    elseif e.id == world.event.S_EVENT_HIT then pcall(onHit, e) end
end
world.addEventHandler(EH)

----------------------------------------------------------------
-- TRACK / SETTLE
----------------------------------------------------------------
local function settle(eg, h)
    eg.settled = true
    for _, m in ipairs(eg.missiles) do MD.byWeapon[m.id] = nil end
    local why
    if eg.hit then why = "hit"
    elseif not h then why = "hero gone"
    elseif not safe(h.inAir, h) then why = "hero not airborne"
    elseif not eg.counts then why = "no-target missile never inside " .. CFG.NOTGT_CLOSE_M .. " m"
    end
    local closest = math.huge
    for _, m in ipairs(eg.missiles) do closest = math.min(closest, m.minD) end
    log(string.format("engagement #%d %s [%s] %d missile(s), closest %s, %.0f s -> %s",
        eg.id, eg.shooter, eg.sType, #eg.missiles,
        closest < math.huge and string.format("%.0f m", closest) or "?", now() - eg.t0,
        why and ("no score (" .. why .. ")") or ("DEFEATED +" .. CFG.PTS)))
    if not why and TRT.addScore then
        TRT.addScore(CFG.PTS, string.format("MISSILE DEFEATED: %s (%s)", eg.wType, eg.sType))
    end
end

timer.scheduleFunction(function(_, t)
    local ok, err = pcall(function()
        local h = hero()
        local hp = h and safe(h.getPoint, h)
        for name, eg in pairs(MD.eng) do
            if not eg.settled then
                local live = 0
                for _, m in ipairs(eg.missiles) do
                    if not m.gone then
                        local ex = safe(m.w.isExist, m.w)
                        if ex and now() - m.t0 < CFG.MAX_FLIGHT_S then
                            live = live + 1
                            local p = hp and safe(m.w.getPoint, m.w)
                            if p then
                                local d = dist(p, hp)
                                if d < m.minD then m.minD = d end
                                if m.mode == "notgt" and d <= CFG.NOTGT_CLOSE_M then eg.counts = true end
                            end
                        else
                            m.gone = true
                        end
                    end
                end
                eg.live = live
                -- settle when every missile is gone and the salvo window is closed
                if live == 0 and now() - eg.t0 > CFG.SALVO_S then settle(eg, h) end
            elseif now() - eg.t0 > CFG.SALVO_S + CFG.MAX_FLIGHT_S then
                MD.eng[name] = nil
            end
        end
    end)
    if not ok then log("tick error: " .. tostring(err)) end
    return t + CFG.TICK
end, nil, timer.getTime() + 1)

log("v" .. CFG.VERSION .. " loaded (hero " .. heroName() .. ", " .. CFG.PTS .. " pts per defeated engagement)")
