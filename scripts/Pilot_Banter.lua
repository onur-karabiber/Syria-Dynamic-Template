-- Pilot_Banter | v2.0.0
--[[
  v2.0.0 (Onur, 2026-10-31): much more self-talk, and spoken checks that read the real state.
    * Composite lines: a line is a list of clips (header, value, comment) chained at runtime,
      e.g. "Fuel check..." + "nine point eight" + "Joker's..." + "five point nine" + "Good margin."
      Values are whole-phrase clips (tts/pb_values.csv, v_<kind>_<n>). If a radio call starts
      mid-line, the rest of the line stops ("cut"); the clip already playing finishes. A check
      (.prio) resumes RESUME_QUIET_S s after the radio ends (once, within RESUME_TTL s).
    * Cruise scheduler (the long legs, outbound and inbound, and Marshal holding): every
      LEVELS[level].cruise s (random in the range) one item, only after RADIO_QUIET_S s without
      radio: fuel check (state vs joker / bingo / tank, burn rate), nav / timing (CP Tiger
      distance, ETE, early / late against the ATO; tanker; Mother; push time), altitude, system
      scan (engine rpm and master caution when the cockpit can be read), musings (scenery by sun
      elevation and sea / land, daily life) and noises. On station (JTAC phases, between attacks):
      fuel, VUL time left, noises.
    * Checks with real values: fence in (before CP Tiger), attack checks (after a correct JTAC
      readback), fence out (leaving the area), JOKER / BINGO / TANK reached (Flight_Timeline),
      tanker checks (join, closure too high, astern, fuel while in contact, disconnect, post-
      tanker), holding, commencing, Case I/II approach check, landing check (wheels, flaps, hook,
      harness) on gear-down, divert.
    * Cockpit read (export environment, net.dostring_in): master arm, A/G master mode light,
      LTD/R, radar knob, dispenser, master caution, engine rpm, IFEI bingo. Probed at load;
      after 3 failed reads the checks use mission data only (fuel, position, external model:
      wheels / flaps / hook / probe). Cockpit items are spoken only for arguments in CK_MAP
      (DCS-BIOS FA-18C argument numbers); every check logs the raw values ("[PB] cockpit").
      Master arm 1 = ARM is assumed and re-calibrated on the first A/G release.
    * JTAC_Controller aware: its radio (through the Comms_Director queue) is visible, so the
      v1.0.1 JTAC-phase silence is replaced by: silent while a 9-line / readback runs and from IP
      inbound until OFF. Field_Arrival radio is visible too.
    * F10 INFO > "Pilot thoughts: <level>" > Off / Quiet / Normal / Chatty (LEVELS).
    * TRT.PB.busyUntil is read by Comms_Director >= v1.7.8: its unsolicited calls wait for the end
      of a line (they may wait CHAT_TTL s anyway).
    Rule extended: a check READS the aircraft state, and may say a state is wrong ("hook's still
    up"); it never says what to do about it. Reactions stay reactions.
  v1.1.1: weapon_away is dropped while Comms_Director v1.5.6 transmits the release call.
  v1.1.0: more self-talk (CAS-1 test 2026-10-28: 9 lines in 2.5 h); cruise, weapon_away,
          missile_defeated, cap_splash, tanker_done.
  v1.0.1: silent while working a JTAC (native DCS JTAC voice not detectable).
  v1.0.0: canopy, engines, checks, cat shot, feet dry / wet, tanker, good hits, threat over, trap
          by LSO grade, bolter, waveoff, canopy open, shutdown.

  The pilot talking to himself (CAS (L) only; not part of the template build). Played with
  outSoundForGroup (no radio, no frequency). Variants are picked from a shuffle bag (no repeat
  until every variant of a group has played); event moments fire with a probability.

  Rules:
    * Radio first: nothing starts while CV_Comms, Comms_Director (also JTAC_Controller voice),
      Field_Arrival or AIRBOSS has a transmission playing or queued, while Comms_Director holds a
      deferred call or waits for a controller reply. A line that cannot start within its TTL is
      dropped. Cruise items and long checks also need RADIO_QUIET_S s of silence first.
    * Silent at high workload: CV_Comms phases in SILENT_CV (moments with .cvok may speak in
      some of them, e.g. the landing check in ZIPLIP), while Flight_Timeline reports ENGAGED,
      during a JTAC 9-line or attack, in close formation with the tanker (except AAR moments).
    * Volume: LEVELS[level].max lines per mission, MIN_GAP s between lines (.gap per moment),
      per-moment cooldown .cd.

  Verified: outSoundForGroup "Sounds/PB/x.ogg" plays (CAS-1 flights 2026-10-28).
  Not verified in DCS [V]: net.dostring_in("export") from the mission environment, the CK_MAP
  value meanings (except the DCS-BIOS step tables for radar and dispenser), external-model gear
  arguments 0 / 3 / 5 and flaps 9 on the Hornet, IFEI bingo text format, UTC_OFFSET of the map.

  Clips: tts/pb_clips.csv + tts/pb_values.csv -> python tts/make_clips.py --set pb [--missing]
         -> tools/pilot_banter/out/Sounds/PB/*.ogg and the AUDIO block below (rewritten in place
         between the markers; do not edit it by hand). Group = id without the trailing _<n>.
  Install: python tools/pilot_banter/install_pilot_banter.py "<...>/Close Air Support (L).miz"
  Load order: free; every other module is read lazily on the tick.
  API: TRT.PB.Say(moment, why, ctx), TRT.PB.level, TRT.PB.busyUntil, TRT.PB.version
]]

_G.TRT = _G.TRT or {}
local TRT = _G.TRT
if TRT.PB then
    env.info("[PB] already loaded, second copy ignored")
    return
end

local CFG = {
    VERSION      = "2.0.0",
    LEVEL        = "NORMAL",       -- start level: OFF | QUIET | NORMAL | CHATTY
    LEVELS = {
        QUIET  = { cruise = { 120, 240 }, muse = 0.30, max = 80 },
        NORMAL = { cruise = {  55, 120 }, muse = 0.35, max = 200 },
        CHATTY = { cruise = {  30,  70 }, muse = 0.45, max = 360 },
    },
    LEVEL_ORDER  = { "OFF", "QUIET", "NORMAL", "CHATTY" },
    SND_DIR      = "Sounds/PB/",
    CARRIER_UNIT = "CVN",
    TANKER_UNITS = { "TANKER-1-1" },
    TICK         = 0.5,            -- s
    MIN_GAP      = 20,             -- s between two lines (default; .gap per moment)
    TAIL         = 0.3,            -- s after a line before anything else of ours may start
    SEG_GAP      = 0.05,           -- s between two clips of a line (clips carry ~0.35 s of silence)
    RADIO_QUIET_S = 12,            -- s of radio silence before a cruise item / .quiet moment
    JC_QUIET_S   = 30,             -- s after JTAC_Controller work before an on-station cruise item
    RESUME_QUIET_S = 2,            -- a check cut by a radio call resumes this long after the radio ends
    RESUME_TTL   = 40,             -- ... or is dropped
    SUBTITLE     = false,          -- true: "(to himself) ..." text
    SUB_DUR      = 5,
    NOISE_SYNTH  = true,           -- synthesized cough / throat / sniff / breath (snd_*) in the noise mix
    NOISE_P      = 0.12,           -- share of cruise items that are noises
    UTC_OFFSET   = 3,              -- h, mission local time - UTC (sun elevation) [V]
    CANOPY_ARG   = 38,
    CANOPY_OPEN  = 0.80,
    CANOPY_SHUT  = 0.02,
    CANOPY_TICKS = 2,
    GEAR_ARGS    = { 0, 3, 5 },    -- external model: nose, right, left gear (1 = down) [V]
    FLAPS_ARG    = 9,              -- external model: flaps (> FLAPS_DOWN = down) [V]
    FLAPS_DOWN   = 0.3,
    HOOK_ARG     = 25,             -- > 0.6 down (PlaneCaptain)
    PROBE_ARG    = 22,             -- >= 0.9 out (AAR_Monitor)
    REARM_REL_MS = 3,
    REARM_DECK_S = 30,
    THREAT_MIN_S = 20,
    DECK_PARK_FLAG = 1910,
    FENCE_IN_NM  = 35,             -- fence in when CP Tiger is this close (outbound, AR1 closed)
    APPROACH_NM  = 12,             -- Case I/II approach check
    LANDING_NM   = 25,             -- landing check only this close to the carrier (or field arrival)
    AAR_CLOSURE_KT = 15,           -- "too much closure" inside AAR_CLOSURE_NM
    AAR_CLOSURE_NM = 0.5,
    AAR_TAKING_S = 50,             -- s between fuel reads in contact
    BURN_WIN_S   = 300,            -- s window for the burn rate
    MENU_SECTION = "INFO",
    MENU_ORDER   = 90,
    FIELDS = {                     -- Flight_Timeline v1.1.x coordinates
        LTAG = { lat = 37.00205,  lon = 35.426083, grp = "field_ltag" },
        LCRA = { lat = 34.590367, lon = 32.987783, grp = "field_lcra" },
    },

    -- CV_Comms phases with no banter (workload / controller reply pending)
    SILENT_CV = {
        CHECKIN_SENT = true, READBACK = true,
        NEEDLES = true, FINAL = true, BALLWAIT = true, BALL = true, GROOVE = true,
        ZIPLIP = true, B_UPWIND = true, B_DOWNWIND = true, B_ABEAM = true,
    },
    -- Comms_Director phases with no banter while the NATIVE JTAC talks (no JTAC_Controller)
    SILENT_CD = { JTAC1 = true, JTAC2 = true },
    -- JTAC_Controller phases of a 9-line in progress
    JC_SILENT = { CHECKIN = true, SITREP = true, GAMEPLAN = true, NINE = true, READBACK = true },
    -- cruise contexts (Comms_Director phases)
    CRUISE_CD  = { STRIKE_OUT = true, ENROUTE = true, J1_OFF = true, J2_OFF = true, REFUEL = true,
                   TKR_DONE = true, RTB = true, OVL_OUT = true, STRIKE_IN = true, INBOUND = true,
                   DIVERT = true },
    STATION_CD = { JTAC1 = true, JTAC2 = true },
    OUTBOUND_CD = { STRIKE_OUT = true, ENROUTE = true },
    INBOUND_CD = { TKR_DONE = true, RTB = true, OVL_OUT = true, STRIKE_IN = true, INBOUND = true },
    FENCE_OUT_CD = { RTB = true, OVL_OUT = true, STRIKE_IN = true, INBOUND = true, DIVERT = true, RECOVERY = true },
    AAR_CLOSE  = { JOIN = true, ECHELON_L = true, ECHELON_R = true, ASTERN = true, CONTACT = true },
    PATTERN_OK = { ZIPLIP = true, B_UPWIND = true, B_DOWNWIND = true, B_ABEAM = true },

    -- cruise items: w = weight, cd = s before the same item again, ctx = where it may play
    ITEMS = {
        fuel = { w = 3, cd = 210, ctx = { transit = true, station = true, hold = true } },
        nav  = { w = 3, cd = 180, ctx = { transit = true, hold = true } },
        alt  = { w = 1, cd = 480, ctx = { transit = true } },
        sys  = { w = 2, cd = 420, ctx = { transit = true, hold = true } },
        vul  = { w = 3, cd = 300, ctx = { station = true } },
    },

    -- p = probability · delay = s after the event · ttl = s it may wait after the delay
    -- cd = s before the same moment again · gap = min s since our previous line
    -- any = ignore every workload rule (never the radio) · jtac = allowed during JTAC work
    -- cvok = CV phases where it may speak anyway · aar = allowed in close tanker formation
    -- quiet = needs RADIO_QUIET_S s of radio silence · prio = not limited by LEVELS.max
    MOMENTS = {
        canopy_close = { p = 0.85, delay = 1.0, ttl = 12, cd = 300, gap = 15 },
        engines_on   = { p = 0.60, delay = 2.0, ttl = 15, cd = 600, gap = 15 },
        checks_done  = { p = 0.70, delay = 2.0, ttl = 20, cd = 600, gap = 15 },
        cat_shot     = { p = 0.90, delay = 3.5, ttl = 12, cd = 120 },
        feet_dry     = { p = 0.85, delay = 1.0, ttl = 20, cd = 600 },
        feet_wet     = { p = 0.85, delay = 1.0, ttl = 20, cd = 600 },
        tanker_in    = { p = 0.85, delay = 1.5, ttl = 8,  cd = 300, aar = true },
        good_hits    = { p = 0.90, delay = 10.0, ttl = 30, cd = 120 },
        weapon_away      = { p = 0.70, delay = 1.5, ttl = 6,  cd = 90, jtac = true },
        missile_defeated = { p = 0.90, delay = 2.0, ttl = 20, cd = 60, any = true },
        cap_splash       = { p = 0.80, delay = 2.0, ttl = 25, cd = 300 },
        tanker_done      = { p = 0.80, delay = 3.0, ttl = 25, cd = 600 },
        threat_over  = { p = 0.90, delay = 2.0, ttl = 20, cd = 300 },
        trap_good    = { p = 0.90, delay = 1.0, ttl = 25, cd = 60, gap = 10, any = true },
        trap_fair    = { p = 0.90, delay = 1.0, ttl = 25, cd = 60, gap = 10, any = true },
        trap_poor    = { p = 0.90, delay = 1.0, ttl = 25, cd = 60, gap = 10, any = true },
        bolter       = { p = 0.80, delay = 0.5, ttl = 10, cd = 60, gap = 10, any = true },
        waveoff      = { p = 0.80, delay = 0.5, ttl = 10, cd = 60, gap = 10, any = true },
        canopy_open  = { p = 0.60, delay = 1.5, ttl = 12, cd = 600, gap = 12, any = true },
        shutdown     = { p = 0.85, delay = 17,  ttl = 20, cd = 600, gap = 12, any = true },
        -- v2.0.0
        cruise_item    = { p = 1.00, delay = 0,   ttl = 20, cd = 0,   quiet = true },
        fence_in       = { p = 1.00, delay = 2,   ttl = 120, cd = 0,  quiet = true, prio = true },
        fence_out      = { p = 1.00, delay = 15,  ttl = 120, cd = 0,  quiet = true, prio = true },
        attack_check   = { p = 1.00, delay = 3,   ttl = 40, cd = 60,  quiet = true, prio = true, jtac = true, gap = 8 },
        joker_call     = { p = 1.00, delay = 1,   ttl = 60, cd = 0,   prio = true, gap = 5, jtac = true },
        bingo_call     = { p = 1.00, delay = 1,   ttl = 60, cd = 0,   prio = true, gap = 5, jtac = true },
        tank_call      = { p = 1.00, delay = 1,   ttl = 60, cd = 0,   prio = true, gap = 5 },
        aar_check      = { p = 1.00, delay = 1,   ttl = 25, cd = 300, prio = true, aar = true, gap = 8 },
        aar_closure    = { p = 1.00, delay = 0,   ttl = 3,  cd = 120, prio = true, aar = true, gap = 4 },
        aar_steady     = { p = 0.60, delay = 1,   ttl = 6,  cd = 120, aar = true, gap = 6 },
        aar_taking     = { p = 1.00, delay = 0,   ttl = 10, cd = 30,  aar = true, gap = 15 },
        aar_disc       = { p = 0.80, delay = 2,   ttl = 8,  cd = 20,  aar = true, gap = 6 },
        aar_post       = { p = 1.00, delay = 4,   ttl = 40, cd = 120, prio = true, gap = 8 },
        hold_check     = { p = 1.00, delay = 6,   ttl = 90, cd = 300, quiet = true, prio = true },
        commence_check = { p = 1.00, delay = 3,   ttl = 30, cd = 300, prio = true },
        approach_check = { p = 1.00, delay = 1,   ttl = 25, cd = 300, prio = true, cvok = { ZIPLIP = true } },
        landing_check  = { p = 1.00, delay = 3,   ttl = 15, cd = 60,  prio = true, gap = 6,
                           cvok = { ZIPLIP = true, B_UPWIND = true, B_DOWNWIND = true, B_ABEAM = true } },
        divert_check   = { p = 1.00, delay = 8,   ttl = 60, cd = 600, quiet = true, prio = true },
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
        cruise_1           = { len = 1.26, text = "Quiet out here." },
        cruise_2           = { len = 1.26, text = "Long way from the boat." },
        cruise_3           = { len = 1.51, text = "Nice view, at least." },
        cruise_4           = { len = 1.88, text = "Just me and the hum of the engines." },
        cruise_5           = { len = 1.33, text = "Alright... settle in." },
        cruise_6           = { len = 2.65, text = "Not a cloud worth worrying about." },
        weapon_away_1      = { len = 1.21, text = "Off it goes." },
        weapon_away_2      = { len = 1.79, text = "Weapon's gone. Come on..." },
        weapon_away_3      = { len = 1.34, text = "Okay, it's away." },
        weapon_away_4      = { len = 1.07, text = "And... released." },
        missile_defeated_1 = { len = 2.60, text = "Whoa... that was close." },
        missile_defeated_2 = { len = 2.17, text = "Missed me. Okay. Breathe." },
        missile_defeated_3 = { len = 1.03, text = "Not today." },
        missile_defeated_4 = { len = 1.55, text = "Heart's still going... good." },
        cap_splash_1       = { len = 1.45, text = "Good shooting, guys." },
        cap_splash_2       = { len = 1.65, text = "One less to worry about." },
        cap_splash_3       = { len = 1.77, text = "Nice. Scratch one." },
        cap_splash_4       = { len = 1.47, text = "Glad they're on our side." },
        tanker_done_1      = { len = 1.74, text = "Topped off. That's better." },
        tanker_done_2      = { len = 1.84, text = "Full tanks. Good feeling." },
        tanker_done_3      = { len = 1.93, text = "Okay, gas is good." },
        tanker_done_4      = { len = 1.53, text = "Thanks, Texaco." },
        fuel_h_1           = { len = 1.10, text = "Fuel check..." },
        fuel_h_2           = { len = 2.11, text = "Let's see, gas..." },
        fuel_h_3           = { len = 1.34, text = "Okay, fuel..." },
        fuel_h_4           = { len = 1.09, text = "Gas check..." },
        fuel_h_5           = { len = 1.51, text = "Where are we on gas..." },
        fuel_h_6           = { len = 0.95, text = "Fuel..." },
        bingo_is_1         = { len = 1.06, text = "Bingo's..." },
        bingo_is_2         = { len = 1.19, text = "Bingo is..." },
        joker_is_1         = { len = 1.11, text = "Joker's..." },
        joker_is_2         = { len = 1.13, text = "Joker is..." },
        tank_is_1          = { len = 1.20, text = "Tank state's..." },
        tank_is_2          = { len = 1.02, text = "Tank is..." },
        burn_h_1           = { len = 1.16, text = "Burning about..." },
        burn_h_2           = { len = 1.12, text = "Flow's about..." },
        cmt_fuel_plenty_1  = { len = 1.52, text = "Plenty of gas." },
        cmt_fuel_plenty_2  = { len = 1.44, text = "Lots of margin." },
        cmt_fuel_plenty_3  = { len = 1.31, text = "We're fat on gas." },
        cmt_fuel_plenty_4  = { len = 1.27, text = "No worries there." },
        cmt_fuel_ok_1      = { len = 1.24, text = "Right on the plan." },
        cmt_fuel_ok_2      = { len = 1.10, text = "That's fine." },
        cmt_fuel_ok_3      = { len = 1.07, text = "Looking good." },
        cmt_fuel_ok_4      = { len = 1.07, text = "Good margin." },
        cmt_fuel_near_joker_1 = { len = 1.48, text = "Getting close to joker." },
        cmt_fuel_near_joker_2 = { len = 1.53, text = "Not much over joker." },
        cmt_fuel_near_joker_3 = { len = 1.62, text = "Hmm. Close to joker." },
        cmt_fuel_past_joker_1 = { len = 1.46, text = "Past joker already." },
        cmt_fuel_past_joker_2 = { len = 1.59, text = "Under joker. Hmm." },
        cmt_fuel_past_joker_3 = { len = 1.40, text = "That's below joker." },
        cmt_fuel_near_bingo_1 = { len = 1.58, text = "Not much over bingo." },
        cmt_fuel_near_bingo_2 = { len = 1.47, text = "Getting close to bingo." },
        cmt_fuel_below_bingo_1 = { len = 1.25, text = "That's below bingo." },
        cmt_fuel_below_bingo_2 = { len = 1.41, text = "Under bingo... not good." },
        cmt_fuel_near_tank_1 = { len = 1.41, text = "Close to tank state." },
        cmt_fuel_near_tank_2 = { len = 1.48, text = "Not much over tank." },
        cmt_fuel_below_tank_1 = { len = 1.37, text = "That's below tank." },
        cmt_fuel_below_tank_2 = { len = 1.65, text = "Under tank state. Hmm." },
        bug_h_1            = { len = 1.62, text = "Bingo bug's at..." },
        bug_h_2            = { len = 1.30, text = "Bug's set to..." },
        bug_off_1          = { len = 1.65, text = "That's not what the card says." },
        bug_off_2          = { len = 2.10, text = "Hmm. Bug doesn't match the card." },
        bug_ok_1           = { len = 1.49, text = "Matches the card." },
        bug_ok_2           = { len = 0.77, text = "Good." },
        cp_h_1             = { len = 1.32, text = "CP Tiger..." },
        cp_h_2             = { len = 1.43, text = "Contact point..." },
        mother_h_1         = { len = 0.99, text = "Mother's..." },
        mother_h_2         = { len = 0.84, text = "Boat's..." },
        mother_h_3         = { len = 1.06, text = "The ship's..." },
        tanker_h_1         = { len = 0.98, text = "Tanker's..." },
        tanker_h_2         = { len = 1.22, text = "Texaco's..." },
        field_ltag_1       = { len = 1.25, text = "Incirlik's..." },
        field_lcra_1       = { len = 1.23, text = "Akrotiri's..." },
        cmt_time_early_1   = { len = 1.27, text = "Plenty of time." },
        cmt_time_early_2   = { len = 1.01, text = "No rush." },
        cmt_time_ok_1      = { len = 1.41, text = "Right where I want to be." },
        cmt_time_ok_2      = { len = 0.77, text = "Good." },
        cmt_time_late_1    = { len = 1.48, text = "Behind the clock a bit." },
        cmt_time_late_2    = { len = 1.28, text = "Hmm. Behind." },
        vul_h_1            = { len = 1.44, text = "VUL closes in..." },
        vul_h_2            = { len = 1.59, text = "On station for another..." },
        vul_past_1         = { len = 1.42, text = "We're past the VUL." },
        vul_past_2         = { len = 1.63, text = "VUL's over. Hmm." },
        push_h_1           = { len = 1.00, text = "Push in..." },
        push_h_2           = { len = 1.35, text = "Push time's in..." },
        level_h_1          = { len = 1.12, text = "Level at..." },
        level_h_2          = { len = 0.95, text = "Holding..." },
        cmt_alt_1          = { len = 0.76, text = "Good." },
        cmt_alt_2          = { len = 1.17, text = "Nice and level." },
        sys_h_1            = { len = 1.10, text = "Quick scan." },
        sys_h_2            = { len = 1.51, text = "Systems check." },
        sys_h_3            = { len = 1.67, text = "Let's look around the cockpit." },
        sys_h_4            = { len = 1.47, text = "Instrument scan." },
        eng_both_1         = { len = 1.41, text = "Both engines..." },
        eng_both_2         = { len = 0.76, text = "Both at..." },
        eng_left_1         = { len = 0.78, text = "Left..." },
        eng_right_1        = { len = 0.80, text = "Right..." },
        eng_ok_1           = { len = 1.31, text = "Engines look good." },
        eng_ok_2           = { len = 1.62, text = "Both motors in the green." },
        eng_ok_3           = { len = 1.20, text = "Temps normal." },
        hyd_ok_1           = { len = 1.36, text = "Hydraulics good." },
        hyd_ok_2           = { len = 1.34, text = "Hyd pressures good." },
        elec_ok_1          = { len = 1.53, text = "Generators online." },
        elec_ok_2          = { len = 1.25, text = "Electrics good." },
        oxy_ok_1           = { len = 2.22, text = "Oxygen's flowing. Mask's good." },
        oxy_ok_2           = { len = 1.33, text = "Breathing's fine." },
        caution_none_1     = { len = 1.28, text = "No cautions." },
        caution_none_2     = { len = 1.64, text = "Caution panel's clean." },
        caution_lit_1      = { len = 2.09, text = "Hmm. Master caution's on." },
        caution_lit_2      = { len = 1.95, text = "Caution light... what's that?" },
        sys_done_1         = { len = 1.06, text = "All good." },
        sys_done_2         = { len = 1.44, text = "Everything's normal." },
        sys_done_3         = { len = 0.95, text = "Okay." },
        fence_in_h_1       = { len = 1.08, text = "Fence in." },
        fence_in_h_2       = { len = 2.14, text = "Okay, fence in checks." },
        fence_out_h_1      = { len = 1.13, text = "Fence out." },
        fence_out_h_2      = { len = 1.70, text = "Okay, fence out." },
        attack_h_1         = { len = 1.76, text = "Okay, attack checks." },
        attack_h_2         = { len = 1.26, text = "Attack checks." },
        attack_h_3         = { len = 1.05, text = "Let's set up." },
        marm_arm_1         = { len = 2.02, text = "Master arm... armed." },
        marm_safe_1        = { len = 1.49, text = "Master arm... safe." },
        ag_mode_1          = { len = 1.39, text = "Air-to-ground mode." },
        ag_not_1           = { len = 1.67, text = "Not in air-to-ground mode." },
        laser_arm_1        = { len = 1.27, text = "Laser armed." },
        laser_safe_1       = { len = 1.15, text = "Laser... safe." },
        radar_opr_1        = { len = 1.59, text = "Radar's operating." },
        radar_stby_1       = { len = 1.91, text = "Radar, standby." },
        radar_off_1        = { len = 1.01, text = "Radar off." },
        disp_on_1          = { len = 1.30, text = "Dispenser on." },
        disp_off_1         = { len = 1.20, text = "Dispenser... off." },
        disp_bypass_1      = { len = 1.77, text = "Dispenser in bypass." },
        code_h_1           = { len = 0.74, text = "Code..." },
        code_h_2           = { len = 1.16, text = "Laser code..." },
        fenced_in_1        = { len = 1.77, text = "Okay. Fenced in." },
        fenced_in_2        = { len = 1.15, text = "Ready to work." },
        fenced_out_1       = { len = 1.70, text = "Fenced out. Heading home." },
        fenced_out_2       = { len = 1.52, text = "Okay, that's fence out." },
        attack_done_1      = { len = 0.83, text = "Ready." },
        attack_done_2      = { len = 1.43, text = "Okay. Set." },
        attack_done_3      = { len = 1.08, text = "Good to go." },
        joker_call_1       = { len = 1.18, text = "That's joker." },
        joker_call_2       = { len = 1.35, text = "Joker fuel." },
        joker_call_3       = { len = 1.15, text = "Joker... okay." },
        bingo_call_1       = { len = 2.08, text = "Bingo. That's bingo fuel." },
        bingo_call_2       = { len = 1.37, text = "And that's bingo." },
        bingo_call_3       = { len = 1.71, text = "Bingo fuel... time to go." },
        tank_call_1        = { len = 1.23, text = "That's tank state." },
        tank_call_2        = { len = 1.61, text = "Tank fuel. Hmm." },
        aar_h_1            = { len = 1.26, text = "Tanker checks." },
        aar_h_2            = { len = 2.12, text = "Okay, pre-contact checks." },
        probe_out_1        = { len = 0.91, text = "Probe out." },
        probe_in_1         = { len = 0.91, text = "Probe in." },
        probe_still_out_1  = { len = 1.16, text = "Probe's still out." },
        probe_still_in_1   = { len = 1.28, text = "Probe's still in." },
        aar_closure_1      = { len = 2.36, text = "Easy... too much closure." },
        aar_closure_2      = { len = 1.84, text = "Whoa, closing fast." },
        aar_steady_1       = { len = 1.21, text = "Steady... steady." },
        aar_steady_2       = { len = 1.48, text = "Nice and easy." },
        aar_steady_3       = { len = 1.48, text = "Okay, stabilized." },
        aar_taking_1       = { len = 1.19, text = "Taking gas..." },
        aar_taking_2       = { len = 1.23, text = "Fuel's flowing..." },
        aar_taking_3       = { len = 0.89, text = "Coming up..." },
        disc_h_1           = { len = 1.10, text = "Disconnect..." },
        disc_h_2           = { len = 2.25, text = "Okay, disconnected..." },
        post_aar_h_1       = { len = 1.36, text = "Off the tanker." },
        post_aar_h_2       = { len = 1.64, text = "Post-tanker checks." },
        hold_h_1           = { len = 1.20, text = "Established." },
        hold_h_2           = { len = 1.35, text = "Okay, holding." },
        hold_h_3           = { len = 1.20, text = "In the stack." },
        commence_h_1       = { len = 1.00, text = "Commencing." },
        commence_h_2       = { len = 1.48, text = "Okay, down we go." },
        approach_h_1       = { len = 1.32, text = "Approach check." },
        approach_h_2       = { len = 1.66, text = "Okay, getting close." },
        hook_down_1        = { len = 1.03, text = "Hook down." },
        hook_down_2        = { len = 1.18, text = "Hook's down." },
        hook_up_warn_1     = { len = 1.36, text = "Hook... hook's still up." },
        hook_up_warn_2     = { len = 1.62, text = "Wait... hook's up." },
        hook_up_field_1    = { len = 0.87, text = "Hook up." },
        landing_h_1        = { len = 1.16, text = "Landing check." },
        landing_h_2        = { len = 1.67, text = "Okay, landing checklist." },
        wheels_down_1      = { len = 1.89, text = "Wheels, three down." },
        wheels_down_2      = { len = 1.43, text = "Three down and locked." },
        wheels_not_1       = { len = 2.46, text = "Wheels... not all down." },
        flaps_down_1       = { len = 1.22, text = "Flaps down." },
        flaps_up_1         = { len = 1.28, text = "Flaps... still up." },
        harness_1          = { len = 1.14, text = "Harness locked." },
        landing_done_1     = { len = 1.40, text = "Landing check complete." },
        landing_done_2     = { len = 1.07, text = "Checks complete." },
        divert_h_1         = { len = 1.52, text = "Okay. Divert." },
        divert_h_2         = { len = 2.33, text = "Alright... divert it is." },
        muse_day_sea_1     = { len = 1.88, text = "Water's really blue today." },
        muse_day_sea_2     = { len = 2.23, text = "Not a ship in sight... except ours." },
        muse_day_sea_3     = { len = 1.99, text = "Look at that. Glassy water." },
        muse_day_sea_4     = { len = 1.73, text = "Sun on the water. Pretty." },
        muse_day_sea_5     = { len = 1.55, text = "Haze over the sea today." },
        muse_day_sea_6     = { len = 2.52, text = "Somebody's sailing down there. Lucky guy." },
        muse_day_land_1    = { len = 1.94, text = "Mountains look sharp today." },
        muse_day_land_2    = { len = 2.89, text = "Farms down there... little squares everywhere." },
        muse_day_land_3    = { len = 2.02, text = "Hard to believe there's a war down there." },
        muse_day_land_4    = { len = 1.42, text = "Look at that ridge line." },
        muse_day_land_5    = { len = 1.16, text = "Dusty down there." },
        muse_day_land_6    = { len = 1.86, text = "Towns all along the coast." },
        muse_night_1       = { len = 1.13, text = "Dark out here." },
        muse_night_2       = { len = 1.53, text = "Stars are out. Wow." },
        muse_night_3       = { len = 1.81, text = "City lights on the horizon." },
        muse_night_4       = { len = 1.40, text = "Black hole down there." },
        muse_night_5       = { len = 1.86, text = "Not much to see tonight." },
        muse_twilight_1    = { len = 2.12, text = "Sky's changing color. Nice." },
        muse_twilight_2    = { len = 1.52, text = "Look at that horizon." },
        muse_twilight_3    = { len = 1.97, text = "Light's going soft. Pretty." },
        muse_twilight_4    = { len = 2.10, text = "Best time of day to be up here." },
        muse_life_1        = { len = 2.26, text = "Should've grabbed a coffee before the brief." },
        muse_life_2        = { len = 2.19, text = "Wonder what's for dinner on the boat." },
        muse_life_3        = { len = 2.04, text = "Sliders tonight, I bet." },
        muse_life_4        = { len = 2.32, text = "Need to call home when we get back." },
        muse_life_5        = { len = 2.50, text = "Did I leave my laundry in the dryer?" },
        muse_life_6        = { len = 2.23, text = "Ready room movie tonight, I hope." },
        muse_life_7        = { len = 1.79, text = "Mail call should be tomorrow." },
        muse_life_8        = { len = 1.60, text = "These boots are killing me." },
        muse_life_9        = { len = 1.95, text = "My back's going to feel this one." },
        muse_life_10       = { len = 2.00, text = "Should've hit the head before the walk." },
        muse_life_11       = { len = 1.96, text = "Hope the gym's not packed tonight." },
        muse_life_12       = { len = 1.96, text = "Haven't slept right in a week." },
        muse_life_13       = { len = 1.97, text = "That song's stuck in my head again." },
        muse_life_14       = { len = 2.10, text = "Note to self. New sunglasses." },
        muse_life_15       = { len = 2.00, text = "I still owe Mike twenty bucks." },
        muse_life_16       = { len = 1.88, text = "Birthday card... need to send that." },
        muse_life_17       = { len = 2.12, text = "Paperwork waiting for me. Great." },
        muse_life_18       = { len = 1.76, text = "Long day. Long day." },
        muse_life_19       = { len = 1.97, text = "Wonder how the game went last night." },
        muse_life_20       = { len = 1.92, text = "Two more weeks till port call." },
        muse_life_21       = { len = 1.23, text = "Need a haircut." },
        muse_life_22       = { len = 1.42, text = "Should write a letter tonight." },
        muse_life_23       = { len = 2.16, text = "Midrats after this. Maybe." },
        muse_life_24       = { len = 1.30, text = "This mask itches." },
        muse_life_25       = { len = 2.09, text = "Gonna sleep like a rock tonight." },
        muse_life_26       = { len = 2.38, text = "Who schedules these brief times anyway?" },
        muse_life_27       = { len = 2.36, text = "Wonder if the ice cream machine works yet." },
        muse_life_28       = { len = 1.51, text = "Gotta finish that book." },
        noise_1            = { len = 0.82, text = "Hmm." },
        noise_2            = { len = 1.12, text = "Mm-hmm." },
        noise_3            = { len = 0.79, text = "Haaah." },
        noise_4            = { len = 0.88, text = "Ahem." },
        noise_5            = { len = 0.78, text = "Aaah... hmm." },
        noise_6            = { len = 0.98, text = "Hm hm hmm." },
        noise_7            = { len = 1.31, text = "Okay, okay." },
        noise_8            = { len = 0.77, text = "Whew." },
        v_fuel_0           = { len = 1.22, text = "point zero" },
        v_fuel_1           = { len = 1.01, text = "point one" },
        v_fuel_2           = { len = 1.03, text = "point two" },
        v_fuel_3           = { len = 1.18, text = "point three" },
        v_fuel_4           = { len = 1.06, text = "point four" },
        v_fuel_5           = { len = 1.19, text = "point five" },
        v_fuel_6           = { len = 1.23, text = "point six" },
        v_fuel_7           = { len = 1.00, text = "point seven" },
        v_fuel_8           = { len = 0.97, text = "point eight" },
        v_fuel_9           = { len = 1.14, text = "point nine" },
        v_fuel_10          = { len = 1.46, text = "one point zero" },
        v_fuel_11          = { len = 1.34, text = "one point one" },
        v_fuel_12          = { len = 1.46, text = "one point two" },
        v_fuel_13          = { len = 1.39, text = "one point three" },
        v_fuel_14          = { len = 1.30, text = "one point four" },
        v_fuel_15          = { len = 1.36, text = "one point five" },
        v_fuel_16          = { len = 1.51, text = "one point six" },
        v_fuel_17          = { len = 1.59, text = "one point seven" },
        v_fuel_18          = { len = 1.19, text = "one point eight" },
        v_fuel_19          = { len = 1.30, text = "one point nine" },
        v_fuel_20          = { len = 1.49, text = "two point zero" },
        v_fuel_21          = { len = 1.21, text = "two point one" },
        v_fuel_22          = { len = 1.27, text = "two point two" },
        v_fuel_23          = { len = 1.25, text = "two point three" },
        v_fuel_24          = { len = 1.30, text = "two point four" },
        v_fuel_25          = { len = 1.34, text = "two point five" },
        v_fuel_26          = { len = 1.44, text = "two point six" },
        v_fuel_27          = { len = 1.48, text = "two point seven" },
        v_fuel_28          = { len = 1.16, text = "two point eight" },
        v_fuel_29          = { len = 1.19, text = "two point nine" },
        v_fuel_30          = { len = 1.65, text = "three point zero" },
        v_fuel_31          = { len = 1.66, text = "three point one" },
        v_fuel_32          = { len = 1.70, text = "three point two" },
        v_fuel_33          = { len = 1.31, text = "three point three" },
        v_fuel_34          = { len = 1.74, text = "three point four" },
        v_fuel_35          = { len = 1.73, text = "three point five" },
        v_fuel_36          = { len = 1.67, text = "three point six" },
        v_fuel_37          = { len = 2.09, text = "three point seven" },
        v_fuel_38          = { len = 1.26, text = "three point eight" },
        v_fuel_39          = { len = 1.42, text = "three point nine" },
        v_fuel_40          = { len = 1.50, text = "four point zero" },
        v_fuel_41          = { len = 1.32, text = "four point one" },
        v_fuel_42          = { len = 1.30, text = "four point two" },
        v_fuel_43          = { len = 1.37, text = "four point three" },
        v_fuel_44          = { len = 1.29, text = "four point four" },
        v_fuel_45          = { len = 1.39, text = "four point five" },
        v_fuel_46          = { len = 1.56, text = "four point six" },
        v_fuel_47          = { len = 1.47, text = "four point seven" },
        v_fuel_48          = { len = 1.38, text = "four point eight" },
        v_fuel_49          = { len = 1.33, text = "four point nine" },
        v_fuel_50          = { len = 1.68, text = "five point zero" },
        v_fuel_51          = { len = 1.76, text = "five point one" },
        v_fuel_52          = { len = 1.68, text = "five point two" },
        v_fuel_53          = { len = 1.72, text = "five point three" },
        v_fuel_54          = { len = 1.56, text = "five point four" },
        v_fuel_55          = { len = 1.39, text = "five point five" },
        v_fuel_56          = { len = 1.63, text = "five point six" },
        v_fuel_57          = { len = 1.79, text = "five point seven" },
        v_fuel_58          = { len = 1.61, text = "five point eight" },
        v_fuel_59          = { len = 1.87, text = "five point nine" },
        v_fuel_60          = { len = 1.57, text = "six point zero" },
        v_fuel_61          = { len = 1.41, text = "six point one" },
        v_fuel_62          = { len = 1.54, text = "six point two" },
        v_fuel_63          = { len = 1.71, text = "six point three" },
        v_fuel_64          = { len = 1.42, text = "six point four" },
        v_fuel_65          = { len = 1.48, text = "six point five" },
        v_fuel_66          = { len = 1.58, text = "six point six" },
        v_fuel_67          = { len = 2.11, text = "six point seven" },
        v_fuel_68          = { len = 1.36, text = "six point eight" },
        v_fuel_69          = { len = 1.41, text = "six point nine" },
        v_fuel_70          = { len = 2.23, text = "seven point zero" },
        v_fuel_71          = { len = 1.71, text = "seven point one" },
        v_fuel_72          = { len = 1.56, text = "seven point two" },
        v_fuel_73          = { len = 1.73, text = "seven point three" },
        v_fuel_74          = { len = 1.74, text = "seven point four" },
        v_fuel_75          = { len = 1.69, text = "seven point five" },
        v_fuel_76          = { len = 1.88, text = "seven point six" },
        v_fuel_77          = { len = 2.11, text = "seven point seven" },
        v_fuel_78          = { len = 1.83, text = "seven point eight" },
        v_fuel_79          = { len = 1.51, text = "seven point nine" },
        v_fuel_80          = { len = 1.32, text = "eight point zero" },
        v_fuel_81          = { len = 1.21, text = "eight point one" },
        v_fuel_82          = { len = 1.26, text = "eight point two" },
        v_fuel_83          = { len = 1.24, text = "eight point three" },
        v_fuel_84          = { len = 1.33, text = "eight point four" },
        v_fuel_85          = { len = 1.44, text = "eight point five" },
        v_fuel_86          = { len = 1.38, text = "eight point six" },
        v_fuel_87          = { len = 1.49, text = "eight point seven" },
        v_fuel_88          = { len = 1.35, text = "eight point eight" },
        v_fuel_89          = { len = 1.33, text = "eight point nine" },
        v_fuel_90          = { len = 1.59, text = "nine point zero" },
        v_fuel_91          = { len = 1.50, text = "nine point one" },
        v_fuel_92          = { len = 1.42, text = "nine point two" },
        v_fuel_93          = { len = 1.52, text = "nine point three" },
        v_fuel_94          = { len = 1.64, text = "nine point four" },
        v_fuel_95          = { len = 1.36, text = "nine point five" },
        v_fuel_96          = { len = 1.46, text = "nine point six" },
        v_fuel_97          = { len = 1.71, text = "nine point seven" },
        v_fuel_98          = { len = 1.62, text = "nine point eight" },
        v_fuel_99          = { len = 1.61, text = "nine point nine" },
        v_fuel_100         = { len = 1.72, text = "ten point zero" },
        v_fuel_101         = { len = 1.46, text = "ten point one" },
        v_fuel_102         = { len = 1.75, text = "ten point two" },
        v_fuel_103         = { len = 1.23, text = "ten point three" },
        v_fuel_104         = { len = 1.80, text = "ten point four" },
        v_fuel_105         = { len = 1.71, text = "ten point five" },
        v_fuel_106         = { len = 1.78, text = "ten point six" },
        v_fuel_107         = { len = 2.10, text = "ten point seven" },
        v_fuel_108         = { len = 1.51, text = "ten point eight" },
        v_fuel_109         = { len = 1.58, text = "ten point nine" },
        v_fuel_110         = { len = 2.40, text = "eleven point zero" },
        v_fuel_111         = { len = 1.70, text = "eleven point one" },
        v_fuel_112         = { len = 2.04, text = "eleven point two" },
        v_fuel_113         = { len = 1.90, text = "eleven point three" },
        v_fuel_114         = { len = 2.08, text = "eleven point four" },
        v_fuel_115         = { len = 2.02, text = "eleven point five" },
        v_fuel_116         = { len = 1.84, text = "eleven point six" },
        v_fuel_117         = { len = 1.85, text = "eleven point seven" },
        v_fuel_118         = { len = 1.91, text = "eleven point eight" },
        v_fuel_119         = { len = 1.99, text = "eleven point nine" },
        v_fuel_120         = { len = 1.94, text = "twelve point zero" },
        v_fuel_121         = { len = 1.34, text = "twelve point one" },
        v_fuel_122         = { len = 1.84, text = "twelve point two" },
        v_fuel_123         = { len = 1.93, text = "twelve point three" },
        v_fuel_124         = { len = 1.46, text = "twelve point four" },
        v_fuel_125         = { len = 1.85, text = "twelve point five" },
        v_fuel_126         = { len = 1.88, text = "twelve point six" },
        v_fuel_127         = { len = 1.68, text = "twelve point seven" },
        v_fuel_128         = { len = 1.41, text = "twelve point eight" },
        v_fuel_129         = { len = 1.77, text = "twelve point nine" },
        v_fuel_130         = { len = 1.51, text = "thirteen point zero" },
        v_fuel_131         = { len = 1.49, text = "thirteen point one" },
        v_fuel_132         = { len = 1.53, text = "thirteen point two" },
        v_fuel_133         = { len = 1.70, text = "thirteen point three" },
        v_fuel_134         = { len = 1.89, text = "thirteen point four" },
        v_fuel_135         = { len = 1.52, text = "thirteen point five" },
        v_fuel_136         = { len = 2.29, text = "thirteen point six" },
        v_fuel_137         = { len = 1.52, text = "thirteen point seven" },
        v_fuel_138         = { len = 1.47, text = "thirteen point eight" },
        v_fuel_139         = { len = 2.22, text = "thirteen point nine" },
        v_fuel_140         = { len = 1.68, text = "fourteen point zero" },
        v_fuel_141         = { len = 1.57, text = "fourteen point one" },
        v_fuel_142         = { len = 1.42, text = "fourteen point two" },
        v_fuel_143         = { len = 1.47, text = "fourteen point three" },
        v_fuel_144         = { len = 1.80, text = "fourteen point four" },
        v_fuel_145         = { len = 1.98, text = "fourteen point five" },
        v_fuel_146         = { len = 1.79, text = "fourteen point six" },
        v_fuel_147         = { len = 1.52, text = "fourteen point seven" },
        v_fuel_148         = { len = 1.83, text = "fourteen point eight" },
        v_fuel_149         = { len = 1.53, text = "fourteen point nine" },
        v_fuel_150         = { len = 2.30, text = "fifteen point zero" },
        v_fuel_151         = { len = 1.61, text = "fifteen point one" },
        v_fuel_152         = { len = 1.56, text = "fifteen point two" },
        v_fuel_153         = { len = 1.56, text = "fifteen point three" },
        v_fuel_154         = { len = 1.75, text = "fifteen point four" },
        v_fuel_155         = { len = 2.06, text = "fifteen point five" },
        v_fuel_156         = { len = 1.67, text = "fifteen point six" },
        v_fuel_157         = { len = 1.61, text = "fifteen point seven" },
        v_fuel_158         = { len = 1.40, text = "fifteen point eight" },
        v_fuel_159         = { len = 1.37, text = "fifteen point nine" },
        v_fuel_160         = { len = 1.80, text = "sixteen point zero" },
        v_fuel_161         = { len = 1.62, text = "sixteen point one" },
        v_fuel_162         = { len = 1.81, text = "sixteen point two" },
        v_fuel_163         = { len = 1.72, text = "sixteen point three" },
        v_fuel_164         = { len = 1.91, text = "sixteen point four" },
        v_fuel_165         = { len = 1.74, text = "sixteen point five" },
        v_fuel_166         = { len = 2.15, text = "sixteen point six" },
        v_fuel_167         = { len = 2.06, text = "sixteen point seven" },
        v_fuel_168         = { len = 1.50, text = "sixteen point eight" },
        v_fuel_169         = { len = 1.63, text = "sixteen point nine" },
        v_fuel_170         = { len = 2.07, text = "seventeen point zero" },
        v_fuel_171         = { len = 1.98, text = "seventeen point one" },
        v_fuel_172         = { len = 1.73, text = "seventeen point two" },
        v_fuel_173         = { len = 1.94, text = "seventeen point three" },
        v_fuel_174         = { len = 2.02, text = "seventeen point four" },
        v_fuel_175         = { len = 2.08, text = "seventeen point five" },
        v_fuel_176         = { len = 2.24, text = "seventeen point six" },
        v_fuel_177         = { len = 2.17, text = "seventeen point seven" },
        v_fuel_178         = { len = 1.77, text = "seventeen point eight" },
        v_fuel_179         = { len = 1.98, text = "seventeen point nine" },
        v_fuel_180         = { len = 1.50, text = "eighteen point zero" },
        v_fuel_181         = { len = 1.52, text = "eighteen point one" },
        v_fuel_182         = { len = 1.40, text = "eighteen point two" },
        v_fuel_183         = { len = 1.47, text = "eighteen point three" },
        v_fuel_184         = { len = 1.45, text = "eighteen point four" },
        v_fuel_185         = { len = 1.53, text = "eighteen point five" },
        v_fuel_186         = { len = 1.51, text = "eighteen point six" },
        v_fuel_187         = { len = 1.63, text = "eighteen point seven" },
        v_fuel_188         = { len = 1.44, text = "eighteen point eight" },
        v_fuel_189         = { len = 1.48, text = "eighteen point nine" },
        v_fuel_190         = { len = 1.54, text = "nineteen point zero" },
        v_fuel_191         = { len = 1.41, text = "nineteen point one" },
        v_fuel_192         = { len = 1.40, text = "nineteen point two" },
        v_fuel_193         = { len = 1.53, text = "nineteen point three" },
        v_fuel_194         = { len = 1.53, text = "nineteen point four" },
        v_fuel_195         = { len = 1.63, text = "nineteen point five" },
        v_fuel_196         = { len = 1.66, text = "nineteen point six" },
        v_fuel_197         = { len = 1.44, text = "nineteen point seven" },
        v_fuel_198         = { len = 1.32, text = "nineteen point eight" },
        v_fuel_199         = { len = 1.65, text = "nineteen point nine" },
        v_fuel_200         = { len = 1.49, text = "twenty point zero" },
        v_kft_1            = { len = 1.18, text = "one thousand" },
        v_kft_2            = { len = 1.20, text = "two thousand" },
        v_kft_3            = { len = 1.23, text = "three thousand" },
        v_kft_4            = { len = 1.20, text = "four thousand" },
        v_kft_5            = { len = 1.74, text = "five thousand" },
        v_kft_6            = { len = 1.33, text = "six thousand" },
        v_kft_7            = { len = 1.27, text = "seven thousand" },
        v_kft_8            = { len = 1.11, text = "eight thousand" },
        v_kft_9            = { len = 1.32, text = "nine thousand" },
        v_kft_10           = { len = 1.18, text = "ten thousand" },
        v_kft_11           = { len = 1.42, text = "eleven thousand" },
        v_kft_12           = { len = 1.24, text = "twelve thousand" },
        v_kft_13           = { len = 1.43, text = "thirteen thousand" },
        v_kft_14           = { len = 1.37, text = "fourteen thousand" },
        v_kft_15           = { len = 1.71, text = "fifteen thousand" },
        v_kft_16           = { len = 1.47, text = "sixteen thousand" },
        v_kft_17           = { len = 1.60, text = "seventeen thousand" },
        v_kft_18           = { len = 1.56, text = "eighteen thousand" },
        v_kft_19           = { len = 1.38, text = "nineteen thousand" },
        v_kft_20           = { len = 1.21, text = "twenty thousand" },
        v_kft_21           = { len = 1.41, text = "twenty one thousand" },
        v_kft_22           = { len = 1.42, text = "twenty two thousand" },
        v_kft_23           = { len = 1.53, text = "twenty three thousand" },
        v_kft_24           = { len = 1.46, text = "twenty four thousand" },
        v_kft_25           = { len = 1.65, text = "twenty five thousand" },
        v_kft_26           = { len = 1.41, text = "twenty six thousand" },
        v_kft_27           = { len = 1.45, text = "twenty seven thousand" },
        v_kft_28           = { len = 1.79, text = "twenty eight thousand" },
        v_kft_29           = { len = 1.66, text = "twenty nine thousand" },
        v_kft_30           = { len = 1.15, text = "thirty thousand" },
        v_kft_31           = { len = 1.38, text = "thirty one thousand" },
        v_kft_32           = { len = 1.42, text = "thirty two thousand" },
        v_kft_33           = { len = 1.45, text = "thirty three thousand" },
        v_kft_34           = { len = 1.41, text = "thirty four thousand" },
        v_kft_35           = { len = 1.58, text = "thirty five thousand" },
        v_kft_36           = { len = 1.50, text = "thirty six thousand" },
        v_kft_37           = { len = 1.51, text = "thirty seven thousand" },
        v_kft_38           = { len = 2.06, text = "thirty eight thousand" },
        v_kft_39           = { len = 1.44, text = "thirty nine thousand" },
        v_kft_40           = { len = 1.18, text = "forty thousand" },
        v_kft_41           = { len = 1.31, text = "forty one thousand" },
        v_kft_42           = { len = 1.49, text = "forty two thousand" },
        v_kft_43           = { len = 1.46, text = "forty three thousand" },
        v_kft_44           = { len = 1.36, text = "forty four thousand" },
        v_kft_45           = { len = 1.52, text = "forty five thousand" },
        v_kft_46           = { len = 1.54, text = "forty six thousand" },
        v_kft_47           = { len = 1.53, text = "forty seven thousand" },
        v_kft_48           = { len = 1.61, text = "forty eight thousand" },
        v_kft_49           = { len = 1.56, text = "forty nine thousand" },
        v_kft_50           = { len = 1.34, text = "fifty thousand" },
        v_nm_1             = { len = 1.02, text = "one mile" },
        v_nm_2             = { len = 1.06, text = "two miles" },
        v_nm_3             = { len = 1.44, text = "three miles" },
        v_nm_4             = { len = 1.10, text = "four miles" },
        v_nm_5             = { len = 1.66, text = "five miles" },
        v_nm_6             = { len = 1.17, text = "six miles" },
        v_nm_7             = { len = 1.72, text = "seven miles" },
        v_nm_8             = { len = 1.22, text = "eight miles" },
        v_nm_9             = { len = 1.14, text = "nine miles" },
        v_nm_10            = { len = 1.13, text = "ten miles" },
        v_nm_11            = { len = 1.24, text = "eleven miles" },
        v_nm_12            = { len = 1.78, text = "twelve miles" },
        v_nm_13            = { len = 1.59, text = "thirteen miles" },
        v_nm_14            = { len = 1.34, text = "fourteen miles" },
        v_nm_15            = { len = 1.23, text = "fifteen miles" },
        v_nm_16            = { len = 1.42, text = "sixteen miles" },
        v_nm_17            = { len = 1.59, text = "seventeen miles" },
        v_nm_18            = { len = 1.27, text = "eighteen miles" },
        v_nm_19            = { len = 1.34, text = "nineteen miles" },
        v_nm_20            = { len = 1.16, text = "twenty miles" },
        v_nm_21            = { len = 1.35, text = "twenty one miles" },
        v_nm_22            = { len = 1.67, text = "twenty two miles" },
        v_nm_23            = { len = 1.73, text = "twenty three miles" },
        v_nm_24            = { len = 1.89, text = "twenty four miles" },
        v_nm_25            = { len = 1.42, text = "twenty five miles" },
        v_nm_26            = { len = 1.54, text = "twenty six miles" },
        v_nm_27            = { len = 1.48, text = "twenty seven miles" },
        v_nm_28            = { len = 1.68, text = "twenty eight miles" },
        v_nm_29            = { len = 1.57, text = "twenty nine miles" },
        v_nm_30            = { len = 1.16, text = "thirty miles" },
        v_nm_31            = { len = 1.40, text = "thirty one miles" },
        v_nm_32            = { len = 1.45, text = "thirty two miles" },
        v_nm_33            = { len = 1.37, text = "thirty three miles" },
        v_nm_34            = { len = 1.39, text = "thirty four miles" },
        v_nm_35            = { len = 1.86, text = "thirty five miles" },
        v_nm_36            = { len = 1.38, text = "thirty six miles" },
        v_nm_37            = { len = 1.56, text = "thirty seven miles" },
        v_nm_38            = { len = 1.58, text = "thirty eight miles" },
        v_nm_39            = { len = 1.34, text = "thirty nine miles" },
        v_nm_40            = { len = 1.23, text = "forty miles" },
        v_nm_41            = { len = 1.35, text = "forty one miles" },
        v_nm_42            = { len = 1.34, text = "forty two miles" },
        v_nm_43            = { len = 1.45, text = "forty three miles" },
        v_nm_44            = { len = 1.33, text = "forty four miles" },
        v_nm_45            = { len = 1.59, text = "forty five miles" },
        v_nm_46            = { len = 1.46, text = "forty six miles" },
        v_nm_47            = { len = 1.49, text = "forty seven miles" },
        v_nm_48            = { len = 1.65, text = "forty eight miles" },
        v_nm_49            = { len = 1.43, text = "forty nine miles" },
        v_nm_50            = { len = 1.20, text = "fifty miles" },
        v_nm_51            = { len = 1.55, text = "fifty one miles" },
        v_nm_52            = { len = 1.47, text = "fifty two miles" },
        v_nm_53            = { len = 1.51, text = "fifty three miles" },
        v_nm_54            = { len = 1.47, text = "fifty four miles" },
        v_nm_55            = { len = 1.49, text = "fifty five miles" },
        v_nm_56            = { len = 1.54, text = "fifty six miles" },
        v_nm_57            = { len = 1.55, text = "fifty seven miles" },
        v_nm_58            = { len = 1.80, text = "fifty eight miles" },
        v_nm_59            = { len = 1.43, text = "fifty nine miles" },
        v_nm_60            = { len = 1.29, text = "sixty miles" },
        v_nm_61            = { len = 1.51, text = "sixty one miles" },
        v_nm_62            = { len = 1.47, text = "sixty two miles" },
        v_nm_63            = { len = 1.62, text = "sixty three miles" },
        v_nm_64            = { len = 1.55, text = "sixty four miles" },
        v_nm_65            = { len = 1.81, text = "sixty five miles" },
        v_nm_66            = { len = 1.81, text = "sixty six miles" },
        v_nm_67            = { len = 1.80, text = "sixty seven miles" },
        v_nm_68            = { len = 1.70, text = "sixty eight miles" },
        v_nm_69            = { len = 1.56, text = "sixty nine miles" },
        v_nm_70            = { len = 1.25, text = "seventy miles" },
        v_nm_71            = { len = 1.92, text = "seventy one miles" },
        v_nm_72            = { len = 1.63, text = "seventy two miles" },
        v_nm_73            = { len = 1.63, text = "seventy three miles" },
        v_nm_74            = { len = 1.55, text = "seventy four miles" },
        v_nm_75            = { len = 1.66, text = "seventy five miles" },
        v_nm_76            = { len = 1.61, text = "seventy six miles" },
        v_nm_77            = { len = 2.01, text = "seventy seven miles" },
        v_nm_78            = { len = 1.65, text = "seventy eight miles" },
        v_nm_79            = { len = 1.53, text = "seventy nine miles" },
        v_nm_80            = { len = 1.17, text = "eighty miles" },
        v_nm_81            = { len = 1.33, text = "eighty one miles" },
        v_nm_82            = { len = 1.36, text = "eighty two miles" },
        v_nm_83            = { len = 1.52, text = "eighty three miles" },
        v_nm_84            = { len = 1.43, text = "eighty four miles" },
        v_nm_85            = { len = 1.46, text = "eighty five miles" },
        v_nm_86            = { len = 1.45, text = "eighty six miles" },
        v_nm_87            = { len = 1.49, text = "eighty seven miles" },
        v_nm_88            = { len = 1.60, text = "eighty eight miles" },
        v_nm_89            = { len = 1.32, text = "eighty nine miles" },
        v_nm_90            = { len = 1.28, text = "ninety miles" },
        v_nm_91            = { len = 1.42, text = "ninety one miles" },
        v_nm_92            = { len = 1.70, text = "ninety two miles" },
        v_nm_93            = { len = 1.53, text = "ninety three miles" },
        v_nm_94            = { len = 1.45, text = "ninety four miles" },
        v_nm_95            = { len = 1.72, text = "ninety five miles" },
        v_nm_96            = { len = 1.53, text = "ninety six miles" },
        v_nm_97            = { len = 1.61, text = "ninety seven miles" },
        v_nm_98            = { len = 1.81, text = "ninety eight miles" },
        v_nm_99            = { len = 1.27, text = "ninety nine miles" },
        v_nm_100           = { len = 1.36, text = "one hundred miles" },
        v_nm_110           = { len = 1.66, text = "one hundred ten miles" },
        v_nm_120           = { len = 1.68, text = "one hundred twenty miles" },
        v_nm_130           = { len = 1.64, text = "one hundred thirty miles" },
        v_nm_140           = { len = 1.77, text = "one hundred forty miles" },
        v_nm_150           = { len = 1.69, text = "one hundred fifty miles" },
        v_nm_160           = { len = 1.66, text = "one hundred sixty miles" },
        v_nm_170           = { len = 1.79, text = "one hundred seventy miles" },
        v_nm_180           = { len = 1.66, text = "one hundred eighty miles" },
        v_nm_190           = { len = 1.63, text = "one hundred ninety miles" },
        v_nm_200           = { len = 1.25, text = "two hundred miles" },
        v_nm_210           = { len = 1.54, text = "two hundred ten miles" },
        v_nm_220           = { len = 1.56, text = "two hundred twenty miles" },
        v_nm_230           = { len = 1.68, text = "two hundred thirty miles" },
        v_nm_240           = { len = 1.65, text = "two hundred forty miles" },
        v_nm_250           = { len = 1.55, text = "two hundred fifty miles" },
        v_nm_260           = { len = 1.65, text = "two hundred sixty miles" },
        v_nm_270           = { len = 1.74, text = "two hundred seventy miles" },
        v_nm_280           = { len = 1.54, text = "two hundred eighty miles" },
        v_nm_290           = { len = 1.72, text = "two hundred ninety miles" },
        v_nm_300           = { len = 1.67, text = "three hundred miles" },
        v_nm_310           = { len = 2.06, text = "three hundred ten miles" },
        v_nm_320           = { len = 1.71, text = "three hundred twenty miles" },
        v_nm_330           = { len = 2.29, text = "three hundred thirty miles" },
        v_nm_340           = { len = 1.97, text = "three hundred forty miles" },
        v_nm_350           = { len = 2.22, text = "three hundred fifty miles" },
        v_nm_360           = { len = 2.13, text = "three hundred sixty miles" },
        v_nm_370           = { len = 2.04, text = "three hundred seventy miles" },
        v_nm_380           = { len = 2.16, text = "three hundred eighty miles" },
        v_nm_390           = { len = 2.16, text = "three hundred ninety miles" },
        v_nm_400           = { len = 1.40, text = "four hundred miles" },
        v_min_1            = { len = 0.97, text = "one minute" },
        v_min_2            = { len = 0.97, text = "two minutes" },
        v_min_3            = { len = 1.16, text = "three minutes" },
        v_min_4            = { len = 1.01, text = "four minutes" },
        v_min_5            = { len = 1.22, text = "five minutes" },
        v_min_6            = { len = 1.23, text = "six minutes" },
        v_min_7            = { len = 1.19, text = "seven minutes" },
        v_min_8            = { len = 1.18, text = "eight minutes" },
        v_min_9            = { len = 1.07, text = "nine minutes" },
        v_min_10           = { len = 1.11, text = "ten minutes" },
        v_min_11           = { len = 1.47, text = "eleven minutes" },
        v_min_12           = { len = 1.10, text = "twelve minutes" },
        v_min_13           = { len = 1.87, text = "thirteen minutes" },
        v_min_14           = { len = 1.33, text = "fourteen minutes" },
        v_min_15           = { len = 1.30, text = "fifteen minutes" },
        v_min_16           = { len = 1.30, text = "sixteen minutes" },
        v_min_17           = { len = 1.58, text = "seventeen minutes" },
        v_min_18           = { len = 1.56, text = "eighteen minutes" },
        v_min_19           = { len = 1.43, text = "nineteen minutes" },
        v_min_20           = { len = 1.14, text = "twenty minutes" },
        v_min_21           = { len = 1.57, text = "twenty one minutes" },
        v_min_22           = { len = 1.88, text = "twenty two minutes" },
        v_min_23           = { len = 1.51, text = "twenty three minutes" },
        v_min_24           = { len = 1.95, text = "twenty four minutes" },
        v_min_25           = { len = 1.40, text = "twenty five minutes" },
        v_min_26           = { len = 1.41, text = "twenty six minutes" },
        v_min_27           = { len = 1.88, text = "twenty seven minutes" },
        v_min_28           = { len = 1.36, text = "twenty eight minutes" },
        v_min_29           = { len = 2.03, text = "twenty nine minutes" },
        v_min_30           = { len = 1.17, text = "thirty minutes" },
        v_min_31           = { len = 1.75, text = "thirty one minutes" },
        v_min_32           = { len = 1.34, text = "thirty two minutes" },
        v_min_33           = { len = 1.43, text = "thirty three minutes" },
        v_min_34           = { len = 1.41, text = "thirty four minutes" },
        v_min_35           = { len = 1.43, text = "thirty five minutes" },
        v_min_36           = { len = 1.48, text = "thirty six minutes" },
        v_min_37           = { len = 1.66, text = "thirty seven minutes" },
        v_min_38           = { len = 1.64, text = "thirty eight minutes" },
        v_min_39           = { len = 1.81, text = "thirty nine minutes" },
        v_min_40           = { len = 1.19, text = "forty minutes" },
        v_min_41           = { len = 1.35, text = "forty one minutes" },
        v_min_42           = { len = 1.42, text = "forty two minutes" },
        v_min_43           = { len = 1.40, text = "forty three minutes" },
        v_min_44           = { len = 1.48, text = "forty four minutes" },
        v_min_45           = { len = 1.59, text = "forty five minutes" },
        v_min_46           = { len = 1.58, text = "forty six minutes" },
        v_min_47           = { len = 1.41, text = "forty seven minutes" },
        v_min_48           = { len = 1.69, text = "forty eight minutes" },
        v_min_49           = { len = 1.33, text = "forty nine minutes" },
        v_min_50           = { len = 1.26, text = "fifty minutes" },
        v_min_51           = { len = 1.50, text = "fifty one minutes" },
        v_min_52           = { len = 1.33, text = "fifty two minutes" },
        v_min_53           = { len = 1.46, text = "fifty three minutes" },
        v_min_54           = { len = 1.40, text = "fifty four minutes" },
        v_min_55           = { len = 1.50, text = "fifty five minutes" },
        v_min_56           = { len = 1.50, text = "fifty six minutes" },
        v_min_57           = { len = 1.55, text = "fifty seven minutes" },
        v_min_58           = { len = 1.52, text = "fifty eight minutes" },
        v_min_59           = { len = 1.55, text = "fifty nine minutes" },
        v_min_60           = { len = 1.39, text = "sixty minutes" },
        v_early_1          = { len = 1.62, text = "about a minute early" },
        v_late_1           = { len = 1.38, text = "about a minute late" },
        v_early_2          = { len = 1.50, text = "about two minutes early" },
        v_late_2           = { len = 1.54, text = "about two minutes late" },
        v_early_3          = { len = 1.87, text = "about three minutes early" },
        v_late_3           = { len = 1.46, text = "about three minutes late" },
        v_early_4          = { len = 1.71, text = "about four minutes early" },
        v_late_4           = { len = 1.50, text = "about four minutes late" },
        v_early_5          = { len = 1.80, text = "about five minutes early" },
        v_late_5           = { len = 1.83, text = "about five minutes late" },
        v_early_6          = { len = 1.76, text = "about six minutes early" },
        v_late_6           = { len = 1.62, text = "about six minutes late" },
        v_early_7          = { len = 1.76, text = "about seven minutes early" },
        v_late_7           = { len = 1.60, text = "about seven minutes late" },
        v_early_8          = { len = 1.72, text = "about eight minutes early" },
        v_late_8           = { len = 1.61, text = "about eight minutes late" },
        v_early_9          = { len = 1.71, text = "about nine minutes early" },
        v_late_9           = { len = 1.71, text = "about nine minutes late" },
        v_early_10         = { len = 1.70, text = "about ten minutes early" },
        v_late_10          = { len = 1.58, text = "about ten minutes late" },
        v_early_11         = { len = 2.10, text = "about eleven minutes early" },
        v_late_11          = { len = 1.76, text = "about eleven minutes late" },
        v_early_12         = { len = 1.89, text = "about twelve minutes early" },
        v_late_12          = { len = 1.57, text = "about twelve minutes late" },
        v_early_13         = { len = 1.83, text = "about thirteen minutes early" },
        v_late_13          = { len = 1.73, text = "about thirteen minutes late" },
        v_early_14         = { len = 2.01, text = "about fourteen minutes early" },
        v_late_14          = { len = 1.91, text = "about fourteen minutes late" },
        v_early_15         = { len = 1.81, text = "about fifteen minutes early" },
        v_late_15          = { len = 1.72, text = "about fifteen minutes late" },
        v_early_16         = { len = 1.88, text = "about sixteen minutes early" },
        v_late_16          = { len = 1.85, text = "about sixteen minutes late" },
        v_early_17         = { len = 2.67, text = "about seventeen minutes early" },
        v_late_17          = { len = 2.05, text = "about seventeen minutes late" },
        v_early_18         = { len = 2.05, text = "about eighteen minutes early" },
        v_late_18          = { len = 1.78, text = "about eighteen minutes late" },
        v_early_19         = { len = 1.87, text = "about nineteen minutes early" },
        v_late_19          = { len = 1.78, text = "about nineteen minutes late" },
        v_early_20         = { len = 1.72, text = "about twenty minutes early" },
        v_late_20          = { len = 1.63, text = "about twenty minutes late" },
        v_early_21         = { len = 1.89, text = "about twenty one minutes early" },
        v_late_21          = { len = 1.87, text = "about twenty one minutes late" },
        v_early_22         = { len = 2.13, text = "about twenty two minutes early" },
        v_late_22          = { len = 1.72, text = "about twenty two minutes late" },
        v_early_23         = { len = 2.01, text = "about twenty three minutes early" },
        v_late_23          = { len = 1.92, text = "about twenty three minutes late" },
        v_early_24         = { len = 1.88, text = "about twenty four minutes early" },
        v_late_24          = { len = 1.88, text = "about twenty four minutes late" },
        v_early_25         = { len = 2.24, text = "about twenty five minutes early" },
        v_late_25          = { len = 1.89, text = "about twenty five minutes late" },
        v_early_26         = { len = 1.97, text = "about twenty six minutes early" },
        v_late_26          = { len = 2.03, text = "about twenty six minutes late" },
        v_early_27         = { len = 2.16, text = "about twenty seven minutes early" },
        v_late_27          = { len = 1.97, text = "about twenty seven minutes late" },
        v_early_28         = { len = 2.13, text = "about twenty eight minutes early" },
        v_late_28          = { len = 1.88, text = "about twenty eight minutes late" },
        v_early_29         = { len = 2.14, text = "about twenty nine minutes early" },
        v_late_29          = { len = 1.86, text = "about twenty nine minutes late" },
        v_early_30         = { len = 1.81, text = "about thirty minutes early" },
        v_late_30          = { len = 1.84, text = "about thirty minutes late" },
        v_ontime           = { len = 1.40, text = "right on time" },
        v_pct_50           = { len = 1.30, text = "fifty percent" },
        v_pct_51           = { len = 1.36, text = "fifty one percent" },
        v_pct_52           = { len = 1.44, text = "fifty two percent" },
        v_pct_53           = { len = 1.55, text = "fifty three percent" },
        v_pct_54           = { len = 1.56, text = "fifty four percent" },
        v_pct_55           = { len = 1.54, text = "fifty five percent" },
        v_pct_56           = { len = 1.48, text = "fifty six percent" },
        v_pct_57           = { len = 1.95, text = "fifty seven percent" },
        v_pct_58           = { len = 1.92, text = "fifty eight percent" },
        v_pct_59           = { len = 1.56, text = "fifty nine percent" },
        v_pct_60           = { len = 1.31, text = "sixty percent" },
        v_pct_61           = { len = 1.49, text = "sixty one percent" },
        v_pct_62           = { len = 1.53, text = "sixty two percent" },
        v_pct_63           = { len = 1.51, text = "sixty three percent" },
        v_pct_64           = { len = 1.55, text = "sixty four percent" },
        v_pct_65           = { len = 1.48, text = "sixty five percent" },
        v_pct_66           = { len = 1.66, text = "sixty six percent" },
        v_pct_67           = { len = 1.90, text = "sixty seven percent" },
        v_pct_68           = { len = 1.67, text = "sixty eight percent" },
        v_pct_69           = { len = 1.70, text = "sixty nine percent" },
        v_pct_70           = { len = 1.37, text = "seventy percent" },
        v_pct_71           = { len = 1.53, text = "seventy one percent" },
        v_pct_72           = { len = 1.60, text = "seventy two percent" },
        v_pct_73           = { len = 1.59, text = "seventy three percent" },
        v_pct_74           = { len = 1.68, text = "seventy four percent" },
        v_pct_75           = { len = 1.76, text = "seventy five percent" },
        v_pct_76           = { len = 1.73, text = "seventy six percent" },
        v_pct_77           = { len = 2.02, text = "seventy seven percent" },
        v_pct_78           = { len = 1.72, text = "seventy eight percent" },
        v_pct_79           = { len = 1.99, text = "seventy nine percent" },
        v_pct_80           = { len = 1.20, text = "eighty percent" },
        v_pct_81           = { len = 1.34, text = "eighty one percent" },
        v_pct_82           = { len = 1.42, text = "eighty two percent" },
        v_pct_83           = { len = 1.48, text = "eighty three percent" },
        v_pct_84           = { len = 1.43, text = "eighty four percent" },
        v_pct_85           = { len = 1.47, text = "eighty five percent" },
        v_pct_86           = { len = 1.43, text = "eighty six percent" },
        v_pct_87           = { len = 1.41, text = "eighty seven percent" },
        v_pct_88           = { len = 1.92, text = "eighty eight percent" },
        v_pct_89           = { len = 1.35, text = "eighty nine percent" },
        v_pct_90           = { len = 1.20, text = "ninety percent" },
        v_pct_91           = { len = 1.42, text = "ninety one percent" },
        v_pct_92           = { len = 1.58, text = "ninety two percent" },
        v_pct_93           = { len = 1.57, text = "ninety three percent" },
        v_pct_94           = { len = 1.41, text = "ninety four percent" },
        v_pct_95           = { len = 1.53, text = "ninety five percent" },
        v_pct_96           = { len = 1.62, text = "ninety six percent" },
        v_pct_97           = { len = 1.58, text = "ninety seven percent" },
        v_pct_98           = { len = 1.62, text = "ninety eight percent" },
        v_pct_99           = { len = 1.46, text = "ninety nine percent" },
        v_pct_100          = { len = 1.43, text = "one hundred percent" },
        v_pct_101          = { len = 1.65, text = "one hundred one percent" },
        v_pct_102          = { len = 1.62, text = "one hundred two percent" },
        v_pct_103          = { len = 1.70, text = "one hundred three percent" },
        v_pct_104          = { len = 1.62, text = "one hundred four percent" },
        v_pct_105          = { len = 1.76, text = "one hundred five percent" },
        v_pct_106          = { len = 1.68, text = "one hundred six percent" },
        v_pct_107          = { len = 1.67, text = "one hundred seven percent" },
        v_pct_108          = { len = 1.57, text = "one hundred eight percent" },
        v_pct_109          = { len = 1.72, text = "one hundred nine percent" },
        v_pct_110          = { len = 1.55, text = "one hundred ten percent" },
        v_rate_60          = { len = 1.68, text = "zero sixty a minute" },
        v_rate_70          = { len = 2.06, text = "zero seventy a minute" },
        v_rate_80          = { len = 1.73, text = "zero eighty a minute" },
        v_rate_90          = { len = 1.72, text = "zero ninety a minute" },
        v_rate_100         = { len = 1.26, text = "one hundred a minute" },
        v_rate_110         = { len = 1.57, text = "one ten a minute" },
        v_rate_120         = { len = 1.88, text = "one twenty a minute" },
        v_rate_130         = { len = 1.85, text = "one thirty a minute" },
        v_rate_140         = { len = 1.56, text = "one forty a minute" },
        v_rate_150         = { len = 1.88, text = "one fifty a minute" },
        v_rate_160         = { len = 1.73, text = "one sixty a minute" },
        v_rate_170         = { len = 1.59, text = "one seventy a minute" },
        v_rate_180         = { len = 1.64, text = "one eighty a minute" },
        v_rate_190         = { len = 1.76, text = "one ninety a minute" },
        v_rate_200         = { len = 1.23, text = "two hundred a minute" },
        v_rate_210         = { len = 1.35, text = "two ten a minute" },
        v_rate_220         = { len = 1.76, text = "two twenty a minute" },
        v_rate_230         = { len = 1.73, text = "two thirty a minute" },
        v_rate_240         = { len = 1.76, text = "two forty a minute" },
        v_rate_250         = { len = 1.67, text = "two fifty a minute" },
        v_rate_260         = { len = 1.63, text = "two sixty a minute" },
        v_rate_270         = { len = 1.64, text = "two seventy a minute" },
        v_rate_280         = { len = 2.03, text = "two eighty a minute" },
        v_rate_290         = { len = 1.85, text = "two ninety a minute" },
        v_rate_300         = { len = 1.40, text = "three hundred a minute" },
        v_rate_310         = { len = 1.78, text = "three ten a minute" },
        v_rate_320         = { len = 1.88, text = "three twenty a minute" },
        v_rate_330         = { len = 1.73, text = "three thirty a minute" },
        v_rate_340         = { len = 1.54, text = "three forty a minute" },
        v_rate_350         = { len = 1.99, text = "three fifty a minute" },
        v_rate_360         = { len = 1.94, text = "three sixty a minute" },
        v_rate_370         = { len = 2.22, text = "three seventy a minute" },
        v_rate_380         = { len = 2.10, text = "three eighty a minute" },
        v_rate_390         = { len = 1.90, text = "three ninety a minute" },
        v_rate_400         = { len = 1.31, text = "four hundred a minute" },
        v_stores_0         = { len = 1.40, text = "And... winchester." },
        v_stores_1         = { len = 1.41, text = "One weapon left." },
        v_stores_2         = { len = 1.41, text = "Two weapons left." },
        v_stores_3         = { len = 2.12, text = "Three weapons left." },
        v_stores_4         = { len = 1.40, text = "Four weapons left." },
        v_stores_5         = { len = 1.48, text = "Five weapons left." },
        v_stores_6         = { len = 1.54, text = "Six weapons left." },
        v_stores_7         = { len = 1.62, text = "Seven weapons left." },
        v_stores_8         = { len = 1.40, text = "Eight weapons left." },
        v_code_1688        = { len = 1.50, text = "one six eight eight" },
        snd_1              = { len = 0.93, text = "<COUGH2>" },
        snd_2              = { len = 0.75, text = "<COUGH1>" },
        snd_3              = { len = 1.13, text = "<THROAT>" },
        snd_4              = { len = 0.79, text = "<SNIFF>" },
        snd_5              = { len = 1.68, text = "<BREATH>" },
        snd_6              = { len = 0.90, text = "<COUGH2>" },
    },
    -- END AUDIO
}

-- Cockpit arguments read through the export environment (DCS-BIOS FA-18C_hornet.lua numbers).
-- trust = false: logged for calibration, never spoken.
local CK_ARGS = { 49, 48, 441, 440, 517, 13, 226, 234, 293, 238, 239, 341, 365, 439 }
local CK_MAP = {
    marm   = { arg = 49,  trust = true },    -- Master Arm ARM/SAFE: > 0.5 = ARM (re-calibrated on the first A/G release)
    agLt   = { arg = 48,  trust = true },    -- A/G master mode light
    ltd    = { arg = 441, trust = true },    -- LTD/R ARM/SAFE: > 0.5 = ARM [V]
    radar  = { arg = 440, trust = true },    -- OFF 0 / STBY 0.1 / OPR 0.2 / EMERG 0.3 (DCS-BIOS step table)
    disp   = { arg = 517, trust = true },    -- BYPASS 0 / ON 0.1 / OFF 0.2 (DCS-BIOS step table)
    caut   = { arg = 13,  trust = true },    -- MASTER CAUTION light
}

local HERO = TRT.PLAYER_NAME or "Player_01"

local PB = {
    version   = CFG.VERSION,
    level     = CFG.LEVEL,
    on        = CFG.LEVEL ~= "OFF",
    pending   = {},        -- { name, why, t0, ctx }
    bags      = {},        -- group -> remaining ids
    lastId    = {},        -- group -> last id played
    lastPlay  = {},        -- moment -> time of the last line
    lastItem  = {},        -- cruise item -> time
    lastLine  = -1e9,
    lastRadio = -1e9,      -- last tick the radio was busy
    busyUntil = 0,
    lines     = 0,
    gen       = 0,         -- line generation (cut / supersede)
    playing   = nil,       -- { name, t1, overlap }
    nextCruise = nil,
    w = {
        can = { state = nil, cand = nil, n = 0, logged = false },
        landed = false, catFired = false, stopSince = nil,
        pcStart = nil, pcChecks = nil, tlLaunched = nil,
        surf = nil, dead1 = nil, dead2 = nil,
        splashes = nil, defeated = nil, refuel = nil,
        engaged = false, engT0 = nil, park = nil,
        cdPhase = nil, cvPhase = nil, wasStation = false,
        fenceIn = false, fenceOut = false, divert = false,
        joker = nil, bingo = nil, tank = nil,
        aarN = nil, aarJoin = false, aarAstern = false, aarClos = false, aarTakeT = nil, aarLast = nil,
        aarPostT = -1e9,
        gearDown = nil, gearCand = nil, gearN = 0, landingArmed = true, approachDone = false,
        fuelHist = {},
    },
    abHooked  = false,
    jcHooked  = false,
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
    for _ = 1, 12 do RNG.s = (RNG.s * 16807) % 2147483647 end
    return RNG.s
end
local function Rand()
    RNG.s = (RNG.s * 16807) % 2147483647
    return (RNG.s - 1) / 2147483646
end
local function Mix(x)
    RNG.s = ((RNG.s + math.floor(x)) % 2147483646) + 1
    for _ = 1, 6 do RNG.s = (RNG.s * 16807) % 2147483647 end
end
local function Between(a, b) return a + (b - a) * Rand() end

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
local function InAir(u)
    local ok, a = pcall(u.inAir, u)
    return ok and a == true
end
local function DistNm(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz) / 1852
end
local function GsKt(u)
    local ok, v = pcall(u.getVelocity, u)
    if not ok or type(v) ~= "table" then return 0 end
    return math.sqrt(v.x * v.x + v.z * v.z) * 1.94384
end
local function RelSpeed(u)
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
local function Carrier()
    local c = Unit.getByName(CFG.CARRIER_UNIT)
    if c and c:isExist() then return c end
end
local fieldCache = {}
local function FieldPos(key)
    if fieldCache[key] then return fieldCache[key] end
    local f = CFG.FIELDS[key]
    if not (f and coord and coord.LLtoLO) then return nil end
    local ok, v = pcall(coord.LLtoLO, f.lat, f.lon, 0)
    if ok and v then fieldCache[key] = v; return v end
end

-- ── radio state of the other modules (read only) ──
local function RadioBusy()
    local cv = TRT.CV
    if cv and (cv.busy or (cv.q and #cv.q > 0)) then return "CV" end
    local cd = TRT.CD
    if cd and (cd.qPlaying or (cd.queue and #cd.queue > 0) or (cd.chat and #cd.chat > 0)
               or cd.awaiting) then return "CD" end
    local jc = TRT.JC
    if jc and jc.qBusy then return "JC" end
    local fa = TRT.FA
    if fa and fa.active and (fa.qPlaying or fa.busy) then return "FA" end
    local ab = TRT.Airboss
    if ab and ((type(ab.RQLSO) == "table" and #ab.RQLSO > 0)
               or (type(ab.RQMarshal) == "table" and #ab.RQMarshal > 0)) then return "AIRBOSS" end
    return nil
end

--- JTAC_Controller workload: reason or nil.
local function JcBusy()
    local jc = TRT.JC
    if not (jc and jc.active and type(jc.st) == "table") then return nil end
    for k, st in pairs(jc.st) do
        local ph = st.phase
        if CFG.JC_SILENT[ph] then return "JC " .. tostring(k) .. " " .. ph end
        if ph == "ATTACK" and type(st.att) == "table" then
            local a = st.att
            if a.ipIn and not a.released then return "JC " .. tostring(k) .. " attack" end
            if a.released and a.offPending then return "JC " .. tostring(k) .. " off pending" end
        end
    end
    return nil
end

local function JcActive() local jc = TRT.JC; return jc and jc.active end

-- ── clips: variant groups and bags ──
local GROUPS = {}
for id in pairs(CFG.AUDIO) do
    local g = string.match(id, "^(.-)_%d+$")
    if g then GROUPS[g] = GROUPS[g] or {}; table.insert(GROUPS[g], id) end
end
for _, l in pairs(GROUPS) do table.sort(l) end
local function HasGroup(g) return GROUPS[g] ~= nil end

--- Pick a variant of group g (shuffle bag, no immediate repeat). nil if the group has no clips.
local function G(g)
    local all = GROUPS[g]
    if not all then return nil end
    local bag = PB.bags[g]
    if not bag or #bag == 0 then
        bag = {}
        for i, id in ipairs(all) do bag[i] = id end
        for i = #bag, 2, -1 do
            local j = math.floor(Rand() * i) + 1
            bag[i], bag[j] = bag[j], bag[i]
        end
        if #bag > 1 and bag[#bag] == PB.lastId[g] then bag[1], bag[#bag] = bag[#bag], bag[1] end
        PB.bags[g] = bag
    end
    local id = table.remove(bag)
    PB.lastId[g] = id
    return id
end

local function Clip(id) if id and CFG.AUDIO[id] then return id end return nil end
local function Round(x) return math.floor(x + 0.5) end

-- value clips (ids as written by tools/pilot_banter/make_pb_values.py)
local function VFuel(lb) if not lb then return nil end local t = Round(lb / 100); if t < 0 or t > 200 then return nil end return Clip("v_fuel_" .. t) end
local function VKft(ft) if not ft then return nil end local n = Round(ft / 1000); if n < 1 or n > 50 then return nil end return Clip("v_kft_" .. n) end
local function VNm(nm)
    if not nm or nm < 0.5 then return nil end
    local n = Round(nm)
    if n >= 100 then n = Round(nm / 10) * 10 end
    if n > 400 then return nil end
    return Clip("v_nm_" .. n)
end
local function VMin(m) if not m or m < 0.5 then return nil end local n = Round(m); if n > 60 then return nil end return Clip("v_min_" .. n) end
local function VTiming(dm)            -- dm < 0 early, > 0 late (minutes)
    if not dm then return nil end
    local n = Round(math.abs(dm))
    if n == 0 then return Clip("v_ontime") end
    if n > 30 then return nil end
    return Clip((dm < 0 and "v_early_" or "v_late_") .. n)
end
local function VPct(p) if not p then return nil end local n = Round(p); if n < 50 or n > 110 then return nil end return Clip("v_pct_" .. n) end
local function VRate(r) if not r then return nil end local n = Round(r / 10) * 10; if n < 60 or n > 400 then return nil end return Clip("v_rate_" .. n) end
local function VStores(n) if not n or n < 0 or n > 8 then return nil end return Clip("v_stores_" .. n) end
local function VCode(c) if not c then return nil end return Clip("v_code_" .. tostring(c)) end

-- line builder: nil entries are skipped; Pair adds header + value only when both exist
local function Seq()
    local s = { n = 0 }
    function s:add(id) if id then self.n = self.n + 1; self[self.n] = id end return self end
    function s:pair(h, v) if h and v then self:add(h); self:add(v) end return self end
    function s:list() local l = {} for i = 1, self.n do l[i] = self[i] end return l end
    return s
end

-- ── cockpit read (export environment) ──
local EXPORT_CODE = [[
local d = GetDevice and GetDevice(0)
if not d then return "nodev" end
local out = {}
for _, n in ipairs({ARGS}) do
  local ok, v = pcall(function() return d:get_argument_value(n) end)
  out[#out + 1] = n .. "=" .. ((ok and type(v) == "number") and string.format("%.3f", v) or "x")
end
local e = LoGetEngineInfo and LoGetEngineInfo()
if e and e.RPM then
  out[#out + 1] = string.format("rpmL=%.1f", e.RPM.left or -1)
  out[#out + 1] = string.format("rpmR=%.1f", e.RPM.right or -1)
end
local okI, ind = pcall(function() return list_indication and list_indication(5) end)
if okI and type(ind) == "string" then
  local b = ind:match("txt_BINGO\n([^\n]*)")
  if b then out[#out + 1] = "bingo=" .. b:gsub("%s", "") end
end
return table.concat(out, ";")
]]
EXPORT_CODE = EXPORT_CODE:gsub("{ARGS}", "{" .. table.concat(CK_ARGS, ",") .. "}")

local CK = { avail = nil, fails = 0, t = -99, v = nil, marmInvert = false }

local function CkInterpret(raw)
    local v = { raw = raw }
    local function num(a) local x = raw[a]; if type(x) == "number" then return x end return nil end
    local m = num(CK_MAP.marm.arg)
    if m and CK_MAP.marm.trust then v.marm = (m > 0.5) ~= CK.marmInvert end
    local ag = num(CK_MAP.agLt.arg); if ag and CK_MAP.agLt.trust then v.agLt = ag > 0.5 end
    local l = num(CK_MAP.ltd.arg); if l and CK_MAP.ltd.trust then v.ltd = l > 0.5 end
    local r = num(CK_MAP.radar.arg)
    if r and CK_MAP.radar.trust then v.radar = (r < 0.05 and "off") or (r < 0.15 and "stby") or (r < 0.25 and "opr") or "emerg" end
    local d = num(CK_MAP.disp.arg)
    if d and CK_MAP.disp.trust then v.disp = (d < 0.05 and "bypass") or (d < 0.15 and "on") or "off" end
    local c = num(CK_MAP.caut.arg); if c and CK_MAP.caut.trust then v.caution = c > 0.5 end
    if type(raw.rpmL) == "number" and raw.rpmL >= 0 then v.rpmL = raw.rpmL end
    if type(raw.rpmR) == "number" and raw.rpmR >= 0 then v.rpmR = raw.rpmR end
    local b = tonumber(raw.bingo)
    if b and b >= 500 and b <= 20000 then v.bug = b end
    return v
end

local function CkRaw(v)
    if not v then return "n/a" end
    local t = {}
    for _, a in ipairs(CK_ARGS) do t[#t + 1] = a .. "=" .. tostring(v.raw[a]) end
    t[#t + 1] = "rpm=" .. tostring(v.raw.rpmL) .. "/" .. tostring(v.raw.rpmR)
    t[#t + 1] = "bingo=" .. tostring(v.raw.bingo)
    return table.concat(t, " ")
end

--- Cockpit state or nil (cached CK_CACHE s; OFF after 3 failed reads).
local function Cockpit()
    if CK.avail == false then return nil end
    if now() - CK.t < 1.5 then return CK.v end
    CK.t = now()
    local ok, res = pcall(function()
        if type(net) ~= "table" or type(net.dostring_in) ~= "function" then error("net.dostring_in not available") end
        return net.dostring_in("export", EXPORT_CODE)
    end)
    if ok and type(res) == "string" and string.find(res, "49=", 1, true) then
        local raw = {}
        for k, val in string.gmatch(res, "([%w]+)=([^;]*)") do
            local n, x = tonumber(k), tonumber(val)
            if n then raw[n] = x else raw[k] = x or val end
        end
        if CK.avail ~= true then CK.avail = true; Log("cockpit read: available | " .. res) end
        CK.v = CkInterpret(raw)
        return CK.v
    end
    CK.v = nil
    if ok and res == "nodev" then                 -- export state reachable, no cockpit yet (not in the jet)
        if not CK.noDevLogged then CK.noDevLogged = true; Log("cockpit read: no cockpit device yet, will retry") end
        return nil
    end
    CK.fails = CK.fails + 1
    Log(string.format("cockpit read failed (%d): %s", CK.fails, tostring(res)))
    if CK.fails >= 3 then CK.avail = false; Log("cockpit read OFF: checks use mission data only") end
    CK.v = nil
    return nil
end

-- ── fuel / plan helpers ──
local function FuelLb(u)
    local okF, f = pcall(u.getFuel, u)
    if not okF or not f then return nil end
    local ok, d = pcall(u.getDesc, u)
    local maxKg = ok and d and d.fuelMassMax or nil
    if not maxKg then return f * 10860 end
    return f * maxKg * 2.2046226218
end
local function Thresh(u)
    local tl = TRT.TL
    if not (tl and type(tl.thresholds) == "function") then return nil end
    local ok, th = pcall(tl.thresholds, u:getPoint(), TRT.CD, nil)
    if ok and type(th) == "table" then return th end
    return nil
end
local function Credit()
    local tl = TRT.TL
    if tl and type(tl.credit) == "table" then return (tl.credit.threat or 0) + (tl.credit.fail or 0) end
    return 0
end
local function KnownFailure()
    local tl = TRT.TL
    if tl and type(tl.fails) == "table" then
        for _, f in ipairs(tl.fails) do if f.done then return true end end
    end
    return false
end
local function BurnRate(lb)        -- lb/min over BURN_WIN_S, nil if refuelled or too short
    local H = PB.w.fuelHist
    if #H < 2 then return nil end
    local old = H[1]
    local dt = now() - old.t
    if dt < CFG.BURN_WIN_S * 0.6 then return nil end
    for i = 2, #H do if H[i].lb > H[i - 1].lb + 50 then return nil end end
    local r = (old.lb - lb) / (dt / 60)
    if r <= 0 then return nil end
    return r
end

local function Tanker()
    local u, best, bd = Hero(), nil, nil
    if not u then return nil end
    local p = u:getPoint()
    for _, n in ipairs(CFG.TANKER_UNITS) do
        local k = Unit.getByName(n)
        if k and k:isExist() then
            local d = DistNm(p, k:getPoint())
            if not bd or d < bd then best, bd = k, d end
        end
    end
    return best, bd
end

-- ── time of day / surface ──
local function TimeOfDay(u)
    local lat, lon = 35.5, 35.5
    local okP, p = pcall(u.getPoint, u)
    if okP and p and coord and coord.LOtoLL then
        local ok2, la, lo = pcall(coord.LOtoLL, p)
        if ok2 and la and lo then lat, lon = la, lo end
    end
    local doy = 300
    local d = env.mission and env.mission.date
    if type(d) == "table" and d.Month and d.Day then
        local cum = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }
        doy = (cum[d.Month] or 273) + d.Day
    end
    local hUtc = (timer.getAbsTime() % 86400) / 3600 - CFG.UTC_OFFSET
    local decl = math.rad(23.44) * math.sin(2 * math.pi * (284 + doy) / 365)
    local ha = math.rad(15 * (hUtc + lon / 15 - 12))
    local la = math.rad(lat)
    local s = math.sin(la) * math.sin(decl) + math.cos(la) * math.cos(decl) * math.cos(ha)
    local el = math.deg(math.asin(math.max(-1, math.min(1, s))))
    return (el > 6 and "day") or (el > -6 and "twilight") or "night", el
end
local function Surface(u)
    local cd = TRT.CD
    if cd and cd.surf then return (cd.surf == "WATER") and "sea" or "land" end
    local p = u:getPoint()
    local ok, st = pcall(land.getSurfaceType, { x = p.x, y = p.z })
    if ok and (st == land.SurfaceType.WATER or st == land.SurfaceType.SHALLOW_WATER) then return "sea" end
    return "land"
end

-- ── builders: return a list of clip ids / pauses, or nil (nothing to say) ──
local B = {}

local function FuelComment(lb, th)
    if not th then return nil end
    if th.zone == "STATION" then
        if lb < th.bingo then return "cmt_fuel_below_bingo" end
        if lb < th.joker then return "cmt_fuel_past_joker" end
        if lb < th.joker + 600 then return "cmt_fuel_near_joker" end
        if lb < th.joker + 2500 then return "cmt_fuel_ok" end
        return "cmt_fuel_plenty"
    elseif th.zone == "RECOVERY" and th.tank then
        if lb < th.bingo then return "cmt_fuel_below_bingo" end
        if lb < th.tank then return "cmt_fuel_below_tank" end
        if lb < th.tank + 600 then return "cmt_fuel_near_tank" end
        return "cmt_fuel_ok"
    else
        if lb < th.bingo then return "cmt_fuel_below_bingo" end
        if lb < th.bingo + 800 then return "cmt_fuel_near_bingo" end
        if lb < th.bingo + 3000 then return "cmt_fuel_ok" end
        return "cmt_fuel_plenty"
    end
end

--- "Fuel..." <state> [<ref>... <value>] <comment> [burn]
local function FuelSeq(s, u, opts)
    opts = opts or {}
    local lb = FuelLb(u)
    local v = VFuel(lb)
    if not v then return false end                  -- no state, no comparison
    s:add(G("fuel_h")):add(v)
    local th = Thresh(u)
    if th then
        if th.zone == "STATION" and th.joker and lb >= th.joker then s:pair(G("joker_is"), VFuel(th.joker))
        elseif th.zone == "RECOVERY" and th.tank and lb >= th.tank then s:pair(G("tank_is"), VFuel(th.tank))
        else s:pair(G("bingo_is"), VFuel(th.bingo)) end
        if not opts.noComment then s:add(G(FuelComment(lb, th))) end
    end
    if opts.burn then s:pair(G("burn_h"), VRate(BurnRate(lb))) end
    return true
end

B.fuel = function(u)
    local s = Seq()
    if not FuelSeq(s, u, { burn = Rand() < 0.35 }) then return nil end
    local ck = (Rand() < 0.2) and Cockpit() or nil
    local th = ck and ck.bug and Thresh(u)
    if th and th.bingo then
        s:pair(G("bug_h"), VFuel(ck.bug))
        s:add(G(math.abs(ck.bug - th.bingo) > 300 and "bug_off" or "bug_ok"))
    end
    return s:list()
end

B.nav = function(u)
    local cd, tl, cv = TRT.CD, TRT.TL, TRT.CV
    local p, gs = u:getPoint(), GsKt(u)
    if gs < 150 then return nil end
    local s = Seq()
    local ph = cd and cd.phase
    -- tanker rendezvous open
    if (cd and cd.tk) or ph == "REFUEL" then
        local k, d = Tanker()
        if k and d and d > 3 then
            s:add(G("tanker_h")):add(VNm(d)):add(VMin(d / gs * 60))
            return (s.n >= 2) and s:list() or nil
        end
    end
    -- outbound to CP Tiger: distance, ETE, early / late against the ATO
    if ph and CFG.OUTBOUND_CD[ph] and tl and tl.ato and tl.ato.cpPos and not tl.cpReached and cd.ar1Done ~= false then
        local d = DistNm(p, tl.ato.cpPos)
        if d < 3 then return nil end
        local ete = d / gs * 60
        s:add(G("cp_h")):add(VNm(d)):add(VMin(ete))
        if tl.ato.CP then
            local dm = ((now() + ete * 60) - (tl.ato.CP + Credit())) / 60
            local tv = VTiming(dm)
            if tv then
                s:add(tv)
                if Rand() < 0.5 then
                    s:add(G((dm < -1.5 and "cmt_time_early") or (dm > 1.5 and "cmt_time_late") or "cmt_time_ok"))
                end
            end
        end
        return (s.n >= 2) and s:list() or nil
    end
    -- divert field
    local dv = cd and cd.divert
    if ph == "DIVERT" and dv and dv.field and CFG.FIELDS[dv.field] then
        local fp = FieldPos(dv.field)
        if fp then
            local d = DistNm(p, fp)
            s:add(G(CFG.FIELDS[dv.field].grp)):add(VNm(d)):add(VMin(d / gs * 60))
            return (s.n >= 2) and s:list() or nil
        end
    end
    -- inbound / holding: Mother, push time
    local c = Carrier()
    if c and ((ph and CFG.INBOUND_CD[ph]) or ph == "RECOVERY") then
        local d = DistNm(p, c:getPoint())
        if d > 5 then s:add(G("mother_h")):add(VNm(d)) end
        if cv and cv.phase ~= "HOLDING" and d > 5 then s:add(VMin(d / gs * 60)) end
        local eat = cv and cv.clr and cv.clr.eatAbs
        if eat then s:pair(G("push_h"), VMin((eat - timer.getAbsTime()) / 60)) end
        return (s.n >= 2) and s:list() or nil
    end
    return nil
end

B.alt = function(u)
    local ok, v = pcall(u.getVelocity, u)
    if not ok or not v or math.abs(v.y) > 1.5 then return nil end
    local ft = u:getPoint().y * 3.28084
    if ft < 3000 then return nil end
    local s = Seq():pair(G("level_h"), VKft(ft))
    if s.n == 0 then return nil end
    if Rand() < 0.5 then s:add(G("cmt_alt")) end
    return s:list()
end

B.sys = function(u)
    local s = Seq():add(G("sys_h"))
    local ck = Cockpit()
    if ck then
        Log("cockpit (sys) " .. CkRaw(ck))
        if ck.rpmL and ck.rpmR then
            if math.abs(ck.rpmL - ck.rpmR) < 2 then s:pair(G("eng_both"), VPct((ck.rpmL + ck.rpmR) / 2))
            else s:pair(G("eng_left"), VPct(ck.rpmL)):pair(G("eng_right"), VPct(ck.rpmR)) end
        end
        if ck.caution then s:add(G("caution_lit")); return s:list() end
    elseif KnownFailure() then
        return nil                                   -- do not claim "all normal" after an ME failure
    end
    local pool = { "eng_ok", "hyd_ok", "elec_ok", "oxy_ok" }
    s:add(G(pool[math.floor(Rand() * #pool) + 1]))
    if ck and ck.caution == false then s:add(G("caution_none")) elseif Rand() < 0.5 then s:add(G("sys_done")) end
    return s:list()
end

B.vul = function(u)
    local tl = TRT.TL
    if not (tl and tl.ato and tl.ato.VUL) then return nil end
    local rem = (tl.ato.VUL + Credit() - now()) / 60
    local s = Seq()
    if rem >= 1 then s:pair(G("vul_h"), VMin(rem)) else s:add(G("vul_past")) end
    if s.n == 0 then return nil end
    return s:list()
end

B.muse = function(u)
    if Rand() < 0.5 then
        local tod = TimeOfDay(u)
        local g = (tod == "day") and ("muse_day_" .. Surface(u)) or ("muse_" .. tod)
        if HasGroup(g) and Rand() < 0.75 then return { G(g) } end
        if HasGroup("cruise") then return { G("cruise") } end
    end
    if HasGroup("muse_life") then return { G("muse_life") } end
    return nil
end

B.noise = function()
    if CFG.NOISE_SYNTH and HasGroup("snd") and Rand() < 0.4 then return { G("snd") } end
    if HasGroup("noise") then return { G("noise") } end
    return nil
end

local function JcCode(key)
    local jc = TRT.JC
    local js = jc and jc.CFG and jc.CFG.JTACS
    if type(js) ~= "table" then return nil end
    if key and js[key] and js[key].mark then return js[key].mark.code end
    for _, j in pairs(js) do if j.mark and j.mark.code then return j.mark.code end end
end

local function CkWeapons(s, ck, withAg)
    if not ck then return end
    if ck.marm ~= nil then s:add(G(ck.marm and "marm_arm" or "marm_safe")) end
    if withAg and ck.agLt ~= nil then s:add(G(ck.agLt and "ag_mode" or "ag_not")) end
    if ck.ltd ~= nil then s:add(G(ck.ltd and "laser_arm" or "laser_safe")) end
end

B.fence_in = function(u)
    -- FENCE: fuel, emitters, (navigation), countermeasures, expendables; laser + code come in the attack check
    local s = Seq():add(G("fence_in_h"))
    local ck = Cockpit()
    if ck then
        Log("cockpit (fence in) " .. CkRaw(ck))
        if ck.marm ~= nil then s:add(G(ck.marm and "marm_arm" or "marm_safe")) end
        if ck.disp then s:add(G("disp_" .. ck.disp)) end
        if ck.radar and ck.radar ~= "emerg" and Rand() < 0.5 then s:add(G("radar_" .. ck.radar)) end
    end
    local tl = TRT.TL
    if tl and tl.ag and tl.ag > 0 then s:add(VStores(tl.ag)) end
    local lb = FuelLb(u)
    s:pair(G("fuel_h"), VFuel(lb))
    s:add(G("fenced_in"))
    return s:list()
end

B.attack_check = function(u, ctx)
    local jc = TRT.JC
    local st = jc and jc.st and ctx and jc.st[ctx.key]
    if st and type(st.att) == "table" and st.att.ipIn then return nil end    -- already inbound: too late
    local s = Seq():add(G("attack_h"))
    local ck = Cockpit()
    if ck then Log("cockpit (attack) " .. CkRaw(ck)); CkWeapons(s, ck, true) end
    s:pair(G("code_h"), VCode(JcCode(ctx and ctx.key)))
    s:add(G("attack_done"))
    if s.n < 3 then return nil end
    return s:list()
end

B.fence_out = function(u)
    local s = Seq():add(G("fence_out_h"))
    local ck = Cockpit()
    if ck then
        Log("cockpit (fence out) " .. CkRaw(ck))
        if ck.marm ~= nil then s:add(G(ck.marm and "marm_arm" or "marm_safe")) end
        if ck.ltd then s:add(G("laser_arm")) end         -- only a laser still armed is worth saying
    end
    local tl = TRT.TL
    if tl and tl.ag then s:add(VStores(tl.ag)) end
    FuelSeq(s, u, { noComment = true })
    s:add(G("fenced_out"))
    return s:list()
end

B.joker_call = function() return { G("joker_call") } end
B.bingo_call = function() return { G("bingo_call") } end
B.tank_call  = function() return { G("tank_call") } end

local function ProbeOut(u) local v = Arg(u, CFG.PROBE_ARG); return v and v >= 0.9 end
local function ProbeIn(u) local v = Arg(u, CFG.PROBE_ARG); return v and v <= 0.1 end

B.aar_check = function(u)
    local s = Seq():add(G("aar_h"))
    s:add(G(ProbeOut(u) and "probe_out" or "probe_still_in"))
    local ck = Cockpit()
    if ck then
        Log("cockpit (tanker) " .. CkRaw(ck))
        if ck.marm ~= nil then s:add(G(ck.marm and "marm_arm" or "marm_safe")) end
        if ck.radar and ck.radar ~= "emerg" then s:add(G("radar_" .. ck.radar)) end
    end
    return s:list()
end
B.aar_closure = function() return { G("aar_closure") } end
B.aar_steady  = function() return { G("aar_steady") } end
B.aar_taking  = function(u) local s = Seq():pair(G("aar_taking"), VFuel(FuelLb(u))); return (s.n > 0) and s:list() or nil end
B.aar_disc    = function(u) local s = Seq():pair(G("disc_h"), VFuel(FuelLb(u))); return (s.n > 0) and s:list() or nil end
B.aar_post = function(u)
    local s = Seq():add(G("post_aar_h"))
    s:add(G(ProbeIn(u) and "probe_in" or "probe_still_out"))
    FuelSeq(s, u, { noComment = true })
    if Rand() < 0.5 then s:add(G("tanker_done")) end
    return s:list()
end

local function HookDown(u) local v = Arg(u, CFG.HOOK_ARG); return v and v > 0.6 end

B.hold_check = function(u)
    local s = Seq():add(G("hold_h"))
    s:pair(G("fuel_h"), VFuel(FuelLb(u)))
    local cv = TRT.CV
    local eat = cv and cv.clr and cv.clr.eatAbs
    if eat then s:pair(G("push_h"), VMin((eat - timer.getAbsTime()) / 60)) end
    return s:list()
end
B.commence_check = function(u)
    local s = Seq():add(G("commence_h"))
    s:add(G(HookDown(u) and "hook_down" or "hook_up_warn"))
    FuelSeq(s, u, {})
    return s:list()
end
B.approach_check = function(u)
    local s = Seq():add(G("approach_h"))
    s:add(G(HookDown(u) and "hook_down" or "hook_up_warn"))
    FuelSeq(s, u, { noComment = true })
    return s:list()
end
B.landing_check = function(u, ctx)
    local s = Seq():add(G("landing_h"))
    local down = true
    for _, a in ipairs(CFG.GEAR_ARGS) do local v = Arg(u, a); if not v or v < 0.9 then down = false end end
    s:add(G(down and "wheels_down" or "wheels_not"))
    local fl = Arg(u, CFG.FLAPS_ARG)
    if fl then s:add(G(fl > CFG.FLAPS_DOWN and "flaps_down" or "flaps_up")) end
    if ctx and ctx.field then
        s:add(G(HookDown(u) and "hook_down" or "hook_up_field"))
    else
        s:add(G(HookDown(u) and "hook_down" or "hook_up_warn"))
    end
    s:add(G("harness")):add(G("landing_done"))
    Log(string.format("landing check: gear %s flaps %s hook %s (%s)", tostring(down), tostring(fl),
        tostring(Arg(u, CFG.HOOK_ARG)), (ctx and ctx.field) and "field" or "carrier"))
    return s:list()
end
B.divert_check = function(u)
    local cd = TRT.CD
    local dv = cd and cd.divert
    if not (dv and dv.field and CFG.FIELDS[dv.field]) then return nil end
    local s = Seq():add(G("divert_h"))
    local fp = FieldPos(dv.field)
    if fp then s:pair(G(CFG.FIELDS[dv.field].grp), VNm(DistNm(u:getPoint(), fp))) end
    FuelSeq(s, u, { noComment = true })
    return s:list()
end

--- Cruise item: chosen when the line is due (ctx.kind = transit | station | hold)
B.cruise_item = function(u, ctx)
    local kind = ctx and ctx.kind or "transit"
    local lv = CFG.LEVELS[PB.level] or CFG.LEVELS.NORMAL
    local r = Rand()
    local order
    if r < CFG.NOISE_P then order = { "noise", "check", "muse" }
    elseif r < CFG.NOISE_P + lv.muse and kind ~= "station" then order = { "muse", "check", "noise" }
    else order = { "check", "muse", "noise" } end
    for _, cat in ipairs(order) do
        if cat == "noise" then
            local l = B.noise(); if l then ctx.item = "noise"; return l end
        elseif cat == "muse" and kind ~= "station" then
            local l = B.muse(u); if l then ctx.item = "muse"; return l end
        elseif cat == "check" then
            local cand, tot = {}, 0
            for name, it in pairs(CFG.ITEMS) do
                if it.ctx[kind] and now() - (PB.lastItem[name] or -1e9) >= it.cd then
                    cand[#cand + 1] = name; tot = tot + it.w
                end
            end
            table.sort(cand)
            while #cand > 0 do
                local x, pick = Rand() * tot, #cand
                for i, name in ipairs(cand) do
                    x = x - CFG.ITEMS[name].w
                    if x <= 0 then pick = i; break end
                end
                local name = cand[pick]
                local l = B[name](u)
                if l then PB.lastItem[name] = now(); ctx.item = name; return l end
                tot = tot - CFG.ITEMS[name].w
                table.remove(cand, pick)
            end
        end
    end
    return nil
end

-- ── play: chain the clips of a line, cut the rest if a radio call starts ──
local function LineText(ids)
    local t = {}
    for _, id in ipairs(ids) do
        if type(id) == "string" then t[#t + 1] = (CFG.AUDIO[id] and CFG.AUDIO[id].text) or id end
    end
    return table.concat(t, " | ")
end

local function SndOut(gid, id)
    local file = CFG.SND_DIR .. id .. ".ogg"
    local ok, err
    if gid then ok, err = pcall(trigger.action.outSoundForGroup, gid, file)
    else ok, err = pcall(trigger.action.outSoundForCoalition, coalition.side.BLUE, file) end
    if not ok then Log("play error " .. id .. ": " .. tostring(err)) end
    return ok
end

local function Play(segs, name, why, resumed)
    PB.resumed = resumed
    local u = Hero()
    if not (u and segs and #segs > 0) then return false end
    for _, id in ipairs(segs) do
        if type(id) == "string" and not CFG.AUDIO[id] then Log(name .. ": missing clip " .. id); return false end
    end
    local okG, gid = pcall(function() return u:getGroup():getID() end)
    if not okG then gid = nil end
    PB.gen = PB.gen + 1
    local gen, t0, at = PB.gen, now(), 0
    local first = true
    for i, id in ipairs(segs) do
        if type(id) == "number" then
            at = at + id
        else
            if first then
                SndOut(gid, id); first = false
            else
                local myAt, myId, idx = at, id, i
                timer.scheduleFunction(function()
                    if PB.gen ~= gen then return nil end
                    local r = RadioBusy()
                    if r then
                        PB.gen = PB.gen + 1                       -- cancels the remaining clips
                        PB.busyUntil = now() + CFG.TAIL
                        if PB.playing then PB.playing.t1 = now() end
                        Log(string.format("cut %s at clip %d/%d (%s)", name, idx, #segs, r))
                        local m = CFG.MOMENTS[name]
                        if m and m.prio and not PB.resumed then        -- a check resumes after the call
                            local rest = {}
                            for j = idx, #segs do rest[#rest + 1] = segs[j] end
                            PB.resume = { segs = rest, name = name, t0 = now() }
                        end
                        return nil
                    end
                    SndOut(gid, myId)
                    return nil
                end, nil, t0 + myAt)
            end
            at = at + CFG.AUDIO[id].len + CFG.SEG_GAP
        end
    end
    PB.lastPlay[name], PB.lastLine = t0, t0
    PB.busyUntil = t0 + at + CFG.TAIL
    if name ~= "cruise_item" and PB.nextCruise and PB.nextCruise < t0 + at + 45 then
        PB.nextCruise = t0 + at + 45                   -- an event line pushes the next cruise item back
    end
    PB.lines = PB.lines + 1
    PB.playing = { name = name, t1 = t0 + at, overlap = false }
    local lv = CFG.LEVELS[PB.level]
    Log(string.format("say %s (%.1f s, %d/%s) \"%s\" [%s]", name, at, PB.lines, lv and tostring(lv.max) or "-",
        LineText(segs), why or "-"))
    if CFG.SUBTITLE and gid then
        trigger.action.outTextForGroup(gid, "(to himself) " .. LineText(segs), CFG.SUB_DUR, false)
    end
    return true
end

-- reason this moment may not start now, nil = clear
local function Blocked(name)
    local m = CFG.MOMENTS[name]
    local t = now()
    if not PB.on then return "off" end
    local lv = CFG.LEVELS[PB.level]
    if not m.prio and lv and PB.lines >= lv.max then return "max lines" end
    if t < PB.busyUntil then return "own line" end
    local r = RadioBusy()
    if r then return "radio " .. r end
    if m.quiet and t - PB.lastRadio < CFG.RADIO_QUIET_S then return "radio recent" end
    if t - PB.lastLine < (m.gap or CFG.MIN_GAP) then return "gap" end
    if not m.any then
        local cv = TRT.CV
        if cv and cv.phase and CFG.SILENT_CV[cv.phase] and not (m.cvok and m.cvok[cv.phase]) then
            return "CV " .. cv.phase
        end
        local tl = TRT.TL
        if tl and tl.engaged then return "engaged" end
        if not m.jtac then
            if JcActive() then
                local j = JcBusy(); if j then return j end
            else
                local cd = TRT.CD
                if cd and cd.phase and CFG.SILENT_CD[cd.phase] then return "CD " .. cd.phase end
            end
        end
        if not m.aar then
            local S = TRT.AAR and TRT.AAR.session
            if S and (CFG.AAR_CLOSE[S.phase] or S.openStart) then return "AAR " .. tostring(S.phase) end
        end
    end
    local cdr = TRT.CD
    if name == "weapon_away" and cdr and cdr.relCallUntil and t < cdr.relCallUntil then return "CD release call" end
    return nil
end

--- Event -> pending line (probability and cooldown decided here).
local function Fire(name, why, ctx, force)
    local m = CFG.MOMENTS[name]
    if not m then Log("unknown moment " .. tostring(name)); return end
    if not PB.on then return end
    local t = now()
    Mix(t * 1000)
    if not force and PB.lastPlay[name] and t - PB.lastPlay[name] < (m.cd or 0) then
        Log(string.format("%s: cooldown (%s)", name, why or "-")); return
    end
    for _, it in ipairs(PB.pending) do if it.name == name then return end end
    if not B[name] and not HasGroup(name) then Log(name .. ": no clips (" .. (why or "-") .. ")"); return end
    if not force then
        local roll = Rand()
        if roll >= m.p then
            Log(string.format("%s: silent by roll %.2f >= %.2f (%s)", name, roll, m.p, why or "-")); return
        end
    end
    PB.pending[#PB.pending + 1] = { name = name, why = why, t0 = t, ctx = ctx or {} }
end

local function ServePending()
    local t = now()
    local R = PB.resume
    if R then
        if t - R.t0 > CFG.RESUME_TTL then
            PB.resume = nil; Log("resume " .. R.name .. ": dropped")
        elseif t >= PB.busyUntil and not RadioBusy() and t - PB.lastRadio >= CFG.RESUME_QUIET_S then
            PB.resume = nil
            Play(R.segs, R.name, "resumed after the radio", true)
            return
        else
            return                                       -- nothing new before the check is finished
        end
    end
    local i = 1
    while i <= #PB.pending do
        local it = PB.pending[i]
        local m = CFG.MOMENTS[it.name]
        local due = it.t0 + m.delay
        if t >= due then
            local r = Blocked(it.name)
            if not r then
                table.remove(PB.pending, i)
                local u = Hero()
                local segs
                if u then
                    local build = B[it.name]
                    if build then
                        local ok, res = pcall(build, u, it.ctx)
                        if ok then segs = res else Log(it.name .. " builder error: " .. tostring(res)) end
                    else
                        segs = { G(it.name) }
                    end
                end
                if segs and #segs > 0 then
                    local why = it.why
                    if it.ctx and it.ctx.item then why = (why or "") .. " / " .. it.ctx.item end
                    Play(segs, it.name, why)
                else
                    Log(it.name .. ": nothing to say (" .. (it.why or "-") .. ")")
                end
                return
            elseif t > due + m.ttl then
                table.remove(PB.pending, i)
                Log(string.format("%s: dropped after %.0f s, last reason: %s", it.name, t - it.t0, r))
            else
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
        if r then p.overlap = true; Log("overlap: " .. r .. " started during " .. p.name) end
    end
end

-- ── cruise scheduler ──
local function CruiseKind(u, air)
    if not air then return nil end
    local tl = TRT.TL
    if tl and tl.engaged then return nil end
    local cv = TRT.CV
    if cv and cv.phase == "HOLDING" then return "hold" end
    local cd = TRT.CD
    local ph = cd and cd.phase
    if ph and CFG.CRUISE_CD[ph] then return "transit" end
    if ph and CFG.STATION_CD[ph] then
        if now() - (PB.lastJcBusy or -1e9) < CFG.JC_QUIET_S then return nil end
        return "station"
    end
    if not cd then return "transit" end
    return nil
end

local function Cruise(u, air)
    local kind = CruiseKind(u, air)
    local lv = CFG.LEVELS[PB.level]
    if not (kind and lv and PB.on) then PB.nextCruise = nil; return end
    local t = now()
    if not PB.nextCruise then PB.nextCruise = t + Between(20, 40); return end
    if t < PB.nextCruise then return end
    for _, it in ipairs(PB.pending) do if it.name == "cruise_item" then return end end
    if t < PB.busyUntil or t - PB.lastLine < CFG.MIN_GAP then return end
    PB.nextCruise = t + Between(lv.cruise[1], lv.cruise[2])
    Fire("cruise_item", "cruise " .. kind, { kind = kind })
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
    if (name == "trap_good" or name == "trap_fair" or name == "trap_poor") and not pd.landed and not grade.wire then
        name = nil
    end
    Log(string.format("LSO grade %s wire %s landed %s -> %s", g, tostring(grade.wire), tostring(pd.landed), tostring(name)))
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

-- ── JTAC_Controller events ──
local function HookJC()
    if PB.jcHooked then return end
    local jc = TRT.JC
    if not (jc and type(jc.on) == "function") then return end
    jc.on(function(ev, data)
        if ev == "READBACK" and type(data) == "table" and data.wrong == 0 then
            Fire("attack_check", "JC readback correct " .. tostring(data.key), { key = data.key })
        end
    end)
    PB.jcHooked = true
    Log("JTAC_Controller events subscribed")
end

-- ── F10 ──
local function SetLevel(l)
    PB.level, PB.on = l, l ~= "OFF"
    if not PB.on then PB.pending = {}; PB.gen = PB.gen + 1 end
    PB.nextCruise = nil
    Log("level -> " .. l)
    if TRT.Menu and TRT.Menu.Msg then TRT.Menu.Msg("Pilot thoughts: " .. l, 5) end
end
local function MenuItems()
    local sub = {}
    for _, l in ipairs(CFG.LEVEL_ORDER) do
        local lab = l:sub(1, 1) .. l:sub(2):lower()
        if l == PB.level then lab = lab .. " (current)" end
        sub[#sub + 1] = { lab, function() SetLevel(l) end }
    end
    return { { "Pilot thoughts: " .. PB.level, sub = sub } }
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
            W.landingArmed, W.approachDone, W.fenceIn, W.fenceOut = true, false, false, false
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

local function WatchFuel(u, air)
    local W = PB.w
    if not air then W.fuelHist = {}; return end
    local H = W.fuelHist
    local t = now()
    if #H == 0 or t - H[#H].t >= 10 then
        local lb = FuelLb(u)
        if lb then H[#H + 1] = { t = t, lb = lb } end
        while #H > 0 and t - H[1].t > CFG.BURN_WIN_S do table.remove(H, 1) end
    end
    local tl = TRT.TL
    if not tl then return end
    local function edge(key, val, moment)
        if W[key] == nil then W[key] = val and true or false; return end
        if val and not W[key] then W[key] = true; Fire(moment, "TL " .. key) end
    end
    edge("joker", tl.joker, "joker_call")
    edge("bingo", tl.bingo or tl.bingoRtb or tl.bingoRec, "bingo_call")
    edge("tank", tl.tank, "tank_call")
end

local function WatchAAR(u, air)
    local W = PB.w
    local A = TRT.AAR
    if not (A and air) then return end
    local S = A.session
    if S then
        if W.aarN ~= S.n then
            W.aarN, W.aarJoin, W.aarAstern, W.aarClos, W.aarTakeT = S.n, false, false, false, nil
        end
        if S.phase == "JOIN" and not W.aarJoin then W.aarJoin = true; Fire("aar_check", "AAR S" .. S.n .. " JOIN") end
        if S.phase == "ASTERN" and not W.aarAstern then W.aarAstern = true; Fire("aar_steady", "AAR astern") end
        if S.openStart then
            if not W.aarTakeT then W.aarTakeT = now() - CFG.AAR_TAKING_S + 25 end
            if now() - W.aarTakeT >= CFG.AAR_TAKING_S then W.aarTakeT = now(); Fire("aar_taking", "AAR contact") end
        else
            W.aarTakeT = nil
        end
        if not W.aarClos and type(S.contacts) == "table" and #S.contacts == 0 and S.join then
            local k = Tanker()
            if k then
                local hp, kp = u:getPoint(), k:getPoint()
                local rx, ry, rz = hp.x - kp.x, hp.y - kp.y, hp.z - kp.z
                local r3 = math.sqrt(rx * rx + ry * ry + rz * rz)
                local okv, vh = pcall(u.getVelocity, u)
                local okk, vk = pcall(k.getVelocity, k)
                local okP, P = pcall(k.getPosition, k)
                if r3 > 1 and okv and okk and okP and vh and vk and P then
                    local clos = -((vh.x - vk.x) * rx + (vh.y - vk.y) * ry + (vh.z - vk.z) * rz) / r3 * 1.94384
                    local fwd = rx * P.x.x + rz * P.x.z
                    if r3 / 1852 <= CFG.AAR_CLOSURE_NM and fwd < 0 and clos > CFG.AAR_CLOSURE_KT then
                        W.aarClos = true
                        Fire("aar_closure", string.format("closure %.0f kt at %.2f NM", clos, r3 / 1852))
                    end
                end
            end
        end
    end
    local last = A.last
    if last ~= W.aarLast then
        local prev = W.aarLast
        W.aarLast = last
        if prev ~= nil or (last and last.contacts and last.contacts > 0) then
            if last and (last.contacts or 0) > 0 then W.aarPostT = now(); Fire("aar_post", "AAR session end") end
        end
    end
end

local function WatchCV(u, air)
    local W = PB.w
    local cv = TRT.CV
    if not (cv and air) then return end
    local ph = cv.phase
    if ph ~= W.cvPhase then
        local prev = W.cvPhase
        W.cvPhase = ph
        if prev then
            if ph == "HOLDING" then Fire("hold_check", "CV " .. prev .. " -> HOLDING") end
            if ph == "PENETRATION" then Fire("commence_check", "CV " .. prev .. " -> PENETRATION") end
        end
    end
    local c = Carrier()
    if c and not W.approachDone and (cv.case == 1 or cv.case == 2)
        and (ph == "ZIPLIP" or ph == "SEEYOU" or ph == "APP_SEEYOU") then
        local d = DistNm(u:getPoint(), c:getPoint())
        if d <= CFG.APPROACH_NM then
            W.approachDone = true
            Fire("approach_check", string.format("Case %d, %.1f NM", cv.case, d))
        end
    end
end

local function WatchGear(u, air)
    local W = PB.w
    if not air then W.gearDown, W.gearCand, W.gearN = nil, nil, 0; return end
    local down = true
    for _, a in ipairs(CFG.GEAR_ARGS) do local v = Arg(u, a); if not v or v < 0.9 then down = false end end
    if W.gearDown == nil then W.gearDown = down; return end
    if down == W.gearDown then W.gearCand, W.gearN = nil, 0; return end
    if down ~= W.gearCand then W.gearCand, W.gearN = down, 1 else W.gearN = W.gearN + 1 end
    if W.gearN < 2 then return end
    W.gearDown, W.gearCand, W.gearN = down, nil, 0
    Log("gear " .. (down and "DOWN" or "UP"))
    if not down then W.landingArmed = true; return end
    if not W.landingArmed then return end
    local fa = TRT.FA
    local c = Carrier()
    local dC = c and DistNm(u:getPoint(), c:getPoint()) or 1e9
    if fa and fa.active then
        W.landingArmed = false
        Fire("landing_check", "gear down, field arrival", { field = true })
    elseif dC <= CFG.LANDING_NM then
        W.landingArmed = false
        Fire("landing_check", string.format("gear down, carrier %.1f NM", dC))
    end
end

local function WatchModules(u, air)
    local W = PB.w
    local pc = TRT.PlaneCaptain
    local ms = pc and pc.milestones
    if ms then
        if ms.START and not W.pcStart then W.pcStart = ms.START; Fire("engines_on", "PlaneCaptain START") end
        if ms.CHECKS and not W.pcChecks then W.pcChecks = ms.CHECKS; Fire("checks_done", "PlaneCaptain CHECKS") end
    end
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
        local sp = cd.splashes or 0
        if W.splashes == nil then W.splashes = sp end
        if sp > W.splashes then W.splashes = sp; if air then Fire("cap_splash", "CAP splash") end end
        local rf = cd.refuelDone and true or false
        if W.refuel == nil then W.refuel = rf end
        if rf and not W.refuel then
            W.refuel = true
            if air and not TRT.AAR then Fire("tanker_done", "refuel complete") end   -- with AAR_Monitor: inside aar_post
        end
        -- fence in / out, divert
        local ph = cd.phase
        if ph ~= W.cdPhase then
            local prev = W.cdPhase
            W.cdPhase = ph
            if CFG.STATION_CD[ph] or ph == "J1_OFF" or ph == "J2_OFF" then
                if not W.fenceIn and air and prev then W.fenceIn = true; Fire("fence_in", "CD " .. tostring(prev) .. " -> " .. ph) end
                W.wasStation = true
            end
            if W.wasStation and not W.fenceOut and air
                and (CFG.FENCE_OUT_CD[ph] or (ph == "REFUEL" and cd.deadJ2)) then
                W.fenceOut = true
                Fire("fence_out", "CD " .. tostring(prev) .. " -> " .. tostring(ph))
            end
        end
        if air and not W.fenceIn and ph and CFG.OUTBOUND_CD[ph] and cd.ar1Done ~= false
            and tl and tl.ato and tl.ato.cpPos then
            local d = DistNm(u:getPoint(), tl.ato.cpPos)
            if d <= CFG.FENCE_IN_NM then W.fenceIn = true; Fire("fence_in", string.format("CP Tiger %.0f NM", d)) end
        end
        if cd.divert and not W.divert then W.divert = true; if air then Fire("divert_check", "divert " .. tostring(cd.divert.field)) end end
    end
    local md = TRT.MD
    if md then
        local d = md.defeated or 0
        if W.defeated == nil then W.defeated = d end
        if d > W.defeated then W.defeated = d; if air then Fire("missile_defeated", "MD defeated") end end
    end
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
        HookJC()
        if RadioBusy() then PB.lastRadio = now() end
        if JcBusy() then PB.lastJcBusy = now() end
        local u = Hero()
        if u then
            local air = InAir(u)
            WatchCanopy(u, air)
            WatchCatRearm(u, air)
            WatchAAR(u, air)
            WatchModules(u, air)
            WatchFuel(u, air)
            WatchCV(u, air)
            WatchGear(u, air)
            Cruise(u, air)
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
        W.landed, W.landingArmed, W.approachDone = true, true, false
        Log("hero landed")
    elseif e.id == world.event.S_EVENT_REFUELING then
        Fire("tanker_in", "S_EVENT_REFUELING")
    elseif e.id == world.event.S_EVENT_REFUELING_STOP then
        Fire("aar_disc", "S_EVENT_REFUELING_STOP")
    elseif e.id == world.event.S_EVENT_SHOT and e.weapon then
        local ok, d = pcall(e.weapon.getDesc, e.weapon)
        if ok and type(d) == "table" then
            local c = d.category
            local ag = (c == Weapon.Category.BOMB) or (c == Weapon.Category.ROCKET)
                or (c == Weapon.Category.MISSILE and d.missileCategory ~= Weapon.MissileCategory.AAM)
            if ag then
                Fire("weapon_away", "S_EVENT_SHOT " .. tostring(d.typeName or "?"))
                -- master arm calibration: a release needs ARM, so arg 49 now = ARM
                local ck = Cockpit()
                local raw = ck and ck.raw and ck.raw[CK_MAP.marm.arg]
                if type(raw) == "number" and not CK.marmChecked then
                    CK.marmChecked = true
                    if raw < 0.5 then
                        CK.marmInvert = true
                        Log(string.format("master arm mapping INVERTED (arg %d = %.3f at an A/G release)", CK_MAP.marm.arg, raw))
                    else
                        Log(string.format("master arm mapping confirmed (arg %d = %.3f at an A/G release)", CK_MAP.marm.arg, raw))
                    end
                end
            end
        end
    end
end
world.addEventHandler(EH)

--- Test hook: speak a moment now (probability and cooldown skipped, every other rule kept).
function PB.Say(name, why, ctx)
    if not CFG.MOMENTS[name] then Log("Say: unknown moment " .. tostring(name)); return end
    PB.pending[#PB.pending + 1] = { name = name, why = why or "Say()", t0 = now() - CFG.MOMENTS[name].delay, ctx = ctx or {} }
end

local nClips, nGroups = 0, 0
for _ in pairs(CFG.AUDIO) do nClips = nClips + 1 end
for _ in pairs(GROUPS) do nGroups = nGroups + 1 end
local seed = Seed()
timer.scheduleFunction(Tick, nil, now() + 2)
timer.scheduleFunction(function() Cockpit(); return nil end, nil, now() + 5)
Log(string.format("Pilot_Banter v%s loaded: hero %s, %d clips in %d groups, seed %d, level %s",
    CFG.VERSION, HERO, nClips, nGroups, seed, PB.level))
