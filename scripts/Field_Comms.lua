-- Field_Comms.lua | v1.4.1
--[[
  v1.4.1 — PILOT voice libritts-high 851 (make_clips v1.6.0); clips re-rendered, AUDIO
           lengths updated.

  LTCC (Diyarbakir) -> CVN-73 departure radio module
  TRT Syria Dynamic Template  -  transit scenario (land-to-carrier)

  !! PREREQUISITE: Hero unit in ME must be named "Player_01" for
     Menu_Manager (TRT.Menu) integration to function.

  !! TRANSIT MISSIONS: Comms_Director.lua (CAS-1 Strike/Overlord flow) must
     NOT be loaded. It drives a carrier-departure state machine that spams
     "ZIPLIP departure - check in with STRIKE" and hands the pilot to
     OVERLORD. Remove its "Do Script File" action from the transit .miz.

  WHO TALKS WHEN: a check-in is the pilot's own call and waits on F10, because
  he has to retune before anyone can hear him. A handoff is the controller
  calling him, so it fires on its own at the right point on the route.

  DEPARTURE FLOW (F10 actions):
    ATIS [126.600] broadcast -> Clearance [121.800] -> Readback
    -> Ground [121.900] radio check + startup -> Taxi -> Tower [118.100]
    -> Departure [119.100] -> Report level FL320

  ENROUTE:
    F10                    -> Ankara Control [132.300] check-in
    near VESAR (WP12)      -> Ankara FIR boundary -> handoff Nicosia  (auto)
    F10                    -> Nicosia Control [127.825] check-in
    near GENOS (WP15)      -> Nicosia -> handoff Strike -> flag 206   (auto)

  RECOVERY HANDOVER (F10, then automatic):
    Strike [254.000] check-in -> Mother bearing/range, expect CASE N
    <= MARSHAL_NM from Mother -> switch Marshal 261.0 button 16
    From there CV_Comms / AIRBOSS owns the recovery  -  Field_Comms is done.

  READBACKS: every controller instruction is followed by a pilot read-back,
  queued as its own transmission. The queue starts each one only after the
  previous clip finishes, so a read-back can never talk over the controller.

  VOICE: clips are rendered with  python tts/make_clips.py --set fc
  (tts/fc_clips.csv -> src/Sounds/FC/, lengths -> tts/fc_audio_table.lua,
  whose AUDIO = { ... } block is pasted over CFG.AUDIO below). build.py packs
  src/Sounds/ into the .miz. With CFG.AUDIO empty the module runs text-only,
  assuming CFG.NO_AUDIO_DUR of airtime per transmission.

  FLAGS (200-range reserved for Field_Comms):
    203 = airborne / Departure contacted
    206 = strike ready (Comms_Director / mission logic picks this up)

  SID: DEMEB 1J (RWY 34L/R)
    Climb 337 deg/DYB NDB to 4,000 ft -> LEFT 242 deg -> DEMEB D50 DYB
    Airway W/UW716 -> FL320 cruise -> FL090 min sector alt
    DYB NDB: 109.4 MHz

  ROUTE FIXES (mission coords, x=north y=east):
    ERCER  WP11   187810,   15114
    VESAR  WP12   122029, -141584    <- Ankara / Nicosia FIR boundary
    GIRNE  WP13    95475, -261460
    VADUS  WP14    44485, -348817
    GENOS  WP15   -14972, -360362    <- Nicosia / Strike handoff

  LOADING ORDER: after MOOSE, MIST, Menu_Manager (TRT.Menu must exist)
  MENU SECTION: COMMS (F1) via TRT.Menu.Register  -  no own F10 root
]]

_G.TRT = _G.TRT or {}

-- ==============================================================
-- CONFIG
-- ==============================================================
local CFG = {
    HERO_NAME  = "Player_01",          -- must match ME unit name
    GROUP_NAME = "HORNET-467",         -- DCS group name
    CALLSIGN   = "Dodge 11",

    OWNER = "FC",                      -- Menu_Manager provider key
    ORDER = 20,                        -- after CV/CD, before others

    FREQ = {
        ATIS      = "126.600",
        CLEARANCE = "121.800",
        GROUND    = "121.900",
        TOWER     = "118.100",
        DEPARTURE = "119.100",
        ANKARA    = "132.300",
        NICOSIA   = "127.825",
        STRIKE    = "254.000",
    },

    STRIKE_CH = 5,                     -- COMM1 preset channel for Strike

    -- Recovery handover (matches CV_Comms CFG.CHAN.MARSHAL)
    MARSHAL_FREQ = "261.000",
    MARSHAL_BTN  = 16,
    MARSHAL_NM   = 50,                 -- Strike -> Marshal, DME to Mother
    STRIKE_SQUAWK = "5-2-0-0",

    MAGVAR           = 5,              -- Syria, east: magnetic = true - MAGVAR
    INTERNAL_FUEL_LB = 10860,          -- F/A-18C, for "state X.Y"

    ATC_DUR        = 20,               -- s, ATC subtitle, minimum
    PILOT_DUR      = 8,                -- s, pilot subtitle, minimum
    SUB_PAD        = 2,                -- s a subtitle outlives its clip when
                                       -- the clip is longer than the minimum

    -- Radio. Clips live in the .miz at SND_DIR; build.py packs src/Sounds/FC/.
    -- Render them with:  python tts/make_clips.py --set fc
    SND_DIR   = "Sounds/FC/",
    TX_POWER  = 100,
    TX_GAP    = 0.5,                   -- s before a queued transmission starts
    REPLY_GAP = 1.2,                   -- s before a controller answers the pilot
    NO_AUDIO_DUR = 4,                  -- s assumed airtime when a clip is missing
                                       -- (keeps the text-only flow readable)

    FLAG_AIRBORNE   = 203,
    FLAG_STRIKE_RDY = 206,

    CARRIER_UNIT = "CVN-73",

    -- Enroute sector triggers  -  DCS mission-file coords {x=north, y=east}
    -- (These map to unit:getPoint().x and .z respectively in DCS vec3)
    FIR_POS    = { x = 122029, y = -141584 },  -- WP12 VESAR, Ankara/Nicosia FIR
    FIR_R_NM   = 30,
    GENOS_POS  = { x = -14972, y = -360362 },  -- WP15 GENOS, Nicosia/Strike
    GENOS_R_NM = 30,

    POLL_INTERVAL = 10,                -- s, enroute position poll

    -- Safety net: if the player never enters the GENOS radius (route
    -- deviation), hand to Strike once this close to the boat anyway.
    STRIKE_FALLBACK_NM = 120,

    -- Clip lengths. GENERATED  -  paste the AUDIO = { ... } block from
    -- tts/fc_audio_table.lua over this one after every render.
    -- Empty is valid: every transmission then falls back to text only.
    AUDIO = {
        atis                   = { ch = "LTCC_INFO", len = 13.80 },
        p_del_req              = { ch = "LTCC_DEL", len = 5.84 },
        del_clr                = { ch = "LTCC_DEL", len = 14.76 },
        p_del_rb               = { ch = "LTCC_DEL", len = 13.18 },
        del_rb_ok              = { ch = "LTCC_DEL", len = 4.94 },
        p_del_ack              = { ch = "LTCC_DEL", len = 2.86 },
        p_gnd_radiochk         = { ch = "LTCC_GND", len = 2.56 },
        gnd_5x5                = { ch = "LTCC_GND", len = 3.11 },
        p_gnd_startup          = { ch = "LTCC_GND", len = 4.16 },
        gnd_startup_ok         = { ch = "LTCC_GND", len = 4.78 },
        p_gnd_startup_rb       = { ch = "LTCC_GND", len = 4.57 },
        p_gnd_taxi_req         = { ch = "LTCC_GND", len = 3.46 },
        gnd_taxi               = { ch = "LTCC_GND", len = 9.44 },
        p_gnd_taxi_rb          = { ch = "LTCC_GND", len = 7.52 },
        p_twr_ready            = { ch = "LTCC_TWR", len = 3.99 },
        twr_clr_to             = { ch = "LTCC_TWR", len = 7.28 },
        p_twr_rb               = { ch = "LTCC_TWR", len = 5.16 },
        p_dep_checkin          = { ch = "LTCC_DEP", len = 4.90 },
        dep_radar_contact      = { ch = "LTCC_DEP", len = 5.63 },
        p_dep_climb_rb         = { ch = "LTCC_DEP", len = 5.38 },
        p_dep_level            = { ch = "LTCC_DEP", len = 3.23 },
        dep_handoff_ank        = { ch = "LTCC_DEP", len = 6.06 },
        p_dep_ank_ack          = { ch = "LTCC_DEP", len = 3.19 },
        p_ank_checkin          = { ch = "ANKARA", len = 6.64 },
        ank_identified         = { ch = "ANKARA", len = 6.46 },
        p_ank_rb               = { ch = "ANKARA", len = 3.44 },
        ank_fir_handoff        = { ch = "ANKARA", len = 12.02 },
        p_ank_fir_ack          = { ch = "ANKARA", len = 5.96 },
        p_nic_checkin          = { ch = "NICOSIA", len = 4.86 },
        nic_identified         = { ch = "NICOSIA", len = 5.84 },
        p_nic_rb               = { ch = "NICOSIA", len = 4.38 },
        nic_strike_handoff     = { ch = "NICOSIA", len = 7.23 },
        p_nic_strike_ack       = { ch = "NICOSIA", len = 2.80 },
        p_str_checkin          = { ch = "STRIKE", len = 2.42 },
        str_radar_contact      = { ch = "STRIKE", len = 7.56 },
        p_str_rb               = { ch = "STRIKE", len = 4.32 },
        str_switch_marshal     = { ch = "STRIKE", len = 5.18 },
        p_str_marshal_ack      = { ch = "STRIKE", len = 2.56 },
    },
}

-- Radio channels. One source of truth for the frequencies is CFG.FREQ above.
local CHAN = {
    LTCC_INFO = { f = CFG.FREQ.ATIS,      name = "DIYARBAKIR INFORMATION ALPHA" },
    LTCC_DEL  = { f = CFG.FREQ.CLEARANCE, name = "DIYARBAKIR CLEARANCE DELIVERY" },
    LTCC_GND  = { f = CFG.FREQ.GROUND,    name = "DIYARBAKIR GROUND" },
    LTCC_TWR  = { f = CFG.FREQ.TOWER,     name = "DIYARBAKIR TOWER" },
    LTCC_DEP  = { f = CFG.FREQ.DEPARTURE, name = "DIYARBAKIR DEPARTURE" },
    ANKARA    = { f = CFG.FREQ.ANKARA,    name = "ANKARA CONTROL" },
    NICOSIA   = { f = CFG.FREQ.NICOSIA,   name = "NICOSIA CONTROL" },
    STRIKE    = { f = CFG.FREQ.STRIKE,    name = "STRIKE" },
}
for _, c in pairs(CHAN) do
    c.hz  = tonumber(c.f) * 1e6
    c.mod = 0                          -- 0 = AM (both the VHF civil chain and Strike)
end

-- ==============================================================
-- STATE
-- ==============================================================
local S = {
    step          = 0,     -- 0=pre-ATIS, 1..9 see enum below
    ankaraFired   = false, -- Ankara check-in done
    ankaraHandoff = false, -- Ankara released us to Nicosia
    nicosFired    = false, -- Nicosia check-in done
    strikeHanded  = false, -- Nicosia released us to Strike
    marshalHanded = false, -- Strike released us to Marshal
    busy          = false, -- an F10 exchange is mid-queue, see Begin/Done
}
--[[
  step 0  pre-ATIS                    (DECK)
  step 1  ATIS received               (DECK)  -> request clearance
  step 2  clearance given             (DECK)  -> readback
  step 3  readback confirmed          (DECK)  -> Ground: radio check + startup
  step 4  startup approved            (DECK)  -> request taxi
  step 5  taxi given                  (DECK)  -> report ready at holding point
  step 6  tower clearance given       (DECK->AIRBORNE) -> Departure check-in
  step 7  Departure contacted         (AIRBORNE) -> report level FL320
  step 8  enroute                     (AIRBORNE) -> automatic sector chain
  step 9  Strike released by Nicosia  (AIRBORNE) -> F10 Strike check-in
  step 10 Strike contacted, inbound   (AIRBORNE) -> auto Marshal at MARSHAL_NM
  step 11 handed to Marshal           -> CV_Comms / AIRBOSS owns it, done
]]

-- ==============================================================
-- HELPERS
-- ==============================================================
local function Msg(text, dur)
    if TRT.Menu then
        TRT.Menu.Msg(text, dur)
    else
        -- Fallback when Menu_Manager not loaded (should not happen in normal build)
        local g = Group.getByName(CFG.GROUP_NAME)
        if g then
            trigger.action.outTextForGroup(g:getID(), text, dur or 15)
        end
    end
end

local function After(sec, fn)
    timer.scheduleFunction(function()
        local ok, err = pcall(fn)
        if not ok then env.info("Field_Comms | After callback error: "..tostring(err)) end
        return nil
    end, nil, timer.getTime() + sec)
end

local function Hero()
    local u = Unit.getByName(CFG.HERO_NAME)
    if u and u:isExist() then return u end
    return nil
end

-- ==============================================================
-- TRANSMISSION QUEUE
-- ==============================================================
-- Transmissions are serialised: the next one starts only after the previous
-- clip has finished playing. That is what keeps a read-back from talking over
-- the controller  -  a fixed delay cannot, because the clips differ in length
-- (the ATIS runs ~15 s, an acknowledgement ~2 s).
--
-- With no clip for an id the queue still runs, assuming NO_AUDIO_DUR of
-- airtime, so the module degrades to exactly the old text-only behaviour.

local RX = { q = {}, busy = false, n = 0 }

--- Key one clip on a channel. Returns its airtime (s), or 0 if there is none.
local function Air(clip, chKey)
    local a, ch, u = CFG.AUDIO[clip], CHAN[chKey], Hero()
    if not (a and ch and u) then return 0 end
    RX.n = RX.n + 1
    local p = u:getPoint()
    -- Transmitted 30 m above the player, as CV_Comms does: no range / LOS loss.
    trigger.action.radioTransmission(CFG.SND_DIR..clip..".ogg",
        { x = p.x, y = p.y + 30, z = p.z },
        ch.mod, false, ch.hz, CFG.TX_POWER, "FC_"..RX.n)
    return a.len or 0
end

local QNext

--- Queue a transmission.
-- @param who   "PILOT" or a channel key (decides the subtitle label)
-- @param chKey channel the transmission is keyed on
-- @param clip  clip id in CFG.AUDIO / SND_DIR (nil = subtitle only)
-- @param text  subtitle
-- @param fn    optional callback, fires when the transmission ends
-- @param gap   s before this transmission starts
local function Q(who, chKey, clip, text, fn, gap)
    RX.q[#RX.q + 1] = { who = who, ch = chKey, clip = clip, text = text, fn = fn, gap = gap }
    if not RX.busy then QNext() end
end

QNext = function()
    local x = table.remove(RX.q, 1)
    if not x then RX.busy = false; return end
    RX.busy = true

    local function go()
        local ch = CHAN[x.ch]
        -- text may be a function: evaluated at transmit time, not queue time,
        -- so dynamic numbers (Mother bearing, recovery case) are current.
        local text = (type(x.text) == "function") and x.text() or x.text
        -- Hold the subtitle at least until the voice stops: the clearance
        -- read-back runs 12 s against a PILOT_DUR of 8, so a fixed duration
        -- would wipe the text while the pilot is still speaking.
        local a    = CFG.AUDIO[x.clip]
        local base = (x.who == "PILOT") and CFG.PILOT_DUR or CFG.ATC_DUR
        local dur  = a and math.max(base, (a.len or 0) + CFG.SUB_PAD) or base
        if x.who == "PILOT" then
            Msg("[PILOT] "..CFG.CALLSIGN..": "..text, dur)
        else
            Msg("["..(ch and ch.name or x.ch).."  -  "..(ch and ch.f or "").."]\n"..text, dur)
        end
        local len = Air(x.clip, x.ch)
        if len <= 0 then len = CFG.NO_AUDIO_DUR end
        timer.scheduleFunction(function()
            if x.fn then
                local ok, err = pcall(x.fn)
                if not ok then env.info("Field_Comms | callback error: "..tostring(err)) end
            end
            QNext()
            return nil
        end, nil, timer.getTime() + len + 0.05)
    end

    local gap = x.gap or CFG.TX_GAP
    if gap > 0 then
        timer.scheduleFunction(function() go() return nil end, nil, timer.getTime() + gap)
    else
        go()
    end
end

--- Pilot transmission on chKey.
local function Pilot(chKey, clip, text, fn)
    Q("PILOT", chKey, clip, text, fn, 0.3)
end

--- Controller transmission on chKey.
local function Ctl(chKey, clip, text, fn)
    Q(chKey, chKey, clip, text, fn, CFG.REPLY_GAP)
end

local function SetFlag(n)
    trigger.action.setUserFlag(n, true)
end

-- Distance in NM from unit to a mission-file coord {x, y}
-- Mission x = DCS vec3.x (north), mission y = DCS vec3.z (east)
local function Dist2D_NM(u, cfg_pos)
    local p = u:getPoint()
    local dx = p.x - cfg_pos.x
    local dz = p.z - cfg_pos.y
    return math.sqrt(dx * dx + dz * dz) / 1852
end

local function DistToCarrier_NM(u)
    local cv = Unit.getByName(CFG.CARRIER_UNIT)
    if not (cv and cv:isExist()) then return 9999 end
    local p1 = u:getPoint()
    local p2 = cv:getPoint()
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return math.sqrt(dx * dx + dz * dz) / 1852
end

-- Magnetic bearing and range from the player to Mother: "bears 190 for 75"
local function MotherBrgRng(u)
    local cv = Unit.getByName(CFG.CARRIER_UNIT)
    if not (cv and cv:isExist()) then return nil end
    local p1, p2 = u:getPoint(), cv:getPoint()
    local brgT = math.deg(math.atan2(p2.z - p1.z, p2.x - p1.x)) % 360
    local brgM = math.floor((brgT - CFG.MAGVAR) % 360 + 0.5) % 360
    local dx, dz = p2.x - p1.x, p2.z - p1.z
    local nm = math.floor(math.sqrt(dx * dx + dz * dz) / 1852 + 0.5)
    return string.format("%03d", brgM), nm
end

local function Angels(u)
    return math.floor(u:getPoint().y * 3.28084 / 1000 + 0.5)
end

local function State(u)
    local f = u:getFuel() or 0
    return string.format("%.1f", f * CFG.INTERNAL_FUEL_LB / 1000)
end

-- Recovery case from the shared TRT state, if the carrier modules set it
local function RecoveryCase()
    local ok, c = pcall(function()
        if TRT.getCurrentCase then return TRT.getCurrentCase() end
        return nil
    end)
    if ok and type(c) == "number" and c >= 1 and c <= 3 then return c end
    return nil
end

local function MenuRefresh()
    if TRT.Menu then TRT.Menu.Refresh() end
end

-- ==============================================================
-- FORWARD DECLARATIONS
-- ==============================================================
local doATIS, doClearance, doReadback, doGround,
      doTaxi, doTower, doDeparture, doLevel

local StartMonitor, PollPosition, DoAnkara, DoFIRHandoff, DoNicosia, DoStrikeHandoff
local doStrike, DoMarshalHandoff

-- ==============================================================
-- PHASE CALLBACKS  -  F10-triggered, sequential
-- ==============================================================
-- Each exchange is queued, so a read-back always follows the controller's
-- clip instead of racing it. Step changes ride the callback of the last
-- transmission in the exchange.
--
-- An exchange now spans the whole radio dialogue (up to ~40 s with voice),
-- and the step only advances at its end. Begin/Done bracket it so the F10
-- item cannot be clicked again mid-exchange and queue the whole thing twice.

--- Open an exchange: hides the F10 item until Done() runs.
local function Begin()
    S.busy = true
    MenuRefresh()
end

--- Close an exchange, advancing to 'step'. 'extra' runs before the refresh.
local function Done(step, extra)
    return function()
        S.step = step
        S.busy = false
        if extra then extra() end
        MenuRefresh()
    end
end

-- ATIS is a continuous recorded broadcast, not a service you call up: the
-- pilot tunes 126.600 and listens. No request, no read-back  -  the letter is
-- acknowledged on first contact with Clearance instead.
doATIS = function()
    if S.step ~= 0 or S.busy then return end
    Begin()
    Ctl("LTCC_INFO", "atis",
        "Information ALPHA.\n"..
        "Runway 34 left in use. Wind 340 at 8 knots. QNH 1013.\n"..
        "Temperature plus 15, dewpoint plus 04. CAVOK.\n"..
        "Transition altitude 10,000 feet.\n"..
        "Advise ALPHA on initial contact.",
        Done(1))
end

doClearance = function()
    if S.step ~= 1 or S.busy then return end
    Begin()
    Pilot("LTCC_DEL", "p_del_req",
        "Clearance, Dodge 11, Hornet, IFR to CVN-73, DEMEB 1 Juliet. Information ALPHA.")
    -- Read-back is the player's own next action (step 2), not automatic
    Ctl("LTCC_DEL", "del_clr",
        "Dodge 11, cleared to CVN-73 via DEMEB 1 Juliet departure.\n"..
        "Runway 34 left. Climb 4,000 feet on SID.\n"..
        "Expect flight level 3-2-0 ten minutes after departure.\n"..
        "Squawk 3-4-7-2. Departure frequency 119.1.\n"..
        "Information ALPHA. Readback.",
        Done(2))
end

doReadback = function()
    if S.step ~= 2 or S.busy then return end
    Begin()
    Pilot("LTCC_DEL", "p_del_rb",
        "Cleared CVN-73, DEMEB 1 Juliet, runway 34 left,\n"..
        "climb 4,000, expect FL320, squawk 3472,\n"..
        "departure 119.1, information ALPHA. Dodge 11.")
    Ctl("LTCC_DEL", "del_rb_ok",
        "Dodge 11, readback correct.\n"..
        "Contact Ground 121.9 when ready. Good day.")
    Pilot("LTCC_DEL", "p_del_ack", "Ground 121.9. Dodge 11, good day.",
        Done(3))
end

-- Ground: radio check -> five by five -> startup request -> approval -> read-back
doGround = function()
    if S.step ~= 3 or S.busy then return end
    Begin()
    Pilot("LTCC_GND", "p_gnd_radiochk", "Diyarbakir Ground, Dodge 11, radio check.")
    Ctl("LTCC_GND", "gnd_5x5", "Dodge 11, Diyarbakir Ground, read you five by five.")
    Pilot("LTCC_GND", "p_gnd_startup",
        "Read you five by five also. Dodge 11, request startup, information ALPHA.")
    Ctl("LTCC_GND", "gnd_startup_ok",
        "Dodge 11, startup approved. QNH 1013.\n"..
        "Report ready to taxi.")
    Pilot("LTCC_GND", "p_gnd_startup_rb",
        "Startup approved, QNH 1013, will report ready to taxi. Dodge 11.",
        Done(4))
end

doTaxi = function()
    if S.step ~= 4 or S.busy then return end
    Begin()
    Pilot("LTCC_GND", "p_gnd_taxi_req", "Ground, Dodge 11, ready to taxi, runway 34 left.")
    Ctl("LTCC_GND", "gnd_taxi",
        "Dodge 11, taxi runway 34 left via Alpha.\n"..
        "Hold short runway 34 left. QNH 1013.\n"..
        "Contact Tower 118.1 at holding point.")
    Pilot("LTCC_GND", "p_gnd_taxi_rb",
        "Taxi runway 34 left via Alpha, hold short 34 left,\n"..
        "Tower 118.1 at the holding point. Dodge 11, good day.",
        Done(5))
end

doTower = function()
    if S.step ~= 5 or S.busy then return end
    Begin()
    Pilot("LTCC_TWR", "p_twr_ready",
        "Tower, Dodge 11, holding short runway 34 left, ready for departure.")
    Ctl("LTCC_TWR", "twr_clr_to",
        "Dodge 11, wind 340 at 8.\n"..
        "Runway 34 left, cleared for takeoff.\n"..
        "After airborne contact Departure 119.1. Good day.")
    Pilot("LTCC_TWR", "p_twr_rb",
        "Runway 34 left cleared for takeoff, Departure 119.1 airborne. Dodge 11.",
        -- Tower clearance means departure is imminent
        Done(6, function()
            if TRT.Menu then TRT.Menu.SetHint(CFG.OWNER, "DEPARTURE") end
        end))
end

doDeparture = function()
    if S.step ~= 6 or S.busy then return end
    Begin()
    local u = Hero()
    if not (u and u:inAir()) then
        Msg("Not airborne yet  -  wheels must be up first.", 5)
        return
    end
    Pilot("LTCC_DEP", "p_dep_checkin",
        "Departure, Dodge 11, airborne runway 34 left, passing 2,000, DEMEB 1 Juliet.")
    SetFlag(CFG.FLAG_AIRBORNE)
    Ctl("LTCC_DEP", "dep_radar_contact",
        "Dodge 11, radar contact. Climb and maintain flight level 3-2-0.\n"..
        "Continue DEMEB 1 Juliet. Report level.")
    Pilot("LTCC_DEP", "p_dep_climb_rb",
        "Climb and maintain flight level 3-2-0, DEMEB 1 Juliet,\n"..
        "will report level. Dodge 11.",
        Done(7))
end

doLevel = function()
    if S.step ~= 7 or S.busy then return end
    Begin()
    Pilot("LTCC_DEP", "p_dep_level", "Departure, Dodge 11, level flight level 3-2-0.")
    Ctl("LTCC_DEP", "dep_handoff_ank",
        "Dodge 11, maintain flight level 3-2-0. Leaving my frequency.\n"..
        "Contact Ankara Control 132.3. Good day.")
    Pilot("LTCC_DEP", "p_dep_ank_ack", "Ankara Control 132.3. Dodge 11, good day.",
        Done(8, function()
            -- Departure phase done  -  drop hint, back to MISSION
            if TRT.Menu then TRT.Menu.SetHint(CFG.OWNER, nil) end
            StartMonitor()
            -- The Ankara check-in is now an F10 item, not a timer: the pilot
            -- has to retune before he can be heard, and a 20 s countdown had
            -- him checking in on a frequency he was still dialling.
        end))
end

-- ==============================================================
-- ENROUTE CHAIN  (automatic: timed check-ins, position-based handoffs)
-- ==============================================================

StartMonitor = function()
    timer.scheduleFunction(function(_, t)
        if S.step >= 11 then return nil end  -- stop once Marshal has us
        local ok, err = pcall(PollPosition)
        if not ok then env.info("Field_Comms | poll error: "..tostring(err)) end
        return t + CFG.POLL_INTERVAL
    end, nil, timer.getTime() + CFG.POLL_INTERVAL)
end

PollPosition = function()
    local u = Hero()
    if not (u and u:isExist() and u:inAir()) then return end

    -- Inbound leg: Strike -> Marshal at MARSHAL_NM from Mother
    if S.step == 10 then
        if not S.marshalHanded and DistToCarrier_NM(u) <= CFG.MARSHAL_NM then
            S.marshalHanded = true
            DoMarshalHandoff()
        end
        return
    end

    -- Stand down if the pilot went to Marshal without us. He can check in with
    -- AIRBOSS straight off its own menu, and then this module sat at step 9 for
    -- the rest of the flight with a stale "check in with Strike" item on F10.
    if S.step == 9 and DistToCarrier_NM(u) <= CFG.MARSHAL_NM then
        S.step = 11
        if TRT.Menu then TRT.Menu.SetHint(CFG.OWNER, nil) end
        MenuRefresh()
        env.info("Field_Comms | inside "..CFG.MARSHAL_NM.." NM without a Strike "..
                 "check-in  -  standing down, the carrier module has the pilot.")
        return
    end

    if S.step ~= 8 then return end

    -- Ankara -> Nicosia at the FIR boundary (VESAR / WP12)
    if S.ankaraFired and not S.ankaraHandoff then
        if Dist2D_NM(u, CFG.FIR_POS) <= CFG.FIR_R_NM then
            S.ankaraHandoff = true
            DoFIRHandoff()
        end
        return
    end

    -- Nicosia -> Strike approaching GENOS (WP15), or close enough to Mother
    if S.nicosFired and not S.strikeHanded then
        if Dist2D_NM(u, CFG.GENOS_POS) <= CFG.GENOS_R_NM
           or DistToCarrier_NM(u) <= CFG.STRIKE_FALLBACK_NM then
            S.strikeHanded = true
            DoStrikeHandoff()
        end
    end
end

DoAnkara = function()
    if S.ankaraFired or S.step ~= 8 or S.busy then return end
    S.ankaraFired = true
    Begin()
    Pilot("ANKARA", "p_ank_checkin",
        "Ankara Control, Dodge 11, flight level 3-2-0, DEMEB 1 Juliet, en route CVN-73.")
    Ctl("ANKARA", "ank_identified",
        "Dodge 11, Ankara Control, identified.\n"..
        "Maintain flight level 3-2-0. Route direct VESAR.")
    Pilot("ANKARA", "p_ank_rb", "Maintain flight level 3-2-0, direct VESAR. Dodge 11.",
        Done(8))
end

DoFIRHandoff = function()
    Ctl("ANKARA", "ank_fir_handoff",
        "Dodge 11, approaching Ankara FIR boundary at VESAR.\n"..
        "Radar service terminated. Squawk 2000 at the boundary.\n"..
        "Contact Nicosia Control 127.825. Good day.")
    -- Nicosia check-in is the pilot's own next call, once he has retuned (F10)
    Pilot("ANKARA", "p_ank_fir_ack",
        "Squawk 2000, Nicosia Control 127.825. Dodge 11, good day.",
        function() MenuRefresh() end)
end

DoNicosia = function()
    if S.nicosFired or S.step ~= 8 or S.busy then return end
    S.nicosFired = true
    Begin()
    Pilot("NICOSIA", "p_nic_checkin",
        "Nicosia Control, Dodge 11, flight level 3-2-0, VESAR, estimating GIRNE.")
    Ctl("NICOSIA", "nic_identified",
        "Dodge 11, Nicosia Control, identified.\n"..
        "Maintain flight level 3-2-0. Cleared GIRNE, VADUS, GENOS.")
    Pilot("NICOSIA", "p_nic_rb",
        "Maintain flight level 3-2-0, cleared GIRNE VADUS GENOS. Dodge 11.",
        Done(8))
end

DoStrikeHandoff = function()
    Ctl("NICOSIA", "nic_strike_handoff",
        "Dodge 11, approaching GENOS, leaving controlled airspace.\n"..
        "Radar service terminated. Contact Strike, 254 decimal 0. Good day.")
    Pilot("NICOSIA", "p_nic_strike_ack", "Strike 254.0. Dodge 11, good day.",
        function()
            Msg(
                "-- STRIKE CHECK-IN ---------------------\n"..
                "Strike: "..CFG.FREQ.STRIKE.." MHz\n"..
                "COMM1 CH"..CFG.STRIKE_CH.."\n"..
                "Check in via F10 > COMMS when ready.",
                20)
            SetFlag(CFG.FLAG_STRIKE_RDY)
            S.step = 9
            MenuRefresh()
            env.info("Field_Comms | flag "..CFG.FLAG_STRIKE_RDY.." set  -  Strike ready.")
        end)
end

-- ==============================================================
-- RECOVERY HANDOVER  -  Strike -> Marshal, then CV_Comms owns it
-- ==============================================================
-- Mother bearing / range, angels and state are dynamic, so they live in the
-- subtitle only; the clip carries the static frame (same convention as the
-- CAS1 / CV sets).

doStrike = function()
    if S.step ~= 9 or S.busy then return end
    local u = Hero()
    if not u then return end
    Begin()

    local brg, nm = MotherBrgRng(u)
    local txt
    if brg then
        txt = string.format("Strike, Dodge 11, Mother %s for %d, angels %d, state %s.",
            brg, nm, Angels(u), State(u))
    else
        txt = string.format("Strike, Dodge 11, inbound Mother, angels %d, state %s.",
            Angels(u), State(u))
    end
    Pilot("STRIKE", "p_str_checkin", txt)

    Ctl("STRIKE", "str_radar_contact", function()
        local hu = Hero()
        local bb, bn
        if hu then bb, bn = MotherBrgRng(hu) end
        local mother = bb and string.format("Mother bears %s for %d. ", bb, bn) or ""
        local case   = RecoveryCase()
        local caseTxt = case and string.format("Expect CASE %s recovery.\n",
            (case == 1 and "one") or (case == 2 and "two") or "three") or ""
        return "Dodge 11, Strike, radar contact. Squawk "..CFG.STRIKE_SQUAWK..".\n"..
               mother..caseTxt..
               "Switch Marshal, button "..CFG.MARSHAL_BTN..", "..CFG.MARSHAL_FREQ..
               ", at "..CFG.MARSHAL_NM.." miles."
    end)
    Pilot("STRIKE", "p_str_rb",
        "Squawk "..CFG.STRIKE_SQUAWK..", Marshal button "..CFG.MARSHAL_BTN..
        " at "..CFG.MARSHAL_NM.." miles. Dodge 11.",
        Done(10))
end

DoMarshalHandoff = function()
    Ctl("STRIKE", "str_switch_marshal",
        "Dodge 11, "..CFG.MARSHAL_NM.." miles. Switch Marshal,\n"..
        "button "..CFG.MARSHAL_BTN..", "..CFG.MARSHAL_FREQ..". Good day.")
    Pilot("STRIKE", "p_str_marshal_ack",
        "Marshal button "..CFG.MARSHAL_BTN..". Dodge 11, good day.",
        function()
            Msg(
                "-- MARSHAL ----------------------------\n"..
                "Marshal: "..CFG.MARSHAL_FREQ.."  button "..CFG.MARSHAL_BTN.."\n"..
                "Recovery comms from here: F10 > COMMS (carrier module).\n"..
                "LTCC departure module complete.",
                20)
            S.step = 11
            MenuRefresh()
            env.info("Field_Comms | handed to Marshal  -  module complete.")
        end)
end

-- ==============================================================
-- MENU PROVIDER  -  TRT.Menu.Register
-- ==============================================================

-- Main item list: one active item per step (empty while enroute)
local function MenuFn(phase)
    -- Mid-exchange the item is withdrawn, so a second click cannot queue the
    -- whole dialogue again. Done() puts the next one up.
    if S.busy then return {} end
    if     S.step == 0 then return { { "LTCC INFO: Monitor ATIS ["..CFG.FREQ.ATIS.."]",                   doATIS      } }
    elseif S.step == 1 then return { { "LTCC DEL: Request IFR clearance ["..CFG.FREQ.CLEARANCE.."]", doClearance } }
    elseif S.step == 2 then return { { "LTCC DEL: Readback clearance",                                doReadback  } }
    elseif S.step == 3 then return { { "LTCC GND: Radio check + startup ["..CFG.FREQ.GROUND.."]",     doGround    } }
    elseif S.step == 4 then return { { "LTCC GND: Request taxi",                                      doTaxi      } }
    elseif S.step == 5 then return { { "LTCC TWR: Report ready for departure ["..CFG.FREQ.TOWER.."]", doTower     } }
    elseif S.step == 6 then
        -- Step 6 unlocks only once airborne
        local u = Hero()
        if u and u:inAir() then
            return { { "LTCC DEP: Airborne  -  contact Departure ["..CFG.FREQ.DEPARTURE.."]", doDeparture } }
        end
        return {}   -- tower clearance given but still on ground
    elseif S.step == 7 then return { { "LTCC DEP: Report level FL320",                                doLevel     } }
    elseif S.step == 8 then
        -- Sector check-ins are the pilot's own calls: he must retune first, so
        -- they wait on F10. The handoffs between them are controller-initiated
        -- and stay automatic.
        if not S.ankaraFired then
            return { { "ANKARA: Check in ["..CFG.FREQ.ANKARA.."]",  DoAnkara  } }
        elseif S.ankaraHandoff and not S.nicosFired then
            return { { "NICOSIA: Check in ["..CFG.FREQ.NICOSIA.."]", DoNicosia } }
        end
        return {}                       -- enroute, waiting on the next boundary
    elseif S.step == 9 then return { { "STRIKE: Check in inbound ["..CFG.FREQ.STRIKE.."]",            doStrike    } }
    else                    return {}   -- inbound / done, calls are automatic
    end
end

-- "Show: next call" text
local NEXT = {
    [0] = "Tune "..CFG.FREQ.ATIS.." and listen to the ATIS broadcast",
    [1] = "Request IFR clearance on "..CFG.FREQ.CLEARANCE,
    [2] = "Readback clearance",
    [3] = "Contact Ground "..CFG.FREQ.GROUND.."  -  radio check, then startup",
    [4] = "Request taxi",
    [5] = "Report ready at holding point  -  Tower "..CFG.FREQ.TOWER,
    [6] = "Get airborne, then contact Departure "..CFG.FREQ.DEPARTURE,
    [7] = "Report level FL320 to Departure",
    [8]  = "Enroute  -  sector calls are automatic (Ankara, VESAR, Nicosia, GENOS)",
    [9]  = "Check in with Strike "..CFG.FREQ.STRIKE.."  (COMM1 CH"..CFG.STRIKE_CH..")",
    [10] = "Inbound  -  Strike hands you to Marshal at "..CFG.MARSHAL_NM.." miles",
    [11] = "Marshal "..CFG.MARSHAL_FREQ.." button "..CFG.MARSHAL_BTN..
           "  -  recovery comms take over",
}

local function NextFn(phase)
    if S.busy then return "Transmitting  -  stand by" end
    -- Enroute: name the next event instead of a generic line
    if S.step == 8 then
        if not S.ankaraFired   then return "Tune "..CFG.FREQ.ANKARA..", then check in with Ankara (F10)" end
        if not S.ankaraHandoff then return "Ankara "..CFG.FREQ.ANKARA.."  -  FIR boundary at VESAR (WP12)" end
        if not S.nicosFired    then return "Tune "..CFG.FREQ.NICOSIA..", then check in with Nicosia (F10)" end
        if not S.strikeHanded  then return "Nicosia "..CFG.FREQ.NICOSIA.."  -  Strike handoff at GENOS (WP15)" end
    end
    if S.step == 10 then
        local u = Hero()
        if u then
            local d = DistToCarrier_NM(u)
            if d < 9999 then
                return string.format("Inbound Mother %d NM  -  Marshal %s button %d at %d NM",
                    math.floor(d + 0.5), CFG.MARSHAL_FREQ, CFG.MARSHAL_BTN, CFG.MARSHAL_NM)
            end
        end
    end
    return NEXT[S.step] or nil
end

-- Comm card  -  LTCC departure + enroute frequencies
local function CardFn()
    return {
        buttons = {
            -- Only Strike has a confirmed COMM1 preset (CH5 = 254.000)
            { n = CFG.STRIKE_CH, f = CFG.FREQ.STRIKE, name = "Strike" },
        },
        lines = {
            "-- LTCC DEPARTURE FREQS -----------",
            "ATIS         "..CFG.FREQ.ATIS.."   manual",
            "Clearance    "..CFG.FREQ.CLEARANCE.."   manual",
            "Ground       "..CFG.FREQ.GROUND.."   manual",
            "Tower        "..CFG.FREQ.TOWER.."   manual",
            "Departure    "..CFG.FREQ.DEPARTURE.."   manual",
            "Ankara ACC   "..CFG.FREQ.ANKARA.."   manual",
            "Nicosia ACC  "..CFG.FREQ.NICOSIA.."  manual  (from VESAR)",
            "Strike       "..CFG.FREQ.STRIKE.."   COMM1 CH"..CFG.STRIKE_CH.."  (from GENOS)",
            "Marshal      "..CFG.MARSHAL_FREQ.."   button "..CFG.MARSHAL_BTN..
                "  (from "..CFG.MARSHAL_NM.." NM)",
            "SID: DEMEB 1J  RWY 34L/R  DYB NDB 109.4",
        },
    }
end

-- ==============================================================
-- EVENT HANDLER  -  TAKEOFF / LAND for DEPARTURE hint
-- ==============================================================
local FC_EH = {}
function FC_EH:onEvent(e)
    if not (e and e.initiator) then return end
    local ok, name = pcall(function() return e.initiator:getName() end)
    if not ok or name ~= CFG.HERO_NAME then return end

    if e.id == world.event.S_EVENT_TAKEOFF then
        -- Hero now airborne; DEPARTURE hint active while step 6-7
        if TRT.Menu and S.step >= 5 and S.step <= 7 then
            TRT.Menu.SetHint(CFG.OWNER, "DEPARTURE")
        end
    elseif e.id == world.event.S_EVENT_LAND then
        if TRT.Menu then TRT.Menu.SetHint(CFG.OWNER, nil) end
    end
end
world.addEventHandler(FC_EH)

-- ==============================================================
-- INIT
-- ==============================================================
local function Init()
    if not TRT.Menu then
        env.info("Field_Comms v1.4.1 | ERROR: TRT.Menu not found. "..
                 "Load Menu_Manager before Field_Comms. No F10 menus will appear.")
        return
    end
    TRT.Menu.Register("COMMS", CFG.OWNER, MenuFn, CFG.ORDER)
    TRT.Menu.RegisterNext(CFG.OWNER, NextFn)
    TRT.Menu.RegisterCard(CFG.OWNER, CardFn, CFG.ORDER)
    -- Start with no hint: on DECK the hero drives phase = "DECK" regardless.
    -- DEPARTURE hint is set in doTower (tower clearance given) and event handler.
    env.info("Field_Comms v1.4.1 | loaded  -  LTCC departure module (group: "..CFG.GROUP_NAME..")")
end

-- Small delay so Menu_Manager is ready
timer.scheduleFunction(function()
    Init()
    return nil
end, nil, timer.getTime() + 0.5)
