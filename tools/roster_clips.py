# roster_clips.py | v1.1.1
# v1.1.1: Pointer / Eyeball get the ROWS they lack from the other one (Eyeball diverted for a TIC with the random
#         pair: p_divert_eye / eye_divert_ack / ovl_resume_eye; Pointer: ptr_laser_*), scenario_test live_18 / 20.
# v1.1.0 (P4, XCAS + any pair): rows for EVERY roster JTAC (Pointer / Eyeball too), written from scratch (ALL_ROWS):
#         ovl_dv_<cn> / ovl_adv_<ck> / ovl_dvu_<ck> (C divert for any pair), p_ovl_off_x_<ck> / ovl_lc_dn_<ck> (the
#         mission number is chained from digit clips after them); plus the XCAS tokens (XCAS_ROWS).
# Comms_Director / OVERLORD / pilot / Bravo 2-1 clips of the JTACs beyond Pointer 11 and Eyeball 11 (JTAC roster
# P3, plan claude/jtac-roster-effects-plan-2026-11-04.md). ONE source: each row is an existing Eyeball 11 row (or a
# Pointer 11 row for the C divert, where the diverted JTAC is slot 1) with call sign, short name, buttons and
# mission number replaced from scripts/CAS_Pack.lua. Ids follow Comms_Director v1.10.0: <ck>_* / p_*_<ck> /
# fr_<ck>_* / ovl_*_<ck>, ovl_contact_<cn>_b, ovl_tic_<cn>_b, p_ovl_off_<cn>_a; pilot p_push_<btn> / p_push_<alt> /
# p_tic_push_<btn> for the roster JTACs' buttons.
#   python tools/roster_clips.py        writes the block "# BEGIN ROSTER (tools/roster_clips.py)" .. "# END ROSTER"
#                                       into tts/clips.csv (before the JC block), prints the ids
#   then: python tts/make_clips.py --missing; python tools/jc_clips.py --audio-into-cd
# The JTAC_Controller token clips (aj_* / dj_*) and the jp_*_<ck> pilot rows come from tools/jc_clips.py.
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
sys.path.insert(0, HERE)
from check_pack import load_pack  # noqa: E402

CSV = os.path.join(REPO, "tts", "clips.csv")
BEGIN, END = "# BEGIN ROSTER (tools/roster_clips.py)", "# END ROSTER"
JC_BEGIN = "# BEGIN JC (tools/jc_clips.py)"
SPOKEN = {"darknight": "Dark Knight"}   # spoken short name where the written one is misheard (2026-11-04 test)
NUM = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "niner"]
BTN = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten",
       11: "eleven", 12: "twelve", 13: "thirteen", 14: "fourteen", 15: "fifteen", 16: "sixteen", 17: "seventeen",
       18: "eighteen", 19: "nineteen", 20: "twenty"}
SKIP = {"J1", "J2"}   # their clips are hand-written rows of clips.csv

# new id template, source id, source JTAC key (J2 Eyeball / J1 Pointer)
ROWS = [
    ("{ck}_tic", "eye_tic", "J2"), ("{ck}_tic_ack", "eye_tic_ack", "J2"),
    ("fr_{ck}_1", "fr_eye_1", "J2"), ("fr_{ck}_2", "fr_eye_2", "J2"), ("fr_{ck}_3", "fr_eye_3", "J2"),
    ("fr_{ck}_4", "fr_eye_4", "J2"), ("fr_{ck}_bda", "fr_eye_bda", "J2"),
    ("{ck}_t1", "eye_t1", "J2"), ("{ck}_t2", "eye_t2", "J2"), ("{ck}_t3", "eye_t3", "J2"), ("{ck}_t4", "eye_t4", "J2"),
    ("{ck}_bda", "eye_bda", "J2"), ("{ck}_rb_ok", "eye_rb_ok", "J2"),
    ("{ck}_laser_on", "eye_laser_on", "J2"), ("{ck}_laser_shift", "eye_laser_shift", "J2"),
    ("{ck}_laser_off", "eye_laser_off", "J2"),
    ("p_rb_{ck}", "p_rb_eye", "J2"), ("p_rel_{ck}", "p_rel_eye", "J2"), ("p_tic_copy_{ck}", "p_tic_copy_eye", "J2"),
    ("p_unable_{ck}", "p_unable_eye", "J2"),
    ("ovl_contact_{cn}_b", "ovl_contact_eyeball_b", "J2"),
    ("ovl_tic_{cn}_b", "ovl_tic_eyeball_c", "J2"),        # CD v1.10.0: "_b" for the roster (J2 keeps "_c")
    ("p_ovl_off_{cn}_a", "p_ovl_off_eyeball_a", "J2"),
    ("ovl_lc_alt_{ck}", "ovl_lc_alt_eye", "J2"), ("ovl_lc_down_{ck}", "ovl_lc_down_eye", "J2"),
    ("p_divert_{ck}", "p_divert_ptr", "J1"), ("{ck}_divert_ack", "ptr_divert_ack", "J1"),
    ("ovl_resume_{ck}", "ovl_resume_ptr", "J1"),
]


# v1.1.0: id template, agency, text ({CS} spoken call sign, {BTN} primary button word)
ALL_ROWS = [
    ("ovl_dv_{cn}", "OVERLORD", "{CS} reports troops in contact, priority immediate. Contact {CS}, push button {BTN}, "
                                "without delay.", "tok:0.1"),
    ("ovl_adv_{ck}", "OVERLORD", "{CS} is advised.", "tok"),
    ("ovl_dvu_{ck}", "OVERLORD", "Hornet five one, Overlord, copy. Continue with {CS}.", "tok"),
    ("p_ovl_off_x_{ck}", "PILOT", "Overlord, Hornet five one, off {CS}, mission", "tok:0.05"),
    ("ovl_lc_dn_{ck}", "OVERLORD", "Hornet five one, Overlord. {CS} is off the net, unable to raise. Mission", "tok:0.05"),
]
XCAS_ROWS = [   # v1.1.0 XCAS (Comms_Director >= v1.11.0)
    ("p_ovl_checkin_x", "PILOT", "Overlord, Hornet five one, checking in as fragged, X CAS,", "tok:0.1"),
    ("ovl_ci_xcas", "OVERLORD", "Mission as fragged, close air support on call. Proceed C P Tiger,", "tok:0.1"),
    ("o_mission", "OVERLORD", "Mission", "tok:0.05"),
    ("o_cancelled", "OVERLORD", "cancelled.", "tok"),
    ("p_mission", "PILOT", "Mission", "tok:0.05"),
    ("p_complete", "PILOT", "complete,", "tok:0.1"),
]


def spoken_cs(j):
    short = SPOKEN.get(j["short"].lower(), j["short"])
    num = " ".join(NUM[int(c)] for c in j["cs"].split()[-1])
    return short, "%s %s" % (short, num)


def msn_words(m):
    return " ".join(NUM[int(c)] for c in m)


def convert(text, agency, src, dst):
    s_short, s_cs = spoken_cs(src)
    d_short, d_cs = spoken_cs(dst)
    t = text.replace(s_cs, d_cs)
    t = re.sub(r"\b%s\b" % re.escape(s_short), d_short, t)
    t = t.replace("push button %s" % BTN[src["btn"]], "push button %s" % BTN[dst["btn"]])
    t = t.replace("on alternate, push button %s" % BTN[dst["btn"]], "on alternate, push button %s" % BTN[dst["alt"]["btn"]])
    t = t.replace("on alternate, push button %s" % BTN[src["alt"]["btn"]], "on alternate, push button %s" % BTN[dst["alt"]["btn"]])
    t = t.replace(msn_words(src["msn"]), msn_words(dst["msn"]))
    voice, _, ch = agency.partition(">")
    if not ch:
        ch, voice = voice, ""
    if ch == src["ch"]:
        ch = dst["ch"]
    if voice in ("POINTER_JC", "POINTER", "EYEBALL") or (not voice and ch == dst["ch"]):
        agency = dst["ch"]                    # the JTAC's own voice
    else:
        agency = (voice + ">" + ch) if voice else ch
    return t, agency


def rows(p, have):
    out = []
    for k in p["order"]:                                  # v1.1.0 every roster JTAC
        j = p["jtacs"][k]
        cs = spoken_cs(j)[1]
        for tid, ag, text, mode in ALL_ROWS:
            out.append((tid.format(ck=j["ck"], cn=j["cn"]), ag, text.format(CS=cs, BTN=BTN[j["btn"]]), mode))
    out += [r for r in XCAS_ROWS if r[0] not in have]
    for k in p["order"]:
        j = p["jtacs"][k]
        for tid, sid, sk in ROWS:
            if k in SKIP and (sk == k or tid.format(ck=j["ck"], cn=j["cn"]) in have):
                continue                              # v1.1.1 J1 / J2: only the rows they lack
            if sid not in have:
                sys.exit("source row %s missing in clips.csv" % sid)
            text, agency, mode = have[sid]
            t, ag = convert(text, agency, p["jtacs"][sk], j)
            if ag == "POINTER":
                ag = "POINTER_JC>POINTER"             # v1.1.1 Pointer's current voice (make_clips v1.10.0)
            out.append((tid.format(ck=j["ck"], cn=j["cn"]), ag, t, mode))
        if k in SKIP:
            continue
        for b in (j["btn"], j["alt"]["btn"]):         # pilot "push button N" readbacks (Comms_Director Ack)
            if "p_push_%d" % b not in have:
                out.append(("p_push_%d" % b, "PILOT", "Push button %s, Hornet five one." % BTN[b], "tok"))
        if "p_tic_push_%d" % j["btn"] not in have:
            out.append(("p_tic_push_%d" % j["btn"], "PILOT>OVERLORD",
                        "Push button %s, Hornet five one, buster." % BTN[j["btn"]], "tok"))
    return out


def main():
    p = load_pack()
    lines = open(CSV, encoding="utf-8").read().split("\n")
    if BEGIN in lines:
        a, b = lines.index(BEGIN), lines.index(END)
        lines = lines[:a] + lines[b + 1:]
    have = {}
    for ln in lines:
        if ln.strip() and not ln.startswith("#"):
            f = ln.split(";")
            have[f[0].strip()] = (f[1].strip(), f[2].strip(), f[3].strip() if len(f) > 3 else "")
    have = {k: (v[1], v[0], v[2]) for k, v in have.items()}   # id -> (text, agency, mode)
    mine = rows(p, have)
    clash = sorted(set(have) & {r[0] for r in mine})
    if clash:
        sys.exit("clip id clash: " + ", ".join(clash))
    block = [BEGIN] + [";".join(r) for r in mine] + [END]
    i = lines.index(JC_BEGIN) if JC_BEGIN in lines else len(lines)
    lines = lines[:i] + block + lines[i:]
    open(CSV, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("clips.csv: %d roster rows" % len(mine))
    print(" ".join(r[0] for r in mine))


if __name__ == "__main__":
    main()
