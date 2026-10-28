-- Pilot_Banter | v1.0.1
--[[
  v1.0.1: silent while working a JTAC (Comms_Director phases in CFG.SILENT_CD): the native
          DCS JTAC voice is not visible to RadioBusy(), so lines overlapped it (CAS-1 test
          2026-10-28: feet_dry / feet_wet during JTAC talk). good_hits waits 10 s after the
          kill so the JTAC's BDA call goes first.
  The pilot talking to himself (CAS (L) only; not part of the template build).

  Short cockpit lines at a few moments of the sortie, played with outSoundForGroup
  (no radio, no frequency). Each moment has 3-6 recorded variants, picked at random
  without repeats (shuffle bag); each moment fires with a probability, so two flights
  do not sound the same.

  Rules (design 2026-10-28):
    * Reaction, never instruction: a line only follows something that has already
      happened (canopy closed, cat shot, trap graded). Text never tells the player
      what to do next.
    * Radio first: nothing starts while CV_Comms, Comms_Director or AIRBOSS has a
      transmission playing or queued, while Comms_Director holds a deferred call or
      waits for a controller reply. A line that cannot start within its TTL is
      dropped, not delayed (a late reaction is worse than none).
    * Silent at high workload: CV_Comms phases in CFG.SILENT_CV (needles, ball,
      groove, Case I/II pattern, bolter pattern, pending Marshal reply) and while
      Flight_Timeline reports ENGAGED. Trap / bolter / waveoff / post-trap moments
      ignore the phase rule (CFG.MOMENTS[..].any), never the radio rule.
    * Rare: CFG.MIN_GAP s between two lines (per-moment .gap overrides it),
      per-moment cooldown .cd, at most CFG.MAX_LINES per mission.
    * A line already playing cannot be stopped (no DCS API for outSound). If a radio
      call starts during it, "[PB] overlap" is logged so the rate can be measured.

  Moments (source -> moment):
    external-model arg 38 open -> shut, on deck, before any landing   canopy_close
    PlaneCaptain milestone START / CHECKS                             engines_on / checks_done
    S_EVENT_TAKEOFF or Flight_Timeline TL.launched (once until the
      hero has been stopped on deck for REARM_DECK_S, so a bolter
      touch-and-go never reads as a cat shot)                         cat_shot
    Comms_Director surface monitor CD.surf LAND / WATER, airborne      feet_dry / feet_wet
    S_EVENT_REFUELING (hero)                                          tanker_in
    Comms_Director CD.deadJ1 / CD.deadJ2 false -> true                good_hits
    Flight_Timeline TL.engaged true -> false after >= THREAT_MIN_S    threat_over
    AIRBOSS OnAfterLSOGrade (hero): _OK_/OK, (OK), --/CUT landed      trap_good / trap_fair / trap_poor
                                    -- (BOLTER), WO/WOP/OWO/WOFD      bolter / waveoff
    arg 38 shut -> open on deck after a landing                       canopy_open
    Deck_Park flag 1910 -> 1 / 2 (post-trap shutdown), after the
      Score_Display medal card                                        shutdown
  Not yet: BINGO / JOKER (Flight_Timeline numbers are placeholders until calibrated).

  Verified in the repo, not yet in DCS for this script:
    * getDrawArgumentValue works on the hero (PlaneCaptain reads args 8/9/17/18/21/22/25/85,
      launch bar 85 calibrated in flight 2026-10-26). Arg 38 = canopy is listed as
      "already explained" in PlaneCaptain's calibration skip list; its 0 = shut / 1 = open
      direction is NOT measured: every canopy state change is logged with the value.
    * outSoundForCoalition("Sounds/SCORE/x.ogg") plays (Score_Display). outSoundForGroup with
      "Sounds/PB/x.ogg" is assumed to resolve the same way; mixer channel / volume unknown.
    * math.random is not used (no side effect on other scripts): own Park-Miller generator,
      seeded from a table address (+ os.time when the sandbox exposes os) and re-mixed with
      the time of every event (human timing). Seed is logged. Whether table addresses
      differ between DCS runs is not verified.

  Clips: tts/pb_clips.csv -> python tts/make_clips.py --set pb
         -> tools/pilot_banter/out/Sounds/PB/*.ogg and the AUDIO block below (rewritten in
         place between the markers; do not edit it by hand). A moment's variants are the
         AUDIO keys <moment>_<n>; a moment without clips is silent.
  Install: python tools/pilot_banter/install_pilot_banter.py "<...>/Close Air Support (L).miz"
  Load order: free. Everything (TRT.CV / CD / TL / PlaneCaptain / Airboss / Menu) is read
         lazily on the tick; the AIRBOSS grade hook is installed when TRT.Airboss appears.
  F10: INFO > "Pilot thoughts: ON/OFF" (Menu_Manager).
  API: TRT.PB.Say(moment, why) (test hook), TRT.PB.on, TRT.PB.version
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.PB then
    env.info("[PB] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION      = "1.0.1",
    ENABLED      = true,           -- start state of the F10 toggle
    SND_DIR      = "Sounds/PB/",
    CARRIER_UNIT = "CVN",
    TICK         = 0.5,            -- s
    MIN_GAP      = 30,             -- s between two lines (default; .gap per moment)
    MAX_LINES    = 14,             -- per mission
    TAIL         = 0.3,            -- s after a clip before anything else of ours may start
    SUBTITLE     = false,          -- true: "(467, to himself) ..." text for SUB_DUR s
    SUB_DUR      = 4,
    CANOPY_ARG   = 38,
    CANOPY_OPEN  = 0.80,           -- arg >= : open
    CANOPY_SHUT  = 0.02,           -- arg <= : shut
    CANOPY_TICKS = 2,              -- consecutive ticks before a state change counts
    REARM_REL_MS = 3,              -- m/s relative to the carrier = "stopped on deck"
    REARM_DECK_S = 30,             -- s stopped on deck before cat_shot is armed again
    THREAT_MIN_S = 20,             -- s ENGAGED before threat_over may follow
    DECK_PARK_FLAG = 1910,
    MENU_SECTION = "INFO",
    MENU_ORDER   = 90,

    -- CV_Comms phases with no banter (workload / controller reply pending)
    SILENT_CV = {
        CHECKIN_SENT = true, READBACK = true,
        NEEDLES = true, FINAL = true, BALLWAIT = true, BALL = true, GROOVE = true,
        ZIPLIP = true, B_UPWIND = true, B_DOWNWIND = true, B_ABEAM = true,
    },
    -- v1.0.1: Comms_Director phases with no banter (native JTAC radio is not detectable)
    SILENT_CD = { JTAC1 = true, JTAC2 = true },

    -- p = probability the moment speaks · delay = s after the event · ttl = s it may wait
    -- for a quiet radio after the delay · cd = s before the same moment may speak again
    -- gap = min s since our previous line (default MIN_GAP) · any = ignore SILENT_CV / ENGAGED
    MOMENTS = {
        canopy_close = { p = 0.85, delay = 1.0, ttl = 12, cd = 300, gap = 15 },   -- deck: little radio,
        engines_on   = { p = 0.60, delay = 2.0, ttl = 15, cd = 600, gap = 15 },   -- and these three often
        checks_done  = { p = 0.70, delay = 2.0, ttl = 20, cd = 600, gap = 15 },   -- come close together
        cat_shot     = { p = 0.85, delay = 3.5, ttl = 12, cd = 120 },
        feet_dry     = { p = 0.70, delay = 1.0, ttl = 20, cd = 600 },
        feet_wet     = { p = 0.70, delay = 1.0, ttl = 20, cd = 600 },
        tanker_in    = { p = 0.70, delay = 1.5, ttl = 8,  cd = 300 },
        good_hits    = { p = 0.75, delay = 10.0, ttl = 30, cd = 120 },   -- v1.0.1: after the JTAC BDA
        threat_over  = { p = 0.90, delay = 2.0, ttl = 20, cd = 300 },
        trap_good    = { p = 0.90, delay = 1.0, ttl = 25, cd = 60, gap = 10, any = true },
        trap_fair    = { p = 0.90, delay = 1.0, ttl = 25, cd = 60, gap = 10, any = true },
        trap_poor    = { p = 0.90, delay = 1.0, ttl = 25, cd = 60, gap = 10, any = true },
        bolter       = { p = 0.80, delay = 0.5, ttl = 10, cd = 60, gap = 10, any = true },
        waveoff      = { p = 0.80, delay = 0.5, ttl = 10, cd = 60, gap = 10, any = true },
        canopy_open  = { p = 0.60, delay = 1.5, ttl = 12, cd = 600, gap = 12, any = true },
        shutdown     = { p = 0.85, delay = 17,  ttl = 20, cd = 600, gap = 12, any = true },
    },

    -- BEGIN AUDIO (generated by tts/make_clips.py --set pb; do not edit by hand)
    AUDIO = {
        canopy_close_1     = { len = 1.88, text = "Okay... canopy's coming down." },
        canopy_close_2     = { len = 1.89, text = "Alright. Lid's closed." },
        canopy_close_3     = { len = 1.83, text = "There we go. Sealed up." },
        canopy_close_4     = { len = 2.08, text = "Canopy down, and locked. Good." },
        canopy_close_5     = { len = 2.01, text = "Bye-bye, fresh air." },
        canopy_close_6     = { len = 1.99, text = "Okay. Closing up shop." },
        engines_on_1       = { len = 2.01, text = "Two good motors. Nice." },
        engines_on_2       = { len = 1.61, text = "Both turning. Good." },
        engines_on_3       = { len = 2.41, text = "Engines up... everything looks normal." },
        engines_on_4       = { len = 1.58, text = "Alright, we're alive." },
        engines_on_5       = { len = 1.76, text = "And... both engines online." },
        checks_done_1      = { len = 2.20, text = "Checks complete. Let's go to work." },
        checks_done_2      = { len = 2.90, text = "Okay, that's everything. Waiting on the director." },
        checks_done_3      = { len = 2.46, text = "Alright. Ready when they are." },
        checks_done_4      = { len = 1.82, text = "Good to go. Now we wait." },
        cat_shot_1         = { len = 1.53, text = "Whoo... good shot." },
        cat_shot_2         = { len = 1.22, text = "And we're flying." },
        cat_shot_3         = { len = 1.32, text = "Never gets old." },
        cat_shot_4         = { len = 1.92, text = "Good shot. Here we go." },
        cat_shot_5         = { len = 1.58, text = "Ugh... every single time." },
        cat_shot_6         = { len = 2.09, text = "Off the pointy end. Nice." },
        feet_dry_1         = { len = 1.80, text = "Feet dry. Eyes open." },
        feet_dry_2         = { len = 2.13, text = "Land below. Head on a swivel." },
        feet_dry_3         = { len = 2.51, text = "Okay, over land now. Stay sharp." },
        feet_dry_4         = { len = 2.20, text = "Feet dry... let's be careful out here." },
        feet_wet_1         = { len = 1.97, text = "Feet wet. That feels better." },
        feet_wet_2         = { len = 1.99, text = "Water below. Almost home." },
        feet_wet_3         = { len = 2.11, text = "Okay, back over the water." },
        feet_wet_4         = { len = 2.18, text = "Feet wet. Let's go find the boat." },
        tanker_in_1        = { len = 1.10, text = "And... we're in." },
        tanker_in_2        = { len = 1.79, text = "Contact. Hold it steady..." },
        tanker_in_3        = { len = 2.36, text = "Okay, plugged. Don't move." },
        tanker_in_4        = { len = 1.41, text = "Got it. Easy now." },
        good_hits_1        = { len = 1.54, text = "Yeah. Good hits." },
        good_hits_2        = { len = 1.00, text = "That'll do it." },
        good_hits_3        = { len = 1.88, text = "Nice. Right on target." },
        good_hits_4        = { len = 2.55, text = "Okay... that one's done." },
        threat_over_1      = { len = 2.06, text = "Okay... okay. Still here." },
        threat_over_2      = { len = 1.63, text = "Phew. That was close." },
        threat_over_3      = { len = 1.31, text = "Alright. Breathe." },
        threat_over_4      = { len = 2.12, text = "Okay, we're clear. Back to work." },
        trap_good_1        = { len = 1.50, text = "Yes! Nailed it." },
        trap_good_2        = { len = 1.41, text = "Oh, that felt good." },
        trap_good_3        = { len = 1.23, text = "That's how you do it." },
        trap_good_4        = { len = 2.22, text = "Okay! Paddles will like that one." },
        trap_fair_1        = { len = 1.79, text = "Not pretty, but I'll take it." },
        trap_fair_2        = { len = 1.94, text = "Okay. Fair pass." },
        trap_fair_3        = { len = 1.86, text = "On deck. Could've been better." },
        trap_poor_1        = { len = 1.67, text = "Ugh. That was ugly." },
        trap_poor_2        = { len = 2.45, text = "Okay... I'm going to hear about that one." },
        trap_poor_3        = { len = 1.36, text = "On deck, at least." },
        trap_poor_4        = { len = 2.55, text = "Well... that wasn't my best." },
        bolter_1           = { len = 0.87, text = "Come on..." },
        bolter_2           = { len = 1.53, text = "Bolter. Again." },
        bolter_3           = { len = 1.70, text = "Ugh. One more time." },
        bolter_4           = { len = 1.76, text = "Missed the wires... okay, okay." },
        waveoff_1          = { len = 2.03, text = "Waved off. Okay, around again." },
        waveoff_2          = { len = 2.12, text = "Alright, alright. Next one." },
        waveoff_3          = { len = 1.15, text = "Not that time." },
        canopy_open_1      = { len = 1.58, text = "Ahh. Fresh air." },
        canopy_open_2      = { len = 1.84, text = "Okay. Home sweet home." },
        canopy_open_3      = { len = 1.72, text = "That's it. Open her up." },
        shutdown_1         = { len = 1.64, text = "Another day at the office." },
        shutdown_2         = { len = 1.70, text = "Okay. That's a wrap." },
        shutdown_3         = { len = 2.11, text = "Good flight. Time for coffee." },
        shutdown_4         = { len = 1.82, text = "And... done. Debrief time." },
    },
    -- END AUDIO
}

local HERO = TRT.PLAYER_NAME or "Player_01"

local PB = {
    version   = CFG.VERSION,
    on        = CFG.ENABLED,
    pending   = {},        -- { name, why, t0 }
    bags      = {},        -- moment -> remaining ids
    lastId    = {},        -- moment -> last id played
    lastPlay  = {},        -- moment -> timer.getTime() of the last line
    lastLine  = -1e9,
    busyUntil = 0,
    lines     = 0,
    playing   = nil,       -- { id, t1, overlap }
    w = {                  -- watchers (edge detection)
        can = { state = nil, cand = nil, n = 0, logged = false },
        landed = false,     -- hero has landed since the last takeoff
        catFired = false, stopSince = nil,
        pcStart = nil, pcChecks = nil,
        tlLaunched = nil,
        surf = nil,
        dead1 = nil, dead2 = nil,
        engaged = false, engT0 = nil,
        park = nil,
    },
    abHooked  = false,
    menu      = false,
}
TRT.PB = PB

local function now() return timer.getTime() end
local function Log(s) env.info("[PB] " .. s) end

-- ── random: Park-Miller minimal standard, local state (math.random untouched) ──
local RNG = { s = 1 }
local function Seed()
    local s = 0
    local addr = string.match(tostring({}), "(%x+)$")
    if addr then s = s + (tonumber(string.sub(addr, -7), 16) or 0) end
    local okT, t = pcall(function() return os and os.time and os.time() end)
    if okT and type(t) == "number" then s = s + t end
    s = s + math.floor((now() % 1) * 1000003)
    RNG.s = (s % 2147483646) + 1
    for _ = 1, 12 do RNG.s = (RNG.s * 16807) % 2147483647 end   -- close seeds -> unrelated outputs
    return RNG.s
end
local function Rand()                                -- [0, 1)
    RNG.s = (RNG.s * 16807) % 2147483647
    return (RNG.s - 1) / 2147483646
end
-- Human timing is the only real entropy in a single-player mission (mission time is
-- deterministic, os is usually sandboxed away): every event folds its time in (ms).
local function Mix(x)
    RNG.s = ((RNG.s + math.floor(x)) % 2147483646) + 1
    for _ = 1, 6 do RNG.s = (RNG.s * 16807) % 2147483647 end
end

-- ── hero / world helpers ──
local function Hero()
    local u = Unit.getByName(HERO)
    if u and u:isExist() then return u end
    return nil
end

local function IsHero(obj)
    if not obj then return false end
    local ok, n = pcall(obj.getName, obj)
    return ok and n == HERO
end

local function Arg(u, a)
    local ok, v = pcall(u.getDrawArgumentValue, u, a)
    if ok and type(v) == "number" then return v end
    return nil
end

local function RelSpeed(u)                           -- m/s relative to the carrier
    local okv, v = pcall(u.getVelocity, u)
    if not okv or type(v) ~= "table" then return nil end
    local c = Unit.getByName(CFG.CARRIER_UNIT)
    local cv = { x = 0, y = 0, z = 0 }
    if c and c:isExist() then
        local okc, vv = pcall(c.getVelocity, c)
        if okc and type(vv) == "table" then cv = vv end
    end
    local dx, dy, dz = v.x - cv.x, v.y - cv.y, v.z - cv.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function InAir(u)
    local ok, a = pcall(u.inAir, u)
    return ok and a == true
end

-- ── radio state of the other modules (read only) ──
local function RadioBusy()
    local cv = TRT.CV
    if cv and (cv.busy or (cv.q and #cv.q > 0)) then return "CV" end
    local cd = TRT.CD
    if cd and (cd.qPlaying or (cd.queue and #cd.queue > 0) or (cd.chat and #cd.chat > 0)
               or cd.awaiting) then return "CD" end
    local ab = TRT.Airboss
    if ab and ((type(ab.RQLSO) == "table" and #ab.RQLSO > 0)
               or (type(ab.RQMarshal) == "table" and #ab.RQMarshal > 0)) then return "AIRBOSS" end
    return nil
end

-- ── clips ──
local function Variants(name)
    local ids = {}
    for id in pairs(CFG.AUDIO) do
        if string.match(id, "^" .. name .. "_%d+$") then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function NextId(name)
    local bag = PB.bags[name]
    if not bag or #bag == 0 then
        bag = Variants(name)
        for i = #bag, 2, -1 do                       -- Fisher-Yates
            local j = math.floor(Rand() * i) + 1
            bag[i], bag[j] = bag[j], bag[i]
        end
        -- no immediate repeat across a refill
        if #bag > 1 and bag[#bag] == PB.lastId[name] then bag[1], bag[#bag] = bag[#bag], bag[1] end
        PB.bags[name] = bag
    end
    return table.remove(bag)
end

local function Play(name, why)
    local id = NextId(name)
    local a = id and CFG.AUDIO[id]
    local u = Hero()
    if not (a and u) then return false end
    local file = CFG.SND_DIR .. id .. ".ogg"
    local okG, gid = pcall(function() return u:getGroup():getID() end)
    local ok, err
    if okG and gid then ok, err = pcall(trigger.action.outSoundForGroup, gid, file)
    else ok, err = pcall(trigger.action.outSoundForCoalition, coalition.side.BLUE, file) end
    if not ok then Log("play error " .. id .. ": " .. tostring(err)); return false end
    local t = now()
    PB.lastId[name], PB.lastPlay[name], PB.lastLine = id, t, t
    PB.busyUntil = t + a.len + CFG.TAIL
    PB.lines = PB.lines + 1
    PB.playing = { id = id, t1 = t + a.len, overlap = false }
    Log(string.format("say %s (%.2f s, %d/%d) \"%s\" [%s]", id, a.len, PB.lines, CFG.MAX_LINES,
        a.text or "?", why or "-"))
    if CFG.SUBTITLE and okG and gid then
        trigger.action.outTextForGroup(gid, "(to himself) " .. (a.text or ""), CFG.SUB_DUR, false)
    end
    return true
end

-- reason this moment may not start now, nil = clear
local function Blocked(name)
    local m = CFG.MOMENTS[name]
    local t = now()
    if not PB.on then return "off" end
    if PB.lines >= CFG.MAX_LINES then return "max lines" end
    if t < PB.busyUntil then return "own line" end
    local r = RadioBusy()
    if r then return "radio " .. r end
    if t - PB.lastLine < (m.gap or CFG.MIN_GAP) then return "gap" end
    if not m.any then
        local cv = TRT.CV
        if cv and cv.phase and CFG.SILENT_CV[cv.phase] then return "CV " .. cv.phase end
        local tl = TRT.TL
        if tl and tl.engaged then return "engaged" end
        local cd = TRT.CD
        if cd and cd.phase and CFG.SILENT_CD[cd.phase] then return "CD " .. cd.phase end
    end
    return nil
end

--- Event -> pending line (probability and cooldown decided here).
local function Fire(name, why)
    local m = CFG.MOMENTS[name]
    if not m then Log("unknown moment " .. tostring(name)); return end
    if not PB.on then return end
    local t = now()
    Mix(t * 1000)
    if PB.lastPlay[name] and t - PB.lastPlay[name] < (m.cd or 0) then
        Log(string.format("%s: cooldown (%s)", name, why or "-")); return
    end
    for _, it in ipairs(PB.pending) do if it.name == name then return end end
    if #Variants(name) == 0 then Log(name .. ": no clips (" .. (why or "-") .. ")"); return end
    local roll = Rand()
    if roll >= m.p then
        Log(string.format("%s: silent by roll %.2f >= %.2f (%s)", name, roll, m.p, why or "-")); return
    end
    PB.pending[#PB.pending + 1] = { name = name, why = why, t0 = t }
end

local function ServePending()
    local t = now()
    local i = 1
    while i <= #PB.pending do
        local it = PB.pending[i]
        local m = CFG.MOMENTS[it.name]
        local due = it.t0 + m.delay
        if t >= due then
            local r = Blocked(it.name)
            if not r then
                table.remove(PB.pending, i)
                Play(it.name, it.why)
                return                                -- one line per tick
            elseif t > due + m.ttl then
                table.remove(PB.pending, i)
                Log(string.format("%s: dropped after %.0f s, last reason: %s", it.name, t - it.t0, r))
            else
                it.reason = r
                i = i + 1
            end
        else
            i = i + 1
        end
    end
end

local function WatchOverlap()
    local p = PB.playing
    if not p then return end
    if now() > p.t1 then PB.playing = nil; return end
    if not p.overlap then
        local r = RadioBusy()
        if r then p.overlap = true; Log("overlap: " .. r .. " started during " .. p.id) end
    end
end

-- ── AIRBOSS grade hook ──
local GRADE = {
    ["_OK_"] = "trap_good", ["OK"] = "trap_good", ["(OK)"] = "trap_fair",
    ["--"] = "trap_poor", ["CUT"] = "trap_poor",
    ["-- (BOLTER)"] = "bolter",
    ["WO"] = "waveoff", ["WOP"] = "waveoff", ["OWO"] = "waveoff", ["WOFD"] = "waveoff",
}

local function OnGrade(pd, grade)
    if type(pd) ~= "table" or type(grade) ~= "table" then return end
    if pd.unitname ~= HERO then return end
    local g = tostring(grade.grade)
    local name = GRADE[g]
    -- a CUT or "--" without a landing is not a trap
    if (name == "trap_good" or name == "trap_fair" or name == "trap_poor") and not pd.landed and not grade.wire then
        name = nil
    end
    Log(string.format("LSO grade %s wire %s landed %s -> %s", g, tostring(grade.wire),
        tostring(pd.landed), tostring(name)))
    if name then Fire(name, "LSO " .. g) end
end

local function HookAirboss()
    if PB.abHooked then return end
    local ab = TRT.Airboss
    if type(ab) ~= "table" then return end
    local prev = ab.OnAfterLSOGrade
    ab.OnAfterLSOGrade = function(self, From, Event, To, pd, grade, ...)
        if prev then
            local ok, err = pcall(prev, self, From, Event, To, pd, grade, ...)
            if not ok then Log("previous OnAfterLSOGrade error: " .. tostring(err)) end
        end
        local ok, err = pcall(OnGrade, pd, grade)
        if not ok then Log("grade hook error: " .. tostring(err)) end
    end
    PB.abHooked = true
    Log("AIRBOSS OnAfterLSOGrade hooked" .. (prev and " (chained to an existing handler)" or ""))
end

-- ── F10 ──
local function MenuItems()
    return { { "Pilot thoughts: " .. (PB.on and "ON" or "OFF"), function()
        PB.on = not PB.on
        if not PB.on then PB.pending = {} end
        Log("toggle -> " .. (PB.on and "ON" or "OFF"))
        if TRT.Menu and TRT.Menu.Msg then TRT.Menu.Msg("Pilot thoughts " .. (PB.on and "ON" or "OFF"), 5) end
    end } }
end

local function RegisterMenu()
    if PB.menu or not (TRT.Menu and TRT.Menu.Register) then return end
    TRT.Menu.Register(CFG.MENU_SECTION, "PB", MenuItems, CFG.MENU_ORDER)
    PB.menu = true
end

-- ── watchers ──
local function WatchCanopy(u, air)
    local C = PB.w.can
    if air then C.cand, C.n = nil, 0; return end
    local v = Arg(u, CFG.CANOPY_ARG)
    if not v then
        if not C.logged then C.logged = true; Log("canopy arg " .. CFG.CANOPY_ARG .. " unreadable") end
        return
    end
    if not C.logged then C.logged = true; Log(string.format("canopy arg %d first read %.3f", CFG.CANOPY_ARG, v)) end
    local s = (v >= CFG.CANOPY_OPEN and "open") or (v <= CFG.CANOPY_SHUT and "shut") or nil
    if not s or s == C.state then C.cand, C.n = nil, 0; return end
    if s ~= C.cand then C.cand, C.n = s, 1 else C.n = C.n + 1 end
    if C.n < CFG.CANOPY_TICKS then return end
    local prev = C.state
    C.state, C.cand, C.n = s, nil, 0
    Log(string.format("canopy %s -> %s (arg %.3f, landed %s)", tostring(prev), s, v, tostring(PB.w.landed)))
    if prev == "open" and s == "shut" and not PB.w.landed then Fire("canopy_close", "canopy arg")
    elseif prev == "shut" and s == "open" and PB.w.landed then Fire("canopy_open", "canopy arg") end
end

local function WatchCatRearm(u, air)
    local W = PB.w
    if not W.catFired then return end
    if air then W.stopSince = nil; return end
    local rs = RelSpeed(u)
    if rs and rs < CFG.REARM_REL_MS then
        W.stopSince = W.stopSince or now()
        if now() - W.stopSince >= CFG.REARM_DECK_S then
            W.catFired, W.stopSince = false, nil
            Log("cat_shot re-armed (stopped on deck)")
        end
    else
        W.stopSince = nil
    end
end

local function CatShot(why)
    local W = PB.w
    if W.catFired then return end
    W.catFired, W.landed = true, false
    Fire("cat_shot", why)
end

local function WatchModules(u, air)
    local W = PB.w
    -- PlaneCaptain milestones
    local pc = TRT.PlaneCaptain
    local ms = pc and pc.milestones
    if ms then
        if ms.START and not W.pcStart then W.pcStart = ms.START; Fire("engines_on", "PlaneCaptain START") end
        if ms.CHECKS and not W.pcChecks then W.pcChecks = ms.CHECKS; Fire("checks_done", "PlaneCaptain CHECKS") end
    end
    -- Flight_Timeline: launch fallback, engaged edge
    local tl = TRT.TL
    if tl then
        if tl.launched and tl.launched ~= W.tlLaunched then
            W.tlLaunched = tl.launched
            if air then CatShot("TL launched") end
        end
        if tl.engaged and not W.engaged then
            W.engaged, W.engT0 = true, now()
        elseif not tl.engaged and W.engaged then
            local dur = now() - (W.engT0 or now())
            W.engaged, W.engT0 = false, nil
            if air and dur >= CFG.THREAT_MIN_S then Fire("threat_over", string.format("engaged %.0f s", dur)) end
        end
    end
    -- Comms_Director: coastline, JTAC targets
    local cd = TRT.CD
    if cd then
        if cd.surf and cd.surf ~= W.surf then
            local prev = W.surf
            W.surf = cd.surf
            if prev and air then
                Fire((cd.surf == "LAND") and "feet_dry" or "feet_wet", "surface " .. prev .. " -> " .. cd.surf)
            end
        end
        if W.dead1 == nil then W.dead1 = cd.deadJ1 and true or false end
        if W.dead2 == nil then W.dead2 = cd.deadJ2 and true or false end
        if cd.deadJ1 and not W.dead1 then W.dead1 = true; Fire("good_hits", "JTAC-1 target dead") end
        if cd.deadJ2 and not W.dead2 then W.dead2 = true; Fire("good_hits", "JTAC-2 target dead") end
    end
    -- Deck_Park result
    local f = trigger.misc.getUserFlag(CFG.DECK_PARK_FLAG)
    if f ~= W.park then
        local prev = W.park
        W.park = f
        if prev ~= nil and (f == 1 or f == 2) then Fire("shutdown", "Deck_Park " .. f) end
    end
end

local function Tick()
    local ok, err = pcall(function()
        RegisterMenu()
        HookAirboss()
        local u = Hero()
        if u then
            local air = InAir(u)
            WatchCanopy(u, air)
            WatchCatRearm(u, air)
            WatchModules(u, air)
        end
        WatchOverlap()
        ServePending()
    end)
    if not ok then Log("tick error: " .. tostring(err)) end
    return now() + CFG.TICK
end

-- ── events ──
local EH = {}
function EH:onEvent(e)
    if not e or not IsHero(e.initiator) then return end
    local W = PB.w
    if e.id == world.event.S_EVENT_TAKEOFF then
        CatShot("S_EVENT_TAKEOFF")
    elseif e.id == world.event.S_EVENT_LAND then
        W.landed = true
        Log("hero landed")
    elseif e.id == world.event.S_EVENT_REFUELING then
        Fire("tanker_in", "S_EVENT_REFUELING")
    end
end
world.addEventHandler(EH)

--- Test hook: speak a moment now-ish (probability and cooldown skipped, all other rules kept).
function PB.Say(name, why)
    if not CFG.MOMENTS[name] then Log("Say: unknown moment " .. tostring(name)); return end
    PB.pending[#PB.pending + 1] = { name = name, why = why or "Say()", t0 = now() - CFG.MOMENTS[name].delay }
end

local nClips, nMom = 0, 0
for _ in pairs(CFG.AUDIO) do nClips = nClips + 1 end
for name in pairs(CFG.MOMENTS) do if #Variants(name) > 0 then nMom = nMom + 1 end end
local seed = Seed()
timer.scheduleFunction(Tick, nil, now() + 2)
Log(string.format("Pilot_Banter v%s loaded: hero %s, %d clips, %d/%d moments with clips, seed %d, %s",
    CFG.VERSION, HERO, nClips, nMom, (function() local n = 0 for _ in pairs(CFG.MOMENTS) do n = n + 1 end return n end)(),
    seed, PB.on and "ON" or "OFF"))
