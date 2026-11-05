# itg_p1.py | v1.0.0
# Into The Grey P1 (2026-11-05, plan: project doc claude/itg-s2s-migration-plan-2026-11-05.md): moves the ITG ME
# layer (missions/ITG/src) onto the shared SEA2STEEL modules. One-off and idempotent: refuses to run twice
# (marker = a trigger named "CASE SELECTOR").
#
#   python tools/itg_p1.py            # edit missions/ITG/src/{mission, l10n/DEFAULT/mapResource}
#   python tools/itg_p1.py -n         # dry run: report only
#
# What it does
#   1. Script triggers rebuilt in SEA2STEEL order. Old: [1] MOOSE (Moose.lua), [2] MOOSE (inline AIRBOSS + mist +
#      Skynet), [3] OWN_SCRIPTS (CASE-III_v20, Flaggers, CASE_III_Departure, Carrier_Geometry, WingmanStrike).
#      New: CASE SELECTOR (flag 100 = 3 departure, 102 = 3 recovery) | MOOSE (Moose_2026-06-14, mist, ITG_Pack,
#      Menu_Manager, Skynet x3, Airboss_Start, Airboss_CaseSync) | OWN_SCRIPTS (Core_Scoring, Deck_Park,
#      Recovery_Approach, Departure, Overspeed, CV_Comms, PlaneCaptain_Carrier, Score_Display, Missile_Defense,
#      Radio_Log, AAR_Monitor, Flaggers v1, WingmanStrike_V10) | Distance & Radial (Carrier_Geometry_v1, shared).
#      CASE-III_v20, CASE_III_Departure, the old Moose.lua and the inline AIRBOSS script leave the mission.
#   2. New triggers: LIGHT MODE (flag 100 = 3 -> carrier lights mode 2) and Commence Recovery (flag 101 = 3 at
#      DME 51 inbound, only after a target is dead - the outbound leg passes 51 NM too).
#   3. Score gates (flag 1908 > n) replaced: Core_Scoring's scale differs from CASE-III_v20's. Recovery Tanker
#      Activation: Marshal_Zone only. Fence Out / Fly to tanker / Larnaca / Inbound mom: their zone or DME AND a
#      target dead (STRIKE1_TRG1 or TRG2).
#   4. Hero group CAS-1 -> HORNET-5 (unit names unchanged).
#   5. 305.00 left to HORNET-5 (COMM2 btn 1, intra-flight): the other AI groups on 305 move to 290-297.
#   6. Player_01 / Player_02 COMM1 presets -> CV button plan (ITG_Pack.lua header).
#   7. Deck park zone CV_PARK_01 (Deck_Park) copied from the template, same spot on the carrier deck.

import argparse
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

SRC = os.path.join(REPO, 'missions', 'ITG', 'src')
TPL = os.path.join(REPO, 'src', 'mission')
MISSION = os.path.join(SRC, 'mission')
MAPRES = os.path.join(SRC, 'l10n', 'DEFAULT', 'mapResource')

MOOSE_SCRIPTS = ['Moose_2026-06-14.lua', 'mist_4_5_126.lua', 'ITG_Pack.lua', 'Menu_Manager.lua',
                 'skynet-iads-compiled.lua', 'Skynet_Init_Main.lua', 'myIADS_v9_fixed.lua',
                 'Airboss_Start.lua', 'Airboss_CaseSync.lua']
OWN_SCRIPTS = ['Core_Scoring.lua', 'Deck_Park.lua', 'Recovery_Approach.lua', 'Departure.lua',
               'Overspeed_Penalty_In_Marshal_Zone_v7.lua', 'CV_Comms.lua', 'PlaneCaptain_Carrier.lua',
               'Score_Display.lua', 'Missile_Defense.lua', 'Radio_Log.lua', 'AAR_Monitor.lua',
               'Flaggers v1.lua', 'WingmanStrike_V10.lua']
GEOMETRY = 'Carrier_Geometry_v1.lua'
DROPPED = ['Moose.lua', 'CASE-III_v20.lua', 'CASE_III_Departure.lua']
OLD_SCRIPT_TRIGGERS = 3          # trigrules[1..3] = MOOSE / MOOSE / OWN_SCRIPTS (checked below)

HERO_OLD, HERO_NEW = b'CAS-1', b'HORNET-5'
FREQ_MOVE = {b'CAP-1': 290, b'CAP-2': 291, b'CAP-3': 292, b'INTER-2': 293, b'INTER-3': 294,
             b'Random-1': 295, b'Random-3': 296, b'RAT_F4E': 297}
# COMM1 button -> MHz (CV button plan + ITG nets). Buttons not listed keep their value.
COMM1 = {1: 262, 2: 269, 3: 127.6, 8: 252.5, 10: 266.6}
TARGET_UNITS = (1904, 1929)      # STRIKE1_TRG1 / STRIKE1_TRG2 (ME unit ids)
CVN_UNIT_ID = 2605
COLOR = b'0xffff00ff'


def S(b):
    return b.decode('utf-8', 'replace') if isinstance(b, bytes) else str(b)


def load(path):
    with open(path, 'rb') as f:
        return dcslua.parse(f.read())


def write(path, var, tbl):
    data = dcslua.dump(var, tbl)
    if isinstance(data, str):
        data = data.encode('utf-8')
    with open(path + '.tmp', 'wb') as f:
        f.write(data)
    os.replace(path + '.tmp', path)


def iter_groups(m):
    for side, cs in m[b'coalition'].items():
        for c in (cs.get(b'country') or {}).values():
            for cat in (b'plane', b'helicopter', b'vehicle', b'ship', b'static'):
                for g in ((c.get(cat) or {}).get(b'group') or {}).values():
                    yield side, cat, g


def find_unit(m, name):
    for *_, g in iter_groups(m):
        for u in g[b'units'].values():
            if u[b'name'] == name:
                return u
    return None


# ---- compiled trigger strings (same shapes the ME writes; see SEA2STEEL src/mission) ----------------------
def c_cond(rules):
    """rules: list of rule dicts (with 'or' separators) -> 'return(... )'"""
    if not rules:
        return b'return(true)'
    groups, cur = [], []
    for r in rules:
        if r[b'predicate'] == b'or':
            groups.append(cur)
            cur = []
        else:
            cur.append(r)
    groups.append(cur)

    def one(r):
        p = r[b'predicate']
        if p == b'c_flag_equals':
            return b'c_flag_equals("%s", %d)' % (r[b'flag'], r[b'value'])
        if p == b'c_unit_dead':
            return b'c_unit_dead(%d)' % r[b'unit']
        if p == b'c_unit_in_zone':
            return b'c_unit_in_zone(%d, %d)' % (r[b'unit'], r[b'zone'])
        raise ValueError(p)
    return b'return(' + b' or '.join(b' and '.join(one(r) for r in g) for g in groups) + b' )'


def c_action(a):
    p = a[b'predicate']
    if p == b'a_do_script_file':
        return b'a_do_script_file(getValueResourceByKey("%s"));' % a[b'file']
    if p == b'a_set_flag_value':
        return b'a_set_flag_value("%s", %d);' % (a[b'flag'], a[b'value'])
    if p == b'a_set_carrier_illumination_mode':
        return b'a_set_carrier_illumination_mode(%d, %d);' % (a[b'unit'], a[b'lightsMode'])
    raise ValueError(p)


def make_rule(comment, pred, rules, actions):
    r = {b'actions': {i + 1: a for i, a in enumerate(actions)}, b'colorItem': COLOR, b'comment': comment,
         b'eventlist': b'', b'predicate': pred, b'rules': {i + 1: x for i, x in enumerate(rules)}}
    return r


def compile_rule(k, r):
    acts = b''.join(c_action(r[b'actions'][i]) for i in sorted(r[b'actions']))
    pred = r[b'predicate']
    out = {'conditions': c_cond([r[b'rules'][i] for i in sorted(r[b'rules'])])}
    if pred == b'triggerStart':
        out['actions'] = acts
        out['funcStartup'] = b'if mission.trig.conditions[%d]() then mission.trig.actions[%d]() end' % (k, k)
    elif pred == b'triggerOnce':
        out['actions'] = acts + b' mission.trig.func[%d]=nil;' % k
        out['func'] = b'if mission.trig.conditions[%d]() then mission.trig.actions[%d]() end' % (k, k)
    elif pred == b'triggerFront':
        out['actions'] = acts
        out['func'] = (b'if mission.trig.conditions[%d]() then if not mission.trig.flag[%d] then '
                       b'mission.trig.actions[%d](); mission.trig.flag[%d] = true;end; else '
                       b'mission.trig.flag[%d] = false; end;' % (k, k, k, k, k))
    else:
        raise ValueError(pred)
    return out


TRIG_REF = re.compile(rb'mission\.trig\.(func|funcStartup|conditions|actions|flag)\[(\d+)\]')


def dead_or(extra):
    """[extra..., dead TRG1, OR, extra..., dead TRG2]"""
    out = []
    for i, u in enumerate(TARGET_UNITS):
        if i:
            out.append({b'predicate': b'or'})
        out += [dict(x) for x in extra] + [{b'predicate': b'c_unit_dead', b'unit': u}]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-n', '--dry-run', action='store_true')
    args = ap.parse_args()

    _, m = load(MISSION)
    _, mr = load(MAPRES)
    R, T = m[b'trigrules'], m[b'trig']
    if any(r[b'comment'] == b'CASE SELECTOR' for r in R.values()):
        sys.exit('itg_p1: already applied (trigger "CASE SELECTOR" exists)')
    if [R[i][b'comment'] for i in (1, 2, 3)] != [b'MOOSE', b'MOOSE', b'OWN_SCRIPTS']:
        sys.exit('itg_p1: trigrules[1..3] are not MOOSE / MOOSE / OWN_SCRIPTS - unexpected mission')
    log = []

    # ---- 1. mapResource keys ------------------------------------------------------------------------
    by_name = {v: k for k, v in mr.items()}
    nums = [int(x.group(1)) for k in mr for x in [re.match(rb'ResKey_[A-Za-z]+_(\d+)$', k)] if x]
    nxt = max(nums + [int(m[b'maxDictId'])])
    for name in MOOSE_SCRIPTS + OWN_SCRIPTS + [GEOMETRY]:
        nb = name.encode()
        if nb not in by_name:
            nxt += 1
            key = b'ResKey_Action_%d' % nxt
            mr[key] = nb
            by_name[nb] = key
            log.append('mapResource + %s = %s' % (S(key), name))
    m[b'maxDictId'] = nxt
    for name in DROPPED:
        k = by_name.pop(name.encode(), None)
        if k:
            del mr[k]
            log.append('mapResource - %s (%s)' % (S(k), name))

    def scripts(names):
        return [{b'file': by_name[n.encode()], b'predicate': b'a_do_script_file'} for n in names]

    new_head = [
        make_rule(b'CASE SELECTOR', b'triggerStart', [],
                  [{b'flag': b'100', b'predicate': b'a_set_flag_value', b'value': 3},
                   {b'flag': b'102', b'predicate': b'a_set_flag_value', b'value': 3}]),
        make_rule(b'MOOSE', b'triggerStart', [], scripts(MOOSE_SCRIPTS)),
        make_rule(b'OWN_SCRIPTS', b'triggerStart', [], scripts(OWN_SCRIPTS)),
        make_rule(b'Distance & Radial', b'triggerOnce', [], scripts([GEOMETRY])),
        make_rule(b'LIGHT MODE', b'triggerOnce', [{b'flag': b'100', b'predicate': b'c_flag_equals', b'value': 3}],
                  [{b'lightsMode': 2, b'predicate': b'a_set_carrier_illumination_mode', b'unit': CVN_UNIT_ID}]),
        make_rule(b'Commence Recovery', b'triggerFront',
                  dead_or([{b'flag': b'6550', b'predicate': b'c_flag_equals', b'value': 51}]),
                  [{b'flag': b'101', b'predicate': b'a_set_flag_value', b'value': 3}]),
    ]
    old_keep = [k for k in sorted(R) if k > OLD_SCRIPT_TRIGGERS]
    renum = {old: len(new_head) + i + 1 for i, old in enumerate(old_keep)}

    newR, newT = {}, {sec: {} for sec in T}
    for i, r in enumerate(new_head):
        k = i + 1
        newR[k] = r
        for sec, v in compile_rule(k, r).items():
            newT[sec.encode()][k] = v
        newT[b'flag'][k] = True
    for old in old_keep:
        k = renum[old]
        newR[k] = R[old]
        for sec in T:
            if old in T[sec]:
                v = T[sec][old]
                if isinstance(v, bytes):
                    v = TRIG_REF.sub(lambda mm: b'mission.trig.%s[%d]' % (mm.group(1), renum[int(mm.group(2))]), v)
                newT[sec][k] = v
    log.append('triggers: %d old script triggers -> %d new; %d kept, renumbered %d..%d'
               % (OLD_SCRIPT_TRIGGERS, len(new_head), len(old_keep), len(new_head) + 1, len(newR)))

    # ---- 3. score gates ------------------------------------------------------------------------------
    for k, r in newR.items():
        rs = [r[b'rules'][i] for i in sorted(r[b'rules'])]
        if not any(x.get(b'flag') == b'1908' for x in rs):
            continue
        rest = [x for x in rs if x.get(b'flag') != b'1908']
        if any(x[b'predicate'] == b'or' for x in rest):
            sys.exit('itg_p1: score gate inside an OR rule: %s' % S(r[b'comment']))
        if r[b'comment'].startswith(b'Recovery Tanker'):
            new = rest
        else:
            new = dead_or(rest)
        r[b'rules'] = {i + 1: x for i, x in enumerate(new)}
        newT[b'conditions'][k] = c_cond(new)
        log.append('score gate [%d] %s: %s' % (k, S(r[b'comment']), S(newT[b'conditions'][k])))

    m[b'trigrules'], m[b'trig'] = newR, newT

    # ---- 4./5. groups ------------------------------------------------------------------------------
    for _side, cat, g in iter_groups(m):
        if g[b'name'] == HERO_OLD:
            g[b'name'] = HERO_NEW
            log.append('group CAS-1 -> HORNET-5')
        if cat in (b'plane', b'helicopter') and g[b'name'] in FREQ_MOVE:
            f = FREQ_MOVE[g[b'name']]
            log.append('group %s frequency %s -> %d' % (S(g[b'name']), g.get(b'frequency'), f))
            g[b'frequency'] = f

    # ---- 6. COMM1 presets ----------------------------------------------------------------------------
    for name in (b'Player_01', b'Player_02'):
        u = find_unit(m, name)
        if b'Radio' not in u:              # AI wingman: no cockpit presets
            continue
        ch = u[b'Radio'][1][b'channels']
        old = {b: ch.get(b) for b in COMM1}
        for b, f in COMM1.items():
            ch[b] = f
        log.append('%s COMM1 %s -> %s' % (S(name), old, COMM1))

    # ---- 7. CV_PARK_01 -----------------------------------------------------------------------------
    _, t = load(TPL)
    tz = next(z for z in t[b'triggers'][b'zones'].values() if z[b'name'] == b'CV_PARK_01')
    tc, ic = find_unit(t, b'CVN'), find_unit(m, b'CVN')
    dx, dy, h0 = tz[b'x'] - tc[b'x'], tz[b'y'] - tc[b'y'], tc[b'heading']
    fwd = dx * math.cos(h0) + dy * math.sin(h0)
    stb = -dx * math.sin(h0) + dy * math.cos(h0)
    h1 = ic[b'heading']
    zones = m[b'triggers'][b'zones']
    if not any(z[b'name'] == b'CV_PARK_01' for z in zones.values()):
        zid = max(max(z[b'zoneId'] for z in zones.values()) + 1, int(m[b'maxDictId']) + 1)
        nz = dict(tz)
        nz[b'x'] = ic[b'x'] + fwd * math.cos(h1) - stb * math.sin(h1)
        nz[b'y'] = ic[b'y'] + fwd * math.sin(h1) + stb * math.cos(h1)
        nz[b'zoneId'] = zid
        zones[max(zones) + 1] = nz
        m[b'maxDictId'] = max(int(m[b'maxDictId']), zid)
        log.append('zone CV_PARK_01 id %d: %.1f m fwd / %.1f m stbd of CVN' % (zid, fwd, stb))

    for line in log:
        print(line)
    if args.dry_run:
        print('dry run: nothing written')
        return 0
    write(MISSION, 'mission', m)
    write(MAPRES, 'mapResource', mr)
    print('written: missions/ITG/src/mission, mapResource')
    return 0


if __name__ == '__main__':
    sys.exit(main())
