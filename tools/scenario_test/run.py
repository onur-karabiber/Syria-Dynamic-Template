# scenario_test/run.py | v1.9.0
# v1.9.0 (P4): cases xcas_* (flag 226: check-in XCAS, mission number at tasking + pilot readback, digit chains in
#         off / lost comms / INFLTREP, divert for any pair) and rpair_* (flag 225: random tasked pair, equal odds).
# v1.8.0: JTAC roster P3: world has AXEMAN 11 (JTAC-8, BASE YE55 insurgents) and DARKNIGHT 11 (ground team JTAC-4,
#         MQ-9 FAC-1-1 designator, SAM BV53 + pool B / C); the bot takes the tasked pair from CAS_PACK.tasked
#         (Tasking_Pick >= v1.3.0) and reads JTAC menu items by the pack call signs. Cases tasked_J3J4_* (A / B / C).
#         ROSTER2=1 (environment): every case on the old two-JTAC pack (regression against older radio logs).
# v1.7.0: opts pack_lua = Lua run right after CAS_Pack.lua (roster tests, Comms_Director v1.10.0 / JTAC_Controller
#         v0.15.1): cases roster_J3_* replace J2 by a key J3 (same groups and voice) -> phases JTAC1 / J1_OFF / JTAC2 /
#         J3_OFF, the scenarios on the slots.
# v1.6.0: opts passes=True: a cleared attack is a real pass - the hero releases the weapon the JTAC asked for (st.ord) at
#         the aim unit, only that unit dies at the impact, the hero's ammo goes down (JTAC_Controller v0.15.0 effects-based
#         tasking: objective, aftermath via flag 222). Cases aft_withdraw / aft_threat / aft_ignore.
# v1.5.1: case audit (flag 221: site check + dry JTAC post search for every pool entry).
# v1.5.0: target pool (Tasking_Pick v1.0.0): the four pool groups exist late-activated next to set A; Tasking_Pick.lua
#         runs after the pack (env.mission built from the mock groups); kills follow the picked target group; cases
#         pick_B / pick_C force entries B / C with flags 217 / 219.
# v1.4.0: loads scripts/CAS_Pack.lua first (Comms_Director >= v1.9.0 / JTAC_Controller >= v0.14.0 need the pack).
# v1.3.0: gates follow JTAC_Controller v0.13.2 / Comms_Director v1.8.4 (items open when the call they answer
#         STARTS): a JTAC dialogue item may not be offered while that JTAC's non-ack call is still WAITING in the
#         queue; a non-urgent COMMS item not while CD.gateWaiting(). New check: no pilot reply is transmitted
#         before the JTAC call it answers has started (radio order).
# v1.2.0: opts "spoof": comply | auth | release | wait (JTAC_Controller >= v0.13.0, ME flag 216 forces the spoofed
#         abort on Pointer 11): the bot answers the spoof that way (release = a synthetic S_EVENT_SHOT GBU-12);
#         Pointer's targets are not "killed" until the spoof has been answered. opts "abort_auth": the bot
#         challenges a real abort (AUTHENTICATE) before ABORTING.
# v1.1.0: opts "abort": (key, ack_delay_s) - the first IN of that JTAC is flown outside the FAH (-> ABORT); the bot
#         presses ABORTING ack_delay_s after the end of the abort call (JTAC_Controller >= v0.12.0).
# Headless walk of the CAS-1 radio flow through every tasking scenario (Comms_Director >= v1.8.0,
# JTAC_Controller >= v0.11.0), with the real Menu_Manager / Comms_Director / JTAC_Controller in a DCS mock
# (dcs_mock.lua, lupa / Lua 5.4). A bot pilot presses the F10 items as soon as they appear (adversarial: it never
# waits for the radio), moves the hero, "kills" targets after CLEARED HOT, and checks:
#   * no dead end (no progress for DEAD_S), no Lua error, the flow reaches STRIKE_IN (RTB)
#   * radio gate: a JTAC dialogue item is never offered while that JTAC's previous call is still queued / on air;
#     a non-urgent Comms_Director item never while the frequency is busy
#   * per-scenario expectations (order of the JTAC phases, results, key radio lines)
#   python tools/scenario_test/run.py            all cases
#   python tools/scenario_test/run.py C_accept   one case (name prefix), -v = print the radio log
import os
import re
import sys
import lupa.lua54 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPTS = os.path.join(REPO, "scripts")

NM = 1852.0
CVN = (0.0, -420000.0)
CP = (73640.0, -39914.0)
T1 = (93640.0, -19914.0)          # Pointer 11 targets (SAM BV51 (SA-13)-1)
T2 = (59271.0, -1176.0)           # Eyeball 11 targets (SAM YE53 (SA-8)-1), Comms_Director CFG.JTAC2_POS
T3 = (71867.0, -8368.0)           # v1.8.0 Axeman 11 targets (BASE YE55 (Insurgent)-1)
T4 = (53640.0, -19914.0)          # v1.8.0 Darknight 11 targets (SAM BV53 (SA-13)-1), mock position
DEAD_S = 420
POOL = [("CAS J1-B (Armor)-1", (T1[0] + 900, T1[1] + 400), ["T-72B", "BMP-1"]),
        ("CAS J1-C (Battery)-1", (T1[0] + 1500, T1[1] + 1500), ["SAU Gvozdika", "SAU Gvozdika"]),
        ("CAS J2-B (Armor)-1", (T2[0] + 900, T2[1] + 200), ["T-72B", "T-72B", "T-72B", "BMP-1"]),
        ("CAS J2-C (Battery)-1", (T2[0] + 1500, T2[1] + 1200), ["SAU Gvozdika"] * 4),
        ("CAS J4-B (Armor)-1", (T4[0] + 900, T4[1] + 400), ["T-72B", "BMP-1"]),          # v1.8.0
        ("CAS J4-C (Trucks)-1", (T4[0] + 1300, T4[1] + 1300), ["Ural-375", "Ural-375"])]
MAGVAR = 5          # JTAC_Controller CFG.MAGVAR (east)
MAX_S = 3 * 3600

DIALOG = ("CHECKIN", "SILENT", "SITREP", "GAMEPLAN", "NINE", "READBACK")


class Run:
    def __init__(self, name, flags, opts):
        self.name, self.flags, self.opts = name, flags, opts
        self.rt = lupa.LuaRuntime(unpack_returned_tuples=True)
        lua = self.rt
        # DCS: math.randomseed is not in the mission sandbox; seed here, then hide it like DCS does
        lua.execute("math.randomseed(%d); math.randomseed = nil" % opts.get("seed", 7))
        lua.execute(open(os.path.join(HERE, "dcs_mock.lua"), encoding="utf-8").read())
        self.M = lua.globals().MOCK
        self.fail = []
        self.presses = []
        self.attack = {}
        self.setup_world()
        for f, v in flags.items():
            lua.eval("function(f, v) MOCK.flags[f] = v end")(str(f), v)
        lua.execute("TRT = TRT or {}; _G.TRT = TRT; TRT.PLAYER_NAME = 'Player_01'; "
                    "TRT.CV_AUDIO = setmetatable({}, { __index = function() return { len = 0.4 } end }); "
                    "TRT.addScore = function(d, r, c) env.info(string.format('[SCORE] %+d %s', d, tostring(r))) end")
        lua.execute("MOCK.missionFromGroups()")                                        # v1.5.0
        for f in ("CAS_Pack.lua", "Tasking_Pick.lua", "Menu_Manager.lua", "Comms_Director.lua", "JTAC_Controller.lua"):
            if f == "Tasking_Pick.lua" and opts.get("pack_lua"):                         # v1.7.0
                lua.execute(opts["pack_lua"])
            elif f == "Tasking_Pick.lua" and os.environ.get("ROSTER2"):                  # v1.8.0 regression mode:
                lua.execute("CAS_PACK.jtacs.J3, CAS_PACK.jtacs.J4 = nil, nil; "          # the 2-JTAC pack of
                            "CAS_PACK.order = { 'J1', 'J2' }")                            # v1.2.x
            src = open(os.path.join(SCRIPTS, f), encoding="utf-8").read()
            ok = lua.eval("function(s, n) local f, e = load(s, '@' .. n); if not f then return e end "
                          "local ok, err = pcall(f); return ok and 'OK' or tostring(err) end")(src, f)
            if ok != "OK":
                self.fail.append("load %s: %s" % (f, ok))
        self.TRT = lua.globals().TRT
        P = lua.globals().CAS_PACK                                                   # v1.7.0 roster keys
        o = P.tasked or P.order                                                       # v1.8.0 the tasked pair
        self.K1, self.K2 = str(o[1]), str(o[2])
        self.CS = {str(P.jtacs[k].cs): str(k) for k in P.order.values()}            # "AXEMAN 11" -> J3
        self.TPOS = {"J1": T1, "J2": T2, "J3": T3, "J4": T4}

    # ── world ────────────────────────────────────────────────────────────────
    def setup_world(self):
        add = self.rt.eval("function(n, c, cat, units) return MOCK.addGroup(n, c, cat, units) end")
        T = self.rt.table_from

        def units(lst):
            return T([T(u) for u in lst])
        sx, sz = self.opts.get("start", (CVN[0] + 30 * NM, CVN[1] + 30 * NM))
        hero = add("CAS-1", 2, 0, units([{"name": "Player_01", "type": "FA-18C_hornet", "x": sx, "z": sz,
                                          "y": 6000}]))
        u = hero.units[1]
        u.air, u.player, u.fuel = True, "Onur", self.opts.get("fuel", 0.85)
        u.v = T({"x": 200, "y": 0, "z": 0})
        ammo = []
        if not self.opts.get("no_ammo"):
            ammo = [
                {"count": 2, "desc": {"category": 1, "missileCategory": 6, "typeName": "AGM_65E", "displayName": "AGM-65E"}},
                {"count": 4, "desc": {"category": 3, "typeName": "GBU_12", "displayName": "GBU-12"}},
                {"count": 570, "desc": {"category": 0, "typeName": "M61", "displayName": "M61"}},
            ]
        u.ammo = T([T({"count": a["count"], "desc": T(a["desc"])}) for a in ammo])
        self.hero = u
        add("CVN", 2, 3, units([{"name": "CVN", "type": "CVN_73", "x": CVN[0], "z": CVN[1]}]))
        if not self.opts.get("no_tanker"):
            tk = add("TANKER-1", 2, 0, units([{"name": "TANKER-1-1", "type": "KC130", "x": CP[0] + 40 * NM,
                                               "z": CP[1] - 10 * NM, "y": 4500}]))
            tk.units[1].air = True
        add("SAM BV51 (SA-13)-1", 1, 2, units([{"name": "BV51-1", "type": "Strela-10M3", "x": T1[0], "z": T1[1]},
                                              {"name": "BV51-2", "type": "T-55", "x": T1[0] + 50, "z": T1[1]}]))
        add("SAM YE53 (SA-8)-1", 1, 2, units([{"name": "YE53-1", "type": "Osa 9A33 ln", "x": T2[0], "z": T2[1]},
                                             {"name": "YE53-2", "type": "Osa 9A33 ln", "x": T2[0] + 60, "z": T2[1]},
                                             {"name": "YE53-3", "type": "BTR-80", "x": T2[0], "z": T2[1] + 60},
                                             {"name": "YE53-4", "type": "T-72B", "x": T2[0] - 60, "z": T2[1]}]))
        # v1.5.0 target pool: late-activated groups (Tasking_Pick activates the picked one, removes set A otherwise)
        for name, (cx, cz), types in POOL:
            g = add(name, 1, 2, units([{"name": "%s-%d" % (name, i), "type": t, "x": cx + 60 * i, "z": cz}
                                       for i, t in enumerate(types, 1)]))
            g.inactive = True
        add("JTAC-1", 2, 2, units([{"name": "JTAC-1-1", "type": "Soldier M4", "x": T1[0] - 3000, "z": T1[1] - 1000}]))
        add("JTAC-2", 2, 2, units([{"name": "JTAC-2-1", "type": "Soldier M4", "x": T2[0] - 2500, "z": T2[1] - 1000}]))
        # v1.8.0 roster P3
        add("BASE YE55 (Insurgent)-1", 1, 2, units(
            [{"name": "YE55-%d" % i, "type": t, "x": T3[0] + 15 * i, "z": T3[1] + 10 * (i % 3)}
             for i, t in enumerate(["HL_DSHK", "Soldier AK", "Soldier AK", "Soldier RPG", "Soldier AK", "HL_DSHK",
                                    "Soldier AK", "HL_DSHK"], 1)]))
        add("SAM BV53 (SA-13)-1", 1, 2, units([{"name": "BV53-1", "type": "T-55", "x": T4[0], "z": T4[1]},
                                              {"name": "BV53-2", "type": "Strela-10M3", "x": T4[0] - 300, "z": T4[1]}]))
        add("JTAC-8", 2, 2, units([{"name": "JTAC-8-1", "type": "M1134 Stryker ATGM", "x": T3[0] - 450, "z": T3[1] - 160}]))
        add("JTAC-4", 2, 2, units([{"name": "JTAC-4-1", "type": "M1134 Stryker ATGM", "x": T4[0] - 3200, "z": T4[1] - 3800}]))
        fac = add("FAC-1", 2, 0, units([{"name": "FAC-1-1", "type": "MQ-9 Reaper", "x": T4[0] + 6900, "z": T4[1] - 2500,
                                         "y": 7010}]))
        fac.units[1].air = True

    # ── helpers ──────────────────────────────────────────────────────────────
    def t(self):
        return self.M.t

    def cd(self):
        return self.TRT.CD

    def jc(self):
        return self.TRT.JC

    def menu(self):
        cur = self.TRT.Menu.cur
        items = cur["COMMS"] if cur else None
        out = []
        if items:
            for i in range(1, len(items) + 1):
                out.append(items[i])
        return out

    def label(self, it):
        return str(it[1])

    def log_has(self, pat):
        rx = re.compile(pat)
        return any(rx.search(str(self.M.log[i])) for i in range(1, len(self.M.log) + 1))

    def radio_busy(self):
        cd = self.cd()
        return bool(cd.qPlaying) or len(cd.queue) > 0

    def tagged_pending(self, tag):
        """v1.3.0: a non-ack transmission of this owner is still waiting (not yet on the air)"""
        cd = self.cd()
        for i in range(1, len(cd.queue) + 1):
            it = cd.queue[i]
            if it.tag == tag and not it.ack:
                return True
        return False

    def move_toward(self, dest, stop_nm, dt):
        p = self.hero.p
        dx, dz = dest[0] - p.x, dest[1] - p.z
        d = (dx * dx + dz * dz) ** 0.5
        if d <= stop_nm * NM:
            return
        step = min(d - stop_nm * NM, 0.8 * NM * dt)   # fast transit (time compression)
        p.x, p.z = p.x + dx / d * step, p.z + dz / d * step

    def burn(self, dt):
        self.hero.fuel = max(0.05, self.hero.fuel - 0.000035 * dt * self.opts.get("burn", 1.0))

    def kill(self, names):
        for n in names:
            u = self.M.units[n]
            if u is not None:
                u.life = 0

    def alive(self, gname):
        g = self.M.groups[gname]
        return [g.units[i].name for i in range(1, len(g.units) + 1) if g.units[i].life > 0]

    def shoot(self):
        """v1.2.0: synthetic GBU-12 release from the hero (S_EVENT_SHOT), 'impacts' at T1 after 5 s"""
        self.rt.execute("""
            local t0 = MOCK.t
            local w = { id_ = 9901 }
            function w:getDesc() return { category = Weapon.Category.BOMB, typeName = "GBU_12", displayName = "GBU-12" } end
            function w:getTypeName() return "GBU_12" end
            function w:isExist() return MOCK.t < t0 + 5 end
            function w:getPoint() return { x = %f, y = 100, z = %f } end
            MOCK.event({ id = world.event.S_EVENT_SHOT, time = t0, initiator = Unit.getByName("Player_01"), weapon = w })
        """ % (T1[0], T1[1]))

    def shoot_at(self, aim, ord_text):
        """v1.6.0: release the JTAC's weapon at unit aim; it impacts after 5 s and kills only that unit"""
        kind = "AGM_65E" if "AGM" in ord_text else "GBU_12"
        for i in range(1, len(self.hero.ammo) + 1):
            a = self.hero.ammo[i]
            if a.desc.typeName == kind and a.count > 0:
                a.count -= 1
                break
        self.rt.execute("""
            local t0, aim, kind = MOCK.t, %r, %r
            local u = Unit.getByName(aim)
            local p = u and u:getPoint() or { x = 0, y = 0, z = 0 }
            local w = { id_ = 9900 + math.floor(t0) }
            function w:getDesc()
                if kind == "AGM_65E" then return { category = Weapon.Category.MISSILE, missileCategory = 6, typeName = kind, displayName = "AGM-65E" } end
                return { category = Weapon.Category.BOMB, typeName = kind, displayName = "GBU-12" }
            end
            function w:getTypeName() return kind end
            function w:isExist() return MOCK.t < t0 + 5 end
            function w:getPoint() return { x = p.x, y = 100, z = p.z } end
            timer.scheduleFunction(function() local v = Unit.getByName(aim); if v then v.life = 0 end end, nil, t0 + 4.9)
            MOCK.event({ id = world.event.S_EVENT_SHOT, time = t0, initiator = Unit.getByName("Player_01"), weapon = w })
        """ % (aim, kind))

    # ── bot ──────────────────────────────────────────────────────────────────
    def press(self, it, sub=None):
        lbl = self.label(it)
        self.presses.append((round(self.t(), 1), lbl + ((" > " + self.label(sub)) if sub is not None else "")))
        fn = (sub if sub is not None else it)[2]
        ok = self.rt.eval("function(f) local ok, e = pcall(f); return ok and 'OK' or tostring(e) end")(fn)
        if ok != "OK":
            self.fail.append("%.0f press '%s': %s" % (self.t(), lbl, ok))
        self.TRT.Menu.Refresh()

    def check_gates(self, items):
        jc, cd = self.jc(), self.cd()
        for it in items:
            lbl = self.label(it)
            m = re.match(r"([A-Z]+ 11): ", lbl)
            if m and m.group(1) in self.CS:
                k = self.CS[m.group(1)]
                ph = jc.st[k].phase
                if ph in DIALOG and self.tagged_pending("JC:" + k):
                    self.fail.append("%.0f GATE: '%s' offered while %s's call is still on the radio (%s)" %
                                     (self.t(), lbl, k, ph))
            elif re.match(r"(OVERLORD|STRIKE|TEXACO): ", lbl) and cd.gateWaiting():
                if not re.search(r"mission abort|divert \(nearest|breakaway|overrun|spokes", lbl):
                    self.fail.append("%.0f GATE: '%s' offered while its call is still waiting" % (self.t(), lbl))

    def choose(self, items):
        o = self.opts
        labels = [(self.label(it), it) for it in items]

        def find(rx):
            for lbl, it in labels:
                if re.search(rx, lbl):
                    return it
            return None
        jc = self.jc()
        # v1.2.0: spoofed abort on Pointer 11
        sm = o.get("spoof")
        if sm:
            st1 = jc.st[self.K1]
            a1 = st1.att if str(st1.phase) == "ATTACK" else None
            sp = a1.spoof if a1 is not None else None
            if a1 is not None and a1.cleared and not st1.spoofDone:
                return None, None                           # cleared: wait for the spoof
            if sp is not None and sp.pending and not sp.onAir:
                return None, None                           # queued, not on the air yet
            if sp is not None and sp.pending and sp.onAir:
                if self.t() - float(sp.onAir) < 3:
                    return None, None                       # listening
                if sm == "comply":
                    return find(r"^POINTER 11: ABORTING$"), None
                if sm == "auth":
                    return find(r"^POINTER 11: AUTHENTICATE$"), None
                if sm == "release" and not self.attack.get("spoof_shot"):
                    self.attack["spoof_shot"] = True
                    self.shoot()
                return None, None
        if o.get("abort_auth"):
            a1 = jc.st[self.K1].att
            if a1 is not None and a1.aborted and a1.ackPending and not a1.authDone:
                it = find(r"^POINTER 11: AUTHENTICATE$")
                if it is not None:
                    return it, None
        # attack simulation: a cleared pass destroys targets
        for k in (self.K1, self.K2):
            g = jc.CFG.JTACS[k].targets[1]                  # v1.5.0 the picked target group
            st = jc.st[k]
            if sm and k == self.K1 and not (st.spoofDone and (st.att is None or st.att.spoof is None
                                                           or not st.att.spoof.pending)):
                continue                                    # v1.2.0 hold the kill until the spoof is answered
            if o.get("passes"):                             # v1.6.0 real passes
                if st.phase == "ATTACK" and st.att is not None and st.att.cleared and not self.attack.get(k) \
                        and st.nine is not None:
                    self.attack[k] = self.t()
                    self.shoot_at(str(st.nine.aim), str(st.ord or ""))
                if st.phase != "ATTACK" or st.att is None or not st.att.cleared:
                    self.attack.pop(k, None)
                continue
            if st.phase == "ATTACK" and st.att is not None and st.att.cleared and not self.attack.get(k):
                self.attack[k] = self.t()
                left = self.alive(g)
                if o.get("winchester") == k:
                    self.hero.ammo = self.rt.table_from([])
                    self.kill(left[:1])
                else:
                    self.kill(left)
            if st.phase != "ATTACK":
                self.attack.pop(k, None)
        # ATTACK: JTAC_Controller puts the next normal-flow call first (F1); never CEASE / NEGATIVE LASER
        for k in (self.K1, self.K2):
            who = str(jc.CFG.JTACS[k].cs)[:-3]   # "POINTER 11" -> "POINTER"
            a = jc.st[k].att
            if str(jc.st[k].phase) == "ATTACK" and a is not None and a.inCalled and not a.cleared \
                    and not a.aborted and self.t() - float(a.inT or 0) < 30:
                return None, None    # IN called: wait for CLEARED HOT (the pilot does not call OFF right away)
            if str(jc.st[k].phase) == "ATTACK":
                for lbl, it in labels:
                    if lbl.startswith(who + " 11: ") and not re.search(r"CEASE LASER|NEGATIVE LASER", lbl):
                        if re.search(r"correlation", lbl):
                            return it, it.sub[1]
                        if re.search(r"IN \(direction", lbl):   # roll in inside the final attack heading window
                            n = jc.st[k].nine
                            lo, hi = float(n.fahLo), float(n.fahHi)
                            mid = (lo + ((hi - lo) % 360) / 2.0) % 360
                            ab = o.get("abort")
                            if ab and ab[0] == k and not self.attack.get("abort_" + k):   # v1.1.0
                                self.attack["abort_" + k] = True
                                mid = (mid + 180) % 360
                            import math
                            self.hero.hdg = math.radians((mid + MAGVAR) % 360)
                        if re.search(r": ABORTING$", lbl) and o.get("abort"):   # v1.1.0
                            t0 = a.abortEndT
                            if t0 is None or self.t() - float(t0) < o["abort"][1]:
                                return None, None
                        return it, None
        order = [
            r"WINCHESTER", r": ABORTING", r": OFF", r"how copy", r"[A-Z]+ 11: check in",
            r"ready for game plan", r"ready for 9-line", r"ready for remarks", r"READBACK \d/3",
            r"STRIKE: check in \(btn", r"OVERLORD: check in", r"OVERLORD: skip AR1",
            r"OVERLORD: continuing mission, no tanker",
            r"OVERLORD: %s divert" % ("unable" if o.get("divert") == "unable" else "wilco"),
            r"OVERLORD: unable contact", r"OVERLORD: off .*retasking", r"OVERLORD: INFLTREP",
            r"OVERLORD: RTB \(no tanker\)", r"^OVERLORD: RTB$", r"STRIKE: check in inbound",
        ]
        for rx in order:
            it = find(rx)
            if it is None:
                continue
            lbl = self.label(it)
            if re.search(r"READBACK \d/3", lbl):
                k = self.CS[lbl.split(":")[0]]
                q = jc.st[k].quiz
                cor = q["items"][q.step].correct
                sub = it.sub
                for i in range(1, len(sub) + 1):
                    if str(sub[i][1]) == str(cor):
                        return it, sub[i]
                return it, sub[1]
            if re.search(r"correlation", lbl):
                return it, it.sub[1]
            if re.search(r": OFF", lbl) and not re.search(r"WINCHESTER", lbl):
                return it, None
            return it, None
        return None, None

    def step(self, dt=1.0):
        self.M.advance(dt)
        cd = self.cd()
        ph = str(cd.phase)
        # movement
        if ph in ("IDLE", "DEPARTURE", "STRIKE_OUT", "STRIKE_CHK", "OVL_OUT", "ENROUTE", "HOLD"):
            self.move_toward(CP, 3 if ph == "HOLD" else 0, dt)
        elif re.match(r"^JTAC\d$", ph) or ph.endswith("_OFF"):                     # v1.8.0 any roster JTAC
            k = str(cd.cur) if cd.cur else self.K1
            self.move_toward(self.TPOS[k], 8, dt)
        elif ph in ("REFUEL", "TKR_DONE", "RTB"):
            self.move_toward(CVN, 0, dt)
        self.burn(dt)
        # scripted world events
        for ev in self.opts.get("events", []):
            if not ev.get("done") and ev["when"](self):
                ev["done"] = True
                ev["do"](self)
        self.TRT.Menu.Refresh()   # the real menu refreshes every 2 s; the bot reads the current state
        items = self.menu()
        self.check_gates(items)
        it, sub = self.choose(items)
        if it is not None:
            self.press(it, sub)
            return True
        return False

    def go(self):
        if self.fail:
            return self
        last_sig, last_t = None, 0
        while self.t() < MAX_S:
            self.step(1.0)
            cd, jc = self.cd(), self.jc()
            sig = (str(cd.phase), str(jc.st[self.K1].phase), str(jc.st[self.K2].phase), len(self.presses), len(cd.queue),
                   bool(cd.qPlaying))
            if sig != last_sig:
                last_sig, last_t = sig, self.t()
            if str(cd.phase) in ("STRIKE_IN", "INBOUND", "RECOVERY"):
                break
            if self.t() - last_t > DEAD_S:
                self.fail.append("%.0f DEAD END: CD %s, J1 %s, J2 %s, menu [%s]" % (
                    self.t(), cd.phase, jc.st[self.K1].phase, jc.st[self.K2].phase,
                    " | ".join(self.label(i) for i in self.menu())))
                break
        else:
            self.fail.append("timeout, CD %s" % self.cd().phase)
        self.check_order()   # v1.3.0
        for i in range(1, len(self.M.errors) + 1):
            self.fail.append("Lua: " + str(self.M.errors[i]))
        for i in range(1, len(self.M.log) + 1):
            s = str(self.M.log[i])
            if re.search(r"error|stale press|subscriber error|BUSY watchdog", s, re.I) and "ERROR" not in s[:20]:
                if not re.search(r"no error", s):
                    self.fail.append("log: " + s)
        return self

    def phases(self):
        out = []
        for i in range(1, len(self.M.log) + 1):
            m = re.search(r"\[CD\] (\w+) → (\w+)", str(self.M.log[i]))
            if m:
                out.append(m.group(2))
        return out

    def radio(self):
        return [str(self.M.texts[i].s) for i in range(1, len(self.M.texts) + 1)]

    # v1.3.0: (pilot reply, the JTAC call it answers) - the reply must come after the call, once per call
    ORDER = [
        (r"^\[HORNET 51\] (Pointer|Eyeball) 11, HORNET 51, ready to copy\.$",
         r"Advise when ready for (game plan|9-line)\.$"),
        (r"^\[HORNET 51\] Ready to copy remarks\.$", r"Advise when ready for remarks\.$"),
        (r"^\[HORNET 51\] (Pointer|Eyeball) 11, -?\d+, \d\d\w .*final attack heading",
         r"(Report IP inbound|Read back)\.$"),
        (r"^\[HORNET 51\] HORNET 51, IP inbound\.$", r"readback correct\."),
    ]

    def check_order(self):
        r = self.radio()
        for rep_rx, call_rx in self.ORDER:
            calls = [i for i, x in enumerate(r) if re.search(call_rx, x)]
            reps = [i for i, x in enumerate(r) if re.search(rep_rx, x)]
            for i in reps:
                if not any(c < i for c in calls):
                    self.fail.append("ORDER: '%s' before the call it answers" % r[i][:70])


# ── cases ──────────────────────────────────────────────────────────────────
def seq_in(ph, *want):
    """want appears in ph as a subsequence"""
    i = 0
    for p in ph:
        if i < len(want) and p == want[i]:
            i += 1
    return i == len(want)


def radio_has(r, rx):
    return any(re.search(rx, s) for s in r.radio())


def kill_jtac_when(k, phase):
    return {"when": lambda r: str(r.jc().st[k].phase) == phase,
            "do": lambda r: r.kill(["JTAC-%s-1" % k[1]])}


J3_PACK = ("CAS_PACK.jtacs.J3 = CAS_PACK.jtacs.J2; CAS_PACK.jtacs.J2 = nil; "    # v1.7.0 roster test
           "CAS_PACK.order = { 'J1', 'J3' }")

CASES = [
    ("pick_B", {210: 1, 211: 9, 212: 2, 214: 1, 217: 2, 219: 2}, {},
     lambda r: [r.cd().res.J1 == "done" and r.cd().res.J2 == "done", radio_has(r, r"T-72 tank"),
                radio_has(r, r"three T-72 tanks and BMP"), r.log_has(r"\[PICK\] J1 -> B"), r.log_has(r"removed SAM BV51")]),
    ("aft_withdraw", {210: 1, 211: 9, 212: 2, 214: 9, 222: 1}, {"passes": True},   # v1.6.0 effects-based
     lambda r: [r.cd().res.J1 == "done" and r.cd().res.J2 == "done", r.log_has(r"AFTERMATH J1: withdraw \(flag\)"),
                r.log_has(r"WITHDRAW J1: 1 unit"), radio_has(r, r"T-55 tank withdrawing"),
                radio_has(r, r"Desired effect, destroy SA-13 launcher"),
                r.log_has(r"\[SCORE\] \+5 JTAC TARGET GROUP OBJECTIVE ACHIEVED"),
                not r.log_has(r"VOICE (text only|missing clip)")]),
    ("aft_threat", {210: 1, 211: 9, 212: 2, 214: 9, 222: 2}, {"passes": True},
     lambda r: [r.cd().res.J1 == "done" and r.cd().res.J2 == "done", r.log_has(r"threat persists -> re-attack"),
                radio_has(r, r"still a threat to friendlies"), not r.log_has(r"VOICE (text only|missing clip)")]),
    ("aft_ignore", {210: 1, 211: 9, 212: 2, 214: 9, 222: 3}, {"passes": True},
     lambda r: [r.cd().res.J1 == "done" and r.cd().res.J2 == "done", radio_has(r, r"T-55 tank remaining"),
                radio_has(r, r"BTR and T-72 tank remaining"), not r.log_has(r"VOICE (text only|missing clip)")]),
    ("audit", {210: 1, 211: 9, 212: 2, 214: 1, 221: 1}, {},          # v1.5.1 Tasking_Pick v1.1.0 / JC v0.14.2
     lambda r: [r.cd().res.J1 == "done" and r.cd().res.J2 == "done", r.log_has(r"AUDIT mode"),
                all(r.log_has(r"\[JC\] AUDIT %s-%s .* -> OK$" % (k, e)) for k in ("J1", "J2") for e in "ABC"),
                all(r.log_has(r"\[PICK\] site %s-%s " % (k, e)) for k in ("J1", "J2") for e in "ABC")]),
    ("pick_C", {210: 3, 211: 9, 212: 2, 217: 3, 219: 3}, {},
     lambda r: [r.cd().res.J1 == "done" and r.cd().res.J2 == "done", radio_has(r, r"two self-propelled howitzers"),
                radio_has(r, r"four self-propelled howitzers"), r.log_has(r"\[PICK\] J2 -> C")]),
    ("A_tic1", {210: 1, 211: 9, 212: 2, 214: 1}, {},
     lambda r: [seq_in(r.phases(), "ENROUTE", "JTAC1", "J1_OFF", "JTAC2", "J2_OFF", "REFUEL"),
                r.cd().res.J1 == "done" and r.cd().res.J2 == "done", bool(r.cd().vulDone)]),
    ("A_tic2", {210: 1, 211: 9, 212: 2, 214: 2}, {},
     lambda r: [seq_in(r.phases(), "JTAC1", "J1_OFF", "JTAC2", "J2_OFF"), radio_has(r, r"EYEBALL 11.*TROOPS IN CONTACT")]),
    ("B_J1first", {210: 2, 211: 9, 212: 2, 215: 1}, {},
     lambda r: [seq_in(r.phases(), "ENROUTE", "HOLD", "JTAC1", "J1_OFF", "JTAC2", "J2_OFF"),
                radio_has(r, r"Hold at CP TIGER"), radio_has(r, r"Overlord, tasking"), r.cd().vulExtS > 0]),
    ("B_J2first", {210: 2, 211: 9, 212: 2, 215: 2}, {},
     lambda r: [seq_in(r.phases(), "HOLD", "JTAC2", "J2_OFF", "JTAC1", "J1_OFF", "REFUEL"),
                r.cd().res.J1 == "done" and r.cd().res.J2 == "done",
                radio_has(r, r"off Eyeball 11, mission 4102 complete")]),
    ("C_accept_seed1", {210: 3, 212: 2}, {"seed": 1},
     lambda r: [seq_in(r.phases(), "JTAC1", "JTAC2", "J2_OFF", "JTAC1", "J1_OFF", "REFUEL"),
                radio_has(r, r"divert, divert"), radio_has(r, r"we'll hold"), radio_has(r, r"Pointer 11 is holding"),
                r.cd().res.J1 == "done" and r.cd().res.J2 == "done", r.log_has(r"SUSPEND J1"), r.log_has(r"RESUME J1")]),
    ("C_accept_seed2", {210: 3, 212: 2}, {"seed": 2},
     lambda r: [seq_in(r.phases(), "JTAC1", "JTAC2", "J2_OFF", "JTAC1", "J1_OFF"), r.cd().dv.state == "accepted"]),
    ("C_accept_seed3", {210: 3, 212: 2}, {"seed": 3},
     lambda r: [seq_in(r.phases(), "JTAC1", "JTAC2", "J2_OFF", "JTAC1", "J1_OFF"), r.cd().dv.state == "accepted"]),
    ("C_unable", {210: 3, 212: 2}, {"divert": "unable"},
     lambda r: [seq_in(r.phases(), "JTAC1", "J1_OFF", "JTAC2", "J2_OFF"), r.cd().dv.state == "refused",
                radio_has(r, r"Continue with Pointer 11"), radio_has(r, r"EYEBALL 11.*TROOPS IN CONTACT")]),
    ("C_nofuel", {210: 3, 212: 2}, {"fuel": 0.42, "burn": 0.2},
     lambda r: [r.cd().dv.state == "nofuel", seq_in(r.phases(), "JTAC1", "J1_OFF", "JTAC2", "J2_OFF")]),
    ("LC_J1_tech", {210: 1, 211: 1, 212: 2, 214: 2}, {},
     lambda r: [radio_has(r, r"radio failure on primary.*button 9"), r.cd().res.J1 == "done",
                seq_in(r.phases(), "JTAC1", "J1_OFF", "JTAC2", "J2_OFF")]),
    ("LC_J1_down", {210: 1, 211: 2, 212: 2, 214: 2}, {},
     lambda r: [radio_has(r, r"Pointer 11 is off the net"), r.cd().res.J1 == "cancelled",
                r.cd().res.J2 == "done", seq_in(r.phases(), "JTAC1", "JTAC2", "J2_OFF", "REFUEL"),
                radio_has(r, r"Mission 4101 cancelled, no JTAC contact")]),
    ("LC_J2_tech", {210: 1, 211: 3, 212: 2, 214: 1}, {},
     lambda r: [radio_has(r, r"radio failure on primary.*button 11"), r.cd().res.J2 == "done"]),
    ("LC_J2_down", {210: 1, 211: 4, 212: 2, 214: 1}, {},
     lambda r: [r.cd().res.J2 == "cancelled", radio_has(r, r"Say intentions"),
                seq_in(r.phases(), "JTAC1", "J1_OFF", "JTAC2", "J2_OFF", "REFUEL")]),
    ("LC_B_J2first_down", {210: 2, 211: 4, 212: 2, 214: 1, 215: 2}, {},
     lambda r: [r.cd().res.J2 == "cancelled", r.cd().res.J1 == "done", seq_in(r.phases(), "HOLD", "JTAC2", "JTAC1", "J1_OFF")]),
    ("JTAC1_killed_in_NINE", {210: 1, 211: 9, 212: 2, 214: 2}, {"events": [kill_jtac_when("J1", "NINE")]},
     lambda r: [r.cd().res.J1 == "cancelled", r.log_has(r"JTAC J1 lost during the tasking"),
                seq_in(r.phases(), "JTAC1", "JTAC2", "J2_OFF")]),
    ("noshow", {210: 1, 211: 9, 212: 1, 214: 1}, {},
     lambda r: [radio_has(r, r"Texaco 11 is off station.*Say intentions"), radio_has(r, r"continuing mission without tanker"),
                radio_has(r, r"No tanker available. Say intentions"), r.cd().res.J2 == "done"]),
    ("tanker_shot_AR1", {210: 1, 211: 9, 212: 2, 214: 1},
     {"events": [{"when": lambda r: str(r.cd().phase) == "ENROUTE",
                  "do": lambda r: setattr(r.M.units["TANKER-1-1"], "life", 0)}]},
     lambda r: [radio_has(r, r"Texaco 11 is off station.*Say intentions"), bool(r.cd().tkrLost)]),
    ("abort_ack_J1", {210: 1, 211: 9, 212: 2, 214: 1}, {"abort": ("J1", 2)},
     lambda r: [r.log_has(r"ABORT J1 \(Outside final attack heading"), r.log_has(r"ABORT ACK J1 \d+\.\d s$"),
                not r.log_has(r"ABORT ACK LATE"), radio_has(r, r"^\[HORNET 51\] HORNET 51, aborting\.$"),
                radio_has(r, r"re-attack approved"), r.cd().res.J1 == "done"]),
    ("abort_ack_J1_late", {210: 1, 211: 9, 212: 2, 214: 1}, {"abort": ("J1", 20)},
     lambda r: [r.log_has(r"ABORT ACK J1 \d+\.\d s \(late\)"), r.log_has(r"\[SCORE\] -2 ABORT ACK LATE"),
                r.cd().res.J1 == "done"]),
    ("abort_auth_J1", {210: 1, 211: 9, 212: 2, 214: 1, 216: 9}, {"abort": ("J1", 2), "abort_auth": True},
     lambda r: [r.log_has(r"AUTH J1 challenge \w\w reply \w \(real abort\)"),
                radio_has(r, r"^\[POINTER 11\] HORNET 51, Pointer 11, I authenticate [A-Z-]+\. ABORT QUEBEC\.$"),
                r.log_has(r"ABORT ACK J1"), r.cd().res.J1 == "done", not r.log_has(r"VOICE (text only|missing clip)")]),
    ("spoof_comply_J1", {210: 1, 211: 9, 212: 2, 214: 1, 216: 1}, {"spoof": "comply"},
     lambda r: [r.log_has(r"SPOOF J1 ABORT [A-Z] \(briefed reply Q\)"), r.log_has(r"SPOOF J1 complied"),
                r.log_has(r"\[SCORE\] -5 ABORT NOT AUTHENTICATED \(Pointer 11\)"),
                radio_has(r, r"negative, Pointer 11 did not call abort\. Report IN\."), not r.log_has(r"INCIDENT"),
                r.cd().res.J1 == "done", not r.log_has(r"VOICE (text only|missing clip)")]),
    ("spoof_auth_J1", {210: 1, 211: 9, 212: 2, 214: 1, 216: 1}, {"spoof": "auth"},
     lambda r: [r.log_has(r"AUTH J1 challenge \w\w reply \w \(spoof\)"),
                radio_has(r, r"I authenticate [A-Z-]+\. Disregard abort, not Pointer 11\. (HORNET 51, cleared hot|Report IN)\.$"),
                not r.log_has(r"\[SCORE\] -(5|10) "), not r.log_has(r"INCIDENT"), r.cd().res.J1 == "done", not r.log_has(r"VOICE (text only|missing clip)")]),
    ("spoof_release_J1", {210: 1, 211: 9, 212: 2, 214: 1, 216: 1}, {"spoof": "release"},
     lambda r: [r.log_has(r"SPOOF J1 unresolved at release"),
                r.log_has(r"\[SCORE\] -10 RELEASE WITH UNRESOLVED ABORT CALL \(Pointer 11\)"),
                radio_has(r, r"be advised, last abort was not Pointer 11\.$"), not r.log_has(r"INCIDENT"),
                r.cd().res.J1 == "done", not r.log_has(r"VOICE (text only|missing clip)")]),
    ("spoof_wait_J1", {210: 1, 211: 9, 212: 2, 214: 1, 216: 1}, {"spoof": "wait"},
     lambda r: [r.log_has(r"SPOOF J1 unanswered"), radio_has(r, r"be advised, last abort was not Pointer 11\.$"),
                not r.log_has(r"\[SCORE\] -(5|10) "), r.cd().res.J1 == "done", not r.log_has(r"VOICE (text only|missing clip)")]),
    ("winchester_J1", {210: 1, 211: 9, 212: 2, 214: 2}, {"winchester": "J1"},
     lambda r: [r.cd().res.J1 == "incomplete", r.cd().res.J2 == "cancelled", radio_has(r, r"copy Winchester"),
                radio_has(r, r"Mission 4102 incomplete, Winchester"), seq_in(r.phases(), "JTAC1", "J1_OFF", "REFUEL")]),
    ("winchester_J2_B", {210: 2, 211: 9, 212: 2, 214: 1, 215: 1}, {"winchester": "J2"},
     lambda r: [r.cd().res.J1 == "done", r.cd().res.J2 == "incomplete", seq_in(r.phases(), "JTAC1", "J1_OFF", "JTAC2", "J2_OFF", "REFUEL")]),
    ("airstart_C", {210: 3, 212: 2}, {"start": (CP[0] - 30 * NM, CP[1] - 5 * NM)},
     lambda r: [seq_in(r.phases(), "ENROUTE", "JTAC1", "JTAC2", "J2_OFF", "JTAC1", "J1_OFF"), r.cd().airStart == "J1"]),
    ("airstart_noshow_B", {210: 2, 211: 9, 212: 1}, {"start": (CP[0] - 30 * NM, CP[1] - 5 * NM)},
     lambda r: [radio_has(r, r"Texaco 11 is off station.*Say intentions"), seq_in(r.phases(), "ENROUTE", "HOLD")]),
    # v1.7.0 roster: J2 renamed J3 (Comms_Director v1.10.0 slots; JTAC_Controller JBEH defaults for J3)
    ("roster_J3_A", {210: 1, 211: 9, 212: 2, 214: 2}, {"pack_lua": J3_PACK},
     lambda r: [seq_in(r.phases(), "ENROUTE", "JTAC1", "J1_OFF", "JTAC2", "J3_OFF", "REFUEL"),
                r.cd().res.J1 == "done" and r.cd().res.J3 == "done", bool(r.cd().vulDone), bool(r.cd().deadJ3),
                radio_has(r, r"EYEBALL 11.*TROOPS IN CONTACT"), radio_has(r, r"mission 4101 and 4102")]),
    ("roster_J3_B", {210: 2, 211: 9, 212: 2, 214: 1, 215: 2}, {"pack_lua": J3_PACK},
     lambda r: [seq_in(r.phases(), "HOLD", "JTAC2", "J3_OFF", "JTAC1", "J1_OFF", "REFUEL"),
                r.cd().res.J1 == "done" and r.cd().res.J3 == "done", radio_has(r, r"off Eyeball 11, mission 4102 complete")]),
    ("roster_J3_C", {210: 3, 212: 2}, {"pack_lua": J3_PACK, "seed": 1},
     lambda r: [seq_in(r.phases(), "JTAC1", "JTAC2", "J3_OFF", "JTAC1", "J1_OFF", "REFUEL"),
                radio_has(r, r"divert, divert. Eyeball 11"), r.cd().dv.state == "accepted",
                r.cd().res.J1 == "done" and r.cd().res.J3 == "done"]),
    ("roster_J3_LC_down", {210: 1, 211: 4, 212: 2, 214: 1}, {"pack_lua": J3_PACK},
     lambda r: [r.cd().res.J3 == "cancelled", radio_has(r, r"Eyeball 11 is off the net"),
                seq_in(r.phases(), "JTAC1", "J1_OFF", "JTAC2", "J3_OFF", "REFUEL")]),
    # v1.8.0 roster P3: AXEMAN 11 (J3) and DARKNIGHT 11 (J4, MQ-9 designator) tasked
    ("tasked_J3J4_A", {210: 1, 211: 9, 212: 2, 214: 2}, {"pack_lua": "CAS_PACK.tasked = { 'J3', 'J4' }"},
     lambda r: [seq_in(r.phases(), "ENROUTE", "JTAC3", "J3_OFF", "JTAC4", "J4_OFF", "REFUEL"),
                r.cd().res.J3 == "done" and r.cd().res.J4 == "done", bool(r.cd().vulDone),
                r.log_has(r"LASER ON J4 -> .* \(designator FAC-1-1\)"), r.log_has(r"GAME PLAN J4: Type 2"),
                r.log_has(r"OBJECTIVE J3: destroy two technicals"), radio_has(r, r"DARKNIGHT 11.*TROOPS IN CONTACT"),
                radio_has(r, r"mission 4103 and 4104"), radio_has(r, r"Line 2, mission 4103 and 4104")]),
    ("tasked_J3J4_C", {210: 3, 212: 2}, {"pack_lua": "CAS_PACK.tasked = { 'J3', 'J4' }", "seed": 1},
     lambda r: [seq_in(r.phases(), "JTAC3", "JTAC4", "J4_OFF", "JTAC3", "J3_OFF", "REFUEL"),
                radio_has(r, r"divert, divert\. Darknight 11"), r.cd().dv.state == "accepted",
                r.log_has(r"SUSPEND J3"), r.log_has(r"RESUME J3"),
                r.cd().res.J3 == "done" and r.cd().res.J4 == "done"]),
    ("tasked_J4J3_B", {210: 2, 211: 9, 212: 2, 214: 1, 215: 2}, {"pack_lua": "CAS_PACK.tasked = { 'J4', 'J3' }"},
     lambda r: [seq_in(r.phases(), "HOLD", "JTAC3", "J3_OFF", "JTAC4", "J4_OFF", "REFUEL"),
                r.cd().res.J3 == "done" and r.cd().res.J4 == "done", radio_has(r, r"off Axeman 11, mission 4103 complete")]),
    # v1.9.0 P4 XCAS / random pair (Tasking_Pick v1.4.0, Comms_Director v1.11.0)
    ("xcas_A", {210: 1, 211: 9, 212: 2, 214: 2, 226: 1}, {"passes": True},
     lambda r: [radio_has(r, r"checking in as fragged, XCAS"), radio_has(r, r"close air support on call"),
                radio_has(r, r"Mission 41\d\d\. Pointer 11 is on station"),
                radio_has(r, r"\] Mission 41\d\d, push button 4, HORNET 51\.$"),
                radio_has(r, r"Mission 41\d\d\. Eyeball 11 reports TROOPS IN CONTACT"),
                radio_has(r, r"Mission 41\d\d, Push button 5, HORNET 51, buster"),
                radio_has(r, r"off Pointer 11, mission 41\d\d complete"), r.log_has(r"XCAS: mission \d+ \(J1\), \d+ \(J2\)"),
                r.cd().res.J1 == "done" and r.cd().res.J2 == "done",
                not r.log_has(r"VOICE (text only|missing clip)|missing clip")]),
    ("xcas_C_J3J4", {210: 3, 212: 2, 226: 1}, {"pack_lua": "CAS_PACK.tasked = { 'J3', 'J4' }", "seed": 1},
     lambda r: [seq_in(r.phases(), "JTAC3", "JTAC4", "J4_OFF", "JTAC3", "J3_OFF", "REFUEL"),
                radio_has(r, r"divert, divert\. Mission 41\d\d\. Darknight 11 reports"),
                radio_has(r, r"Axeman 11 is holding"), not radio_has(r, r"Axeman 11 is holding.*Mission"),
                not r.log_has(r"VOICE (text only|missing clip)|missing clip")]),
    ("xcas_LC_down_J4", {210: 1, 211: 4, 212: 2, 214: 1, 226: 1}, {"pack_lua": "CAS_PACK.tasked = { 'J3', 'J4' }"},
     lambda r: [r.cd().res.J4 == "cancelled", radio_has(r, r"Darknight 11 is off the net.*Mission 41\d\d cancelled"),
                radio_has(r, r"cancelled, no JTAC contact"), not r.log_has(r"missing clip")]),
] + [("rpair_%02d" % i, {225: 1, 226: 1}, {"seed": 200 + i},
      lambda r: [bool(r.cd().vulDone), r.log_has(r"\[PICK\] tasked: J\d J\d \(random pair\)"),
                 not r.log_has(r"missing clip")]) for i in range(1, 9)
] + [("random_%02d" % i, {}, {"seed": 100 + i}, lambda r: [bool(r.cd().vulDone)]) for i in range(1, 13)]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verbose = "-v" in sys.argv
    bad = 0
    for name, flags, opts, expect in CASES:
        if args and not any(name.startswith(a) for a in args):
            continue
        r = Run(name, flags, opts).go()
        try:
            checks = expect(r)
        except Exception as ex:   # noqa: BLE001
            checks = [False]
            r.fail.append("expect error: %r" % ex)
        if not all(checks):
            r.fail.append("expectations %s" % checks)
        scen = r.cd().scen
        desc = "%s order %s" % (scen.kind if scen else "?", " ".join(str(x) for x in r.cd().order.values())) if scen else ""
        status = "PASS" if not r.fail else "FAIL"
        bad += 0 if not r.fail else 1
        print("%-22s %s  %5.0f s  %s  phases: %s" % (name, status, r.t(), desc, " ".join(r.phases())))
        for f in r.fail[:12]:
            print("      " + f)
        if verbose:
            for i in range(1, len(r.M.log) + 1):
                s = str(r.M.log[i])
                if re.search(r"\[CD\]|\[JC\]|Menu_Manager \| press", s):
                    print("   " + s)
            for tt, s in [(r.M.texts[i].t, r.M.texts[i].s) for i in range(1, len(r.M.texts) + 1)]:
                print("   TXT %7.1f %s" % (tt, str(s).replace("\n", " / ")[:220]))
    print("\n%d case(s) failed" % bad if bad else "\nall cases passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
