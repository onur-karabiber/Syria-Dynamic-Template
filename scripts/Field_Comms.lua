-- Field_Comms.lua | v1.0.0
--[[
  LTCC (Diyarbakir) → CVN-73 departure radio module
  TRT Syria Dynamic Template  -  transit scenario (land-to-carrier)

  !! PREREQUISITE: Hero unit in ME must be named "Player_01" for
     Menu_Manager (TRT.Menu) integration to function.
     Current unit name is "HORNET-4-1"  -  rename it in ME:
       Mission Editor → select HORNET-467 group → unit properties
       → name: "Player_01" → save → extract.py → build.py

  DEPARTURE FLOW (sequential F10 actions):
    ATIS [126.600] → Clearance [121.800] → Readback
    → Startup [121.900] → Taxi → Tower [118.100]
    → Departure [119.100] → Report level FL320

  AMBIENT (auto, timer-based position polling, no player input):
    Near ERCER    → Ankara Control [132.300] initial contact
    ~180 s later  → Ankara FIR boundary handoff
    Near GIRNE    → Nicosia Control [127.825] → handoff to Strike
    Strike handed → flag 206 set (Comms_Director monitors this)

  FLAGS (200-range reserved for Field_Comms):
    203 = airborne / Departure contacted
    206 = strike ready (Comms_Director / mission logic picks this up)

  SID: DEMEB 1J (RWY 34L/R)
    Climb 337°/DYB NDB to 4,000 ft → LEFT 242° → DEMEB D50 DYB
    Airway W/UW716 → FL320 cruise → FL090 min sector alt
    DYB NDB: 109.4 MHz

  LOADING ORDER: after MOOSE, MIST, Menu_Manager (TRT.Menu must exist)
  MENU SECTION: COMMS (F1) via TRT.Menu.Register  -  no own F10 root
]]

_G.TRT = _G.TRT or {}

-- ══════════════════════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════════════════════
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

    ATC_DUR   = 20,                    -- s, ATC message display
    PILOT_DUR = 8,                     -- s, pilot read-back display

    FLAG_AIRBORNE   = 203,
    FLAG_STRIKE_RDY = 206,

    CARRIER_UNIT = "CVN-73",

    -- Ambient position triggers  -  DCS mission-file coords {x=north, y=east}
    -- (These map to unit:getPoint().x and .z respectively in DCS vec3)
    ANKARA_POS  = { x = 187810, y = 15114  },  -- WP11 ERCER
    ANKARA_R_NM = 20,
    NICOSIA_POS = { x = 95475,  y = -261460 }, -- WP13 GIRNE
    NICOSIA_R_NM = 25,

    ANKARA_HANDOFF_DELAY = 180,        -- s after Ankara contact → FIR boundary
    POLL_INTERVAL        = 10,         -- s, ambient position poll
}

-- ══════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════
local S = {
    step          = 0,    -- 0=pre-ATIS, 1..9 see enum below
    ankaraFired   = false,
    ankaraHandoff = false,
    nicosFired    = false,
}
--[[
  step 0  pre-ATIS                    (DECK)
  step 1  ATIS received               (DECK)  → request clearance
  step 2  clearance given             (DECK)  → readback
  step 3  readback confirmed          (DECK)  → contact Ground / startup
  step 4  startup approved            (DECK)  → request taxi
  step 5  taxi given                  (DECK)  → report ready at holding point
  step 6  tower clearance given       (DECK→AIRBORNE) → Departure check-in
  step 7  Departure contacted         (AIRBORNE) → report level FL320
  step 8  Departure handoff to Ankara (AIRBORNE) → ambient only
  step 9  Strike flag set             → done
]]

-- ══════════════════════════════════════════════════════════════
-- HELPERS
-- ══════════════════════════════════════════════════════════════
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

local function MsgATC(header, body)
    Msg("["..header.."]\n"..body, CFG.ATC_DUR)
end

local function MsgPilot(text)
    Msg("[PILOT] "..CFG.CALLSIGN..": "..text, CFG.PILOT_DUR)
end

local function After(sec, fn)
    timer.scheduleFunction(function()
        local ok, err = pcall(fn)
        if not ok then env.info("Field_Comms | After callback error: "..tostring(err)) end
        return nil
    end, nil, timer.getTime() + sec)
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

local function MenuRefresh()
    if TRT.Menu then TRT.Menu.Refresh() end
end

-- ══════════════════════════════════════════════════════════════
-- FORWARD DECLARATIONS
-- (needed because some phase fns reference ambient fns defined later)
-- ══════════════════════════════════════════════════════════════
local doATIS, doClearance, doReadback, doGround,
      doTaxi, doTower, doDeparture, doLevel

local StartMonitor, PollPosition, DoAnkara, DoNicosia

-- ══════════════════════════════════════════════════════════════
-- PHASE CALLBACKS  -  F10-triggered, sequential
-- ══════════════════════════════════════════════════════════════

doATIS = function()
    if S.step ~= 0 then return end
    MsgPilot("Diyarbakir Information, Dodge 11, request ATIS.")
    After(2.5, function()
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
            "Contact Ground 121.9 when ready. Good day.")
        S.step = 3
        MenuRefresh()
    end)
end

doGround = function()
    if S.step ~= 3 then return end
    MsgPilot("Ground, Dodge 11, requesting startup. Information ALPHA.")
    After(3, function()
        MsgATC("DIYARBAKIR GROUND  -  "..CFG.FREQ.GROUND,
            "Dodge 11, startup approved. QNH 1013.\n"..
            "Report ready to taxi.")
        S.step = 4
        MenuRefresh()
    end)
end

doTaxi = function()
    if S.step ~= 4 then return end
    MsgPilot("Ready to taxi, runway 34 left, Dodge 11.")
    After(3, function()
        MsgATC("DIYARBAKIR GROUND  -  "..CFG.FREQ.GROUND,
            "Dodge 11, taxi runway 34 left via Alpha.\n"..
            "Hold short runway 34 left. QNH 1013.\n"..
            "Contact Tower 118.1 at holding point.")
        S.step = 5
        MenuRefresh()
    end)
end

doTower = function()
    if S.step ~= 5 then return end
    MsgPilot("Tower, Dodge 11, holding short runway 34 left, ready.")
    After(3, function()
        MsgATC("DIYARBAKIR TOWER  -  "..CFG.FREQ.TOWER,
            "Dodge 11, wind 340 at 8.\n"..
            "Runway 34 left, cleared for takeoff.\n"..
            "After airborne contact Departure 119.1. Good day.")
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
            "Continue DEMEB 1 Juliet. Report level.")
        S.step = 7
        MenuRefresh()
    end)
end

doLevel = function()
    if S.step ~= 7 then return end
    MsgPilot("Level flight level 3-2-0, Dodge 11.")
    After(3, function()
        MsgATC("DIYARBAKIR DEPARTURE  -  "..CFG.FREQ.DEPARTURE,
            "Dodge 11, maintain flight level 3-2-0. Leaving my frequency.\n"..
            "Contact Ankara Control 132.3. Good day.")
        -- Remind pilot of the upcoming freq chain (stays up long)
        After(4, function()
            Msg(
                "-- ENROUTE FREQ CHAIN ------------------\n"..
                "Ankara Control   "..CFG.FREQ.ANKARA.."  (manual)\n"..
                "Nicosia Control  "..CFG.FREQ.NICOSIA.."  (manual)\n"..
                "Strike           "..CFG.FREQ.STRIKE.."   COMM1 CH"..CFG.STRIKE_CH.."\n"..
                "Sector changes will be announced automatically.",
                25)
        end)
        S.step = 8
        -- Departure phase done  -  drop hint, back to MISSION
        if TRT.Menu then TRT.Menu.SetHint(CFG.OWNER, nil) end
        MenuRefresh()
        StartMonitor()
    end)
end

-- ══════════════════════════════════════════════════════════════
-- AMBIENT MONITOR  (timer-based position polling, step 8 only)
-- ══════════════════════════════════════════════════════════════

StartMonitor = function()
    timer.scheduleFunction(function(_, t)
        if S.step >= 9 then return nil end   -- stop when done
        local ok, err = pcall(PollPosition)
        if not ok then env.info("Field_Comms | poll error: "..tostring(err)) end
        return t + CFG.POLL_INTERVAL
    end, nil, timer.getTime() + CFG.POLL_INTERVAL)
end

PollPosition = function()
    if S.step ~= 8 then return end
    local u = Hero()
    if not (u and u:isExist() and u:inAir()) then return end

    -- Ankara trigger  -  once, when within ANKARA_R_NM of ERCER
    if not S.ankaraFired then
        if Dist2D_NM(u, CFG.ANKARA_POS) <= CFG.ANKARA_R_NM then
            S.ankaraFired = true
            DoAnkara()
        end
        return   -- no Nicosia check until Ankara FIR boundary announced
    end

    -- Nicosia trigger  -  once, after Ankara FIR handoff, within NICOSIA_R_NM of GIRNE
    if S.ankaraHandoff and not S.nicosFired then
        if Dist2D_NM(u, CFG.NICOSIA_POS) <= CFG.NICOSIA_R_NM then
            S.nicosFired = true
            DoNicosia()
        end
    end
end

DoAnkara = function()
    After(2, function()
        MsgPilot("Ankara Control, Dodge 11, flight level 3-2-0, ERCER.")
        After(3, function()
            MsgATC("ANKARA CONTROL  -  "..CFG.FREQ.ANKARA,
                "Dodge 11, Ankara Control, identified.\n"..
                "Maintain flight level 3-2-0.")
            -- FIR boundary handoff after delay (position-agnostic safety net)
            After(CFG.ANKARA_HANDOFF_DELAY, function()
                if not S.ankaraHandoff then
                    S.ankaraHandoff = true
                    MsgATC("ANKARA CONTROL  -  "..CFG.FREQ.ANKARA,
                        "Dodge 11, leaving Turkish FIR. Radar service terminated.\n"..
                        "Contact Nicosia Control 127.825. Good day.")
                end
            end)
        end)
    end)
end

DoNicosia = function()
    After(2, function()
        MsgPilot("Nicosia Control, Dodge 11, flight level 3-2-0.")
        After(3, function()
            MsgATC("NICOSIA CONTROL  -  "..CFG.FREQ.NICOSIA,
                "Dodge 11, Nicosia Control, identified.\n"..
                "Maintain flight level 3-2-0.")
            After(35, function()
                MsgATC("NICOSIA CONTROL  -  "..CFG.FREQ.NICOSIA,
                    "Dodge 11, leaving my airspace.\n"..
                    "Contact Strike, 254 decimal 0. Good day.")
                After(8, function()
                    Msg(
                        "-- STRIKE CHECK-IN ---------------------\n"..
                        "Strike: "..CFG.FREQ.STRIKE.." MHz\n"..
                        "COMM1 CH"..CFG.STRIKE_CH.."\n"..
                        "Check in when ready.",
                        20)
                    SetFlag(CFG.FLAG_STRIKE_RDY)
                    S.step = 9
                    env.info("Field_Comms | flag "..CFG.FLAG_STRIKE_RDY.." set  -  Strike ready.")
                end)
            end)
        end)
    end)
end

-- ══════════════════════════════════════════════════════════════
-- MENU PROVIDER  -  TRT.Menu.Register
-- ══════════════════════════════════════════════════════════════

-- Main item list: one active item per step (or empty in ambient phase)
local function MenuFn(phase)
    if     S.step == 0 then return { { "LTCC INFO: Get ATIS ["..CFG.FREQ.ATIS.."]",                   doATIS      } }
    elseif S.step == 1 then return { { "LTCC DEL: Request IFR clearance ["..CFG.FREQ.CLEARANCE.."]", doClearance } }
    elseif S.step == 2 then return { { "LTCC DEL: Readback clearance",                                doReadback  } }
    elseif S.step == 3 then return { { "LTCC GND: Request startup ["..CFG.FREQ.GROUND.."]",           doGround    } }
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
    else                    return {}   -- ambient or done, no F10 items
    end
end

-- "Show: next call" text
local NEXT = {
    [0] = "Get ATIS on "..CFG.FREQ.ATIS,
    [1] = "Request IFR clearance on "..CFG.FREQ.CLEARANCE,
    [2] = "Readback clearance",
    [3] = "Contact Ground "..CFG.FREQ.GROUND.." for startup",
    [4] = "Request taxi",
    [5] = "Report ready at holding point  -  Tower "..CFG.FREQ.TOWER,
    [6] = "Get airborne, then contact Departure "..CFG.FREQ.DEPARTURE,
    [7] = "Report level FL320 to Departure",
    [8] = "Monitor "..CFG.FREQ.ANKARA.."  -  Ankara will trigger automatically near ERCER",
    [9] = "Field Comms complete. Strike: "..CFG.FREQ.STRIKE.." (COMM1 CH5)",
}

local function NextFn(phase)
    return NEXT[S.step] or nil
end

-- Comm card  -  LTCC departure frequencies
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
            "Nicosia ACC  "..CFG.FREQ.NICOSIA.."  manual",
            "Strike       "..CFG.FREQ.STRIKE.."   COMM1 CH"..CFG.STRIKE_CH,
            "SID: DEMEB 1J  RWY 34L/R  DYB NDB 109.4",
        },
    }
end

-- ══════════════════════════════════════════════════════════════
-- EVENT HANDLER  -  TAKEOFF / LAND for DEPARTURE hint
-- ══════════════════════════════════════════════════════════════
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

-- ══════════════════════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════════════════════
local function Init()
    if not TRT.Menu then
        env.info("Field_Comms v1.0.0 | ERROR: TRT.Menu not found. "..
                 "Load Menu_Manager before Field_Comms. No F10 menus will appear.")
        return
    end
    TRT.Menu.Register("COMMS", CFG.OWNER, MenuFn, CFG.ORDER)
    TRT.Menu.RegisterNext(CFG.OWNER, NextFn)
    TRT.Menu.RegisterCard(CFG.OWNER, CardFn, CFG.ORDER)
    -- Start with no hint: on DECK the hero drives phase = "DECK" regardless.
    -- DEPARTURE hint is set in doTower (tower clearance given) and event handler.
    env.info("Field_Comms v1.0.0 | loaded  -  LTCC departure module (group: "..CFG.GROUP_NAME..")")
end

-- Small delay so Menu_Manager is ready
timer.scheduleFunction(function()
    Init()
    return nil
end, nil, timer.getTime() + 0.5)
