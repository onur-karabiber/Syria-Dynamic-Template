-- AAR_Monitor | v1.0.0
--[[
  Aerial refuelling (AAR) measurement - TRT Syria Dynamic Template (template-level module).
  Design: project doc claude/aar-plan-2026-10-30.md (v0.6, sections 10 and 18).

  SHADOW MODE (CFG.SCORING = false): everything is measured and logged ("[AAR]"), a summary is
  shown at the end of each session, nothing is added to the score and TRT.onRefuelComplete is not
  called. Core_Scoring v1.4.3 no longer scores the player refuel either.

  A session = hero approaches the tanker (<= RV_NM) ... last disconnect ... hero > LEAVE_NM away.
  A second refuelling (AR2) is a new session. A session without contact ends "abandoned" when the
  hero goes > ABANDON_NM away.

  Phases (log only): IDLE -> RV -> JOIN (<= 1 NM) -> ECHELON_L / ASTERN (pre-contact) -> CONTACT
  (S_EVENT_REFUELING .. _STOP) -> POST -> LEAVE.

  Geometry (tanker unit, DCS x = north, z = east): fwd/right are horizontal, along/across the
  tanker's ground heading; up = hero MSL - tanker MSL (world axis). Closure from the 3-D velocity
  difference. All three in the same way as tools/aar_test_logger.lua v1.0.1 (verified on the
  TEST-AAR flights 2026-10-30: left drogue = 91 ft aft, 47 ft left, 5 ft below the tanker unit).

  Measurements and PROPOSED points ([V], plan section 10; total clipped to [CAP_MIN, CAP_MAX]):
    RV_VERT   at the first tick <= 1 NM: hero >= RV_MIN_BELOW_FT below the tanker      +2 / -2
    JOIN_SIDE at that tick: left of the tanker (right < 0)                              +1 / -1
    OVERTAKE  max closure at 0.5 NM..contact (aft of the tanker), > 25 kt               -2 (<= 25: 0)
    OVERRUN   hero ahead of the tanker (fwd > OVERRUN_FT) inside 1 NM before contact    -2
    WEAPON    S_EVENT_SHOT by the hero with the tanker <= WEAPON_NM                     -5
    CONNECT   contacts - 1 = breaks: 0 breaks +2, each break -1 (floor -3)
    DEPART    after the last disconnect, until LEAVE_NM: right side at 0.3 NM and never
              below DEPART_MIN_UP_FT relative to the tanker                              +1 / -2
  Logged only (no points until a decision): onload per contact and total, contact duration, closure
  and geometry at contact, probe open/close distance, fuel at 1 NM / contact / disconnect / leave,
  time RV -> first contact.
  Not measured here: radar state (Unit.getRadar() is nil for the player), recovery TANK/BINGO,
  divert decision (other modules).

  Flags: 3200 first contact (latched) | 3201 session complete (latched, each session).
  Exports: _G.TRT.AAR (state + last session summary).
  Reads, never writes: TRT.PLAYER_NAME. Scores only with CFG.SCORING = true (TRT.addScore).
  Load order: after Core_Scoring. No other dependency.
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.AAR then
    env.info("[AAR] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION      = "1.0.0",
    PLAYER_UNIT  = TRT.PLAYER_NAME or "Player_01",
    TANKERS      = { "TANKER-1-1" },     -- unit names; the nearest existing one is used
    SCORING      = false,                -- shadow
    SHADOW_MSG   = true,                 -- show the session summary on screen
    CALL_REFUEL_COMPLETE = false,        -- TRT.onRefuelComplete at session end (only with SCORING)

    TICK_FAR     = 2,                    -- s
    TICK_NEAR    = 1,                    -- s, inside 2 NM
    RV_NM        = 15,                   -- session starts
    ABANDON_NM   = 25,                   -- session without contact ends
    LEAVE_NM     = 2,                    -- session with contact ends
    JOIN_NM      = 1.0,

    RV_MIN_BELOW_FT   = 900,             -- plan 1000 ft, 100 ft tolerance
    OVERTAKE_BAD_KT   = 25,
    OVERTAKE_PLAN_KT  = 10,
    OVERTAKE_FROM_NM  = 0.5,
    OVERRUN_FT        = 300,
    OVERRUN_NM        = 1.0,
    WEAPON_NM         = 10,
    DEPART_SIDE_NM    = 0.3,
    DEPART_MIN_UP_FT  = -500,

    -- pre-contact zones relative to the tanker unit (ft)
    ECH_L = { fwdMin = -400, fwdMax = 100, rightMin = -400, rightMax = -60 },
    ECH_R = { fwdMin = -400, fwdMax = 100, rightMin = 60,   rightMax = 400 },
    ASTERN = { fwdMin = -300, fwdMax = -30, rightMin = -130, rightMax = 40 },
    PROBE_OUT = 0.9, PROBE_ARG = 22,

    CAP_MIN = -10, CAP_MAX = 10,
    FLAGS = { CONTACT = 3200, DONE = 3201 },
}

local NM, FT, KT, LB = 1852, 3.28084, 1.94384, 2.2046226218

local AAR = { version = CFG.VERSION, session = nil, sessions = {}, last = nil, nSession = 0, armed = true }
TRT.AAR = AAR

local function log(s) env.info("[AAR] " .. s) end
local function now() return timer.getTime() end

local function hero()
    local u = Unit.getByName(CFG.PLAYER_UNIT)
    if u and u:isExist() then return u end
    return nil
end

local function msg(text, dur)
    local u = hero()
    if u and u:getGroup() then
        trigger.action.outTextForGroup(u:getGroup():getID(), text, dur or 20, false)
    else
        trigger.action.outText(text, dur or 20, false)
    end
end

local function setFlag(id) trigger.action.setUserFlag(tostring(id), 1) end

local function fuelLb(u)
    local f = u:getFuel()
    if not f then return nil end
    local ok, d = pcall(function() return u:getDesc() end)
    local maxKg = ok and d and d.fuelMassMax or nil
    if not maxKg then return nil end
    return f * maxKg * LB
end

local function fmt(v, f) if v == nil then return "n/a" end return string.format(f or "%.0f", v) end

local function tanker()
    local best, bd
    local h = hero()
    for _, n in ipairs(CFG.TANKERS) do
        local k = Unit.getByName(n)
        if k and k:isExist() then
            if not h then return k end
            local hp, kp = h:getPoint(), k:getPoint()
            local d = (hp.x - kp.x) ^ 2 + (hp.z - kp.z) ^ 2
            if not bd or d < bd then best, bd = k, d end
        end
    end
    return best
end

-- Relative state of the hero to tanker k. Distances in ft, closure in kt.
local function rel(h, k)
    local hp, kp = h:getPoint(), k:getPoint()
    local rx, ry, rz = hp.x - kp.x, hp.y - kp.y, hp.z - kp.z
    local P = k:getPosition()
    local hx, hz = P.x.x, P.x.z
    local hn = math.sqrt(hx * hx + hz * hz)
    if hn < 1e-6 then return nil end
    hx, hz = hx / hn, hz / hn
    local d = math.sqrt(rx * rx + rz * rz)
    local vh, vk = h:getVelocity(), k:getVelocity()
    local r3 = math.sqrt(rx * rx + ry * ry + rz * rz)
    local clos = 0
    if r3 > 1 then
        clos = -((vh.x - vk.x) * rx + (vh.y - vk.y) * ry + (vh.z - vk.z) * rz) / r3 * KT
    end
    local okP, probe = pcall(function() return h:getDrawArgumentValue(CFG.PROBE_ARG) end)
    return {
        dNm = d / NM,
        fwd = (rx * hx + rz * hz) * FT,
        right = (-rx * hz + rz * hx) * FT,
        up = ry * FT,
        clos = clos,
        probe = okP and probe or nil,
        hAlt = hp.y * FT, kAlt = kp.y * FT,
    }
end

local function inBox(r, b)
    return r.fwd >= b.fwdMin and r.fwd <= b.fwdMax and r.right >= b.rightMin and r.right <= b.rightMax
end

-- ══════════════════════════════════════════════════════════════
--  SESSION
-- ══════════════════════════════════════════════════════════════
local function newSession(r, f)
    AAR.nSession = AAR.nSession + 1
    local S = {
        n = AAR.nSession, t0 = now(), phase = "RV", phaseT = {},
        fuelRV = f,
        contacts = {}, openStart = nil,
        stops = 0, lastStop = nil,
        join = nil, overtakeMax = nil, overtakeOver10 = 0, overruns = 0, overrunT = -999,
        weapons = 0,
        probeOpenNm = nil, probeCloseNm = nil,
        dep = { sideNm = nil, side = nil, minUp = nil, minUpNm = nil },
        firstContactT = nil,
    }
    AAR.session = S
    log(string.format("S%d RV: d=%.1f NM up=%.0f ft fuel=%s lb", S.n, r.dNm, r.up, fmt(f)))
    return S
end

local function setPhase(S, p, r)
    if S.phase == p then return end
    S.phase = p
    S.phaseT[p] = now()
    log(string.format("S%d phase %s: d=%.2f NM fwd=%.0f right=%.0f up=%.0f clos=%.1f kt probe=%s",
        S.n, p, r.dNm, r.fwd, r.right, r.up, r.clos, fmt(r.probe, "%.2f")))
end

local function evaluate(S)
    local P, why = {}, {}
    local function add(code, pts, txt) P[#P + 1] = { code = code, pts = pts, txt = txt } end

    if S.join then
        add("RV_VERT", (-S.join.up >= CFG.RV_MIN_BELOW_FT) and 2 or -2,
            string.format("%.0f ft %s the tanker at 1 NM", math.abs(S.join.up), S.join.up < 0 and "below" or "above"))
        add("JOIN_SIDE", (S.join.right < 0) and 1 or -1,
            string.format("%s side at 1 NM (right=%.0f ft)", S.join.right < 0 and "left" or "right", S.join.right))
    else
        add("RV_VERT", 0, "no 1 NM snapshot")
    end
    if S.overtakeMax then
        add("OVERTAKE", (S.overtakeMax > CFG.OVERTAKE_BAD_KT) and -2 or 0,
            string.format("max closure %.1f kt inside %.1f NM (%d s > %d kt)", S.overtakeMax,
                CFG.OVERTAKE_FROM_NM, S.overtakeOver10, CFG.OVERTAKE_PLAN_KT))
    end
    add("OVERRUN", (S.overruns > 0) and -2 or 0, string.format("%d overrun(s)", S.overruns))
    add("WEAPON", (S.weapons > 0) and -5 or 0, string.format("%d shot(s) near the tanker", S.weapons))
    if #S.contacts > 0 then
        local breaks = #S.contacts - 1
        add("CONNECT", (breaks == 0) and 2 or math.max(-3, -breaks),
            string.format("%d contact(s), %d break(s)", #S.contacts, breaks))
        local sideOk = S.dep.side == nil or S.dep.side > 0
        local upOk = S.dep.minUp == nil or S.dep.minUp >= CFG.DEPART_MIN_UP_FT
        add("DEPART", (sideOk and upOk) and 1 or -2,
            string.format("%s side at %.1f NM, min up %s ft", S.dep.side and (S.dep.side > 0 and "right" or "left") or "n/a",
                CFG.DEPART_SIDE_NM, fmt(S.dep.minUp)))
    end
    local sum = 0
    for _, p in ipairs(P) do sum = sum + p.pts end
    local clipped = math.max(CFG.CAP_MIN, math.min(CFG.CAP_MAX, sum))
    return P, sum, clipped
end

local function finish(S, why)
    local P, sum, clipped = evaluate(S)
    local onload, dur = 0, 0
    for i, c in ipairs(S.contacts) do
        local on = (c.fuelStop and c.fuelStart) and (c.fuelStop - c.fuelStart) or 0
        onload = onload + on
        dur = dur + (c.tStop and (c.tStop - c.tStart) or 0)
        log(string.format("S%d contact %d: fuel %s -> %s lb (+%.0f) %.0f s | at contact fwd=%.0f right=%.0f up=%.0f clos=%.1f kt probe=%s",
            S.n, i, fmt(c.fuelStart), fmt(c.fuelStop), on, c.tStop and (c.tStop - c.tStart) or 0,
            c.fwd or 0, c.right or 0, c.up or 0, c.clos or 0, fmt(c.probe, "%.2f")))
    end
    log(string.format("S%d END (%s): contacts=%d onload=%.0f lb contact time=%.0f s | RV->contact=%s s | probe open at %s NM, closed at %s NM",
        S.n, why, #S.contacts, onload, dur,
        S.firstContactT and fmt(S.firstContactT - S.t0) or "n/a",
        fmt(S.probeOpenNm, "%.2f"), fmt(S.probeCloseNm, "%.2f")))
    for _, p in ipairs(P) do
        log(string.format("S%d %-9s %+d  %s", S.n, p.code, p.pts, p.txt))
    end
    log(string.format("S%d proposed total %+d (clipped %+d)%s", S.n, sum, clipped, CFG.SCORING and "" or "  [shadow, not applied]"))

    S.summary = { points = P, sum = sum, clipped = clipped, onload = onload, why = why, contacts = #S.contacts }
    AAR.last = S.summary
    AAR.sessions[#AAR.sessions + 1] = S.summary
    AAR.session = nil
    AAR.armed = false

    if #S.contacts > 0 then
        setFlag(CFG.FLAGS.DONE)
        if CFG.SHADOW_MSG then
            local lines = { string.format("[AAR shadow] S%d: %d contact(s), onload %.0f lb, proposed %+d", S.n, #S.contacts, onload, clipped) }
            for _, p in ipairs(P) do
                if p.pts ~= 0 then lines[#lines + 1] = string.format("  %s %+d: %s", p.code, p.pts, p.txt) end
            end
            msg(table.concat(lines, "\n"), 25)
        end
        if CFG.SCORING and TRT.addScore and clipped ~= 0 then
            TRT.addScore(clipped, "Aerial Refuel (AAR_Monitor)")
        end
        if CFG.SCORING and CFG.CALL_REFUEL_COMPLETE and TRT.onRefuelComplete then
            TRT.onRefuelComplete(CFG.PLAYER_UNIT)
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  TICK
-- ══════════════════════════════════════════════════════════════
local function tick(_, t)
    local h, k = hero(), tanker()
    if not (h and k) then return t + CFG.TICK_FAR end
    local r = rel(h, k)
    if not r then return t + CFG.TICK_FAR end
    local S = AAR.session
    local f = fuelLb(h)

    if not S then
        -- after a session ended the hero must leave RV_NM before a new session can start (AR2)
        if r.dNm > CFG.RV_NM then AAR.armed = true end
        if AAR.armed and r.dNm <= CFG.RV_NM then S = newSession(r, f) else return t + CFG.TICK_FAR end
    end

    -- probe open / close distance
    if r.probe then
        if r.probe >= CFG.PROBE_OUT and not S.probeOpenNm and #S.contacts == 0 then
            S.probeOpenNm = r.dNm
            log(string.format("S%d probe out at %.2f NM (fwd=%.0f up=%.0f)", S.n, r.dNm, r.fwd, r.up))
        end
        if r.probe <= 0.05 and S.stops > 0 and not S.openStart and not S.probeCloseNm then
            S.probeCloseNm = r.dNm
            log(string.format("S%d probe in at %.2f NM", S.n, r.dNm))
        end
    end

    local contact = S.openStart ~= nil

    if #S.contacts == 0 then
        -- pre-contact
        if r.dNm <= CFG.JOIN_NM and not S.join then
            S.join = { up = r.up, right = r.right, fwd = r.fwd, clos = r.clos, fuel = f, dNm = r.dNm }
            log(string.format("S%d JOIN snapshot: d=%.2f NM fwd=%.0f right=%.0f up=%.0f clos=%.1f kt fuel=%s lb%s",
                S.n, r.dNm, r.fwd, r.right, r.up, r.clos, fmt(f), r.fwd > 0 and "  (AHEAD of the tanker)" or ""))
            setPhase(S, "JOIN", r)
        end
        if S.join then
            if r.dNm <= CFG.OVERTAKE_FROM_NM and r.fwd < CFG.ASTERN.fwdMin and r.clos > 0 then
                if not S.overtakeMax or r.clos > S.overtakeMax then S.overtakeMax = r.clos end
                if r.clos > CFG.OVERTAKE_PLAN_KT then S.overtakeOver10 = S.overtakeOver10 + CFG.TICK_NEAR end
            end
            if r.fwd > CFG.OVERRUN_FT and r.dNm <= CFG.OVERRUN_NM and (now() - S.overrunT) > 60 then
                S.overruns = S.overruns + 1
                S.overrunT = now()
                log(string.format("S%d OVERRUN: fwd=%.0f right=%.0f up=%.0f", S.n, r.fwd, r.right, r.up))
            end
            if r.probe and r.probe >= CFG.PROBE_OUT and inBox(r, CFG.ASTERN) then
                setPhase(S, "ASTERN", r)
            elseif inBox(r, CFG.ECH_L) then
                setPhase(S, "ECHELON_L", r)
            elseif inBox(r, CFG.ECH_R) then
                setPhase(S, "ECHELON_R", r)
            end
        end
        if r.dNm > CFG.ABANDON_NM then
            log(string.format("S%d abandoned at %.1f NM, no contact", S.n, r.dNm))
            AAR.session = nil
            AAR.armed = false
            return t + CFG.TICK_FAR
        end
    elseif not contact and S.lastStop then
        -- post disconnect
        S.dep.minUp = (S.dep.minUp == nil) and r.up or math.min(S.dep.minUp, r.up)
        if r.dNm >= CFG.DEPART_SIDE_NM and not S.dep.side then
            S.dep.side = (r.right > 0) and 1 or -1
            S.dep.sideNm = r.dNm
            log(string.format("S%d depart side %s at %.2f NM (fwd=%.0f right=%.0f up=%.0f)", S.n,
                r.right > 0 and "right" or "left", r.dNm, r.fwd, r.right, r.up))
            setPhase(S, "POST", r)
        end
        if r.dNm > CFG.LEAVE_NM then
            setPhase(S, "LEAVE", r)
            S.fuelLeave = f
            finish(S, "left the tanker")
            return t + CFG.TICK_FAR
        end
    end

    return t + ((r.dNm < 2) and CFG.TICK_NEAR or CFG.TICK_FAR)
end
timer.scheduleFunction(tick, nil, now() + 3)

-- ══════════════════════════════════════════════════════════════
--  EVENTS
-- ══════════════════════════════════════════════════════════════
local H = {}
function H:onEvent(e)
    if not (e and e.initiator and e.initiator.getName) then return end
    local okN, nm = pcall(function() return e.initiator:getName() end)
    if not okN or nm ~= CFG.PLAYER_UNIT then return end

    if e.id == world.event.S_EVENT_REFUELING or e.id == world.event.S_EVENT_REFUELING_STOP then
        local h, k = hero(), tanker()
        local S = AAR.session
        if not S and h and k then
            local r0 = rel(h, k)
            if r0 then S = newSession(r0, fuelLb(h)) end   -- contact without an RV phase: late load / start in range
        end
        if not S then return end
        local f = h and fuelLb(h)
        local r = (h and k) and rel(h, k) or nil
        if e.id == world.event.S_EVENT_REFUELING then
            local c = { tStart = now(), fuelStart = f }
            if r then c.fwd, c.right, c.up, c.clos, c.probe = r.fwd, r.right, r.up, r.clos, r.probe end
            S.contacts[#S.contacts + 1] = c
            S.openStart = c
            S.lastStop = nil
            S.dep = { sideNm = nil, side = nil, minUp = nil, minUpNm = nil }   -- a reconnect restarts the departure check
            S.probeCloseNm = nil
            if not S.firstContactT then S.firstContactT = now() end
            setFlag(CFG.FLAGS.CONTACT)
            if r then setPhase(S, "CONTACT", r) end
            log(string.format("S%d CONTACT %d: fuel=%s lb%s", S.n, #S.contacts, fmt(f),
                r and string.format(" fwd=%.0f right=%.0f up=%.0f clos=%.1f kt", r.fwd, r.right, r.up, r.clos) or ""))
        else
            local c = S.openStart
            if c then
                c.tStop, c.fuelStop = now(), f
                S.openStart = nil
                S.stops = S.stops + 1
                S.lastStop = now()
                log(string.format("S%d DISCONNECT %d: fuel=%s lb (+%.0f in %.0f s)", S.n, S.stops, fmt(f),
                    (f and c.fuelStart) and (f - c.fuelStart) or 0, c.tStop - c.tStart))
            end
        end
    elseif e.id == world.event.S_EVENT_SHOT then
        local h, k = hero(), tanker()
        if h and k then
            local r = rel(h, k)
            if r and r.dNm <= CFG.WEAPON_NM then
                local S = AAR.session
                if S then S.weapons = S.weapons + 1 end
                log(string.format("WEAPON released by the hero %.1f NM from the tanker", r.dNm))
            end
        end
    end
end
world.addEventHandler(H)

log(string.format("v%s loaded (shadow=%s) hero=%s tankers=%s", CFG.VERSION, tostring(not CFG.SCORING), CFG.PLAYER_UNIT,
    table.concat(CFG.TANKERS, ",")))
