-- CV_Comms | v1.5.2
--[[
  Carrier (CVN) departure / recovery radio — TRT Syria Dynamic Template
  Template-level module (not CAS-1 specific). Plan: project doc
  claude/cv-comms-gap-analysis.md (§5 decisions, §5.4 = this release, "R1").

  v1.5.2 — test helpers removed (Onur): no "Set CASE" on deck, no airborne "Test: set
           CASE" / "Test: deck fouled, Delta 5". Cases are planned in the ME (flag 100
           departure, flag 102 recovery). CFG.CASE_MENU and A_SetCase gone.

  v1.5.1 — the case-change 99 call is made whenever the hero is airborne (not only
           inside the CCA): the planned recovery case (flag 102, Airboss_CaseSync
           v1.0.6) is applied at ~51 NM, before the Marshal check-in. Like every 99
           call it is keyed on Marshal 261.00 (heard only when tuned there); the
           Marshal check-in reply states the case again. Time hack logs the abs time
           of "mark".

  v1.5.0 — R5: 99 calls / Delta / time hack (voiced by CV, Marshal 261.00; only while
           the hero is airborne inside the CCA). AIRBOSS overrides:
             _MarshalCallRecoveryStart   -> "99, Mother is now CASE N recovery, BRC/expected
                                            FB, altimeter" (only on a real case change).
                                            AIRBOSS's own call computed the marshal radial
                                            before the new holding offset (R-175 bug).
                                            Hero still in the Marshal queue -> re-marshalled
                                            with the new case (new instructions, readback).
             _MarshalCallRecoveryStopped -> "99, recovery complete, deck is closed." (silent
                                            for 90 s after an Airboss_CaseSync rebuild)
             _MarshalCallNewFinalBearing / _MarshalCallCarrierTurnTo -> voiced 99 calls
             RecoveryPause(duration)     -> "99, Delta N. Approach times plus N minutes."
                                            + "467, new expected approach time NN" + readback
             RecoveryPause()/Unpause     -> "99, Delta. Recovery paused, hold ..." / "99,
                                            recovery resumed ..." (MOOSE calls the undefined
                                            _MarshalCallRecoveryPausedNotice; defined here)
           Time hack once per pass after "established" (CASE II/III): "99, stand by for
           time hack" ... "5, 4, 3, 2, 1, mark, time NN" with mark on the whole minute;
           skipped when the EAT is < 90 s after it. Altimeter change >= 0.02 inHg while in
           the stack -> "99, altimeter NNNN". Test helpers (CFG.CASE_MENU) in the stack:
           "Test: set CASE I/II/III" and "Test: deck fouled, Delta 5".
           Q entries may give gap / seq / text as functions (evaluated at air time).

  v1.4.3 — CASE I: pilot acknowledges the Marshal info ("467, angels 2, wilco.").
           Signal Charlie text tells WHERE to commence: AIRBOSS only accepts the CASE I
           commence inside its 1 NM circle 4.75 NM on the port beam (ship heading -85);
           flying straight from the stack to the initial leaves AIRBOSS at "Commencing"
           and the pass is graded INVALID. AIRBOSS repeats Charlie every 180 s while the
           point is not reached; the repeat now says so. Clips re-rendered (make_clips
           v1.4.1, +5.5 dB).

  v1.4.2 — "established" is graded once per pass (TRT.addScore -> flag 1908):
           within EST_NM of the assigned fix (radial + DME), EST_FT of the assigned
           angels and EST_KIAS of HOLD_KIAS -> +EST_PTS, otherwise -EST_PTS with the
           failed items on screen. KIAS is estimated (3D velocity minus DCS wind = TAS,
           x sqrt(ISA density ratio)); +/-10 kt is typical, hence the wide window.
           "Recovery open" text: once per pass; past the EAT it reads "commence now".
           Clips re-rendered by make_clips v1.4.0 (25 % slower, +30 % level).

  v1.4.1 — test helper: on deck (not airborne, phase IDLE) CV COMMS offers
           "Set CASE I / II / III (flag 100)" (CFG.CASE_MENU). Airboss_CaseSync,
           Bankler gate and the scoring scripts follow flag 100 within ~5 s. The ME
           "CASE SELECTOR" still sets the mission default at start.

  v1.4.0 — R4: CASE III bolter / wave-off pattern + modex acknowledgements
    * After a bolter / wave-off (GROOVE -> AIRBOSS Bolter Pattern / Bullseye / Dirty Up):
          auto  467: 467, airborne.
                APP: 467, take angels 1.2, when level, turn left to the downwind,
                     heading <FB+180>.                          467: 467.
          auto  abeam (AIRBOSS X <= 0 on the downwind heading +/-45 deg):
                467: 467, abeam, state X.Y.
                APP: 467, at 4 DME, turn left to final bearing <FB>.   467: 467.
          -> BALLWAIT: ¾ mile "call the ball" again on the next pass (now also requires
             a heading within 45 deg of the final bearing).
    * Pilot "467." acknowledgement after Marshal "radar contact, final bearing" and
      after Approach "final bearing" (ACOP: most readbacks = side number only).

  v1.3.1 — groove fixes from the 2026-10-23 test
    * Roger ball / Paddles contact: one subtitle (AIRBOSS "LSO: Roger ball, 23 knots,
      axial.") instead of AIRBOSS "Roger ball." + a CV duplicate.
    * Bolter / wave-off (CASE III): when AIRBOSS sends the hero back to Bolter Pattern /
      Bullseye / Dirty Up after a Groove step, CV re-arms the ¾ mile call (GROOVE -> BALLWAIT), so the
      next pass gets "call the ball" + roger ball again. The ¾ mile trigger now also
      requires the aircraft to be astern (AIRBOSS _GetDistances X < sterndist) — after a
      bolter the jet is over the deck, i.e. < 1 NM from the stern but not astern.
      (Bolter-pattern radio = R4, not yet.)

  v1.3.0 — D1: CASE III departure (Departure 269.00, voice lessac = Comms_Director's)
    Armed by S_EVENT_TAKEOFF within 3 NM of the ship when the case is III
    (TRT.getCurrentCase / flag 100). CASE I/II departures stay ZIPLIP (no calls).
      auto  467: Departure, 467, airborne.        DEP: 467, radar contact, altimeter 2984.
                                                   467: 467.
      auto  >= 2,500 ft           467: 467, passing 2.5, Kilo.           DEP: 467, roger.
      auto  arc (6.5-11.5 DME, heading >= 30 deg off the launch heading)
                                  467: 467, arcing.                      DEP: 467, roger.
      auto  on R-DEP_RADIAL +/-5 deg, >= 9 DME, heading within 30 deg
                                  467: 467, established outbound.        DEP: 467, roger.
      F10   >= 17,500 ft  "Departure: Popeye, angels NN"  -> DEP: 467, roger.
      F10   >= 15,000 ft  "Departure: on top, angels NN"  -> DEP: 467, cleared to switch.
                                                              467: 467.
      fallback: >= DEP_FALLBACK_NM without "on top" -> DEP: 467, cleared to switch.
    TRT.CV.depActive (true from takeoff until cleared) and TRT.CV_DEP_CLEARED tell
    Comms_Director (v1.4.0) to skip its own 20 NM "switch Strike".
    Exports TRT.CV_AUDIO / TRT.CV_SND_DIR so Comms_Director can chain the pilot
    digit / letter tokens.

  v1.2.1 — commencing item label shows the time to EAT, refreshed every tick (2 s):
           "Marshal: commencing (EAT :32, T-1:20)" / "(EAT :32, T+0:15)".
           Menu root is now persistent; only the items are re-created when a label or
           the action set changes (keeps the player inside CV COMMS where DCS allows).

  v1.2.0 — R3: CASE III final
    * <= ACLS_NM (after platform): APP: 467, ACLS lock on, 6 miles, say needles.
        F10 "Needles: up and on"   -> APP: 467, concur, fly mode 2.
        F10 "Needles: negative"    -> APP: 467, roger, fly bullseye.
        no answer in NEEDLES_TIMEOUT s -> APP: 467, fly bullseye.
    * <= BALL_NM from the stern: APP: 467, <glidepath>, <course>, three-quarter mile,
      call the ball.  Glidepath / course words from AIRBOSS:_Glideslope / _Lineup with
      AIRBOSS's own LSO thresholds (gle / lue tables).
        F10 "Ball (Hornet ball, state)" / "Clara"; no answer in BALL_AUTO s -> ball
        call is made automatically (logged "ball call AUTO").
        Ball  -> Raynor LSO "Roger ball" + Raynor digits = wind over deck (axial, kt);
                 subtitle adds cross component. Raynor has no "knots" recording.
        Clara -> Raynor LSO "Paddles contact".
    * AIRBOSS calls now dropped: LSO "Call the ball" (all cases; CASE III Approach
      calls it), Marshal "Say needles" / "Fly your needles" (all cases, CV does it),
      LSO "Roger ball" unless CV plays it (CASE III after the pilot's ball call).

  v1.1.1 — diagnostics: AIRBOSS step and holding-zone flag of the hero are logged
           on change ("AIRBOSS step ...", "AIRBOSS holding ...").

  v1.1.0 — R2: commence -> Approach -> platform, CASE II see-you
    * CASE II/III  F10 "Marshal: commencing (EAT :mm)" (HOLDING / ESTABLISH)
          467: 467, commencing, 2984, state 5.1
          MSH: 467, radar contact, final bearing 346
        Commence time vs EAT is logged, TRT.CV_COMMENCE = { t, dt } (dt s, + = late).
        If AIRBOSS still has the hero in HOLDING, AIRBOSS:_RequestCommence is called.
    * Hand-off (controller-initiated, during penetration): first of altitude <=
      SWITCH_APP_FT MSL or DME <= SWITCH_APP_DME, >= SWITCH_APP_MIN s after radar
      contact:  MSH: 467, switch approach, button 15.   467: 467.
    * F10 "Approach 263.00: check in"
          467: Approach, 467, checking in, 19 miles, state 4.9
          APP: 467, Approach, final bearing 346
    * F10 "Approach: platform" (altitude <= PLATFORM_FT MSL)  -> APP: 467, roger.
    * CASE II  F10 "Approach: see you at 10" (<= SEE_YOU_NM, after Approach check-in)
          -> APP: 467, update state, go button 1 -> 467: state -> ZIPLIP (button 1)
    * CASE III after platform: phase FINAL (needles / ¾ mi / ball = R3).
    * AIRBOSS "cleared for recovery" text for CASE II/III now points to the EAT.
    * Voice APPROACH = Piper kusal (a_* tokens).

  v1.0.3 — comment only: Airboss_Start v1.0.3 holds stack 1 at angels 10, base 15
           (25 DME). DME formula unchanged.

  v1.0.2 — Marshal DME = angels + TRT.HOLD_DME_BASE (Airboss_Start v1.0.2: 19 ->
           25 DME at angels 6), fallback 15.

  v1.0.1 — "Marshal: established" no longer gated on AIRBOSS's holding zone (it was
           never offered when the player held at a fix other than AIRBOSS's). Offered
           right after the readback; the pilot decides when he is established. Distance
           to the assigned fix and altitude error are logged and stored in
           TRT.CV_ESTABLISHED for scoring.

  v1.0.0 — R1: Marshal
    * Pilot-initiated calls via F10 "CV COMMS" (only the next valid call is listed).
    * Voice: pre-rendered Piper token clips (tts/cv_clips.csv, make_clips.py --set cv)
      chained at runtime -> numbers are spoken (radial, DME, angels, state, altimeter,
      EAT). Every transmission = sq_up + tokens + sq_dn on the agency frequency.
    * Flow
        inbound (<= CCA_NM)  F10 "Marshal: check in"
          467: Marshal, 467, marking mom's 205 for 48, angels 18, state 7.2
          -> AIRBOSS:_RequestMarshal (AIRBOSS still owns stack / holding / grading)
          -> AIRBOSS:_MarshalCallArrived is OVERRIDDEN -> case-correct reply:
             CASE I : 467, Mother is VFR, altimeter 29.92, CASE I recovery,
                      BRC 355, hold angels 2, report see me.
             CASE II: 467, altimeter .., CASE II recovery, CV-1 approach, expected
                      BRC 355. 467, marshal on the 205 radial, 21 DME, angels 6,
                      expected approach time 28, approach button 15.
             CASE III: same, "expected final bearing" instead of BRC.
        CASE II/III  F10 "Marshal: readback"     -> "readback correct"
                     F10 "Marshal: established"  -> "roger"
        CASE I       F10 "Marshal: see you at 10" (<= SEE_YOU_NM)
                     -> "update state, go button 1" -> pilot state -> ZIPLIP
    * AIRBOSS instance overrides (MOOSE file untouched; installed when TRT.Airboss
      exists):
        _MarshalCallArrived            -> CV Marshal reply (hero only; AI silent)
        _MarshalCallClearedForRecovery -> text only for the hero (no Raynor voice;
                                          CASE I/II ZIPLIP, CASE II/III EAT = R2)
        MessageToPlayer(sender MARSHAL)-> text only (AIRBOSS plays Raynor modex /
                                          roger / negative via USERSOUND otherwise)
        RadioTransmission              -> drops LSO "Call the ball", "Roger ball",
                                          "Paddles contact" while the hero is CASE I/II
                                          (ZIPLIP on button 1). LSO corrections,
                                          wave off and bolter stay.
    * AIRBOSS LSO radio follows the case at Marshal reply: CASE III -> APPROACH
      (263.00, ball call is made on approach freq), CASE I/II -> TOWER (262.00).

  Not yet (see plan): needles / ¾ mi / ball call / roger ball + wind (R3), CASE III bolter pattern (R4),
  departure (D1), 99 calls / Delta (R5). AIRBOSS's own 99 calls and needles calls
  still use the Raynor Marshal voice until then.

  BUTTONS (COMM1, AM): 1 TOWER/PADDLES 262.00 · 2 DEPARTURE 269.00 ·
                       15 APPROACH 263.00 · 16 MARSHAL 261.00

  LOADING
    scripts/CV_Comms.lua, ME "Do Script File" ResKey_Action_314 (trigger
    OWN_SCRIPTS, after Comms_Director). Needs MOOSE + Airboss_Start.lua loaded
    earlier (MOOSE trigger). Clips: src/Sounds/CV/*.ogg. Regenerate with
    python tts/make_clips.py --set cv, then paste tts/cv_audio_table.lua into
    CFG.AUDIO below.
]]

-- ══════════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════════
local CFG = {
    VERSION      = "1.5.2",
    PLAYER_UNIT  = "Player_01",
    CARRIER_UNIT = "CVN",
    MODEX        = "467",       -- fallback if AIRBOSS has no onboard number yet

    EST_NM       = 1.5,         -- v1.4.2 established grading: max distance to the fix (NM)
    EST_FT       = 300,         -- ... max altitude error (ft)
    HOLD_KIAS    = 250,         -- ... holding speed and tolerance (estimated KIAS)
    EST_KIAS     = 30,
    EST_PTS      = 5,           -- +/- points
    CCA_NM       = 50,          -- Marshal check-in offered inside this range
    ARM_AIRBORNE = 900,         -- s airborne after which check-in is offered even
                                -- if the player never left the CCA
    SEE_YOU_NM   = 12,          -- "see you at 10" offered inside this range (CASE I/II)
    SWITCH_APP_FT  = 6000,      -- Marshal -> Approach hand-off: altitude (ft MSL) ...
    SWITCH_APP_DME = 21,        -- ... or DME, whichever first
    SWITCH_APP_MIN = 10,        -- s after "radar contact" at the earliest
    PLATFORM_FT    = 5500,      -- "platform" offered below this (ft MSL; ship at sea level)
    DEP_RADIAL     = 50,        -- CASE III departure radial (magnetic)
    DEP_ARC_MIN    = 6.5,       -- DME window in which the turn onto the arc is detected
    DEP_ARC_MAX    = 11.5,
    DEP_ARC_TURN   = 30,        -- deg off the launch heading = turning onto the arc
    DEP_RAD_TOL    = 5,         -- deg, "established outbound" on the departure radial
    DEP_RAD_MIN    = 9,         -- DME, minimum for "established outbound"
    POPEYE_FT      = 17500,     -- "Popeye" offered above this (mandatory at FL180 in IMC)
    ONTOP_FT       = 15000,     -- "on top" offered above this
    DEP_FALLBACK_NM= 30,        -- no "on top" by then -> Departure clears to switch anyway
    BOLTER_FINAL_DME = 4,       -- R4: "at 4 DME, turn left to final bearing"
    ACLS_NM        = 6.5,       -- "ACLS lock on, say needles" (DME)
    NEEDLES_TIMEOUT= 15,        -- s without a needles answer -> "fly bullseye"
    BALL_NM        = 1.0,       -- Approach starts "...three-quarter mile, call the ball" (NM from stern;
                                -- the call is ~4 s long, so it ends near 0.85 NM at 140 kt)
    BALL_AUTO      = 2.5,       -- s without a ball/Clara call -> automatic ball call

    SND_DIR      = "Sounds/CV/",
    TX_POWER     = 1000,        -- W, transmitted 30 m above the player (no LOS loss)
    GAP          = 0.03,        -- s between chained token clips
    P            = 0.22,        -- s comma pause inside a transmission
    REPLY_GAP    = 1.2,         -- s between pilot call end and controller reply
    TX_GAP       = 0.8,         -- s between consecutive transmissions otherwise
    DUR_TEXT     = 12,          -- s subtitle on screen
    TICK         = 2,           -- s

    CHAN = {
        TOWER     = { hz = 262.00e6, mod = 0, name = "TOWER",     btn = 1  },
        DEPARTURE = { hz = 269.00e6, mod = 0, name = "DEPARTURE", btn = 2  },
        APPROACH  = { hz = 263.00e6, mod = 0, name = "APPROACH",  btn = 15 },
        MARSHAL   = { hz = 261.00e6, mod = 0, name = "MARSHAL",   btn = 16 },
    },

    -- generated by tts/make_clips.py; len = clip length (s)
    AUDIO = {
        sq_up                  = { ch = "MARSHAL", len = 0.07 },
        sq_dn                  = { ch = "MARSHAL", len = 0.12 },
        m_0                    = { ch = "MARSHAL", len = 0.50 },
        m_1                    = { ch = "MARSHAL", len = 0.34 },
        m_2                    = { ch = "MARSHAL", len = 0.38 },
        m_3                    = { ch = "MARSHAL", len = 0.35 },
        m_4                    = { ch = "MARSHAL", len = 0.37 },
        m_5                    = { ch = "MARSHAL", len = 0.46 },
        m_6                    = { ch = "MARSHAL", len = 0.45 },
        m_7                    = { ch = "MARSHAL", len = 0.47 },
        m_8                    = { ch = "MARSHAL", len = 0.29 },
        m_9                    = { ch = "MARSHAL", len = 0.44 },
        m_vfr                  = { ch = "MARSHAL", len = 1.17 },
        m_altimeter            = { ch = "MARSHAL", len = 0.59 },
        m_case1                = { ch = "MARSHAL", len = 1.08 },
        m_case2                = { ch = "MARSHAL", len = 2.08 },
        m_case3                = { ch = "MARSHAL", len = 2.03 },
        m_brc                  = { ch = "MARSHAL", len = 0.71 },
        m_exp_brc              = { ch = "MARSHAL", len = 1.19 },
        m_exp_fb               = { ch = "MARSHAL", len = 1.15 },
        m_hold_angels          = { ch = "MARSHAL", len = 0.73 },
        m_report_see_me        = { ch = "MARSHAL", len = 0.82 },
        m_marshal_on           = { ch = "MARSHAL", len = 0.57 },
        m_radial               = { ch = "MARSHAL", len = 0.47 },
        m_dme                  = { ch = "MARSHAL", len = 0.67 },
        m_angels               = { ch = "MARSHAL", len = 0.50 },
        m_eat                  = { ch = "MARSHAL", len = 1.10 },
        m_btn15                = { ch = "MARSHAL", len = 1.21 },
        m_readback             = { ch = "MARSHAL", len = 0.75 },
        m_roger                = { ch = "MARSHAL", len = 0.50 },
        m_go1                  = { ch = "MARSHAL", len = 1.55 },
        p_0                    = { ch = "PILOT", len = 0.48 },
        p_1                    = { ch = "PILOT", len = 0.38 },
        p_2                    = { ch = "PILOT", len = 0.41 },
        p_3                    = { ch = "PILOT", len = 0.37 },
        p_4                    = { ch = "PILOT", len = 0.40 },
        p_5                    = { ch = "PILOT", len = 0.51 },
        p_6                    = { ch = "PILOT", len = 0.52 },
        p_7                    = { ch = "PILOT", len = 0.47 },
        p_8                    = { ch = "PILOT", len = 0.28 },
        p_9                    = { ch = "PILOT", len = 0.48 },
        p_point                = { ch = "PILOT", len = 0.41 },
        p_marshal              = { ch = "PILOT", len = 0.58 },
        p_marking              = { ch = "PILOT", len = 0.81 },
        p_for                  = { ch = "PILOT", len = 0.40 },
        p_angels               = { ch = "PILOT", len = 0.59 },
        p_state                = { ch = "PILOT", len = 0.42 },
        p_established          = { ch = "PILOT", len = 1.12 },
        p_see_you              = { ch = "PILOT", len = 1.02 },
        p_marshal_on           = { ch = "PILOT", len = 0.73 },
        p_approach_time        = { ch = "PILOT", len = 0.72 },
        p_btn15                = { ch = "PILOT", len = 0.89 },
        m_radar_fb             = { ch = "MARSHAL", len = 1.69 },
        m_switch_app           = { ch = "MARSHAL", len = 1.61 },
        a_0                    = { ch = "APPROACH", len = 0.47 },
        a_1                    = { ch = "APPROACH", len = 0.37 },
        a_2                    = { ch = "APPROACH", len = 0.33 },
        a_3                    = { ch = "APPROACH", len = 0.37 },
        a_4                    = { ch = "APPROACH", len = 0.34 },
        a_5                    = { ch = "APPROACH", len = 0.39 },
        a_6                    = { ch = "APPROACH", len = 0.50 },
        a_7                    = { ch = "APPROACH", len = 0.42 },
        a_8                    = { ch = "APPROACH", len = 0.23 },
        a_9                    = { ch = "APPROACH", len = 0.44 },
        a_approach             = { ch = "APPROACH", len = 0.57 },
        a_radar_contact        = { ch = "APPROACH", len = 0.79 },
        a_final_bearing        = { ch = "APPROACH", len = 0.68 },
        a_roger                = { ch = "APPROACH", len = 0.46 },
        a_go1                  = { ch = "APPROACH", len = 1.45 },
        p_commencing           = { ch = "PILOT", len = 0.68 },
        p_approach             = { ch = "PILOT", len = 0.71 },
        p_checking_in          = { ch = "PILOT", len = 0.74 },
        p_miles                = { ch = "PILOT", len = 0.50 },
        p_platform             = { ch = "PILOT", len = 0.60 },
        a_acls                 = { ch = "APPROACH", len = 1.35 },
        a_miles                = { ch = "APPROACH", len = 0.53 },
        a_say_needles          = { ch = "APPROACH", len = 0.71 },
        a_concur               = { ch = "APPROACH", len = 1.15 },
        a_bullseye             = { ch = "APPROACH", len = 0.68 },
        a_gp_on                = { ch = "APPROACH", len = 0.64 },
        a_gp_sl_above          = { ch = "APPROACH", len = 1.12 },
        a_gp_above             = { ch = "APPROACH", len = 0.73 },
        a_gp_sl_below          = { ch = "APPROACH", len = 1.03 },
        a_gp_below             = { ch = "APPROACH", len = 0.74 },
        a_crs_on               = { ch = "APPROACH", len = 0.65 },
        a_crs_sl_left          = { ch = "APPROACH", len = 1.08 },
        a_crs_left             = { ch = "APPROACH", len = 0.73 },
        a_crs_sl_right         = { ch = "APPROACH", len = 1.19 },
        a_crs_right            = { ch = "APPROACH", len = 0.87 },
        a_3q_ball              = { ch = "APPROACH", len = 1.44 },
        p_up_on                = { ch = "PILOT", len = 0.70 },
        p_neg_needles          = { ch = "PILOT", len = 1.19 },
        p_hornet_ball          = { ch = "PILOT", len = 0.67 },
        p_clara                = { ch = "PILOT", len = 0.39 },
        d_0                    = { ch = "DEPARTURE", len = 0.45 },
        d_1                    = { ch = "DEPARTURE", len = 0.31 },
        d_2                    = { ch = "DEPARTURE", len = 0.33 },
        d_3                    = { ch = "DEPARTURE", len = 0.36 },
        d_4                    = { ch = "DEPARTURE", len = 0.32 },
        d_5                    = { ch = "DEPARTURE", len = 0.39 },
        d_6                    = { ch = "DEPARTURE", len = 0.37 },
        d_7                    = { ch = "DEPARTURE", len = 0.34 },
        d_8                    = { ch = "DEPARTURE", len = 0.28 },
        d_9                    = { ch = "DEPARTURE", len = 0.40 },
        d_radar_alt            = { ch = "DEPARTURE", len = 1.28 },
        d_roger                = { ch = "DEPARTURE", len = 0.41 },
        d_cleared              = { ch = "DEPARTURE", len = 0.67 },
        p_departure            = { ch = "PILOT", len = 0.57 },
        p_airborne             = { ch = "PILOT", len = 0.62 },
        p_passing              = { ch = "PILOT", len = 0.44 },
        p_kilo                 = { ch = "PILOT", len = 0.44 },
        p_arcing               = { ch = "PILOT", len = 0.51 },
        p_est_out              = { ch = "PILOT", len = 1.03 },
        p_popeye               = { ch = "PILOT", len = 0.43 },
        p_on_top               = { ch = "PILOT", len = 0.54 },
        p_and                  = { ch = "PILOT", len = 0.44 },
        p_local                = { ch = "PILOT", len = 0.43 },
        p_unknown              = { ch = "PILOT", len = 0.60 },
        p_l_a                  = { ch = "PILOT", len = 0.39 },
        p_l_b                  = { ch = "PILOT", len = 0.48 },
        p_l_c                  = { ch = "PILOT", len = 0.40 },
        p_l_d                  = { ch = "PILOT", len = 0.49 },
        p_l_e                  = { ch = "PILOT", len = 0.46 },
        p_l_f                  = { ch = "PILOT", len = 0.57 },
        p_l_g                  = { ch = "PILOT", len = 0.39 },
        p_l_h                  = { ch = "PILOT", len = 0.61 },
        p_l_i                  = { ch = "PILOT", len = 0.46 },
        p_l_j                  = { ch = "PILOT", len = 0.62 },
        p_l_k                  = { ch = "PILOT", len = 0.46 },
        p_l_l                  = { ch = "PILOT", len = 0.46 },
        p_l_m                  = { ch = "PILOT", len = 0.44 },
        p_l_n                  = { ch = "PILOT", len = 0.62 },
        p_l_o                  = { ch = "PILOT", len = 0.48 },
        p_l_p                  = { ch = "PILOT", len = 0.50 },
        p_l_q                  = { ch = "PILOT", len = 0.47 },
        p_l_r                  = { ch = "PILOT", len = 0.56 },
        p_l_s                  = { ch = "PILOT", len = 0.55 },
        p_l_t                  = { ch = "PILOT", len = 0.51 },
        p_l_u                  = { ch = "PILOT", len = 0.68 },
        p_l_v                  = { ch = "PILOT", len = 0.54 },
        p_l_w                  = { ch = "PILOT", len = 0.47 },
        p_l_x                  = { ch = "PILOT", len = 0.69 },
        p_l_y                  = { ch = "PILOT", len = 0.47 },
        p_l_z                  = { ch = "PILOT", len = 0.63 },
        a_take_12              = { ch = "APPROACH", len = 1.38 },
        a_downwind             = { ch = "APPROACH", len = 1.76 },
        a_at                   = { ch = "APPROACH", len = 0.28 },
        a_dme_final            = { ch = "APPROACH", len = 1.80 },
        p_abeam                = { ch = "PILOT", len = 0.61 },
        p_wilco                = { ch = "PILOT", len = 0.52 },
        m_99                   = { ch = "MARSHAL", len = 0.69 },
        m_mother_now           = { ch = "MARSHAL", len = 0.67 },
        m_new_fb               = { ch = "MARSHAL", len = 0.98 },
        m_turning              = { ch = "MARSHAL", len = 0.76 },
        m_deck_closed          = { ch = "MARSHAL", len = 1.79 },
        m_delta_hold           = { ch = "MARSHAL", len = 4.11 },
        m_delta                = { ch = "MARSHAL", len = 0.39 },
        m_plus                 = { ch = "MARSHAL", len = 0.96 },
        m_minutes              = { ch = "MARSHAL", len = 0.50 },
        m_resume               = { ch = "MARSHAL", len = 2.26 },
        m_new_eat              = { ch = "MARSHAL", len = 1.24 },
        m_time_hack            = { ch = "MARSHAL", len = 1.08 },
        m_mark                 = { ch = "MARSHAL", len = 0.45 },
        m_time                 = { ch = "MARSHAL", len = 0.38 },
    },

    -- AIRBOSS calls dropped in every case (CV_Comms makes them)
    ALWAYS_DROP = {
        ["LSO-CallTheBall"]        = true,
        ["MARSHAL-SayNeedles"]     = true,
        ["MARSHAL-FlyYourNeedles"] = true,
    },
    -- LSO calls dropped while the hero flies CASE I/II (ZIPLIP on button 1)
    ZIPLIP_DROP = {
        ["LSO-CallTheBall"]    = true,
        ["LSO-RogerBall"]      = true,
        ["LSO-PaddlesContact"] = true,
    },
}

-- ══════════════════════════════════════════════════════════════
--  STATE
-- ══════════════════════════════════════════════════════════════
--  phase: IDLE -> CHECKIN -> CHECKIN_SENT -> (I) SEEYOU -> ZIPLIP
--     (II/III) READBACK -> ESTABLISH -> HOLDING -> PENETRATION -> APP_CHECKIN
--              -> APPROACH -> (II) APP_SEEYOU -> ZIPLIP   (III) FINAL (R3)
local CV = {
    phase      = "IDLE",
    case       = nil,
    air        = false,     -- hero airborne
    tAir       = nil,       -- takeoff time (timer.getTime)
    wasOutside = false,     -- hero has been outside the CCA since takeoff
    clr        = nil,       -- Marshal clearance { radial, dme, angels, eat, brc, fb, alt }
    q          = {},        -- transmission queue
    busy       = false,
    txn        = 0,
    menu       = { gid = nil, root = nil },
    hooked     = false,
    tRadar     = nil,       -- timer.getTime() of Marshal "radar contact"
    tPhase     = 0,         -- timer.getTime() of the last phase change
    allowRB    = false,     -- let one LSO "Roger ball" through (CV plays it)
    origRT     = nil,       -- AIRBOSS:RadioTransmission before the override
    depActive  = false,     -- CASE III departure in progress (Comms_Director reads it)
    dep        = nil,       -- { hdg0, popeye, ontop }
}
_G.TRT = _G.TRT or {}
TRT.CV = CV
TRT.CV_AUDIO   = CFG.AUDIO     -- shared token clips (Comms_Director v1.4.0)
TRT.CV_SND_DIR = CFG.SND_DIR

-- ══════════════════════════════════════════════════════════════
--  UTILITIES
-- ══════════════════════════════════════════════════════════════
local function Log(s) env.info("CV_Comms | " .. s) end
local function AB() return TRT.Airboss end
local function Hero() return Unit.getByName(CFG.PLAYER_UNIT) end
local function Ship() return Unit.getByName(CFG.CARRIER_UNIT) end

local function DistNM(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return math.sqrt(dx * dx + dz * dz) / 1852
end

--- AIRBOSS player record of the hero (nil until AIRBOSS registered the player).
local function HeroPD()
    local ab = AB(); if not ab or not ab.players then return nil end
    for _, pd in pairs(ab.players) do
        if pd.unitname == CFG.PLAYER_UNIT then return pd end
    end
    return nil
end

local function Modex()
    local pd = HeroPD()
    local m = pd and pd.onboard
    if type(m) ~= "string" or not m:match("^%d+$") then m = CFG.MODEX end
    return m
end

local function Msg(text, dur)
    local u = Hero(); if not u then return end
    trigger.action.outTextForGroup(u:getGroup():getID(), text, dur or CFG.DUR_TEXT)
end

--- Token ids for each digit of string/number s, voice prefix "m" / "p".
local function D(v, s)
    local t = {}
    for c in tostring(s):gmatch("%d") do t[#t + 1] = v .. "_" .. c end
    return t
end

--- Flatten nested sequence tables.
local function Seq(...)
    local out = {}
    local function add(x)
        if type(x) == "table" then for _, y in ipairs(x) do add(y) end
        elseif x ~= nil then out[#out + 1] = x end
    end
    for _, x in ipairs({ ... }) do add(x) end
    return out
end

local function Hdg3(h) return string.format("%03d", math.floor(h + 0.5) % 360) end
local function Alt4(inhg) return string.format("%04d", math.floor(inhg * 100 + 0.5)) end
local function StateStr(lbs) return string.format("%.1f", math.floor(lbs / 100 + 0.5) / 10) end

local function StateTokens(lbs)
    local s = StateStr(lbs)
    local i, f = s:match("^(%d+)%.(%d)$")
    return Seq(D("p", i), "p_point", D("p", f))
end

local function FuelLbs()
    local pd, ab = HeroPD(), AB()
    if pd and ab then
        local ok, lbs = pcall(ab._GetFuelState, ab, pd.unit)
        if ok and lbs then return lbs end
    end
    local u = Hero()
    return u and (u:getFuel() or 0) * 10860 or 0
end

-- ══════════════════════════════════════════════════════════════
--  TRANSMISSION QUEUE
-- ══════════════════════════════════════════════════════════════
--- Play one chained transmission. seq = token ids and numbers (pause, s).
-- Returns total airtime (s).
local function Air(chKey, seq)
    local ch, u = CFG.CHAN[chKey], Hero()
    if not (ch and u) then return 0 end
    local full = Seq("sq_up", seq, "sq_dn")
    local t = 0
    CV.txn = CV.txn + 1
    local tag = "CV_" .. CV.txn .. "_"
    for i, id in ipairs(full) do
        if type(id) == "number" then
            t = t + id
        else
            local a = CFG.AUDIO[id]
            if a then
                local name = tag .. i
                local file = CFG.SND_DIR .. id .. ".ogg"
                timer.scheduleFunction(function()
                    local h = Hero(); if not h then return end
                    local p = h:getPoint()
                    trigger.action.radioTransmission(file, { x = p.x, y = p.y + 30, z = p.z },
                        ch.mod, false, ch.hz, CFG.TX_POWER, name)
                end, nil, timer.getTime() + t + 0.01)
                t = t + a.len + ((id == "sq_up") and 0 or CFG.GAP)
            else
                Log("missing clip " .. tostring(id))
            end
        end
    end
    return t
end

local QNext
--- Queue a transmission.
-- @param who   "PILOT" or agency key (subtitle prefix)
-- @param ch    CFG.CHAN key the transmission is keyed on
-- @param seq   token sequence
-- @param text  subtitle
-- @param fn    optional callback after the transmission ends
-- @param gap   s before this transmission starts (default TX_GAP)
local function Q(who, ch, seq, text, fn, gap)
    CV.q[#CV.q + 1] = { who = who, ch = ch, seq = seq, text = text, fn = fn, gap = gap }
    if not CV.busy then QNext() end
end

QNext = function()
    local x = table.remove(CV.q, 1)
    if not x then CV.busy = false; return end
    CV.busy = true
    local function go()
        local label = (x.who == "PILOT") and Modex() or x.who
        local seq  = (type(x.seq) == "function") and x.seq() or x.seq      -- v1.5.0: lazy
        local text = (type(x.text) == "function") and x.text() or x.text
        Msg(string.format("[%s · %s %.2f] %s", label, CFG.CHAN[x.ch].name,
            CFG.CHAN[x.ch].hz / 1e6, text))
        local len = Air(x.ch, seq)
        timer.scheduleFunction(function()
            if x.fn then
                local ok, err = pcall(x.fn)
                if not ok then Log("callback error: " .. tostring(err)) end
            end
            QNext()
        end, nil, timer.getTime() + len + 0.05)
    end
    local gap = x.gap or CFG.TX_GAP
    if type(gap) == "function" then gap = gap() end
    if gap > 0 then timer.scheduleFunction(go, nil, timer.getTime() + gap) else go() end
end

local function Pilot(ch, seq, text, fn) Q("PILOT", ch, seq, text, fn, 0.2) end
local function Ctl(who, ch, seq, text, fn) Q(who, ch, seq, text, fn, CFG.REPLY_GAP) end

-- ══════════════════════════════════════════════════════════════
--  F10 MENU
-- ══════════════════════════════════════════════════════════════
local MenuRebuild

local function SetPhase(p)
    if CV.phase ~= p then
        Log("phase " .. CV.phase .. " -> " .. p)
        CV.phase = p
        CV.tPhase = timer.getTime()
        if MenuRebuild then MenuRebuild() end
    end
end

-- ══════════════════════════════════════════════════════════════
--  CALLS
-- ══════════════════════════════════════════════════════════════
local function A_CheckIn()
    local u, s, ab = Hero(), Ship(), AB()
    if not (u and s and ab) then return end
    local up, sp = u:getPoint(), s:getPoint()
    local trueBrg = math.deg(math.atan2(up.z - sp.z, up.x - sp.x)) % 360
    local radial  = Hdg3(trueBrg - (ab.magvar or 0))
    local dme     = tostring(math.floor(DistNM(up, sp) + 0.5))
    local angels  = tostring(math.max(1, math.floor(up.y * 3.28084 / 1000 + 0.5)))
    local lbs     = FuelLbs()
    local m       = Modex()
    Pilot("MARSHAL",
        Seq("p_marshal", D("p", m), CFG.P, "p_marking", D("p", radial), "p_for", D("p", dme),
            CFG.P, "p_angels", D("p", angels), CFG.P, "p_state", StateTokens(lbs)),
        string.format("Marshal, %s, marking mom's %s for %s, angels %s, state %s.",
            m, radial, dme, angels, StateStr(lbs)),
        function()
            CV.replied = false
            -- AIRBOSS validates (CCA, airborne, queues) and assigns the stack;
            -- the reply comes through the _MarshalCallArrived override.
            ab:_RequestMarshal(CFG.PLAYER_UNIT)
            if not CV.replied then
                Log("Marshal request not accepted by AIRBOSS (see AIRBOSS message)")
                if MenuRebuild then MenuRebuild() end
            end
        end)
    SetPhase("CHECKIN_SENT")
end

local function A_Readback()
    local c, m = CV.clr, Modex()
    if not c then return end
    Pilot("MARSHAL",
        Seq(D("p", m), CFG.P, "p_marshal_on", D("p", c.radial), CFG.P, D("p", c.dme), CFG.P,
            "p_angels", D("p", c.angels), CFG.P, "p_approach_time", D("p", c.eat), CFG.P, "p_btn15"),
        string.format("%s, marshal on the %s, %s, angels %s, approach time %s, button 15.",
            m, c.radial, c.dme, c.angels, c.eat),
        function()
            Ctl("MARSHAL", "MARSHAL", Seq(D("m", m), CFG.P, "m_readback"),
                string.format("%s, readback correct.", m))
        end)
    SetPhase("ESTABLISH")
end

--- Distance (NM) to the assigned marshal fix and altitude error (ft).
local function FixError()
    local c, u, s, ab = CV.clr, Hero(), Ship(), AB()
    if not (c and c.radial and u and s and ab) then return nil end
    local tr = math.rad(tonumber(c.radial) + (ab.magvar or 0))
    local d  = tonumber(c.dme) * 1852
    local sp, up = s:getPoint(), u:getPoint()
    local fx = { x = sp.x + d * math.cos(tr), z = sp.z + d * math.sin(tr) }
    return DistNM(up, fx), up.y * 3.28084 - tonumber(c.angels) * 1000
end

--- Estimated indicated airspeed (kt): TAS from velocity minus wind, ISA density ratio.
local function EstKIAS(u)
    if not u or not u:isExist() then return nil end
    local v, p = u:getVelocity(), u:getPoint()
    local ok, w = pcall(atmosphere.getWind, p)
    if not ok or type(w) ~= "table" then w = { x = 0, y = 0, z = 0 } end
    local tas = math.sqrt((v.x - w.x)^2 + (v.y - (w.y or 0))^2 + (v.z - w.z)^2)
    local hft = p.y * 3.28084
    local sigma = math.max(0.1, (1 - 6.8756e-6 * hft)) ^ 4.2559
    return tas * math.sqrt(sigma) * 1.94384
end

--- v1.4.2: grade the "established" call once per pass.
local function GradeEstablished(dn, da, kias)
    if not (TRT and TRT.addScore) then return end
    local bad = {}
    if dn > CFG.EST_NM then bad[#bad + 1] = string.format("%.1f NM off the fix", dn) end
    if math.abs(da) > CFG.EST_FT then bad[#bad + 1] = string.format("altitude %+d ft", math.floor(da + 0.5)) end
    if kias and math.abs(kias - CFG.HOLD_KIAS) > CFG.EST_KIAS then
        bad[#bad + 1] = string.format("~%d KIAS (hold %d)", math.floor(kias + 0.5), CFG.HOLD_KIAS)
    end
    if #bad == 0 then
        TRT.addScore(CFG.EST_PTS, "Established on the marshal fix")
    else
        TRT.addScore(-CFG.EST_PTS, "Established call not on the fix: " .. table.concat(bad, ", "))
    end
end

local TimeHack   -- v1.5.0 (R5 block)

local function A_Established()
    local c, m, lbs = CV.clr, Modex(), FuelLbs()
    if not c then return end
    local dn, da = FixError()
    if dn then
        local kias = EstKIAS(Hero())
        TRT.CV_ESTABLISHED = { t = timer.getAbsTime(), dNM = dn, dAltFt = da, kias = kias }
        Log(string.format("established: %.1f NM from assigned fix (%s R / %s DME), alt error %+d ft, ~%d KIAS",
            dn, c.radial, c.dme, math.floor(da + 0.5), math.floor((kias or 0) + 0.5)))
        if not c.estScored then
            c.estScored = true
            timer.scheduleFunction(function() pcall(GradeEstablished, dn, da, kias) end, nil, timer.getTime() + 6)
        end
    end
    Pilot("MARSHAL",
        Seq(D("p", m), CFG.P, "p_established", D("p", c.angels), CFG.P, "p_state", StateTokens(lbs)),
        string.format("%s, established angels %s, state %s.", m, c.angels, StateStr(lbs)),
        function()
            Ctl("MARSHAL", "MARSHAL", Seq(D("m", m), CFG.P, "m_roger"), string.format("%s, roger.", m),
                function() if TimeHack then pcall(TimeHack) end end)
        end)
    SetPhase("HOLDING")
end

local function A_SeeYou()
    local m = Modex()
    Pilot("MARSHAL", Seq(D("p", m), CFG.P, "p_see_you"), string.format("%s, see you at 10.", m),
        function()
            Ctl("MARSHAL", "MARSHAL", Seq(D("m", m), CFG.P, "m_go1"),
                string.format("%s, update state, go button 1 (TOWER %.2f).", m, CFG.CHAN.TOWER.hz / 1e6),
                function()
                    local lbs = FuelLbs()
                    Pilot("MARSHAL", Seq(D("p", m), CFG.P, StateTokens(lbs)),
                        string.format("%s, %s.", m, StateStr(lbs)),
                        function()
                            Msg(string.format("[CV] Button 1, TOWER %.2f — ZIPLIP.", CFG.CHAN.TOWER.hz / 1e6), 8)
                        end)
                end)
        end)
    SetPhase("ZIPLIP")
end

--- Approach "see you at 10" (CASE II) -> go button 1 -> state -> ZIPLIP.
local function A_AppSeeYou()
    local m = Modex()
    Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_see_you"), string.format("%s, see you at 10.", m),
        function()
            Ctl("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, "a_go1"),
                string.format("%s, update state, go button 1 (TOWER %.2f).", m, CFG.CHAN.TOWER.hz / 1e6),
                function()
                    local lbs = FuelLbs()
                    Pilot("APPROACH", Seq(D("p", m), CFG.P, StateTokens(lbs)),
                        string.format("%s, %s.", m, StateStr(lbs)),
                        function()
                            Msg(string.format("[CV] Button 1, TOWER %.2f — ZIPLIP.", CFG.CHAN.TOWER.hz / 1e6), 8)
                        end)
                end)
        end)
    SetPhase("ZIPLIP")
end

local function A_Commencing()
    local c, m, lbs, ab = CV.clr, Modex(), FuelLbs(), AB()
    if not c then return end
    local dt = timer.getAbsTime() - (c.eatAbs or timer.getAbsTime())
    TRT.CV_COMMENCE = { t = timer.getAbsTime(), dt = dt }
    Log(string.format("commencing: %+d s vs EAT :%s%s", math.floor(dt + 0.5), c.eat,
        (math.abs(dt) > 10) and " (outside +/-10 s)" or ""))
    local altTxt = c.alt:sub(1, 2) .. "." .. c.alt:sub(3, 4)
    Pilot("MARSHAL",
        Seq(D("p", m), CFG.P, "p_commencing", D("p", c.alt), CFG.P, "p_state", StateTokens(lbs)),
        string.format("%s, commencing, %s, state %s.", m, altTxt, StateStr(lbs)),
        function()
            local fb = Hdg3(ab:GetFinalBearing(true))
            c.fb = fb
            Ctl("MARSHAL", "MARSHAL", Seq(D("m", m), CFG.P, "m_radar_fb", D("m", fb)),
                string.format("%s, radar contact, final bearing %s.", m, fb),
                function()
                    CV.tRadar = timer.getTime()
                    Pilot("MARSHAL", D("p", m), string.format("%s.", m))
                end)
            -- keep AIRBOSS in step if it has not released the hero from the stack yet
            local pd = HeroPD()
            if pd and pd.step == AIRBOSS.PatternStep.HOLDING then
                pcall(ab._RequestCommence, ab, CFG.PLAYER_UNIT)
            end
        end)
    SetPhase("PENETRATION")
end

local function C_SwitchApproach()
    local m = Modex()
    Ctl("MARSHAL", "MARSHAL", Seq(D("m", m), CFG.P, "m_switch_app"),
        string.format("%s, switch approach, button 15 (%.2f).", m, CFG.CHAN.APPROACH.hz / 1e6),
        function()
            Pilot("MARSHAL", D("p", m), string.format("%s.", m))
        end)
    SetPhase("APP_CHECKIN")
end

local function A_AppCheckIn()
    local u, s, m, lbs, ab = Hero(), Ship(), Modex(), FuelLbs(), AB()
    if not (u and s) then return end
    local miles = tostring(math.floor(DistNM(u:getPoint(), s:getPoint()) + 0.5))
    Pilot("APPROACH",
        Seq("p_approach", D("p", m), CFG.P, "p_checking_in", D("p", miles), "p_miles", CFG.P,
            "p_state", StateTokens(lbs)),
        string.format("Approach, %s, checking in, %s miles, state %s.", m, miles, StateStr(lbs)),
        function()
            local fb = Hdg3(ab:GetFinalBearing(true))
            if CV.clr then CV.clr.fb = fb end
            Ctl("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, "a_approach", "a_final_bearing", D("a", fb)),
                string.format("%s, Approach, final bearing %s.", m, fb),
                function() Pilot("APPROACH", D("p", m), string.format("%s.", m)) end)
        end)
    SetPhase("APPROACH")
end

local function A_Platform()
    local m = Modex()
    Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_platform"), string.format("%s, platform.", m),
        function()
            Ctl("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, "a_roger"), string.format("%s, roger.", m))
        end)
    SetPhase((CV.case == 2) and "APP_SEEYOU" or "FINAL")
end

-- ── R3: final ─────────────────────────────────────────────────
--- True when the hero is astern of the ship (AIRBOSS geometry; groove side).
local function Astern()
    local pd, ab = HeroPD(), AB()
    if not (pd and ab) then return true end
    local ok, X = pcall(ab._GetDistances, ab, pd.unit)
    if not ok or not X then return true end
    return X < ((ab.carrierparam and ab.carrierparam.sterndist) or 0)
end

--- NM from the carrier stern (AIRBOSS geometry), fallback ship centre.
local function SternNM()
    local pd, ab, u, s = HeroPD(), AB(), Hero(), Ship()
    if pd and ab then
        local ok, st = pcall(ab._GetSternCoord, ab)
        if ok and st then return st:Get2DDistance(pd.unit:GetCoordinate()) / 1852 end
    end
    return (u and s) and DistNM(u:getPoint(), s:getPoint()) or 99
end

local function C_AclsLock()
    local m = Modex()
    Q("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, "a_acls", D("a", "6"), "a_miles", "a_say_needles"),
        string.format("%s, ACLS lock on, 6 miles, say needles.", m), nil, 0.2)
    SetPhase("NEEDLES")
end

local function A_Needles(concur)
    local m = Modex()
    if concur then
        Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_up_on"), string.format("%s, up and on.", m), function()
            Q("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, "a_concur"),
                string.format("%s, concur, fly mode 2.", m), nil, 0.4)
        end)
    else
        Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_neg_needles"), string.format("%s, negative needles.", m), function()
            Q("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, "a_roger", "a_bullseye"),
                string.format("%s, roger, fly bullseye.", m), nil, 0.4)
        end)
    end
    SetPhase("BALLWAIT")
end

local function C_FlyBullseye()
    local m = Modex()
    Q("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, "a_bullseye"), string.format("%s, fly bullseye.", m), nil, 0.2)
    SetPhase("BALLWAIT")
end

--- Glidepath / course words from AIRBOSS's LSO error functions and thresholds.
local function Position()
    local pd, ab = HeroPD(), AB()
    local gpT, gpX, crT, crX = "a_gp_on", "on glidepath", "a_crs_on", "on course"
    if not (pd and ab) then return gpT, gpX, crT, crX end
    local ok1, gse = pcall(ab._Glideslope, ab, pd.unit)
    local ok2, lue = pcall(ab._Lineup, ab, pd.unit, true)
    local g, l = ab.gle or {}, ab.lue or {}
    if ok1 and gse then
        if gse > (g.High or 0.8) then gpT, gpX = "a_gp_above", "above glidepath"
        elseif gse > (g._max or 0.4) then gpT, gpX = "a_gp_sl_above", "slightly above glidepath"
        elseif gse < (g.Low or -0.6) then gpT, gpX = "a_gp_below", "below glidepath"
        elseif gse < (g._min or -0.3) then gpT, gpX = "a_gp_sl_below", "slightly below glidepath" end
    end
    if ok2 and lue then
        if lue < (l.Left or -2.8) then crT, crX = "a_crs_left", "left of course"
        elseif lue < (l._min or -1.8) then crT, crX = "a_crs_sl_left", "slightly left of course"
        elseif lue > (l.Right or 2.8) then crT, crX = "a_crs_right", "right of course"
        elseif lue > (l._max or 1.8) then crT, crX = "a_crs_sl_right", "slightly right of course" end
    end
    return gpT, gpX, crT, crX
end

local function C_CallBall()
    local m = Modex()
    local gpT, gpX, crT, crX = Position()
    CV.q = {}                      -- nothing else on the air in the groove
    Q("APPROACH", "APPROACH", Seq(D("a", m), CFG.P, gpT, crT, "a_3q_ball"),
        string.format("%s, %s, %s, three-quarter mile, call the ball.", m, gpX, crX),
        function() CV.tBallAsk = timer.getTime() end, 0)
    SetPhase("BALL")
end

--- Raynor LSO transmission that bypasses the drop filter.
local function LsoRaw(call, subtitle)
    local ab = AB()
    if not (ab and CV.origRT and call) then return end
    local c = call
    if subtitle then
        local ok, cp = pcall(function() return UTILS.DeepCopy(call) end)
        if ok and cp then cp.subtitle = subtitle; c = cp end
    end
    CV.allowRB = true
    pcall(CV.origRT, ab, ab.LSORadio, c, false)
    CV.allowRB = false
end

local function A_Ball(auto)
    if CV.phase ~= "BALL" then return end
    local m, lbs, ab = Modex(), FuelLbs(), AB()
    if auto then Log("ball call AUTO (no pilot call in " .. CFG.BALL_AUTO .. " s)") end
    SetPhase("GROOVE")
    Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_hornet_ball", StateTokens(lbs)),
        string.format("%s, Hornet ball, %s.", m, StateStr(lbs)),
        function()
            local kts, cross = nil, 0
            local ok, ax, cr = pcall(ab.GetWindOnDeck, ab)
            if ok and ax then kts = math.floor(ax * 1.94384 + 0.5); cross = math.floor(math.abs(cr or 0) * 1.94384 + 0.5) end
            LsoRaw(ab.LSOCall.ROGERBALL, string.format("Roger ball%s.",
                kts and string.format(", %d knots%s", kts, (cross > 2) and string.format(" (cross %d kt)", cross) or ", axial") or ""))
            if kts and kts > 0 then pcall(ab._Number2Radio, ab, ab.LSORadio, tostring(kts)) end
        end)
end

local function A_Clara()
    if CV.phase ~= "BALL" then return end
    local m, ab = Modex(), AB()
    SetPhase("GROOVE")
    Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_clara"), string.format("%s, Clara.", m), function()
        LsoRaw(ab.LSOCall.PADDLESCONTACT, "Paddles contact.")
    end)
end

-- ── D1: CASE III departure ─────────────────────────────────────
local function MagHdg(u)
    local ab = AB()
    local pos = u:getPosition()
    local h = math.deg(math.atan2(pos.x.z, pos.x.x)) % 360
    return (h - ((ab and ab.magvar) or 0)) % 360
end

local function MagRadial(u, s)
    local ab = AB()
    local up, sp = u:getPoint(), s:getPoint()
    return (math.deg(math.atan2(up.z - sp.z, up.x - sp.x)) - ((ab and ab.magvar) or 0)) % 360
end

local function ADiff(a, b) local d = (a - b + 540) % 360 - 180; return d end

local function DepAck(text)   -- Departure "467, roger."
    local m = Modex()
    Q("DEPARTURE", "DEPARTURE", Seq(D("d", m), CFG.P, "d_roger"), string.format("%s, roger.", m), nil, 0.8)
end

local function DepCleared()
    local m = Modex()
    if CV.phase == "IDLE" then return end
    Q("DEPARTURE", "DEPARTURE", Seq(D("d", m), CFG.P, "d_cleared"), string.format("%s, cleared to switch.", m),
        function()
            Pilot("DEPARTURE", D("p", m), string.format("%s.", m), function()
                TRT.CV_DEP_CLEARED = true
                CV.depActive = false
                Msg("[CV] Departure complete — switch Strike.", 8)
            end)
        end, 0.8)
    SetPhase("IDLE")
end

local function DepStart()
    local u, ab = Hero(), AB()
    if not u then return end
    local m = Modex()
    CV.dep = { hdg0 = MagHdg(u) }
    CV.depActive, TRT.CV_DEP_CLEARED = true, false
    SetPhase("DEP_AIR")
    local alt4 = "2992"
    if ab then
        local ok, p = pcall(function() return UTILS.hPa2inHg(ab:GetCoordinate():GetPressure()) end)
        if ok and p then alt4 = Alt4(p) end
    end
    Pilot("DEPARTURE", Seq("p_departure", D("p", m), CFG.P, "p_airborne"),
        string.format("Departure, %s, airborne.", m), function()
            Q("DEPARTURE", "DEPARTURE", Seq(D("d", m), CFG.P, "d_radar_alt", D("d", alt4)),
                string.format("%s, radar contact, altimeter %s.%s.", m, alt4:sub(1, 2), alt4:sub(3, 4)),
                function() Pilot("DEPARTURE", D("p", m), string.format("%s.", m)) end, 0.8)
        end)
    SetPhase("DEP_CLIMB")
end

local function DepReport(seq, text, nextPhase)
    local m = Modex()
    Pilot("DEPARTURE", Seq(D("p", m), CFG.P, seq), string.format("%s, %s", m, text), function() DepAck() end)
    SetPhase(nextPhase)
end

local function DepTick(u, s, d)
    local ph = CV.phase
    if CV.busy then return end
    local altFt = u:getPoint().y * 3.28084
    if ph == "DEP_CLIMB" and altFt >= 2500 then
        DepReport(Seq("p_passing", D("p", "2"), "p_point", D("p", "5"), CFG.P, "p_kilo"), "passing 2.5, Kilo.", "DEP_ARC")
        return
    end
    if ph == "DEP_ARC" or ph == "DEP_RADIAL" then
        local onRadial = math.abs(ADiff(MagRadial(u, s), CFG.DEP_RADIAL)) <= CFG.DEP_RAD_TOL
            and d >= CFG.DEP_RAD_MIN and math.abs(ADiff(MagHdg(u), CFG.DEP_RADIAL)) <= 30
        if onRadial then
            DepReport("p_est_out", "established outbound.", "DEP_OUT")
            return
        end
        if ph == "DEP_ARC" and d >= CFG.DEP_ARC_MIN and d <= CFG.DEP_ARC_MAX
           and math.abs(ADiff(MagHdg(u), CV.dep.hdg0)) >= CFG.DEP_ARC_TURN then
            DepReport("p_arcing", "arcing.", "DEP_RADIAL")
            return
        end
    end
    if d >= CFG.DEP_FALLBACK_NM then DepCleared() end
end

local function A_Popeye()
    local u = Hero(); if not u then return end
    local a = tostring(math.floor(u:getPoint().y * 3.28084 / 1000 + 0.5))
    CV.dep.popeye = true
    local m = Modex()
    Pilot("DEPARTURE", Seq(D("p", m), CFG.P, "p_popeye", "p_angels", D("p", a)),
        string.format("%s, Popeye, angels %s.", m, a), function() DepAck() end)
end

local function A_OnTop()
    local u = Hero(); if not u then return end
    local a = tostring(math.floor(u:getPoint().y * 3.28084 / 1000 + 0.5))
    CV.dep.ontop = true
    local m = Modex()
    Pilot("DEPARTURE", Seq(D("p", m), CFG.P, "p_on_top", "p_angels", D("p", a)),
        string.format("%s, on top, angels %s.", m, a), function() DepCleared() end)
end

local function CaseNow()
    if TRT.getCurrentCase then
        local ok, c = pcall(TRT.getCurrentCase)
        if ok and c then return c end
    end
    local f = trigger.misc.getUserFlag(100)
    return (f == 1 or f == 2 or f == 3) and f or 3
end

-- ── R4: CASE III bolter / wave-off pattern ─────────────────────
local function C_BolterStart()
    local m, ab = Modex(), AB()
    local fbN = ab and ab:GetFinalBearing(true) or 0
    local dw  = Hdg3(fbN + 180)
    CV.bolter = { dw = tonumber(dw), fb = Hdg3(fbN) }
    SetPhase("B_UPWIND")
    CV.q = {}
    Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_airborne"), string.format("%s, airborne.", m), function()
        Q("APPROACH", "APPROACH",
            Seq(D("a", m), CFG.P, "a_take_12", "a_downwind", D("a", dw)),
            string.format("%s, take angels 1.2, when level, turn left to the downwind, heading %s.", m, dw),
            function()
                Pilot("APPROACH", D("p", m), string.format("%s.", m))
                SetPhase("B_DOWNWIND")
            end, 0.8)
    end)
end

local function C_BolterAbeam()
    local m, lbs = Modex(), FuelLbs()
    local fb, dme = CV.bolter.fb, tostring(CFG.BOLTER_FINAL_DME)
    SetPhase("B_ABEAM")
    Pilot("APPROACH", Seq(D("p", m), CFG.P, "p_abeam", "p_state", StateTokens(lbs)),
        string.format("%s, abeam, state %s.", m, StateStr(lbs)), function()
            Q("APPROACH", "APPROACH",
                Seq(D("a", m), CFG.P, "a_at", D("a", dme), "a_dme_final", D("a", fb)),
                string.format("%s, at %s DME, turn left to final bearing %s.", m, dme, fb),
                function()
                    Pilot("APPROACH", D("p", m), string.format("%s.", m))
                    SetPhase("BALLWAIT")
                end, 0.8)
        end)
end

--- Marshal reply (from the _MarshalCallArrived override).
local function MarshalReply(case, brc, altitude, tcharlie, qfe)
    local ab, m = AB(), Modex()
    local angels = math.floor(altitude * 3.28084 / 1000 + 0.5)
    local alt4   = Alt4(qfe or 29.92)
    local altTxt = alt4:sub(1, 2) .. "." .. alt4:sub(3, 4)
    local B      = Hdg3(brc)
    -- EAT: AIRBOSS Charlie time rounded UP to the whole minute; spoken as minutes.
    local eatAbs = math.ceil((tcharlie or (timer.getAbsTime() + 600)) / 60) * 60
    local eat    = string.format("%02d", math.floor(eatAbs / 60) % 60)
    CV.case = case
    CV.replied = true

    -- LSO radio follows the case (ball call on approach freq in CASE III)
    local lso = (case == 3) and CFG.CHAN.APPROACH or CFG.CHAN.TOWER
    pcall(ab.SetLSORadio, ab, lso.hz / 1e6, "AM")

    if case == 1 then
        CV.clr = { brc = B, angels = tostring(angels), alt = alt4 }
        Ctl("MARSHAL", "MARSHAL",
            Seq(D("m", m), CFG.P, "m_vfr", "m_altimeter", D("m", alt4), CFG.P, "m_case1",
                "m_brc", D("m", B), CFG.P, "m_hold_angels", D("m", angels), CFG.P, "m_report_see_me"),
            string.format("%s, Mother is VFR, altimeter %s, CASE I recovery, BRC %s, hold angels %d, report see me.",
                m, altTxt, B, angels),
            function()
                Pilot("MARSHAL", Seq(D("p", m), CFG.P, "p_angels", D("p", angels), CFG.P, "p_wilco"),
                    string.format("%s, angels %d, wilco.", m, angels))
            end)
        SetPhase("SEEYOU")
        return
    end

    local radial = Hdg3(ab:GetRadial(case, true, true, false))
    local dme    = tostring(angels + (TRT.HOLD_DME_BASE or 15))
    local fb     = Hdg3(ab:GetFinalBearing(true))
    CV.clr = { radial = radial, dme = dme, angels = tostring(angels), eat = eat, eatAbs = eatAbs,
               brc = B, fb = fb, alt = alt4 }
    TRT.CV_EAT = eatAbs   -- for scoring (R2)

    local head, headTxt
    if case == 2 then
        head    = Seq("m_case2", "m_exp_brc", D("m", B))
        headTxt = string.format("CASE II recovery, CV-1 approach, expected BRC %s.", B)
    else
        head    = Seq("m_case3", "m_exp_fb", D("m", fb))
        headTxt = string.format("CASE III recovery, CV-1 approach, expected final bearing %s.", fb)
    end
    Ctl("MARSHAL", "MARSHAL",
        Seq(D("m", m), CFG.P, "m_altimeter", D("m", alt4), CFG.P, head, CFG.P,
            D("m", m), CFG.P, "m_marshal_on", D("m", radial), "m_radial", CFG.P, D("m", dme), "m_dme",
            CFG.P, "m_angels", D("m", angels), CFG.P, "m_eat", D("m", eat), CFG.P, "m_btn15"),
        string.format("%s, altimeter %s, %s %s, marshal on the %s radial, %s DME, angels %d, "
            .. "expected approach time %s, approach button 15.",
            m, altTxt, headTxt, m, radial, dme, angels, eat))
    SetPhase("READBACK")
end

-- ══════════════════════════════════════════════════════════════
--  MENU
-- ══════════════════════════════════════════════════════════════
local function Actions()
    local a, u, s = {}, Hero(), Ship()
    if CV.phase == "IDLE" then return a end
    if (CV.busy and CV.phase ~= "BALL") or not (u and s) then return a end
    local d = DistNM(u:getPoint(), s:getPoint())
    local ph = CV.phase
    if ph:sub(1, 4) == "DEP_" and ph ~= "DEP_AIR" and CV.dep then
        local altFt = u:getPoint().y * 3.28084
        if altFt >= CFG.POPEYE_FT and not CV.dep.popeye and not CV.dep.ontop then
            a[#a + 1] = { string.format("Departure %.2f: Popeye, angels %d", CFG.CHAN.DEPARTURE.hz / 1e6,
                math.floor(altFt / 1000 + 0.5)), A_Popeye }
        end
        if altFt >= CFG.ONTOP_FT and not CV.dep.ontop then
            a[#a + 1] = { string.format("Departure %.2f: on top, angels %d", CFG.CHAN.DEPARTURE.hz / 1e6,
                math.floor(altFt / 1000 + 0.5)), A_OnTop }
        end
        return a
    end
    if ph == "CHECKIN" then
        a[#a + 1] = { string.format("Marshal %.2f: check in (inbound)", CFG.CHAN.MARSHAL.hz / 1e6), A_CheckIn }
    elseif ph == "READBACK" then
        a[#a + 1] = { "Marshal: readback", A_Readback }
    elseif ph == "ESTABLISH" or ph == "HOLDING" then
        if ph == "ESTABLISH" then a[#a + 1] = { "Marshal: established", A_Established } end
        local c, lbl = CV.clr, "Marshal: commencing"
        if c and c.eat and c.eatAbs then
            local r = math.floor(c.eatAbs - timer.getAbsTime() + 0.5)
            local sign = (r >= 0) and "T-" or "T+"
            r = math.abs(r)
            lbl = string.format("%s (EAT :%s, %s%d:%02d)", lbl, c.eat, sign, math.floor(r / 60), r % 60)
        end
        a[#a + 1] = { lbl, A_Commencing }
    elseif ph == "SEEYOU" and d <= CFG.SEE_YOU_NM then
        a[#a + 1] = { "Marshal: see you at 10", A_SeeYou }
    elseif ph == "APP_CHECKIN" then
        a[#a + 1] = { string.format("Approach %.2f: check in", CFG.CHAN.APPROACH.hz / 1e6), A_AppCheckIn }
    elseif ph == "APPROACH" or ph == "APP_SEEYOU" then
        local alt = u:getPoint().y * 3.28084
        if ph == "APPROACH" and alt <= CFG.PLATFORM_FT then a[#a + 1] = { "Approach: platform", A_Platform } end
        if CV.case == 2 and d <= CFG.SEE_YOU_NM then a[#a + 1] = { "Approach: see you at 10", A_AppSeeYou } end
    elseif ph == "NEEDLES" then
        a[#a + 1] = { "Needles: up and on", function() A_Needles(true) end }
        a[#a + 1] = { "Needles: negative", function() A_Needles(false) end }
    elseif ph == "BALL" then
        a[#a + 1] = { "Ball (Hornet ball, state)", function() A_Ball(false) end }
        a[#a + 1] = { "Clara", A_Clara }
    end
    return a
end

local function CommCard()
    local c = CFG.CHAN
    local lines = {
        "── CV COMM CARD (COMM1, AM) ──────────",
        string.format("BTN 1   %.2f  TOWER / PADDLES", c.TOWER.hz / 1e6),
        string.format("BTN 2   %.2f  DEPARTURE", c.DEPARTURE.hz / 1e6),
        string.format("BTN 15  %.2f  APPROACH", c.APPROACH.hz / 1e6),
        string.format("BTN 16  %.2f  MARSHAL", c.MARSHAL.hz / 1e6),
        "CASE I/II: ZIPLIP on button 1 · CASE III: full voice",
    }
    if CV.clr and CV.clr.radial then
        lines[#lines + 1] = string.format("Marshal: %s R / %s DME / angels %s / EAT :%s / FB %s",
            CV.clr.radial, CV.clr.dme, CV.clr.angels, CV.clr.eat, CV.clr.fb)
    elseif CV.clr then
        lines[#lines + 1] = string.format("CASE I: BRC %s, hold angels %s", CV.clr.brc, CV.clr.angels)
    end
    Msg(table.concat(lines, "\n"), 20)
end

local lastSig = nil
MenuRebuild = function()
    local u = Hero()
    if not u then return end
    local gid = u:getGroup():getID()
    local idleHidden = CV.phase == "IDLE"
    if idleHidden or (CV.menu.root and CV.menu.gid ~= gid) then
        if CV.menu.root then pcall(missionCommands.removeItemForGroup, CV.menu.gid, CV.menu.root) end
        CV.menu.root, CV.menu.items, lastSig = nil, nil, nil
        if idleHidden then return end
    end
    local acts = Actions()
    local labels = {}
    for i, it in ipairs(acts) do labels[i] = it[1] end
    local sig = table.concat(labels, "|")
    if sig == lastSig and CV.menu.root then return end
    lastSig = sig
    if not CV.menu.root then
        CV.menu.gid  = gid
        CV.menu.root = missionCommands.addSubMenuForGroup(gid, "CV COMMS")
    end
    for _, h in ipairs(CV.menu.items or {}) do pcall(missionCommands.removeItemForGroup, gid, h) end
    CV.menu.items = {}
    for _, it in ipairs(acts) do
        CV.menu.items[#CV.menu.items + 1] = missionCommands.addCommandForGroup(gid, it[1], CV.menu.root, function()
            if CV.busy and CV.phase ~= "BALL" then return end
            it[2]()
            MenuRebuild()
        end)
    end
    CV.menu.items[#CV.menu.items + 1] =
        missionCommands.addCommandForGroup(gid, "Show: comm card", CV.menu.root, CommCard)
end

-- ══════════════════════════════════════════════════════════════
--  AIRBOSS OVERRIDES (instance fields; class methods untouched)
-- ══════════════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════════════
--  R5 — 99 CALLS, DELTA, TIME HACK, ALTIMETER (v1.5.0)
-- ══════════════════════════════════════════════════════════════
local HOLD_PHASES = { CHECKIN_SENT = true, READBACK = true, ESTABLISH = true, HOLDING = true,
                      SEEYOU = true, ZIPLIP = true }

--- Hero airborne inside the CCA: 99 calls are voiced only then (Marshal frequency).
local function Near()
    local u, s = Hero(), Ship()
    return u and s and CV.air and DistNM(u:getPoint(), s:getPoint()) <= CFG.CCA_NM
end

local function QfeInHg()
    local ab = AB()
    local ok, p = pcall(function() return UTILS.hPa2inHg(ab:GetCoordinate():GetPressure()) end)
    return ok and p or nil
end

--- "99, Mother is now CASE N recovery, BRC / expected FB, altimeter".
local function Ann99Case(case)
    local ab = AB(); if not ab then return end
    local B   = Hdg3(ab:GetBRC())
    local alt = Alt4(QfeInHg() or 29.92)
    local altTxt = alt:sub(1, 2) .. "." .. alt:sub(3, 4)
    local head, headTxt
    if case == 1 then
        head, headTxt = Seq("m_case1", "m_brc", D("m", B)), "CASE I recovery, BRC " .. B
    elseif case == 2 then
        head, headTxt = Seq("m_case2", "m_exp_brc", D("m", B)), "CASE II recovery, CV-1 approach, expected BRC " .. B
    else
        local fb = Hdg3(ab:GetFinalBearing(true))
        head, headTxt = Seq("m_case3", "m_exp_fb", D("m", fb)), "CASE III recovery, CV-1 approach, expected final bearing " .. fb
    end
    Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_mother_now", head, CFG.P, "m_altimeter", D("m", alt)),
        string.format("99, Mother is now %s, altimeter %s.", headTxt, altTxt))
end

--- Hero still in the Marshal stack when the case changes: AIRBOSS keeps the old case
-- for flights already queued, so the hero is re-marshalled with the new case
-- (new Marshal instructions via the normal MarshalReply).
local function ReMarshal(case)
    local ab, pd = AB(), HeroPD()
    if not (ab and pd and pd.group) then return end
    if not ab:_InQueue(ab.Qmarshal, pd.group) then
        Log(string.format("case -> %d: hero not in the Marshal queue (step %s), no re-marshal", case, tostring(pd.step)))
        return
    end
    Log(string.format("case %s -> %d: re-marshalling hero", tostring(pd.case), case))
    ab:_RemoveFlightFromMarshalQueue(pd, true)
    CV.clr, CV.replied = nil, false
    SetPhase("CHECKIN_SENT")
    local stack = ab:_GetFreeStack(pd.ai)
    if stack then ab:_MarshalPlayer(pd, stack) else ab:_WaitPlayer(pd) end
end

--- Time hack after "established" (CASE II/III): "mark" on the whole minute.
TimeHack = function()
    local c = CV.clr
    if not c or c.hackDone or not c.eatAbs then return end
    c.hackDone = true
    local function len(id) return (CFG.AUDIO[id] and CFG.AUDIO[id].len or 0.4) end
    local lead = len("sq_up") + 5 * 1.0                  -- countdown 5..1 at 1 s
    local now  = timer.getAbsTime()
    local first = len("sq_up") + len("m_99") + len("m_time_hack") + len("sq_dn") + 2 * CFG.GAP
    -- enqueue so that the countdown starts ~3 s after the "stand by" call
    local wait = (60 - now % 60) - lead - first - 3 - CFG.TX_GAP
    if wait < 0 then wait = wait + 60 end
    if c.eatAbs - (now + wait + first + lead) < 90 then Log("time hack skipped (EAT too close)"); return end
    timer.scheduleFunction(function()
        if CV.clr ~= c or not HOLD_PHASES[CV.phase] then return end
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_time_hack"), "99, stand by for time hack.")
        local mm
        local tx = {
            who = "MARSHAL", ch = "MARSHAL",
            gap = function()
                local g = (60 - timer.getAbsTime() % 60) - lead
                if g < 0.3 then g = g + 60 end
                return g
            end,
            seq = function()
                mm = string.format("%02d", math.floor((timer.getAbsTime() + lead + 0.5) / 60) % 60)
                local s = {}
                for n = 5, 1, -1 do
                    s[#s + 1] = "m_" .. n
                    s[#s + 1] = math.max(0, 1.0 - len("m_" .. n) - CFG.GAP)
                end
                timer.scheduleFunction(function()
                    Log(string.format("time hack mark: abs %.1f (sec %.1f), spoken %s", timer.getAbsTime(),
                        timer.getAbsTime() % 60, mm))
                end, nil, timer.getTime() + lead)
                return Seq(s, "m_mark", "m_time", D("m", mm))
            end,
            text = function() return string.format("99, five, four, three, two, one, mark, time %s.", mm) end,
        }
        CV.q[#CV.q + 1] = tx
        if not CV.busy then QNext() end
    end, nil, timer.getTime() + math.max(0, wait))
end

--- Delta: shift the hero's EAT by n minutes and reissue it.
local function DeltaEAT(n)
    local c, m = CV.clr, Modex()
    if not (c and c.eatAbs) or not (CV.phase == "ESTABLISH" or CV.phase == "HOLDING" or CV.phase == "READBACK") then return end
    c.eatAbs = c.eatAbs + n * 60
    c.eat = string.format("%02d", math.floor(c.eatAbs / 60) % 60)
    c.openShown, c.hackDone = nil, nil
    TRT.CV_EAT = c.eatAbs
    Ctl("MARSHAL", "MARSHAL", Seq(D("m", m), CFG.P, "m_new_eat", D("m", c.eat)),
        string.format("%s, new expected approach time %s.", m, c.eat))
    Pilot("MARSHAL", Seq(D("p", m), CFG.P, "p_approach_time", D("p", c.eat)),
        string.format("%s, approach time %s.", m, c.eat))
end

--- Altimeter change >= 0.02 inHg while in the stack: "99, altimeter NNNN".
local function CheckAltimeter()
    local c = CV.clr
    if not (c and c.alt and HOLD_PHASES[CV.phase] and Near()) or CV.busy then return end
    local q = QfeInHg(); if not q then return end
    local a = Alt4(q)
    if math.abs(tonumber(a) - tonumber(c.alt)) >= 2 then
        c.alt = a
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_altimeter", D("m", a)),
            string.format("99, altimeter %s.%s.", a:sub(1, 2), a:sub(3, 4)))
    end
end

local function InstallR5(ab)
    -- case change announced by the ship (also fixes AIRBOSS's 99 radial, which was
    -- computed before the new holding offset was applied)
    ab._MarshalCallRecoveryStart = function(self, case)
        local prev = CV.annCase
        CV.annCase = case
        Log(string.format("recovery start CASE %s (previous %s)", tostring(case), tostring(prev)))
        if prev == case or not CV.air then return end      -- v1.5.1: any range
        Ann99Case(case)
        timer.scheduleFunction(function() pcall(ReMarshal, case) end, nil, timer.getTime() + 2)
    end
    ab._MarshalCallRecoveryStopped = function(self, case)
        local tr = TRT.CaseSync and TRT.CaseSync.tRebuild
        if (tr and timer.getTime() - tr < 90) or not Near() then return end   -- case rebuild: silent
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_deck_closed"), "99, recovery complete, deck is closed.")
    end
    ab._MarshalCallNewFinalBearing = function(self, fb)
        if CV.clr then CV.clr.fb = Hdg3(fb) end
        if not Near() then return end
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_new_fb", D("m", Hdg3(fb))),
            string.format("99, new final bearing %s.", Hdg3(fb)))
    end
    ab._MarshalCallCarrierTurnTo = function(self, hdg)
        if not Near() then return end
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_turning", D("m", Hdg3(hdg))),
            string.format("99, Mother turning to %s.", Hdg3(hdg)))
    end
    local function pausedHold()
        if not Near() then return end
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_delta_hold"),
            "99, Delta. Recovery paused, hold and conserve fuel, expect further instructions.")
    end
    ab._MarshalCallRecoveryPausedUntilFurtherNotice = function(self) pausedHold() end
    ab._MarshalCallRecoveryPausedNotice = function(self) pausedHold() end   -- MOOSE calls this (undefined there)
    ab._MarshalCallRecoveryPausedResumedAt = function(self, clock)
        local h, mi = tostring(clock):match("^(%d+):(%d+)")
        local n = 1
        if h then
            local tRes = tonumber(h) * 3600 + tonumber(mi) * 60
            local now  = timer.getAbsTime() % 86400
            n = math.max(1, math.ceil(((tRes - now) % 86400) / 60))
        end
        Log("recovery paused, Delta " .. n)
        if not Near() then return end
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_delta", D("m", n), CFG.P, "m_plus", D("m", n), "m_minutes"),
            string.format("99, Delta %d. Approach times plus %d minutes.", n, n))
        DeltaEAT(n)
    end
    ab._MarshalCallResumeRecovery = function(self)
        if not Near() then return end
        Ctl("MARSHAL", "MARSHAL", Seq("m_99", "m_resume"), "99, recovery resumed, commence at your approach time.")
    end
end

local function IsHeroModex(modex)
    local pd = HeroPD()
    return pd and pd.onboard and tostring(modex) == tostring(pd.onboard)
end

local function InstallHooks()
    local ab = AB()
    if not ab or CV.hooked then return CV.hooked end

    -- 1) Marshal reply
    local origArrived = ab._MarshalCallArrived
    ab._MarshalCallArrived = function(self, modex, case, brc, altitude, charlie, qfe)
        if not IsHeroModex(modex) then return end      -- AI flights: silent
        local pd = HeroPD()
        local ok, err = pcall(MarshalReply, case, brc, altitude, pd and pd.Tcharlie, qfe)
        if not ok then
            Log("MarshalReply error: " .. tostring(err) .. " -> AIRBOSS default call")
            return origArrived(self, modex, case, brc, altitude, charlie, qfe)
        end
    end

    -- 2) "Cleared for Case X recovery" (Charlie) -> text only for the hero
    local origCleared = ab._MarshalCallClearedForRecovery
    ab._MarshalCallClearedForRecovery = function(self, modex, case)
        if not IsHeroModex(modex) then return origCleared(self, modex, case) end
        if case == 1 then
            local c = CV.clr or {}
            if not c.charlieShown then
                c.charlieShown = true
                Msg("[CV] Signal Charlie — leave the stack at the port beam (9 o'clock, ~4.75 NM from the ship), "
                    .. "descend, then proceed to the initial (ZIPLIP, no call).", 15)
            else
                Msg("[CV] AIRBOSS has not seen you commence: pass the port-beam point (9 o'clock, 4.75 NM, "
                    .. "1 NM radius) before the initial, or the pass is INVALID.", 15)
            end
        else
            local c = CV.clr
            if c and c.openShown then return end           -- v1.4.2: once per pass
            if c then c.openShown = true end
            local eat = c and c.eat
            local late = c and c.eatAbs and timer.getAbsTime() >= c.eatAbs
            Msg(string.format("[CV] Recovery open%s.", not eat and ""
                or late and (" — EAT :" .. eat .. " passed, commence now")
                or (" — commence at EAT :" .. eat)), 10)
        end
    end

    -- 3) Marshal text messages without Raynor USERSOUND
    local origMsg = ab.MessageToPlayer
    ab.MessageToPlayer = function(self, pd, message, sender, receiver, duration, clear, delay)
        if sender ~= "MARSHAL" or self.SRS or not pd or not message or message == "" then
            return origMsg(self, pd, message, sender, receiver, duration, clear, delay)
        end
        if delay and delay > 0 then
            timer.scheduleFunction(function()
                self:MessageToPlayer(pd, message, sender, receiver, duration, clear, 0)
            end, nil, timer.getTime() + delay)
            return
        end
        local text
        if receiver == "" then text = message
        else text = string.format("%s, %s", receiver or pd.onboard, message) end
        if pd.client then
            MESSAGE:New(text, duration or self.Tmessage, sender, clear):ToClient(pd.client)
        end
    end

    -- 4) ZIPLIP: drop LSO ball / roger ball / paddles contact for the hero in CASE I/II
    local origRT = ab.RadioTransmission
    CV.origRT = origRT
    ab.RadioTransmission = function(self, radio, call, ...)
        local f = call and call.file
        if f and not CV.allowRB then
            if CFG.ALWAYS_DROP[f] then return end
            local pd = HeroPD()
            if pd and (pd.case == 1 or pd.case == 2) and CFG.ZIPLIP_DROP[f] then return end
            if f == "LSO-RogerBall" then return end      -- CASE III: CV plays it after the ball call
        end
        return origRT(self, radio, call, ...)
    end

    -- 5) R5: 99 calls, Delta, time hack (v1.5.0)
    InstallR5(ab)
    CV.annCase = ab.case

    CV.hooked = true
    Log("AIRBOSS hooks installed")
    return true
end

-- ══════════════════════════════════════════════════════════════
--  EVENTS / TICK
-- ══════════════════════════════════════════════════════════════
local function Reset(reason)
    CV.q, CV.clr, CV.case, CV.tRadar, CV.tBallAsk = {}, nil, nil, nil, nil
    CV.dep, CV.depActive, CV.sawGroove, CV.bolter = nil, false, false, nil
    CV.wasOutside = false
    SetPhase("IDLE")
    Log("reset (" .. reason .. ")")
end

local EH = {}
function EH:onEvent(e)
    if not e.initiator or not e.initiator.getName then return end
    local ok, name = pcall(e.initiator.getName, e.initiator)
    if not ok or name ~= CFG.PLAYER_UNIT then return end
    if e.id == world.event.S_EVENT_TAKEOFF then
        CV.air, CV.tAir = true, timer.getTime()
        Reset("takeoff")
        local u, s = Hero(), Ship()
        if u and s and DistNM(u:getPoint(), s:getPoint()) <= 3 then
            local c = CaseNow()
            Log("carrier launch, CASE " .. tostring(c))
            if c == 3 then
                timer.scheduleFunction(function() pcall(DepStart) end, nil, timer.getTime() + 2)
            end
        end
    elseif e.id == world.event.S_EVENT_LAND then
        CV.air = false
        Reset("landed")
    elseif e.id == world.event.S_EVENT_BIRTH then
        CV.air = false
        Reset("birth")
    end
end
world.addEventHandler(EH)

local function Tick(_, t)
    local ok, err = pcall(function()
        if not CV.hooked then InstallHooks() end
        local u, s = Hero(), Ship()
        if not (u and s) then return end
        if not CV.air and u:inAir() then CV.air, CV.tAir = true, timer.getTime() end
        local d = DistNM(u:getPoint(), s:getPoint())
        if d > CFG.CCA_NM then CV.wasOutside = true end
        local pd = HeroPD()
        if CV.phase:sub(1, 4) == "DEP_" and CV.phase ~= "DEP_AIR" then
            DepTick(u, s, d)
        elseif CV.phase == "IDLE" and CV.air and d <= CFG.CCA_NM and not CV.depActive then
            local long = CV.tAir and (timer.getTime() - CV.tAir) >= CFG.ARM_AIRBORNE
            if CV.wasOutside or long then SetPhase("CHECKIN") end
        elseif CV.phase == "CHECKIN_SENT" and not CV.busy and not CV.replied then
            SetPhase("CHECKIN")      -- AIRBOSS refused (message shown) -> offer again
        elseif CV.phase == "PENETRATION" and CV.tRadar and not CV.busy
               and timer.getTime() - CV.tRadar >= CFG.SWITCH_APP_MIN then
            local alt = u:getPoint().y * 3.28084
            if alt <= CFG.SWITCH_APP_FT or d <= CFG.SWITCH_APP_DME then C_SwitchApproach() end
        elseif CV.phase == "FINAL" and not CV.busy and d <= CFG.ACLS_NM then
            C_AclsLock()
        elseif CV.phase == "NEEDLES" and not CV.busy and timer.getTime() - CV.tPhase >= CFG.NEEDLES_TIMEOUT then
            C_FlyBullseye()
        elseif CV.phase == "GROOVE" and pd and type(pd.step) == "string" and pd.step:sub(1, 6) == "Groove" then
            CV.sawGroove = true
        elseif CV.phase == "GROOVE" and CV.sawGroove and pd and (pd.step == AIRBOSS.PatternStep.BOLTER
               or pd.step == AIRBOSS.PatternStep.BULLSEYE or pd.step == AIRBOSS.PatternStep.DIRTYUP) then
            Log("bolter / wave-off (AIRBOSS step " .. tostring(pd.step) .. ")")
            CV.sawGroove = false
            if CV.case == 3 then C_BolterStart() else SetPhase("BALLWAIT") end
        elseif CV.phase == "B_DOWNWIND" and not CV.busy and pd and CV.bolter then
            local ok, X = pcall(AB()._GetDistances, AB(), pd.unit)
            if ok and X and X <= 0 and math.abs(ADiff(MagHdg(u), CV.bolter.dw)) <= 45 then C_BolterAbeam() end
        elseif CV.phase == "BALLWAIT" and SternNM() <= CFG.BALL_NM and Astern()
               and math.abs(ADiff(MagHdg(u), AB():GetFinalBearing(true))) <= 45 then
            C_CallBall()
        elseif CV.phase == "BALL" and CV.tBallAsk and timer.getTime() - CV.tBallAsk >= CFG.BALL_AUTO then
            A_Ball(true)
        end
        if not CV.tAltChk or timer.getTime() - CV.tAltChk >= 60 then   -- v1.5.0
            CV.tAltChk = timer.getTime()
            CheckAltimeter()
        end
        if pd then
            if pd.step ~= CV.abStep then
                Log("AIRBOSS step " .. tostring(CV.abStep) .. " -> " .. tostring(pd.step)
                    .. string.format(" (%.1f NM, %d ft)", d, math.floor(u:getPoint().y * 3.28084)))
                CV.abStep = pd.step
            end
            if pd.holding ~= CV.abHold then
                Log("AIRBOSS holding " .. tostring(CV.abHold) .. " -> " .. tostring(pd.holding))
                CV.abHold = pd.holding
            end
        end
        MenuRebuild()
    end)
    if not ok then Log("tick error: " .. tostring(err)) end
    -- fast tick in the last miles (ball call timing)
    if CV.phase == "BALLWAIT" or CV.phase == "BALL" or CV.phase == "NEEDLES" then return t + 0.5 end
    return t + CFG.TICK
end
timer.scheduleFunction(Tick, nil, timer.getTime() + 3)

Log("v" .. CFG.VERSION .. " loaded")
