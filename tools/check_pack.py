# check_pack.py | v1.1.0
# v1.1.0 (target pool, Tasking_Pick v1.0.0): every pool group / static exists; entries after the first are late
#         activated (the first, set A, is active at start and removed by the pick when not chosen); every entry of a
#         JTAC has the unit count of its first entry (weapons budget: 2 Pointer / 4 Eyeball), else a warning;
#         entries with w > 0 are listed (a set enabled before its DCS site audit is a warning).
# Checks scripts/CAS_Pack.lua (tasking pack, 2026-11-04) against the template mission (src/mission):
#   * hero unit, hero group, carrier, tanker, JTAC groups and every JTAC target group exist
#   * cp.wp_name is a point of the hero group's route, within CP_TOL_M of cp.pos; "IP <name>" points exist
#   * every btn / freq of nets + JTAC primary / alternate = the hero's COMM1 preset (nets.OVL.comm2 = COMM2 preset)
#   * voiced values (call signs, buttons, frequencies, CP / IP names, mission numbers ...) = tts/pack_voiced.json,
#     the values the clips were rendered with: a change needs the clips re-rendered (tts/make_clips.py), then
#     --accept-voiced
# Exit 1 on an error (sync_missions.py guards stop), 0 otherwise (warnings printed).
#
#   python tools/check_pack.py [--mission <path to a mission file or .miz>] [--accept-voiced]

import argparse
import json
import math
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

PACK = os.path.join(REPO, "scripts", "CAS_Pack.lua")
VOICED = os.path.join(REPO, "tts", "pack_voiced.json")
CP_TOL_M = 50


def py(v):
    if isinstance(v, bytes):
        return v.decode("utf-8")
    if isinstance(v, dict):
        if v and all(isinstance(k, int) for k in v):
            return [py(v[k]) for k in sorted(v)]
        return {(k.decode() if isinstance(k, bytes) else k): py(x) for k, x in v.items()}
    return v


def load_pack():
    return py(dcslua.parse(open(PACK, "rb").read())[1])


def load_mission(path):
    if path.lower().endswith(".miz"):
        with zipfile.ZipFile(path) as z:
            return py(dcslua.parse(z.read("mission"))[1])
    return py(dcslua.parse(open(path, "rb").read())[1])


def index(m):
    groups, units, statics = {}, {}, set()
    for side in (m.get("coalition") or {}).values():
        for c in (side.get("country") or []):
            for cat in ("plane", "helicopter", "vehicle", "ship", "static"):
                for g in ((c.get(cat) or {}).get("group") or []):
                    groups[g["name"]] = g
                    if cat == "static":   # StaticObject.getByName takes the UNIT name
                        statics.update(u["name"] for u in g.get("units") or [])
                    for u in g.get("units") or []:
                        units[u["name"]] = u
    return groups, units, statics


def voiced(p):
    v = {"cs": p["cs"], "cp": p["cp"]["name"], "hold_angels": p["hold_angels"], "hard_deck_ft": p["hard_deck_ft"],
         "friendly": [p["friendly"]["name"], p["friendly"]["cs"]], "challenge": p["abort"]["challenge"],
         "nets": {k: [n.get("btn"), n.get("freq"), n.get("comm2")] for k, n in p["nets"].items()}}
    for k, j in p["jtacs"].items():
        v[k] = [j["cs"], j["disp"], j["short"], j["btn"], j["freq"], j["alt"]["btn"], j["alt"]["freq"], j["msn"],
                j["ip"]["name"], j["mark"]["code"]]
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mission", default=os.path.join(REPO, "src", "mission"))
    ap.add_argument("--accept-voiced", action="store_true")
    a = ap.parse_args()
    p = load_pack()
    m = load_mission(a.mission)
    groups, units, statics = index(m)
    err, warn = [], []

    for what, name in (("hero unit", p["hero"]), ("carrier", p["carrier"]), ("tanker", p["tanker"])):
        if name not in units:
            err.append("%s %r not in the mission" % (what, name))
    for name in [p["group"]] + [j["group"] for j in p["jtacs"].values()] + \
            [t for j in p["jtacs"].values() for t in j["targets"]]:
        if name not in groups:
            err.append("group %r not in the mission" % name)
    for k in p["order"]:
        if k not in p["jtacs"]:
            err.append("order: %s not in jtacs" % k)

    for k, j in p["jtacs"].items():                             # v1.1.0 target pool
        pool = j.get("pool") or []
        if not pool:
            continue
        n0 = None
        for i, e in enumerate(pool):
            cnt = 0
            for gname in e.get("targets") or []:
                g = groups.get(gname)
                if not g:
                    err.append("pool %s-%s: group %r not in the mission" % (k, e.get("id"), gname))
                    continue
                cnt += len(g.get("units") or [])
                if i > 0 and not g.get("lateActivation"):
                    err.append("pool %s-%s: group %r is not late activated" % (k, e.get("id"), gname))
            for sname in e.get("statics") or []:
                if sname not in statics:
                    err.append("pool %s-%s: static %r not in the mission" % (k, e.get("id"), sname))
            if n0 is None:
                n0 = cnt
            elif cnt != n0:
                warn.append("pool %s-%s: %d target units, entry %s has %d (weapons budget)" % (
                    k, e.get("id"), cnt, pool[0].get("id"), n0))
        on = ["%s(w %s)" % (e.get("id"), e.get("w")) for e in pool if (e.get("w") or 0) > 0]
        print("pool %s: %d entries, random over %s" % (k, len(pool), ", ".join(on) or "none (entry 1)"))

    g = groups.get(p["group"])
    if g:
        pts = (g.get("route") or {}).get("points") or []
        names = [pt.get("name") for pt in pts]
        cp = next((pt for pt in pts if pt.get("name") == p["cp"]["wp_name"]), None)
        if not cp:
            err.append("CP: no route point %r in %s (points: %s)" % (p["cp"]["wp_name"], p["group"], names))
        else:
            d = math.hypot(cp["x"] - p["cp"]["pos"]["x"], cp["y"] - p["cp"]["pos"]["z"])
            if d > CP_TOL_M:
                err.append("CP: %s route point is %.0f m from cp.pos (x %.0f z %.0f)" % (p["cp"]["name"], d, cp["x"], cp["y"]))
        for k, j in p["jtacs"].items():
            if "IP " + j["ip"]["name"] not in names:
                warn.append("IP %s (%s): no route point 'IP %s' in %s" % (j["ip"]["name"], k, j["ip"]["name"], p["group"]))

    hero = units.get(p["hero"])
    if hero:
        radio = hero.get("Radio") or []
        ch1 = (radio[0].get("channels") if len(radio) > 0 else None) or []
        ch2 = (radio[1].get("channels") if len(radio) > 1 else None) or []

        def preset(ch, btn, freq, what):
            have = ch[btn - 1] if 0 < btn <= len(ch) else None
            if have is None or abs(float(have) - float(freq)) > 0.001:
                err.append("%s: preset %d = %s, pack says %s" % (what, btn, have, freq))
        for k, n in p["nets"].items():
            if n.get("btn"):
                preset(ch1, n["btn"], n["freq"], "COMM1 " + k)
            if n.get("comm2"):
                preset(ch2, n["comm2"], n["freq"], "COMM2 " + k)
        for k, j in p["jtacs"].items():
            preset(ch1, j["btn"], j["freq"], "COMM1 %s %s" % (k, j["cs"]))
            preset(ch1, j["alt"]["btn"], j["alt"]["freq"], "COMM1 %s alternate" % k)

    v = voiced(p)
    if a.accept_voiced or not os.path.isfile(VOICED):
        with open(VOICED, "w", encoding="utf-8") as f:
            json.dump(v, f, indent=1, sort_keys=True)
            f.write("\n")
        print("voiced values recorded: %s" % os.path.relpath(VOICED, REPO))
    else:
        old = json.load(open(VOICED, encoding="utf-8"))
        changed = sorted(k for k in set(v) | set(old) if v.get(k) != old.get(k))
        if changed:
            warn.append("voiced values changed since the clips were rendered: %s -> re-render the clips "
                        "(tts/make_clips.py), then --accept-voiced" % ", ".join(changed))

    for w in warn:
        print("WARN  " + w)
    for e in err:
        print("ERROR " + e)
    print("check_pack: %d error(s), %d warning(s) (pack %s, %s)" % (len(err), len(warn), p.get("version"),
                                                                  os.path.relpath(a.mission, REPO)))
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
