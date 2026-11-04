-- Traffic | v1.1.0
--[[
  v1.1.0 - AAR queue deconfliction (CAS (L) flight 2026-11-04, Onur: midair with TRF Hornet 41-1 on the hose).
           The log: Hornet 41 disconnected at 0.48, was "done" 60 s later (TEXACO "clear to leave"), but its DCS
           Refueling task was still open, so it stayed behind the tanker and came back for a hose 4 min later.
           * done -> the receiver's task is replaced (controller:setTask Mission): 0.5 NM right of the tanker,
             1,000 ft low, then EXIT_BRG off the tanker's heading at +EXIT_KT; removed DONE_DESPAWN_NM from the hero.
           * the hero astern / in contact (TRT.AAR session phase ASTERN or CONTACT, or within HOLD_NM of the tanker)
             -> every AI receiver not in contact HOLDS: Follow TANKER-1 at HOLD_POS (1.5 NM trail, 1,000 ft low);
             a receiver in contact finishes. Released (Refueling again) once the hero is in POST / LEAVE / no session,
             RELEASE_S after his last astern / contact moment (Onur 00:04: they wait and refuel after him).
  Light AI traffic around the CAS-1 sortie (Onur, 2026-11-01). Template and CAS (L).

  RECOVERY  When the hero is in AIRBOSS's Marshal queue (after his Marshal check-in), a 2-ship AI F/A-18C
            section "Hornet 31" (modex 410/411) is spawned REC.SPAWN_NM from Mother on a random radial at
            least REC.MIN_SEP_DEG away from the hero's (over water when one is found), inbound to an orbit
            REC.HOLD_NM out (inside the 50 NM CCA). When the hero has read back his marshal instructions
            (CV_Comms phase in REC.CV_OK) and the Marshal frequency has been quiet REC.QUIET_S, the section is
            handed to AIRBOSS the way AIRBOSS's own AI scan does it: AIRBOSS:_MarshalAI(flight, next free
            stack). It gets the stack ABOVE the hero and its Charlie time is after the hero's. AIRBOSS's own
            _GetNextMarshalFight would clear ANY holding CASE II/III flight once the player is set COMMENCING
            (while he still waits for his EAT at the fix, no one in the pattern) -> the section could land first.
            So the instance method is wrapped: our section is not cleared while the hero is still in the Marshal
            queue (airborne); after he commences AIRBOSS's 2 min pattern spacing applies (REC.HOLD_MAX_S cap). Calls are AIRBOSS / Raynor: inbound and commencing pilot voice-overs
            (SetExtraVoiceOversAI) and the Marshal reply (CV_Comms >= v1.7.5 passes AI arrivals to AIRBOSS).
            Fallback: hero gone / on deck / no readback within REC.MARSHAL_WAIT_MAX_S -> handed over anyway.
            The MOOSE file is untouched; AIRBOSS:SetHandleAION() is NOT used (it would grab any inbound
            FLIGHTGROUP).
  AAR       When Comms_Director opens a tanker RV (CD.tk, AR1 or AR2), with probability AAR.P one or (AAR.P_TWO)
            two AI receivers (single-ship groups Hornet 41 / 42, modex 420 / 421) are spawned AAR.BEHIND_NM
            behind and 1,000 ft below TANKER-1-1 with a Refueling task; as separate groups they can take both
            KC-130 hoses. TEXACO's RV Alpha reply (Comms_Director >= v1.7.10, TkrRemark) adds "One receiver
            ahead of you." / "Two receivers ahead of you, join echelon left." EMCON 2: no clear-contact calls,
            the hero moves astern when a hose is free. When an AI receiver is full (S_EVENT_REFUELING_STOP and no
            new contact for RCVD_HOLD_S; not full: PARTIAL_HOLD_S) TEXACO says "Hornet 41, Texaco 11, you
            received X.X. Clear to leave." and the receiver "Hornet 41." on 252.10 (only while the hero has an RV
            open or is within RADIO_NM of the tanker). The receivers then fly their exit leg and are removed
            DESPAWN_NM from the hero (or after LIFE_S).
            Queue credit: before the hero's first contact of that RV, while both hoses carry AI receivers and the
            hero is within WAIT_NM of the tanker, the time goes to TRT.TL.credit.tanker (Flight_Timeline
            >= v1.1.6; capped CREDIT_MAX_S): a random queue moves the plan times like threat credit.
  Not verified in DCS [V]: two AI groups on both KC-130 hoses at once; AIRBOSS handling of a section handed over
  by script (same call path as its own scan); payload.fuel at spawn; Refueling as a first-waypoint task.
  Log: [TRF] lines in dcs.log.
  Load order: after MOOSE and Airboss_Start (AIRBOSS is read lazily, as are Comms_Director, CV_Comms, TL).
  API: TRT.Traffic.TkrRemark() -> { text, clip } | nil, .version, .R (recovery state), .A (AAR state)
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.Traffic then
    env.info("[TRF] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION   = "1.1.0",
    HERO      = TRT.PLAYER_NAME or "Player_01",
    CARRIER   = "CVN",
    COUNTRY   = country.id.USA,
    TYPE      = "FA-18C_hornet",
    FUEL_KG   = 4900,              -- F/A-18C internal fuel, kg (payload.fuel)
    INT_LB    = 10860,             -- internal fuel, lb (Comms_Director INTERNAL_FUEL_LB)
    TICK      = 5,                 -- s
    REC = {
        ON = true, P = 1.0,
        NAME = "TRF Hornet 31", N = 2, CS = { 9, 3 }, MODEX = { "410", "411" },
        SPAWN_NM = 60, HOLD_NM = 32, ANGELS = 16, KT = 330, FUEL = 0.55,
        MIN_SEP_DEG = 70,
        CV_OK = { ESTABLISH = true, HOLDING = true, PENETRATION = true, APP_CHECKIN = true, APPROACH = true,
                  NEEDLES = true, BALLWAIT = true, BALL = true, GROOVE = true, ZIPLIP = true, SEEYOU = true,
                  B_UPWIND = true, B_DOWNWIND = true, B_ABEAM = true },
        QUIET_S = 8,
        MARSHAL_WAIT_MAX_S = 900,
        HOLD_MAX_S = 1500,         -- s in the Marshal queue after which the section is cleared anyway
    },
    AAR = {
        ON = true, P = 0.5, P_TWO = 0.6,
        TANKER = "TANKER-1-1",
        RX = {
            { name = "TRF Hornet 41", cs = { 9, 4, 1 }, modex = "420", say = "HORNET 41", rcvd = "tq_rcvd41", ack = "a41_ack" },
            { name = "TRF Hornet 42", cs = { 9, 4, 2 }, modex = "421", say = "HORNET 42", rcvd = "tq_rcvd42", ack = "a42_ack" },
        },
        BEHIND_NM = 2.0, LATERAL_NM = 0.3, BELOW_FT = 1000, OVERTAKE_KT = 20, FUEL = 0.40,
        FULL = 0.97,
        RCVD_HOLD_S = 10, PARTIAL_HOLD_S = 60,
        RADIO_NM = 30,
        WAIT_NM = 1.5, CREDIT_MAX_S = 600,
        EXIT_NM = 80, DESPAWN_NM = 30, LIFE_S = 2400,
        -- v1.1.0
        EXIT_RIGHT_NM = 0.5, EXIT_BRG = 30, EXIT_KT = 40, EXIT_DOWN_FT = 1000, DONE_DESPAWN_NM = 10,
        HOLD_NM = 0.15, HOLD_PH = { ASTERN = true, CONTACT = true }, RELEASE_S = 20,
        HOLD_POS = { x = -2778, y = -305 },       -- Follow offset from the tanker (m): x ahead, y up, z right
        HOLD_Z = { -400, -900 },                  -- per receiver (left of the trail line)
    },
}

local function log(s) env.info("[TRF] " .. s) end
local function now() return timer.getTime() end
local function nm2m(n) return n * 1852 end
local function m2nm(m) return m / 1852 end
local function kt2ms(k) return k * 0.514444 end
local function ft2m(f) return f * 0.3048 end
local function d2(a, b) local dx, dz = a.x - b.x, a.z - b.z; return math.sqrt(dx * dx + dz * dz) end
local function brgT(a, b) return math.deg(math.atan2(b.z - a.z, b.x - a.x)) % 360 end
local function fwd(p, brg, m)
    local r = math.rad(brg)
    return { x = p.x + m * math.cos(r), y = p.y, z = p.z + m * math.sin(r) }
end
local function angDiff(a, b) local d = math.abs((a - b) % 360); return d > 180 and 360 - d or d end
local function alive(name) local u = Unit.getByName(name); if u and u:isExist() then return u end end
local function hero() return alive(CFG.HERO) end
local function hdgOf(u)
    local o = u:getPosition()
    return math.deg(math.atan2(o.x.z, o.x.x)) % 360
end
local function spdOf(u)
    local v = u:getVelocity()
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end
local function water(p)
    local ok, st = pcall(land.getSurfaceType, { x = p.x, y = p.z })
    return ok and (st == land.SurfaceType.WATER or st == land.SurfaceType.SHALLOW_WATER)
end
local function AB() return TRT.Airboss end

-- ── group builder ──
local function unitTbl(name, cs, modex, p, hdg, altM, spdMs, fuel)
    return {
        name = name, type = CFG.TYPE, x = p.x, y = p.z, alt = altM, alt_type = "BARO",
        speed = spdMs, heading = math.rad(hdg), psi = -math.rad(hdg), skill = "High", onboard_num = modex,
        callsign = { [1] = cs[1], [2] = cs[2], [3] = cs[3], name = string.format("Hornet%d%d", cs[2], cs[3]) },
        payload = { fuel = CFG.FUEL_KG * fuel, flare = 60, chaff = 60, gun = 100, pylons = {} },
    }
end
local function wpt(p, altM, spdMs, tasks, name)
    return {
        x = p.x, y = p.z, alt = altM, alt_type = "BARO", type = "Turning Point", action = "Turning Point",
        speed = spdMs, speed_locked = true, name = name,
        task = { id = "ComboTask", params = { tasks = tasks or {} } },
    }
end
local function spawn(gname, units, points)
    local g = { name = gname, task = "Nothing", uncontrolled = false, route = { points = points }, units = units }
    local ok, res = pcall(coalition.addGroup, CFG.COUNTRY, Group.Category.AIRPLANE, g)
    if not ok or not res then log("spawn FAILED " .. gname .. ": " .. tostring(res)); return nil end
    log(string.format("spawned %s (%d unit(s))", gname, #units))
    return res
end

-- ══════════════════════════════════════════════════════════════
--  RECOVERY TRAFFIC
-- ══════════════════════════════════════════════════════════════
local R = { state = nil, n = 0 }

local function heroInMarshal(ab)
    local h = hero(); if not (h and ab and ab.Qmarshal) then return false end
    local okG, gname = pcall(function() return h:getGroup():getName() end)
    if not okG then return false end
    for _, f in pairs(ab.Qmarshal) do if f.groupname == gname then return true end end
    return false
end

local function recSpawn(ab)
    local cv = alive(CFG.CARRIER); if not cv then return end
    local h = hero()
    local cp = cv:getPoint()
    local hr = h and brgT(cp, h:getPoint()) or 0
    local pick, pickWet
    for _ = 1, 36 do
        local b = math.random(0, 359)
        if angDiff(b, hr) >= CFG.REC.MIN_SEP_DEG then
            local sp, hp = fwd(cp, b, nm2m(CFG.REC.SPAWN_NM)), fwd(cp, b, nm2m(CFG.REC.HOLD_NM))
            pick = pick or b
            if water(sp) and water(hp) then pickWet = b; break end
        end
    end
    local b = pickWet or pick or ((hr + 120) % 360)
    local altM, spd = ft2m(CFG.REC.ANGELS * 1000), kt2ms(CFG.REC.KT)
    local sp, hp = fwd(cp, b, nm2m(CFG.REC.SPAWN_NM)), fwd(cp, b, nm2m(CFG.REC.HOLD_NM))
    local inb = (b + 180) % 360
    R.n = R.n + 1
    R.name = CFG.REC.NAME .. (R.n > 1 and (" #" .. R.n) or "")
    local units = {}
    for i = 1, CFG.REC.N do
        local up = fwd(fwd(sp, inb + 180, nm2m(0.3) * (i - 1)), inb - 90, nm2m(0.3) * (i - 1))
        units[i] = unitTbl(R.name .. "-" .. i, { CFG.REC.CS[1], CFG.REC.CS[2], i }, CFG.REC.MODEX[i] or "41" .. i,
            up, inb, altM, spd, CFG.REC.FUEL)
    end
    local orbit = { number = 1, auto = false, enabled = true, id = "Orbit",
                    params = { pattern = "Circle", point = { x = hp.x, y = hp.z }, altitude = altM, speed = kt2ms(274) } }
    if spawn(R.name, units, { wpt(sp, altM, spd, nil, "Inbound"), wpt(hp, altM, spd, { orbit }, "Wait") }) then
        R.state, R.t0, R.quietSince = "INBOUND", now(), nil
        log(string.format("recovery section %s: radial %03d T (hero %03d T), %d NM, angels %d, wet=%s",
            R.name, b, hr, CFG.REC.SPAWN_NM, CFG.REC.ANGELS, tostring(pickWet ~= nil)))
        pcall(function() ab:SetExtraVoiceOversAI(true) end)
    else
        R.state = "OFF"
    end
end

--- AIRBOSS instance wrap: no clearance for our section while the hero is still in Marshal.
local function hookClearance(ab)
    if R.hooked then return end
    local orig = ab._GetNextMarshalFight
    if type(orig) ~= "function" then log("AIRBOSS _GetNextMarshalFight not found, no clearance hold"); return end
    ab._GetNextMarshalFight = function(self)
        local f = orig(self)
        if f and R.name and f.groupname == R.name then
            local h = hero()
            local held = R.marshalT and (now() - R.marshalT) > CFG.REC.HOLD_MAX_S
            if h and h:inAir() and heroInMarshal(self) and not held then
                if not R.holdLogged then R.holdLogged = true; log("section clearance held: hero still in Marshal") end
                return nil
            end
            if not R.clearLogged then R.clearLogged = true; log("section clearance released (hero commenced / gone)") end
        end
        return f
    end
    R.hooked = true
end

local function marshalQuiet(ab, t)
    local cv = TRT.CV
    local busy = (cv and (cv.busy or (cv.q and #cv.q > 0)))
        or (type(ab.RQMarshal) == "table" and #ab.RQMarshal > 0)
    if busy then R.quietSince = nil; return false end
    R.quietSince = R.quietSince or t
    return t - R.quietSince >= CFG.REC.QUIET_S
end

local function recTick(t)
    local ab = AB()
    if not (CFG.REC.ON and ab) or R.state == "OFF" or R.state == "MARSHAL" then return end
    if not R.state then
        if heroInMarshal(ab) then
            if math.random() < CFG.REC.P then recSpawn(ab) else R.state = "OFF"; log("recovery traffic: not this time") end
        end
        return
    end
    -- INBOUND: hand the section to AIRBOSS
    local okG, grp = pcall(GROUP.FindByName, GROUP, R.name)
    if not okG or not grp or not grp:IsAlive() then
        if t - R.t0 > 60 then R.state = "OFF"; log("recovery section gone before Marshal") end
        return
    end
    local flight = ab:_GetFlightFromGroupInQueue(grp, ab.flights)
    if not flight then return end                       -- not yet inside the CCA / not yet scanned
    if flight.flag ~= -100 then R.state = "MARSHAL"; return end
    local h = hero()
    local cv = TRT.CV
    local heroDone = (not h) or (not h:inAir())
    local ready = cv and cv.phase and CFG.REC.CV_OK[cv.phase]
    local late = t - R.t0 > CFG.REC.MARSHAL_WAIT_MAX_S
    if not (heroDone or late or (ready and marshalQuiet(ab, t))) then return end
    hookClearance(ab)
    R.marshalT = t
    local stack = ab:_GetFreeStack(true)
    if stack then
        ab:_MarshalAI(flight, stack)
        log(string.format("recovery section %s -> AIRBOSS Marshal stack %d (hero %s, CV %s)", R.name, stack,
            heroDone and "not airborne" or "airborne", tostring(cv and cv.phase)))
    else
        ab:_WaitAI(flight)
        log("recovery section " .. R.name .. " -> AIRBOSS waiting queue (no free stack)")
    end
    R.state = "MARSHAL"
end

-- ══════════════════════════════════════════════════════════════
--  AAR QUEUE
-- ══════════════════════════════════════════════════════════════
local A = { lastTk = nil, rx = {}, n = 0, wait = 0, heroContact = false, sessionTk = nil, lastT = nil }

local function rxActive()
    local n = 0
    for _, r in ipairs(A.rx) do
        if not r.done and alive(r.unit) then n = n + 1 end
    end
    return n
end

local function aarSpawn(tk)
    local k = alive(CFG.AAR.TANKER); if not k then return end
    local kp, kh = k:getPoint(), hdgOf(k)
    local spd = spdOf(k) + kt2ms(CFG.AAR.OVERTAKE_KT)
    local altM = kp.y - ft2m(CFG.AAR.BELOW_FT)
    local nRx = (math.random() < CFG.AAR.P_TWO) and 2 or 1
    local base = fwd(kp, kh + 180, nm2m(CFG.AAR.BEHIND_NM))
    local exitP = fwd(kp, kh, nm2m(CFG.AAR.EXIT_NM))
    A.n = A.n + 1
    for i = 1, nRx do
        local c = CFG.AAR.RX[i]
        local gname = c.name .. (A.n > 1 and (" #" .. A.n) or "")
        local p = fwd(base, kh - 90, nm2m(CFG.AAR.LATERAL_NM) * i)
        local refuel = { number = 1, auto = false, enabled = true, id = "Refueling", params = {} }
        local u = unitTbl(gname .. "-1", c.cs, c.modex, p, kh, altM, spd, CFG.AAR.FUEL)
        if spawn(gname, { u }, { wpt(p, altM, spd, { refuel }, "Join tanker"), wpt(exitP, altM, spd, nil, "Exit") }) then
            A.rx[#A.rx + 1] = { cfg = c, group = gname, unit = gname .. "-1", t0 = now(), f0 = nil,
                                contact = false, lastStop = nil, done = false, tk = tk }
        end
    end
    log(string.format("AAR queue: %d AI receiver(s) %.1f NM behind %s (AR%s)", nRx, CFG.AAR.BEHIND_NM,
        CFG.AAR.TANKER, tostring(tk and tk.ar)))
end

local function klb(lb) return string.format("%.1f", math.floor(math.max(0, lb) / 100 + 0.5) / 10) end
local function tnum(s)
    local t = {}
    for c in s:gmatch(".") do
        if c == "." then t[#t + 1] = "t_point" elseif c:match("%d") then t[#t + 1] = "t_" .. c end
    end
    return t
end
local function seq(ch, ...)
    local out = { ch = ch, "cv:sq_up" }
    for _, x in ipairs({ ... }) do
        if type(x) == "table" then for _, y in ipairs(x) do out[#out + 1] = y end else out[#out + 1] = x end
    end
    out[#out + 1] = "cv:sq_dn"
    return out
end
local function voiced(s)
    local RD = TRT.CD_RADIO
    if not (RD and RD.has) then return nil end
    for _, id in ipairs(s) do
        if type(id) == "string" and not RD.has(id) then log("text only, missing clip " .. id); return nil end
    end
    return s
end

-- v1.1.0 controller helpers
local function ctl(r)
    local g = Group.getByName(r.group)
    return g and g:isExist() and g:getController() or nil
end
local function setMission(r, points, why)
    local c = ctl(r); if not c then return false end
    local ok, err = pcall(c.setTask, c, { id = "Mission", params = { route = { points = points } } })
    if not ok then log("setTask FAILED " .. r.group .. " (" .. why .. "): " .. tostring(err)) end
    return ok
end
local function rxExit(r)
    local k, u = alive(CFG.AAR.TANKER), alive(r.unit)
    if not (k and u) then return end
    local kp, kh = k:getPoint(), hdgOf(k)
    local spd = spdOf(k) + kt2ms(CFG.AAR.EXIT_KT)
    local altM = kp.y - ft2m(CFG.AAR.BELOW_FT)
    local p1 = fwd(kp, kh + 90, nm2m(CFG.AAR.EXIT_RIGHT_NM))
    local p2 = fwd(p1, kh + CFG.AAR.EXIT_BRG, nm2m(CFG.AAR.EXIT_NM))
    if setMission(r, { wpt(u:getPoint(), u:getPoint().y, spd, nil, "Leave"), wpt(p1, altM, spd, nil, "Echelon right"),
                       wpt(p2, altM - ft2m(CFG.AAR.EXIT_DOWN_FT), spd, nil, "Exit") }, "exit") then
        r.exitT = now()
        log("AI receiver " .. r.unit .. " cleared off: exit route (refueling task ended)")
    end
end
local function rxHold(r, i)
    local k = alive(CFG.AAR.TANKER); if not k then return end
    local c = ctl(r); if not c then return end
    local okG, gid = pcall(function() return k:getGroup():getID() end)
    if not okG then return end
    local pos = { x = CFG.AAR.HOLD_POS.x, y = CFG.AAR.HOLD_POS.y, z = CFG.AAR.HOLD_Z[i] or CFG.AAR.HOLD_Z[1] }
    local ok, err = pcall(c.setTask, c, { id = "Follow", params = { groupId = gid, pos = pos, lastWptIndexFlag = false } })
    if ok then
        r.held = true
        log(string.format("AI receiver %s holds: 1.5 NM trail of the tanker (hero astern / in contact)", r.unit))
    else
        log("Follow FAILED " .. r.group .. ": " .. tostring(err))
    end
end
local function rxRelease(r)
    local k, u = alive(CFG.AAR.TANKER), alive(r.unit)
    if not (k and u) then return end
    local spd = spdOf(k) + kt2ms(CFG.AAR.OVERTAKE_KT)
    local refuel = { number = 1, auto = false, enabled = true, id = "Refueling", params = {} }
    local exitP = fwd(k:getPoint(), hdgOf(k), nm2m(CFG.AAR.EXIT_NM))
    if setMission(r, { wpt(u:getPoint(), u:getPoint().y, spd, { refuel }, "Join tanker"),
                       wpt(exitP, u:getPoint().y, spd, nil, "Exit") }, "release") then
        r.held = false
        if r.lastStop then r.lastStop = now() end   -- the partial-fill timer restarts after the hold
        log("AI receiver " .. r.unit .. " released: refueling after the hero")
    end
end
local function heroOnHose(h, k)
    local am = TRT.AAR and TRT.AAR.session
    if am and am.phase and CFG.AAR.HOLD_PH[am.phase] then return true end
    return h and k and m2nm(d2(h:getPoint(), k:getPoint())) <= CFG.AAR.HOLD_NM or false
end

local function rxDone(r, t)
    r.done = true
    rxExit(r)   -- v1.1.0
    local u = alive(r.unit)
    local f1 = (u and u:getFuel()) or r.f1 or r.f0 or 0
    local lb = math.max(0, (f1 - (r.f0 or f1)) * CFG.INT_LB)
    local x = klb(lb)
    log(string.format("AI receiver %s done: onload %d lb (fuel %.2f -> %.2f)", r.unit, math.floor(lb + 0.5), r.f0 or -1, f1))
    local RD = TRT.CD_RADIO
    local h, k = hero(), alive(CFG.AAR.TANKER)
    local near = (TRT.CD and TRT.CD.tk) or (h and k and m2nm(d2(h:getPoint(), k:getPoint())) <= CFG.AAR.RADIO_NM)
    if not (RD and RD.Q and near) then return end
    local c = r.cfg
    RD.Q(string.format("[TEXACO] %s, Texaco 11, you received %s. Clear to leave.", c.say, x), 8, 1, nil, nil,
        voiced(seq("TEXACO", c.rcvd, tnum(x), 0.15, "tq_ctl")))
    RD.Q(string.format("[%s] %s.", c.say, c.say), 6, 0.8, nil, 2, voiced(seq("TEXACO", c.ack)))
    RD.QPlay()
end

local function aarTick(t, dt)
    if not CFG.AAR.ON then return end
    local cd = TRT.CD
    local tk = cd and cd.tk
    if tk and tk ~= A.lastTk then
        A.lastTk = tk
        A.sessionTk, A.heroContact = tk, false
        if rxActive() == 0 and alive(CFG.AAR.TANKER) then
            if math.random() < CFG.AAR.P then aarSpawn(tk) else log("AAR queue: not this time (AR" .. tostring(tk.ar) .. ")") end
        end
    end
    -- receivers: done / cleanup
    local h, k = hero(), alive(CFG.AAR.TANKER)
    -- v1.1.0 hero on a hose -> receivers not in contact hold in trail; released RELEASE_S after he is off
    if heroOnHose(h, k) then A.heroHoseT = t end
    local hold = A.heroHoseT and (t - A.heroHoseT) < CFG.AAR.RELEASE_S
    for i, r in ipairs(A.rx) do
        local u = not r.done and not r.gone and alive(r.unit)
        local full = u and r.lastStop and (u:getFuel() or 0) >= CFG.AAR.FULL   -- a full one goes "done", not on hold
        if u and not full then
            if hold and not r.held and not r.contact then rxHold(r, i)
            elseif not hold and r.held then rxRelease(r) end
        end
    end
    for _, r in ipairs(A.rx) do
        local u = alive(r.unit)
        if not r.done and u and not r.contact and r.lastStop and not r.held then
            local f = u:getFuel() or 0
            if (f >= CFG.AAR.FULL and t - r.lastStop >= CFG.AAR.RCVD_HOLD_S) or t - r.lastStop >= CFG.AAR.PARTIAL_HOLD_S then
                rxDone(r, t)
            end
        end
        if not r.gone then
            local far = u and h and m2nm(d2(u:getPoint(), h:getPoint()))
                > (r.exitT and CFG.AAR.DONE_DESPAWN_NM or CFG.AAR.DESPAWN_NM)   -- v1.1.0
            if (u and r.done and (far or not h)) or (u and t - r.t0 > CFG.AAR.LIFE_S) then
                local g = Group.getByName(r.group)
                if g then pcall(g.destroy, g) end
                r.gone = true
                log("AI receiver " .. r.group .. " removed")
            elseif not u then
                r.gone, r.done = true, true
            end
        end
    end
    -- queue credit for the hero (before his first contact of this RV)
    local nIn = 0
    for _, r in ipairs(A.rx) do if r.contact and not r.done and alive(r.unit) then nIn = nIn + 1 end end
    if h and k and tk and tk == A.sessionTk and not A.heroContact and nIn >= 2          -- both hoses taken
        and m2nm(d2(h:getPoint(), k:getPoint())) <= CFG.AAR.WAIT_NM then
        A.wait = math.min(CFG.AAR.CREDIT_MAX_S, A.wait + dt)
        local tl = TRT.TL
        if tl and tl.credit then tl.credit.tanker = A.wait end
        if not A.waitLogged then A.waitLogged = true; log("hero waiting for a hose (queue credit running)") end
    end
end

local function rxByUnit(name)
    for _, r in ipairs(A.rx) do if r.unit == name then return r end end
end

local EH = {}
function EH:onEvent(e)
    if not (e and e.initiator and (e.id == world.event.S_EVENT_REFUELING or e.id == world.event.S_EVENT_REFUELING_STOP)) then return end
    local okN, nm = pcall(function() return e.initiator:getName() end)
    if not okN then return end
    local on = (e.id == world.event.S_EVENT_REFUELING)
    if nm == CFG.HERO then
        if on and not A.heroContact then
            A.heroContact = true
            if A.wait > 0 then log(string.format("hero contact, queue wait %d s -> TL credit.tanker", math.floor(A.wait + 0.5))) end
        end
        return
    end
    local r = rxByUnit(nm); if not r then return end
    local okF, f = pcall(function() return e.initiator:getFuel() end)
    f = okF and f or nil
    if on then
        r.contact = true
        r.f0 = r.f0 or f
        log(string.format("AI receiver %s contact (fuel %.2f)", nm, f or -1))
    else
        r.contact, r.lastStop, r.f1 = false, now(), f
        log(string.format("AI receiver %s disconnect (fuel %.2f)", nm, f or -1))
    end
end
world.addEventHandler(EH)

-- ══════════════════════════════════════════════════════════════
--  API + TICK
-- ══════════════════════════════════════════════════════════════
local function TkrRemark()
    local cd = TRT.CD
    if not (cd and cd.tk and cd.tk == A.sessionTk) then return nil end
    local n = rxActive()
    if n >= 2 then return { text = "Two receivers ahead of you, join echelon left.", clip = "tq_rmk2" } end
    if n == 1 then return { text = "One receiver ahead of you.", clip = "tq_rmk1" } end
    return nil
end

TRT.Traffic = { version = CFG.VERSION, TkrRemark = TkrRemark, R = R, A = A }

timer.scheduleFunction(function(_, t)
    local ok, err = pcall(function()
        local dt = A.lastT and (t - A.lastT) or 0
        A.lastT = t
        recTick(t)
        aarTick(t, dt)
    end)
    if not ok then log("tick error: " .. tostring(err)) end
    return t + CFG.TICK
end, nil, timer.getTime() + 10)

log(string.format("Traffic v%s loaded: recovery %s (P %.2f), AAR queue %s (P %.2f, two %.2f), hero %s",
    CFG.VERSION, tostring(CFG.REC.ON), CFG.REC.P, tostring(CFG.AAR.ON), CFG.AAR.P, CFG.AAR.P_TWO, CFG.HERO))
