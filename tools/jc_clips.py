# jc_clips.py | v1.0.0
# Voice for JTAC_Controller (>= v0.7.0): ONE source for the clip list and the runtime dictionary.
#   python tools/jc_clips.py            writes the JC rows into tts/clips.csv (block "# BEGIN JC" .. "# END JC")
#                                       and the dictionary into scripts/JTAC_Controller.lua
#                                       (block "-- BEGIN VOICE (tools/jc_clips.py)" .. "-- END VOICE")
#   python tools/jc_clips.py --ids      prints the clip ids (for: python tts/make_clips.py <ids>)
#   python tools/jc_clips.py --audio-into-cd   copies tts/audio_table.lua into Comms_Director CFG.AUDIO
# Runtime: JTAC_Controller turns every transmission TEXT into tokens: longest dictionary phrase first,
# then grids, numbers (digits; after a direction word a multiple of 100 is read "two thousand two hundred"),
# count words, directions, NATO words. Any word it cannot place -> that message stays text only (logged).
# Written keys are normalised like JTAC_Controller Norm(): lower case, , . ; : ! ? ( ) removed (decimal point
# kept), runs of spaces collapsed. "{s}" = the JTAC's own call sign ("pointer 11" / "eyeball 11").
# Voices: pj_* POINTER (Pointer 11), ej_* EYEBALL (Eyeball 11), jp_* PILOT, ovl_rep_* OVERLORD.
# (pj / ej, not ptr / eye: Comms_Director already owns eye_area_clear, ptr_rb_ok, ... - write_csv refuses clashes.)
# POINTER_JC = john-medium (tts/make_clips.py v1.10.0): ryan-medium, the old POINTER voice, collapses
# one-word tokens to ~0.1 s of speech ("eight" 0.15 s raw at any length_scale), unusable for chained digits.
# Pilot digits / letters / directions are the existing cv:p_* (CV_Comms) and p_dir_* (Comms_Director) clips.
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
CSV = os.path.join(REPO, "tts", "clips.csv")
JC = os.path.join(REPO, "scripts", "JTAC_Controller.lua")
BEGIN, END = "# BEGIN JC (tools/jc_clips.py)", "# END JC"
LBEGIN, LEND = "-- BEGIN VOICE (tools/jc_clips.py)", "-- END VOICE"

JTACS = {   # prefix -> (voice, written self, spoken self, written egress, spoken egress)
    "pj": ("POINTER_JC>POINTER", "pointer 11", "Pointer one one", "egress north to tiger", "Egress north to Tiger."),
    "ej": ("EYEBALL", "eyeball 11", "Eyeball one one", "egress northwest feet wet", "Egress north west, feet wet."),
}
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
NATO = ["Alfa", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliett", "Kilo",
        "Lima", "Mike", "November", "Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
        "Victor", "Whiskey", "X-ray", "Yankee", "Zulu"]
DIRS = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
DIR_SPOKEN = {"northeast": "north east", "southeast": "south east", "southwest": "south west",
              "northwest": "north west"}
# label as JTAC_Controller writes it (CFG.LABEL values, CFG.THREAT labels) -> (singular, plural) spoken
LABELS = {
    "SA-8 launcher": ("S A eight launcher", "S A eight launchers"),
    "SA-13 launcher": ("S A thirteen launcher", "S A thirteen launchers"),
    "SA-15": ("S A fifteen", "S A fifteens"),
    "SA-15 (M2)": ("S A fifteen M two", "S A fifteen M twos"),
    "SA-6 radar": ("S A six radar", "S A six radars"),
    "SA-6 launcher": ("S A six launcher", "S A six launchers"),
    "SA-6": ("S A six", "S A sixes"),
    "SA-3": ("S A three", "S A threes"),
    "SA-10": ("S A ten", "S A tens"),
    "SA-11": ("S A eleven", "S A elevens"),
    "SA-8": ("S A eight", "S A eights"),
    "SA-19": ("S A nineteen", "S A nineteens"),
    "ZSU-23-4": ("Z S U twenty three four", "Z S U twenty three fours"),
    "SA-14 MANPADS": ("S A fourteen manpads", "S A fourteen manpads"),
    "SA-18 MANPADS": ("S A eighteen manpads", "S A eighteen manpads"),
    "SA-3 radar": ("S A three radar", "S A three radars"),
    "SA-3 launcher": ("S A three launcher", "S A three launchers"),
    "T-55 tank": ("T fifty five tank", "T fifty five tanks"),
    "T-72 tank": ("T seventy two tank", "T seventy two tanks"),
    "BTR": ("B T R", "B T Rs"),
    "BMP": ("B M P", "B M Ps"),
    "truck": ("truck", "trucks"),
    "infantry": ("infantry", "infantry"),
}
ORDS = {"one AGM-65E": "one A G M sixty five echo", "one GBU-12": "one G B U twelve"}

# name -> (written key, spoken)   {s} / {S} = own call sign
JP = {
    "ci_a": ("hornet 51 {s} copy all abort code noted situation update threat the target itself",
             "Hornet five one, {S}, copy all, abort code noted. Situation update. Threat, the target itself,"),
    "w_plus": ("plus", "plus"),
    "ci_enemy": ("enemy", "Enemy,"),
    "ci_fr_bravo": ("friendlies bravo 2-1 mech platoon in contact all friendlies",
                    "Friendlies, Bravo two one, mech platoon, in contact. All friendlies"),
    "ci_fr_team": ("friendlies my team only all friendlies", "Friendlies, my team only. All friendlies"),
    "w_of_tgt": ("of the target", "of the target."),
    "ci_wind": ("no artillery hazards winds on the deck", "No artillery. Hazards, winds on the deck"),
    "ci_calm": ("no artillery hazards winds on the deck calm", "No artillery. Hazards, winds on the deck calm."),
    "w_at": ("at", "at"),
    "ci_end": ("remarks i have a laser no ir pointer request in with heading advise when ready for game plan",
               "Remarks, I have a laser, no I R pointer. Request IN with heading. Advise when ready for game plan."),
    "gp_t1": ("hornet 51 type 1 control bomb on target", "Hornet five one, type one control, bomb on target,"),
    "gp_t2": ("hornet 51 type 2 control bomb on target", "Hornet five one, type two control, bomb on target,"),
    "gp_t2c": ("hornet 51 type 2 control bomb on coordinate", "Hornet five one, type two control, bomb on coordinate,"),
    "gp_end": ("advise when ready for 9-line", "Advise when ready for nine line."),
    "cs": ("hornet 51", "Hornet five one,"),
    "ip_lynx": ("lynx", "Lynx."),
    "ip_puma": ("puma", "Puma."),
    "w_keyhole": ("keyhole", "Keyhole"),
    "w_laser": ("laser", "Laser"),
    "w_toc": ("troops in contact", "troops in contact."),
    "nl_end": ("advise when ready for remarks", "Advise when ready for remarks."),
    "rm_a": ("hornet 51 remarks", "Hornet five one, remarks."),
    "rm_ltl": ("laser-to-target line", "Laser to target line"),
    "rm_threat": ("threat", "Threat"),
    "rm_caution": ("caution no run-in clear of", "Caution, no run in clear of"),
    "rm_via": ("proceed to the ip via", "Proceed to the I P via"),
    "w_caution": ("caution", "Caution,"),
    "rm_route": ("on the route to the ip", "on the route to the I P."),
    "rm_req": ("request", "Request"),
    "rm_hd": ("hard deck two-zero thousand in effect", "Hard deck two zero thousand in effect."),
    "rm_fah": ("restrictions final attack heading", "Restrictions. Final attack heading"),
    "w_to": ("to", "to"),
    "rm_end": ("report ip inbound", "Report I P inbound."),
    "rb_ok": ("hornet 51 readback correct", "Hornet five one, readback correct."),
    "w_call_laser": ("call for laser", "Call for laser."),
    "rb_neg": ("hornet 51 negative", "Hornet five one, negative."),
    "w_elev": ("elevation", "Elevation"),
    "w_grid": ("grid", "grid"),
    "w_fah": ("final attack heading", "final attack heading"),
    "w_readback": ("read back", "Read back."),
    "say_rb": ("hornet 51 {s} say readback", "Hornet five one, {S}, say readback."),
    "cont": ("hornet 51 continue", "Hornet five one, continue."),
    "clr_hot": ("hornet 51 cleared hot", "Hornet five one, cleared hot."),
    "blind": ("hornet 51 blind continue", "Hornet five one, blind. Continue."),
    "cont_tally": ("hornet 51 continue say when tally or captured", "Hornet five one, continue. Say when tally or captured."),
    "w_abort": ("abort", "abort"),
    "ab_fah": ("outside final attack heading heading", "Outside final attack heading, heading"),
    "ab_civ": ("civilian vehicle entering the target area", "Civilian vehicle entering the target area."),
    "lasing": ("{s} lasing", "{S}, lasing"),
    "unable_los": ("hornet 51 unable laser no line of sight", "Hornet five one, unable laser, no line of sight."),
    "neg_resp": ("hornet 51 laser on code", "Hornet five one, laser on, code"),
    "laser_off": ("{s} laser off", "{S}, laser off."),
    "laser_to": ("hornet 51 {s} laser off no cease laser call", "Hornet five one, {S}, laser off, no cease laser call."),
    "not_clr": ("hornet 51 {s} you were not cleared hold fire", "Hornet five one, {S}, you were not cleared. Hold fire."),
    "aft_abort": ("hornet 51 {s} weapon released after abort hold fire",
                  "Hornet five one, {S}, weapon released after abort. Hold fire."),
    "term": ("hornet 51 {s} second unauthorized release terminating control cleared off return to overlord",
             "Hornet five one, {S}, second unauthorized release. Terminating control. Cleared off, return to Overlord."),
    "as_a": ("hornet 51 {s}", "Hornet five one, {S},"),
    "w_splash": ("splash", "splash,"),
    "as_good": ("good hits", "good hits."),
    "as_next": ("next target", "Next target,"),
    "as_from": ("from your hits", "From your hits,"),
    "as_shift": ("call shift", "Call shift."),
    "as_rin": ("report in", "Report IN."),
    "as_miss": ("miss", "miss."),
    "bda_a": ("bda size", "B D A. Size,"),
    "w_destroyed": ("destroyed", "destroyed,"),
    "w_notobs": ("not observed", "not observed."),
    "bda_act": ("activity none observed location", "Activity, none observed. Location,"),
    "w_time": ("time", "Time,"),
    "w_local": ("local", "local."),
    "bda_rmk": ("remarks mission", "Remarks, mission"),
    "bda_end": ("successful cleared to depart return to overlord", "successful. Cleared to depart, return to Overlord."),
    "nj_a": ("hornet 51 target is the", "Hornet five one, target is the"),
    "nj_bravo": ("from bravo 2-1", "From Bravo two one,"),
    "nj_me": ("from my position", "From my position,"),
    "off_copy": ("hornet 51 copy", "Hornet five one, copy."),
    "off_reatk": ("hornet 51 copy re-attack approved", "Hornet five one, copy, re-attack approved."),
    "area_clear": ("hornet 51 {s} target area clear", "Hornet five one, {S}, target area clear."),
    "w_and": ("and", "and"),
    "w_meters": ("meters", "meters."),
    "w_point": (None, "point"),
    "w_hundred": (None, "hundred"),
    "w_thousand": (None, "thousand"),
}
PILOT = {   # id -> (written key, spoken)
    "jp_ci_ptr": ("pointer 11 hornet 51 mission", "Pointer one one, Hornet five one, mission"),
    "jp_ci_eye": ("eyeball 11 hornet 51 mission", "Eyeball one one, Hornet five one, mission"),
    "jp_one_hornet": ("one hornet", "one Hornet,"),
    "jp_cptiger": ("cp tiger", "C P Tiger"),
    "jp_for": ("for", "for"),
    "jp_overhead": ("overhead cp tiger", "overhead C P Tiger,"),
    "jp_angels": ("angels", "angels"),
    "jp_wpn_agm_65e": ("agm-65e", "A G M sixty five echo,"),
    "jp_wpn_gbu_12": ("gbu-12", "G B U twelve,"),
    "jp_gun": ("gun", "gun,"),
    "jp_playtime": ("playtime", "playtime"),
    "jp_ci_end": ("atflir laser spot tracker abort code", "A T FLIR, laser spot tracker, abort code"),
    "jp_ready_ptr": ("pointer 11 hornet 51 ready to copy", "Pointer one one, Hornet five one, ready to copy."),
    "jp_ready_eye": ("eyeball 11 hornet 51 ready to copy", "Eyeball one one, Hornet five one, ready to copy."),
    "jp_ready_rmk": ("ready to copy remarks", "Ready to copy remarks."),
    "jp_rb_ptr": ("pointer 11", "Pointer one one,"),
    "jp_rb_eye": ("eyeball 11", "Eyeball one one,"),
    "jp_fah": ("final attack heading", "final attack heading"),
    "jp_to": ("to", "to"),
    "jp_ipin": ("hornet 51 ip inbound", "Hornet five one, I P inbound."),
    "jp_ten": ("hornet 51 ten seconds", "Hornet five one, ten seconds."),
    "jp_lon_ptr": ("pointer 11 laser on", "Pointer one one, laser on."),
    "jp_lon_eye": ("eyeball 11 laser on", "Eyeball one one, laser on."),
    "jp_shift_ptr": ("pointer 11 shift", "Pointer one one, shift."),
    "jp_shift_eye": ("eyeball 11 shift", "Eyeball one one, shift."),
    "jp_cease_ptr": ("pointer 11 cease laser", "Pointer one one, cease laser."),
    "jp_cease_eye": ("eyeball 11 cease laser", "Eyeball one one, cease laser."),
    "jp_spot": ("hornet 51 spot", "Hornet five one, spot."),
    "jp_neglaser": ("hornet 51 negative laser", "Hornet five one, negative laser."),
    "jp_tally": ("hornet 51 tally", "Hornet five one, tally."),
    "jp_captured": ("hornet 51 captured", "Hornet five one, captured."),
    "jp_nojoy": ("hornet 51 no joy", "Hornet five one, no joy."),
    "jp_in": ("hornet 51 in from the", "Hornet five one, IN from the"),
    "jp_off": ("hornet 51 off", "Hornet five one, off"),
    "jp_dry": ("dry", "dry."),
    "jp_aborting": ("hornet 51 aborting off", "Hornet five one, aborting, off"),
    "jp_cs": ("hornet 51", "Hornet five one,"),
    "jp_rifle": ("rifle", "rifle,"),
    "jp_away": ("away", "away."),
}
OVL = {
    "ovl_rep_ptr": ("hornet 51 overlord pointer 11 reports an unauthorized weapons release the incident has been "
                    "reported to cag report to cag on recovery",
                    "Hornet five one, Overlord. Pointer one one reports an unauthorized weapons release. "
                    "The incident has been reported to CAG. Report to CAG on recovery."),
    "ovl_rep_eye": ("hornet 51 overlord eyeball 11 reports an unauthorized weapons release the incident has been "
                    "reported to cag report to cag on recovery",
                    "Hornet five one, Overlord. Eyeball one one reports an unauthorized weapons release. "
                    "The incident has been reported to CAG. Report to CAG on recovery."),
}


def norm(t):
    t = t.lower().replace("\n", " ")
    t = re.sub(r"(\d)\.(\d)", r"\1<dot>\2", t)
    t = re.sub(r"[,.;:!?()]", " ", t).replace("<dot>", ".")
    return re.sub(r"\s+", " ", t).strip()


def slug(t):
    return re.sub(r"[^a-z0-9]+", "_", t.lower()).strip("_")


def label_keys():
    out = []   # (suffix, written, spoken)
    for lab, (sg, pl) in LABELS.items():
        w = norm(lab)
        wpl = w if (lab == "infantry" or "MANPADS" in lab) else w + "s"
        out.append(("lab_" + slug(lab), w, sg))
        if wpl != w:
            out.append(("lab_" + slug(lab) + "_pl", wpl, pl))
    return out


def rows():
    out = []
    for p, (voice, me, me_sp, eg, eg_sp) in JTACS.items():
        for i, w in enumerate(DIGITS):
            out.append((f"{p}_n_{i}", voice, w, "tok"))
        for i, w in enumerate(NATO):
            out.append((f"{p}_l_{chr(97 + i)}", voice, w, "tok"))
        for d in DIRS:
            out.append((f"{p}_d_{d}", voice, DIR_SPOKEN.get(d, d), "tok"))
        for suf, _, sp in label_keys():
            out.append((f"{p}_{suf}", voice, sp, "tok"))
        for o, sp in ORDS.items():
            out.append((f"{p}_ord_{slug(o)}", voice, sp, "tok"))
        out.append((f"{p}_egress", voice, eg_sp, "tok"))
        for k, (_, sp) in JP.items():
            t = sp.replace("{S}", me_sp)
            out.append((f"{p}_{k}", voice, t, "tok:0.1" if t.endswith(",") else "tok"))
    for k, (_, sp) in PILOT.items():
        out.append((k, "PILOT", sp, "tok:0.1" if sp.endswith(",") else "tok"))
    for k, (_, sp) in OVL.items():
        out.append((k, "OVERLORD", sp, "tok"))
    return out


def lua_dict():
    def q(s):
        return '"' + s.replace('"', '\\"') + '"'
    jt = {}
    for k, (w, _) in JP.items():
        if w:
            jt[w] = k
    for suf, w, _ in label_keys():
        jt[w] = suf
    for o in ORDS:
        jt[norm(o)] = "ord_" + slug(o)
    pl = {w: k for k, (w, _) in PILOT.items()}
    ov = {w: k for k, (w, _) in OVL.items()}
    maxlen = max(len(w.split()) for w in list(jt) + list(pl) + list(ov))
    L = [LBEGIN, "-- generated by tools/jc_clips.py v1.0.0 - do not edit by hand", "local VOICE = {"]
    L.append("    maxlen = %d," % maxlen)
    L.append("    egress = { pj = %s, ej = %s }," % (q(JTACS["pj"][3]), q(JTACS["ej"][3])))
    L.append("    jtac = {   -- written key ({s} = own call sign) -> suffix (<prefix>_<suffix>)")
    for w in sorted(jt):
        L.append("        [%s] = %s," % (q(w), q(jt[w])))
    L.append("    },")
    L.append("    pilot = {")
    for w in sorted(pl):
        L.append("        [%s] = %s," % (q(w), q(pl[w])))
    L.append("    },")
    L.append("    ovl = {")
    for w in sorted(ov):
        L.append("        [%s] = %s," % (q(w), q(ov[w])))
    L.append("    },")
    L.append("}")
    L.append(LEND)
    return "\n".join(L)


def write_csv():
    lines = open(CSV, encoding="utf-8").read().split("\n")
    if BEGIN in lines:
        a, b = lines.index(BEGIN), lines.index(END)
        lines = lines[:a] + lines[b + 1:]
    while lines and lines[-1] == "":
        lines.pop()
    mine = rows()
    other = {l.split(";")[0].strip() for l in lines if l.strip() and not l.startswith("#")}
    clash = sorted(other & {r[0] for r in mine})
    if clash:
        sys.exit("clip id clash with existing clips.csv rows: " + ", ".join(clash))
    if len({r[0] for r in mine}) != len(mine):
        sys.exit("duplicate JC clip ids")
    block = [BEGIN] + [";".join(r) for r in mine] + [END]
    open(CSV, "w", encoding="utf-8", newline="\n").write("\n".join(lines + block) + "\n")
    print("clips.csv: %d JC rows" % (len(block) - 2))


def write_lua():
    s = open(JC, encoding="utf-8").read()
    a, b = s.find(LBEGIN), s.find(LEND)
    if a < 0 or b < 0:
        sys.exit("VOICE block markers not found in JTAC_Controller.lua")
    s = s[:a] + lua_dict() + s[b + len(LEND):]
    open(JC, "w", encoding="utf-8", newline="").write(s)
    print("JTAC_Controller.lua: VOICE block written")


def audio_into_cd():
    cd = os.path.join(REPO, "scripts", "Comms_Director.lua")
    tab = open(os.path.join(REPO, "tts", "audio_table.lua"), encoding="utf-8").read()
    body = [l.strip() for l in tab.split("\n") if re.match(r"\s*[A-Za-z0-9_]+\s*=\s*\{\s*ch\s*=", l)]
    s = open(cd, encoding="utf-8").read()
    m = re.search(r"(\n    AUDIO = \{\n)(.*?)(\n    \},)", s, re.S)
    if not m:
        sys.exit("CFG.AUDIO block not found in Comms_Director.lua")
    s = s[:m.start(2)] + "\n".join("        " + l for l in body) + s[m.end(2):]
    open(cd, "w", encoding="utf-8", newline="").write(s)
    print("Comms_Director CFG.AUDIO: %d entries" % len(body))


if __name__ == "__main__":
    if "--audio-into-cd" in sys.argv:
        audio_into_cd()
    elif "--ids" in sys.argv:
        print(" ".join(r[0] for r in rows()))
    else:
        write_csv()
        write_lua()
