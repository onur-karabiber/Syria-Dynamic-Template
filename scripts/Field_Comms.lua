-- Field_Comms.lua | v1.2.0
--[[
  LTCC (Diyarbakir) -> CVN-73 departure radio module
  TRT Syria Dynamic Template  -  transit scenario (land-to-carrier)

  !! PREREQUISITE: Hero unit in ME must be named "Player_01" for
     Menu_Manager (TRT.Menu) integration to function.

  !! TRANSIT MISSIONS: Comms_Director.lua (CAS-1 Strike/Overlord flow) must
     NOT be loaded. It drives a carrier-departure state machine that spams
     "ZIPLIP departure - check in with STRIKE" and hands the pilot to
     OVERLORD. Remove its "Do Script File" action from the transit .miz.

  DEPARTURE FLOW (sequential F10 actions):
    ATIS [126.600] -> Clearance [121.800] -> Readback
    -> Ground [121.900] radio check + startup -> Taxi -> Tower [118.100]
    -> Departure [119.100] -> Report level FL320

  ENROUTE (automatic after FL320 report, no player input):
    +ANKARA_DELAY s        -> Ankara Control [132.300] check-in
    near VESAR (WP12)      -> Ankara FIR boundary -> handoff Nicosia
    +NICOSIA_DELAY s       -> Nicosia Control [127.825] check-in
    near GENOS (WP15)      -> Nicosia -> handoff Strike -> flag 206

  RECOVERY HANDOVER (F10, then automatic):
    Strike [254.000] check-in -> Mother bearing/range, expect CASE N
    <= MARSHAL_NM from Mother -> switch Marshal 261.0 button 16
    From there CV_Comms / AIRBOSS owns the recovery  -  Field_Comms is done.

  READBACKS: every ATC transmission that carries an instruction is followed
  by an automatic pilot read-back (MsgATC's 3rd argument), READBACK_DELAY s
  after the controller.

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

    ATC_DUR        = 20,               -- s, ATC message display
    PILOT_DUR      = 8,                -- s, pilot read-back display
    READBACK_DELAY = 4,                -- s, controller -> pilot read-back gap

    FLAG_AIRBORNE   = 203,
    FLAG_STRIKE_RDY = 206,

    CARRIER_UNIT = "CVN-73",

    -- Enroute sector triggers  -  DCS mission-file coords {x=north, y=east}
    -- (These map to unit:getPoint().x and .z respectively in DCS vec3)
    FIR_POS    = { x = 122029, y = -141584 },  -- WP12 VESAR, Ankara/Nicosia FIR
    FIR_R_NM   = 30,
    GENOS_POS  = { x = -14972, y = -360362 },  -- WP15 GENOS, Nicosia/Strike
    GENOS_R_NM = 30,

    ANKARA_DELAY  = 20,                -- s after Departure handoff -> Ankara call
    NICOSIA_DELAY = 20,                -- s after FIR handoff -> Nicosia call
    POLL_INTERVAL = 10,                -- s, enroute position poll

    -- Safety net: if the player never enters the GENOS radius (route
    -- deviation), hand to Strike once this close to the boat anyway.
    STRIKE_FALLBACK_NM = 120,
}

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

local function MsgPilot(text)
    Msg("[PILOT] "..CFG.CALLSIGN..": "..text, CFG.PILOT_DUR)
end

-- Controller transmission. If 'readback' is given, the pilot answers it
-- automatically READBACK_DELAY seconds later.
local function MsgATC(header, body, readback)
    Msg("["..header.."]\n"..body, CFG.ATC_DUR)
    if readback then
        After(CFG.READBACK_DELAY, function() MsgPilot(readback) end)
    end
end

local function SetFlag(n)
    trigger.action.setUserFlag(n, true)
end

local function Hero()
    local u = Unit.getByName(CFG.HERO_NAME)
    if u and u:isExist() then return u end
    return nil
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

doATIS = function()
    if S.step ~= 0 then return end
    MsgPilot("Diyarbakir Information, Dodge 11, request ATIS.")
    After(2.5, function()
        -- Information broadcast: acknowledged on next contact, no read-back
        MsgATC("DIYARBAKIR INFORMATION ALPHA  -  "..CFG.FREQ.ATIS,
            "Information ALPHA.\n"..
            "Runway 34 left in use. Wind 340 at 8 knots. QNH 1013.\n"..
            "Temperature plus 15, dewpoint plus 04. CAVOK.\n"..
            "Transition altitude 10,000 feet.\n"..
            "Advise ALPHA on initial contact.")
        S.step = 1
        MenuRefresh()
    end)
end

doClearance = function()
    if S.step ~= 1 then return end
    MsgPilot("Clearance, Dodge 11, F/A-18, IFR to CVN-73, DEMEB 1 Juliet. Information ALPHA.")
    After(3, function()
        -- Read-back is the player's own next action (step 2), not automatic
        MsgATC("DIYARBAKIR CLEARANCE DELIVERY  -  "..CFG.FREQ.CLEARANCE,
            "Dodge 11, cleared to CVN-73 via DEMEB 1 Juliet departure.\n"..
            "Runway 34 left. Climb 4,000 feet on SID.\n"..
            "Expect flight level 3-2-0 ten minutes after departure.\n"..
            "Squawk 3-4-7-2. Departure frequency 119.1.\n"..
            "Information ALPHA. Readback.")
        S.step = 2
        MenuRefresh()
    end)
end

doReadback = function()
    if S.step ~= 2 then return end
    MsgPilot(
        "Cleared CVN-73, DEMEB 1 Juliet, runway 34 left,\n"..
        "climb 4,000, expect FL320, squawk 3472,\n"..
        "departure 119.1, information ALPHA. Dodge 11.")
    After(2, function()
        MsgATC("DIYARBAKIR CLEARANCE DELIVERY  -  "..CFG.FREQ.CLEARANCE,
            "Dodge 11, readback correct.\n"..
            "Contact Ground 121.9 when ready. Good day.",
            "Ground 121.9. Dodge 11, good day.")
        S.step = 3
        MenuRefresh()
    end)
end

-- Ground: radio check -> five by five -> startup request -> approval -> read-back
doGround = function()
    if S.step ~= 3 then return end
    MsgPilot("Diyarbakir Ground, Dodge 11, radio check.")
    After(3, function()
        MsgATC("DIYARBAKIR GROUND  -  "..CFG.FREQ.GROUND,
            "Dodge 11, Diyarbakir Ground, read you five by five.")
        After(4, function()
            MsgPilot("Read you five by five also. Dodge 11, request startup, information ALPHA.")
            After(3, function()
                MsgATC("DIYARBAKIR GROUND  -  "..CFG.FREQ.GROUND,
                    "Dodge 11, startup approved. QNH 1013.\n"..
                    "Report ready to taxi.",
                    "Startup approved, QNH 1013, will report ready to taxi. Dodge 11.")
                S.step = 4
                MenuRefresh()
            end)
        end)
    end)
end

doTaxi = function()
    if S.step ~= 4 then return end
    MsgPilot("Ground, Dodge 11, ready to taxi, runway 34 left.")
    After(3, function()
        MsgATC("DIYARBAKIR GROUND  -  "..CFG.FREQ.GROUND,
            "Dodge 11, taxi runway 34 left via Alpha.\n"..
            "Hold short runway 34 left. QNH 1013.\n"..
            "Contact Tower 118.1 at holding point.",
            "Taxi runway 34 left via Alpha, hold short 34 left,\n"..
            "Tower 118.1 at the holding point. Dodge 11.")
        S.step = 5
        MenuRefresh()
    end)
end

doTower = function()
    if S.step ~= 5 then return end
    MsgPilot("Tower, Dodge 11, holding short runway 34 left, ready for departure.")
    After(3, function()
        MsgATC("DIYARBAKIR TOWER  -  "..CFG.FREQ.TOWER,
            "Dodge 11, wind 340 at 8.\n"..
            "Runway 34 left, cleared for takeoff.\n"..
            "After airborne contact Departure 119.1. Good day.",
            "Runway 34 left cleared for takeoff, Departure 119.1 airborne. Dodge 11.")
        S.step = 6
        -- Hint DEPARTURE now  -  Tower clearance means departure is imminent
        if TRT.Menu then TRT.Menu.SetHint(CFG.OWNER, "DEPARTURE") end
        MenuRefresh()
    end)
end

doDeparture = function()
    if S.step ~= 6 then return end
    local u = Hero()
    if not (u and u:inAir()) then
        Msg("Not airborne yet  -  wheels must be up first.", 5)
        return
    end
    MsgPilot("Departure, Dodge 11, airborne runway 34 left, passing 2,000, DEMEB 1 Juliet.")
    SetFlag(CFG.FLAG_AIRBORNE)
    After(3, function()
        MsgATC("DIYARBAKIR DEPARTURE  -  "..CFG.FREQ.DEPARTURE,
            "Dodge 11, radar contact. Climb and maintain flight level 3-2-0.\n"..
            "Continue DEMEB 1 Juliet. Report level.",
            "Climb and maintain flight level 3-2-0, DEMEB 1 Juliet,\n"..
            "will report level. Dodge 11.")
        S.step = 7
        MenuRefresh()
    end)
end

doLevel = function()
    if S.step ~= 7 then return end
    MsgPilot("Departure, Dodge 11, level flight level 3-2-0.")
    After(3, function()
        MsgATC("DIYARBAKIR DEPARTURE  -  "..CFG.FREQ.DEPARTURE,
            "Dodge 11, maintain flight level 3-2-0. Leaving my frequency.\n"..
            "Contact Ankara Control 132.3. Good day.",
            "Ankara Control 132.3. Dodge 11, good day.")
        S.step = 8
        -- Departure phase done  -  drop hint, back to MISSION
        if TRT.Menu then TRT.Menu.SetHint(CFG.OWNER, nil) end
        MenuRefresh()
        StartMonitor()
        -- Pilot switches and checks in right away, as on the real frequency
        After(CFG.ANKARA_DELAY, DoAnkara)
    end)
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
    if S.ankaraFired or S.step ~= 8 then return end
    S.ankaraFired = true
    MsgPilot("Ankara Control, Dodge 11, flight level 3-2-0, DEMEB 1 Juliet, en route CVN-73.")
    After(3, function()
        MsgATC("ANKARA CONTROL  -  "..CFG.FREQ.ANKARA,
            "Dodge 11, Ankara Control, identified.\n"..
            "Maintain flight level 3-2-0. Route direct VESAR.",
            "Maintain flight level 3-2-0, direct VESAR. Dodge 11.")
    end)
end

DoFIRHandoff = function()
    MsgATC("ANKARA CONTROL  -  "..CFG.FREQ.ANKARA,
        "Dodge 11, approaching Ankara FIR boundary at VESAR.\n"..
        "Radar service terminated. Squawk 2000 at the boundary.\n"..
        "Contact Nicosia Control 127.825. Good day.",
        "Squawk 2000, Nicosia Control 127.825. Dodge 11, good day.")
    After(CFG.NICOSIA_DELAY, DoNicosia)
end

DoNicosia = function()
    if S.nicosFired or S.step ~= 8 then return end
    S.nicosFired = true
    MsgPilot("Nicosia Control, Dodge 11, flight level 3-2-0, VESAR, estimating GIRNE.")
    After(3, function()
        MsgATC("NICOSIA CONTROL  -  "..CFG.FREQ.NICOSIA,
            "Dodge 11, Nicosia Control, identified.\n"..
            "Maintain flight level 3-2-0. Cleared GIRNE, VADUS, GENOS.",
            "Maintain flight level 3-2-0, cleared GIRNE VADUS GENOS. Dodge 11.")
    end)
end

DoStrikeHandoff = function()
    MsgATC("NICOSIA CONTROL  -  "..CFG.FREQ.NICOSIA,
        "Dodge 11, approaching GENOS, leaving controlled airspace.\n"..
        "Radar service terminated. Contact Strike, 254 decimal 0. Good day.",
        "Strike 254.0. Dodge 11, good day.")
    After(10, function()
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

doStrike = function()
    if S.step ~= 9 then return end
    local u = Hero()
    if not u then return end

    local brg, nm = MotherBrgRng(u)
    if brg then
        MsgPilot(string.format("Strike, Dodge 11, Mother %s for %d, angels %d, state %s.",
            brg, nm, Angels(u), State(u)))
    else
        MsgPilot(string.format("Strike, Dodge 11, inbound Mother, angels %d, state %s.",
            Angels(u), State(u)))
    end

    S.step = 10
    MenuRefresh()

    After(3, function()
        local hu = Hero()
        local bb, bn
        if hu then bb, bn = MotherBrgRng(hu) end
        local mother = bb and string.format("Mother bears %s for %d. ", bb, bn) or ""
        local case   = RecoveryCase()
        local caseTxt = case and string.format("Expect CASE %s recovery.\n",
            (case == 1 and "one") or (case == 2 and "two") or "three") or ""

        MsgATC("STRIKE  -  "..CFG.FREQ.STRIKE,
            "Dodge 11, Strike, radar contact. Squawk "..CFG.STRIKE_SQUAWK..".\n"..
            mother..caseTxt..
            "Switch Marshal, button "..CFG.MARSHAL_BTN..", "..CFG.MARSHAL_FREQ..
            ", at "..CFG.MARSHAL_NM.." miles.",
            "Squawk "..CFG.STRIKE_SQUAWK..", Marshal button "..CFG.MARSHAL_BTN..
            " at "..CFG.MARSHAL_NM.." miles. Dodge 11.")
    end)
end

DoMarshalHandoff = function()
    MsgATC("STRIKE  -  "..CFG.FREQ.STRIKE,
        "Dodge 11, "..CFG.MARSHAL_NM.." miles. Switch Marshal,\n"..
        "button "..CFG.MARSHAL_BTN..", "..CFG.MARSHAL_FREQ..". Good day.",
        "Marshal button "..CFG.MARSHAL_BTN..". Dodge 11, good day.")
    After(10, function()
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
    if     S.step == 0 then return { { "LTCC INFO: Get ATIS ["..CFG.FREQ.ATIS.."]",                   doATIS      } }
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
    elseif S.step == 9 then return { { "STRIKE: Check in inbound ["..CFG.FREQ.STRIKE.."]",            doStrike    } }
    else                    return {}   -- enroute / inbound / done, calls are automatic
    end
end

-- "Show: next call" text
local NEXT = {
    [0] = "Get ATIS on "..CFG.FREQ.ATIS,
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
    -- Enroute: name the next event instead of a generic line
    if S.step == 8 then
        if not S.ankaraFired   then return "Switching Ankara Control "..CFG.FREQ.ANKARA   end
        if not S.ankaraHandoff then return "Ankara "..CFG.FREQ.ANKARA.."  -  FIR boundary at VESAR (WP12)" end
        if not S.nicosFired    then return "Switching Nicosia Control "..CFG.FREQ.NICOSIA end
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
        env.info("Field_Comms v1.2.0 | ERROR: TRT.Menu not found. "..
                 "Load Menu_Manager before Field_Comms. No F10 menus will appear.")
        return
    end
    TRT.Menu.Register("COMMS", CFG.OWNER, MenuFn, CFG.ORDER)
    TRT.Menu.RegisterNext(CFG.OWNER, NextFn)
    TRT.Menu.RegisterCard(CFG.OWNER, CardFn, CFG.ORDER)
    -- Start with no hint: on DECK the hero drives phase = "DECK" regardless.
    -- DEPARTURE hint is set in doTower (tower clearance given) and event handler.
    env.info("Field_Comms v1.2.0 | loaded  -  LTCC departure module (group: "..CFG.GROUP_NAME..")")
end

-- Small delay so Menu_Manager is ready
timer.scheduleFunction(function()
    Init()
    return nil
end, nil, timer.getTime() + 0.5)
