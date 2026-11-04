-- Comms_Director | v1.11.0
--[[
  v1.11.0 - P4 XCAS (decisions Onur 2026-11-04 14:34; CAS_PACK.xcas set by Tasking_Pick >= v1.4.0, OFF by default):
           * check-in "checking in as fragged, XCAS" / OVERLORD "close air support on call" (no JTAC names, no
             mission numbers); OVERLORD gives the mission number with the tasking ("Mission 4137. Axeman 11 is on
             station ...", also in the divert call), the pilot reads it back ("Mission 4137, push button 10,
             Hornet 51."); a resumed tasking gets no number again
           * off / lost comms "cancelled" / INFLTREP speak the generated numbers from digit clips
           * C divert voiced for any pair (ovl_divert_a + ovl_dv_<cn> + ovl_adv_<ck>; "unable" ovl_dvu_<ck>);
             Pointer -> Eyeball without XCAS keeps the v1.8 clips
           Without XCAS nothing changes for Pointer + Eyeball.
  v1.10.1 - JTAC roster P3 (pack v1.3.0: AXEMAN 11 J3, DARKNIGHT 11 J4): CD.tasked from CAS_PACK.tasked (Tasking_Pick
           >= v1.3.0). The OVERLORD check-in clips name Pointer 11 / Eyeball 11 and missions 4101 / 4102: any other
           tasked pair gets that exchange as text only (P4 replaces it with the XCAS check-in). INFLTREP line 2 and
           the remarks are chained from digit clips for another pair (new i_l2_a, i_rmk_msn, i_rmk_inc_b,
           i_rmk_can_b). CFG.AUDIO + the
           roster clips (tools/roster_clips.py, tools/jc_clips.py v1.6.0).
  v1.10.0 - JTAC roster (P2, plan claude/jtac-roster-effects-plan-2026-11-04.md; zero behaviour change for the pack
           roster { J1, J2 }): every JTAC of CAS_PACK.order gets its phases from its roster index n - "JTAC<n>" (working
           it) and "<key>_OFF" (that tasking ended); buttons, frequencies, alternates, voice and MUD channels, F10
           items, NEXT / REMIND, target tracking (CD.dead[k] / CD.seen[k] / CD.jd[k], aliases deadJ1 / seenJ1 / j1 ...
           kept for Flight_Timeline / Pilot_Banter / Flight_Report) are built per roster key. CD.tasked = the two
           taskings of the sortie in fragged order (slots; P2: the first two roster keys, P4 picks them at random);
           scenarios A / B / C, TIC, lost comms, INFLTREP and the OVERLORD check-in work on CD.tasked: C diverts from
           slot 1 to slot 2 (the TIC JTAC). Injects (abort / rearm / MANPADS) belong to the pack JTAC with
           injects = true (Eyeball 11). Clip ids for keys other than J1 / J2 come from the pack's cn / ck; missing
           clips fall back to text. Pack >= v1.2.1 (cn, injects).
  v1.9.2 - CFG.AUDIO: pj_ / ej_w_desired_destroy, _withdrawing, _location, _still_threat (Piper, same voices).
           effects-based tasking (JTAC_Controller v0.15.0): a JTAC tasking whose objective is destroyed (TRT.JC.st[k]
           .objDone) counts as "target dead" (deadJ1 / deadJ2) even when units of the group are left (withdrawing /
           remaining) - TIC BDA, VUL, Pilot_Banter and Flight_Timeline follow it as before.
  v1.9.1 - CFG.AUDIO: pj_ / ej_lab_sp_howitzer(_pl) (target pool, JTAC_Controller v0.14.1 label
           "self-propelled howitzer"; Piper, same voices, rendered 2026-11-04).
  v1.9.0 - tasking pack (decision Onur 2026-11-04, plan claude/target-pool-tasking-pack-plan-2026-11-04.md): names,
           positions, call signs, buttons, frequencies, mission numbers, JTAC target groups and the friendly unit come
           from CAS_PACK (scripts/CAS_Pack.lua, loaded before this file); missing pack -> env.error, module not
           started. Text that named Pointer 11 / Eyeball 11 / Bravo 2-1 literally now uses the pack values; the COMM
           card buttons too. No behaviour change: scenario_test radio logs identical to v1.8.4.
  v1.8.4 - menu items open when the call they answer STARTS (Onur, TEST-J1-A-SPFboth 2026-11-03: items showed up
           only after the clip had ended, a player who opens F10 right after the call finds nothing). The queue is
           FIFO, so a reply pressed while the call is on the air is transmitted after it; timers that measure the
           pilot still start at the end of the call.
           * Q(..., ack): automatic pilot acknowledgements (Ack, ReadBack, the TIC "push button, buster" /
             "copy troops in contact", JTAC_Controller's own acks) are marked ack and do not hold the menu.
           * Non-urgent COMMS items are hidden only while a non-ack transmission is still WAITING in the queue
             (GateWaiting, exported as CD.gateWaiting); the one on the air no longer hides them (was RadioIdle).
           * OVERLORD tasking / retasking: the JTAC phase starts when OVERLORD's "contact <JTAC>, push button N"
             starts (was: the end of the pilot's push readback). TIC: the check-in opens when the JTAC's "check in
             when ready" starts. TIC BDA: OVERLORD items open when Bravo 2-1's thanks starts. Lost comms tech: the
             alternate frequency is set when OVERLORD's "contact on alternate" starts. C divert: OVERLORD breaks in
             when nothing is waiting (the call on the air ends first); wilco / unable open when the divert starts.
           * JTAC tasking ended (JTAC_Controller DONE / TERMINATED event) -> J1_OFF / J2_OFF at once (was: the next
             5 s tick), so "OVERLORD: off <JTAC>" opens while the BDA is on the air.
  v1.8.3 - flight 2026-11-03 (Onur): the pilot's "negative Texaco, state X.X, proceeding CP TIGER" (skip AR1) is voiced
           (p_ovl_neg_tkr_a + state tokens + p_ovl_off_tkr_b); it was text only.
  v1.8.2 - CFG.AUDIO: spoofed-abort / AUTHENTICATE clips (pj_/ej_ iauth, spf_dis, spf_neg, spf_adv; jp_auth_ptr /
           jp_auth_eye) for JTAC_Controller v0.13.0. No logic change.
  v1.8.1 - CFG.AUDIO: pilot clip jp_abort_ack ("Hornet five one, aborting.") for JTAC_Controller v0.12.0
           (tools/jc_clips.py --audio-into-cd). No logic change.
  v1.8.0 - tasking scenarios and radio-flow gates (decisions Onur 2026-11-03, project doc
           claude/tasking-scenarios-2026-11-03.md):
            * The JTAC order is a list (CD.order), not the phase chain: JTAC1 / JTAC2 = "working Pointer / Eyeball",
              J1_OFF / J2_OFF = "that tasking ended"; the F10 item there is "off <JTAC>, ready for retasking" while
              a tasking remains, else INFLTREP. CD.res[key] = done | incomplete | terminated | cancelled | skipped;
              CD.vulDone / vulT when every tasking has ended (Flight_Timeline T3, Pilot_Banter); CD.vulExtS = C2 delay.
            * Scenario picked once at the OVERLORD check-in (40 / 30 / 30): A Pointer -> Eyeball; B "hold at CP TIGER,
              angels 22, expect tasking in five minutes", then a random JTAC first ("Hornet 51, Overlord, tasking.");
              C Pointer first, OVERLORD breaks in on COMM2 during the Pointer 9-line dialogue: "divert, divert,
              Eyeball 11 reports troops in contact ... Pointer 11 is advised" -> F10 wilco (pilot tells Pointer 11,
              Pointer 11 holds, "no other CAS available") or unable (state); fuel guard; after Eyeball 11 the hero
              returns to Pointer 11 for a fresh check-in. ME flags 210-212 force them (test variants), 213 = picked.
            * Lost comms (A / B, ~12 % of sorties, never the TIC JTAC; or the JTAC unit dead): JTAC_Controller keeps
              the JTAC silent; after two calls F10 "OVERLORD: unable contact <JTAC>" -> "stand by" -> tech: "radio
              failure on primary, contact on alternate, push button 9 / 11" (CHAN switched) | down: "off the net,
              unable to raise, mission 41xx cancelled" -> next tasking or "say intentions" (INFLTREP).
            * Winchester cancels the remaining taskings (nothing left to drop).
            * AR1 tanker lost or no-show (0.1 %): "Texaco 11 is off station, no tanker available. Say intentions."
              -> F10 continue without tanker / RTB / divert (was "Proceed CP TIGER").
            * Radio-flow gates: Q(..., onEnd, tag) runs onEnd when the transmission has ENDED; QClear / QDrop still
              run the dropped items' onEnd (gates never stick). A JTAC phase starts at the end of the pilot's
              push-button readback; the TIC check-in at the end of the JTAC's "check in when ready" call.
  v1.7.13 - CAS (L) sortie 2026-11-02/03 (Onur):
            * WINCHESTER (JTAC_Controller >= v0.10.0): a JTAC tasking that ends DONE with targets still alive
              (st.incomplete) counts as finished like TERMINATED: JTAC1 -> J1_OFF, JTAC2 -> J2_OFF. J2_OFF then
              offers the INFLTREP and the AR2 tanker as usual (2026-11-02: the hero had no bomb for Eyeball's last
              target, no menu item led out, he called "mission abort" and AR2 had no OVERLORD control). The
              hand-off text says "checked out, Winchester"; no Bravo 2-1 "fire has stopped" call while targets
              remain. INFLTREP: line 5 = units actually destroyed, remarks + "Mission 41xx incomplete, Winchester."
              (clips i_rmk_inc1 / i_rmk_inc2). Time on target = check-out time when the group is not dead.
            * Strike speed calls (warn / brass) get the pilot's "Hornet 51, wilco." (p_wilco); 2026-11-02 the
              "Check speed" call had no answer.
            OPEN: a Winchester at Pointer (JTAC-1) still goes to Eyeball on OVERLORD's retasking (pilot line
            "mission 4101 complete"); with six weapons for six targets this needs four misses at Pointer.
  v1.7.12 - report card: CD.ticState.callT (timer.getTime() of the JTAC's TIC call), CD.corridorMz = true when
            Strike made the "still off the corridor" call at the Marshal hand-off.
  v1.7.11 - CAS (L) sortie 2026-11-02 (Onur):
            * MUD call on a JTAC frequency gets a JTAC "Hornet 51, copy." (JTAC_Controller voice, TRT.JC.voice);
              before, only OVERLORD answered and a MUD on Pointer / Eyeball went unanswered.
            * Strike corridor call reworded: "You are off the inbound corridor. Intercept the zero five zero
              radial inbound." ("Turn now to zero five zero" read as heading 050, away from Mother).
            * At the Strike -> Marshal hand-off (~50 NM) a hero still outside the corridor gets
              "You are inside fifty miles and still off the corridor. Intercept the zero five zero radial now."
              (str_corridor_mz) before "Marshal, push button 16". Not scored. 2026-11-02: corridor called at
              78 NM, hero entered the Marshal Zone on R-079 with no further call.
            * CD.speedCall(kind) for Overspeed_Penalty v7.5.0: while the hero is still on Strike (STRIKE_IN /
              INBOUND), Strike calls "check speed, three fifty knots maximum inside fifty miles" (warn) and
              "you are still fast ... that goes in the debrief" (brass, first penalty). Marshal / Approach
              phases are CV_Comms' (TRT.CV.speedCall).
            * TIC: CD.ticState.ready = true once the JTAC's "check in when ready for nine-line" has played;
              JTAC_Controller >= v0.8.1 offers the TIC JTAC's check-in only then.
  v1.7.10 - Traffic.lua (Onur, 2026-11-01): TEXACO's RV Alpha reply appends TRT.Traffic.TkrRemark() when AI
            receivers are queued at the tanker ("Two receivers ahead of you, join echelon left."). The queue's
            own Texaco / AI calls go through TRT.CD_RADIO; their clips are in CFG.AUDIO (tq_*, a41_*, a42_*).
  v1.7.9 - Onur, 2026-11-01:
           * TEXACO "you received X" CFG.TKR.RCVD_FULL_S (5) s after the disconnect when the hero is full
             (>= CFG.TKR.RCVD_FULL_LB). A partial fill keeps the v1.7.7 rule (0.3 NM sideways departure or
             RCVD_WAIT 60 s). The v1.7.7 reconnect withdrawal is unchanged.
           * MUD calls (CFG.MUD): the first time a SAM site's radar tracks the hero (Unit.getRadar target =
             hero; fallback: a fire-control radar emitting with the hero inside CFG.MUD.TYPES[..].trNm and in
             terrain LOS) the pilot calls on the frequency he is working: "Hornet 51, mud six, 090."
             (brevity MUD: RWR ground threat displayed, type and magnetic bearing). One call per site, again only
             after the site was silent for REARM_S. Put at the head of the radio queue. OVERLORD answers
             "Hornet 51, Overlord, copy."; Strike / JTACs do not answer. No calls in DEPARTURE / RECOVERY.
             Not verified in DCS [V]: getRadar() target for AI SAM radars; the trNm values are approximate.
             Every detection is logged: [CD] MUD ...
  v1.7.8 - Pilot_Banter v2.0.0 (CAS (L) only) talks much more: ChatPump holds unsolicited calls while
           TRT.PB.busyUntil is in the future (the pilot's own line ends first; a line is <= ~15 s, CHAT_TTL
           still applies). Replies and every queued exchange are unchanged. Without Pilot_Banter: no change.
  v1.7.7 - TEST-AAR 2026-10-31 (Onur): a 10 s first contact, a 33 s gap, then the fill. "You received 0.5" came
           30 s after the first disconnect, 3 s before the reconnect, and hid the breakaway / spokes items.
           Now: CFG.TKR.RCVD_WAIT 30 -> 60 s, and a new contact after "you received" (before "TEXACO: state")
           withdraws the report: the menu goes back to the contact items and TEXACO reports the session total
           again after the last disconnect.
  v1.7.6 - AAR branch calls and tanker loss (Onur, 2026-10-31; project doc claude/aar-realism-review-2026-10-31.md):
           * F10 "TEXACO: execute overrun" (RV / join, before the first contact): pilot "Texaco 11, execute
             overrun" [A 2.4a]. When the hero is again >= CFG.TKR.OVR_BEHIND_NM behind the tanker, TEXACO
             "Hornet 51, terminate overrun" [A 2.4c]. An AAR_Monitor overrun without the call -> on-screen hint.
           * F10 "TEXACO: breakaway" (inside 1 NM, until "you received"): pilot "Texaco 11, breakaway x3"
             (tanker callsign first, 2P note 10). When out of contact and >= CFG.TKR.BKW_CLEAR_NM from the tanker
             (or after CFG.TKR.BKW_MAX_S) TEXACO "terminate emergency separation" + pilot ack [A 2.32, 2P s.13-15].
           * F10 "TEXACO: spokes" (after a contact): pilot "Hornet 51, spokes" -> TEXACO "copy spokes. Disconnect,
             check engine instruments." [A 2.28f, 2P s.16]. Hint: damage -> divert.
           * Tanker loss: the tanker unit gone (or life < 1) after it existed -> OVERLORD, once, in an OVERLORD
             phase where the tanker mattered: AR1 open -> "Texaco 11 is off station, no tanker available. Proceed
             CP TIGER." (AR1 closed); RV open / REFUEL / J2_OFF -> "... Say intentions." INFLTREP with the tanker
             lost -> "copy INFLTREP. No tanker available. Say intentions." CD.tkrLost is read by Flight_Timeline
             >= v1.1.4 (station BINGO becomes the direct LTAG value).
  v1.7.5 - Divert to Incirlik hands over to Field_Arrival (Onur, 2026-10-31; project doc
           claude/divert-arrival-2026-10-31.md). With Field_Arrival loaded and a field it supports
           (TRT.FA.Supports(key)), OVERLORD now says "Proceed direct. Contact Ankara Control, 240.8." and the
           pilot "proceeding direct, switching Ankara"; after the readback TRT.FA.Start(key, { minFuel })
           runs the Ankara -> Incirlik Approach -> Tower -> Ground chain (no native ATC). Fields without
           Field_Arrival data (LCRA) keep the v1.7.4 tower hand-off. The next-call text yields to Field_Arrival
           while it is active. Exports TRT.CD_AUDIO / TRT.CD_SND_DIR (clip sharing, as TRT.CV_AUDIO).
           New clips: ovl_div_b_ltag_ank, p_div_rb_ltag_ank.
  v1.7.4 - AAR calls against ATP-56 (project doc claude/aar-realism-review-2026-10-31.md; Onur, 2026-10-31):
           * 29.92 / "flight level" for the AAR exchange [A 2.2a]: OVERLORD "Texaco 11 bears BBB for RR, flight
             level 150. Vector HHH, maintain flight level 140"; TEXACO no longer passes the mission QNH.
             FL = tanker true altitude rounded to 1,000 ft (the tanker AI holds TRUE MSL; on 29.92 the cockpit
             shows ~+300 ft in this mission's cold air).
           * RV Alpha vectors [A 2A.2, 2A.3]: magnetic heading (5 deg steps) to intercept the point 1 NM behind the
             tanker (straight-line lead on the tanker velocity, own speed >= 250 kt), in the first call and in the
             20 / 10 / 5 NM updates ("Hornet 51, vector HHH, Texaco bears BBB for RR"). Pilot readback carries it.
           * RV initial: pilot adds "Mode 3 <CFG.TKR.MODE3>" (kneeboard squawk 2042); TEXACO answers "RV Alpha,
             flight level 150, R.R available" [A 2O-1 e, 2P serial 2, 2A.2d].
           * "Clear to leave" acknowledged by the pilot ("Hornet 51.") [A 2P serial 19].
           * Divert: OVERLORD "Proceed direct" (was the ATC word "Cleared direct"); below BINGO - 200 lb the pilot
             adds "minimum fuel" [OPNAV M-3710.7 6.2.6]; the next-call hint tells the pilot to repeat it to tower.
  v1.7.3 - OVERLORD divert branch (project doc aar-plan s.7, s.9). F10 "OVERLORD: bingo / divert (nearest field)"
           in ENROUTE, JTAC1, J1_OFF, JTAC2, J2_OFF, REFUEL, TKR_DONE, RTB (OVERLORD control). Field = nearer of
           Incirlik (LTAG) / Akrotiri (LCRA) from the hero, CFG.DIVERT.FIELDS. The pilot says "bingo" only when
           the fuel is at or below the Flight_Timeline BINGO of the current zone (TRT.TL.thresholds, + BINGO_TOL_LB):
             HORNET 51: Overlord, Hornet 51, [bingo,] diverting Incirlik, angels N, state X.Y.
             OVERLORD:  Hornet 51, Overlord, copy divert. Incirlik bears BBB for RR. Cleared direct.
                        Contact Incirlik tower, 360.1.
             HORNET 51: Hornet 51, cleared direct, switching Incirlik tower.
           -> phase DIVERT: no JTAC / tanker / Strike / Marshal hand-offs; landing (S_EVENT_LAND) -> DONE.
           The landing itself is native DCS ATC. Tower UHF 360.100 (LTAG) / 252.000 (LCRA) from the DCS Syria
           terrain data as exported by pydcs [K]; not checked in the ME. CD.divert = { t, field, name, lb, bingo,
           isBingo, from, dNm } is read by Flight_Timeline >= v1.1.2. STRIKE_IN / INBOUND / RECOVERY: no item
           (Strike / Marshal control; CV_Comms "signal bingo" covers the recovery).
  v1.7.2 - Judy reply: OVERLORD "Hornet 51, Overlord, copy." (clip ovl_copy_51). "Copy Judy, Texaco is yours" was
           invented phraseology: Judy is a one-way receiver call (ATP-56 Annex 2P serial 3: no tanker reply;
           brevity JUDY = controller minimizes transmissions). Clip ovl_judy removed (csv, AUDIO, ogg).
  v1.7.1 - AR1 hand-off hold (TEST-AAR, Onur, 2026-10-30): the AR1 anchor is ~11 NM from CP TIGER, inside the
           20 NM POINTER hand-off ring, so ENROUTE handed off to POINTER at once and "request Texaco" never
           showed. Now, while a tanker exists, the hand-off waits until AR1 is closed: "off Texaco" or the new
           F10 "OVERLORD: skip AR1 (no top-off)". CFG.TKR.AR1_HOLD = false restores the old ring-only hand-off.
           Next-call hint names both items.
  v1.7.0 - EMCON 2 tanker radio (project doc aar-plan s.9 v2), plan C: AR1 top-off before the VUL, AR2 after.
           The native DCS tanker exchange (intent to refuel / ready pre-contact / abort) stays; it cannot be
           silenced and without it there is no contact. The script talks only where native DCS does not:
             AR1: ENROUTE, F10 "OVERLORD: request Texaco (AR1 top-off)" -> pilot request -> OVERLORD
                  "Texaco 11 bears BBB for RR, angels 15. Maintain angels 14. TACAN 21Y. Texaco, button 7."
                  The JTAC-1 hand-off (20 NM from CP TIGER) is held while AR1 is open (the anchor is 11 NM
                  from CP TIGER). F10 "OVERLORD: off Texaco" closes AR1 (also usable to cancel it).
             AR2: INFLTREP reply now carries the same vector ("Maintain angels 14").
             Both: pilot readback "angels 14, push button 7" | F10 TEXACO "RV initial" (angels, TACAN, nose
                  cold, switches safe, state, request) -> TEXACO "angels 15, altimeter <mission QNH>,
                  <request> available" | OVERLORD "Texaco bears BBB for RR" at 20 / 10 / 5 NM until Judy |
                  F10 "OVERLORD: Judy" -> "copy Judy, Texaco is yours" | silent join / contact (EMCON 2,
                  native calls only) | after the last disconnect (AAR_Monitor session, departure at 0.3 NM
                  or 30 s) TEXACO "you received X.X" | F10 "TEXACO: state" -> "clear to leave".
             AR2: REFUEL -> TKR_DONE at "clear to leave" (fallback: TRT.onRefuelComplete as before).
           Removed: clips tkr_checkin ("Port drogue": EMCON 1 content, and ATP-56 puts a single receiver
           on the right hose), tkr_done, p_tkr_checkin_a, ovl_texaco_freq (unused since v1.6.5).
           A call is voiced only if every clip of it exists (Voiced()); new clips in tts/clips.csv must be
           rendered on the PC (python tts/make_clips.py, paste tts/audio_table.lua into CFG.AUDIO). Until then
           the new calls, and the AR2 INFLTREP reply (new token o_maintain), are subtitle-only.
           Not yet: overrun / breakaway / spokes / divert calls (plan s.9 branch calls).
           "You received" needs AAR_Monitor >= v1.1.0 (TRT.AAR); without it the RV stops at Judy and AR2 ends via
           TRT.onRefuelComplete as before.
  v1.6.6 - card data: COMM1 btn 8 = ARCO 31 (252.30 AM, CVN recovery tanker) added to the F10 info card.
  v1.6.5 — tanker dialogue removed (TEST flight #5, Onur, 2026-10-30). The DCS tanker AI ignored a
           silent pre-contact with the probe out, so the native DCS "intent to refuel" call is needed
           anyway; the scripted TEXACO check-in duplicated it, and "offload complete" fired as soon as
           Core_Scoring's refuel score (TRT.onRefuelComplete) came in, while the pilot still wanted fuel.
           Now: OVERLORD still routes to Texaco (INFLTREP reply, TACAN, button); no TEXACO F10 item, no
           Texaco radio calls, no REFUEL reminder; refuel complete -> TKR_DONE silently (RTB item then
           says "off Texaco"). Load log line fixed (said v1.6.3 under v1.6.4).
  v1.6.4 — JTAC_Controller v0.7.0 voice: TRT.CD_RADIO.len(id) / has(id) (clip length or nil, "cv:" ids
           via TRT.CV_AUDIO), so JC can check every clip of a sequence before it queues it.
           CFG.AUDIO now also carries the JC token clips (pj_* POINTER, ej_* EYEBALL, jp_* pilot,
           ovl_rep_* OVERLORD), generated by tools/jc_clips.py + tts/make_clips.py.
  v1.6.3 — hard deck 23,000 -> 20,000 ft MSL (Onur, 2026-10-29): it clears every short-range threat
           covering the two target areas (SA-8 ~16,500 ft the highest) and leaves room for AGM-65E
           attacks. Texts and clips eye_manpads / ovl_checkin_b / p_ovl_checkin_rb re-rendered
           ("two zero thousand"). SAM_FireGate v1.5.3 ceilings 22,000 -> 19,000 ft to match.
           Hard deck violations stay unscored (decision 2026-10-29).
  v1.6.2 — JTAC_Controller v0.2.0: a JTAC in phase TERMINATED (two unauthorized releases) ends the
           JTAC1 / JTAC2 phase like a destroyed target group. With JTAC_Controller the on-screen
           "tasking complete" hint waits 8 s (it came before the JTAC's BDA in the 2026-10-29 flight).
  v1.6.1 — air start (test variants, tools/make_test_variant.py): on the first tick with the hero
           in the world, if it is airborne (> CFG.AIRSTART.ALT_AGL_M AGL, > CFG.AIRSTART.SPD_MS) and
           more than CFG.AIRSTART.NM from the carrier, the departure / Strike / OVERLORD check-in legs
           are skipped (text only, no voice):
             * first route point of the hero's group named "AIRSTART J2" -> straight to JTAC2
               (OVERLORD "contact Eyeball 11" + the TIC hand-off when Eyeball is the TIC JTAC)
             * any other air start ("AIRSTART J1" or no tag)            -> ENROUTE (Pointer hand-off
               at JTAC_HANDOFF_NM from CP TIGER as usual)
           CD.airStart = "J1" / "J2" (read-only for other modules). A deck start is unchanged.
  v1.6.0 — scripted JTAC (JTAC_Controller v0.1.0, plan claude/jtac-plan-2026-10-29.md):
           * TRT.CD_RADIO = { Q, QPlay, Msg } exports the clip queue, so JTAC_Controller
             transmissions are serialised with every Comms_Director call.
           * While TRT.JC.active (JTAC_Controller loaded) Comms_Director stands down on the JTAC
             net: no F10 9-line readback, no JTAC_Laser spot calls, no rifle / bombs away calls,
             no INJ-1 abort (JTAC_Controller owns all four), no JTAC "good hits" line in the TIC
             BDA (Bravo 2-1 and the pilot's thanks stay), "next call" hint for JTAC1 / JTAC2 comes
             from JTAC_Controller, TIC hand-off text points to F10 > COMMS.
           * Without JTAC_Controller nothing changes (template with the native JTAC).
  v1.5.6 — release calls (Onur, 2026-10-29): when the hero fires an air-to-ground weapon
           while working a JTAC (JTAC1 / JTAC2, or a re-attack under the RbAvail rule), the
           pilot transmits on that JTAC's button (ATP 1-02.1 brevity):
             missile (Maverick etc.)  "<JTAC>, Hornet 51, rifle."        ("rifle, two" for 2+)
             bomb                     "<JTAC>, Hornet 51, bombs away."   ("two away" for 2+)
           Shots of one kind inside CFG.REL_AGG_S are one call (ripple / pairs). Not called:
           rockets, guns, anti-radiation missiles (would be MAGNUM; not in CAS-1).
           CD.relCallUntil tells Pilot_Banter v1.1.1 to drop its own "weapon away" line.
           No time of flight (would need a fall-time estimate). Can overlap native JTAC talk.
  v1.5.5 — CAS-1 test 2026-10-28 night:
           * Eyeball laser calls: JTAC_Laser v1.1.0 spot events -> EYEBALL 11 on button 5
             "laser on, code 1688" / "shifting laser, same code" / "laser off". The scripted
             spot was on target the whole re-attack, but nothing said so and the pilot
             aborted for fuel. Only once Eyeball 11 has been worked (JTAC2 entered) and in an
             OVERLORD phase other than JTAC1.
           * Re-attack after abort / tanker: the 9-line readback item is no longer tied to
             the JTAC1 / JTAC2 phase. It is offered for a JTAC that has been worked, whose
             target group is alive, while the hero is within CFG.RB_NM of it (the night
             flight attacked YE53 in RTB phase -> no readback item).
  v1.5.4 — troops in contact + 9-line readback (Onur, CAS-1 test 2026-10-28):
           TIC: one JTAC per flight (CFG.TIC.WHO, nil = random between Pointer 11 and
           Eyeball 11, picked at the OVERLORD check-in from the press time) is "in contact".
             * OVERLORD's hand-off to it says "troops in contact, priority immediate ...
               without delay"; pilot "push button N, Hornet 51, buster".
             * CFG.TIC.FIRST_S after that readback, on the JTAC button: JTAC "troops in
               contact" call, pilot "copy troops in contact, N minutes out" (N from range
               and ground speed), JTAC "check in when ready for nine-line".
             * Up to CFG.TIC.MAX_CALLS tension exchanges (friendly ground unit Bravo 2-1 <->
               JTAC, sometimes the pilot), CFG.TIC.GAP_MIN..GAP_MAX s apart, only while the
               hero is more than CFG.TIC.QUIET_NM from the target group (inside that the
               native 9-line / attack talk owns the frequency).
             * CFG.TIC.BDA_S after the target group is dead: JTAC "good hits", Bravo 2-1
               "fire has stopped", pilot "glad to help".
           Readback: F10 > COMMS "<JTAC>: 9-line readback (4/6/8)" in JTAC1 / JTAC2. The pilot
           reads Line 4 elevation (ft, land.getHeight at the target unit), Line 6 grid (MGRS,
           10 m) and Line 8 friendlies (8-point direction + distance target -> JTAC unit,
           rounded to 100 m); the JTAC answers "readback correct". Values are ground truth;
           the native 9-line is not readable from scripts, so digits can differ slightly
           from what the DCS JTAC said (its target unit / precision).
           New: CFG.CHAN.POINTER, CFG.JTAC1_GROUP / JTAC2_GROUP, CFG.TIC; voices POINTER
           (ryan-medium) and FRIENDLY (sam-medium, faster) in make_clips v1.9.0.
           Native JTAC traffic cannot be detected: a scripted call can still overlap it.
  v1.5.3 —preset buttons instead of frequencies (Onur, CAS-1 test 2026-10-28): every
           hand-off says "<agency>, push button N" (CFG.BTN = Player_01 COMM1 presets) and the
           pilot reads it back: "Push button N, Hornet 51." (new clips p_push_N). Subtitles
           keep the frequency in brackets; F10 labels / next-call hints show the button.
           Same "button" convention as CV_Comms (Marshal "approach button 15").
           CD.splashes counts CAP splash calls the hero can hear (OVERLORD net), for Pilot_Banter.
  v1.5.2 — late RTB fix (CAS-1 test 2026-10-28: RTB at 49.9 NM went RTB -> STRIKE_IN ->
           RECOVERY in one tick; QClear() dropped the queued "contact Strike" call, so the
           Strike leg was silent). Marshal hand-off now needs INBOUND (pilot checked in with
           Strike). STRIKE_IN without a check-in is forced to Marshal only inside
           RECOVERY_FORCE_NM (fallback, so a pilot who never calls Strike still gets Marshal).
           CAP-net captions (commit / committing / splash / picture clean) start with
           "(CAP net)": in the test the CAP commit read as an order to Hornet 51.
  v1.5.1 — read-only state view for Flight_Timeline v1.0.0: _G.TRT.CD = CD (phase, deadJ2,
           j2.tot, inj, ...) and CD.aborted = true when the pilot calls OVERLORD "mission abort".
           No behaviour change; nothing else in this file reads TRT.CD.

  v1.5.0 — air picture, threat calls and CAP net (OVERLORD frequency):
    * Picture is computed, no longer hard-coded "picture clean": OVERLORD check-in and
      F10 "request picture" report airborne RED fighter groups within PIC_RANGE_NM of
      the player (count + nearest group, bullseye-referenced; BRAA fallback if the
      blue bullseye cannot be read). "Picture clean" only when there is none.
    * Threat call (OVERLORD → HORNET 51, BRAA from the player, pilot "copy"):
      per RED fighter group, once when HOT/FLANK inside THREAT_NM and once inside
      THREAT_CLOSE_NM (any aspect). Only in OVL_PHASES (player checked in).
    * CAP net: CFG.CAP groups (CAP-1 Check 31, CAP-2 Check 21, INTER-2 Viper 21).
      Narration of what the AI actually does, it does not task the AI:
        airborne + bandit ≤ CAP_COMMIT_NM of the lead → OVERLORD "commit, group BRAA…",
                                                        CAP "committing"
        S_EVENT_KILL, killer in a CAP group, victim RED airplane → CAP "splash one",
                                                        OVERLORD "copy splash"
        committed, no bandit ≤ CAP_COMMIT_NM + 10 for CAP_CLEAN_TICKS ticks
                                                     → CAP "picture clean, back to station"
      Transmitted on the OVERLORD channel; subtitles only in OVL_PHASES / OVL_OUT
      (outside them the radio still transmits, it is just not captioned).
    * Unsolicited calls wait in CD.chat until the clip queue is idle (CHAT_TTL s,
      then dropped); BRAA/bullseye are computed when the call is made, not when queued.
    * Ground truth, no radar model: E-2C detection / coverage is not simulated.
    * 35 new clips (make_clips v1.7.0: voices CHECK31 ryan-high, CHECK21 john-medium,
      VIPER21 bryce-medium). QFire accepts clips without subtitle text.

  v1.4.10 — pilot acknowledgement of Strike's Mode 4 instructions (STRIKE_CHK):
           "Check Mode 4" and "Mode 4 sour. Recycle." now get "<callsign>, wilco."
           (Ack, existing p_wilco clip — no new clips). The 16 s gap before
           "Mode 4 sweet now" is unchanged and now counts from the end of the ack.

  v1.4.9 — voices: make_clips v1.6.0 (MARSHAL/APPROACH/PILOT libritts-high 736/69/851,
           OVERLORD lessac-high, DEPARTURE ljspeech-high); clips re-rendered, AUDIO lengths updated.

  CAS-1 Communications State Machine — Syria Dynamic Template
  Scope: Departure→Strike→OVERLORD hand-offs · JTAC hand-offs · INFLTREP · TANKER
         · RTB (OVERLORD→Strike→Marshal) · INJ-1..4
  Out of scope: JTAC comms themselves (native DCS JTAC check-in / 9-line / clearance
                preserved, do not touch)

  v1.4.7 — F10 via Menu_Manager v1.0.0 (TRT.Menu): no own "CAS-1 COMMS" root any more
           (it was removed and re-added on every phase change, so its F-key moved).
           Calls -> F10 > COMMS (provider "CD"), "Show: hard deck" -> INFO (MISSION
           phase only), comm ladder -> INFO > "Show: comm card" (buttons 3-7 + FLOW),
           "Show: next call" -> NEXT[phase] (nil in RECOVERY / DONE: CV_Comms answers).
           Menu phase hint: DEPARTURE -> DEPARTURE, RECOVERY / DONE / IDLE -> none,
           everything else -> MISSION. Labels "AGENCY: action" (STRIKE / OVERLORD /
           TEXACO). Hints in messages read "F10 > COMMS".

  v1.4.6 — text-only reminders (CASE I/II ZIPLIP departure) show one line; the extra
           "F10 > CAS-1 COMMS - ..." hint is added only after a voiced controller repeat.

  v1.4.5 — pilot readbacks to Overlord: check-in reply -> "Hornet 51, proceeding CP Tiger,
           hard deck two-three thousand, wilco."; RTB / mission-abort reply -> "Hornet 51,
           050, wilco." (ReadBack()). Phraseology: corridor→radial/route. Re-render: make_clips --set cd
           (speech 25 % slower, +30 % level); CFG.AUDIO lengths updated.

  v1.4.4 — CASE I/II departure = ZIPLIP (ACOP / CV NATOPS): no Departure voice. At
           DEP_ZIPLIP_NM (7 DME) the phase moves to STRIKE_OUT with an on-screen hint
           only; the 60 s reminder is text-only too. The old 20 NM Departure "switch
           Strike" call is kept only when CV_Comms is not loaded.

  v1.4.3 — "SAM" was spelled letter by letter by Piper (es-ay-em); clips re-rendered
           with "Sam" (ovl_checkin_b, ovl_picture, i_rmk).

  v1.4.2 — F10 "OVERLORD: RTB (mission abort)" in ENROUTE / JTAC1 / J1_OFF / JTAC2 /
           J2_OFF (REFUEL / TKR_DONE keep their normal RTB item):
             HORNET 51: Overlord, Hornet 51, mission abort, RTB, angels N, state X.Y
             OVERLORD:  Hornet 51, Overlord, copy abort. RTB approved. Mother bears
                        XXX for YY. Proceed outbound zero five zero. Report feet wet.
           -> phase RTB (normal inbound flow: 90 NM Strike, 50 NM Marshal).

  v1.4.1 — ack timing: the hand-off ack waited for the controller's SUBTITLE time
           (dur, e.g. 10 s) instead of the end of its audio. Ack() now sets the
           preceding queued clip's hold to 0.1 s, so the ack starts ~0.8 s after
           the controller's voice ends (QFire waits max(hold, audio + AUDIO_PAD)).

  v1.4.0 — pilot hand-off acknowledgements + spoken numbers
    * Every controller hand-off gets an automatic, voiced pilot ack on the same
      frequency: "Hornet 51, switching." (Departure->Strike, Strike->Overlord,
      Overlord->Pointer / Eyeball / Texaco / Strike, Texaco->Overlord, Strike->Marshal);
      "Hornet 51, wilco." for Strike's inbound "switch Marshal at 50 miles".
    * Dynamic parts are voiced: pilot angels / state (all check-ins), Overlord
      "bears XXX for YY" (CP Tiger, Mother, Texaco + angels), full INFLTREP (MGRS in
      phonetic alphabet, TOT, vehicle counts). Clips are chained token sequences:
      Q(..., audio) accepts a table { ch = "<CHAN>", "<id>", <pause s>, ... }.
      Pilot digits / letters come from the CV_Comms set ("cv:p_*", TRT.CV_AUDIO);
      Overlord digits are o_* (tts/clips.csv). Text and voice now say the same thing
      (hard deck sentence included).
    * CASE III departure: CV_Comms v1.3.0 runs the Departure dialogue; this script
      waits for TRT.CV_DEP_CLEARED ("cleared to switch") instead of its own 20 NM
      "switch Strike". CASE I/II unchanged (20 NM).

  v1.3.5 — load log line carried a stale version ("v1.2.1 online"); now matches header.

  v1.3.4 — CV button plan (CV_Comms.lua): DEPARTURE 127.60 -> 269.00 AM (btn 2),
           MARSHAL 305.00 FM -> 261.00 AM (btn 16). str_switch_marshal / str_inbound
           re-rendered. Comm ladder lists the real COMM1 buttons.

  v1.3.3 — voices re-cast (make_clips v1.2.1): DEPARTURE and OVERLORD female
           (lessac, kristin), HORNET 51 = john. All 41 clips re-rendered, CFG.AUDIO
           lengths updated.

  v1.3.2 — HORNET 51 (pilot) calls voiced too: static part only (call sign, agency,
           request); angels / state / MGRS / TOT stay on-screen. Played on the called
           agency's frequency (CFG.AUDIO ch), voice = Piper ryan pitched down.

  v1.3.1 — clips re-rendered with make_clips.py v1.1.0 (~2x faster speech, heavier
           radio chain: squelch bursts, noise floor, soft-clip). CFG.AUDIO lengths updated.

  v1.3.0 — TTS voice for controller calls
    * Controller calls play a pre-rendered .ogg (Piper TTS, tts/make_clips.py) via
      trigger.action.radioTransmission on the agency frequency (CFG.CHAN); heard only
      when a radio is tuned to it. Pilot calls are not voiced. Dynamic content
      (bearing/range, angels, state, MGRS, TOT) stays text-only.
    * Clips: Sounds/CAS1/<id>.ogg (src/Sounds/CAS1/), table CFG.AUDIO (len = clip s).
    * Queue waits for the clip: next clip starts at max(hold or dur, len + AUDIO_PAD).
    * Urgent calls (abort / MANPADS / corridor) cut the clip on air and play at once.

  v1.2.1 — check-in reminders
    * If a pilot check-in / report is pending, the handing-off or monitoring agency
      repeats the call after REMIND_FIRST s, then every REMIND_EVERY s
      ("..., contact Strike 265.00, how copy?"), followed by an F10 hint line.
    * One-time F10 hint on takeoff. Hand-off calls stay on screen longer (DUR_HANDOFF).

  v1.2.0 — realistic C2 flow (JP 3-09.3 Ch V + CV ops practice)
    * Pilot-initiated check-ins via F10. No agency talks to the player until the
      player has checked in on its frequency. Only directive hand-offs ("switch X"),
      threat/abort calls and corridor violations are controller-initiated.
    * Hand-offs are position-gated, not time-gated:
        Departure → Strike    ≥ DEP_HANDOFF_NM from the carrier
        OVERLORD  → JTAC      ≤ JTAC_HANDOFF_NM from CP TIGER (ME WP2)
        OVERLORD  → Strike    ≤ RTB_STRIKE_NM from the carrier
        Strike    → Marshal   ≤ RECOVERY_NM from the carrier (AIRBOSS takes over)
    * Agencies corrected: CP / JTAC / tanker / RTB tasking = OVERLORD (C2 agency).
      Strike = Mode 4 / Kilo outbound, corridor + Marshal hand-off inbound.
    * Hard deck: single value, 20,000 ft MSL (v1.6.3; was 23,000), engagement area (flag 200 = 1).
    * INFLTREP (JP 3-09.3 Fig V-17) to OVERLORD after JTAC-2, then tanker assignment.
    * Feet dry / feet wet reports offered in F10 when the coastline is crossed
      (land.getSurfaceType).
    * Fix: Bearing() used atan2(dx, dz) → mirrored about 045°; now atan2(dz, dx).
    * Removed: unsolicited 4-min OVERLORD "no change" calls.

  PHASE FLOW
  ──────────────────────────────────────────────────────────────
    IDLE ─airborne→ DEPARTURE ─≥20 NM→ STRIKE_OUT ─F10→ STRIKE_CHK ─Mode 4 sweet→
    OVL_OUT ─F10→ ENROUTE ─≤20 NM CP→ JTAC1 ─tgt dead→ J1_OFF ─F10→ JTAC2
    ─tgt dead→ J2_OFF ─F10 INFLTREP→ REFUEL ─refuel done→ TKR_DONE ─F10→ RTB
    ─≤90 NM CVN→ STRIKE_IN ─F10→ INBOUND ─≤50 NM CVN→ RECOVERY
    (J2_OFF / REFUEL / TKR_DONE / RTB fall through to STRIKE_IN at ≤ RTB_STRIKE_NM)

  INJECTS
    INJ-1  Abort (30%, JTAC-2 / pass 2-3):     Eyeball "abort, abort, abort"
    INJ-2  IFF sour (15%, Strike check-in):    Strike "Mode 4 SOUR, recycle"
    INJ-3  MANPADS (25%, JTAC-2 before p3):    Eyeball threat call, hard deck reminder
    INJ-4  Corridor dev (auto, 80-50 NM):      Strike "outside corridor"
    INJ-1/3 are armed once the player is within INJ_ARM_NM of JTAC-2's targets.

  FLAGS  (no ME trigger reads 200-205 as of v1.2.0)
    100  = departure CASE (3 = CASE III — pre-set, DO NOT WRITE)
    200  = hard deck  0 = not in effect   1 = in effect, 20,000 ft MSL
    201  = INJ-1 state     0=clear  1=abort active  2=re-cleared
    202  = INJ-2 fired
    203  = INJ-3 fired (MANPADS)
    204  = INJ-4 fired (corridor deviation)
    205  = RTB corridor passed clean

  LOADING
    scripts/Comms_Director.lua, referenced by ME "Do Script File" (ResKey_Action_313).
    Embedded by build.py. Voice clips: src/Sounds/CAS1/*.ogg (regenerate with
    python tts/make_clips.py, then paste tts/audio_table.lua into CFG.AUDIO).
    Requires: DCS base Lua API, coord.*, land.* (no libraries).
]]

-- ══════════════════════════════════════════════════════════════
--  CONFIG  — v1.9.0: names, positions, call signs, buttons and frequencies come from CAS_PACK
--  (scripts/CAS_Pack.lua, loaded earlier); behaviour stays here.
-- ══════════════════════════════════════════════════════════════
local P = _G.CAS_PACK
if type(P) ~= "table" or type(P.jtacs) ~= "table" then
    env.error("[CD] CAS_PACK missing (Do Script File CAS_Pack.lua before Comms_Director.lua) - Comms_Director not started")
    return
end
-- (one local only: the main chunk is at Lua's 200-local limit; Hz = MHz string * 1e6, float as the old literals)

local CFG = {
    -- ME unit / group names
    PLAYER_UNIT    = P.hero,
    CARRIER_UNIT   = P.carrier,
    TANKER_UNIT    = P.tanker,        -- KC-130, Texaco 11
    CS             = P.cs,

    -- CP = CAS-1 route point (DCS world coords: ME x = north -> vec3.x, ME y = east -> vec3.z)
    CP_NAME        = P.cp.name,
    CP_POS         = { x = P.cp.pos.x, z = P.cp.pos.z },

    -- v1.10.0: JTAC target / friendly groups per roster key -> JT (TROOPS IN CONTACT section)
    RB_NM          = 30,
    REL_AGG_S      = 2,     -- v1.5.6: release call aggregation window (s)    -- v1.5.5: readback item outside the JTAC phase within this range

    -- v1.5.4: troops-in-contact sequence (one JTAC per flight)
    TIC = {
        ENABLE    = true,
        WHO       = nil,    -- a tasked JTAC key ("J1" Pointer 11 / "J2" Eyeball 11) / nil = random
        FIRST_S   = 10,     -- s after the pilot's "push button" readback: JTAC TIC call
        GAP_MIN   = 60,     -- s between tension exchanges
        GAP_MAX   = 90,
        MAX_CALLS = 3,      -- tension exchanges (of 4)
        QUIET_NM  = 10,     -- no tension call with the hero this close to the target group
        BDA_S     = 15,     -- s after the group is dead: "good hits"
        GS_MIN    = 180,    -- m/s ground speed floor for "N minutes out"
    },
    INJ_ARM_NM     = 20,

    -- v1.8.0 tasking scenarios (decisions Onur 2026-11-03), picked once at the OVERLORD check-in
    --   A  Pointer 11 then Eyeball 11 (fragged order)
    --   B  hold at CP TIGER, OVERLORD tasks a random JTAC first
    --   C  Pointer 11 first; during the 9-line dialogue OVERLORD diverts the hero to Eyeball 11 (TIC),
    --      Pointer 11 holds; after Eyeball 11 the hero returns to Pointer 11 (fresh check-in)
    -- Lost comms with one JTAC (A / B only, never the TIC JTAC): "tech" = radio failure on primary, recovered
    -- on the alternate button; "down" = off the net, mission cancelled. Tanker no-show: per mille.
    -- ME overrides: flag 210 scenario 1/2/3 (0 = random), 211 lost comms 1 J1 tech, 2 J1 down, 3 J2 tech,
    -- 4 J2 down, 9 none (0 = random), 212 tanker no-show 1 yes / 2 no (0 = random). Flag 213 = scenario picked.
    SCEN = {
        P        = { A = 40, B = 30, C = 30 },
        LC_P     = 17,       -- % in A / B (A + B = 70 % of sorties -> ~12 % overall, Onur: 10-15 %)
        LC_TECH  = 50,       -- % of lost comms that are recoverable on the alternate button
        NOSHOW_PM = 1,       -- tanker no-show, per mille (Onur: 0.1 %)
        FLAG_SCEN = 210, FLAG_LC = 211, FLAG_NOSHOW = 212, FLAG_PICKED = 213,
        FLAG_TIC = 214, FLAG_FIRST = 215,   -- tests: TIC 1 Pointer / 2 Eyeball / 9 off; B first tasking 1 / 2
        HOLD_NM  = 8,        -- B: tasking timer starts inside this range of CP TIGER ...
        HOLD_MAX_S = 300,    -- ... or this long after the hold call
        HOLD_WAIT = { 60, 150 },   -- B: s after that until the tasking call
        HOLD_ANGELS = P.hold_angels,
        STBY_S   = { 30, 50 },     -- lost comms: OVERLORD "stand by" -> answer
        DV_PHASES = { "SITREP", "GAMEPLAN", "NINE", "READBACK" },   -- C: Pointer 11 phases a divert may hit
        DV_DELAY = { 4, 15 },      -- C: s of radio silence in that phase before OVERLORD breaks in
        DV_BURN_LB_NM = 14,        -- C: fuel guard, transit burn
        DV_RESERVE_LB = 1000,      -- C: fuel guard, margin above the station BINGO after the transit
    },
    -- v1.8.0 alternate JTAC frequencies = unused COMM1 presets (v1.10.0: per roster key, filled below)
    ALT = {},

    -- Hand-off geometry (NM)
    DEP_HANDOFF_NM  = 20,    -- only without CV_Comms (legacy)
    DEP_ZIPLIP_NM   = 7,     -- CASE I/II: ZIPLIP, Strike check-in from 7 DME    -- Departure → Strike (outbound, on departure radial)
    JTAC_HANDOFF_NM = 20,    -- OVERLORD → JTAC, distance to CP TIGER
    RTB_STRIKE_NM   = 90,    -- OVERLORD → Strike (inbound)
    RECOVERY_NM     = 50,    -- Strike → Marshal (AIRBOSS)
    RECOVERY_FORCE_NM = 25,  -- v1.5.2: STRIKE_IN without Strike check-in -> Marshal anyway

    -- Airborne detection
    DEP_ALT_M      = 100,    -- ~330 ft MSL
    DEP_SPD_MS     = 41,     -- ~80 kt

    -- RTB corridor (TRUE degrees; Syria mag var ≈ +5° E → 050M = 055T)
    CORRIDOR_TRUE  = 55,     -- bearing FROM carrier TO player (true)
    CORRIDOR_HALF  = 15,
    CORRIDOR_OUT   = 80,
    CORRIDOR_IN    = 50,

    MAGVAR         = 5,      -- east; magnetic = true − MAGVAR
    HARD_DECK_FT   = P.hard_deck_ft,  -- MSL, engagement area (v1.6.3)
    INTERNAL_FUEL_LB = 10860,

    -- v1.5.3: Player_01 COMM1 preset buttons (ME, checked 2026-10-28)
    BTN = { DEP = P.nets.DEP.btn, STRIKE = P.nets.STRIKE.btn, OVL = P.nets.OVL.btn,   -- v1.10.0 + JTAC keys below
            TKR = P.nets.TKR.btn, MARSHAL = P.nets.MARSHAL.btn },
    FREQ = {
        DEP     = P.nets.DEP.freq,
        STRIKE  = P.nets.STRIKE.freq,
        OVL     = P.nets.OVL.freq,
        TKR     = P.nets.TKR.freq,
        MARSHAL = P.nets.MARSHAL.freq,
    },

    -- Voice (v1.3.0). Transmitted from 30 m above the player → no range/LOS loss.
    SND_DIR   = "Sounds/CAS1/",
    TX_POWER  = 1000,    -- W
    AUDIO_PAD = 0.5,     -- s after a clip ends before the next clip may start
    CHAN = {             -- Hz, modulation (v1.9.0: from CAS_PACK nets / jtacs)
        [P.nets.DEP.ch]    = { hz = math.floor(tonumber(P.nets.DEP.freq) * 1e6 + 0.5) * 1.0,    mod = radio.modulation.AM },
        [P.nets.STRIKE.ch] = { hz = math.floor(tonumber(P.nets.STRIKE.freq) * 1e6 + 0.5) * 1.0, mod = radio.modulation.AM },
        [P.nets.OVL.ch]    = { hz = math.floor(tonumber(P.nets.OVL.freq) * 1e6 + 0.5) * 1.0,    mod = radio.modulation.AM },
        [P.nets.TKR.ch]    = { hz = math.floor(tonumber(P.nets.TKR.freq) * 1e6 + 0.5) * 1.0,    mod = radio.modulation.AM },
    },
    -- generated by tts/make_clips.py; len = clip length (s)
    AUDIO = {
        dep_switch_strike      = { ch = "DEPARTURE", len = 2.72 },
        str_switch_marshal     = { ch = "STRIKE", len = 2.78 },
        eye_area_clear         = { ch = "EYEBALL", len = 3.15 },
        str_radar_contact      = { ch = "STRIKE", len = 3.18 },
        str_m4_sweet_ovl       = { ch = "STRIKE", len = 3.89 },
        str_m4_sour            = { ch = "STRIKE", len = 2.48 },
        str_m4_sweet_now       = { ch = "STRIKE", len = 2.44 },
        str_kilo_ovl           = { ch = "STRIKE", len = 3.01 },
        str_inbound            = { ch = "STRIKE", len = 6.69 },
        ovl_feet_dry           = { ch = "OVERLORD", len = 2.62 },
        ovl_feet_wet           = { ch = "OVERLORD", len = 2.51 },
        ovl_picture            = { ch = "OVERLORD", len = 4.50 },
        ovl_say_int            = { ch = "OVERLORD", len = 2.39 },
        ovl_contact_strike     = { ch = "OVERLORD", len = 3.75 },
        dep_contact_strike     = { ch = "DEPARTURE", len = 3.70 },
        str_contact_ovl        = { ch = "STRIKE", len = 3.26 },
        ovl_say_status         = { ch = "OVERLORD", len = 2.36 },
        ovl_say_status_tkr     = { ch = "OVERLORD", len = 3.50 },
        eye_abort              = { ch = "EYEBALL", len = 3.98 },
        eye_manpads            = { ch = "EYEBALL", len = 5.91 },
        str_corridor           = { ch = "STRIKE", len = 4.99 },
        str_corridor_mz        = { ch = "STRIKE", len = 5.44 },
        str_speed              = { ch = "STRIKE", len = 4.24 },
        str_speed_brass        = { ch = "STRIKE", len = 4.83 },
        p_ovl_feet_dry         = { ch = "OVERLORD", len = 2.09 },
        p_ovl_feet_wet         = { ch = "OVERLORD", len = 1.97 },
        p_ovl_picture          = { ch = "OVERLORD", len = 2.74 },
        o_0                    = { ch = "OVERLORD", len = 0.46 },
        o_1                    = { ch = "OVERLORD", len = 0.41 },
        o_2                    = { ch = "OVERLORD", len = 0.38 },
        o_3                    = { ch = "OVERLORD", len = 0.38 },
        o_4                    = { ch = "OVERLORD", len = 0.33 },
        o_5                    = { ch = "OVERLORD", len = 0.37 },
        o_6                    = { ch = "OVERLORD", len = 0.49 },
        o_7                    = { ch = "OVERLORD", len = 0.38 },
        o_8                    = { ch = "OVERLORD", len = 0.30 },
        o_9                    = { ch = "OVERLORD", len = 0.40 },
        o_bears                = { ch = "OVERLORD", len = 0.42 },
        o_for                  = { ch = "OVERLORD", len = 0.34 },
        o_angels               = { ch = "OVERLORD", len = 0.53 },
        o_mother               = { ch = "OVERLORD", len = 0.36 },
        ovl_checkin_a          = { ch = "OVERLORD", len = 7.03 },
        ovl_checkin_b          = { ch = "OVERLORD", len = 5.73 },
        ovl_contact_pointer_a  = { ch = "OVERLORD", len = 2.09 },
        ovl_contact_pointer_b  = { ch = "OVERLORD", len = 4.98 },
        ovl_off_pointer_a      = { ch = "OVERLORD", len = 2.97 },
        ovl_off_pointer_b      = { ch = "OVERLORD", len = 3.75 },
        ovl_switch_strike_a    = { ch = "OVERLORD", len = 1.46 },
        ovl_switch_strike_b    = { ch = "OVERLORD", len = 1.35 },
        ovl_rtb_a              = { ch = "OVERLORD", len = 2.49 },
        ovl_rtb_b              = { ch = "OVERLORD", len = 2.44 },
        ovl_inflrep_a          = { ch = "OVERLORD", len = 3.00 },
        ovl_inflrep_b          = { ch = "OVERLORD", len = 2.52 },
        ovl_inflrep_nt         = { ch = "OVERLORD", len = 6.03 },
        p_str_out_a            = { ch = "PILOT", len = 3.21 },
        p_ovl_checkin_a        = { ch = "PILOT", len = 5.60 },
        p_ovl_off_pointer_a    = { ch = "PILOT", len = 4.38 },
        p_ovl_off_pointer_b    = { ch = "PILOT", len = 0.97 },
        p_ovl_rtb_tkr_a        = { ch = "PILOT", len = 2.88 },
        p_ovl_rtb_notkr_a      = { ch = "PILOT", len = 3.27 },
        p_str_inbound_a        = { ch = "PILOT", len = 2.40 },
        p_switching            = { ch = "PILOT", len = 1.48 },
        p_wilco                = { ch = "PILOT", len = 1.31 },
        p_push_3               = { ch = "PILOT", len = 1.52 },
        p_push_4               = { ch = "PILOT", len = 1.65 },
        p_push_5               = { ch = "PILOT", len = 1.74 },
        p_push_6               = { ch = "PILOT", len = 1.60 },
        p_push_7               = { ch = "PILOT", len = 1.66 },
        p_push_16              = { ch = "PILOT", len = 1.77 },
        i_head                 = { ch = "PILOT", len = 1.93 },
        i_l1                   = { ch = "PILOT", len = 1.49 },
        i_l2                   = { ch = "PILOT", len = 3.48 },
        i_l3                   = { ch = "PILOT", len = 0.66 },
        i_l4                   = { ch = "PILOT", len = 1.68 },
        i_l5                   = { ch = "PILOT", len = 0.66 },
        i_l5b                  = { ch = "PILOT", len = 1.14 },
        i_rmk                  = { ch = "PILOT", len = 3.06 },
        i_rmk_inc1             = { ch = "PILOT", len = 2.12 },
        i_rmk_inc2             = { ch = "PILOT", len = 2.31 },
        p_ovl_abort_a          = { ch = "PILOT", len = 2.71 },
        ovl_abort_a            = { ch = "OVERLORD", len = 3.24 },
        p_ovl_checkin_rb       = { ch = "OVERLORD", len = 4.25 },
        p_ovl_rtb_rb           = { ch = "OVERLORD", len = 2.06 },
        ovl_ci_rc              = { ch = "OVERLORD", len = 2.39 },
        ovl_ci_frag            = { ch = "OVERLORD", len = 3.95 },
        o_pic                  = { ch = "OVERLORD", len = 0.47 },
        o_pic_clean            = { ch = "OVERLORD", len = 0.77 },
        o_single               = { ch = "OVERLORD", len = 0.67 },
        o_two                  = { ch = "OVERLORD", len = 0.61 },
        o_three                = { ch = "OVERLORD", len = 0.66 },
        o_many                 = { ch = "OVERLORD", len = 0.81 },
        o_nearest              = { ch = "OVERLORD", len = 0.60 },
        o_bullseye             = { ch = "OVERLORD", len = 0.49 },
        o_braa                 = { ch = "OVERLORD", len = 0.35 },
        o_thousand             = { ch = "OVERLORD", len = 0.51 },
        o_hot                  = { ch = "OVERLORD", len = 0.36 },
        o_flank                = { ch = "OVERLORD", len = 0.40 },
        o_beam                 = { ch = "OVERLORD", len = 0.43 },
        o_cold                 = { ch = "OVERLORD", len = 0.40 },
        o_hostile              = { ch = "OVERLORD", len = 0.46 },
        o_sam_rmk              = { ch = "OVERLORD", len = 1.98 },
        ovl_threat_head        = { ch = "OVERLORD", len = 1.99 },
        p_ovl_copy             = { ch = "OVERLORD", len = 1.22 },
        ovl_c31_commit         = { ch = "OVERLORD", len = 2.09 },
        ovl_c21_commit         = { ch = "OVERLORD", len = 2.04 },
        ovl_v21_commit         = { ch = "OVERLORD", len = 2.20 },
        ovl_c31_copy           = { ch = "OVERLORD", len = 2.11 },
        ovl_c21_copy           = { ch = "OVERLORD", len = 2.21 },
        ovl_v21_copy           = { ch = "OVERLORD", len = 2.09 },
        cap_c31_commit         = { ch = "OVERLORD", len = 1.30 },
        cap_c21_commit         = { ch = "OVERLORD", len = 1.48 },
        cap_v21_commit         = { ch = "OVERLORD", len = 1.55 },
        cap_c31_splash         = { ch = "OVERLORD", len = 2.00 },
        cap_c21_splash         = { ch = "OVERLORD", len = 2.39 },
        cap_v21_splash         = { ch = "OVERLORD", len = 2.31 },
        cap_c31_station        = { ch = "OVERLORD", len = 2.95 },
        cap_c21_station        = { ch = "OVERLORD", len = 3.84 },
        cap_v21_station        = { ch = "OVERLORD", len = 3.21 },
        ovl_tic_pointer_b      = { ch = "OVERLORD", len = 7.33 },
        ovl_tic_eyeball_b      = { ch = "OVERLORD", len = 5.69 },
        p_tic_push_4           = { ch = "OVERLORD", len = 2.39 },
        p_tic_push_5           = { ch = "OVERLORD", len = 2.11 },
        ptr_tic                = { ch = "POINTER", len = 7.71 },
        eye_tic                = { ch = "EYEBALL", len = 8.61 },
        p_tic_copy_ptr         = { ch = "POINTER", len = 2.91 },
        p_tic_copy_eye         = { ch = "EYEBALL", len = 2.94 },
        p_min_out              = { ch = "PILOT", len = 0.54 },
        p_cs                   = { ch = "PILOT", len = 0.78 },
        ptr_tic_ack            = { ch = "POINTER", len = 2.84 },
        eye_tic_ack            = { ch = "EYEBALL", len = 3.18 },
        fr_ptr_1               = { ch = "POINTER", len = 4.33 },
        fr_ptr_2               = { ch = "POINTER", len = 3.20 },
        fr_ptr_3               = { ch = "POINTER", len = 3.16 },
        fr_ptr_4               = { ch = "POINTER", len = 3.73 },
        fr_eye_1               = { ch = "EYEBALL", len = 4.23 },
        fr_eye_2               = { ch = "EYEBALL", len = 3.11 },
        fr_eye_3               = { ch = "EYEBALL", len = 3.25 },
        fr_eye_4               = { ch = "EYEBALL", len = 3.67 },
        ptr_t1                 = { ch = "POINTER", len = 3.60 },
        ptr_t2                 = { ch = "POINTER", len = 3.78 },
        ptr_t3                 = { ch = "POINTER", len = 4.76 },
        ptr_t4                 = { ch = "POINTER", len = 2.53 },
        eye_t1                 = { ch = "EYEBALL", len = 3.39 },
        eye_t2                 = { ch = "EYEBALL", len = 4.39 },
        eye_t3                 = { ch = "EYEBALL", len = 5.04 },
        eye_t4                 = { ch = "EYEBALL", len = 2.72 },
        p_expediting           = { ch = "PILOT", len = 2.28 },
        ptr_bda                = { ch = "POINTER", len = 3.78 },
        eye_bda                = { ch = "EYEBALL", len = 4.28 },
        fr_ptr_bda             = { ch = "POINTER", len = 4.22 },
        fr_eye_bda             = { ch = "EYEBALL", len = 4.07 },
        p_tic_thanks           = { ch = "PILOT", len = 1.73 },
        p_rb_ptr               = { ch = "POINTER", len = 2.52 },
        p_rb_eye               = { ch = "EYEBALL", len = 1.89 },
        p_elev                 = { ch = "PILOT", len = 0.63 },
        p_feet                 = { ch = "PILOT", len = 0.47 },
        p_grid                 = { ch = "PILOT", len = 0.33 },
        p_friendlies           = { ch = "PILOT", len = 0.61 },
        p_thousand             = { ch = "PILOT", len = 0.47 },
        p_hundred              = { ch = "PILOT", len = 0.49 },
        p_meters               = { ch = "PILOT", len = 0.52 },
        p_dir_n                = { ch = "PILOT", len = 0.47 },
        p_dir_ne               = { ch = "PILOT", len = 0.59 },
        p_dir_e                = { ch = "PILOT", len = 0.49 },
        p_dir_se               = { ch = "PILOT", len = 0.66 },
        p_dir_s                = { ch = "PILOT", len = 0.50 },
        p_dir_sw               = { ch = "PILOT", len = 0.76 },
        p_dir_w                = { ch = "PILOT", len = 0.47 },
        p_dir_nw               = { ch = "PILOT", len = 0.63 },
        ptr_rb_ok              = { ch = "POINTER", len = 2.40 },
        eye_rb_ok              = { ch = "EYEBALL", len = 2.35 },
        eye_laser_on           = { ch = "EYEBALL", len = 3.46 },
        eye_laser_shift        = { ch = "EYEBALL", len = 2.75 },
        eye_laser_off          = { ch = "EYEBALL", len = 1.31 },
        p_rel_ptr              = { ch = "POINTER", len = 1.66 },
        p_rel_eye              = { ch = "EYEBALL", len = 1.48 },
        p_rifle                = { ch = "PILOT", len = 0.50 },
        p_bombs_away           = { ch = "PILOT", len = 0.72 },
        p_away                 = { ch = "PILOT", len = 0.47 },
        ovl_ar1_a              = { ch = "OVERLORD", len = 2.21 },
        o_maintain             = { ch = "OVERLORD", len = 0.52 },
        ovl_tkr_bra            = { ch = "OVERLORD", len = 1.41 },
        ovl_off_tkr            = { ch = "OVERLORD", len = 2.88 },
        ovl_copy_51            = { ch = "OVERLORD", len = 1.93 },
        p_ovl_req_tkr_a        = { ch = "PILOT", len = 2.45 },
        p_ovl_off_tkr_a        = { ch = "PILOT", len = 2.34 },
        p_ovl_off_tkr_b        = { ch = "PILOT", len = 1.12 },
        p_tkr_rb_a             = { ch = "PILOT", len = 0.92 },
        p_tkr_rb_b             = { ch = "PILOT", len = 0.86 },
        p_tkr_init_a           = { ch = "PILOT", len = 2.76 },
        p_tkr_init_b           = { ch = "PILOT", len = 2.32 },
        p_request              = { ch = "PILOT", len = 0.58 },
        p_judy                 = { ch = "PILOT", len = 1.45 },
        tkr_init_a             = { ch = "TEXACO", len = 3.73 },
        tkr_rcvd               = { ch = "TEXACO", len = 2.33 },
        tkr_clear              = { ch = "TEXACO", len = 2.79 },
        t_altimeter            = { ch = "TEXACO", len = 0.58 },
        t_available            = { ch = "TEXACO", len = 0.51 },
        t_point                = { ch = "TEXACO", len = 0.35 },
        t_0                    = { ch = "TEXACO", len = 0.44 },
        t_1                    = { ch = "TEXACO", len = 0.41 },
        t_2                    = { ch = "TEXACO", len = 0.31 },
        t_3                    = { ch = "TEXACO", len = 0.38 },
        t_4                    = { ch = "TEXACO", len = 0.34 },
        t_5                    = { ch = "TEXACO", len = 0.40 },
        t_6                    = { ch = "TEXACO", len = 0.51 },
        t_7                    = { ch = "TEXACO", len = 0.43 },
        t_8                    = { ch = "TEXACO", len = 0.25 },
        t_9                    = { ch = "TEXACO", len = 0.40 },
        p_ovl_divb_ltag        = { ch = "PILOT", len = 3.10 },
        p_ovl_div_ltag         = { ch = "PILOT", len = 2.11 },
        p_ovl_divb_lcra        = { ch = "PILOT", len = 2.90 },
        p_ovl_div_lcra         = { ch = "PILOT", len = 2.40 },
        ovl_div_a              = { ch = "OVERLORD", len = 2.40 },
        o_ltag                 = { ch = "OVERLORD", len = 0.49 },
        o_lcra                 = { ch = "OVERLORD", len = 0.61 },
        ovl_div_b_ltag         = { ch = "OVERLORD", len = 3.24 },
        ovl_div_b_lcra         = { ch = "OVERLORD", len = 3.35 },
        p_div_rb_ltag          = { ch = "OVERLORD", len = 2.99 },
        p_div_rb_lcra          = { ch = "OVERLORD", len = 3.12 },
        o_fl                   = { ch = "OVERLORD", len = 0.57 },
        o_vector               = { ch = "OVERLORD", len = 0.42 },
        ovl_vec_a              = { ch = "OVERLORD", len = 1.21 },
        o_texaco               = { ch = "OVERLORD", len = 0.50 },
        p_fl                   = { ch = "PILOT", len = 0.68 },
        p_vector               = { ch = "PILOT", len = 0.45 },
        p_nose_cold            = { ch = "PILOT", len = 1.79 },
        p_51                   = { ch = "PILOT", len = 0.89 },
        p_min_fuel             = { ch = "PILOT", len = 0.82 },
        ovl_div_b_ltag_ank     = { ch = "OVERLORD", len = 3.56 },
        p_div_rb_ltag_ank      = { ch = "OVERLORD", len = 2.76 },
        p_tkr_overrun          = { ch = "PILOT", len = 2.15 },
        p_tkr_breakaway        = { ch = "PILOT", len = 2.29 },
        p_spokes               = { ch = "PILOT", len = 1.51 },
        tkr_term_overrun       = { ch = "TEXACO", len = 1.76 },
        tkr_term_bkw           = { ch = "TEXACO", len = 2.05 },
        tkr_spokes             = { ch = "TEXACO", len = 4.22 },
        ovl_tkr_lost_cp        = { ch = "OVERLORD", len = 5.07 },
        ovl_tkr_lost_si        = { ch = "OVERLORD", len = 4.67 },
        ovl_inflrep_lost       = { ch = "OVERLORD", len = 4.08 },
        p_mud                  = { ch = "OVERLORD", len = 0.36 },
        p_n10                  = { ch = "OVERLORD", len = 0.43 },
        p_n15                  = { ch = "OVERLORD", len = 0.55 },
        p_n19                  = { ch = "OVERLORD", len = 0.56 },
        tq_rmk1                = { ch = "TEXACO", len = 1.03 },
        tq_rmk2                = { ch = "TEXACO", len = 2.06 },
        tq_rcvd41              = { ch = "TEXACO", len = 2.21 },
        tq_rcvd42              = { ch = "TEXACO", len = 2.26 },
        tq_ctl                 = { ch = "TEXACO", len = 0.62 },
        a41_ack                = { ch = "TEXACO", len = 0.90 },
        a42_ack                = { ch = "TEXACO", len = 0.76 },
        ovl_contact_eyeball_b  = { ch = "OVERLORD", len = 4.98 },
        ovl_tic_eyeball_c      = { ch = "OVERLORD", len = 7.46 },
        ovl_resume_ptr         = { ch = "OVERLORD", len = 3.34 },
        ovl_task_a             = { ch = "OVERLORD", len = 1.92 },
        ovl_hold               = { ch = "OVERLORD", len = 4.81 },
        p_hold_rb              = { ch = "OVERLORD", len = 2.82 },
        p_ovl_off_eyeball_a    = { ch = "PILOT", len = 3.92 },
        ovl_divert_a           = { ch = "OVERLORD", len = 2.45 },
        ovl_divert_b           = { ch = "OVERLORD", len = 7.40 },
        p_divert_ptr           = { ch = "POINTER", len = 4.54 },
        ptr_divert_ack         = { ch = "POINTER", len = 5.25 },
        p_divert_unable        = { ch = "OVERLORD", len = 1.95 },
        ovl_divert_unable      = { ch = "OVERLORD", len = 3.14 },
        p_unable_ptr           = { ch = "OVERLORD", len = 3.07 },
        p_unable_eye           = { ch = "OVERLORD", len = 3.12 },
        ovl_standby            = { ch = "OVERLORD", len = 2.60 },
        ovl_lc_alt_ptr         = { ch = "OVERLORD", len = 6.29 },
        ovl_lc_alt_eye         = { ch = "OVERLORD", len = 6.55 },
        ovl_lc_down_ptr        = { ch = "OVERLORD", len = 5.42 },
        ovl_lc_down_eye        = { ch = "OVERLORD", len = 5.57 },
        p_push_9               = { ch = "PILOT", len = 1.62 },
        p_push_11              = { ch = "PILOT", len = 1.95 },
        p_ovl_neg_tkr_a        = { ch = "PILOT", len = 2.22 },
        p_ovl_cont_notkr_a     = { ch = "PILOT", len = 3.03 },
        i_rmk_can1             = { ch = "PILOT", len = 2.96 },
        i_rmk_can2             = { ch = "PILOT", len = 2.98 },
        i_l2_a                 = { ch = "PILOT", len = 0.90 },
        i_rmk_msn              = { ch = "PILOT", len = 0.38 },
        i_rmk_inc_b            = { ch = "PILOT", len = 1.17 },
        i_rmk_can_b            = { ch = "PILOT", len = 1.97 },
        ovl_dv_pointer         = { ch = "OVERLORD", len = 6.05 },
        ovl_adv_ptr            = { ch = "OVERLORD", len = 1.40 },
        ovl_dvu_ptr            = { ch = "OVERLORD", len = 3.33 },
        p_ovl_off_x_ptr        = { ch = "PILOT", len = 3.00 },
        ovl_lc_dn_ptr          = { ch = "OVERLORD", len = 4.01 },
        ovl_dv_eyeball         = { ch = "OVERLORD", len = 5.72 },
        ovl_adv_eye            = { ch = "OVERLORD", len = 1.30 },
        ovl_dvu_eye            = { ch = "OVERLORD", len = 3.05 },
        p_ovl_off_x_eye        = { ch = "PILOT", len = 2.66 },
        ovl_lc_dn_eye          = { ch = "OVERLORD", len = 4.22 },
        ovl_dv_axeman          = { ch = "OVERLORD", len = 6.25 },
        ovl_adv_axe            = { ch = "OVERLORD", len = 1.39 },
        ovl_dvu_axe            = { ch = "OVERLORD", len = 3.31 },
        p_ovl_off_x_axe        = { ch = "PILOT", len = 2.66 },
        ovl_lc_dn_axe          = { ch = "OVERLORD", len = 4.13 },
        ovl_dv_darknight       = { ch = "OVERLORD", len = 6.16 },
        ovl_adv_dkn            = { ch = "OVERLORD", len = 1.54 },
        ovl_dvu_dkn            = { ch = "OVERLORD", len = 3.23 },
        p_ovl_off_x_dkn        = { ch = "PILOT", len = 2.53 },
        ovl_lc_dn_dkn          = { ch = "OVERLORD", len = 4.39 },
        p_ovl_checkin_x        = { ch = "PILOT", len = 3.10 },
        ovl_ci_xcas            = { ch = "OVERLORD", len = 3.28 },
        o_mission              = { ch = "OVERLORD", len = 0.39 },
        o_cancelled            = { ch = "OVERLORD", len = 0.45 },
        p_mission              = { ch = "PILOT", len = 0.51 },
        p_complete             = { ch = "PILOT", len = 0.57 },
        axe_tic                = { ch = "AXEMAN", len = 9.46 },
        axe_tic_ack            = { ch = "AXEMAN", len = 3.81 },
        fr_axe_1               = { ch = "AXEMAN", len = 4.37 },
        fr_axe_2               = { ch = "AXEMAN", len = 3.24 },
        fr_axe_3               = { ch = "AXEMAN", len = 3.23 },
        fr_axe_4               = { ch = "AXEMAN", len = 3.87 },
        fr_axe_bda             = { ch = "AXEMAN", len = 4.26 },
        axe_t1                 = { ch = "AXEMAN", len = 4.24 },
        axe_t2                 = { ch = "AXEMAN", len = 4.45 },
        axe_t3                 = { ch = "AXEMAN", len = 5.97 },
        axe_t4                 = { ch = "AXEMAN", len = 2.87 },
        axe_bda                = { ch = "AXEMAN", len = 3.90 },
        axe_rb_ok              = { ch = "AXEMAN", len = 2.89 },
        axe_laser_on           = { ch = "AXEMAN", len = 4.07 },
        axe_laser_shift        = { ch = "AXEMAN", len = 3.18 },
        axe_laser_off          = { ch = "AXEMAN", len = 1.44 },
        p_rb_axe               = { ch = "AXEMAN", len = 2.19 },
        p_rel_axe              = { ch = "AXEMAN", len = 1.71 },
        p_tic_copy_axe         = { ch = "AXEMAN", len = 3.03 },
        p_unable_axe           = { ch = "OVERLORD", len = 3.01 },
        ovl_contact_axeman_b   = { ch = "OVERLORD", len = 5.20 },
        ovl_tic_axeman_b       = { ch = "OVERLORD", len = 7.41 },
        p_ovl_off_axeman_a     = { ch = "PILOT", len = 3.88 },
        ovl_lc_alt_axe         = { ch = "OVERLORD", len = 6.66 },
        ovl_lc_down_axe        = { ch = "OVERLORD", len = 5.43 },
        p_divert_axe           = { ch = "AXEMAN", len = 4.61 },
        axe_divert_ack         = { ch = "AXEMAN", len = 4.84 },
        ovl_resume_axe         = { ch = "OVERLORD", len = 3.49 },
        p_push_10              = { ch = "PILOT", len = 1.79 },
        p_push_13              = { ch = "PILOT", len = 2.02 },
        p_tic_push_10          = { ch = "OVERLORD", len = 2.03 },
        dkn_tic                = { ch = "DARKNIGHT", len = 9.07 },
        dkn_tic_ack            = { ch = "DARKNIGHT", len = 3.83 },
        fr_dkn_1               = { ch = "DARKNIGHT", len = 4.39 },
        fr_dkn_2               = { ch = "DARKNIGHT", len = 3.24 },
        fr_dkn_3               = { ch = "DARKNIGHT", len = 3.16 },
        fr_dkn_4               = { ch = "DARKNIGHT", len = 3.86 },
        fr_dkn_bda             = { ch = "DARKNIGHT", len = 4.33 },
        dkn_t1                 = { ch = "DARKNIGHT", len = 4.02 },
        dkn_t2                 = { ch = "DARKNIGHT", len = 4.55 },
        dkn_t3                 = { ch = "DARKNIGHT", len = 5.87 },
        dkn_t4                 = { ch = "DARKNIGHT", len = 2.63 },
        dkn_bda                = { ch = "DARKNIGHT", len = 4.05 },
        dkn_rb_ok              = { ch = "DARKNIGHT", len = 2.88 },
        dkn_laser_on           = { ch = "DARKNIGHT", len = 3.87 },
        dkn_laser_shift        = { ch = "DARKNIGHT", len = 3.08 },
        dkn_laser_off          = { ch = "DARKNIGHT", len = 1.76 },
        p_rb_dkn               = { ch = "DARKNIGHT", len = 2.22 },
        p_rel_dkn              = { ch = "DARKNIGHT", len = 1.81 },
        p_tic_copy_dkn         = { ch = "DARKNIGHT", len = 3.44 },
        p_unable_dkn           = { ch = "OVERLORD", len = 3.10 },
        ovl_contact_darknight_b = { ch = "OVERLORD", len = 5.37 },
        ovl_tic_darknight_b    = { ch = "OVERLORD", len = 7.77 },
        p_ovl_off_darknight_a  = { ch = "PILOT", len = 4.34 },
        ovl_lc_alt_dkn         = { ch = "OVERLORD", len = 7.08 },
        ovl_lc_down_dkn        = { ch = "OVERLORD", len = 5.69 },
        p_divert_dkn           = { ch = "DARKNIGHT", len = 4.92 },
        dkn_divert_ack         = { ch = "DARKNIGHT", len = 5.03 },
        ovl_resume_dkn         = { ch = "OVERLORD", len = 3.67 },
        p_push_12              = { ch = "PILOT", len = 2.18 },
        p_push_14              = { ch = "PILOT", len = 2.18 },
        p_tic_push_12          = { ch = "OVERLORD", len = 2.58 },
        pj_n_0                 = { ch = "POINTER", len = 0.45 },
        pj_n_1                 = { ch = "POINTER", len = 0.42 },
        pj_n_2                 = { ch = "POINTER", len = 0.49 },
        pj_n_3                 = { ch = "POINTER", len = 0.32 },
        pj_n_4                 = { ch = "POINTER", len = 0.41 },
        pj_n_5                 = { ch = "POINTER", len = 0.45 },
        pj_n_6                 = { ch = "POINTER", len = 0.48 },
        pj_n_7                 = { ch = "POINTER", len = 0.45 },
        pj_n_8                 = { ch = "POINTER", len = 0.33 },
        pj_n_9                 = { ch = "POINTER", len = 0.45 },
        pj_l_a                 = { ch = "POINTER", len = 0.39 },
        pj_l_b                 = { ch = "POINTER", len = 0.44 },
        pj_l_c                 = { ch = "POINTER", len = 0.43 },
        pj_l_d                 = { ch = "POINTER", len = 0.39 },
        pj_l_e                 = { ch = "POINTER", len = 0.47 },
        pj_l_f                 = { ch = "POINTER", len = 0.63 },
        pj_l_g                 = { ch = "POINTER", len = 0.42 },
        pj_l_h                 = { ch = "POINTER", len = 0.56 },
        pj_l_i                 = { ch = "POINTER", len = 0.51 },
        pj_l_j                 = { ch = "POINTER", len = 0.55 },
        pj_l_k                 = { ch = "POINTER", len = 0.37 },
        pj_l_l                 = { ch = "POINTER", len = 0.46 },
        pj_l_m                 = { ch = "POINTER", len = 0.41 },
        pj_l_n                 = { ch = "POINTER", len = 0.59 },
        pj_l_o                 = { ch = "POINTER", len = 0.42 },
        pj_l_p                 = { ch = "POINTER", len = 0.51 },
        pj_l_q                 = { ch = "POINTER", len = 0.46 },
        pj_l_r                 = { ch = "POINTER", len = 0.55 },
        pj_l_s                 = { ch = "POINTER", len = 0.60 },
        pj_l_t                 = { ch = "POINTER", len = 0.45 },
        pj_l_u                 = { ch = "POINTER", len = 0.66 },
        pj_l_v                 = { ch = "POINTER", len = 0.52 },
        pj_l_w                 = { ch = "POINTER", len = 0.53 },
        pj_l_x                 = { ch = "POINTER", len = 0.49 },
        pj_l_y                 = { ch = "POINTER", len = 0.41 },
        pj_l_z                 = { ch = "POINTER", len = 0.50 },
        pj_d_north             = { ch = "POINTER", len = 0.42 },
        pj_d_northeast         = { ch = "POINTER", len = 0.57 },
        pj_d_east              = { ch = "POINTER", len = 0.47 },
        pj_d_southeast         = { ch = "POINTER", len = 0.61 },
        pj_d_south             = { ch = "POINTER", len = 0.42 },
        pj_d_southwest         = { ch = "POINTER", len = 0.76 },
        pj_d_west              = { ch = "POINTER", len = 0.42 },
        pj_d_northwest         = { ch = "POINTER", len = 0.66 },
        pj_lab_sa_8_launcher   = { ch = "POINTER", len = 0.96 },
        pj_lab_sa_8_launcher_pl = { ch = "POINTER", len = 1.01 },
        pj_lab_sa_13_launcher  = { ch = "POINTER", len = 1.10 },
        pj_lab_sa_13_launcher_pl = { ch = "POINTER", len = 1.27 },
        pj_lab_sa_15           = { ch = "POINTER", len = 0.74 },
        pj_lab_sa_15_pl        = { ch = "POINTER", len = 0.85 },
        pj_lab_sa_15_m2        = { ch = "POINTER", len = 1.05 },
        pj_lab_sa_15_m2_pl     = { ch = "POINTER", len = 1.32 },
        pj_lab_sa_6_radar      = { ch = "POINTER", len = 1.05 },
        pj_lab_sa_6_radar_pl   = { ch = "POINTER", len = 1.26 },
        pj_lab_sa_6_launcher   = { ch = "POINTER", len = 0.92 },
        pj_lab_sa_6_launcher_pl = { ch = "POINTER", len = 1.05 },
        pj_lab_sa_6            = { ch = "POINTER", len = 0.63 },
        pj_lab_sa_6_pl         = { ch = "POINTER", len = 0.79 },
        pj_lab_sa_3            = { ch = "POINTER", len = 0.55 },
        pj_lab_sa_3_pl         = { ch = "POINTER", len = 0.67 },
        pj_lab_sa_10           = { ch = "POINTER", len = 0.65 },
        pj_lab_sa_10_pl        = { ch = "POINTER", len = 0.76 },
        pj_lab_sa_11           = { ch = "POINTER", len = 0.73 },
        pj_lab_sa_11_pl        = { ch = "POINTER", len = 0.76 },
        pj_lab_sa_8            = { ch = "POINTER", len = 0.65 },
        pj_lab_sa_8_pl         = { ch = "POINTER", len = 0.66 },
        pj_lab_sa_19           = { ch = "POINTER", len = 0.79 },
        pj_lab_sa_19_pl        = { ch = "POINTER", len = 0.82 },
        pj_lab_zsu_23_4        = { ch = "POINTER", len = 1.40 },
        pj_lab_zsu_23_4_pl     = { ch = "POINTER", len = 1.44 },
        pj_lab_sa_14_manpads   = { ch = "POINTER", len = 1.27 },
        pj_lab_sa_18_manpads   = { ch = "POINTER", len = 1.45 },
        pj_lab_sa_3_radar      = { ch = "POINTER", len = 0.91 },
        pj_lab_sa_3_radar_pl   = { ch = "POINTER", len = 1.16 },
        pj_lab_sa_3_launcher   = { ch = "POINTER", len = 0.86 },
        pj_lab_sa_3_launcher_pl = { ch = "POINTER", len = 1.03 },
        pj_lab_t_55_tank       = { ch = "POINTER", len = 1.14 },
        pj_lab_t_55_tank_pl    = { ch = "POINTER", len = 1.19 },
        pj_lab_t_72_tank       = { ch = "POINTER", len = 1.01 },
        pj_lab_t_72_tank_pl    = { ch = "POINTER", len = 1.06 },
        pj_lab_btr             = { ch = "POINTER", len = 0.77 },
        pj_lab_btr_pl          = { ch = "POINTER", len = 1.32 },
        pj_lab_bmp             = { ch = "POINTER", len = 0.77 },
        pj_lab_bmp_pl          = { ch = "POINTER", len = 0.85 },
        pj_lab_truck           = { ch = "POINTER", len = 0.42 },
        pj_lab_truck_pl        = { ch = "POINTER", len = 0.55 },
        pj_lab_infantry        = { ch = "POINTER", len = 0.59 },
        pj_lab_technical       = { ch = "POINTER", len = 0.54 },
        pj_lab_technical_pl    = { ch = "POINTER", len = 0.75 },
        pj_lab_sp_howitzer     = { ch = "POINTER", len = 1.22 },
        pj_lab_sp_howitzer_pl  = { ch = "POINTER", len = 1.34 },
        pj_ord_one_agm_65e     = { ch = "POINTER", len = 1.84 },
        pj_ord_one_gbu_12      = { ch = "POINTER", len = 1.08 },
        pj_egress              = { ch = "POINTER", len = 1.31 },
        pj_ci_a                = { ch = "POINTER", len = 5.99 },
        pj_w_plus              = { ch = "POINTER", len = 0.40 },
        pj_ci_enemy            = { ch = "POINTER", len = 0.38 },
        pj_ci_fr_bravo         = { ch = "POINTER", len = 3.59 },
        pj_ci_fr_team          = { ch = "POINTER", len = 2.38 },
        pj_w_of_tgt            = { ch = "POINTER", len = 0.70 },
        pj_ci_wind             = { ch = "POINTER", len = 2.34 },
        pj_ci_calm             = { ch = "POINTER", len = 2.74 },
        pj_w_at                = { ch = "POINTER", len = 0.23 },
        pj_ci_end              = { ch = "POINTER", len = 6.39 },
        pj_gp_t1               = { ch = "POINTER", len = 2.96 },
        pj_gp_t2               = { ch = "POINTER", len = 3.43 },
        pj_gp_t2c              = { ch = "POINTER", len = 2.79 },
        pj_gp_end              = { ch = "POINTER", len = 1.68 },
        pj_cs                  = { ch = "POINTER", len = 0.96 },
        pj_ip_lynx             = { ch = "POINTER", len = 0.50 },
        pj_ip_puma             = { ch = "POINTER", len = 1.04 },
        pj_ip_jackal           = { ch = "POINTER", len = 0.49 },
        pj_ip_cobra            = { ch = "POINTER", len = 0.42 },
        pj_w_keyhole           = { ch = "POINTER", len = 0.39 },
        pj_w_laser             = { ch = "POINTER", len = 0.44 },
        pj_w_toc               = { ch = "POINTER", len = 1.06 },
        pj_nl_end              = { ch = "POINTER", len = 1.54 },
        pj_rm_a                = { ch = "POINTER", len = 1.44 },
        pj_rm_ltl              = { ch = "POINTER", len = 1.26 },
        pj_rm_threat           = { ch = "POINTER", len = 0.43 },
        pj_rm_caution          = { ch = "POINTER", len = 1.57 },
        pj_rm_via              = { ch = "POINTER", len = 1.45 },
        pj_w_caution           = { ch = "POINTER", len = 0.47 },
        pj_rm_route            = { ch = "POINTER", len = 1.27 },
        pj_rm_req              = { ch = "POINTER", len = 0.52 },
        pj_rm_hd               = { ch = "POINTER", len = 1.74 },
        pj_rm_fah              = { ch = "POINTER", len = 1.86 },
        pj_w_to                = { ch = "POINTER", len = 0.42 },
        pj_rm_end              = { ch = "POINTER", len = 1.28 },
        pj_rb_ok               = { ch = "POINTER", len = 1.93 },
        pj_w_call_laser        = { ch = "POINTER", len = 0.89 },
        pj_rb_neg              = { ch = "POINTER", len = 1.65 },
        pj_w_elev              = { ch = "POINTER", len = 0.53 },
        pj_w_grid              = { ch = "POINTER", len = 0.33 },
        pj_w_fah               = { ch = "POINTER", len = 0.95 },
        pj_w_readback          = { ch = "POINTER", len = 0.60 },
        pj_say_rb              = { ch = "POINTER", len = 3.18 },
        pj_cont                = { ch = "POINTER", len = 1.58 },
        pj_clr_hot             = { ch = "POINTER", len = 1.75 },
        pj_blind               = { ch = "POINTER", len = 2.27 },
        pj_cont_tally          = { ch = "POINTER", len = 2.92 },
        pj_w_abort             = { ch = "POINTER", len = 0.49 },
        pj_ab_fah              = { ch = "POINTER", len = 2.02 },
        pj_ab_civ              = { ch = "POINTER", len = 2.29 },
        pj_lasing              = { ch = "POINTER", len = 1.88 },
        pj_unable_los          = { ch = "POINTER", len = 2.94 },
        pj_neg_resp            = { ch = "POINTER", len = 1.97 },
        pj_laser_off           = { ch = "POINTER", len = 1.71 },
        pj_laser_to            = { ch = "POINTER", len = 4.11 },
        pj_not_clr             = { ch = "POINTER", len = 3.26 },
        pj_aft_abort           = { ch = "POINTER", len = 3.57 },
        pj_term                = { ch = "POINTER", len = 6.84 },
        pj_as_a                = { ch = "POINTER", len = 1.63 },
        pj_w_splash            = { ch = "POINTER", len = 0.63 },
        pj_as_good             = { ch = "POINTER", len = 0.74 },
        pj_as_next             = { ch = "POINTER", len = 0.74 },
        pj_as_from             = { ch = "POINTER", len = 0.83 },
        pj_as_shift            = { ch = "POINTER", len = 0.67 },
        pj_as_rin              = { ch = "POINTER", len = 0.70 },
        pj_as_miss             = { ch = "POINTER", len = 0.46 },
        pj_bda_a               = { ch = "POINTER", len = 1.58 },
        pj_w_destroyed         = { ch = "POINTER", len = 0.68 },
        pj_w_notobs            = { ch = "POINTER", len = 0.87 },
        pj_bda_act             = { ch = "POINTER", len = 2.32 },
        pj_w_time              = { ch = "POINTER", len = 0.48 },
        pj_w_local             = { ch = "POINTER", len = 0.41 },
        pj_bda_rmk             = { ch = "POINTER", len = 0.99 },
        pj_bda_end             = { ch = "POINTER", len = 2.76 },
        pj_bda_wnc             = { ch = "POINTER", len = 2.71 },
        pj_w_none_obs          = { ch = "POINTER", len = 0.77 },
        pj_w_activity          = { ch = "POINTER", len = 0.70 },
        pj_w_remaining         = { ch = "POINTER", len = 1.44 },
        pj_bda_end_inc         = { ch = "POINTER", len = 3.17 },
        pj_nj_a                = { ch = "POINTER", len = 1.58 },
        pj_nj_bravo            = { ch = "POINTER", len = 1.18 },
        pj_nj_me               = { ch = "POINTER", len = 0.82 },
        pj_off_copy            = { ch = "POINTER", len = 1.35 },
        pj_off_reatk           = { ch = "POINTER", len = 2.31 },
        pj_area_clear          = { ch = "POINTER", len = 3.32 },
        pj_iauth               = { ch = "POINTER", len = 2.23 },
        pj_spf_dis             = { ch = "POINTER", len = 2.23 },
        pj_spf_neg             = { ch = "POINTER", len = 3.46 },
        pj_spf_adv             = { ch = "POINTER", len = 4.10 },
        pj_w_and               = { ch = "POINTER", len = 0.46 },
        pj_w_meters            = { ch = "POINTER", len = 0.54 },
        pj_w_desired_destroy   = { ch = "POINTER", len = 1.64 },
        pj_w_withdrawing       = { ch = "POINTER", len = 0.69 },
        pj_w_location          = { ch = "POINTER", len = 0.66 },
        pj_w_still_threat      = { ch = "POINTER", len = 1.24 },
        pj_w_point             = { ch = "POINTER", len = 0.44 },
        pj_w_hundred           = { ch = "POINTER", len = 0.39 },
        pj_w_thousand          = { ch = "POINTER", len = 0.48 },
        ej_n_0                 = { ch = "EYEBALL", len = 0.47 },
        ej_n_1                 = { ch = "EYEBALL", len = 0.35 },
        ej_n_2                 = { ch = "EYEBALL", len = 0.39 },
        ej_n_3                 = { ch = "EYEBALL", len = 0.35 },
        ej_n_4                 = { ch = "EYEBALL", len = 0.37 },
        ej_n_5                 = { ch = "EYEBALL", len = 0.46 },
        ej_n_6                 = { ch = "EYEBALL", len = 0.39 },
        ej_n_7                 = { ch = "EYEBALL", len = 0.48 },
        ej_n_8                 = { ch = "EYEBALL", len = 0.30 },
        ej_n_9                 = { ch = "EYEBALL", len = 0.45 },
        ej_l_a                 = { ch = "EYEBALL", len = 0.37 },
        ej_l_b                 = { ch = "EYEBALL", len = 0.43 },
        ej_l_c                 = { ch = "EYEBALL", len = 0.43 },
        ej_l_d                 = { ch = "EYEBALL", len = 0.36 },
        ej_l_e                 = { ch = "EYEBALL", len = 0.38 },
        ej_l_f                 = { ch = "EYEBALL", len = 0.49 },
        ej_l_g                 = { ch = "EYEBALL", len = 0.45 },
        ej_l_h                 = { ch = "EYEBALL", len = 0.42 },
        ej_l_i                 = { ch = "EYEBALL", len = 0.46 },
        ej_l_j                 = { ch = "EYEBALL", len = 0.54 },
        ej_l_k                 = { ch = "EYEBALL", len = 0.43 },
        ej_l_l                 = { ch = "EYEBALL", len = 0.43 },
        ej_l_m                 = { ch = "EYEBALL", len = 0.30 },
        ej_l_n                 = { ch = "EYEBALL", len = 0.57 },
        ej_l_o                 = { ch = "EYEBALL", len = 0.40 },
        ej_l_p                 = { ch = "EYEBALL", len = 0.40 },
        ej_l_q                 = { ch = "EYEBALL", len = 0.39 },
        ej_l_r                 = { ch = "EYEBALL", len = 0.54 },
        ej_l_s                 = { ch = "EYEBALL", len = 0.57 },
        ej_l_t                 = { ch = "EYEBALL", len = 0.45 },
        ej_l_u                 = { ch = "EYEBALL", len = 0.61 },
        ej_l_v                 = { ch = "EYEBALL", len = 0.40 },
        ej_l_w                 = { ch = "EYEBALL", len = 0.45 },
        ej_l_x                 = { ch = "EYEBALL", len = 0.49 },
        ej_l_y                 = { ch = "EYEBALL", len = 0.47 },
        ej_l_z                 = { ch = "EYEBALL", len = 0.48 },
        ej_d_north             = { ch = "EYEBALL", len = 0.42 },
        ej_d_northeast         = { ch = "EYEBALL", len = 0.76 },
        ej_d_east              = { ch = "EYEBALL", len = 0.35 },
        ej_d_southeast         = { ch = "EYEBALL", len = 0.61 },
        ej_d_south             = { ch = "EYEBALL", len = 0.41 },
        ej_d_southwest         = { ch = "EYEBALL", len = 0.67 },
        ej_d_west              = { ch = "EYEBALL", len = 0.42 },
        ej_d_northwest         = { ch = "EYEBALL", len = 0.63 },
        ej_lab_sa_8_launcher   = { ch = "EYEBALL", len = 0.82 },
        ej_lab_sa_8_launcher_pl = { ch = "EYEBALL", len = 0.98 },
        ej_lab_sa_13_launcher  = { ch = "EYEBALL", len = 1.10 },
        ej_lab_sa_13_launcher_pl = { ch = "EYEBALL", len = 1.17 },
        ej_lab_sa_15           = { ch = "EYEBALL", len = 0.85 },
        ej_lab_sa_15_pl        = { ch = "EYEBALL", len = 0.89 },
        ej_lab_sa_15_m2        = { ch = "EYEBALL", len = 1.22 },
        ej_lab_sa_15_m2_pl     = { ch = "EYEBALL", len = 1.30 },
        ej_lab_sa_6_radar      = { ch = "EYEBALL", len = 0.95 },
        ej_lab_sa_6_radar_pl   = { ch = "EYEBALL", len = 1.04 },
        ej_lab_sa_6_launcher   = { ch = "EYEBALL", len = 0.87 },
        ej_lab_sa_6_launcher_pl = { ch = "EYEBALL", len = 0.98 },
        ej_lab_sa_6            = { ch = "EYEBALL", len = 0.70 },
        ej_lab_sa_6_pl         = { ch = "EYEBALL", len = 0.71 },
        ej_lab_sa_3            = { ch = "EYEBALL", len = 0.55 },
        ej_lab_sa_3_pl         = { ch = "EYEBALL", len = 0.72 },
        ej_lab_sa_10           = { ch = "EYEBALL", len = 0.63 },
        ej_lab_sa_10_pl        = { ch = "EYEBALL", len = 0.64 },
        ej_lab_sa_11           = { ch = "EYEBALL", len = 0.64 },
        ej_lab_sa_11_pl        = { ch = "EYEBALL", len = 0.76 },
        ej_lab_sa_8            = { ch = "EYEBALL", len = 0.56 },
        ej_lab_sa_8_pl         = { ch = "EYEBALL", len = 0.63 },
        ej_lab_sa_19           = { ch = "EYEBALL", len = 0.99 },
        ej_lab_sa_19_pl        = { ch = "EYEBALL", len = 0.91 },
        ej_lab_zsu_23_4        = { ch = "EYEBALL", len = 1.33 },
        ej_lab_zsu_23_4_pl     = { ch = "EYEBALL", len = 1.47 },
        ej_lab_sa_14_manpads   = { ch = "EYEBALL", len = 1.24 },
        ej_lab_sa_18_manpads   = { ch = "EYEBALL", len = 1.20 },
        ej_lab_sa_3_radar      = { ch = "EYEBALL", len = 0.88 },
        ej_lab_sa_3_radar_pl   = { ch = "EYEBALL", len = 1.07 },
        ej_lab_sa_3_launcher   = { ch = "EYEBALL", len = 0.94 },
        ej_lab_sa_3_launcher_pl = { ch = "EYEBALL", len = 0.98 },
        ej_lab_t_55_tank       = { ch = "EYEBALL", len = 1.03 },
        ej_lab_t_55_tank_pl    = { ch = "EYEBALL", len = 1.19 },
        ej_lab_t_72_tank       = { ch = "EYEBALL", len = 1.00 },
        ej_lab_t_72_tank_pl    = { ch = "EYEBALL", len = 1.06 },
        ej_lab_btr             = { ch = "EYEBALL", len = 0.69 },
        ej_lab_btr_pl          = { ch = "EYEBALL", len = 0.93 },
        ej_lab_bmp             = { ch = "EYEBALL", len = 0.70 },
        ej_lab_bmp_pl          = { ch = "EYEBALL", len = 0.84 },
        ej_lab_truck           = { ch = "EYEBALL", len = 0.32 },
        ej_lab_truck_pl        = { ch = "EYEBALL", len = 0.40 },
        ej_lab_infantry        = { ch = "EYEBALL", len = 0.54 },
        ej_lab_technical       = { ch = "EYEBALL", len = 0.48 },
        ej_lab_technical_pl    = { ch = "EYEBALL", len = 0.55 },
        ej_lab_sp_howitzer     = { ch = "EYEBALL", len = 1.03 },
        ej_lab_sp_howitzer_pl  = { ch = "EYEBALL", len = 1.13 },
        ej_ord_one_agm_65e     = { ch = "EYEBALL", len = 1.59 },
        ej_ord_one_gbu_12      = { ch = "EYEBALL", len = 1.03 },
        ej_egress              = { ch = "EYEBALL", len = 1.58 },
        ej_ci_a                = { ch = "EYEBALL", len = 5.78 },
        ej_w_plus              = { ch = "EYEBALL", len = 0.38 },
        ej_ci_enemy            = { ch = "EYEBALL", len = 0.49 },
        ej_ci_fr_bravo         = { ch = "EYEBALL", len = 3.48 },
        ej_ci_fr_team          = { ch = "EYEBALL", len = 2.18 },
        ej_w_of_tgt            = { ch = "EYEBALL", len = 0.55 },
        ej_ci_wind             = { ch = "EYEBALL", len = 1.89 },
        ej_ci_calm             = { ch = "EYEBALL", len = 2.40 },
        ej_w_at                = { ch = "EYEBALL", len = 0.24 },
        ej_ci_end              = { ch = "EYEBALL", len = 4.63 },
        ej_gp_t1               = { ch = "EYEBALL", len = 2.35 },
        ej_gp_t2               = { ch = "EYEBALL", len = 2.51 },
        ej_gp_t2c              = { ch = "EYEBALL", len = 2.64 },
        ej_gp_end              = { ch = "EYEBALL", len = 1.49 },
        ej_cs                  = { ch = "EYEBALL", len = 0.84 },
        ej_ip_lynx             = { ch = "EYEBALL", len = 0.42 },
        ej_ip_puma             = { ch = "EYEBALL", len = 0.40 },
        ej_ip_jackal           = { ch = "EYEBALL", len = 0.43 },
        ej_ip_cobra            = { ch = "EYEBALL", len = 0.41 },
        ej_w_keyhole           = { ch = "EYEBALL", len = 0.46 },
        ej_w_laser             = { ch = "EYEBALL", len = 0.46 },
        ej_w_toc               = { ch = "EYEBALL", len = 0.95 },
        ej_nl_end              = { ch = "EYEBALL", len = 1.40 },
        ej_rm_a                = { ch = "EYEBALL", len = 1.22 },
        ej_rm_ltl              = { ch = "EYEBALL", len = 1.07 },
        ej_rm_threat           = { ch = "EYEBALL", len = 0.29 },
        ej_rm_caution          = { ch = "EYEBALL", len = 1.43 },
        ej_rm_via              = { ch = "EYEBALL", len = 1.27 },
        ej_w_caution           = { ch = "EYEBALL", len = 0.50 },
        ej_rm_route            = { ch = "EYEBALL", len = 1.04 },
        ej_rm_req              = { ch = "EYEBALL", len = 0.51 },
        ej_rm_hd               = { ch = "EYEBALL", len = 1.64 },
        ej_rm_fah              = { ch = "EYEBALL", len = 1.74 },
        ej_w_to                = { ch = "EYEBALL", len = 0.28 },
        ej_rm_end              = { ch = "EYEBALL", len = 1.28 },
        ej_rb_ok               = { ch = "EYEBALL", len = 1.48 },
        ej_w_call_laser        = { ch = "EYEBALL", len = 0.73 },
        ej_rb_neg              = { ch = "EYEBALL", len = 1.18 },
        ej_w_elev              = { ch = "EYEBALL", len = 0.59 },
        ej_w_grid              = { ch = "EYEBALL", len = 0.42 },
        ej_w_fah               = { ch = "EYEBALL", len = 0.91 },
        ej_w_readback          = { ch = "EYEBALL", len = 0.58 },
        ej_say_rb              = { ch = "EYEBALL", len = 2.32 },
        ej_cont                = { ch = "EYEBALL", len = 1.28 },
        ej_clr_hot             = { ch = "EYEBALL", len = 1.44 },
        ej_blind               = { ch = "EYEBALL", len = 1.77 },
        ej_cont_tally          = { ch = "EYEBALL", len = 2.85 },
        ej_w_abort             = { ch = "EYEBALL", len = 0.39 },
        ej_ab_fah              = { ch = "EYEBALL", len = 1.69 },
        ej_ab_civ              = { ch = "EYEBALL", len = 1.85 },
        ej_lasing              = { ch = "EYEBALL", len = 1.13 },
        ej_unable_los          = { ch = "EYEBALL", len = 2.56 },
        ej_neg_resp            = { ch = "EYEBALL", len = 1.79 },
        ej_laser_off           = { ch = "EYEBALL", len = 1.39 },
        ej_laser_to            = { ch = "EYEBALL", len = 3.29 },
        ej_not_clr             = { ch = "EYEBALL", len = 3.04 },
        ej_aft_abort           = { ch = "EYEBALL", len = 3.70 },
        ej_term                = { ch = "EYEBALL", len = 5.39 },
        ej_as_a                = { ch = "EYEBALL", len = 1.71 },
        ej_w_splash            = { ch = "EYEBALL", len = 0.56 },
        ej_as_good             = { ch = "EYEBALL", len = 0.55 },
        ej_as_next             = { ch = "EYEBALL", len = 0.71 },
        ej_as_from             = { ch = "EYEBALL", len = 0.71 },
        ej_as_shift            = { ch = "EYEBALL", len = 0.68 },
        ej_as_rin              = { ch = "EYEBALL", len = 0.61 },
        ej_as_miss             = { ch = "EYEBALL", len = 0.45 },
        ej_bda_a               = { ch = "EYEBALL", len = 1.28 },
        ej_w_destroyed         = { ch = "EYEBALL", len = 0.56 },
        ej_w_notobs            = { ch = "EYEBALL", len = 0.71 },
        ej_bda_act             = { ch = "EYEBALL", len = 1.74 },
        ej_w_time              = { ch = "EYEBALL", len = 0.43 },
        ej_w_local             = { ch = "EYEBALL", len = 0.43 },
        ej_bda_rmk             = { ch = "EYEBALL", len = 0.93 },
        ej_bda_end             = { ch = "EYEBALL", len = 2.29 },
        ej_bda_wnc             = { ch = "EYEBALL", len = 2.39 },
        ej_w_none_obs          = { ch = "EYEBALL", len = 0.68 },
        ej_w_activity          = { ch = "EYEBALL", len = 0.67 },
        ej_w_remaining         = { ch = "EYEBALL", len = 1.33 },
        ej_bda_end_inc         = { ch = "EYEBALL", len = 2.23 },
        ej_nj_a                = { ch = "EYEBALL", len = 1.26 },
        ej_nj_bravo            = { ch = "EYEBALL", len = 1.07 },
        ej_nj_me               = { ch = "EYEBALL", len = 0.88 },
        ej_off_copy            = { ch = "EYEBALL", len = 1.12 },
        ej_off_reatk           = { ch = "EYEBALL", len = 2.17 },
        ej_area_clear          = { ch = "EYEBALL", len = 2.80 },
        ej_iauth               = { ch = "EYEBALL", len = 2.31 },
        ej_spf_dis             = { ch = "EYEBALL", len = 1.86 },
        ej_spf_neg             = { ch = "EYEBALL", len = 3.71 },
        ej_spf_adv             = { ch = "EYEBALL", len = 3.82 },
        ej_w_and               = { ch = "EYEBALL", len = 0.33 },
        ej_w_meters            = { ch = "EYEBALL", len = 0.47 },
        ej_w_desired_destroy   = { ch = "EYEBALL", len = 1.27 },
        ej_w_withdrawing       = { ch = "EYEBALL", len = 0.62 },
        ej_w_location          = { ch = "EYEBALL", len = 0.61 },
        ej_w_still_threat      = { ch = "EYEBALL", len = 1.18 },
        ej_w_point             = { ch = "EYEBALL", len = 0.37 },
        ej_w_hundred           = { ch = "EYEBALL", len = 0.42 },
        ej_w_thousand          = { ch = "EYEBALL", len = 0.48 },
        aj_n_0                 = { ch = "AXEMAN", len = 0.61 },
        aj_n_1                 = { ch = "AXEMAN", len = 0.45 },
        aj_n_2                 = { ch = "AXEMAN", len = 0.40 },
        aj_n_3                 = { ch = "AXEMAN", len = 0.36 },
        aj_n_4                 = { ch = "AXEMAN", len = 0.38 },
        aj_n_5                 = { ch = "AXEMAN", len = 0.50 },
        aj_n_6                 = { ch = "AXEMAN", len = 0.46 },
        aj_n_7                 = { ch = "AXEMAN", len = 0.49 },
        aj_n_8                 = { ch = "AXEMAN", len = 0.53 },
        aj_n_9                 = { ch = "AXEMAN", len = 0.55 },
        aj_l_a                 = { ch = "AXEMAN", len = 0.54 },
        aj_l_b                 = { ch = "AXEMAN", len = 0.46 },
        aj_l_c                 = { ch = "AXEMAN", len = 0.50 },
        aj_l_d                 = { ch = "AXEMAN", len = 0.48 },
        aj_l_e                 = { ch = "AXEMAN", len = 0.41 },
        aj_l_f                 = { ch = "AXEMAN", len = 0.71 },
        aj_l_g                 = { ch = "AXEMAN", len = 0.45 },
        aj_l_h                 = { ch = "AXEMAN", len = 0.52 },
        aj_l_i                 = { ch = "AXEMAN", len = 0.57 },
        aj_l_j                 = { ch = "AXEMAN", len = 0.61 },
        aj_l_k                 = { ch = "AXEMAN", len = 0.41 },
        aj_l_l                 = { ch = "AXEMAN", len = 0.59 },
        aj_l_m                 = { ch = "AXEMAN", len = 0.37 },
        aj_l_n                 = { ch = "AXEMAN", len = 0.66 },
        aj_l_o                 = { ch = "AXEMAN", len = 0.54 },
        aj_l_p                 = { ch = "AXEMAN", len = 0.51 },
        aj_l_q                 = { ch = "AXEMAN", len = 0.52 },
        aj_l_r                 = { ch = "AXEMAN", len = 0.69 },
        aj_l_s                 = { ch = "AXEMAN", len = 0.54 },
        aj_l_t                 = { ch = "AXEMAN", len = 0.51 },
        aj_l_u                 = { ch = "AXEMAN", len = 0.59 },
        aj_l_v                 = { ch = "AXEMAN", len = 0.42 },
        aj_l_w                 = { ch = "AXEMAN", len = 0.49 },
        aj_l_x                 = { ch = "AXEMAN", len = 0.83 },
        aj_l_y                 = { ch = "AXEMAN", len = 0.54 },
        aj_l_z                 = { ch = "AXEMAN", len = 0.51 },
        aj_d_north             = { ch = "AXEMAN", len = 0.43 },
        aj_d_northeast         = { ch = "AXEMAN", len = 0.76 },
        aj_d_east              = { ch = "AXEMAN", len = 0.50 },
        aj_d_southeast         = { ch = "AXEMAN", len = 0.88 },
        aj_d_south             = { ch = "AXEMAN", len = 0.55 },
        aj_d_southwest         = { ch = "AXEMAN", len = 0.67 },
        aj_d_west              = { ch = "AXEMAN", len = 0.56 },
        aj_d_northwest         = { ch = "AXEMAN", len = 0.81 },
        aj_lab_sa_8_launcher   = { ch = "AXEMAN", len = 1.04 },
        aj_lab_sa_8_launcher_pl = { ch = "AXEMAN", len = 1.09 },
        aj_lab_sa_13_launcher  = { ch = "AXEMAN", len = 1.45 },
        aj_lab_sa_13_launcher_pl = { ch = "AXEMAN", len = 1.67 },
        aj_lab_sa_15           = { ch = "AXEMAN", len = 1.02 },
        aj_lab_sa_15_pl        = { ch = "AXEMAN", len = 1.14 },
        aj_lab_sa_15_m2        = { ch = "AXEMAN", len = 1.15 },
        aj_lab_sa_15_m2_pl     = { ch = "AXEMAN", len = 1.28 },
        aj_lab_sa_6_radar      = { ch = "AXEMAN", len = 1.15 },
        aj_lab_sa_6_radar_pl   = { ch = "AXEMAN", len = 1.41 },
        aj_lab_sa_6_launcher   = { ch = "AXEMAN", len = 1.37 },
        aj_lab_sa_6_launcher_pl = { ch = "AXEMAN", len = 1.18 },
        aj_lab_sa_6            = { ch = "AXEMAN", len = 0.82 },
        aj_lab_sa_6_pl         = { ch = "AXEMAN", len = 1.01 },
        aj_lab_sa_3            = { ch = "AXEMAN", len = 0.83 },
        aj_lab_sa_3_pl         = { ch = "AXEMAN", len = 1.00 },
        aj_lab_sa_10           = { ch = "AXEMAN", len = 0.79 },
        aj_lab_sa_10_pl        = { ch = "AXEMAN", len = 0.74 },
        aj_lab_sa_11           = { ch = "AXEMAN", len = 0.91 },
        aj_lab_sa_11_pl        = { ch = "AXEMAN", len = 0.86 },
        aj_lab_sa_8            = { ch = "AXEMAN", len = 1.23 },
        aj_lab_sa_8_pl         = { ch = "AXEMAN", len = 0.76 },
        aj_lab_sa_19           = { ch = "AXEMAN", len = 0.92 },
        aj_lab_sa_19_pl        = { ch = "AXEMAN", len = 0.99 },
        aj_lab_zsu_23_4        = { ch = "AXEMAN", len = 1.74 },
        aj_lab_zsu_23_4_pl     = { ch = "AXEMAN", len = 2.23 },
        aj_lab_sa_14_manpads   = { ch = "AXEMAN", len = 1.33 },
        aj_lab_sa_18_manpads   = { ch = "AXEMAN", len = 1.38 },
        aj_lab_sa_3_radar      = { ch = "AXEMAN", len = 1.21 },
        aj_lab_sa_3_radar_pl   = { ch = "AXEMAN", len = 1.15 },
        aj_lab_sa_3_launcher   = { ch = "AXEMAN", len = 1.56 },
        aj_lab_sa_3_launcher_pl = { ch = "AXEMAN", len = 1.17 },
        aj_lab_t_55_tank       = { ch = "AXEMAN", len = 1.17 },
        aj_lab_t_55_tank_pl    = { ch = "AXEMAN", len = 1.26 },
        aj_lab_t_72_tank       = { ch = "AXEMAN", len = 1.48 },
        aj_lab_t_72_tank_pl    = { ch = "AXEMAN", len = 1.64 },
        aj_lab_btr             = { ch = "AXEMAN", len = 0.99 },
        aj_lab_btr_pl          = { ch = "AXEMAN", len = 1.14 },
        aj_lab_bmp             = { ch = "AXEMAN", len = 0.78 },
        aj_lab_bmp_pl          = { ch = "AXEMAN", len = 1.41 },
        aj_lab_truck           = { ch = "AXEMAN", len = 0.40 },
        aj_lab_truck_pl        = { ch = "AXEMAN", len = 0.45 },
        aj_lab_infantry        = { ch = "AXEMAN", len = 0.76 },
        aj_lab_technical       = { ch = "AXEMAN", len = 0.59 },
        aj_lab_technical_pl    = { ch = "AXEMAN", len = 0.74 },
        aj_lab_sp_howitzer     = { ch = "AXEMAN", len = 1.31 },
        aj_lab_sp_howitzer_pl  = { ch = "AXEMAN", len = 1.35 },
        aj_ord_one_agm_65e     = { ch = "AXEMAN", len = 2.47 },
        aj_ord_one_gbu_12      = { ch = "AXEMAN", len = 1.11 },
        aj_egress              = { ch = "AXEMAN", len = 1.66 },
        aj_ci_a                = { ch = "AXEMAN", len = 5.81 },
        aj_w_plus              = { ch = "AXEMAN", len = 0.52 },
        aj_ci_enemy            = { ch = "AXEMAN", len = 0.52 },
        aj_ci_fr_bravo         = { ch = "AXEMAN", len = 3.53 },
        aj_ci_fr_team          = { ch = "AXEMAN", len = 2.15 },
        aj_w_of_tgt            = { ch = "AXEMAN", len = 0.87 },
        aj_ci_wind             = { ch = "AXEMAN", len = 2.23 },
        aj_ci_calm             = { ch = "AXEMAN", len = 2.45 },
        aj_w_at                = { ch = "AXEMAN", len = 0.44 },
        aj_ci_end              = { ch = "AXEMAN", len = 4.97 },
        aj_gp_t1               = { ch = "AXEMAN", len = 2.86 },
        aj_gp_t2               = { ch = "AXEMAN", len = 2.94 },
        aj_gp_t2c              = { ch = "AXEMAN", len = 3.01 },
        aj_gp_end              = { ch = "AXEMAN", len = 1.66 },
        aj_cs                  = { ch = "AXEMAN", len = 1.18 },
        aj_ip_lynx             = { ch = "AXEMAN", len = 0.51 },
        aj_ip_puma             = { ch = "AXEMAN", len = 0.57 },
        aj_ip_jackal           = { ch = "AXEMAN", len = 0.48 },
        aj_ip_cobra            = { ch = "AXEMAN", len = 0.51 },
        aj_w_keyhole           = { ch = "AXEMAN", len = 0.51 },
        aj_w_laser             = { ch = "AXEMAN", len = 0.58 },
        aj_w_toc               = { ch = "AXEMAN", len = 0.99 },
        aj_nl_end              = { ch = "AXEMAN", len = 1.61 },
        aj_rm_a                = { ch = "AXEMAN", len = 1.43 },
        aj_rm_ltl              = { ch = "AXEMAN", len = 1.26 },
        aj_rm_threat           = { ch = "AXEMAN", len = 0.45 },
        aj_rm_caution          = { ch = "AXEMAN", len = 1.55 },
        aj_rm_via              = { ch = "AXEMAN", len = 1.57 },
        aj_w_caution           = { ch = "AXEMAN", len = 0.55 },
        aj_rm_route            = { ch = "AXEMAN", len = 1.24 },
        aj_rm_req              = { ch = "AXEMAN", len = 0.63 },
        aj_rm_hd               = { ch = "AXEMAN", len = 2.00 },
        aj_rm_fah              = { ch = "AXEMAN", len = 1.70 },
        aj_w_to                = { ch = "AXEMAN", len = 0.30 },
        aj_rm_end              = { ch = "AXEMAN", len = 1.26 },
        aj_rb_ok               = { ch = "AXEMAN", len = 2.03 },
        aj_w_call_laser        = { ch = "AXEMAN", len = 0.85 },
        aj_rb_neg              = { ch = "AXEMAN", len = 1.67 },
        aj_w_elev              = { ch = "AXEMAN", len = 0.72 },
        aj_w_grid              = { ch = "AXEMAN", len = 0.51 },
        aj_w_fah               = { ch = "AXEMAN", len = 1.05 },
        aj_w_readback          = { ch = "AXEMAN", len = 0.71 },
        aj_say_rb              = { ch = "AXEMAN", len = 2.84 },
        aj_cont                = { ch = "AXEMAN", len = 1.68 },
        aj_clr_hot             = { ch = "AXEMAN", len = 1.54 },
        aj_blind               = { ch = "AXEMAN", len = 2.09 },
        aj_cont_tally          = { ch = "AXEMAN", len = 2.78 },
        aj_w_abort             = { ch = "AXEMAN", len = 0.49 },
        aj_ab_fah              = { ch = "AXEMAN", len = 1.74 },
        aj_ab_civ              = { ch = "AXEMAN", len = 2.05 },
        aj_lasing              = { ch = "AXEMAN", len = 1.46 },
        aj_unable_los          = { ch = "AXEMAN", len = 2.74 },
        aj_neg_resp            = { ch = "AXEMAN", len = 2.04 },
        aj_laser_off           = { ch = "AXEMAN", len = 1.68 },
        aj_laser_to            = { ch = "AXEMAN", len = 3.99 },
        aj_not_clr             = { ch = "AXEMAN", len = 3.82 },
        aj_aft_abort           = { ch = "AXEMAN", len = 3.63 },
        aj_term                = { ch = "AXEMAN", len = 5.98 },
        aj_as_a                = { ch = "AXEMAN", len = 2.34 },
        aj_w_splash            = { ch = "AXEMAN", len = 0.74 },
        aj_as_good             = { ch = "AXEMAN", len = 0.69 },
        aj_as_next             = { ch = "AXEMAN", len = 0.88 },
        aj_as_from             = { ch = "AXEMAN", len = 0.84 },
        aj_as_shift            = { ch = "AXEMAN", len = 0.66 },
        aj_as_rin              = { ch = "AXEMAN", len = 0.64 },
        aj_as_miss             = { ch = "AXEMAN", len = 0.45 },
        aj_bda_a               = { ch = "AXEMAN", len = 1.24 },
        aj_w_destroyed         = { ch = "AXEMAN", len = 0.79 },
        aj_w_notobs            = { ch = "AXEMAN", len = 0.83 },
        aj_bda_act             = { ch = "AXEMAN", len = 1.97 },
        aj_w_time              = { ch = "AXEMAN", len = 0.45 },
        aj_w_local             = { ch = "AXEMAN", len = 0.66 },
        aj_bda_rmk             = { ch = "AXEMAN", len = 0.91 },
        aj_bda_end             = { ch = "AXEMAN", len = 2.61 },
        aj_bda_wnc             = { ch = "AXEMAN", len = 2.17 },
        aj_w_none_obs          = { ch = "AXEMAN", len = 0.76 },
        aj_w_activity          = { ch = "AXEMAN", len = 0.82 },
        aj_w_remaining         = { ch = "AXEMAN", len = 1.17 },
        aj_bda_end_inc         = { ch = "AXEMAN", len = 2.71 },
        aj_nj_a                = { ch = "AXEMAN", len = 1.66 },
        aj_nj_bravo            = { ch = "AXEMAN", len = 1.33 },
        aj_nj_me               = { ch = "AXEMAN", len = 1.01 },
        aj_off_copy            = { ch = "AXEMAN", len = 1.34 },
        aj_off_reatk           = { ch = "AXEMAN", len = 2.24 },
        aj_area_clear          = { ch = "AXEMAN", len = 2.75 },
        aj_iauth               = { ch = "AXEMAN", len = 2.93 },
        aj_spf_dis             = { ch = "AXEMAN", len = 1.94 },
        aj_spf_neg             = { ch = "AXEMAN", len = 3.95 },
        aj_spf_adv             = { ch = "AXEMAN", len = 4.33 },
        aj_w_and               = { ch = "AXEMAN", len = 0.50 },
        aj_w_meters            = { ch = "AXEMAN", len = 0.57 },
        aj_w_desired_destroy   = { ch = "AXEMAN", len = 1.70 },
        aj_w_withdrawing       = { ch = "AXEMAN", len = 0.75 },
        aj_w_location          = { ch = "AXEMAN", len = 0.71 },
        aj_w_still_threat      = { ch = "AXEMAN", len = 1.30 },
        aj_w_point             = { ch = "AXEMAN", len = 0.44 },
        aj_w_hundred           = { ch = "AXEMAN", len = 0.59 },
        aj_w_thousand          = { ch = "AXEMAN", len = 0.51 },
        dj_n_0                 = { ch = "DARKNIGHT", len = 0.53 },
        dj_n_1                 = { ch = "DARKNIGHT", len = 0.32 },
        dj_n_2                 = { ch = "DARKNIGHT", len = 0.44 },
        dj_n_3                 = { ch = "DARKNIGHT", len = 0.37 },
        dj_n_4                 = { ch = "DARKNIGHT", len = 0.36 },
        dj_n_5                 = { ch = "DARKNIGHT", len = 0.45 },
        dj_n_6                 = { ch = "DARKNIGHT", len = 0.60 },
        dj_n_7                 = { ch = "DARKNIGHT", len = 0.44 },
        dj_n_8                 = { ch = "DARKNIGHT", len = 0.43 },
        dj_n_9                 = { ch = "DARKNIGHT", len = 0.63 },
        dj_l_a                 = { ch = "DARKNIGHT", len = 0.61 },
        dj_l_b                 = { ch = "DARKNIGHT", len = 0.54 },
        dj_l_c                 = { ch = "DARKNIGHT", len = 0.46 },
        dj_l_d                 = { ch = "DARKNIGHT", len = 0.52 },
        dj_l_e                 = { ch = "DARKNIGHT", len = 0.44 },
        dj_l_f                 = { ch = "DARKNIGHT", len = 0.69 },
        dj_l_g                 = { ch = "DARKNIGHT", len = 0.39 },
        dj_l_h                 = { ch = "DARKNIGHT", len = 0.54 },
        dj_l_i                 = { ch = "DARKNIGHT", len = 0.47 },
        dj_l_j                 = { ch = "DARKNIGHT", len = 0.67 },
        dj_l_k                 = { ch = "DARKNIGHT", len = 0.60 },
        dj_l_l                 = { ch = "DARKNIGHT", len = 0.66 },
        dj_l_m                 = { ch = "DARKNIGHT", len = 0.41 },
        dj_l_n                 = { ch = "DARKNIGHT", len = 0.69 },
        dj_l_o                 = { ch = "DARKNIGHT", len = 0.54 },
        dj_l_p                 = { ch = "DARKNIGHT", len = 0.37 },
        dj_l_q                 = { ch = "DARKNIGHT", len = 0.52 },
        dj_l_r                 = { ch = "DARKNIGHT", len = 0.65 },
        dj_l_s                 = { ch = "DARKNIGHT", len = 0.80 },
        dj_l_t                 = { ch = "DARKNIGHT", len = 0.50 },
        dj_l_u                 = { ch = "DARKNIGHT", len = 0.66 },
        dj_l_v                 = { ch = "DARKNIGHT", len = 0.44 },
        dj_l_w                 = { ch = "DARKNIGHT", len = 0.54 },
        dj_l_x                 = { ch = "DARKNIGHT", len = 0.83 },
        dj_l_y                 = { ch = "DARKNIGHT", len = 0.58 },
        dj_l_z                 = { ch = "DARKNIGHT", len = 0.46 },
        dj_d_north             = { ch = "DARKNIGHT", len = 0.54 },
        dj_d_northeast         = { ch = "DARKNIGHT", len = 0.84 },
        dj_d_east              = { ch = "DARKNIGHT", len = 0.39 },
        dj_d_southeast         = { ch = "DARKNIGHT", len = 1.13 },
        dj_d_south             = { ch = "DARKNIGHT", len = 0.62 },
        dj_d_southwest         = { ch = "DARKNIGHT", len = 0.90 },
        dj_d_west              = { ch = "DARKNIGHT", len = 0.49 },
        dj_d_northwest         = { ch = "DARKNIGHT", len = 0.87 },
        dj_lab_sa_8_launcher   = { ch = "DARKNIGHT", len = 1.21 },
        dj_lab_sa_8_launcher_pl = { ch = "DARKNIGHT", len = 1.30 },
        dj_lab_sa_13_launcher  = { ch = "DARKNIGHT", len = 1.20 },
        dj_lab_sa_13_launcher_pl = { ch = "DARKNIGHT", len = 1.43 },
        dj_lab_sa_15           = { ch = "DARKNIGHT", len = 1.04 },
        dj_lab_sa_15_pl        = { ch = "DARKNIGHT", len = 1.11 },
        dj_lab_sa_15_m2        = { ch = "DARKNIGHT", len = 1.17 },
        dj_lab_sa_15_m2_pl     = { ch = "DARKNIGHT", len = 1.45 },
        dj_lab_sa_6_radar      = { ch = "DARKNIGHT", len = 1.12 },
        dj_lab_sa_6_radar_pl   = { ch = "DARKNIGHT", len = 1.39 },
        dj_lab_sa_6_launcher   = { ch = "DARKNIGHT", len = 0.95 },
        dj_lab_sa_6_launcher_pl = { ch = "DARKNIGHT", len = 1.34 },
        dj_lab_sa_6            = { ch = "DARKNIGHT", len = 0.90 },
        dj_lab_sa_6_pl         = { ch = "DARKNIGHT", len = 0.85 },
        dj_lab_sa_3            = { ch = "DARKNIGHT", len = 0.97 },
        dj_lab_sa_3_pl         = { ch = "DARKNIGHT", len = 0.87 },
        dj_lab_sa_10           = { ch = "DARKNIGHT", len = 0.76 },
        dj_lab_sa_10_pl        = { ch = "DARKNIGHT", len = 1.09 },
        dj_lab_sa_11           = { ch = "DARKNIGHT", len = 1.03 },
        dj_lab_sa_11_pl        = { ch = "DARKNIGHT", len = 1.18 },
        dj_lab_sa_8            = { ch = "DARKNIGHT", len = 0.70 },
        dj_lab_sa_8_pl         = { ch = "DARKNIGHT", len = 0.82 },
        dj_lab_sa_19           = { ch = "DARKNIGHT", len = 0.90 },
        dj_lab_sa_19_pl        = { ch = "DARKNIGHT", len = 1.12 },
        dj_lab_zsu_23_4        = { ch = "DARKNIGHT", len = 1.85 },
        dj_lab_zsu_23_4_pl     = { ch = "DARKNIGHT", len = 2.14 },
        dj_lab_sa_14_manpads   = { ch = "DARKNIGHT", len = 1.37 },
        dj_lab_sa_18_manpads   = { ch = "DARKNIGHT", len = 1.72 },
        dj_lab_sa_3_radar      = { ch = "DARKNIGHT", len = 1.19 },
        dj_lab_sa_3_radar_pl   = { ch = "DARKNIGHT", len = 1.06 },
        dj_lab_sa_3_launcher   = { ch = "DARKNIGHT", len = 1.19 },
        dj_lab_sa_3_launcher_pl = { ch = "DARKNIGHT", len = 1.35 },
        dj_lab_t_55_tank       = { ch = "DARKNIGHT", len = 1.04 },
        dj_lab_t_55_tank_pl    = { ch = "DARKNIGHT", len = 1.13 },
        dj_lab_t_72_tank       = { ch = "DARKNIGHT", len = 1.41 },
        dj_lab_t_72_tank_pl    = { ch = "DARKNIGHT", len = 1.64 },
        dj_lab_btr             = { ch = "DARKNIGHT", len = 0.82 },
        dj_lab_btr_pl          = { ch = "DARKNIGHT", len = 1.21 },
        dj_lab_bmp             = { ch = "DARKNIGHT", len = 0.82 },
        dj_lab_bmp_pl          = { ch = "DARKNIGHT", len = 1.54 },
        dj_lab_truck           = { ch = "DARKNIGHT", len = 0.33 },
        dj_lab_truck_pl        = { ch = "DARKNIGHT", len = 0.56 },
        dj_lab_infantry        = { ch = "DARKNIGHT", len = 0.67 },
        dj_lab_technical       = { ch = "DARKNIGHT", len = 0.62 },
        dj_lab_technical_pl    = { ch = "DARKNIGHT", len = 0.73 },
        dj_lab_sp_howitzer     = { ch = "DARKNIGHT", len = 1.23 },
        dj_lab_sp_howitzer_pl  = { ch = "DARKNIGHT", len = 1.33 },
        dj_ord_one_agm_65e     = { ch = "DARKNIGHT", len = 1.97 },
        dj_ord_one_gbu_12      = { ch = "DARKNIGHT", len = 1.76 },
        dj_egress              = { ch = "DARKNIGHT", len = 1.27 },
        dj_ci_a                = { ch = "DARKNIGHT", len = 5.54 },
        dj_w_plus              = { ch = "DARKNIGHT", len = 0.51 },
        dj_ci_enemy            = { ch = "DARKNIGHT", len = 0.52 },
        dj_ci_fr_bravo         = { ch = "DARKNIGHT", len = 3.68 },
        dj_ci_fr_team          = { ch = "DARKNIGHT", len = 1.94 },
        dj_w_of_tgt            = { ch = "DARKNIGHT", len = 0.87 },
        dj_ci_wind             = { ch = "DARKNIGHT", len = 2.18 },
        dj_ci_calm             = { ch = "DARKNIGHT", len = 2.44 },
        dj_w_at                = { ch = "DARKNIGHT", len = 0.35 },
        dj_ci_end              = { ch = "DARKNIGHT", len = 4.86 },
        dj_gp_t1               = { ch = "DARKNIGHT", len = 3.00 },
        dj_gp_t2               = { ch = "DARKNIGHT", len = 2.75 },
        dj_gp_t2c              = { ch = "DARKNIGHT", len = 3.57 },
        dj_gp_end              = { ch = "DARKNIGHT", len = 1.53 },
        dj_cs                  = { ch = "DARKNIGHT", len = 0.91 },
        dj_ip_lynx             = { ch = "DARKNIGHT", len = 0.67 },
        dj_ip_puma             = { ch = "DARKNIGHT", len = 0.56 },
        dj_ip_jackal           = { ch = "DARKNIGHT", len = 0.50 },
        dj_ip_cobra            = { ch = "DARKNIGHT", len = 0.52 },
        dj_w_keyhole           = { ch = "DARKNIGHT", len = 0.61 },
        dj_w_laser             = { ch = "DARKNIGHT", len = 0.55 },
        dj_w_toc               = { ch = "DARKNIGHT", len = 0.96 },
        dj_nl_end              = { ch = "DARKNIGHT", len = 1.61 },
        dj_rm_a                = { ch = "DARKNIGHT", len = 1.59 },
        dj_rm_ltl              = { ch = "DARKNIGHT", len = 1.17 },
        dj_rm_threat           = { ch = "DARKNIGHT", len = 0.46 },
        dj_rm_caution          = { ch = "DARKNIGHT", len = 1.90 },
        dj_rm_via              = { ch = "DARKNIGHT", len = 1.62 },
        dj_w_caution           = { ch = "DARKNIGHT", len = 0.51 },
        dj_rm_route            = { ch = "DARKNIGHT", len = 1.23 },
        dj_rm_req              = { ch = "DARKNIGHT", len = 0.65 },
        dj_rm_hd               = { ch = "DARKNIGHT", len = 2.03 },
        dj_rm_fah              = { ch = "DARKNIGHT", len = 1.75 },
        dj_w_to                = { ch = "DARKNIGHT", len = 0.32 },
        dj_rm_end              = { ch = "DARKNIGHT", len = 1.41 },
        dj_rb_ok               = { ch = "DARKNIGHT", len = 1.87 },
        dj_w_call_laser        = { ch = "DARKNIGHT", len = 0.80 },
        dj_rb_neg              = { ch = "DARKNIGHT", len = 1.29 },
        dj_w_elev              = { ch = "DARKNIGHT", len = 0.70 },
        dj_w_grid              = { ch = "DARKNIGHT", len = 0.39 },
        dj_w_fah               = { ch = "DARKNIGHT", len = 1.01 },
        dj_w_readback          = { ch = "DARKNIGHT", len = 0.71 },
        dj_say_rb              = { ch = "DARKNIGHT", len = 2.55 },
        dj_cont                = { ch = "DARKNIGHT", len = 1.55 },
        dj_clr_hot             = { ch = "DARKNIGHT", len = 1.72 },
        dj_blind               = { ch = "DARKNIGHT", len = 2.06 },
        dj_cont_tally          = { ch = "DARKNIGHT", len = 2.76 },
        dj_w_abort             = { ch = "DARKNIGHT", len = 0.52 },
        dj_ab_fah              = { ch = "DARKNIGHT", len = 1.72 },
        dj_ab_civ              = { ch = "DARKNIGHT", len = 2.03 },
        dj_lasing              = { ch = "DARKNIGHT", len = 1.54 },
        dj_unable_los          = { ch = "DARKNIGHT", len = 2.98 },
        dj_neg_resp            = { ch = "DARKNIGHT", len = 1.69 },
        dj_laser_off           = { ch = "DARKNIGHT", len = 1.58 },
        dj_laser_to            = { ch = "DARKNIGHT", len = 3.90 },
        dj_not_clr             = { ch = "DARKNIGHT", len = 3.53 },
        dj_aft_abort           = { ch = "DARKNIGHT", len = 3.90 },
        dj_term                = { ch = "DARKNIGHT", len = 5.79 },
        dj_as_a                = { ch = "DARKNIGHT", len = 2.28 },
        dj_w_splash            = { ch = "DARKNIGHT", len = 0.66 },
        dj_as_good             = { ch = "DARKNIGHT", len = 0.66 },
        dj_as_next             = { ch = "DARKNIGHT", len = 0.93 },
        dj_as_from             = { ch = "DARKNIGHT", len = 0.80 },
        dj_as_shift            = { ch = "DARKNIGHT", len = 0.64 },
        dj_as_rin              = { ch = "DARKNIGHT", len = 0.72 },
        dj_as_miss             = { ch = "DARKNIGHT", len = 0.46 },
        dj_bda_a               = { ch = "DARKNIGHT", len = 1.33 },
        dj_w_destroyed         = { ch = "DARKNIGHT", len = 0.87 },
        dj_w_notobs            = { ch = "DARKNIGHT", len = 0.99 },
        dj_bda_act             = { ch = "DARKNIGHT", len = 1.98 },
        dj_w_time              = { ch = "DARKNIGHT", len = 0.47 },
        dj_w_local             = { ch = "DARKNIGHT", len = 0.48 },
        dj_bda_rmk             = { ch = "DARKNIGHT", len = 0.82 },
        dj_bda_end             = { ch = "DARKNIGHT", len = 2.68 },
        dj_bda_wnc             = { ch = "DARKNIGHT", len = 2.02 },
        dj_w_none_obs          = { ch = "DARKNIGHT", len = 0.77 },
        dj_w_activity          = { ch = "DARKNIGHT", len = 0.80 },
        dj_w_remaining         = { ch = "DARKNIGHT", len = 1.27 },
        dj_bda_end_inc         = { ch = "DARKNIGHT", len = 2.74 },
        dj_nj_a                = { ch = "DARKNIGHT", len = 1.82 },
        dj_nj_bravo            = { ch = "DARKNIGHT", len = 1.13 },
        dj_nj_me               = { ch = "DARKNIGHT", len = 0.85 },
        dj_off_copy            = { ch = "DARKNIGHT", len = 1.27 },
        dj_off_reatk           = { ch = "DARKNIGHT", len = 2.18 },
        dj_area_clear          = { ch = "DARKNIGHT", len = 2.61 },
        dj_iauth               = { ch = "DARKNIGHT", len = 3.15 },
        dj_spf_dis             = { ch = "DARKNIGHT", len = 2.13 },
        dj_spf_neg             = { ch = "DARKNIGHT", len = 3.71 },
        dj_spf_adv             = { ch = "DARKNIGHT", len = 4.15 },
        dj_w_and               = { ch = "DARKNIGHT", len = 0.37 },
        dj_w_meters            = { ch = "DARKNIGHT", len = 0.62 },
        dj_w_desired_destroy   = { ch = "DARKNIGHT", len = 1.49 },
        dj_w_withdrawing       = { ch = "DARKNIGHT", len = 0.75 },
        dj_w_location          = { ch = "DARKNIGHT", len = 0.80 },
        dj_w_still_threat      = { ch = "DARKNIGHT", len = 1.27 },
        dj_w_point             = { ch = "DARKNIGHT", len = 0.46 },
        dj_w_hundred           = { ch = "DARKNIGHT", len = 0.52 },
        dj_w_thousand          = { ch = "DARKNIGHT", len = 0.57 },
        jp_ci_ptr              = { ch = "PILOT", len = 2.59 },
        jp_ci_eye              = { ch = "PILOT", len = 2.08 },
        jp_one_hornet          = { ch = "PILOT", len = 0.65 },
        jp_cptiger             = { ch = "PILOT", len = 0.87 },
        jp_for                 = { ch = "PILOT", len = 0.39 },
        jp_overhead            = { ch = "PILOT", len = 1.24 },
        jp_angels              = { ch = "PILOT", len = 0.56 },
        jp_wpn_agm_65e         = { ch = "PILOT", len = 1.33 },
        jp_wpn_gbu_12          = { ch = "PILOT", len = 1.06 },
        jp_gun                 = { ch = "PILOT", len = 0.45 },
        jp_playtime            = { ch = "PILOT", len = 0.56 },
        jp_ci_end              = { ch = "PILOT", len = 2.34 },
        jp_ready_ptr           = { ch = "PILOT", len = 2.49 },
        jp_ready_eye           = { ch = "PILOT", len = 2.55 },
        jp_auth_ptr            = { ch = "PILOT", len = 2.25 },
        jp_auth_eye            = { ch = "PILOT", len = 2.37 },
        jp_ready_rmk           = { ch = "PILOT", len = 1.02 },
        jp_rb_ptr              = { ch = "PILOT", len = 0.76 },
        jp_rb_eye              = { ch = "PILOT", len = 0.80 },
        jp_fah                 = { ch = "PILOT", len = 0.93 },
        jp_to                  = { ch = "PILOT", len = 0.35 },
        jp_ipin                = { ch = "PILOT", len = 1.78 },
        jp_ten                 = { ch = "PILOT", len = 1.72 },
        jp_lon_ptr             = { ch = "PILOT", len = 1.61 },
        jp_lon_eye             = { ch = "PILOT", len = 1.56 },
        jp_shift_ptr           = { ch = "PILOT", len = 1.03 },
        jp_shift_eye           = { ch = "PILOT", len = 1.45 },
        jp_cease_ptr           = { ch = "PILOT", len = 1.76 },
        jp_cease_eye           = { ch = "PILOT", len = 1.70 },
        jp_spot                = { ch = "PILOT", len = 1.19 },
        jp_neglaser            = { ch = "PILOT", len = 1.52 },
        jp_tally               = { ch = "PILOT", len = 1.14 },
        jp_captured            = { ch = "PILOT", len = 1.46 },
        jp_nojoy               = { ch = "PILOT", len = 1.57 },
        jp_in                  = { ch = "PILOT", len = 1.35 },
        jp_off                 = { ch = "PILOT", len = 1.39 },
        jp_dry                 = { ch = "PILOT", len = 0.49 },
        jp_aborting            = { ch = "PILOT", len = 1.35 },
        jp_abort_ack           = { ch = "PILOT", len = 1.36 },
        jp_cs                  = { ch = "PILOT", len = 0.90 },
        jp_wilco               = { ch = "PILOT", len = 1.32 },
        jp_rifle               = { ch = "PILOT", len = 0.58 },
        jp_away                = { ch = "PILOT", len = 0.44 },
        jp_bda_ptr             = { ch = "PILOT", len = 3.97 },
        jp_bda_eye             = { ch = "PILOT", len = 3.57 },
        jp_swo_ptr             = { ch = "PILOT", len = 3.12 },
        jp_swo_eye             = { ch = "PILOT", len = 3.14 },
        jp_hc_ptr              = { ch = "PILOT", len = 2.40 },
        jp_hc_eye              = { ch = "PILOT", len = 2.16 },
        jp_wnc_ptr             = { ch = "PILOT", len = 2.02 },
        jp_wnc_eye             = { ch = "PILOT", len = 1.87 },
        jp_ci_axe              = { ch = "PILOT", len = 2.37 },
        jp_ready_axe           = { ch = "PILOT", len = 2.70 },
        jp_auth_axe            = { ch = "PILOT", len = 2.60 },
        jp_rb_axe              = { ch = "PILOT", len = 0.93 },
        jp_lon_axe             = { ch = "PILOT", len = 1.53 },
        jp_shift_axe           = { ch = "PILOT", len = 1.27 },
        jp_cease_axe           = { ch = "PILOT", len = 1.47 },
        jp_bda_axe             = { ch = "PILOT", len = 4.65 },
        jp_swo_axe             = { ch = "PILOT", len = 3.26 },
        jp_hc_axe              = { ch = "PILOT", len = 2.27 },
        jp_wnc_axe             = { ch = "PILOT", len = 2.38 },
        jp_ci_dkn              = { ch = "PILOT", len = 1.92 },
        jp_ready_dkn           = { ch = "PILOT", len = 2.17 },
        jp_auth_dkn            = { ch = "PILOT", len = 2.21 },
        jp_rb_dkn              = { ch = "PILOT", len = 0.87 },
        jp_lon_dkn             = { ch = "PILOT", len = 1.75 },
        jp_shift_dkn           = { ch = "PILOT", len = 1.38 },
        jp_cease_dkn           = { ch = "PILOT", len = 1.64 },
        jp_bda_dkn             = { ch = "PILOT", len = 3.59 },
        jp_swo_dkn             = { ch = "PILOT", len = 3.20 },
        jp_hc_dkn              = { ch = "PILOT", len = 2.40 },
        jp_wnc_dkn             = { ch = "PILOT", len = 2.38 },
        ovl_rep_ptr            = { ch = "OVERLORD", len = 7.49 },
        ovl_rep_eye            = { ch = "OVERLORD", len = 7.60 },
        ovl_rep_axe            = { ch = "OVERLORD", len = 7.55 },
        ovl_rep_dkn            = { ch = "OVERLORD", len = 7.84 },
    },

    -- Air picture / threat / CAP net (v1.5.0)
    PIC_RANGE_NM    = 120,   -- picture: RED fighter groups within this range of the player
    THREAT_NM       = 35,    -- threat call: HOT/FLANK group inside this range
    THREAT_CLOSE_NM = 20,    -- second threat call: any aspect inside this range
    CAP_COMMIT_NM   = 60,    -- CAP lead ↔ nearest RED fighter: committed
    CAP_CLEAN_TICKS = 6,     -- ticks (× TICK s) with no bandit ≤ CAP_COMMIT_NM + 10 → back to station
    CHAT_TTL        = 45,    -- s an unsolicited call may wait for an idle queue
    FIGHTER_ATTRS   = { "Fighters", "Interceptors", "Multirole fighters" },
    CAP = {                  -- ME group, clip key, spoken callsign
        { group = "CAP-1",   key = "c31", cs = "Check 31" },
        { group = "CAP-2",   key = "c21", cs = "Check 21" },
        { group = "INTER-2", key = "v21", cs = "Viper 21" },
    },

    -- Inject probabilities (integer 0–100)
    PROB_INJ1      = 30,
    PROB_INJ2      = 15,
    PROB_INJ3      = 25,

    TICK           = 5,      -- main tick (s)
    REPLY_GAP      = 2,      -- gap between pilot call and controller reply (s)
    PILOT_HOLD     = 2,      -- pilot call "airtime" before the reply gap starts (s)

    DUR_PILOT      = 7,
    DUR_SHORT      = 8,
    DUR_LONG       = 16,
    DUR_URGENT     = 12,
    DUR_HANDOFF    = 15,

    AIRSTART       = { NM = 60, ALT_AGL_M = 300, SPD_MS = 80 },   -- v1.6.1
    TKR            = {       -- v1.7.0 EMCON 2 tanker radio
        RV_BELOW_ANGELS = 1,     -- RV altitude = tanker angels - 1 (ATP-56 RV: receiver 1,000 ft below)
        FULL_LB  = 13000,        -- "request" = FULL_LB - fuel (DCS stops the flow at ~13,043 lb)
        BRA_NM   = { 20, 10, 5 },-- OVERLORD tanker bearing / range calls until Judy
        RCVD_WAIT = 60,          -- s after the last disconnect if no 0.3 NM departure was measured (v1.7.7: was 30)
        RCVD_FULL_S  = 5,        -- v1.7.9: s after the last disconnect when the hero is full
        RCVD_FULL_LB = 12700,    -- v1.7.9: "full" (DCS stops the flow at ~13,043 lb, FULL_LB 13000)
        AR1_HOLD  = true,        -- v1.7.1 POINTER hand-off waits for AR1 closed (off Texaco / skip AR1)
        MODE3     = "2042",      -- v1.7.4 RV initial call (kneeboard 01 SQUAWK)
        VEC_MIN_MS = 128.6,      -- v1.7.4 own speed floor for the intercept vector (250 kt)
        VEC_MAX_S  = 900,        -- v1.7.4 lead only if the intercept is within 15 min (else pure pursuit)
        OVR_BEHIND_NM = 0.25,    -- v1.7.6 "terminate overrun" when the hero is this far behind the tanker
        BKW_CLEAR_NM  = 0.25,    -- v1.7.6 "terminate emergency separation" when out of contact and this far away
        BKW_MAX_S     = 30,      -- v1.7.6 ... or this long after the breakaway call
    },
    DIVERT         = {       -- v1.7.3 OVERLORD divert branch
        BINGO_TOL_LB = 200,      -- "bingo" in the pilot call when fuel <= TL BINGO + this
        FIELDS = {               -- tower UHF from the DCS Syria terrain data (pydcs export) [K]
            { key = "LTAG", name = "Incirlik", lat = 37.00205,  lon = 35.426083, twr = "360.100", clip = "ltag",
              ank = "240.800" },   -- v1.7.5 Field_Arrival hand-off (Ankara Control, AIP ENR 2.1)
            { key = "LCRA", name = "Akrotiri", lat = 34.590367, lon = 32.987783, twr = "252.000", clip = "lcra" },
        },
    },
    MUD = {                  -- v1.7.9 RWR ground threat calls
        ON        = true,
        TICK      = 2,           -- s
        RESCAN_S  = 60,          -- s between scans for RED radar units (late activations)
        MIN_GAP_S = 20,          -- s between two MUD calls
        REARM_S   = 600,         -- s without a spike from a site before it may be called again
        EYE_M     = 6,           -- m antenna height for the LOS fallback
        -- unit type -> RWR type (spoken) and trNm = fallback range (NM) for a fire-control radar that is ON
        -- (no trNm: search radar, called only when getRadar() reports the hero as its target)
        TYPES = {
            ["SNR_75V"]                = { sym = "2",  trNm = 24 },
            ["snr s-125 tr"]           = { sym = "3",  trNm = 13 },
            ["p-19 s-125 sr"]          = { sym = "3" },
            ["Kub 1S91 str"]           = { sym = "6",  trNm = 13 },
            ["Osa 9A33 ln"]            = { sym = "8",  trNm = 5.5 },
            ["Tor 9A331"]              = { sym = "15", trNm = 6.5 },
            ["CHAP_TorM2"]             = { sym = "15", trNm = 8 },
            ["2S6 Tunguska"]           = { sym = "19", trNm = 4.5 },
            ["S-300PS 40B6M tr"]       = { sym = "10", trNm = 40 },
            ["S-300PS 5H63C 30H6_tr"]  = { sym = "10", trNm = 40 },
            ["S-300PS 64H6E sr"]       = { sym = "10" },
            ["S-300PS 40B6MD sr"]      = { sym = "10" },
            ["S-300PS 40B6MD sr_19J6"] = { sym = "10" },
        },
        SYM_TOK = { ["10"] = "p_n10", ["15"] = "p_n15", ["19"] = "p_n19" },   -- else cv:p_<digit>
        -- CD phase -> frequency the hero is working (no entry = no call)
        CH = { STRIKE_OUT = "STRIKE", STRIKE_CHK = "STRIKE", STRIKE_IN = "STRIKE", INBOUND = "STRIKE",
               OVL_OUT = "OVERLORD", ENROUTE = "OVERLORD", REFUEL = "OVERLORD", TKR_DONE = "OVERLORD",
               RTB = "OVERLORD", DIVERT = "OVERLORD", HOLD = "OVERLORD" },   -- v1.10.0 + JTAC phases below
    },
    REMIND_FIRST   = 60,     -- s after a check-in becomes due before the first repeat
    REMIND_EVERY   = 120,    -- s between further repeats
}
do   -- v1.10.0 roster: per JTAC key (CAS_PACK.order) button, frequency, alternate, voice channel, MUD channel
    for i, k in ipairs(P.order) do
        local j = P.jtacs[k]
        CFG.BTN[k], CFG.FREQ[k] = j.btn, j.freq
        CFG.ALT[k] = { btn = j.alt.btn, freq = j.alt.freq, hz = math.floor(tonumber(j.alt.freq) * 1e6 + 0.5) * 1.0 }
        CFG.CHAN[j.ch] = { hz = math.floor(tonumber(j.freq) * 1e6 + 0.5) * 1.0, mod = radio.modulation.AM }
        CFG.MUD.CH["JTAC" .. i], CFG.MUD.CH[k .. "_OFF"] = j.ch, "OVERLORD"
    end
end

-- ══════════════════════════════════════════════════════════════
--  MODULE STATE
-- ══════════════════════════════════════════════════════════════
local CD = {
    phase         = "IDLE",
    queue         = {},
    qPlaying      = false,
    seen          = {},       -- v1.10.0 key -> target group seen alive (aliases seenJ1 / seenJ2 ...)
    dead          = {},       -- v1.10.0 key -> target group dead / objective done (aliases deadJ1 / deadJ2 ...)
    jd            = {},       -- v1.10.0 key -> INFLTREP data { pos, size, tot } (aliases j1 / j2 ...)
    injArmed      = false,    -- v1.10.0 (was j2Armed): injects of the pack JTAC with injects = true
    tkrCheckedIn  = false,
    refuelDone    = false,
    tk            = nil,      -- v1.7.0 open tanker RV { ar = 1|2, vec, init, judy, bra, rcvd, state, clear }
    ar1Done       = false,    -- v1.7.0 AR1 closed (off Texaco) or not wanted any more
    corridorDone  = false,
    surf          = nil,      -- "LAND" / "WATER" (debounced)
    surfCand      = nil,
    surfCount     = 0,
    feetPending   = nil,      -- "DRY" / "WET" — report offered in F10
    awaiting      = false,    -- pilot call made, controller reply pending
    inj           = { i1 = false, i2 = false, i3 = false },
    chat          = {},       -- v1.5.0 deferred unsolicited calls { t0, fn }
    cap           = {},       -- v1.5.0 per CAP key { state = off|station|commit, clean }
    threat        = {},       -- v1.5.0 per RED group name { far, close } (calls made)
    aborted       = false,    -- v1.5.1 OVERLORD mission abort called (read by Flight_Timeline)
    tic           = nil,      -- v1.5.4 "J1" / "J2" / false (off); nil = not picked yet
    ticState      = nil,
    worked        = {},       -- v1.5.5 J1 / J2 = true once JTAC1 / JTAC2 was entered      -- v1.5.4 { key, n, used, next, done, bda } after the TIC hand-off
    -- v1.8.0 tasking order (read-only for other modules)
    scen          = nil,      -- { kind = "A"|"B"|"C", lc = nil | { key, kind = "tech"|"down" }, noShow }
    tasked        = { (P.tasked or P.order)[1], (P.tasked or P.order)[2] },   -- v1.10.0 the sortie's two taskings, fragged
    order         = { (P.tasked or P.order)[1], (P.tasked or P.order)[2] },   -- order (slots; Tasking_Pick >= v1.3.0)
    cur           = nil,      -- JTAC key being worked (or last worked)
    res           = {},       -- key -> "done" | "incomplete" | "terminated" | "cancelled" | "skipped"
    why           = {},       -- key -> reason of a cancellation ("lost comms", "winchester", ...)
    vulDone       = false,    -- every tasking finished / cancelled (Flight_Timeline T3, Pilot_Banter)
    vulT          = nil,      -- timer.getAbsTime() of vulDone
    vulExtS       = 0,        -- s of C2-directed delay (B hold, C partial Pointer work) added to VUL END
    hold          = nil,      -- B: { t0, armT, fireT }
    dv            = nil,      -- C: { state = armed|asked|accepted|refused|missed, at, t }
    lcs           = {},       -- lost comms progress per key
    ar1Int        = false,    -- AR1 tanker gone: OVERLORD asked "say intentions"
}
_G.TRT = _G.TRT or {}
_G.TRT.CD = CD   -- v1.5.1: read-only view for Flight_Timeline; do not write from outside

-- Phases in which the player is (or should be) working OVERLORD (v1.10.0: + JTAC<n> / <key>_OFF from the roster)
local OVL_PHASES = {
    ENROUTE = true, HOLD = true, REFUEL = true, TKR_DONE = true, RTB = true,
}

-- v1.10.0 roster (ONE local: the main chunk is at Lua's 200-local limit). Per key k of CAS_PACK.order (index n):
-- RS.ph[k] = "JTAC<n>", RS.off[k] = "<k>_OFF", RS.MSN[k]; RS.key[phase] -> k; RS.chKey[voice channel] -> k;
-- RS.injKey = the JTAC with injects = true; RS.idx[k] = n.
local RS = { ph = {}, off = {}, MSN = {}, key = {}, chKey = {}, idx = {} }
for i, k in ipairs(P.order) do
    local j = P.jtacs[k]
    RS.ph[k], RS.off[k], RS.MSN[k], RS.idx[k] = "JTAC" .. i, k .. "_OFF", j.msn, i
    RS.key[RS.ph[k]], RS.key[RS.off[k]], RS.chKey[j.ch] = k, k, k
    OVL_PHASES[RS.ph[k]], OVL_PHASES[RS.off[k]] = true, true
    if j.injects then RS.injKey = k end
    CD.jd[k] = { pos = nil, size = 0, tot = nil }
    CD[k:lower()] = CD.jd[k]                        -- CD.j1 / CD.j2 (Flight_Timeline: j2.tot)
    CD["seen" .. k], CD["dead" .. k] = false, false -- CD.deadJ2 (Flight_Timeline, Pilot_Banter)
end
RS.JD = function(k) return CD.jd[k] end
RS.isJ = function(ph) local k = RS.key[ph]; return k ~= nil and RS.ph[k] == ph end     -- working a JTAC
RS.isOff = function(ph) local k = RS.key[ph]; return k ~= nil and RS.off[k] == ph end  -- a tasking ended
RS.other = function(k) return (k == CD.tasked[1]) and CD.tasked[2] or CD.tasked[1] end -- the other slot

-- ══════════════════════════════════════════════════════════════
--  UTILITIES
-- ══════════════════════════════════════════════════════════════
local function MtoNM(m)   return m / 1852 end
local function Roll(pct)  return math.random(1, 100) <= pct end

local function Player()   return Unit.getByName(CFG.PLAYER_UNIT)  end
local function Carrier()  return Unit.getByName(CFG.CARRIER_UNIT) end
local function Tanker()   return Unit.getByName(CFG.TANKER_UNIT)  end

local function Dist2D(a, b)
    local dx, dz = a.x - b.x, a.z - b.z
    return MtoNM(math.sqrt(dx * dx + dz * dz))
end

--- True bearing (°) from A to B. Vec3: x = north, z = east.
local function Bearing(a, b)
    return math.deg(math.atan2(b.z - a.z, b.x - a.x)) % 360
end

local function BrgMag(a, b)
    return (Bearing(a, b) - CFG.MAGVAR) % 360
end

local function ADiff(a, b)
    local d = (a - b + 360) % 360
    return (d > 180) and (d - 360) or d
end

--- "bears 043 for 37"
local function BrgRng(from, to)
    return string.format("bears %03d for %d",
        math.floor(BrgMag(from, to) + 0.5) % 360, math.floor(Dist2D(from, to) + 0.5))
end

local function Angels(u)
    return math.floor(u:getPoint().y * 3.28084 / 1000 + 0.5)
end

local function State(u)
    local f = u:getFuel() or 0
    return string.format("%.1f", f * CFG.INTERNAL_FUEL_LB / 1000)
end

local function MGRS(pos)
    local ok, s = pcall(function()
        local lat, lon = coord.LOtoLL(pos)
        local m = coord.LLtoMGRS(lat, lon)
        return string.format("%s %s %04d %04d", m.UTMZone, m.MGRSDigraph,
            math.floor(m.Easting / 10), math.floor(m.Northing / 10))
    end)
    return ok and s or "unknown"
end

local function Clock(abs)
    if not abs then return "unknown" end
    local t = math.floor(abs) % 86400
    return string.format("%02d%02dL", math.floor(t / 3600), math.floor((t % 3600) / 60))
end

local function Msg(text, dur, clear)
    local p = Player(); if not p then return end
    trigger.action.outTextForGroup(p:getGroup():getID(), text, dur or CFG.DUR_SHORT, clear or false)
end

local function SetFlag(f, v)  trigger.action.setUserFlag(tostring(f), v) end

--- v1.6.0: scripted JTAC loaded and active (JTAC_Controller)
local function JcOn()
    local jc = _G.TRT and _G.TRT.JC
    return (jc and jc.active) and true or false
end

--- v1.6.2: JTAC_Controller terminated control of JTAC key "J1" / "J2"
--- v1.7.13: JTAC_Controller tasking that ended with targets still alive (Winchester): { destroyed, remaining, total }
local function JcInc(k)
    local jc = _G.TRT and _G.TRT.JC
    local st = jc and jc.active and jc.st and jc.st[k]
    return (st and st.phase == "DONE" and st.incomplete) or nil
end

local function JcTerm(k)
    local jc = _G.TRT and _G.TRT.JC
    if (jc and jc.active and jc.st and jc.st[k] and jc.st[k].phase == "TERMINATED") then return true end
    return JcInc(k) ~= nil   -- v1.7.13 Winchester
end

--- Clip length + file for a token id. "cv:<id>" = CV_Comms clip set (TRT.CV_AUDIO).
local function ClipOf(id)
    local cvid = id:match("^cv:(.+)$")
    if cvid then
        local tbl = _G.TRT and _G.TRT.CV_AUDIO
        local a = tbl and tbl[cvid]
        return a and a.len, ((_G.TRT and _G.TRT.CV_SND_DIR) or "Sounds/CV/") .. cvid .. ".ogg"
    end
    local a = CFG.AUDIO[id]
    return a and a.len, CFG.SND_DIR .. id .. ".ogg"
end

local txn = 0
--- Chained transmission: seq = { ch = "<CHAN>", id | pause(s), ... }. Returns airtime (s).
local function TxSeq(seq)
    local ch, p = CFG.CHAN[seq.ch], Player()
    if not (ch and p) then return 0 end
    local t = 0
    txn = txn + 1
    for i, id in ipairs(seq) do
        if type(id) == "number" then
            t = t + id
        else
            local len, file = ClipOf(id)
            if len then
                local name = "CD_" .. txn .. "_" .. i
                timer.scheduleFunction(function()
                    local u = Player(); if not u then return end
                    local pos = u:getPoint()
                    trigger.action.radioTransmission(file, { x = pos.x, y = pos.y + 30, z = pos.z },
                        ch.mod, false, ch.hz, CFG.TX_POWER, name)
                end, nil, timer.getTime() + t + 0.01)
                t = t + len + ((id == "cv:sq_up") and 0 or 0.03)
            else
                env.info("[CD] missing clip " .. tostring(id))
            end
        end
    end
    return t
end

--- Play voice clip <id> (or a token sequence table) on its agency frequency.
-- Returns clip length (s), 0 if none.
-- @param cut  true → stop the clip currently on air first (urgent calls).
local function Tx(id, cut)
    if cut and CD.txName then pcall(trigger.action.stopRadioTransmission, CD.txName) end
    if type(id) == "table" then return TxSeq(id) end
    local a = id and CFG.AUDIO[id]; if not a then return 0 end
    local ch, p = CFG.CHAN[a.ch], Player()
    if not (ch and p) then return 0 end
    local pos = p:getPoint()
    CD.txName = "CD_" .. id
    trigger.action.radioTransmission(CFG.SND_DIR .. id .. ".ogg",
        { x = pos.x, y = pos.y + 30, z = pos.z }, ch.mod, false, ch.hz, CFG.TX_POWER, CD.txName)
    return a.len
end

local HD_TEXT = "hard deck two-zero thousand MSL in the engagement area"

-- ══════════════════════════════════════════════════════════════
--  CLIP QUEUE
-- ══════════════════════════════════════════════════════════════
--- Push a clip to the end of the queue.
-- @param text   Radio call subtitle.
-- @param dur    Display duration (s).
-- @param after  Gap after the PREVIOUS clip ends before this one fires (s).
-- @param fn     Optional callback run when this clip fires (phase change etc.).
-- @param hold   Time from this clip's start until the next clip may start
--               (default = dur). Shorter than dur → next clip overlaps on screen.
-- @param audio  Optional voice clip id (CFG.AUDIO key). Next clip waits for it.
-- @param onEnd  v1.8.0: callback when the transmission has ENDED (audio + pad, or hold / dur) - menu gates
-- @param tag    v1.8.0: owner tag ("JC:J1" ...) so a suspended tasking can drop its queued traffic
-- @param ack    v1.8.4: automatic pilot acknowledgement (does not hold the menu, GateWaiting)
-- Returns the queued item.
local function Q(text, dur, after, fn, hold, audio, onEnd, tag, ack)
    local it = { text = text, dur = dur or CFG.DUR_SHORT, after = after or 1,
                 fn = fn, hold = hold, audio = audio, onEnd = onEnd, tag = tag, ack = ack or nil }
    table.insert(CD.queue, it)
    return it
end

local function RunEnd(clip)
    if clip and clip.onEnd then
        local f = clip.onEnd
        clip.onEnd = nil
        local ok, err = pcall(f)
        if not ok then env.info("[CD] onEnd error: " .. tostring(err)) end
    end
end

local function QFire()
    if #CD.queue == 0 then CD.qPlaying = false; return end
    local clip = table.remove(CD.queue, 1)
    if clip.after > 0 and not clip.waited then
        -- honour the pre-gap before showing the clip
        clip.waited = true
        table.insert(CD.queue, 1, clip)
        CD.qPlaying = true
        timer.scheduleFunction(function() QFire() end, nil, timer.getTime() + clip.after)
        return
    end
    if clip.text then Msg(clip.text, clip.dur) end
    local len = Tx(clip.audio)
    if clip.fn then pcall(clip.fn) end
    CD.qPlaying = true
    CD.onAir = clip
    local wait = clip.hold or clip.dur
    if len > 0 then wait = math.max(wait, len + CFG.AUDIO_PAD) end
    -- v1.8.0: onEnd at the end of the audio (or the hold), never before; the next clip starts after it
    local endT = (len > 0) and (len + CFG.AUDIO_PAD) or wait
    if endT < wait then
        timer.scheduleFunction(function() RunEnd(clip) end, nil, timer.getTime() + endT)
    end
    timer.scheduleFunction(function()
        RunEnd(clip)
        if CD.onAir == clip then CD.onAir = nil end
        CD.qPlaying = false; QFire()
    end, nil, timer.getTime() + wait)
end

local function QPlay()
    if not CD.qPlaying and #CD.queue > 0 then QFire() end
end

--- Drop every queued (not yet on air) transmission. v1.8.0: their onEnd still runs (menu gates never stick).
local function QClear()
    local old = CD.queue
    CD.queue = {}
    for _, it in ipairs(old) do RunEnd(it) end
end

--- v1.8.0: drop the queued transmissions of one owner tag (onEnd still runs).
local function QDrop(tag)
    local keep, drop = {}, {}
    for _, it in ipairs(CD.queue) do
        if it.tag == tag then drop[#drop + 1] = it else keep[#keep + 1] = it end
    end
    CD.queue = keep
    for _, it in ipairs(drop) do RunEnd(it) end
    return #drop
end

--- v1.8.0: radio idle (nothing on air, nothing queued)
local function RadioIdle() return not CD.qPlaying and #CD.queue == 0 end
--- v1.8.4: a transmission that is not an automatic pilot acknowledgement is still waiting (not yet on the air)
local function GateWaiting()
    for _, it in ipairs(CD.queue) do if not it.ack then return true end end
    return false
end
CD.gateWaiting = GateWaiting
--- v1.8.4: run f when the item goes on the air, or when it is dropped from the queue (QClear / QDrop run onEnd),
--- whichever comes first, once. A gate opened at the start can never stay closed.
local function AtStart(it, f)
    local done = false
    local g = function() if done then return end done = true; f() end
    it.fn, it.onEnd = g, g
    return it
end

--- Pilot transmission followed by controller reply(ies).
-- @param audio  Optional voice clip id (pilot side, CFG.AUDIO key).
--- Token sequence on channel ch, wrapped in squelch bursts.
local function S(ch, ...)
    local out = { ch = ch, "cv:sq_up" }
    local function add(x)
        if type(x) == "table" then for _, y in ipairs(x) do add(y) end
        elseif x ~= nil then out[#out + 1] = x end
    end
    for _, x in ipairs({ ... }) do add(x) end
    out[#out + 1] = "cv:sq_dn"
    return out
end

local function PD(v) local t = {}; for c in tostring(v):gmatch("%d") do t[#t + 1] = "cv:p_" .. c end; return t end
local function OD(v) local t = {}; for c in tostring(v):gmatch("%d") do t[#t + 1] = "o_" .. c end; return t end

--- Pilot "angels N, state X.Y".
local function PAS(u)
    local i, f = State(u):match("^(%d+)%.(%d)$")
    return { "cv:p_angels", PD(Angels(u)), 0.15, "cv:p_state", PD(i or "0"), "cv:p_point", PD(f or "0") }
end

--- Overlord "bears XXX for YY".
local function OBR(from, to)
    local b = string.format("%03d", math.floor(BrgMag(from, to) + 0.5) % 360)
    return { "o_bears", OD(b), "o_for", OD(math.floor(Dist2D(from, to) + 0.5)) }
end

--- Pilot spelling of an MGRS string: digits, phonetic letters, short pauses.
local function PSpell(str)
    if not str or str == "unknown" then return { "cv:p_unknown" } end
    local t = {}
    for c in str:gmatch(".") do
        if c:match("%d") then t[#t + 1] = "cv:p_" .. c
        elseif c:match("%a") then t[#t + 1] = "cv:p_l_" .. c:lower()
        elseif c == " " then t[#t + 1] = 0.12 end
    end
    return t
end

--- Pilot TOT "1423L" -> "one four two three local".
local function PClock(abs)
    if not abs then return { "cv:p_unknown" } end
    return { PD(Clock(abs):sub(1, 4)), "cv:p_local" }
end

local function Pilot(text, audio)
    -- pilot text stays DUR_PILOT s; the reply may start PILOT_HOLD s after it
    -- (or after the pilot clip ends, whichever is later)
    Q("[" .. CFG.CS .. "] " .. text, CFG.DUR_PILOT, 0, nil, CFG.PILOT_HOLD, audio)
end

--- Automatic pilot acknowledgement of a hand-off, on the controller's frequency.
local function Ack(ch, wilco, btn)
    local prev = CD.queue[#CD.queue]
    if prev then prev.hold = 0.1 end   -- start after the controller's audio, not its subtitle time
    if btn and not wilco then          -- v1.5.3: read the button back
        Q(string.format("[%s] Push button %d, %s.", CFG.CS, btn, CFG.CS),
            CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD, S(ch, "p_push_" .. btn), nil, nil, true)
        return
    end
    Q("[" .. CFG.CS .. "] " .. CFG.CS .. (wilco and ", wilco." or ", switching."),
        CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD, S(ch, wilco and "p_wilco" or "p_switching"), nil, nil, true)
end

-- v1.5.3: "button N (frequency)" for subtitles, "btn N" for F10 / hints
local function Btn(k) return string.format("push button %d (%s)", CFG.BTN[k], CFG.FREQ[k]) end
local function BtnL(k) return string.format("btn %d / %s", CFG.BTN[k], CFG.FREQ[k]) end

-- v1.6.0: shared radio queue for JTAC_Controller (text only for now; audio arg optional)
_G.TRT.CD_AUDIO   = CFG.AUDIO      -- v1.7.5 shared token clips (Field_Arrival "cd:")
_G.TRT.CD_SND_DIR = CFG.SND_DIR
_G.TRT.CD_RADIO = { Q = function(...) return Q(...) end, QPlay = function() return QPlay() end, Msg = Msg,
    len = function(id) return (ClipOf(id)) end,                         -- v1.6.4
    has = function(id) return ClipOf(id) ~= nil end,
    drop = function(tag) return QDrop(tag) end,                         -- v1.8.0
    idle = function() return RadioIdle() end }                          -- v1.8.0

--- Pilot readback after the queued controller transmission (v1.4.5).
local function ReadBack(ch, text, clip)
    local prev = CD.queue[#CD.queue]
    if prev then prev.hold = 0.1 end
    Q("[" .. CFG.CS .. "] " .. text, CFG.DUR_PILOT + 2, 0.8, nil, CFG.PILOT_HOLD, S(ch, clip), nil, nil, true)
end

-- ══════════════════════════════════════════════════════════════
--  AIR PICTURE / THREAT / CAP NET  (v1.5.0)
-- ══════════════════════════════════════════════════════════════
local function IsFighter(u)
    for _, a in ipairs(CFG.FIGHTER_ATTRS) do
        local ok, has = pcall(u.hasAttribute, u, a)
        if ok and has then return true end
    end
    return false
end

--- First active, airborne, alive unit of a group (fighters only if asked) + count.
local function AirLead(g, fightersOnly)
    local lead, n = nil, 0
    for _, u in ipairs(g:getUnits() or {}) do
        if u and u:isExist() and u:isActive() and u:inAir() and u:getLife() > 0
            and (not fightersOnly or IsFighter(u)) then
            n = n + 1; lead = lead or u
        end
    end
    return lead, n
end

--- Airborne RED fighter groups within rangeNM of ref, nearest first: { name, unit, pos, n, d }.
local function Bandits(ref, rangeNM)
    local out = {}
    local ok, groups = pcall(coalition.getGroups, coalition.side.RED, Group.Category.AIRPLANE)
    if not ok or not groups then return out end
    for _, g in ipairs(groups) do
        if g and g:isExist() then
            local lead, n = AirLead(g, true)
            if lead then
                local pos = lead:getPoint()
                local d = Dist2D(ref, pos)
                if d <= rangeNM then
                    out[#out + 1] = { name = g:getName(), unit = lead, pos = pos, n = n, d = d }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

--- Target aspect relative to ref: HOT ≤30°, FLANK ≤70°, BEAM ≤110°, else COLD. nil if slow.
local function Aspect(u, ref)
    local v = u:getVelocity()
    if math.sqrt(v.x * v.x + v.z * v.z) < 30 then return nil end
    local hdg = math.deg(math.atan2(v.z, v.x)) % 360
    local a = math.abs(ADiff(hdg, Bearing(u:getPoint(), ref)))
    if a <= 30 then return "HOT" elseif a <= 70 then return "FLANK" elseif a <= 110 then return "BEAM" end
    return "COLD"
end

local function Bullseye()
    local ok, p = pcall(coalition.getMainRefPoint, coalition.side.BLUE)
    return (ok and p and p.x) and p or nil
end

--- Group description: "bullseye|BRAA BRG/RNG, NN thousand[, aspect], hostile" + tokens.
-- kind = "BULL" (from the bullseye) or "BRAA" (from the reference aircraft).
local function GroupDesc(b, from, kind, aspectRef)
    local brg = string.format("%03d", math.floor(BrgMag(from, b.pos) + 0.5) % 360)
    local rng = math.floor(Dist2D(from, b.pos) + 0.5)
    local alt = math.max(1, Angels(b.unit))
    local asp = aspectRef and Aspect(b.unit, aspectRef)
    local txt = string.format("%s %s/%d, %d thousand%s, hostile", (kind == "BULL") and "bullseye" or "BRAA",
        brg, rng, alt, asp and (", " .. asp:lower()) or "")
    local seq = { (kind == "BULL") and "o_bullseye" or "o_braa", OD(brg), 0.12, OD(rng), 0.12, OD(alt), "o_thousand" }
    if asp then seq[#seq + 1] = "o_" .. asp:lower() end
    seq[#seq + 1] = "o_hostile"
    return txt, seq
end

local COUNT_TXT = { "single group", "two groups", "three groups" }
local COUNT_TOK = { "o_single", "o_two", "o_three" }

--- Picture for the player: text + tokens. "Picture clean." only when no RED fighter is airborne in range.
local function PictureParts(pPos)
    local bs = Bandits(pPos, CFG.PIC_RANGE_NM)
    if #bs == 0 then return "Picture clean.", { "o_pic_clean" } end
    local from, kind = Bullseye(), "BULL"
    if not from then from, kind = pPos, "BRAA" end
    local n = #bs
    local gt, gs = GroupDesc(bs[1], from, kind)
    local txt = "Picture, " .. (COUNT_TXT[n] or "multiple groups")
    local seq = { "o_pic", COUNT_TOK[n] or "o_many" }
    if n > 1 then txt = txt .. ", nearest group"; seq[#seq + 1] = "o_nearest" end
    return txt .. ", " .. gt .. ".", { seq, gs }
end

--- Unsolicited traffic on the OVERLORD net. Captioned only while the player works OVERLORD;
-- otherwise the transmission still goes out on the OVERLORD frequency, without subtitle.
local function QNet(text, audio, after)
    local captioned = OVL_PHASES[CD.phase] or CD.phase == "OVL_OUT"
    if captioned and text then text = "(CAP net) " .. text end   -- v1.5.2
    Q(captioned and text or nil, CFG.DUR_SHORT, after or 0, nil, 0.1, audio)
end

--- Deferred call: fn builds the exchange when the queue is idle (positions taken then).
local function Chat(fn, prio)
    local it = { t0 = timer.getTime(), fn = fn }
    if prio then table.insert(CD.chat, 1, it) else CD.chat[#CD.chat + 1] = it end
end

local function ThreatCall(name, close)
    Chat(function()
        local p = Player(); if not p then return end
        local g = Group.getByName(name); if not g then return end
        local lead = AirLead(g, true); if not lead then return end
        local pPos = p:getPoint()
        local gt, gs = GroupDesc({ unit = lead, pos = lead:getPoint() }, pPos, "BRAA", pPos)
        Q(string.format("[OVERLORD] %s, Overlord, threat, %s.", CFG.CS, gt), CFG.DUR_URGENT, 0, nil, nil,
            S("OVERLORD", "ovl_threat_head", gs))
        ReadBack("OVERLORD", CFG.CS .. ", copy.", "p_ovl_copy")
        env.info(string.format("[CD] threat call %s (%s): %s", name, close and "close" or "first", gt))
    end, true)
end

local function CapCommit(c)
    Chat(function()
        local g = Group.getByName(c.group); if not g then return end
        local lead = AirLead(g, false); if not lead then return end
        local lp = lead:getPoint()
        local bs = Bandits(lp, CFG.CAP_COMMIT_NM)
        if #bs == 0 then return end
        local gt, gs = GroupDesc(bs[1], lp, "BRAA", lp)
        QNet(string.format("[OVERLORD] %s, Overlord, commit, group %s.", c.cs, gt),
            S("OVERLORD", "ovl_" .. c.key .. "_commit", gs))
        QNet(string.format("[%s] %s, committing.", c.cs:upper(), c.cs),
            S("OVERLORD", "cap_" .. c.key .. "_commit"), 0.8)
        env.info(string.format("[CD] %s committed on %s: %s", c.group, bs[1].name, gt))
    end)
end

local function CapSplash(c)
    if OVL_PHASES[CD.phase] or CD.phase == "OVL_OUT" then CD.splashes = (CD.splashes or 0) + 1 end  -- v1.5.3
    Chat(function()
        QNet(string.format("[%s] Overlord, %s, splash one.", c.cs:upper(), c.cs),
            S("OVERLORD", "cap_" .. c.key .. "_splash"))
        QNet(string.format("[OVERLORD] %s, Overlord, copy splash.", c.cs),
            S("OVERLORD", "ovl_" .. c.key .. "_copy"), 0.8)
    end)
end

local function CapStation(c)
    Chat(function()
        QNet(string.format("[%s] Overlord, %s, picture clean, back to station.", c.cs:upper(), c.cs),
            S("OVERLORD", "cap_" .. c.key .. "_station"))
    end)
end

-- forward declarations
local SetPhase, MenuRebuild, Remind
local TicPick, TicHandoff   -- v1.5.4 (TROOPS IN CONTACT section)
local ScenPick, C_OvlContact, A_Inflrep, NextKey, C_NoShow   -- v1.8.0 (TASKING section)

-- ══════════════════════════════════════════════════════════════
--  RADIO CALLS — controller-initiated (hand-offs / threats)
-- ══════════════════════════════════════════════════════════════
local function C_DepSwitchStrike()
    Q(string.format("[DEPARTURE] %s, Departure. Strike, %s.", CFG.CS, Btn("STRIKE")),
        CFG.DUR_HANDOFF, 0, nil, nil, "dep_switch_strike")
    Ack("DEPARTURE", false, CFG.BTN.STRIKE)
end

-- v1.8.0: C_OvlContactPointer -> C_OvlContact(key, ...) in the TASKING section

local function C_OvlSwitchStrike(p)
    local c = Carrier()
    local mother = c and (", Mother " .. BrgRng(p:getPoint(), c:getPoint())) or ""
    Q(string.format("[OVERLORD] %s, Overlord%s. Strike, %s.",
        CFG.CS, mother, Btn("STRIKE")), CFG.DUR_HANDOFF, 0, nil, nil,
        S("OVERLORD", "ovl_switch_strike_a", c and { "o_mother", OBR(p:getPoint(), c:getPoint()) }, 0.1,
          "ovl_switch_strike_b"))
    Ack("OVERLORD", false, CFG.BTN.STRIKE)
end

local function C_StrikeSwitchMarshal()
    Q(string.format("[STRIKE] %s, Strike. Marshal, %s.", CFG.CS, Btn("MARSHAL")),
        CFG.DUR_SHORT + 2, 0, nil, nil, "str_switch_marshal")
    Ack("STRIKE", false, CFG.BTN.MARSHAL)
end

-- Urgent calls bypass the queue: shown immediately, queued routine traffic is dropped.
local function C_Abort()
    QClear()
    local J = P.jtacs[RS.injKey]   -- v1.10.0
    Msg(string.format("[" .. J.cs .. "] %s, abort, abort, abort. Civilian vehicle in target area.", CFG.CS),
        CFG.DUR_URGENT + 2)
    Tx(J.ck .. "_abort", true)
    SetFlag(201, 1)
end

local function C_Rearm()
    local J = P.jtacs[RS.injKey]   -- v1.10.0
    Q(string.format("[" .. J.cs .. "] %s, target area clear. Continue as briefed.", CFG.CS), 10, 6, nil, nil, J.ck .. "_area_clear")
    SetFlag(201, 2)
end

local function C_Manpads()
    local J = P.jtacs[RS.injKey]   -- v1.10.0
    Msg(string.format("[" .. J.cs .. "] %s, MANPADS launch observed one klick east of the target. "
        .. "Remain at or above hard deck, two-zero thousand MSL.", CFG.CS), CFG.DUR_URGENT + 1)
    Tx(J.ck .. "_manpads", true)
    SetFlag(203, 1)
end

local function C_CorridorDev()
    Msg(string.format("[STRIKE] %s, Strike. You are off the inbound corridor. Intercept the zero five zero radial inbound.",
        CFG.CS), CFG.DUR_URGENT + 1)
    Tx("str_corridor", true)
    SetFlag(204, 1)
end

--- v1.7.11: still outside the corridor at the Marshal hand-off (queued before "Marshal, push button 16")
local function C_CorridorMz(radial)
    CD.corridorMz = true   -- v1.7.12
    env.info(string.format("[CD] corridor: Marshal hand-off on R-%03d (corridor R-%03d +/-%d)", radial,
        (CFG.CORRIDOR_TRUE - CFG.MAGVAR) % 360, CFG.CORRIDOR_HALF))
    Q(string.format("[STRIKE] %s, Strike. You are inside fifty miles and still off the corridor. "
        .. "Intercept the zero five zero radial now.", CFG.CS), CFG.DUR_URGENT + 1, 0, nil, nil, "str_corridor_mz")
end

--- v1.7.11: Marshal Zone speed call while the hero is still on Strike (Overspeed_Penalty >= v7.5.0).
--- Returns true when Strike made the call; Marshal / Approach phases belong to CV_Comms.
function CD.speedCall(kind)
    if CD.phase ~= "STRIKE_IN" and CD.phase ~= "INBOUND" then return false end
    if kind == "warn" then
        Q(string.format("[STRIKE] %s, Strike. Check speed. Three fifty knots maximum inside fifty miles.", CFG.CS),
            CFG.DUR_URGENT, 0, nil, nil, "str_speed")
    elseif kind == "brass" then
        Q(string.format("[STRIKE] %s, Strike. You are still fast. Slow to three fifty knots now. That goes in the debrief.",
            CFG.CS), CFG.DUR_URGENT, 0, nil, nil, "str_speed_brass")
    else
        return false
    end
    ReadBack("STRIKE", CFG.CS .. ", wilco.", "p_wilco")   -- v1.7.13
    env.info("[CD] speed call (Strike): " .. kind)
    QPlay()
    return true
end

-- ══════════════════════════════════════════════════════════════
--  F10 ACTIONS — pilot-initiated
-- ══════════════════════════════════════════════════════════════
local function A_StrikeCheckInOut()
    local p = Player(); if not p then return end
    SetPhase("STRIKE_CHK")
    Pilot(string.format("Strike, %s, checking in outbound, passing angels %d, Kilo.", CFG.CS, Angels(p)),
        S("STRIKE", "p_str_out_a", PD(Angels(p)), 0.12, "cv:p_kilo"))
    Q(string.format("[STRIKE] %s, Strike, radar contact. Check Mode 4.", CFG.CS), CFG.DUR_SHORT, CFG.REPLY_GAP, nil, nil, "str_radar_contact")
    Ack("STRIKE", true)
    local sweetToOvl = function()
        Q(string.format("[STRIKE] %s, Mode 4 sweet. Kilo copied. Overlord, %s.",
            CFG.CS, Btn("OVL")), CFG.DUR_SHORT + 2, 3, function() SetPhase("OVL_OUT") end, nil, "str_m4_sweet_ovl")
        Ack("STRIKE", false, CFG.BTN.OVL)
    end
    if not CD.inj.i2 and Roll(CFG.PROB_INJ2) then
        CD.inj.i2 = true
        SetFlag(202, 1)
        Q(string.format("[STRIKE] %s, Mode 4 sour. Recycle.", CFG.CS), CFG.DUR_URGENT, 4, nil, nil, "str_m4_sour")
        Ack("STRIKE", true)
        Q(string.format("[STRIKE] %s, Strike. Mode 4 sweet now.", CFG.CS), CFG.DUR_SHORT, 16, nil, nil, "str_m4_sweet_now")
        Q(string.format("[STRIKE] %s, Kilo copied. Overlord, %s.", CFG.CS, Btn("OVL")),
            CFG.DUR_SHORT + 2, 2, function() SetPhase("OVL_OUT") end, nil, "str_kilo_ovl")
        Ack("STRIKE", false, CFG.BTN.OVL)
    else
        sweetToOvl()
    end
    QPlay()
end

local function A_OvlCheckIn()
    local p = Player(); if not p then return end
    TicPick()   -- v1.5.4: press time = entropy (math.randomseed is not in the sandbox)
    CD.awaiting = true; MenuRebuild()
    local T = CD.tasked   -- v1.10.0
    local std = (T[1] == "J1" and T[2] == "J2")   -- v1.10.1: the check-in clips name Pointer / Eyeball and 4101 / 4102
    local picTxt, picSeq = PictureParts(p:getPoint())
    if P.xcas then   -- v1.11.0 XCAS: no JTACs, no mission numbers at check-in
        Pilot(string.format("Overlord, %s, checking in as fragged, XCAS, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
            S("OVERLORD", "p_ovl_checkin_x", PAS(p)))
    else
        Pilot(string.format("Overlord, %s, checking in as fragged, mission %s and %s, angels %d, state %s.",
            CFG.CS, RS.MSN[T[1]], RS.MSN[T[2]], Angels(p), State(p)), std and S("OVERLORD", "p_ovl_checkin_a", PAS(p)) or nil)
    end
    Q(string.format("[OVERLORD] %s, Overlord, radar contact. %s "
        .. (P.xcas and "Mission as fragged, close air support on call."
            or ("Mission as fragged, " .. P.jtacs[T[1]].disp .. " and " .. P.jtacs[T[2]].disp .. " on station."))
        .. " Proceed %s, %s. SAM activity reported in both target areas, %s. Report feet dry.",
        CFG.CS, picTxt, CFG.CP_NAME, BrgRng(p:getPoint(), CFG.CP_POS), HD_TEXT),
        CFG.DUR_LONG + 4, CFG.REPLY_GAP, function() SetPhase("ENROUTE") end, nil,
        (P.xcas or std) and S("OVERLORD", "ovl_ci_rc", picSeq, 0.1, P.xcas and "ovl_ci_xcas" or "ovl_ci_frag",
            OBR(p:getPoint(), CFG.CP_POS), 0.15, "ovl_checkin_b")
        or nil)   -- v1.10.1: another pair without XCAS -> text only
    ReadBack("OVERLORD", string.format("%s, proceeding %s, hard deck two-zero thousand, wilco.", CFG.CS, CFG.CP_NAME),
        "p_ovl_checkin_rb")
    if CD.scen and CD.scen.noShow then C_NoShow() end   -- v1.8.0
    QPlay()
end

-- v1.8.0: A_OvlOffPointer -> A_OvlOffJtac(key) in the TASKING section

-- ══════════════════════════════════════════════════════════════
--  v1.7.0 TANKER RV, EMCON 2 (AR1 before the VUL, AR2 after INFLTREP)
-- ══════════════════════════════════════════════════════════════
--- seq if every clip in it exists, else nil (text only, never a half-voiced call).
local function Voiced(seq)
    if type(seq) ~= "table" then return seq end
    for _, id in ipairs(seq) do
        if type(id) == "string" and not ClipOf(id) then
            env.info("[CD] text only, missing clip " .. id)
            return nil
        end
    end
    return seq
end

local function FuelLb(u) return (u:getFuel() or 0) * CFG.INTERNAL_FUEL_LB end
local function Klb(lb) return string.format("%.1f", math.floor(math.max(0, lb) / 100 + 0.5) / 10) end
local function TD(v) local t = {}; for c in tostring(v):gmatch("%d") do t[#t + 1] = "t_" .. c end; return t end
--- "6.8" -> digit tokens with "point" (pilot cv:p_*, Texaco t_*).
local function PNum(s) local i, f = s:match("^(%d+)%.(%d)$"); return { PD(i or "0"), "cv:p_point", PD(f or "0") } end
local function TNum(s) local i, f = s:match("^(%d+)%.(%d)$"); return { TD(i or "0"), "t_point", TD(f or "0") } end

--- v1.7.6: tanker unit exists and is not dead.
local function TkAlive()
    if CD.scen and CD.scen.noShow then return false end   -- v1.8.0 tanker no-show
    local t = Tanker()
    if not t then return false end
    local okE, ex = pcall(t.isExist, t)
    if not (okE and ex) then return false end
    local okL, l = pcall(t.getLife, t)
    return not (okL and type(l) == "number" and l < 1)
end

--- v1.7.6: hero position along the tanker's velocity (NM, + ahead, - behind) and 2-D distance (NM).
local function TkAlong(p, t)
    local P, T = p:getPoint(), t:getPoint()
    local v = t:getVelocity() or { x = 0, z = 0 }
    local vs = math.sqrt(v.x * v.x + v.z * v.z)
    local d = Dist2D(P, T)
    if vs < 1 then return 0, d end
    return ((P.x - T.x) * v.x + (P.z - T.z) * v.z) / vs / 1852, d
end

--- v1.7.4: flight level of a unit (true altitude rounded to 1,000 ft), e.g. 150.
local function FL(u) return math.floor(u:getPoint().y * 3.28084 / 1000 + 0.5) * 10 end

--- v1.7.4 RV Alpha vector: magnetic heading (5 deg steps, 360 for north) to intercept the point 1 NM behind
-- the tanker, leading the tanker's current velocity; pure pursuit of that point when no intercept exists
-- within CFG.TKR.VEC_MAX_S (receiver not faster than the tanker).
local function TkrVecHdg(p, t)
    local P, T = p:getPoint(), t:getPoint()
    local tv = t:getVelocity() or { x = 0, z = 0 }
    local ts = math.sqrt(tv.x * tv.x + tv.z * tv.z)
    local ax, az = T.x, T.z
    if ts > 1 then ax, az = T.x - tv.x / ts * 1852, T.z - tv.z / ts * 1852 end
    local pv = p:getVelocity() or { x = 0, z = 0 }
    local sp = math.max(math.sqrt(pv.x * pv.x + pv.z * pv.z), CFG.TKR.VEC_MIN_MS)
    local dx, dz = ax - P.x, az - P.z
    local qa = tv.x * tv.x + tv.z * tv.z - sp * sp
    local qb = 2 * (dx * tv.x + dz * tv.z)
    local qc = dx * dx + dz * dz
    local tt
    if math.abs(qa) < 1e-6 then
        if qb < 0 then tt = -qc / qb end
    else
        local disc = qb * qb - 4 * qa * qc
        if disc >= 0 then
            local r = math.sqrt(disc)
            for _, x in ipairs({ (-qb - r) / (2 * qa), (-qb + r) / (2 * qa) }) do
                if x > 0 and (not tt or x < tt) then tt = x end
            end
        end
    end
    local gx, gz = ax, az
    if tt and tt <= CFG.TKR.VEC_MAX_S then gx, gz = ax + tv.x * tt, az + tv.z * tt end   -- else pure pursuit
    local h = (Bearing(P, { x = gx, z = gz }) - CFG.MAGVAR) % 360
    h = (math.floor(h / 5 + 0.5) * 5) % 360
    return (h == 0) and 360 or h
end

local function TkOpen(ar)
    local A = _G.TRT and _G.TRT.AAR
    CD.tk = { ar = ar, t0 = timer.getTime(), bra = {},
              aarN0 = A and ((A.nSession or 0) - (A.session and 1 or 0)) or nil,
              last0 = A and A.last or nil }   -- AAR.last before this RV (an abandoned session leaves it unchanged)
    CD.refuelDone = false
end

--- OVERLORD vector to the tanker (AR1 head or AR2 INFLTREP head) + pilot readback.
-- @return true if a tanker exists (vector given)
local function TkrVector(p, ar)
    local t = Tanker()
    if not t then return false end
    local ta = FL(t)
    local rv = ta - CFG.TKR.RV_BELOW_ANGELS * 10
    local hd = string.format("%03d", TkrVecHdg(p, t))
    local head = (ar == 2) and "copy INFLTREP. " or ""
    Q(string.format("[OVERLORD] %s, Overlord, %sTexaco 11 %s, flight level %d. Vector %s, maintain flight level %d. TACAN 21 Yankee. Texaco, %s.",
        CFG.CS, head, BrgRng(p:getPoint(), t:getPoint()), ta, hd, rv, Btn("TKR")),
        CFG.DUR_LONG, CFG.REPLY_GAP, function()
            if ar == 2 then SetPhase("REFUEL") else CD.awaiting = false end
            if CD.tk then CD.tk.vec = true end
            local u, k = Player(), Tanker()
            if CD.tk and u and k then      -- calls only below the current range
                local d = Dist2D(u:getPoint(), k:getPoint())
                for _, th in ipairs(CFG.TKR.BRA_NM) do if d <= th + 1 then CD.tk.bra[th] = true end end
            end
            MenuRebuild()
        end, nil,
        Voiced(S("OVERLORD", (ar == 2) and "ovl_inflrep_a" or "ovl_ar1_a", OBR(p:getPoint(), t:getPoint()), 0.08,
          "o_fl", OD(ta), 0.15, "o_vector", OD(hd), 0.1, "o_maintain", "o_fl", OD(rv), 0.15, "ovl_inflrep_b")))
    local prev = CD.queue[#CD.queue]
    if prev then prev.hold = 0.1 end
    Q(string.format("[%s] %s, vector %s, flight level %d, push button %d.", CFG.CS, CFG.CS, hd, rv, CFG.BTN.TKR),
        CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD,
        Voiced(S("OVERLORD", "p_tkr_rb_a", "p_vector", PD(hd), 0.1, "p_fl", PD(rv), "p_tkr_rb_b")))
    return true
end

local function A_TkrRequest()
    local p = Player(); if not p then return end
    if not TkAlive() then Msg("[CAS-1] Texaco 11 not available.", CFG.DUR_SHORT); return end   -- v1.8.0
    CD.awaiting = true
    TkOpen(1)
    MenuRebuild()
    Pilot(string.format("Overlord, %s, request Texaco, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
        Voiced(S("OVERLORD", "p_ovl_req_tkr_a", PAS(p))))
    TkrVector(p, 1)
    QPlay()
end

local function A_TkrInit()
    local p, t = Player(), Tanker(); if not (p and t and CD.tk) then return end
    CD.tk.init = true
    CD.awaiting = true; MenuRebuild()
    local ta = FL(t)
    local rv = ta - CFG.TKR.RV_BELOW_ANGELS * 10
    local st, rq = State(p), Klb(CFG.TKR.FULL_LB - FuelLb(p))
    local m3 = CFG.TKR.MODE3
    Pilot(string.format("Texaco 11, %s, flight level %d, TACAN 21 Yankee, Mode 3 %s, nose cold, switches safe, state %s, request %s.",
        CFG.CS, rv, m3, st, rq),
        Voiced(S("TEXACO", "p_tkr_init_a", PD(rv), 0.1, "p_tkr_init_b", PD(m3), 0.1, "p_nose_cold",
          "cv:p_state", PNum(st), 0.1, "p_request", PNum(rq))))
    local trf = _G.TRT and _G.TRT.Traffic                          -- v1.7.10 AI receivers queued
    local okR, rmk = pcall(function() return trf and trf.TkrRemark and trf.TkrRemark() end)
    if not okR or type(rmk) ~= "table" then rmk = nil end
    Q(string.format("[TEXACO] %s, Texaco 11, RV Alpha, flight level %d, %s available.%s", CFG.CS, ta, rq,
        rmk and (" " .. rmk.text) or ""),
        CFG.DUR_SHORT, CFG.REPLY_GAP, function() CD.awaiting = false; MenuRebuild() end, nil,
        Voiced(S("TEXACO", "tkr_init_a", TD(ta), 0.1, TNum(rq), "t_available", rmk and 0.15 or nil, rmk and rmk.clip or nil)))
    QPlay()
end

local function A_Judy()
    if not CD.tk then return end
    CD.tk.judy = true
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("%s, Judy.", CFG.CS), Voiced(S("OVERLORD", "p_judy")))
    Q(string.format("[OVERLORD] %s, Overlord, copy.", CFG.CS),
        CFG.DUR_SHORT, CFG.REPLY_GAP, function() CD.awaiting = false; MenuRebuild() end, nil,
        Voiced(S("OVERLORD", "ovl_copy_51")))
    QPlay()
end

local function A_TkrState()
    local p = Player(); if not (p and CD.tk) then return end
    CD.tk.state = true
    CD.awaiting = true; MenuRebuild()
    local st = State(p)
    Pilot(string.format("%s, state %s.", CFG.CS, st), Voiced(S("TEXACO", "p_tkr_rb_a", "cv:p_state", PNum(st))))
    Q(string.format("[TEXACO] %s, Texaco 11, clear to leave.", CFG.CS),
        CFG.DUR_SHORT, CFG.REPLY_GAP, function()
            if CD.tk then CD.tk.clear = true end
            CD.awaiting = false
            if CD.phase == "REFUEL" then SetPhase("TKR_DONE") end
            MenuRebuild()
        end, nil, Voiced(S("TEXACO", "tkr_clear")))
    local prev = CD.queue[#CD.queue]
    if prev then prev.hold = 0.1 end
    Q(string.format("[%s] %s.", CFG.CS, CFG.CS), CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD,
        Voiced(S("TEXACO", "p_51")))   -- v1.7.4 acknowledge "clear to leave" [A 2P serial 19]
    QPlay()
end

--- v1.7.1: AR1 still open (not flown, not skipped) while a tanker exists -> POINTER hand-off waits.
local function Ar1Pending()
    return CFG.TKR.AR1_HOLD and not CD.ar1Done and Tanker() ~= nil and not CD.tkrLost
end

--- v1.7.1: no AR1 top-off wanted.
local function A_SkipAR1()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, negative Texaco, state %s, proceeding %s.", CFG.CS, State(p), CFG.CP_NAME),
        Voiced(S("OVERLORD", "p_ovl_neg_tkr_a", "cv:p_state", PD((State(p):match("^(%d+)%.") or "0")), "cv:p_point",
            PD((State(p):match("%.(%d)$") or "0")), 0.15, "p_ovl_off_tkr_b")))   -- v1.8.3
    Q(string.format("[OVERLORD] %s, Overlord, copy.", CFG.CS), CFG.DUR_SHORT, CFG.REPLY_GAP,
        function() CD.tk = nil; CD.ar1Done = true; CD.awaiting = false; MenuRebuild() end, nil,
        Voiced(S("OVERLORD", "ovl_copy_51")))
    QPlay()
end

--- AR1 closed: off Texaco (or cancelled), back to CP TIGER; the JTAC-1 hand-off follows if inside 20 NM.
local function A_OffTkrAR1()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, off Texaco, angels %d, state %s, proceeding %s.",
        CFG.CS, Angels(p), State(p), CFG.CP_NAME),
        Voiced(S("OVERLORD", "p_ovl_off_tkr_a", PAS(p), 0.15, "p_ovl_off_tkr_b")))
    local far = Dist2D(p:getPoint(), CFG.CP_POS) > CFG.JTAC_HANDOFF_NM
    local done = function() CD.tk = nil; CD.ar1Done = true; CD.awaiting = false; MenuRebuild() end
    if far then
        Q(string.format("[OVERLORD] %s, Overlord, copy. Proceed %s, %s.", CFG.CS, CFG.CP_NAME,
            BrgRng(p:getPoint(), CFG.CP_POS)), CFG.DUR_SHORT, CFG.REPLY_GAP, done, nil,
            Voiced(S("OVERLORD", "ovl_off_tkr", OBR(p:getPoint(), CFG.CP_POS))))
    else
        Q(string.format("[OVERLORD] %s, Overlord, copy.", CFG.CS), CFG.DUR_SHORT, CFG.REPLY_GAP, done, nil,
            Voiced(S("OVERLORD", "ovl_copy_51")))
    end
    QPlay()
end

--- Tick: OVERLORD tanker BRA calls until Judy; TEXACO "you received" after the last disconnect.
-- v1.7.6 AAR branch calls ------------------------------------------------------------------------
local function AarS() local A = _G.TRT and _G.TRT.AAR; return A and A.session or nil end

local function A_Overrun()
    local tk = CD.tk; if not tk then return end
    tk.ovr, tk.ovrCalled = true, true
    env.info("[CD] AAR: execute overrun called")
    Pilot(string.format("Texaco 11, execute overrun."), Voiced(S("TEXACO", "p_tkr_overrun")))
    table.insert(CD.queue, 1, table.remove(CD.queue))   -- urgent: ahead of queued calls (callbacks kept)
    MenuRebuild(); QPlay()
end

local function A_Breakaway()
    local tk = CD.tk; if not tk then return end
    tk.bkw, tk.bkwT = true, timer.getTime()
    env.info("[CD] AAR: breakaway called by the receiver")
    Pilot(string.format("Texaco 11, breakaway, breakaway, breakaway."), Voiced(S("TEXACO", "p_tkr_breakaway")))
    table.insert(CD.queue, 1, table.remove(CD.queue))   -- urgent: ahead of queued calls (callbacks kept)
    MenuRebuild(); QPlay()
end

local function A_Spokes()
    local tk = CD.tk; if not tk then return end
    tk.spokes = true
    env.info("[CD] AAR: spokes called")
    Pilot(string.format("%s, spokes.", CFG.CS), Voiced(S("TEXACO", "p_spokes")))
    Q(string.format("[TEXACO] %s, Texaco 11, copy spokes. Disconnect, check engine instruments.", CFG.CS),
        CFG.DUR_SHORT, CFG.REPLY_GAP, function()
            Msg("[CAS-1] Spokes: check engine instruments. Damage or doubt: F10 OVERLORD: bingo / divert.", CFG.DUR_HANDOFF)
        end, nil, Voiced(S("TEXACO", "tkr_spokes")))
    MenuRebuild(); QPlay()
end

--- Which branch items are available now (also the menu-rebuild signature).
local function TkBranch()
    local tk = CD.tk
    if not (tk and tk.vec and not tk.rcvd) then return {} end
    local Sn, b = AarS(), {}
    local contacts = Sn and #Sn.contacts or 0
    if contacts == 0 and not tk.ovr then b.ovr = true end
    if Sn and Sn.join and not tk.bkw then b.bkw = true end
    if contacts > 0 and not tk.spokes then b.spk = true end
    return b
end

local function TkBranchSig()
    local b = TkBranch()
    return (b.ovr and "o" or "") .. (b.bkw and "b" or "") .. (b.spk and "s" or "")
end

--- Overrun hint / terminate, breakaway terminate, menu refresh.
local function TkBranchTick(p)
    local tk, t = CD.tk, Tanker()
    if not (tk and t) then return end
    local Sn = AarS()
    if Sn and (Sn.overruns or 0) > (tk.ovrSeen or 0) then
        tk.ovrSeen = Sn.overruns
        if not tk.ovr then
            Msg("[CAS-1] Overrun: pass at least 1,000 ft below the tanker, slow down. F10 TEXACO: execute overrun.", CFG.DUR_SHORT)
        end
    end
    local along, d = TkAlong(p, t)
    if tk.ovr and along <= -CFG.TKR.OVR_BEHIND_NM then
        tk.ovr = false
        Q(string.format("[TEXACO] %s, terminate overrun.", CFG.CS), CFG.DUR_SHORT, 0, nil, nil,
            Voiced(S("TEXACO", "tkr_term_overrun")))
        QPlay()
    end
    if tk.bkw and not tk.bkwDone then
        local inContact = Sn and Sn.openStart ~= nil
        if (not inContact and d >= CFG.TKR.BKW_CLEAR_NM) or timer.getTime() - (tk.bkwT or 0) >= CFG.TKR.BKW_MAX_S then
            tk.bkwDone = true
            Q(string.format("[TEXACO] %s, terminate emergency separation.", CFG.CS), CFG.DUR_SHORT, 0, nil, nil,
                Voiced(S("TEXACO", "tkr_term_bkw")))
            local prev = CD.queue[#CD.queue]
            if prev then prev.hold = 0.1 end
            Q(string.format("[%s] %s.", CFG.CS, CFG.CS), CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD,
                Voiced(S("TEXACO", "p_51")))
            QPlay()
        end
    end
    local sig = TkBranchSig()
    if sig ~= (tk.brSig or "") then tk.brSig = sig; MenuRebuild() end
end

--- v1.7.6: tanker lost after it existed -> OVERLORD call (once).
local function TkrLostTick()
    if CD.tkrLost then return end
    if TkAlive() then CD.tkrSeen = true; return end
    if not CD.tkrSeen then return end
    CD.tkrLost = true
    local ph, wasOpen = CD.phase, CD.tk ~= nil
    env.info(string.format("[CD] tanker lost (%s) in phase %s%s", CFG.TANKER_UNIT, ph, wasOpen and ", RV open" or ""))
    CD.tk = nil
    local ar1 = (ph == "ENROUTE") and not CD.ar1Done
    if ar1 then CD.ar1Done = true end
    local lastOff = RS.isOff(ph) and not NextKey()   -- v1.8.0 (v1.10.0 roster)
    if not OVL_PHASES[ph] or not (ar1 or wasOpen or ph == "REFUEL" or lastOff) then MenuRebuild(); return end
    CD.awaiting = false
    if ar1 then   -- v1.8.0 (Onur): say intentions, the pilot decides (continue / RTB / divert)
        CD.ar1Int = true
        Q(string.format("[OVERLORD] %s, Overlord, Texaco 11 is off station, no tanker available. Say intentions.",
            CFG.CS), CFG.DUR_LONG, 0, nil, nil, Voiced(S("OVERLORD", "ovl_tkr_lost_si")))
    else
        Q(string.format("[OVERLORD] %s, Overlord, Texaco 11 is off station, no tanker available. Say intentions.",
            CFG.CS), CFG.DUR_LONG, 0, nil, nil, Voiced(S("OVERLORD", "ovl_tkr_lost_si")))
    end
    MenuRebuild(); QPlay()
end

local function TkrTick(p)
    local tk = CD.tk
    if not tk or not (CD.phase == "ENROUTE" or CD.phase == "REFUEL" or CD.phase == "TKR_DONE") then return end
    local t = Tanker()
    if tk.vec and not tk.judy and t and not CD.awaiting then
        local d = Dist2D(p:getPoint(), t:getPoint())
        for _, th in ipairs(CFG.TKR.BRA_NM) do
            if d <= th and not tk.bra[th] then
                for _, th2 in ipairs(CFG.TKR.BRA_NM) do if d <= th2 then tk.bra[th2] = true end end
                local hd = string.format("%03d", TkrVecHdg(p, t))   -- v1.7.4
                Q(string.format("[OVERLORD] %s, vector %s, Texaco %s.", CFG.CS, hd, BrgRng(p:getPoint(), t:getPoint())),
                    CFG.DUR_SHORT, 0, nil, nil,
                    Voiced(S("OVERLORD", "ovl_vec_a", OD(hd), 0.1, "o_texaco", OBR(p:getPoint(), t:getPoint()))))
                QPlay()
                break
            end
        end
    end
    if tk.rcvd and not tk.state and tk.rcvdN then          -- v1.7.7 reconnect after "you received"
        local A0 = _G.TRT and _G.TRT.AAR
        local S0 = A0 and A0.session
        if S0 and S0.openStart and #S0.contacts > tk.rcvdN then
            tk.rcvd, tk.rcvdN = nil, nil
            env.info("[CD] reconnect after 'you received': report withdrawn, repeated after the last disconnect")
            MenuRebuild()
        end
    end
    if tk.rcvd then return end
    local A = _G.TRT and _G.TRT.AAR
    if not (A and tk.aarN0) then return end
    local onload, nC
    local Sn = A.session
    if Sn and Sn.n > tk.aarN0 and Sn.lastStop and not Sn.openStart and #Sn.contacts > 0
        and (Sn.dep.side or timer.getTime() - Sn.lastStop >= CFG.TKR.RCVD_WAIT
             or (timer.getTime() - Sn.lastStop >= CFG.TKR.RCVD_FULL_S and Player()
                 and FuelLb(Player()) >= CFG.TKR.RCVD_FULL_LB)) then   -- v1.7.9: full -> 5 s
        onload, nC = 0, #Sn.contacts
        for _, c in ipairs(Sn.contacts) do
            if c.fuelStart and c.fuelStop then onload = onload + math.max(0, c.fuelStop - c.fuelStart) end
        end
    elseif not Sn and A.last and A.last ~= tk.last0 and (A.nSession or 0) > tk.aarN0 and (A.last.contacts or 0) > 0 then
        onload = A.last.onload
    end
    if not onload then return end
    tk.rcvd, tk.rcvdN = true, nC   -- nC nil when the session already ended (no withdrawal then)
    local x = Klb(onload)
    Q(string.format("[TEXACO] %s, Texaco 11, you received %s.", CFG.CS, x), CFG.DUR_SHORT, 0,
        function() MenuRebuild() end, nil, Voiced(S("TEXACO", "tkr_rcvd", TNum(x))))
    QPlay()
end

local function TkrNext()
    local tk = CD.tk
    if not tk and CD.phase == "ENROUTE" and Ar1Pending() and not CD.awaiting then   -- v1.7.1
        return "AR1 top-off: OVERLORD, request Texaco (F10), or skip AR1 (F10). The hand-off to " .. P.jtacs[CD.tasked[1]].disp .. " waits for AR1."
    end
    if not tk or not (CD.phase == "ENROUTE" or CD.phase == "REFUEL" or CD.phase == "TKR_DONE") then return nil end
    local btn = BtnL("TKR")
    if tk.clear then
        return (tk.ar == 1) and ("Report off Texaco to OVERLORD (F10), then " .. CFG.CP_NAME .. ".")
            or "Report RTB to OVERLORD (F10)."
    end
    if tk.rcvd then return "Report state to TEXACO 11 (F10), wait for clear to leave." end
    if not tk.vec then return "Stand by, OVERLORD." end
    local s = {}
    if not tk.init then s[#s + 1] = "RV initial to TEXACO 11 " .. btn .. " (F10)" end
    if not tk.judy then s[#s + 1] = "Judy to OVERLORD when visual (F10)" end
    s[#s + 1] = "join left, 1,000 ft below, DCS radio menu: intent to refuel (TACAN 21Y). No radio calls on the join (EMCON 2)."
    return table.concat(s, "; ")
end

-- v1.8.0: A_Inflrep -> TASKING section (per-tasking results)

-- v1.6.5: A_TexacoCheckIn removed (refuelling uses the native DCS tanker comms)

local function A_OvlRTB()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    local c = Carrier()
    local from = (CD.phase == "TKR_DONE") and "off Texaco" or "no tanker required"
    Pilot(string.format("Overlord, %s, %s, RTB, angels %d, state %s.", CFG.CS, from, Angels(p), State(p)),
        S("OVERLORD", (CD.phase == "TKR_DONE") and "p_ovl_rtb_tkr_a" or "p_ovl_rtb_notkr_a", PAS(p)))
    local mother = c and (" Mother " .. BrgRng(p:getPoint(), c:getPoint()) .. ".") or ""
    Q(string.format("[OVERLORD] %s, Overlord, RTB approved.%s Proceed outbound zero five zero. Report feet wet.", CFG.CS, mother), CFG.DUR_LONG, CFG.REPLY_GAP,
        function() SetPhase("RTB") end, nil,
        S("OVERLORD", "ovl_rtb_a", c and { "o_mother", OBR(p:getPoint(), c:getPoint()) }, 0.15, "ovl_rtb_b"))
    ReadBack("OVERLORD", CFG.CS .. ", zero five zero, wilco.", "p_ovl_rtb_rb")
    QPlay()
end

local function A_OvlAbort()
    local p = Player(); if not p then return end
    CD.aborted = true   -- v1.5.1
    CD.awaiting = true; MenuRebuild()
    local c = Carrier()
    Pilot(string.format("Overlord, %s, mission abort, RTB, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
        S("OVERLORD", "p_ovl_abort_a", PAS(p)))
    local mother = c and (" Mother " .. BrgRng(p:getPoint(), c:getPoint()) .. ".") or ""
    Q(string.format("[OVERLORD] %s, Overlord, copy abort. RTB approved.%s Proceed outbound zero five zero. Report feet wet.", CFG.CS, mother), CFG.DUR_LONG, CFG.REPLY_GAP,
        function() SetPhase("RTB") end, nil,
        S("OVERLORD", "ovl_abort_a", c and { "o_mother", OBR(p:getPoint(), c:getPoint()) }, 0.15, "ovl_rtb_b"))
    ReadBack("OVERLORD", CFG.CS .. ", zero five zero, wilco.", "p_ovl_rtb_rb")
    QPlay()
end

-- v1.7.3 OVERLORD divert branch ----------------------------------------------------------
local DIV_PHASES = {}   -- v1.10.0: = the OVERLORD phases (incl. the roster's JTAC phases)
for ph in pairs(OVL_PHASES) do DIV_PHASES[ph] = true end

--- Nearest divert field to pos: field, NM.
local function DivertField(pos)
    local best, bd
    for _, f in ipairs(CFG.DIVERT.FIELDS) do
        if not f.pos then
            local ok, v = pcall(coord.LLtoLO, f.lat, f.lon, 0)
            if ok and v then f.pos = v end
        end
        if f.pos then
            local d = Dist2D(pos, f.pos)
            if not bd or d < bd then best, bd = f, d end
        end
    end
    return best, bd
end

--- Flight_Timeline BINGO for the hero's current zone (lb), nil without TL >= v1.1.2.
local function BingoNow(p)
    local tl = _G.TRT and _G.TRT.TL
    if not (tl and tl.thresholds) then return nil end
    local ok, thr = pcall(tl.thresholds, p:getPoint(), CD, nil)
    return (ok and type(thr) == "table") and thr.bingo or nil
end

local function A_Divert()
    local p = Player(); if not p then return end
    local pos = p:getPoint()
    local f, d = DivertField(pos)
    if not f then Msg("[CAS-1] No divert field available.", CFG.DUR_SHORT); return end
    local lb, bingo = FuelLb(p), BingoNow(p)
    local isBingo = (bingo ~= nil) and lb <= bingo + CFG.DIVERT.BINGO_TOL_LB
    local minFuel = (bingo ~= nil) and lb < bingo - CFG.DIVERT.BINGO_TOL_LB   -- v1.7.4 [OPNAV M-3710.7 6.2.6]
    CD.divert = { t = timer.getTime(), field = f.key, name = f.name, lb = lb, bingo = bingo,
                  isBingo = isBingo, minFuel = minFuel, from = CD.phase, dNm = d }
    env.info(string.format("[CD] DIVERT %s (%s) from %s, %.0f NM, state %.0f lb, bingo %s%s", f.key, f.name,
        CD.phase, d, lb, bingo and string.format("%.0f", bingo) or "n/a", isBingo and " (bingo call)" or ""))
    CD.tk = nil
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, %sdiverting %s, %sangels %d, state %s.", CFG.CS,
        isBingo and "bingo, " or "", f.name, minFuel and "minimum fuel, " or "", Angels(p), State(p)),
        Voiced(S("OVERLORD", (isBingo and "p_ovl_divb_" or "p_ovl_div_") .. f.clip, minFuel and "p_min_fuel" or nil, PAS(p))))
    local fa = _G.TRT and _G.TRT.FA                                  -- v1.7.5
    local useFA = fa and fa.Supports and fa.Supports(f.key) and f.ank and true or false
    local toTxt = useFA and string.format("Contact Ankara Control, %s.", f.ank)
        or string.format("Contact %s tower, %s.", f.name, f.twr)
    local sfx = useFA and "_ank" or ""
    Q(string.format("[OVERLORD] %s, Overlord, copy divert. %s %s. Proceed direct. %s",
        CFG.CS, f.name, BrgRng(pos, f.pos), toTxt), CFG.DUR_LONG, CFG.REPLY_GAP,
        function() SetPhase("DIVERT") end, nil,
        Voiced(S("OVERLORD", "ovl_div_a", "o_" .. f.clip, OBR(pos, f.pos), 0.15, "ovl_div_b_" .. f.clip .. sfx)))
    local prev = CD.queue[#CD.queue]
    if prev then prev.hold = 0.1 end
    Q(string.format("[%s] %s, proceeding direct, switching %s.", CFG.CS, CFG.CS, useFA and "Ankara" or (f.name .. " tower")),
        CFG.DUR_PILOT + 2, 0.8,
        useFA and function()
            local ok, err = pcall(fa.Start, f.key, { minFuel = minFuel, isBingo = isBingo })
            if not ok then env.info("[CD] Field_Arrival start failed: " .. tostring(err)) end
        end or nil,
        CFG.PILOT_HOLD, Voiced(S("OVERLORD", "p_div_rb_" .. f.clip .. sfx)))
    QPlay()
end

local function A_StrikeCheckInIn()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Strike, %s, inbound, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
        S("STRIKE", "p_str_inbound_a", PAS(p)))
    Q(string.format("[STRIKE] %s, Strike, radar contact, Mode 4 sweet. Continue zero five zero. "
        .. "Marshal at 50 miles, %s.", CFG.CS, Btn("MARSHAL")),
        CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("INBOUND") end, nil, "str_inbound")
    Ack("STRIKE", true)
    QPlay()
end

local function A_FeetReport()
    local kind = CD.feetPending; if not kind then return end
    CD.feetPending = nil
    local word = (kind == "DRY") and "feet dry" or "feet wet"
    Pilot(string.format("Overlord, %s, %s.", CFG.CS, word), "p_ovl_feet_" .. kind:lower())
    Q(string.format("[OVERLORD] %s, Overlord, copy %s.", CFG.CS, word), CFG.DUR_SHORT, CFG.REPLY_GAP, nil, nil, "ovl_feet_" .. kind:lower())
    QPlay()
    MenuRebuild()
end

local function A_Picture()
    if not OVL_PHASES[CD.phase] then
        Msg("[CAS-1] Not checked in with OVERLORD.", 7); return
    end
    local p = Player(); if not p then return end
    Pilot(string.format("Overlord, %s, request picture.", CFG.CS), "p_ovl_picture")
    local picTxt, picSeq = PictureParts(p:getPoint())
    picTxt = (picTxt:gsub("^Picture", "picture"))
    Q(string.format("[OVERLORD] %s, Overlord, %s SAM activity reported in the target areas.",
        CFG.CS, picTxt), CFG.DUR_SHORT + 4, CFG.REPLY_GAP, nil, nil,
        S("OVERLORD", "ovl_switch_strike_a", picSeq, 0.1, "o_sam_rmk"))
    QPlay()
end

-- ══════════════════════════════════════════════════════════════
--  TROOPS IN CONTACT + 9-LINE READBACK  (v1.5.4)
-- ══════════════════════════════════════════════════════════════
local JT = {}   -- v1.9.0 from CAS_PACK; v1.10.0 one entry per roster key (tgt = target group after Tasking_Pick)
for _, k in ipairs(P.order) do
    local j = P.jtacs[k]
    JT[k] = { ch = j.ch, k = j.ck, cn = j.cn, cs = j.cs, disp = j.disp, short = j.short, tgt = j.targets[1],
              jtac = j.group, phase = RS.ph[k], btn = k, pos = j.tgt_fallback }
end
local FR_CS = P.friendly.cs

-- Tension exchanges: Bravo 2-1 -> JTAC (-> pilot). <J> = JTAC short callsign, <CS> = hero.
-- Clips: fr_<k>_<i>, <k>_t<i>; pilot p_expediting / p_cs + digits + p_min_out.
local TIC_CALLS = {
    { fr = "<J>, " .. P.friendly.name .. "! We are pinned down, taking heavy fire from the ridge. Where is my air?",
      jt = P.friendly.name .. ", <J>. Fast movers inbound, minutes out. Keep your heads down." },
    { fr = "<J>, " .. P.friendly.name .. ", we have one wounded! I need that air now!",
      jt = "Copy one wounded. <CS>, <J>, friendlies are taking casualties. Expedite.", pilot = "expedite" },
    { fr = "<J>, " .. P.friendly.name .. ", enemy armor is pushing toward our position!",
      jt = P.friendly.name .. ", hold what you've got. <CS>, <J>, enemy is closing on friendlies. Say time out.",
      pilot = "time" },
    { fr = "<J>, " .. P.friendly.name .. ", we are running low on ammo. We can't hold much longer!",
      jt = "Copy, " .. P.friendly.name .. ". Air is almost overhead, hang on." },
}

local function Fill(s, j)
    local r = s:gsub("<J>", j.short)
    r = r:gsub("<CS>", CFG.CS)
    return r
end

local function AliveUnits(gname)
    local out, g = {}, Group.getByName(gname)
    if not g or not g:isExist() then return out end
    for _, u in ipairs(g:getUnits() or {}) do
        if u and u:isExist() and u:getLife() > 0 then out[#out + 1] = u end
    end
    return out
end

--- Live centroid of the JTAC's target group, nil when it is dead.
local function TicTgtPos(j)
    local us = AliveUnits(j.tgt)
    if #us == 0 then return nil end
    local sx, sz = 0, 0
    for _, u in ipairs(us) do local q = u:getPoint(); sx, sz = sx + q.x, sz + q.z end
    return { x = sx / #us, y = 0, z = sz / #us }
end

--- Readback target unit: JTAC_Laser's spot unit when it has one, else the first alive unit
--- in JTAC_Laser's PRIORITY type order (SAM first), else ME order.
local function TicTgtUnit(j)
    local jl = _G.TRT and _G.TRT.JL
    if jl then
        for _, pr in ipairs(jl.pairs or {}) do
            if pr.target == j.tgt and pr.unit then
                local u = Unit.getByName(pr.unit)
                if u and u:isExist() and u:getLife() > 0 then return u end
            end
        end
    end
    local prio = {}
    for i, t in ipairs((jl and jl.CFG and jl.CFG.PRIORITY) or {}) do prio[t] = i end
    local best, bp
    for i, u in ipairs(AliveUnits(j.tgt)) do
        local pr = prio[u:getTypeName()] or (100 + i)
        if not bp or pr < bp then best, bp = u, pr end
    end
    return best
end

--- "N minutes out": range to the target group / ground speed (floor CFG.TIC.GS_MIN), 2..99.
local function MinutesOut(p, tp)
    if not tp then return 5 end
    local v = p:getVelocity()
    local gs = math.max(CFG.TIC.GS_MIN, math.sqrt(v.x * v.x + v.z * v.z))
    local m = math.ceil(Dist2D(p:getPoint(), tp) * 1852 / gs / 60)
    return math.max(2, math.min(m, 99))
end

--- Pick the TIC JTAC once (v1.8.0: together with the tasking scenario, ScenPick).
TicPick = function()
    if CD.tic ~= nil then return CD.tic end
    ScenPick()
    return CD.tic
end

--- Queued right after OVERLORD's TIC hand-off transmission.
--- v1.8.0 opts.noPush: the pilot has already switched (OVERLORD divert), no "push button, buster" readback.
TicHandoff = function(key, opts)
    local j = JT[key]
    local btn = CFG.BTN[j.btn]
    if not (opts and opts.noPush) then
        local prev = CD.queue[#CD.queue]
        if prev then prev.hold = 0.1 end
        local mx = opts and opts.msn   -- v1.11.0 XCAS: "Mission 4137, push button 10, ..."
        Q(string.format("[%s] %sPush button %d, %s, buster.", CFG.CS, mx and ("Mission " .. mx .. ", ") or "", btn, CFG.CS),
            CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD,
            S("OVERLORD", mx and { "p_mission", PD(mx), 0.1 } or {}, "p_tic_push_" .. btn), nil, nil, true)
    end
    CD.ticState = { key = key, n = 0, used = {}, next = nil, done = false, bda = false }
    Q(string.format("[%s] %s, %s, TROOPS IN CONTACT, troops in contact! " .. P.friendly.name .. " is taking effective "
        .. "fire from enemy armor. Request immediate CAS, say time out.", j.cs, CFG.CS, j.disp),
        CFG.DUR_URGENT, CFG.TIC.FIRST_S, function()
            env.info("[CD] TIC call " .. j.disp)
            if CD.ticState then CD.ticState.callT = timer.getTime() end   -- v1.7.12
        end, nil,
        S(j.ch, j.k .. "_tic"))
    CD.queue[#CD.queue].hold = 0.1
    local p = Player()
    local m = p and MinutesOut(p, TicTgtPos(j)) or 5
    Q(string.format("[%s] %s, %s, copy troops in contact, %d minutes out.", CFG.CS, j.disp, CFG.CS, m),
        CFG.DUR_PILOT, 1.0, nil, CFG.PILOT_HOLD, S(j.ch, "p_tic_copy_" .. j.k, PD(m), "p_min_out"), nil, nil, true)
    Q(string.format("[%s] %s, copy. Check in when ready for nine-line, we need you now.", j.cs, CFG.CS),
        CFG.DUR_SHORT + 2, CFG.REPLY_GAP, function()
            if JcOn() then   -- v1.6.0
                Msg(string.format("[CAS-1] Check in with %s: F10 > COMMS.", j.disp), CFG.DUR_HANDOFF)
            else
                Msg(string.format("[CAS-1] Check in with %s in the DCS JTAC menu (native 9-line). "
                    .. "Readback: F10 > COMMS.", j.disp), CFG.DUR_HANDOFF)
            end
            local s = CD.ticState
            if s then
                s.next = timer.getTime() + math.random(CFG.TIC.GAP_MIN, CFG.TIC.GAP_MAX)
                s.ready = true   -- v1.7.11: JTAC_Controller may now offer the check-in
            end
        end, nil, S(j.ch, j.k .. "_tic_ack"), nil)
    -- v1.8.4: the check-in item opens when the JTAC's call STARTS again (v1.8.0 had moved it to the end)
    local it = CD.queue[#CD.queue]
    AtStart(it, it.fn)
end

--- Main-tick pump for the tension exchanges.
local function TicTick(now, p)
    local s = CD.ticState
    if not s or s.done or not s.next or now < s.next then return end
    local j = JT[s.key]
    if CD.phase ~= j.phase then return end
    local tp = TicTgtPos(j)
    if not tp then s.done = true; return end
    local d = Dist2D(p:getPoint(), tp)
    if d <= CFG.TIC.QUIET_NM or s.n >= CFG.TIC.MAX_CALLS then
        s.done = true
        env.info(string.format("[CD] TIC tension calls end (%d made, hero %.1f NM)", s.n, d))
        return
    end
    if CD.qPlaying or #CD.queue > 0 then s.next = now + 5; return end
    local free = {}
    for i = 1, #TIC_CALLS do if not s.used[i] then free[#free + 1] = i end end
    if #free == 0 then s.done = true; return end
    local i = free[math.random(1, #free)]
    s.used[i], s.n = true, s.n + 1
    s.next = now + math.random(CFG.TIC.GAP_MIN, CFG.TIC.GAP_MAX)
    local c = TIC_CALLS[i]
    Q("[" .. FR_CS .. "] " .. Fill(c.fr, j), CFG.DUR_URGENT, 0, nil, nil, S(j.ch, "fr_" .. j.k .. "_" .. i))
    CD.queue[#CD.queue].hold = 0.1
    Q("[" .. j.cs .. "] " .. Fill(c.jt, j), CFG.DUR_SHORT + 2, 0.8, nil, nil, S(j.ch, j.k .. "_t" .. i))
    if c.pilot == "expedite" then
        ReadBack(j.ch, CFG.CS .. ", copy, expediting.", "p_expediting")
    elseif c.pilot == "time" then
        local m = MinutesOut(p, tp)
        CD.queue[#CD.queue].hold = 0.1
        Q(string.format("[%s] %s, %d minutes out.", CFG.CS, CFG.CS, m), CFG.DUR_PILOT, 0.8, nil,
            CFG.PILOT_HOLD, S(j.ch, "p_cs", PD(m), "p_min_out"))
    end
    env.info(string.format("[CD] TIC tension %d/%d (#%d), hero %.1f NM", s.n, CFG.TIC.MAX_CALLS, i, d))
    QPlay()
end

--- Called from SetPhase on J1_OFF / J2_OFF (target group dead).
local function TicBDA(key)
    local s = CD.ticState
    if not s or s.key ~= key or s.bda then return end
    s.bda, s.done = true, true
    local j = JT[key]
    CD.awaiting = true   -- v1.8.0: no OVERLORD call (retasking / INFLTREP) before Bravo 2-1's thanks has been heard
    timer.scheduleFunction(function()
        if not JcOn() then   -- v1.6.0: JTAC_Controller already gave the BDA
            Q(string.format("[%s] %s, %s, good hits, good hits! Enemy fire has stopped.", j.cs, CFG.CS, j.disp),
                CFG.DUR_SHORT + 2, 0, nil, nil, S(j.ch, j.k .. "_bda"))
            CD.queue[#CD.queue].hold = 0.1
        end
        AtStart(Q(string.format("[%s] %s, " .. P.friendly.name .. ", contact broken, fire has stopped. Tell that Hornet thanks.",
            FR_CS, j.short), CFG.DUR_SHORT + 2, 1.0, nil, nil, S(j.ch, "fr_" .. j.k .. "_bda")),
            function() CD.awaiting = false; MenuRebuild() end)   -- v1.8.4: at the start of the thanks
        ReadBack(j.ch, CFG.CS .. ", copy. Glad to help.", "p_tic_thanks")
        QPlay()
        env.info("[CD] TIC BDA " .. j.disp)
    end, nil, timer.getTime() + CFG.TIC.BDA_S)
end

-- ══════════════════════════════════════════════════════════════
--  TASKING ORDER / SCENARIOS  (v1.8.0, decisions Onur 2026-11-03)
-- ══════════════════════════════════════════════════════════════
local function KeyOfPhase(ph) return RS.key[ph] end   -- v1.10.0 roster (OFF_PH / MSN / JD -> RS)

--- Entropy: math.randomseed is nil in the mission sandbox; the ms of the first draw (a pilot F10 press)
--- seeds a Park-Miller generator, mixed with math.random. Rand(n) -> 1..n
local rngX
local function Rand(n)
    if not rngX then
        rngX = (math.floor(timer.getTime() * 1000) + math.random(0, 9999)) % 2147483646 + 1
    end
    rngX = (rngX * 16807) % 2147483647
    return rngX % n + 1
end
local function RandIn(lo, hi) return lo + Rand(hi - lo + 1) - 1 end

local function FlagN(f)
    local ok, v = pcall(trigger.misc.getUserFlag, tostring(f))
    return (ok and tonumber(v)) or 0
end

local function JC_()
    local jc = _G.TRT and _G.TRT.JC
    return (jc and jc.active) and jc or nil
end
local function JcCall(fn, ...)
    local jc = JC_()
    if jc and type(jc[fn]) == "function" then
        local ok, err = pcall(jc[fn], ...)
        if not ok then env.info("[CD] JC." .. fn .. " error: " .. tostring(err)) end
        return ok
    end
    return false
end

local function TargetDead(k) return CD.dead[k] or false end
local function JtacAlive(k) return #AliveUnits(JT[k].jtac) > 0 end

--- First tasking still to be worked (order), nil when the VUL is complete. A target group destroyed before
--- its tasking (not by the hero) is cancelled silently.
NextKey = function()
    for _, k in ipairs(CD.order) do
        if not CD.res[k] then
            if TargetDead(k) and not CD.worked[k] then
                CD.res[k], CD.why[k] = "cancelled", "target destroyed"
                env.info("[CD] task " .. k .. " cancelled before tasking: target group already destroyed")
            elseif k ~= CD.cur or CD.resume == k then
                return k
            end
        end
    end
    return nil
end

local function VulCheck()
    if CD.vulDone then return end
    for _, k in ipairs(CD.order) do if not CD.res[k] then return end end
    CD.vulDone, CD.vulT = true, timer.getAbsTime()
    local r = {}
    for _, k in ipairs(CD.tasked) do r[#r + 1] = k .. " " .. tostring(CD.res[k]) end
    env.info(string.format("[CD] VUL complete: %s, VUL extension %.0f s", table.concat(r, ", "), CD.vulExtS))
end

--- A worked tasking ended (target group dead, Winchester, ROE termination).
local function FinishTask(k)
    local jc = JC_()
    local inc = JcInc(k)
    local term = jc and jc.st and jc.st[k] and jc.st[k].phase == "TERMINATED"
    CD.res[k] = (inc and "incomplete") or (term and "terminated") or "done"
    if CD.resume == k then CD.resume = nil end
    if inc then   -- Winchester: nothing left to drop for the remaining taskings
        for _, o in ipairs(CD.order) do
            if not CD.res[o] then
                CD.res[o], CD.why[o] = "cancelled", "winchester"
                JcCall("cancel", o, "winchester")
                env.info("[CD] task " .. o .. " cancelled: Winchester at " .. JT[k].disp)
            end
        end
        RS.JD(k).tot = RS.JD(k).tot or timer.getAbsTime()
    end
    env.info(string.format("[CD] task %s %s", k, CD.res[k]))
    VulCheck()
end

--- Pick the scenario (once). Also picks the TIC JTAC (CD.tic), the order, lost comms and the tanker no-show.
ScenPick = function()
    if CD.scen then return CD.scen end
    local SC = CFG.SCEN
    local f = FlagN(SC.FLAG_SCEN)
    local kind = (f == 1 and "A") or (f == 2 and "B") or (f == 3 and "C") or nil
    local forced = kind ~= nil
    if not kind then
        local r = Rand(100)
        kind = (r <= SC.P.A and "A") or (r <= SC.P.A + SC.P.B and "B") or "C"
    end
    -- v1.10.0: on the slots T = CD.tasked (flags 214 / 215 / 211: 1 / 2 = slot 1 / 2); same Rand sequence as v1.9
    local T = CD.tasked
    local tic
    local ft = FlagN(SC.FLAG_TIC)
    if not CFG.TIC.ENABLE or ft == 9 then tic = false
    elseif kind == "C" then tic = T[2]
    elseif ft == 1 or ft == 2 then tic = T[ft]
    elseif CFG.TIC.WHO == T[1] or CFG.TIC.WHO == T[2] then tic = CFG.TIC.WHO
    else tic = T[Rand(2)] end
    local order = { T[1], T[2] }
    local ff = FlagN(SC.FLAG_FIRST)
    if kind == "B" and (ff == 2 or (ff ~= 1 and Rand(2) == 2)) then order = { T[2], T[1] } end
    local lc
    local fl = FlagN(SC.FLAG_LC)
    if fl >= 1 and fl <= 4 then
        lc = { key = T[(fl <= 2) and 1 or 2], kind = (fl % 2 == 1) and "tech" or "down", forced = true }
    elseif fl ~= 9 and kind ~= "C" and Rand(100) <= SC.LC_P then
        local key = tic and RS.other(tic) or T[Rand(2)]
        lc = { key = key, kind = (Rand(100) <= SC.LC_TECH) and "tech" or "down" }
    end
    if lc and kind == "C" then
        env.info("[CD] scenario C: lost comms ignored (" .. lc.key .. ")"); lc = nil
    end
    if lc and tic == lc.key then tic = RS.other(lc.key) end   -- forced: the JTAC that calls TIC talks
    local fn = FlagN(SC.FLAG_NOSHOW)
    local noShow = (fn == 1) or (fn ~= 2 and Rand(1000) <= SC.NOSHOW_PM)
    CD.tic, CD.order = tic, order
    CD.scen = { kind = kind, lc = lc, noShow = noShow, forced = forced }
    if kind == "C" then
        CD.dv = { state = "armed", at = SC.DV_PHASES[Rand(#SC.DV_PHASES)], delay = RandIn(SC.DV_DELAY[1], SC.DV_DELAY[2]),
                  first = T[1], tic = T[2] }   -- v1.10.0: diverted from slot 1 to slot 2
    end
    SetFlag(SC.FLAG_PICKED, (kind == "A" and 1) or (kind == "B" and 2) or 3)
    if lc then JcCall("setNoComm", lc.key, lc.kind) end
    env.info(string.format("[CD] SCENARIO %s%s: order %s, TIC %s, lost comms %s, tanker no-show %s%s", kind,
        forced and " (flag)" or "", table.concat(order, " "), tic and JT[tic].disp or "off",
        lc and (JT[lc.key].disp .. " " .. lc.kind) or "none", noShow and "YES" or "no",
        CD.dv and string.format(", divert at %s +%d s", CD.dv.at, CD.dv.delay) or ""))
    return CD.scen
end

-- ── OVERLORD tasking calls ────────────────────────────────────────────────────────────────
local LINE = {   -- clip / text of the contact line per JTAC
    J1 = { on = "ovl_contact_pointer_b", tic = "ovl_tic_pointer_b", res = "ovl_resume_ptr" },
    J2 = { on = "ovl_contact_eyeball_b", tic = "ovl_tic_eyeball_c" },
}
for k, j in pairs(JT) do   -- v1.10.0: other roster keys by their pack clip names (cn / ck)
    LINE[k] = LINE[k] or { on = "ovl_contact_" .. tostring(j.cn) .. "_b", tic = "ovl_tic_" .. tostring(j.cn) .. "_b",
                           res = "ovl_resume_" .. j.k }
end

--- OVERLORD hands the hero to JTAC k. mode: "cp" (ENROUTE, "CP TIGER bears ..."), "task" (B, after the hold),
--- "retask" (after "off <JTAC>": "copy. Return to CP TIGER ..."), "cancel" (right after a cancellation call).
--- The JTAC phase starts when the pilot's readback has ENDED (JTAC_Controller offers the check-in then).
C_OvlContact = function(k, p, mode)
    local j = JT[k]
    local tic = (CD.tic == k) and not CD.ticState
    local resume = (CD.resume == k)
    local L = LINE[k]
    local id = (tic and L.tic) or (resume and L.res) or L.on
    local line
    if tic then
        line = string.format("%s reports TROOPS IN CONTACT, priority immediate. Contact %s, %s, without delay. "
            .. "Return to this button on check-out.", j.disp, j.disp, Btn(j.btn))
    elseif resume then
        line = string.format("%s is holding. Contact %s, %s.", j.disp, j.disp, Btn(j.btn))
    else
        line = string.format("%s is on station. Contact %s, %s. Return to this button on check-out.", j.disp,
            j.disp, Btn(j.btn))
    end
    local pre, preSeq = "", {}
    local pp = p:getPoint()
    if mode == "cp" then
        pre = string.format("%s, Overlord. %s %s. ", CFG.CS, CFG.CP_NAME, BrgRng(pp, CFG.CP_POS))
        preSeq = { "ovl_contact_pointer_a", OBR(pp, CFG.CP_POS), 0.1 }
    elseif mode == "task" then
        pre = string.format("%s, Overlord, tasking. ", CFG.CS)
        preSeq = { "ovl_task_a", 0.1 }
    elseif mode == "retask" then
        pre = string.format("%s, Overlord, copy. Return to %s, %s. ", CFG.CS, CFG.CP_NAME, BrgRng(pp, CFG.CP_POS))
        preSeq = { "ovl_off_pointer_a", OBR(pp, CFG.CP_POS), 0.1 }
    else
        pre = string.format("%s, Overlord. ", CFG.CS)
        preSeq = { "ovl_switch_strike_a", 0.1 }
    end
    CD.awaiting = true
    CD.cur = k
    -- v1.11.0 XCAS: the mission number comes with the (first) tasking of this JTAC
    CD.msnGiven = CD.msnGiven or {}
    local mx = P.xcas and not CD.msnGiven[k] and RS.MSN[k] or nil
    if mx then CD.msnGiven[k] = true; pre = pre .. "Mission " .. mx .. ". " end
    local ovlIt = Q("[OVERLORD] " .. pre .. line, CFG.DUR_LONG, (mode == "retask") and CFG.REPLY_GAP or 0, nil, nil,
        Voiced(S("OVERLORD", preSeq, mx and { "o_mission", OD(mx), 0.15 } or {}, id)))
    local enter = function()
        CD.taskT = CD.taskT or {}
        CD.taskT[k] = timer.getTime()
        if CD.resume == k then
            JcCall("resume", k)          -- fresh check-in after the divert
        end
        SetPhase(j.phase)
        QPlay()
    end
    -- v1.8.4: the JTAC phase (its check-in item) starts when OVERLORD's line starts (was: the end of the
    -- pilot's push readback); a check-in pressed now is transmitted after the readback (FIFO)
    AtStart(ovlIt, enter)
    if tic then
        TicHandoff(k, mx and { msn = mx } or nil)
    elseif mx then   -- v1.11.0 XCAS readback "Mission 4137, push button 10, Hornet 51."
        local prev = CD.queue[#CD.queue]
        if prev then prev.hold = 0.1 end
        Q(string.format("[%s] Mission %s, push button %d, %s.", CFG.CS, mx, CFG.BTN[j.btn], CFG.CS),
            CFG.DUR_PILOT, 0.8, nil, CFG.PILOT_HOLD, S("OVERLORD", "p_mission", PD(mx), 0.1, "p_push_" .. CFG.BTN[j.btn]),
            nil, nil, true)
    else
        Ack("OVERLORD", false, CFG.BTN[j.btn])
    end
    env.info(string.format("[CD] tasking %s (%s%s%s%s)", j.disp, mode, tic and ", TIC" or "", resume and ", resume" or "",
        mx and (", mission " .. mx) or ""))
end

--- F10 in J1_OFF / J2_OFF while a tasking remains.
local function A_OvlOffJtac(k)
    local p = Player(); if not p then return end
    local nk = NextKey()
    if not nk then return A_Inflrep() end
    CD.awaiting = true; MenuRebuild()
    local j = JT[k]
    Pilot(string.format("Overlord, %s, off %s, mission %s complete, angels %d, state %s. Ready for retasking.",
        CFG.CS, j.disp, RS.MSN[k], Angels(p), State(p)),
        S("OVERLORD", P.xcas and { "p_ovl_off_x_" .. j.k, PD(RS.MSN[k]), "p_complete" }   -- v1.11.0 XCAS numbers
            or ("p_ovl_off_" .. tostring(j.cn) .. "_a"), PAS(p), 0.15, "p_ovl_off_pointer_b"))
    C_OvlContact(nk, p, "retask")
    QPlay()
end

-- ── B: hold at CP TIGER ─────────────────────────────────────────────────────────────────
local function C_OvlHold()
    local SC = CFG.SCEN
    CD.awaiting = true
    Q(string.format("[OVERLORD] %s, Overlord. Hold at %s, angels %d. Expect tasking in five minutes.", CFG.CS,
        CFG.CP_NAME, SC.HOLD_ANGELS), CFG.DUR_LONG, 0, nil, nil, Voiced(S("OVERLORD", "ovl_hold")))
    ReadBack("OVERLORD", string.format("%s, holding %s, angels %d.", CFG.CS, CFG.CP_NAME, SC.HOLD_ANGELS), "p_hold_rb")
    CD.queue[#CD.queue].onEnd = function()
        CD.hold = { t0 = timer.getTime() }
        SetPhase("HOLD")
    end
    env.info("[CD] B: hold at " .. CFG.CP_NAME)
end

local function HoldTick(p)
    local h = CD.hold
    if not h or CD.phase ~= "HOLD" then return end
    local SC, now = CFG.SCEN, timer.getTime()
    if not h.armT and (Dist2D(p:getPoint(), CFG.CP_POS) <= SC.HOLD_NM or now - h.t0 >= SC.HOLD_MAX_S) then
        h.armT = now
        h.fireT = now + RandIn(SC.HOLD_WAIT[1], SC.HOLD_WAIT[2])
        env.info(string.format("[CD] B: hold armed (%.0f s after the call), tasking in %.0f s", now - h.t0, h.fireT - now))
    end
    if h.fireT and now >= h.fireT and not CD.awaiting and RadioIdle() then
        local k = NextKey()
        CD.vulExtS = CD.vulExtS + (now - h.armT)
        CD.hold = nil
        if k then C_OvlContact(k, p, "task"); QPlay() end
    end
end

-- ── C: OVERLORD diverts the hero from Pointer 11 to Eyeball 11 (TIC) ──────────────────────────
local DV_IDX = {}
for i, ph in ipairs(CFG.SCEN.DV_PHASES) do DV_IDX[ph] = i end

local function PState(u)
    local i, f = State(u):match("^(%d+)%.(%d)$")
    return { "cv:p_state", PD(i or "0"), "cv:p_point", PD(f or "0") }
end

local function DivertTick(p)
    local dv = CD.dv
    if not dv or dv.state ~= "armed" or CD.phase ~= RS.ph[dv.first] then return end
    local jc = JC_()
    local st = jc and jc.st and jc.st[dv.first]
    local J1, J2 = P.jtacs[dv.first], P.jtacs[dv.tic]   -- v1.10.0: slot 1 (diverted from) / slot 2 (TIC)
    if not st then return end
    -- window: the dialogue phases, and ATTACK until the pilot reports IP inbound (not yet committed to an attack)
    local inAtk = st.phase == "ATTACK" and st.att and not st.att.ipIn
    if (st.phase == "ATTACK" and not inAtk) or st.phase == "DONE" or st.phase == "TERMINATED" or st.phase == "NOCOMM"
        or st.phase == "SILENT" then
        dv.state = "missed"
        env.info("[CD] C: divert window missed (" .. J1.disp .. " " .. st.phase .. ") -> scenario runs as A")
        return
    end
    local i = DV_IDX[st.phase] or (inAtk and (#CFG.SCEN.DV_PHASES + 1)) or nil
    if not i or i < DV_IDX[dv.at] then return end
    local now = timer.getTime()
    dv.since = dv.since or now            -- first second inside the chosen phase (or later)
    if now - dv.since < dv.delay then return end
    -- v1.8.4: break in right after the call on the air (nothing else waiting); was RadioIdle(), which a pilot
    -- who answers while the JTAC is still talking (items open at the start of the call) never leaves
    if st.busy or GateWaiting() or CD.awaiting then return end
    local SC = CFG.SCEN
    local lb, bingo = FuelLb(p), BingoNow(p) or 4100
    local tp = TicTgtPos(JT[dv.tic]) or JT[dv.tic].pos
    local need = bingo + Dist2D(p:getPoint(), tp) * SC.DV_BURN_LB_NM + SC.DV_RESERVE_LB
    if lb < need then
        dv.state = "nofuel"
        env.info(string.format("[CD] C: no divert, fuel %.0f < %.0f lb (bingo %.0f + transit + %d)", lb, need, bingo,
            SC.DV_RESERVE_LB))
        return
    end
    dv.state, dv.t = "asked", now
    JcCall("freeze", dv.first, true)
    CD.msnGiven = CD.msnGiven or {}   -- v1.11.0 XCAS: the TIC tasking's number comes with the divert
    local mx = P.xcas and not CD.msnGiven[dv.tic] and RS.MSN[dv.tic] or nil
    if mx then CD.msnGiven[dv.tic] = true; dv.msn = mx end
    local clip = (dv.first == "J1" and dv.tic == "J2" and not mx) and S("OVERLORD", "ovl_divert_a", 0.15, "ovl_divert_b")
        or S("OVERLORD", "ovl_divert_a", 0.15, mx and { "o_mission", OD(mx), 0.15 } or {},   -- v1.11.0 any pair
             "ovl_dv_" .. tostring(JT[dv.tic].cn), "ovl_adv_" .. JT[dv.first].k)
    AtStart(Q(string.format("[OVERLORD] %s, Overlord, divert, divert. " .. (mx and ("Mission " .. mx .. ". ") or "")
        .. J2.disp .. " reports TROOPS IN CONTACT, priority "
        .. "immediate. Contact " .. J2.disp .. ", %s, without delay. " .. J1.disp .. " is advised.", CFG.CS, Btn(dv.tic)),
        CFG.DUR_URGENT + 4, 0, nil, nil, clip and Voiced(clip)),
        function() dv.open = true; MenuRebuild() end)   -- v1.8.4: wilco / unable open at the start
    env.info(string.format("[CD] C: OVERLORD divert (" .. J1.disp .. " in %s, fuel %.0f lb)", st.phase, lb))
    QPlay()
end

-- v1.8.0: OVERLORD breaks in between two transmissions -> checked every second, not on the 5 s main tick
timer.scheduleFunction(function(_, t)
    if CD.dv and CD.dv.state == "armed" then
        local p = Player()
        if p then
            local ok, err = pcall(DivertTick, p)
            if not ok then env.info("[CD] divert error: " .. tostring(err)) end
        end
    end
    if CD.phase == "DONE" or CD.phase == "RECOVERY" then return nil end
    return t + 1
end, nil, timer.getTime() + 5)

local function A_DivertWilco()
    local dv = CD.dv; if not dv or not dv.open then return end
    dv.open, dv.state = false, "accepted"
    CD.awaiting = true; MenuRebuild()
    local f, t = dv.first, dv.tic   -- v1.10.0 slots
    local jf = JT[f]
    local t1 = CD.taskT and CD.taskT[f]
    if t1 then CD.vulExtS = CD.vulExtS + (timer.getTime() - t1) end   -- the slot-1 work done so far is repeated
    Q(string.format("[%s] %s, wilco.", CFG.CS, CFG.CS), CFG.DUR_PILOT, 0.3, nil, CFG.PILOT_HOLD,
        S("OVERLORD", "p_wilco"))
    Q(string.format("[%s] " .. jf.disp .. ", %s, diverted by Overlord to troops in contact. Will return when able.", CFG.CS,
        CFG.CS), CFG.DUR_PILOT + 2, 1.5, nil, CFG.PILOT_HOLD, Voiced(S(jf.ch, "p_divert_" .. jf.k)))
    Q(string.format("[" .. jf.cs .. "] %s, " .. jf.disp .. ", copy. No other CAS available, we'll hold. Return when able.", CFG.CS),
        CFG.DUR_SHORT + 2, CFG.REPLY_GAP, function() JcCall("suspend", f) end, nil,
        Voiced(S(jf.ch, jf.k .. "_divert_ack")),
        function()
            CD.order, CD.resume, CD.cur = { t, f }, f, t
            CD.taskT = CD.taskT or {}
            CD.taskT[t] = timer.getTime()
            TicHandoff(t, { noPush = true })
            SetPhase(RS.ph[t])
            QPlay()
        end)
    env.info("[CD] C: divert accepted")
    QPlay()
end

local function A_DivertUnable()
    local dv = CD.dv; if not dv or not dv.open then return end
    local p = Player(); if not p then return end
    dv.open, dv.state = false, "refused"
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, unable divert, state %s.", CFG.CS, State(p)),
        Voiced(S("OVERLORD", "p_divert_unable", PState(p))))
    Q(string.format("[OVERLORD] %s, Overlord, copy. Continue with " .. P.jtacs[dv.first].disp .. ".", CFG.CS), CFG.DUR_SHORT,
        CFG.REPLY_GAP, nil, nil, Voiced(S("OVERLORD", (dv.first == "J1") and "ovl_divert_unable"
            or ("ovl_dvu_" .. JT[dv.first].k))),   -- v1.11.0 any pair
        function() JcCall("freeze", dv.first, false); CD.awaiting = false; MenuRebuild() end)
    env.info(string.format("[CD] C: divert refused by the pilot, state %s", State(p)))
    QPlay()
end

-- ── Lost comms with a JTAC (JTAC_Controller phase NOCOMM after two unanswered calls) ─────────────────
local function LcAnswer(k)
    local p = Player(); if not p then return end
    local j = JT[k]
    local lc = CD.scen and CD.scen.lc
    local kind = (lc and lc.key == k and lc.kind) or "down"
    if not JtacAlive(k) or (CD.lcAlt and CD.lcAlt[k]) then kind = "down" end   -- dead, or already on the alternate
    CD.lcs[k].kind = kind
    if kind == "tech" then
        local alt = CFG.ALT[k]
        local altIt = Q(string.format("[OVERLORD] %s, Overlord. %s reports radio failure on primary. Contact %s on "
            .. "alternate, push button %d (%s).", CFG.CS, j.disp, j.disp, alt.btn, alt.freq), CFG.DUR_LONG, 0, nil, nil,
            Voiced(S("OVERLORD", "ovl_lc_alt_" .. j.k)))
        Ack("OVERLORD", false, alt.btn)
        AtStart(altIt, function()   -- v1.8.4: at the start of OVERLORD's call (was: the end of the readback)
            CFG.BTN[j.btn], CFG.FREQ[j.btn], CFG.CHAN[j.ch].hz = alt.btn, alt.freq, alt.hz
            CD.lcAlt = CD.lcAlt or {}
            CD.lcAlt[k] = true
            CD.lcs[k] = nil          -- a second loss (on the alternate) can be reported again
            JcCall("altFreq", k, alt.btn)
            CD.awaiting = false; MenuRebuild()
        end)
        env.info(string.format("[CD] lost comms %s: alternate button %d (%s)", j.disp, alt.btn, alt.freq))
    else
        CD.res[k], CD.why[k] = "cancelled", "lost comms"
        if CD.resume == k then CD.resume = nil end
        JcCall("cancel", k, "lost comms")
        Q(string.format("[OVERLORD] %s, Overlord. %s is off the net, unable to raise. Mission %s cancelled.", CFG.CS,
            j.disp, RS.MSN[k]), CFG.DUR_LONG, 0, nil, nil, Voiced(S("OVERLORD", P.xcas   -- v1.11.0 XCAS numbers
                and { "ovl_lc_dn_" .. j.k, OD(RS.MSN[k]), "o_cancelled" } or ("ovl_lc_down_" .. j.k))))
        VulCheck()
        local nk = NextKey()
        if nk then
            C_OvlContact(nk, p, "cancel")
        else
            Q(string.format("[OVERLORD] %s, Overlord. Say intentions.", CFG.CS), CFG.DUR_SHORT, 1, nil, nil, "ovl_say_int",
                function() SetPhase(RS.off[k]) end)
        end
        env.info(string.format("[CD] lost comms %s: mission %s cancelled%s", j.disp, RS.MSN[k], nk and (", next " .. nk) or ""))
    end
    QPlay()
end

local function A_UnableContact(k)
    local j = JT[k]
    if CD.lcs[k] then return end
    CD.lcs[k] = { t = timer.getTime() }
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, unable contact %s.", CFG.CS, j.disp), Voiced(S("OVERLORD", "p_unable_" .. j.k)))
    Q(string.format("[OVERLORD] %s, Overlord, copy, stand by.", CFG.CS), CFG.DUR_SHORT, CFG.REPLY_GAP, nil, nil,
        Voiced(S("OVERLORD", "ovl_standby")), function()
            local w = RandIn(CFG.SCEN.STBY_S[1], CFG.SCEN.STBY_S[2])
            env.info(string.format("[CD] lost comms %s reported, OVERLORD answer in %d s", j.disp, w))
            timer.scheduleFunction(function()
                local ok, err = pcall(LcAnswer, k)
                if not ok then env.info("[CD] LcAnswer error: " .. tostring(err)); CD.awaiting = false end
            end, nil, timer.getTime() + w)
        end)
    QPlay()
end

local function LcNeeded(k)
    local jc = JC_()
    return (jc and jc.st and jc.st[k] and jc.st[k].phase == "NOCOMM" and CD.lcs[k] == nil) and true or false
end

-- ── AR1 tanker gone (no-show or lost): say intentions ─────────────────────────────────────────
C_NoShow = function()
    CD.tkrLost, CD.ar1Done, CD.ar1Int = true, true, true
    pcall(function()
        local t = Tanker()
        if t then t:getGroup():destroy() end   -- destroy() raises no event (no "mission loss")
    end)
    Q(string.format("[OVERLORD] %s, Overlord, Texaco 11 is off station, no tanker available. Say intentions.", CFG.CS),
        CFG.DUR_LONG, 2, nil, nil, Voiced(S("OVERLORD", "ovl_tkr_lost_si")))
    env.info("[CD] tanker NO-SHOW: Texaco 11 removed, OVERLORD asks for intentions")
end

local function A_ContNoTkr()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("Overlord, %s, continuing mission without tanker, angels %d, state %s.", CFG.CS, Angels(p), State(p)),
        Voiced(S("OVERLORD", "p_ovl_cont_notkr_a", PAS(p))))
    Q(string.format("[OVERLORD] %s, Overlord, copy.", CFG.CS), CFG.DUR_SHORT, CFG.REPLY_GAP, nil, nil,
        Voiced(S("OVERLORD", "ovl_copy_51")), function() CD.ar1Int = false; CD.awaiting = false; MenuRebuild() end)
    env.info("[CD] AR1: continuing without tanker")
    QPlay()
end

-- ── INFLTREP (JP 3-09.3 Fig V-17), per-tasking results ─────────────────────────────────────
local function Destroyed(k)
    local inc = JcInc(k)
    if inc then return inc.destroyed or 0 end
    local r = CD.res[k]
    if r == "done" then return RS.JD(k).size or 0 end
    local size = RS.JD(k).size or 0
    return math.max(0, size - #AliveUnits(JT[k].tgt))
end

A_Inflrep = function()
    local p = Player(); if not p then return end
    CD.awaiting = true; MenuRebuild()
    local T = CD.tasked                    -- v1.10.0: the two taskings in fragged order (slots)
    local d1, d2 = RS.JD(T[1]), RS.JD(T[2])
    local n1, n2 = Destroyed(T[1]), Destroyed(T[2])
    local rmk, rmkSeq = "Remarks, SAM activity in both target areas.", {}
    local std = (T[1] == "J1" and T[2] == "J2") and not P.xcas   -- v1.10.1: i_l2 / i_rmk_* speak 4101 / 4102
    for idx, k in ipairs(T) do
        local r, why = CD.res[k], CD.why[k]
        if r == "incomplete" or (r == "cancelled" and why == "winchester") then
            rmk = rmk .. string.format(" Mission %s incomplete, Winchester.", RS.MSN[k])
            rmkSeq[#rmkSeq + 1] = std and ("i_rmk_inc" .. idx) or { "i_rmk_msn", PD(RS.MSN[k]), "i_rmk_inc_b" }
        elseif r == "cancelled" then
            rmk = rmk .. string.format(" Mission %s cancelled, no JTAC contact.", RS.MSN[k])
            rmkSeq[#rmkSeq + 1] = std and ("i_rmk_can" .. idx) or { "i_rmk_msn", PD(RS.MSN[k]), "i_rmk_can_b" }
        end
    end
    Pilot(string.format("Overlord, %s, INFLTREP.\n"
        .. "Line 1, %s.\nLine 2, mission %s and %s.\nLine 3, %s and %s.\n"
        .. "Line 4, time on target %s and %s.\nLine 5, %d and %d vehicles destroyed.\n%s",
        CFG.CS, CFG.CS, RS.MSN[T[1]], RS.MSN[T[2]],
        d1.pos and MGRS(d1.pos) or "unknown", d2.pos and MGRS(d2.pos) or "unknown",
        Clock(d1.tot), Clock(d2.tot), n1, n2, rmk),
        S("OVERLORD", "i_head", "i_l1",
          std and "i_l2" or { "i_l2_a", PD(RS.MSN[T[1]]), "cv:p_and", PD(RS.MSN[T[2]]), 0.2 },
          "i_l3", PSpell(d1.pos and MGRS(d1.pos)), 0.1, "cv:p_and", PSpell(d2.pos and MGRS(d2.pos)), 0.25,
          "i_l4", PClock(d1.tot), 0.1, "cv:p_and", PClock(d2.tot), 0.25,
          "i_l5", PD(n1), "cv:p_and", PD(n2), "i_l5b", "i_rmk", rmkSeq))
    -- INFLTREP is long — give it time on screen
    CD.queue[#CD.queue].dur  = CFG.DUR_LONG + 4
    CD.queue[#CD.queue].hold = 8
    if TkAlive() and not CD.tkrLost then                 -- v1.7.0: EMCON 2 RV vector + readback (v1.7.6 alive)
        TkOpen(2)
        TkrVector(p, 2)
    elseif CD.tkrLost then                               -- v1.7.6
        CD.tk = nil
        Q(string.format("[OVERLORD] %s, Overlord, copy INFLTREP. No tanker available. Say intentions.", CFG.CS),
            CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("REFUEL") end, nil,
            Voiced(S("OVERLORD", "ovl_inflrep_lost")))
    else
        CD.tk = nil
        Q(string.format("[OVERLORD] %s, Overlord, copy INFLTREP. Texaco 11 on station, TACAN 21 Yankee. Texaco, %s.",
            CFG.CS, Btn("TKR")), CFG.DUR_LONG, CFG.REPLY_GAP, function() SetPhase("REFUEL") end, nil,
            S("OVERLORD", "ovl_inflrep_nt"))
        Ack("OVERLORD", false, CFG.BTN.TKR)
    end
    QPlay()
end

local DIR8 = { "n", "ne", "e", "se", "s", "sw", "w", "nw" }
local DIR8_TXT = { n = "north", ne = "northeast", e = "east", se = "southeast",
                   s = "south", sw = "southwest", w = "west", nw = "northwest" }
local function Dir8(brg) return DIR8[math.floor(((brg % 360) + 22.5) / 45) % 8 + 1] end

--- Pilot tokens for a distance rounded to 100 m: "one thousand two hundred".
local function SpokenM(m)
    local t = {}
    local th, h = math.floor(m / 1000), math.floor((m % 1000) / 100)
    if th > 0 then t[#t + 1] = PD(th); t[#t + 1] = "p_thousand" end
    if h > 0 then t[#t + 1] = PD(h); t[#t + 1] = "p_hundred" end
    return t
end

--- F10: 9-line readback, Lines 4 / 6 / 8 from ground truth.
local function A_Readback(key)
    local j = JT[key]
    local tu = TicTgtUnit(j)
    if not tu then Msg("[CAS-1] " .. j.disp .. ": no live target for a readback.", CFG.DUR_SHORT); return end
    local tp = tu:getPoint()
    local okH, h = pcall(land.getHeight, { x = tp.x, y = tp.z })
    local elev = math.floor(((okH and h) or tp.y) * 3.28084 + 0.5)
    local grid = MGRS(tp)
    local ju = AliveUnits(j.jtac)[1]
    local frTxt, frSeq = "", {}
    if ju then
        local fp = ju:getPoint()
        local dx, dz = fp.x - tp.x, fp.z - tp.z
        local m = math.max(100, math.floor(math.sqrt(dx * dx + dz * dz) / 100 + 0.5) * 100)
        local d8 = Dir8(Bearing(tp, fp))
        frTxt = string.format(", friendlies %s %d meters", DIR8_TXT[d8], m)
        frSeq = { 0.2, "p_friendlies", "p_dir_" .. d8, SpokenM(m), "p_meters" }
    end
    CD.awaiting = true; MenuRebuild()
    Pilot(string.format("%s, %s, readback: elevation %d feet, grid %s%s.", j.disp, CFG.CS, elev, grid, frTxt),
        S(j.ch, "p_rb_" .. j.k, "p_elev", PD(elev), "p_feet", "p_grid", PSpell(grid), frSeq))
    CD.queue[#CD.queue].dur = CFG.DUR_LONG
    Q(string.format("[%s] %s, %s, readback correct.", j.cs, CFG.CS, j.disp), CFG.DUR_SHORT, CFG.REPLY_GAP,
        function() CD.awaiting = false; MenuRebuild() end, nil, S(j.ch, j.k .. "_rb_ok"))
    env.info(string.format("[CD] readback %s: %s [%s] elev %d ft, %s%s", j.disp, tu:getName(),
        tu:getTypeName(), elev, grid, frTxt))
    QPlay()
end

--- v1.5.5: readback offered in the JTAC's own phase, or later (re-attack) while its
--- target group is alive and the hero is within CFG.RB_NM of it.
local function RbAvail(key)
    local j = JT[key]
    if JcOn() then return false end   -- v1.6.0
    if not CD.worked[key] then return false end
    if CD.phase == j.phase then return true end
    if not OVL_PHASES[CD.phase] or RS.isJ(CD.phase) then return false end
    local p, tp = Player(), TicTgtPos(j)
    return (p and tp and Dist2D(p:getPoint(), tp) <= CFG.RB_NM) and true or false
end

--- v1.5.5: JTAC_Laser spot events -> JTAC radio calls (JTAC-2 / Eyeball 11 only).
local function OnSpot(ev, info)
    if JcOn() then return end   -- v1.6.0
    local key
    for i = #P.order, 1, -1 do if info.jtac == JT[P.order[i]].jtac then key = P.order[i] end end   -- v1.10.0
    if not key then return end
    local j = JT[key]
    if not CD.worked[key] or not OVL_PHASES[CD.phase] or CD.phase == RS.ph[P.order[1]] then return end
    if ev == "OFF" and (info.why == "target group dead" or info.why == "hero not airborne") then return end
    local std = tonumber(info.code) == 1688
    local txt, clip
    if ev == "ON" then
        txt = string.format("[%s] %s, %s, laser on, code %d.", j.cs, CFG.CS, j.disp, info.code)
        clip = std and (j.k .. "_laser_on")
    elseif ev == "MOVE" then
        txt = string.format("[%s] %s, shifting laser to next target, same code.", j.cs, j.disp)
        clip = j.k .. "_laser_shift"
    else
        txt = string.format("[%s] %s, laser off.", j.cs, j.disp)
        clip = j.k .. "_laser_off"
    end
    env.info(string.format("[CD] laser call %s %s (%s)", j.disp, ev, tostring(info.unit)))
    Q(txt, CFG.DUR_SHORT, 0, nil, nil, clip and S(j.ch, clip) or nil)
    QPlay()
end

--- v1.5.6: the JTAC the hero is working right now, or nil.
local function RelKey()
    if RS.isJ(CD.phase) then return RS.key[CD.phase] end   -- v1.10.0
    local p, best, bd = Player(), nil, nil
    if not p then return nil end
    for _, k in ipairs(P.order) do
        if RbAvail(k) then
            local d = Dist2D(p:getPoint(), TicTgtPos(JT[k]))
            if not bd or d < bd then best, bd = k, d end
        end
    end
    return best
end

local function RelFlush(rel)
    local j = JT[rel.key]
    local txt, seq
    if rel.kind == "rifle" then
        txt = string.format("%s, %s, rifle%s.", j.disp, CFG.CS, rel.n > 1 and (", " .. rel.n) or "")
        seq = S(j.ch, "p_rel_" .. j.k, "p_rifle", rel.n > 1 and PD(rel.n) or {})
    else
        txt = string.format("%s, %s, %s.", j.disp, CFG.CS, rel.n > 1 and (rel.n .. " away") or "bombs away")
        seq = S(j.ch, "p_rel_" .. j.k, rel.n > 1 and { PD(rel.n), "p_away" } or "p_bombs_away")
    end
    env.info(string.format("[CD] release call %s: %s x%d", j.disp, rel.kind, rel.n))
    Q("[" .. CFG.CS .. "] " .. txt, CFG.DUR_PILOT, 0, nil, CFG.PILOT_HOLD, seq)
    QPlay()
end

--- v1.5.6: hero S_EVENT_SHOT -> rifle / bombs away on the JTAC button.
local function OnHeroShot(w)
    local d = w:getDesc()
    if type(d) ~= "table" then return end
    local kind
    local tn = tostring(d.typeName or (w.getTypeName and w:getTypeName()) or "")
    if d.category == Weapon.Category.BOMB then
        kind = "bombs"
    elseif d.category == Weapon.Category.MISSILE and d.missileCategory ~= Weapon.MissileCategory.AAM
        and d.missileCategory ~= Weapon.MissileCategory.SAM and not tn:find("AGM_88") then
        kind = "rifle"
    end
    if not kind then return end
    if JcOn() then return end   -- v1.6.0: JTAC_Controller makes the release call
    local key = RelKey()
    if not key then return end
    local now = timer.getTime()
    CD.relCallUntil = now + 10
    local rel = CD.rel
    if rel and not rel.sent and rel.kind == kind and rel.key == key and now - rel.t0 <= CFG.REL_AGG_S then
        rel.n = rel.n + 1
        return
    end
    rel = { kind = kind, key = key, n = 1, t0 = now }
    CD.rel = rel
    timer.scheduleFunction(function() rel.sent = true; RelFlush(rel) end, nil, now + CFG.REL_AGG_S)
end

-- "What is my next call?" — single-line hint per phase
local NEXT = {
    IDLE       = "Launch. CASE III departure on Departure " .. BtnL("DEP") .. ".",
    DEPARTURE  = "On Departure " .. BtnL("DEP") .. ". CASE III: airborne / 2.5 / arcing / established "
                 .. "are automatic, Popeye / on top via F10 > COMMS. CASE I/II: ZIPLIP, check in with "
                 .. "Strike from " .. CFG.DEP_ZIPLIP_NM .. " DME.",
    STRIKE_OUT = "Check in with STRIKE " .. BtnL("STRIKE") .. " (F10).",
    STRIKE_CHK = "Stand by, Strike working Mode 4.",
    OVL_OUT    = "Check in with OVERLORD " .. BtnL("OVL") .. " (F10).",
    ENROUTE    = "Proceed " .. CFG.CP_NAME .. ". OVERLORD tasks you about "
                 .. CFG.JTAC_HANDOFF_NM .. " NM from " .. CFG.CP_NAME .. " (Overlord on COMM2 btn 1).",
    HOLD       = "Hold at " .. CFG.CP_NAME .. ", angels " .. CFG.SCEN.HOLD_ANGELS .. ". OVERLORD will task you (COMM2 btn 1).",
    REFUEL     = "Refuel with TEXACO 11 " .. BtnL("TKR") .. ", TACAN 21Y: use the DCS radio menu (intent to refuel). "
        .. "Then report RTB to OVERLORD (F10).",
    TKR_DONE   = "Report RTB to OVERLORD (F10).",
    RTB        = "RTB outbound zero five zero. OVERLORD hands you to Strike at "
                 .. CFG.RTB_STRIKE_NM .. " NM.",
    STRIKE_IN  = "Check in with STRIKE " .. BtnL("STRIKE") .. " inbound (F10).",
    INBOUND    = "Switch Marshal " .. BtnL("MARSHAL") .. " at " .. CFG.RECOVERY_NM .. " NM.",
    RECOVERY   = "Marshal / AIRBOSS.",
}
for i, k in ipairs(P.order) do   -- v1.10.0 roster (NextText normally answers the OFF phases itself)
    NEXT[RS.ph[k]] = "Work " .. JT[k].disp .. " " .. BtnL(k) .. " (native JTAC menu). After the 9-line: "
        .. "readback via F10 > COMMS."
    NEXT[RS.off[k]] = "Check out with " .. JT[k].disp .. ((i == #P.order) and ", pass INFLTREP to OVERLORD (F10)."
        or ", report to OVERLORD (F10).")
end

-- ══════════════════════════════════════════════════════════════
--  F10 MENU (rebuilt on every phase change)
-- ══════════════════════════════════════════════════════════════
local function PhaseActions()
    local ph, a = CD.phase, {}
    if CD.awaiting then return a end
    if ph == "STRIKE_OUT" then a[#a+1] = { "STRIKE: check in (btn " .. CFG.BTN.STRIKE .. ")", A_StrikeCheckInOut } end
    if ph == "OVL_OUT"    then a[#a+1] = { "OVERLORD: check in (btn " .. CFG.BTN.OVL .. ")", A_OvlCheckIn } end
    if RS.isOff(ph) then   -- v1.8.0: next tasking or INFLTREP, whatever the order
        local k = KeyOfPhase(ph)
        if NextKey() then
            a[#a+1] = { "OVERLORD: off " .. JT[k].disp .. ", ready for retasking", function() A_OvlOffJtac(k) end }
        else
            a[#a+1] = { "OVERLORD: INFLTREP", A_Inflrep }
        end
    end
    if RS.isJ(ph) and LcNeeded(KeyOfPhase(ph)) then   -- v1.8.0 lost comms
        local k = KeyOfPhase(ph)
        a[#a+1] = { "OVERLORD: unable contact " .. JT[k].disp, function() A_UnableContact(k) end }
    end
    if CD.dv and CD.dv.open then                                          -- v1.8.0 C: divert
        local p = Player()
        a[#a+1] = { "OVERLORD: wilco divert (" .. P.jtacs[CD.dv.tic].disp .. ")", A_DivertWilco }
        a[#a+1] = { "OVERLORD: unable divert" .. (p and (", state " .. State(p)) or ""), A_DivertUnable }
    end
    if ph == "ENROUTE" and CD.ar1Int then                                 -- v1.8.0 AR1 tanker gone
        a[#a+1] = { "OVERLORD: continuing mission, no tanker", A_ContNoTkr }
    end
    if ph == "REFUEL" or ph == "TKR_DONE" then
        a[#a+1] = { (ph == "TKR_DONE") and "OVERLORD: RTB" or "OVERLORD: RTB (no tanker)", A_OvlRTB }
    end
    -- v1.7.0 tanker RV (EMCON 2)
    if ph == "ENROUTE" and not CD.tk and not CD.ar1Done and TkAlive() and not CD.tkrLost then   -- v1.8.0
        a[#a+1] = { "OVERLORD: request Texaco (AR1 top-off)", A_TkrRequest }
        if CFG.TKR.AR1_HOLD then a[#a+1] = { "OVERLORD: skip AR1 (no top-off)", A_SkipAR1 } end
    end
    local tk = CD.tk
    if tk and tk.vec and (ph == "ENROUTE" or ph == "REFUEL" or ph == "TKR_DONE") then
        if not tk.init and not tk.rcvd then a[#a+1] = { "TEXACO: RV initial (btn " .. CFG.BTN.TKR .. ")", A_TkrInit } end
        if not tk.judy and not tk.rcvd then a[#a+1] = { "OVERLORD: Judy (tanker visual)", A_Judy } end
        if tk.rcvd and not tk.state then a[#a+1] = { "TEXACO: state", A_TkrState } end
        if tk.ar == 1 and ph == "ENROUTE" then
            a[#a+1] = { tk.rcvd and "OVERLORD: off Texaco, proceeding " .. CFG.CP_NAME
                        or "OVERLORD: off Texaco (cancel AR1)", A_OffTkrAR1 }
        end
        local br = TkBranch()                                    -- v1.7.6
        if br.ovr then a[#a+1] = { "TEXACO: execute overrun", A_Overrun } end
        if br.bkw then a[#a+1] = { "TEXACO: breakaway (emergency)", A_Breakaway } end
        if br.spk then a[#a+1] = { "TEXACO: spokes (drogue damaged)", A_Spokes } end
    end
    if ph == "STRIKE_IN"  then a[#a+1] = { "STRIKE: check in inbound (btn " .. CFG.BTN.STRIKE .. ")", A_StrikeCheckInIn } end
    for _, k in ipairs(P.order) do   -- v1.10.0
        if RbAvail(k) then a[#a+1] = { P.jtacs[k].cs .. ": 9-line readback (4/6/8)", function() A_Readback(k) end } end
    end
    if ph == "ENROUTE" or ph == "HOLD" or RS.key[ph] then
        a[#a+1] = { "OVERLORD: RTB (mission abort)", A_OvlAbort }
    end
    if DIV_PHASES[ph] then a[#a+1] = { "OVERLORD: bingo / divert (nearest field)", A_Divert } end   -- v1.7.3
    if CD.feetPending and OVL_PHASES[ph] then
        a[#a+1] = { "OVERLORD: " .. ((CD.feetPending == "DRY") and "feet dry" or "feet wet"), A_FeetReport }
    end
    return a
end

--- v1.8.0: calls that may step on a busy frequency (emergencies, abort, divert); everything else waits until the
--- frequency is clear, so a menu item never runs ahead of the transmission it answers.
local URGENT = { [A_OvlAbort] = true, [A_Divert] = true, [A_Breakaway] = true, [A_Overrun] = true, [A_Spokes] = true }
local function CommsItems()
    local a = PhaseActions()
    if OVL_PHASES[CD.phase] then a[#a + 1] = { "OVERLORD: request picture", A_Picture } end
    if GateWaiting() then   -- v1.8.4: was not RadioIdle() (the call on the air no longer hides the items)
        local u = {}
        for _, it in ipairs(a) do if URGENT[it[2]] then u[#u + 1] = it end end
        return u
    end
    return a
end

local function InfoItems(ph)
    if ph ~= "MISSION" then return {} end
    return { { "Show: hard deck", function()
        local on = trigger.misc.getUserFlag("200") == 1
        Msg(string.format("[CAS-1] Hard deck %d ft MSL, engagement area — %s",
            CFG.HARD_DECK_FT, on and "IN EFFECT" or "not in effect (transit)"), CFG.DUR_SHORT)
    end } }
end

local function CardData()
    local b = {   -- v1.9.0 from CAS_PACK; v1.10.0 JTAC primaries / alternates per roster key
        { n = P.nets.TOWER.btn,    f = P.nets.TOWER.freq .. " AM",    name = "TOWER / PADDLES" },
        { n = CFG.BTN.DEP,         f = CFG.FREQ.DEP .. " AM",         name = "DEPARTURE" },
        { n = CFG.BTN.STRIKE,      f = CFG.FREQ.STRIKE .. " AM",      name = "STRIKE" },
    }
    for _, k in ipairs(P.order) do
        b[#b + 1] = { n = CFG.BTN[k], f = CFG.FREQ[k] .. " AM", name = P.jtacs[k].cs .. " (" .. P.jtacs[k].group .. ")" }
    end
    b[#b + 1] = { n = CFG.BTN.OVL, f = CFG.FREQ.OVL .. " AM",
                  name = "OVERLORD (COMM2 btn " .. P.nets.OVL.comm2 .. " = " .. CFG.FREQ.OVL .. ")" }
    for _, k in ipairs(P.order) do
        b[#b + 1] = { n = CFG.ALT[k].btn, f = CFG.ALT[k].freq .. " AM", name = P.jtacs[k].cs .. " alternate" }
    end
    for _, x in ipairs({
            { n = CFG.BTN.TKR,         f = CFG.FREQ.TKR .. " AM",         name = "TEXACO 11" },
            { n = P.nets.ARCO.btn,     f = P.nets.ARCO.freq .. " AM",     name = "ARCO 31 (recovery tanker)" },
            { n = P.nets.APPROACH.btn, f = P.nets.APPROACH.freq .. " AM", name = "APPROACH" },
            { n = CFG.BTN.MARSHAL,     f = CFG.FREQ.MARSHAL .. " AM",     name = "MARSHAL" } }) do b[#b + 1] = x end
    return {
        buttons = b,
        lines = {
            "CAS-1 FLOW: DEP → (ZIPLIP " .. CFG.DEP_ZIPLIP_NM .. " DME / CASE III cleared) STRIKE → OVERLORD",
            "→ (CP-20 NM) OVERLORD tasking: JTACs in OVERLORD's order (hold at CP / divert possible)",
            "→ OVERLORD INFLTREP → TEXACO · COMM1 = JTAC / tanker, COMM2 btn 1 = OVERLORD",
            "→ OVERLORD RTB → (90 NM) STRIKE → (50 NM) MARSHAL",
        },
    }
end

local function NextText()
    if CD.phase == "RECOVERY" or CD.phase == "DONE" then return nil end
    if JcOn() and RS.isJ(CD.phase) and not (CD.dv and CD.dv.open)
        and not LcNeeded(KeyOfPhase(CD.phase)) then return nil end   -- v1.6.0
    if CD.phase == "DIVERT" and _G.TRT.FA and _G.TRT.FA.active then return nil end   -- v1.7.5 Field_Arrival
    if CD.phase == "DIVERT" and CD.divert then   -- v1.7.3
        local f
        for _, x in ipairs(CFG.DIVERT.FIELDS) do if x.key == CD.divert.field then f = x end end
        return string.format("Divert %s (%s): tower %s UHF, set manually. Native ATC (F10 > ATC).%s Land, taxi, shut down.",
            CD.divert.name, CD.divert.field, f and f.twr or "?",
            CD.divert.minFuel and " Tell tower: minimum fuel." or "")
    end
    local offK = RS.isOff(CD.phase) and KeyOfPhase(CD.phase) or nil   -- v1.8.0
    local last = offK and not NextKey()
    if CD.tkrLost and (CD.phase == "REFUEL" or last) then   -- v1.7.6
        return last and "Tanker off station. Pass INFLTREP to OVERLORD (F10), then RTB or divert."
            or "Tanker off station: OVERLORD RTB (no tanker) or bingo / divert (F10)."
    end
    if offK then
        local d = JT[offK].disp
        if CD.res[offK] == "cancelled" then return "Mission cancelled. INFLTREP to OVERLORD (F10), or RTB / divert." end
        return last and ("Check out with " .. d .. ", pass INFLTREP to OVERLORD (F10).")
            or ("Check out with " .. d .. ", report to OVERLORD for retasking (F10).")
    end
    if CD.phase == "ENROUTE" and CD.ar1Int then return "No tanker. Tell OVERLORD your intentions (F10): continue, RTB or divert." end
    if CD.dv and CD.dv.open then return "OVERLORD divert: wilco (F10) - you tell " .. P.jtacs[CD.dv.first].disp .. " and switch to " .. P.jtacs[CD.dv.tic].disp .. " - or unable." end
    if RS.isJ(CD.phase) and LcNeeded(KeyOfPhase(CD.phase)) then
        return "No answer from " .. JT[KeyOfPhase(CD.phase)].disp .. ". Report to OVERLORD on COMM2 (F10)."
    end
    return TkrNext() or NEXT[CD.phase]
end

MenuRebuild = function()
    if TRT and TRT.Menu then TRT.Menu.Refresh() end
    return true
end

if TRT and TRT.Menu then
    TRT.Menu.Register("COMMS", "CD", CommsItems, 20)
    TRT.Menu.Register("INFO", "CD", InfoItems, 20)
    TRT.Menu.RegisterCard("CD", CardData, 20)
    TRT.Menu.RegisterNext("CD", NextText)
else
    env.info("[CD] TRT.Menu missing (Menu_Manager.lua not loaded before Comms_Director) -> no F10 calls")
end

-- ══════════════════════════════════════════════════════════════
--  INJECTS (v1.10.0: the pack JTAC with injects = true, RS.injKey; Eyeball 11)
-- ══════════════════════════════════════════════════════════════
local function ArmInjects()
    local IK = RS.injKey
    if not CD.inj.i3 then
        local d3 = 55 + math.random(0, 20)
        timer.scheduleFunction(function()
            local jst = JcOn() and _G.TRT.JC.st and _G.TRT.JC.st[IK]   -- v1.8.0: only a JTAC that is talking
            local talking = not jst or ((jst.phase == "SITREP" or jst.phase == "GAMEPLAN" or jst.phase == "NINE"
                or jst.phase == "READBACK" or jst.phase == "ATTACK") and jst.nocomm == nil)
            if CD.phase == RS.ph[IK] and talking and not CD.inj.i3 and Roll(CFG.PROB_INJ3) then
                CD.inj.i3 = true
                C_Manpads()
            end
        end, nil, timer.getTime() + d3)
    end
    if not CD.inj.i1 and not JcOn() then   -- v1.6.0: JTAC_Controller owns the abort inject
        local d1 = 85 + math.random(0, 60)
        timer.scheduleFunction(function()
            if CD.phase == RS.ph[IK] and not CD.inj.i1 and Roll(CFG.PROB_INJ1) then
                CD.inj.i1 = true
                C_Abort()
                timer.scheduleFunction(function()
                    if CD.phase == RS.ph[IK] or CD.phase == RS.off[IK] then C_Rearm(); QPlay() end
                end, nil, timer.getTime() + 45)
            end
        end, nil, timer.getTime() + d1)
    end
end

-- ══════════════════════════════════════════════════════════════
--  CORRIDOR MONITOR  (RTB / STRIKE_IN / INBOUND)
-- ══════════════════════════════════════════════════════════════
local function CorridorCheck(pPos, cPos)
    if CD.corridorDone then return end
    local dist = Dist2D(pPos, cPos)
    if dist > CFG.CORRIDOR_OUT then return end
    if dist < CFG.CORRIDOR_IN then
        SetFlag(205, 1)
        CD.corridorDone = true
        return
    end
    local delta = math.abs(ADiff(Bearing(cPos, pPos), CFG.CORRIDOR_TRUE))
    if delta > CFG.CORRIDOR_HALF then
        CD.corridorDone = true
        C_CorridorDev()
    end
end

-- ══════════════════════════════════════════════════════════════
--  MUD CALLS (v1.7.9): RWR ground threat, first track per SAM site
-- ══════════════════════════════════════════════════════════════
local MUD = { units = nil, scanT = -1e9, last = -1e9, sites = {}, n = 0 }
CD.mud = MUD

local function MudScan()
    local list = {}
    local ok, groups = pcall(coalition.getGroups, coalition.side.RED, Group.Category.GROUND)
    if not ok or type(groups) ~= "table" then return end
    for _, g in ipairs(groups) do
        local okU, units = pcall(g.getUnits, g)
        if okU and type(units) == "table" then
            for _, u in ipairs(units) do
                local okT, tn = pcall(u.getTypeName, u)
                local ty = okT and CFG.MUD.TYPES[tn]
                if ty then
                    list[#list + 1] = { u = u, type = tn, grp = g:getName(), sym = ty.sym, trNm = ty.trNm }
                end
            end
        end
    end
    if not MUD.units or #list ~= #MUD.units then env.info(string.format("[CD] MUD: %d RED radar units", #list)) end
    MUD.units = list
end

local function MudCall(ch, r, uPos, pPos, how, dNm)
    local brg = string.format("%03d", math.floor(BrgMag(pPos, uPos) + 0.5) % 360)
    local symTok = CFG.MUD.SYM_TOK[r.sym] or PD(r.sym)
    MUD.n = MUD.n + 1
    env.info(string.format("[CD] MUD call #%d: %s (%s, %s) %s, %.1f NM, %s, on %s", MUD.n, r.sym, r.grp, r.type,
        brg, dNm, how, ch))
    local items = { { text = string.format("[%s] %s, mud %s, %s.", CFG.CS, CFG.CS, r.sym, brg),
                      dur = CFG.DUR_PILOT, after = 0.5, hold = CFG.PILOT_HOLD,
                      audio = Voiced(S(ch, "jp_cs", "p_mud", symTok, 0.1, PD(brg))) } }
    if ch == "OVERLORD" then
        items[2] = { text = string.format("[OVERLORD] %s, Overlord, copy.", CFG.CS), dur = CFG.DUR_SHORT,
                     after = CFG.REPLY_GAP, audio = Voiced(S("OVERLORD", "ovl_copy_51")) }
    elseif RS.chKey[ch] then   -- v1.7.11: the JTAC acknowledges too (v1.10.0 any roster JTAC)
        local key = RS.chKey[ch]
        local txt = string.format("%s, copy.", CFG.CS)
        local jc = TRT.JC
        local seq = jc and type(jc.voice) == "function" and (jc.voice("J", key, txt)) or nil
        items[2] = { text = string.format("[%s] %s", JT[key].cs, txt), dur = CFG.DUR_SHORT,
                     after = CFG.REPLY_GAP, audio = seq }
    end
    for i = #items, 1, -1 do table.insert(CD.queue, 1, items[i]) end   -- threat call first
    QPlay()
end

local function MudTick()
    local t = timer.getTime()
    local ok, err = pcall(function()
        if not CFG.MUD.ON then return end
        local p = Player(); if not (p and p:inAir()) then return end
        local ch = CFG.MUD.CH[CD.phase]; if not ch then return end
        if not MUD.units or t - MUD.scanT >= CFG.MUD.RESCAN_S then MUD.scanT = t; MudScan() end
        if not MUD.units then return end
        local pPos, pName = p:getPoint(), p:getName()
        local best
        for _, r in ipairs(MUD.units) do
            local u = r.u
            if u and u:isExist() and u:isActive() then
                local okR, on, tgt = pcall(u.getRadar, u)
                if okR and on then
                    local uPos = u:getPoint()
                    local dNm = Dist2D(uPos, pPos)
                    local how
                    if tgt then
                        local okN, tn = pcall(tgt.getName, tgt)
                        if okN and tn == pName then how = "track" end
                    end
                    if not how and r.trNm and dNm <= r.trNm
                        and land.isVisible({ x = uPos.x, y = uPos.y + CFG.MUD.EYE_M, z = uPos.z }, pPos) then
                        how = "range+LOS"
                    end
                    if how then
                        local s = MUD.sites[r.grp]
                        if not s then
                            s = {}; MUD.sites[r.grp] = s
                            env.info(string.format("[CD] MUD spike: %s %s (%s) %.1f NM, %s", r.sym, r.grp, r.type, dNm, how))
                        end
                        if s.called and s.lastSeen and t - s.lastSeen > CFG.MUD.REARM_S then s.called = nil end
                        s.lastSeen = t
                        if not s.called and (not best or dNm < best.d) then
                            best = { r = r, d = dNm, how = how, pos = uPos, s = s }
                        end
                    end
                end
            end
        end
        if best and t - MUD.last >= CFG.MUD.MIN_GAP_S then
            MUD.last, best.s.called = t, t
            MudCall(ch, best.r, best.pos, pPos, best.how, best.d)
        end
    end)
    if not ok then env.info("[CD] MUD error: " .. tostring(err)) end
    return t + CFG.MUD.TICK
end

-- ══════════════════════════════════════════════════════════════
--  FEET DRY / WET MONITOR
-- ══════════════════════════════════════════════════════════════
local function SurfaceCheck(pPos)
    local ok, st = pcall(land.getSurfaceType, { x = pPos.x, y = pPos.z })
    if not ok or not st then return end
    local s = (st == land.SurfaceType.WATER or st == land.SurfaceType.SHALLOW_WATER) and "WATER" or "LAND"
    if s == CD.surf then CD.surfCand, CD.surfCount = nil, 0; return end
    if s ~= CD.surfCand then CD.surfCand, CD.surfCount = s, 1; return end
    CD.surfCount = CD.surfCount + 1
    if CD.surfCount < 2 then return end              -- debounce: 2 ticks
    local prev = CD.surf
    CD.surf, CD.surfCand, CD.surfCount = s, nil, 0
    if prev and OVL_PHASES[CD.phase] then
        CD.feetPending = (s == "LAND") and "DRY" or "WET"
        MenuRebuild()
    end
end

-- ══════════════════════════════════════════════════════════════
--  PHASE STATE MACHINE
-- ══════════════════════════════════════════════════════════════
SetPhase = function(new)
    if CD.phase == new then return end
    CD.awaiting = false
    CD.dueSince, CD.nextRemind = timer.getTime(), nil
    env.info(string.format("[CD] %s → %s", CD.phase, new))
    CD.phase = new
    if TRT and TRT.Menu then
        local hint = "MISSION"
        if new == "DEPARTURE" then hint = "DEPARTURE"
        elseif new == "IDLE" or new == "RECOVERY" or new == "DONE" then hint = nil end
        TRT.Menu.SetHint("CD", hint)
    end

    if RS.isJ(new) then CD.worked[RS.key[new]] = true end  -- v1.5.5 (v1.10.0 roster)
    if RS.key[new] then
        SetFlag(200, 1)
    else
        SetFlag(200, 0)
    end

    if new == "DEPARTURE" then
        Msg("[CAS-1] All radio calls: F10 > COMMS. \"Show: next call\" lists the next step.", CFG.DUR_HANDOFF)
    elseif RS.isOff(new) then   -- v1.8.0: one handler, whatever the order
        local k = KeyOfPhase(new)
        local j, r = JT[k], CD.res[k]
        local last = not NextKey()
        local txt
        if r == "incomplete" then
            RS.JD(k).tot = RS.JD(k).tot or timer.getAbsTime()
            txt = string.format("[CAS-1] Checked out of %s (Winchester, mission incomplete). %s", j.disp,
                last and "INFLTREP to OVERLORD (F10)." or "Report to OVERLORD (F10).")
            local inc = JcInc(k)
            if inc then env.info(string.format("[CD] %s Winchester: %d destroyed, %d remaining", k, inc.destroyed or 0,
                inc.remaining or 0)) end
        elseif r ~= "cancelled" then
            txt = string.format("[CAS-1] %s tasking complete. Check out, then %s", j.disp,
                last and "INFLTREP to OVERLORD (F10)." or "report to OVERLORD (F10).")
        end
        if txt then   -- v1.8.0: shown when the frequency is clear (after the JTAC's BDA / Winchester exchange)
            local t0 = timer.getTime()
            timer.scheduleFunction(function(_, tt)
                if RadioIdle() or tt - t0 > 60 then Msg(txt, CFG.DUR_SHORT); return nil end
                return tt + 1
            end, nil, t0 + (JcOn() and 3 or 0.1))
        end
        if r ~= "incomplete" and r ~= "cancelled" then TicBDA(k) end   -- v1.5.4
    elseif new == "DIVERT" and CD.divert then   -- v1.7.3
        Msg("[CAS-1] " .. (NextText() or "Divert."), CFG.DUR_HANDOFF)
    elseif new == "RECOVERY" then
        env.info("[CD] RECOVERY phase — AIRBOSS active, CD standing down after Marshal hand-off.")
    end

    MenuRebuild()
end

local function GroupAlive(name)
    local g = Group.getByName(name)
    if not g or not g:isExist() then return false end
    for _, u in ipairs(g:getUnits() or {}) do
        if u and u:isExist() and u:getLife() > 0 then return true end
    end
    return false
end

--- Centroid + initial size of a live group (for INFLTREP / inject arming).
local function Snapshot(name, rec)
    local g = Group.getByName(name)
    if not g then return end
    local sx, sz, n = 0, 0, 0
    for _, u in ipairs(g:getUnits() or {}) do
        if u and u:isExist() then
            local p = u:getPoint(); sx, sz, n = sx + p.x, sz + p.z, n + 1
        end
    end
    if n > 0 then rec.pos = { x = sx / n, y = 0, z = sz / n } end
    local ok, sz0 = pcall(function() return g:getInitialSize() end)
    rec.size = (ok and sz0) or n
end

local function TrackTargets()
    local jc = TRT.JC   -- v1.9.2 objective destroyed = target dead
    local function ObjDone(k) return jc and jc.st and jc.st[k] and jc.st[k].objDone end
    for i, k in ipairs(P.order) do   -- v1.10.0 roster (aliases deadJ1 / seenJ1 ... kept for other modules)
        if not CD.dead[k] then
            local g = JT[k].tgt
            if GroupAlive(g) and not ObjDone(k) then
                if not CD.seen[k] then CD.seen[k] = true; CD["seen" .. k] = true; Snapshot(g, CD.jd[k]) end
            elseif CD.seen[k] then
                CD.dead[k] = true; CD["dead" .. k] = true; CD.jd[k].tot = timer.getAbsTime()
                env.info("[CD] JTAC-" .. i .. " target group destroyed: " .. g)
            end
        end
    end
end

local function EvalPhase(pUnit, cUnit)
    local pPos = pUnit:getPoint()
    local cPos = cUnit and cUnit:getPoint()
    local ph   = CD.phase

    if ph == "IDLE" then
        local v = pUnit:getVelocity()
        local spd = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        if pPos.y > CFG.DEP_ALT_M and spd > CFG.DEP_SPD_MS then SetPhase("DEPARTURE") end

    elseif ph == "DEPARTURE" then
        local T = _G.TRT
        if T and T.CV and (T.CV.depActive or T.CV_DEP_CLEARED) then
            -- CASE III: CV_Comms runs the Departure dialogue ("cleared to switch")
            if T.CV_DEP_CLEARED then SetPhase("STRIKE_OUT") end
        elseif T and T.CV then
            -- CASE I/II: ZIPLIP departure, no Departure transmission
            if cPos and Dist2D(pPos, cPos) >= CFG.DEP_ZIPLIP_NM then
                CD.depZiplip = true
                Msg(string.format("[CAS-1] ZIPLIP departure. Check in with STRIKE %s (F10 > COMMS).",
                    BtnL("STRIKE")), CFG.DUR_HANDOFF)
                SetPhase("STRIKE_OUT")
            end
        elseif cPos and Dist2D(pPos, cPos) >= CFG.DEP_HANDOFF_NM then
            C_DepSwitchStrike(); QPlay()
            SetPhase("STRIKE_OUT")
        end

    elseif ph == "ENROUTE" then
        if Dist2D(pPos, CFG.CP_POS) <= CFG.JTAC_HANDOFF_NM and not CD.tk and not CD.awaiting and not Ar1Pending()
            and not CD.ar1Int and RadioIdle() then  -- v1.7.0/1: not during or before AR1; v1.8.0 intentions given
            ScenPick()
            local k = NextKey()
            if CD.scen.kind == "B" and k then
                C_OvlHold()
            elseif k then
                C_OvlContact(k, pUnit, "cp")
            else
                env.info("[CD] ENROUTE: nothing left to task")
                SetPhase(RS.off[CD.order[#CD.order]])
            end
            QPlay()
        end

    elseif RS.isJ(ph) then   -- v1.8.0: either JTAC, in any order (v1.10.0 roster)
        local k = KeyOfPhase(ph)
        if k == RS.injKey and not CD.injArmed then
            local tgt = CD.jd[k].pos or JT[k].pos
            if tgt and Dist2D(pPos, tgt) <= CFG.INJ_ARM_NM then CD.injArmed = true; ArmInjects() end
        end
        if not CD.res[k] and (TargetDead(k) or JcTerm(k)) then
            FinishTask(k)
            SetPhase(RS.off[k])
        end

    elseif ph == "REFUEL" then
        if CD.refuelDone then SetPhase("TKR_DONE") end   -- v1.7.0: fallback; normally "clear to leave"
    end

    -- Inbound: OVERLORD → Strike (also catches a skipped INFLTREP / tanker / RTB call)
    ph = CD.phase
    if ((RS.isOff(ph) and not NextKey()) or ph == "REFUEL" or ph == "TKR_DONE" or ph == "RTB")
        and cPos and Dist2D(pPos, cPos) <= CFG.RTB_STRIKE_NM then
        C_OvlSwitchStrike(pUnit); QPlay()
        SetPhase("STRIKE_IN")
    end

    ph = CD.phase
    if (ph == "RTB" or ph == "STRIKE_IN" or ph == "INBOUND") and cPos then
        CorridorCheck(pPos, cPos)
        local d = Dist2D(pPos, cPos)
        -- v1.5.2: hand to Marshal only after the Strike check-in (INBOUND); STRIKE_IN /
        -- RTB only as a late fallback, so the Overlord -> Strike call is not cleared
        if (ph == "INBOUND" and d <= CFG.RECOVERY_NM)
            or (ph ~= "INBOUND" and d <= CFG.RECOVERY_FORCE_NM) then
            QClear()
            local brgT = Bearing(cPos, pPos)                                     -- v1.7.11
            if math.abs(ADiff(brgT, CFG.CORRIDOR_TRUE)) > CFG.CORRIDOR_HALF then
                C_CorridorMz(math.floor(brgT - CFG.MAGVAR + 0.5) % 360)
            end
            C_StrikeSwitchMarshal(); QPlay()
            SetPhase("RECOVERY")
        end
    end
end

-- ══════════════════════════════════════════════════════════════
--  THREAT / CAP MONITORS + CHAT PUMP  (v1.5.0)
-- ══════════════════════════════════════════════════════════════
local function ThreatMonitor(pPos)
    if not OVL_PHASES[CD.phase] then return end
    for _, b in ipairs(Bandits(pPos, CFG.THREAT_NM)) do
        local r = CD.threat[b.name] or {}
        CD.threat[b.name] = r
        if b.d <= CFG.THREAT_CLOSE_NM and not r.close then
            r.close, r.far = true, true
            ThreatCall(b.name, true)
        elseif not r.far then
            local asp = Aspect(b.unit, pPos)
            if asp == "HOT" or asp == "FLANK" then r.far = true; ThreatCall(b.name, false) end
        end
    end
end

local function CapMonitor()
    for _, c in ipairs(CFG.CAP) do
        local st = CD.cap[c.key] or { state = "off", clean = 0 }
        CD.cap[c.key] = st
        local g = Group.getByName(c.group)
        local lead = (g and g:isExist()) and AirLead(g, false) or nil
        if lead then
            local lp = lead:getPoint()
            local near = #Bandits(lp, CFG.CAP_COMMIT_NM) > 0
            if near and st.state ~= "commit" then
                st.state, st.clean = "commit", 0
                CapCommit(c)
            elseif st.state == "commit" then
                if #Bandits(lp, CFG.CAP_COMMIT_NM + 10) > 0 then
                    st.clean = 0
                else
                    st.clean = st.clean + 1
                    if st.clean >= CFG.CAP_CLEAN_TICKS then st.state = "station"; CapStation(c) end
                end
            elseif st.state == "off" then
                st.state = "station"
                env.info("[CD] " .. c.group .. " airborne, no bandit inside " .. CFG.CAP_COMMIT_NM .. " NM")
            end
        end
    end
end

local function ChatPump(now)
    if CD.qPlaying or #CD.queue > 0 then return end
    local pb = _G.TRT and _G.TRT.PB                      -- v1.7.8
    if pb and type(pb.busyUntil) == "number" and timer.getTime() < pb.busyUntil then return end
    while #CD.chat > 0 do
        local it = table.remove(CD.chat, 1)
        if now - it.t0 <= CFG.CHAT_TTL then
            local ok, err = pcall(it.fn)
            if not ok then env.info("[CD] chatter error: " .. tostring(err)) end
            if #CD.queue > 0 then QPlay(); return end
        end
    end
end

local function CapGroupCfg(gname)
    for _, c in ipairs(CFG.CAP) do if c.group == gname then return c end end
end

local CD_EVENTS = {}
function CD_EVENTS:onEvent(e)
    if e and e.id == world.event.S_EVENT_SHOT and e.weapon and e.initiator then   -- v1.5.6
        local okS, err = pcall(function()
            if e.initiator:getName() == CFG.PLAYER_UNIT then OnHeroShot(e.weapon) end
        end)
        if not okS then env.info("[CD] shot handler error: " .. tostring(err)) end
        return
    end
    if e and e.id == world.event.S_EVENT_LAND and e.initiator and CD.phase == "DIVERT" then   -- v1.7.3
        local okL, nm = pcall(function() return e.initiator:getName() end)
        if okL and nm == CFG.PLAYER_UNIT then
            local pn = "?"
            pcall(function() pn = e.place and e.place:getName() or "?" end)
            env.info("[CD] divert landing at " .. tostring(pn))
            SetPhase("DONE")
        end
        return
    end
    if not e or e.id ~= world.event.S_EVENT_KILL then return end
    local ok, err = pcall(function()
        local k, v = e.initiator, e.target
        if not (k and v and k.getGroup and v.getCoalition and v.getDesc) then return end
        if v:getCoalition() ~= coalition.side.RED then return end
        local d = v:getDesc()
        if not d or d.category ~= Unit.Category.AIRPLANE then return end
        local g = k:getGroup(); if not g then return end
        local c = CapGroupCfg(g:getName()); if not c then return end
        env.info(string.format("[CD] %s splash: %s", c.group, tostring(v:getName())))
        CapSplash(c)
    end)
    if not ok then env.info("[CD] kill handler error: " .. tostring(err)) end
end

-- ══════════════════════════════════════════════════════════════
--  MAIN TICK
-- ══════════════════════════════════════════════════════════════
-- Pending pilot call → repeated controller call (+ F10 hint)
local function OffRemind()
    if NextKey() or (CD.tkrLost) then return string.format("[OVERLORD] %s, Overlord. Say status.", CFG.CS), "ovl_say_status" end
    return string.format("[OVERLORD] %s, Overlord. Say status, advise when ready for tanker.", CFG.CS), "ovl_say_status_tkr"
end
local REMIND = {
    STRIKE_OUT = function()
        if CD.depZiplip then
            return string.format("[CAS-1] ZIPLIP departure — check in with STRIKE %s (F10 > COMMS).", BtnL("STRIKE")), nil
        end
        return string.format("[DEPARTURE] %s, Departure. Contact Strike, %s, how copy?", CFG.CS, Btn("STRIKE")), "dep_contact_strike"
    end,
    OVL_OUT    = function() return string.format("[STRIKE] %s, Strike. Contact Overlord, %s.", CFG.CS, Btn("OVL")), "str_contact_ovl" end,
    ENROUTE    = function()                            -- v1.8.0: AR1 tanker gone, intentions pending
        if CD.ar1Int then return string.format("[OVERLORD] %s, Overlord. Say intentions.", CFG.CS), "ovl_say_int" end
    end,
    -- v1.6.5: no REFUEL reminder (the pilot is on the tanker, native DCS comms)
    TKR_DONE   = function() return string.format("[OVERLORD] %s, Overlord. Say intentions.", CFG.CS), "ovl_say_int" end,
    STRIKE_IN  = function() return string.format("[OVERLORD] %s, Overlord. Contact Strike, %s, how copy?", CFG.CS, Btn("STRIKE")), "ovl_contact_strike" end,
}
for _, ph in pairs(RS.off) do REMIND[ph] = OffRemind end   -- v1.8.0: by what is left, not by the JTAC (v1.10.0 roster)

Remind = function(now)
    local f = REMIND[CD.phase]
    if not f or CD.awaiting or not CD.dueSince then return end
    if not CD.nextRemind then CD.nextRemind = CD.dueSince + CFG.REMIND_FIRST end
    if now < CD.nextRemind or CD.qPlaying then return end
    CD.nextRemind = now + CFG.REMIND_EVERY
    local txt, audio = f(); if not txt then return end
    if not audio then Msg(txt, CFG.DUR_HANDOFF); return end      -- v1.4.6: hint already says it
    Q(txt, CFG.DUR_HANDOFF, 0, nil, nil, audio)
    QPlay()
    Msg("[CAS-1] F10 > COMMS - " .. (NextText() or NEXT[CD.phase] or ""), CFG.DUR_HANDOFF)
end

-- v1.6.1: air start tag from the hero group's first route point name ("AIRSTART J2")
local function AirStartTag()
    local tag
    pcall(function()
        for _, side in pairs(env.mission.coalition or {}) do
            for _, c in pairs(side.country or {}) do
                for _, g in pairs((c.plane and c.plane.group) or {}) do
                    for _, u in pairs(g.units or {}) do
                        if u.name == CFG.PLAYER_UNIT then
                            local pt = g.route and g.route.points and g.route.points[1]
                            local nm = pt and pt.name
                            if nm and env.getValueDictByKey then nm = env.getValueDictByKey(nm) or nm end
                            tag = nm and tostring(nm):upper():match("^AIRSTART%s*(J%d)")
                            return
                        end
                    end
                end
            end
        end
    end)
    return tag
end

--- v1.6.1: first tick with the hero in the world: skip the carrier legs on an air start.
local function AirStartCheck(p, c)
    CD.airChecked = true
    local pos, v = p:getPoint(), p:getVelocity()
    local okH, gh = pcall(land.getHeight, { x = pos.x, y = pos.z })
    local agl = pos.y - ((okH and gh) or 0)
    local spd = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    local far = (not c) or Dist2D(pos, c:getPoint()) > CFG.AIRSTART.NM
    if not (agl > CFG.AIRSTART.ALT_AGL_M and spd > CFG.AIRSTART.SPD_MS and far) then return end
    local key = AirStartTag() or CD.tasked[1]
    CD.airStart = key
    env.info(string.format("[CD] AIR START detected (%s): AGL %.0f m, %.0f m/s", key, agl, spd))
    SetFlag(200, 0)
    if key == CD.tasked[2] then   -- v1.10.0: "AIRSTART <slot-2 key>" -> straight to the second tasking
        local f = CD.tasked[1]
        CD.worked[f] = true
        CD.res[f], CD.cur = "skipped", key   -- v1.8.0
        SetPhase(RS.ph[key])
        local tic = TicPick() == key
        local d = P.jtacs[key].disp
        if P.xcas then CD.msnGiven = { [key] = true } end   -- v1.11.0
        Q(string.format("[OVERLORD] %s, Overlord. AIR START: check-in assumed. %s %s. %s%s Contact " .. d .. ", %s.",
            CFG.CS, CFG.CP_NAME, BrgRng(pos, CFG.CP_POS), P.xcas and ("Mission " .. RS.MSN[key] .. ". ") or "",
            tic and d .. " reports TROOPS IN CONTACT, priority immediate." or d .. " is on station.",
            Btn(key)), CFG.DUR_LONG, 2)
        if tic then TicHandoff(key) else Ack("OVERLORD", false, CFG.BTN[key]) end
        QPlay()
    else
        TicPick()   -- as at the OVERLORD check-in: JTAC_Controller spawns Bravo 2-1 from CD.tic
        SetPhase("ENROUTE")
        Q(string.format("[OVERLORD] %s, Overlord. AIR START: check-in assumed. Proceed %s, %s, "
            .. "hard deck two-zero thousand. OVERLORD tasking %d NM from %s.", CFG.CS, CFG.CP_NAME,
            BrgRng(pos, CFG.CP_POS), CFG.JTAC_HANDOFF_NM, CFG.CP_NAME), CFG.DUR_LONG, 2)
        if CD.scen and CD.scen.noShow then C_NoShow() end   -- v1.8.0
        QPlay()
    end
end

--- v1.8.4: a JTAC_Controller tasking that ends (BDA queued / Winchester / terminated) moves the phase to J1_OFF /
--- J2_OFF at once instead of on the next 5 s tick, so "OVERLORD: off <JTAC>" opens while the BDA is on the air.
local function HookJc()
    local jc = _G.TRT and _G.TRT.JC
    if CD.jcHooked or not (jc and jc.on) then return end
    CD.jcHooked = true
    jc.on(function(ev)
        if ev ~= "DONE" and ev ~= "TERMINATED" then return end
        timer.scheduleFunction(function()   -- after JTAC_Controller has set its own phase
            local p = Player()
            if not p or CD.phase == "DONE" or CD.phase == "RECOVERY" then return end
            local ok, err = pcall(function() TrackTargets(); EvalPhase(p, Carrier()) end)
            if not ok then env.info("[CD] JC hook error: " .. tostring(err)) end
        end, nil, timer.getTime() + 0.2)
    end)
end

local function CD_Tick(_, t)
    if CD.phase == "DONE" or CD.phase == "RECOVERY" then return end
    HookJc()   -- v1.8.4
    TrackTargets()
    local p = Player()
    if not p then return t + CFG.TICK end
    if not CD.airChecked and CD.phase == "IDLE" then AirStartCheck(p, Carrier()) end   -- v1.6.1
    EvalPhase(p, Carrier())
    local okK, errK = pcall(TkrTick, p)   -- v1.7.0
    if okK then okK, errK = pcall(TkBranchTick, p) end   -- v1.7.6
    if okK then okK, errK = pcall(TkrLostTick) end        -- v1.7.6
    if not okK then env.info("[CD] tanker error: " .. tostring(errK)) end
    Remind(t)
    CapMonitor()
    ThreatMonitor(p:getPoint())
    ChatPump(t)
    local okT, errT = pcall(TicTick, t, p)   -- v1.5.4
    if not okT then env.info("[CD] TIC error: " .. tostring(errT)) end
    local okH, errH = pcall(HoldTick, p)     -- v1.8.0 (DivertTick has its own 1 s timer)
    if not okH then env.info("[CD] tasking error: " .. tostring(errH)) end
    if OVL_PHASES[CD.phase] or CD.phase == "DEPARTURE" then SurfaceCheck(p:getPoint()) end
    return t + CFG.TICK
end

-- ══════════════════════════════════════════════════════════════
--  INIT
-- ══════════════════════════════════════════════════════════════
local function CD_Init()
    pcall(math.randomseed, timer.getAbsTime())

    -- Core_Scoring refuel-complete callback (TRT.onRefuelComplete); retry until TRT exists.
    local function HookRefuel(_, tm)
        if _G.TRT then
            local prev = _G.TRT.onRefuelComplete
            _G.TRT.onRefuelComplete = function(name, ...)
                if prev then pcall(prev, name, ...) end
                if name == CFG.PLAYER_UNIT then
                    CD.refuelDone = true
                    env.info("[CD] refuel complete reported for " .. tostring(name))
                end
            end
            env.info("[CD] hooked TRT.onRefuelComplete")
            return nil
        end
        return tm + 2
    end
    timer.scheduleFunction(HookRefuel, nil, timer.getTime() + 2)

    -- v1.5.5: JTAC_Laser spot events (any load order; give up after 60 s)
    local function HookSpot(_, tm)
        local jl = _G.TRT and _G.TRT.JL
        if jl and jl.onSpot then
            jl.onSpot(OnSpot); env.info("[CD] hooked TRT.JL.onSpot"); return nil
        end
        if tm > 60 then env.info("[CD] JTAC_Laser v1.1+ not loaded -> no laser calls"); return nil end
        return tm + 2
    end
    timer.scheduleFunction(HookSpot, nil, timer.getTime() + 1)

    SetFlag(200, 0)
    world.addEventHandler(CD_EVENTS)
    timer.scheduleFunction(CD_Tick, nil, timer.getTime() + CFG.TICK)
    timer.scheduleFunction(MudTick, nil, timer.getTime() + 10)   -- v1.7.9
    env.info("[CD] Comms_Director v1.11.0 online — CAS-1 Syria (pack " .. tostring(P.version) .. ")")
end

CD_Init()
