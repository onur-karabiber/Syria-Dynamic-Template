# flight_report.py | v1.1.0
# v1.1.0: badges shown with Onur's art (tools/score_cards/src_art/badges/<ID>.png, embedded as data URIs).
# Full flight report (HTML, one self-contained file) from dcs.log, decision Onur 2026-11-02
# (project doc claude/report-card-design-2026-11-02.md). DCS cannot write files itself (io/lfs sanitized), so
# Flight_Report.lua (>= v1.0.0) writes one "[FR] JSON {...}" line at the end of the sortie and this tool turns
# it, plus the rest of the log (timing debrief, fuel ladder, AAR rows, JTAC events, LSO / Bankler lines, ROE
# report, radio transcript), into a report.
#
#   python tools/flight_report.py                       # %USERPROFILE%\Saved Games\DCS\Logs\dcs.log
#   python tools/flight_report.py "<path>\dcs.log" -o report.html
#   python tools/flight_report.py --all                 # one report per sortie found in the log
# Default output: <log folder>\FlightReports\flight_report_<log date>_<n>.html
# Without an [FR] JSON line (older scripts) the score part is rebuilt from the "[Core_Scoring] SCORE" lines.

import argparse
import base64
import html
import json
import os
import re
import sys

GROUPS = [("LAUNCH", "Launch & departure"), ("TIMING", "Mission timing"), ("AAR", "Aerial refuelling"),
          ("CAS", "VUL / CAS procedure"), ("KILL", "Targets"), ("THREAT", "Threat avoidance"),
          ("ROE", "ROE / friendly fire"), ("RECOVERY", "Recovery"), ("TRAP", "Trap & deck"),
          ("DIVERT", "Divert"), ("MISSION", "Mission events")]
CAT_RULES = [  # Core_Scoring v1.5.x CAT_RULES (fallback when the log has no category)
    (r"^MISSION EVENT", "MISSION"), (r"^FRIENDLY FIRE", "ROE"), (r"^ROE", "ROE"), (r"^READBACK", "CAS"),
    (r"^TARGET DESTROYED", "KILL"), (r"^JTAC TARGET GROUP", "KILL"), (r"^MISSILE DEFEATED", "THREAT"),
    (r"^ASSET LOST", "ASSET"), (r"^Aerial Refuel", "AAR"), (r"^TIMING", "TIME"), (r"^Departure", "DEP"),
    (r"^Divert", "DIVERT"), (r"land-based", "DIVERT"), (r"^Carrier landing", "TRAP"),
    (r"^Successful carrier", "TRAP"), (r"^Groove fuel", "TRAP"), (r"^Fuel state", "TRAP"), (r"^Deck park", "TRAP"),
    (r"^MARSHAL ZONE", "RECOVERY"), (r"^Established", "RECOVERY"), (r"^Commenced", "RECOVERY"),
    (r"^No established", "RECOVERY"), (r"^No commencing", "RECOVERY"), (r"12NM", "RECOVERY"),
    (r"10NM", "RECOVERY"), (r"^Initial Fix", "RECOVERY"), (r"^Holding", "RECOVERY")]
CAT2GROUP = {"DEP": "LAUNCH", "AAR": "AAR", "CAS": "CAS", "KILL": "KILL", "THREAT": "THREAT", "ROE": "ROE",
             "RECOVERY": "RECOVERY", "TRAP": "TRAP", "DIVERT": "DIVERT", "MISSION": "MISSION", "OTHER": "MISSION",
             "ASSET": "MISSION"}
DISP = {0: "none", 1: "Letter of Instruction", 2: "Letter of Reprimand + FNAEB",
        3: "JAGMAN investigation, court-martial possible"}

RE_TS = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.\d+ \S+\s+SCRIPTING \(Main\): (.*)$")
RE_SCORE = re.compile(r"^\[Core_Scoring\] SCORE ([+-]\d+) \(total (-?\d+)\) (?:\[(\w+)\] )?(.*)$")
RE_FUEL = re.compile(r"^\[TL\] FUEL (\d\d:\d\d:\d\d)L lb=(\d+).*?distCVN=([\d.]+).*?alt=(\d+) gs=(\d+).*?phase=(\w+)")


def category(reason):
    for pat, cat in CAT_RULES:
        if re.search(pat, reason):
            return cat
    return "OTHER"


def group_of(cat, reason):
    if cat == "TIME":
        return "LAUNCH" if re.match(r"^TIMING (M1|M2|T1)", reason) else "TIMING"
    return CAT2GROUP.get(cat, "MISSION")


def read_lines(path):
    out = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            m = RE_TS.match(raw.rstrip("\n"))
            if m:
                out.append((m.group(1), m.group(2)))
            elif out and not re.match(r"^\d{4}-\d\d-\d\d ", raw):   # continuation of a multi-line message
                out[-1] = (out[-1][0], out[-1][1] + "\n" + raw.rstrip("\n"))
    return out


def sorties(lines):
    """Split at "[TL] BIRTH" / "[Departure] armed" after a report, or at a mission load; last chunk last."""
    starts = [i for i, (_, m) in enumerate(lines) if m.startswith("[TL] BIRTH")]
    if not starts:
        return [lines]
    starts[0] = 0
    return [lines[a:b] for a, b in zip(starts, starts[1:] + [len(lines)])]


def build(chunk):
    D = {"fr": None, "scores": [], "fuel": [], "tl": [], "aar": [], "jc": [], "radio": [], "lso": [], "bankler": [],
         "report": None, "losses": [], "incidents": []}
    for ts, m in chunk:
        if m.startswith("[FR] JSON "):
            try:
                D["fr"] = json.loads(m[10:])
            except ValueError:
                pass
        elif m.startswith("[Core_Scoring] SCORE"):
            s = RE_SCORE.match(m)
            if s:
                reason = s.group(4)
                cat = s.group(3) or category(reason)
                D["scores"].append({"ts": ts, "d": int(s.group(1)), "total": int(s.group(2)), "cat": cat, "reason": reason})
        elif m.startswith("[Core_Scoring] REPORT"):
            D["report"] = m.split("\n", 1)[1] if "\n" in m else m
        elif m.startswith("[Core_Scoring] MISSION LOSS"):
            D["losses"].append(m[15:])
        elif m.startswith("[Core_Scoring] INCIDENT") or m.startswith("[JC] INCIDENT"):
            D["incidents"].append(m)
        elif m.startswith("[TL] FUEL ") and "INIT" not in m:
            f = RE_FUEL.match(m)
            if f:
                D["fuel"].append((f.group(1), int(f.group(2)), float(f.group(3)), int(f.group(4)), int(f.group(5)), f.group(6)))
        elif m.startswith("[TL] DEBRIEF"):
            D["tl"].append(m[13:])
        elif re.match(r"^\[AAR\] S\d", m) and re.search(r"[+-]\d+ ", m):
            D["aar"].append(m[6:])
        elif re.match(r"^\[JC\] (READBACK|CLEARED|RELEASE|IMPACT|ABORT|LASER ON|BDA|MISS|INCIDENT|9-LINE|GAME PLAN)", m):
            D["jc"].append((ts, m[5:]))
        elif m.startswith("[RADIO] "):
            r = re.match(r"^\[RADIO\] (\d\d:\d\d:\d\d) \S+ (.*)$", m, re.S)
            if r:
                D["radio"].append((r.group(1), r.group(2).replace(" | ", "\n")))
                if "LSO:" in r.group(2) and "PT" in r.group(2):
                    D["lso"].append(r.group(2))
        elif "Final score:" in m and "/" in m and "Break:" not in m and "\n" not in m.strip():
            D["bankler"].append(m.strip())
    return D


def summarize(D):
    """Scores, groups and grade: from [FR] JSON when present, else rebuilt from SCORE lines."""
    fr = D["fr"]
    if fr:
        S = {"src": "Flight_Report " + str(fr.get("version")), "grade": fr.get("grade"), "total": fr.get("total"),
             "earned": fr.get("earned"), "pen": fr.get("penalties"), "loss": fr.get("loss"),
             "groups": [(g["label"], g["e"], g["p"]) for g in fr.get("groups", [])],
             "lso": fr.get("lso"), "bankler": fr.get("bankler"), "disp": fr.get("disposition"),
             "badges": fr.get("badges", []), "ledger": fr.get("ledger", []), "losses": fr.get("losses", []),
             "incidents": fr.get("incidents", []), "hard_deck_s": fr.get("hard_deck_s"), "lost": fr.get("lost")}
        return S
    g = {k: [0, 0] for k, _ in GROUPS}
    earned = pen = 0
    ledger = []
    for s in D["scores"]:
        if s["cat"] == "ASSET":
            continue
        k = group_of(s["cat"], s["reason"])
        if s["d"] > 0:
            g[k][0] += s["d"]; earned += s["d"]
        else:
            g[k][1] += s["d"]; pen += s["d"]
        ledger.append({"ts": s["ts"], "d": s["d"], "cat": s["cat"], "reason": s["reason"]})
    total = D["scores"][-1]["total"] if D["scores"] else 0
    return {"src": "rebuilt from [Core_Scoring] SCORE lines (no [FR] JSON in this log)", "grade": None,
            "total": total, "earned": earned, "pen": pen, "loss": None,
            "groups": [(lab, g[k][0], g[k][1]) for k, lab in GROUPS], "lso": None, "bankler": None, "disp": None,
            "badges": [], "ledger": ledger, "losses": [], "incidents": [], "hard_deck_s": None, "lost": None}


def esc(s):
    return html.escape(str(s))


def sgn(v):
    v = round(v or 0)
    return "+%d" % v if v > 0 else str(v)


ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "score_cards", "src_art", "badges")


def badge_html(b):
    p = os.path.join(ART, "%s.png" % b.get("id"))
    if os.path.isfile(p):
        with open(p, "rb") as f:
            uri = "data:image/png;base64," + base64.b64encode(f.read()).decode()
        return '<img class=bimg src="%s" alt="%s" title="%s">' % (uri, esc(b.get("label")), esc(b.get("label")))
    return '<span class="badge %s">%s</span>' % (esc(b.get("kind")), esc(b.get("label")))


def fuel_svg(fuel):
    if len(fuel) < 2:
        return "<p class=dim>No fuel samples ([TL] FUEL).</p>"
    def sec(c):
        h, m, s = map(int, c.split(":")); return h * 3600 + m * 60 + s
    t0, t1 = sec(fuel[0][0]), sec(fuel[-1][0])
    if t1 <= t0:
        return ""
    W, H, P = 900, 260, 40
    lbmax = max(f[1] for f in fuel) * 1.1
    altmax = max(max(f[3] for f in fuel) * 1.1, 1)
    def x(c): return P + (sec(c) - t0) / (t1 - t0) * (W - 2 * P)
    def y(v, mx): return H - P - v / mx * (H - 2 * P)
    fl = " ".join("%.1f,%.1f" % (x(f[0]), y(f[1], lbmax)) for f in fuel)
    al = " ".join("%.1f,%.1f" % (x(f[0]), y(f[3], altmax)) for f in fuel)
    ticks = "".join('<text x="%.0f" y="%d" class=ax>%s</text>' % (x(f[0]), H - 12, f[0][:5])
                    for i, f in enumerate(fuel) if i % max(1, len(fuel) // 8) == 0)
    lbt = "".join('<text x="4" y="%.0f" class=ax>%dk</text>' % (y(v, lbmax), v // 1000)
                  for v in range(0, int(lbmax), 2000))
    return ('<svg viewBox="0 0 %d %d" class=chart><polyline points="%s" class=alt />'
            '<polyline points="%s" class=fuel />%s%s</svg>'
            '<p class=dim><span class=kf>&#9632;</span> fuel (lb) &nbsp; <span class=ka>&#9632;</span> altitude '
            '(scaled, max %d ft)</p>') % (W, H, al, fl, ticks, lbt, altmax / 1.1)


CSS = """
:root{--bg:#0b1219;--pan:#121c26;--line:#2b4256;--txt:#e3ebf0;--dim:#93aebf;--pos:#5fff8c;--neg:#ff5a4a;--amb:#ffc446}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--txt);font:15px/1.45 system-ui,Segoe UI,sans-serif}
main{max-width:1100px;margin:0 auto;padding:20px 16px 60px}h1{margin:0;font-size:28px;letter-spacing:.06em}
h2{font-size:17px;letter-spacing:.08em;color:var(--dim);border-bottom:1px solid var(--line);padding-bottom:4px;margin-top:34px}
.top{display:flex;justify-content:space-between;align-items:flex-end;flex-wrap:wrap;gap:12px}
.grade{font-size:34px;font-weight:800;letter-spacing:.08em}.SH{color:var(--pos)}.SAT{color:var(--amb)}.UNSAT{color:var(--neg)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px;margin-top:16px}
.card{background:var(--pan);border:1px solid var(--line);border-radius:10px;padding:12px}
.card b{display:block;font-size:30px}.dim{color:var(--dim)}.pos{color:var(--pos)}.neg{color:var(--neg)}.amb{color:var(--amb)}
table{width:100%;border-collapse:collapse}td,th{padding:5px 8px;border-bottom:1px solid #1d2c3a;text-align:left;vertical-align:top}
th{color:var(--dim);font-weight:600}th.n,td.n{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
.badges{display:flex;flex-wrap:wrap;gap:8px}.badge{padding:6px 12px;border-radius:8px;border:2px solid}
.bimg{width:200px;height:200px;object-fit:contain}.badge.A{border-color:var(--pos);background:#123a22}.badge.D{border-color:var(--neg);background:#3d1515}
pre{white-space:pre-wrap;background:var(--pan);border:1px solid var(--line);border-radius:8px;padding:10px;font-size:13px}
details summary{cursor:pointer;color:var(--dim)}.chart{width:100%;height:auto;background:var(--pan);border-radius:8px}
.chart .fuel{fill:none;stroke:var(--pos);stroke-width:2}.chart .alt{fill:none;stroke:#4b7aa0;stroke-width:1.5}
.chart .ax{fill:var(--dim);font-size:11px}.kf{color:var(--pos)}.ka{color:#4b7aa0}
@media(max-width:600px){.grade{font-size:26px}}
"""


def render(D, S, logpath, n):
    date = D["scores"][0]["ts"][:16] if D["scores"] else (D["radio"][0][0] if D["radio"] else "")
    g = S["grade"]
    gcls = {"SIERRA HOTEL": "SH", "SAT": "SAT", "UNSAT": "UNSAT"}.get(g or "", "dim")
    o = ['<!doctype html><html lang=en><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">'
         '<title>Flight Report</title><style>%s</style><main>' % CSS]
    o.append('<div class=top><div><h1>FLIGHT REPORT</h1><div class=dim>HORNET 51 · CAS-1 · %s · sortie %d · %s</div></div>'
             '<div class="grade %s">%s</div></div>' % (esc(date), n, esc(os.path.basename(logpath)), gcls, esc(g or "no grade (old log)")))
    loss = S["loss"]
    o.append('<div class=cards><div class=card><span class=dim>TOTAL</span><b>%s</b></div>'
             '<div class=card><span class=dim>EARNED</span><b class=pos>%s</b></div>'
             '<div class=card><span class=dim>PENALTIES</span><b class=neg>%s</b></div>'
             '<div class=card><span class=dim>MISSION LOSSES (not in the total)</span><b class=amb>%s</b></div></div>'
             % (esc(S["total"]), sgn(S["earned"]), sgn(S["pen"]), esc(sgn(loss) if loss else "0")))
    o.append('<p class=dim>Source: %s</p>' % esc(S["src"]))
    o.append('<h2>GROUPS</h2><table><tr><th>Group</th><th class=n>Earned</th><th class=n>Penalty</th></tr>')
    for lab, e, p in S["groups"]:
        o.append('<tr><td>%s</td><td class="n pos">%s</td><td class="n neg">%s</td></tr>' % (esc(lab), sgn(e), sgn(p)))
    o.append('</table>')
    o.append('<h2>CARRIER</h2>')
    lso, bk = S["lso"], S["bankler"]
    rows = []
    if lso:
        rows.append(("LSO grade", "%s (%s PT)" % (lso.get("grade"), lso.get("points"))))
        if lso.get("wire"): rows.append(("Wire", lso.get("wire")))
        if lso.get("tgroove"): rows.append(("Groove time", "%.1f s" % lso["tgroove"]))
        if lso.get("details"): rows.append(("LSO comments", lso.get("details")))
    for l in D["lso"][-3:]:
        rows.append(("AIRBOSS", l))
    if bk:
        rows.append(("Bankler (not in the total)", "%d / %d (%d %%)" % (bk["score"], bk["max"], round(100 * bk["score"] / max(1, bk["max"])))))
    for l in D["bankler"][-3:]:
        rows.append(("Bankler pass", l))
    o.append('<table>%s</table>' % "".join('<tr><td>%s</td><td>%s</td></tr>' % (esc(a), esc(b)) for a, b in rows)
             if rows else '<p class=dim>No graded carrier pass.</p>')
    o.append('<h2>BADGES</h2>')
    o.append('<div class=badges>%s</div>' % "".join(badge_html(b) for b in S["badges"])
             if S["badges"] else '<p class=dim>None.</p>')
    if S.get("hard_deck_s"):
        o.append('<p class=dim>Hard deck: %s s below 20,000 ft MSL in the engagement area (not scored).</p>' % esc(S["hard_deck_s"]))
    o.append('<h2>ROE / FRIENDLY FIRE</h2>')
    disp = S["disp"]
    o.append('<p>Disposition: <b class=%s>%s</b></p>' % ("neg" if (disp or 0) >= 2 else ("amb" if disp else "pos"), esc(DISP.get(disp, "n/a"))))
    if D["report"]:
        o.append('<pre>%s</pre>' % esc(D["report"]))
    elif D["incidents"]:
        o.append('<pre>%s</pre>' % esc("\n".join(D["incidents"])))
    if S["losses"] or D["losses"]:
        o.append('<h2>MISSION LOSSES</h2><pre>%s</pre>' % esc("\n".join(
            [("%s (%s)" % (l.get("name"), l.get("value"))) for l in S["losses"]] or D["losses"])))
    o.append('<h2>SCORE LEDGER</h2><table><tr><th>Time</th><th class=n>Pts</th><th>Cat.</th><th>Reason</th></tr>')
    for e in S["ledger"]:
        if e.get("ts"):
            t = e["ts"][11:16]
        else:
            sec = int(e.get("t", 0)) % 86400
            t = "%02d:%02dL" % (sec // 3600, (sec % 3600) // 60)
        cls = "pos" if e["d"] > 0 else "neg"
        o.append('<tr><td>%s</td><td class="n %s">%s</td><td>%s</td><td>%s</td></tr>' % (esc(t), cls, sgn(e["d"]), esc(e.get("cat")), esc(e.get("reason"))))
    o.append('</table>')
    o.append('<h2>FUEL &amp; ALTITUDE</h2>' + fuel_svg(D["fuel"]))
    if D["tl"]:
        o.append('<h2>TIMING DEBRIEF</h2><pre>%s</pre>' % esc("\n".join(D["tl"])))
    if D["aar"]:
        o.append('<h2>AERIAL REFUELLING</h2><pre>%s</pre>' % esc("\n".join(D["aar"])))
    if D["jc"]:
        o.append('<h2>JTAC</h2><details><summary>%d events</summary><pre>%s</pre></details>'
                 % (len(D["jc"]), esc("\n".join("%s  %s" % (t[11:], m) for t, m in D["jc"]))))
    if D["radio"]:
        o.append('<h2>RADIO</h2><details><summary>%d transmissions</summary><pre>%s</pre></details>'
                 % (len(D["radio"]), esc("\n".join("%s  %s" % r for r in D["radio"]))))
    o.append('<p class=dim>tools/flight_report.py v1.1.0</p></main></html>')
    return "\n".join(o)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", nargs="?", default=os.path.join(os.path.expanduser("~"), "Saved Games", "DCS", "Logs", "dcs.log"))
    ap.add_argument("-o", "--out")
    ap.add_argument("--all", action="store_true", help="one report per sortie in the log")
    a = ap.parse_args()
    if not os.path.isfile(a.log):
        sys.exit("no log: " + a.log)
    lines = read_lines(a.log)
    chunks = [c for c in sorties(lines) if any(m.startswith("[Core_Scoring] SCORE") or m.startswith("[FR] JSON") for _, m in c)]
    if not chunks:
        sys.exit("no scored sortie in " + a.log)
    pick = list(enumerate(chunks, 1)) if a.all else [(len(chunks), chunks[-1])]
    outdir = os.path.join(os.path.dirname(os.path.abspath(a.log)), "FlightReports")
    stamp = lines[0][0][:16].replace("-", "").replace(":", "").replace(" ", "-") if lines else "log"
    for n, c in pick:
        D = build(c)
        S = summarize(D)
        out = a.out if (a.out and not a.all) else os.path.join(outdir, "flight_report_%s_%d.html" % (stamp, n))
        os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            f.write(render(D, S, a.log, n))
        print("written", out, "|", S["src"], "| total", S["total"], "| grade", S["grade"])


if __name__ == "__main__":
    main()
