# briefing.py | v1.0.0
# Mission briefing texts from briefing/<CODE>.txt (decision Onur 2026-11-05: briefings written from scratch, one
# file per mission; the file is the source - a briefing edited in the Mission Editor is overwritten next time).
#   python tools/briefing.py SDT            # briefing/SDT.txt -> src/l10n/DEFAULT/dictionary (then python build.py)
#   python tools/briefing.py SDT --check    # 0 if src/ already carries briefing/SDT.txt, 1 if not (nothing written)
# SEA2STEEL / SEA2STEEL_HOUND: tools/make_sea2steel.py (>= v1.3.0) applies briefing/STS.txt to the generated mission.
# File format: sections [sortie] [situation] [blue] [red] [neutrals] (DCS: sortie name, situation text, coalition
# tasks). Lines starting with '#' are comments. Text is kept as written, CR removed, leading / trailing blank lines
# dropped. A missing or empty section clears that field. Non-ASCII characters are refused (DCS briefing fonts).

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

BRIEFING_DIR = os.path.join(REPO, "briefing")
FIELDS = {"sortie": b"sortie", "situation": b"descriptionText", "blue": b"descriptionBlueTask",
          "red": b"descriptionRedTask", "neutrals": b"descriptionNeutralsTask"}
SECTION = re.compile(r"^\[(\w+)\]\s*$")


def path_for(code):
    return os.path.join(BRIEFING_DIR, "%s.txt" % code)


def parse(path):
    """{field: text} for every FIELDS key (missing section -> "")."""
    with open(path, encoding="utf-8") as f:
        raw = f.read().replace("\r", "")
    bad = sorted(set(ch for ch in raw if ord(ch) > 127))
    if bad:
        raise SystemExit("%s: non-ASCII characters %r" % (path, bad))
    out, cur = {k: [] for k in FIELDS}, None
    for line in raw.split("\n"):
        if line.startswith("#"):
            continue
        mm = SECTION.match(line)
        if mm:
            cur = mm.group(1)
            if cur not in FIELDS:
                raise SystemExit("%s: unknown section [%s] (one of %s)" % (path, cur, ", ".join(FIELDS)))
            continue
        if cur is None:
            if line.strip():
                raise SystemExit("%s: text before the first section: %r" % (path, line[:60]))
            continue
        out[cur].append(line)
    return {k: "\n".join(v).strip("\n") for k, v in out.items()}


def apply(mission, dictionary, texts):
    """Writes texts into the dictionary keys the mission references (the ME stores briefing fields as DictKeys);
    a field holding a literal (or nothing) is set directly in the mission. Returns the changed field names."""
    changed = []
    for name, field in FIELDS.items():
        val = texts[name].encode("utf-8")
        key = mission.get(field)
        if isinstance(key, bytes) and key.startswith(b"DictKey_"):
            if dictionary.get(key) != val:
                dictionary[key] = val
                changed.append(name)
        elif key != val:
            mission[field] = val
            changed.append(name)
    return changed


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        print("usage: python tools/briefing.py <CODE> [--check]   (CODE = SDT; STS is applied by make_sea2steel.py)")
        return 2
    texts = parse(path_for(args[0]))
    mpath, dpath = os.path.join(REPO, "src", "mission"), os.path.join(REPO, "src", "l10n", "DEFAULT", "dictionary")
    with open(mpath, "rb") as f:
        _, m = dcslua.parse(f.read())
    with open(dpath, "rb") as f:
        dname, d = dcslua.parse(f.read())
    changed = apply(m, d, texts)
    if any(not (isinstance(m.get(FIELDS[c]), bytes) and m[FIELDS[c]].startswith(b"DictKey_")) for c in changed):
        raise SystemExit("src/mission holds a briefing field as a literal; set it once in the ME (DictKey) first")
    if "--check" in sys.argv:
        print("same" if not changed else "differs: %s" % ", ".join(changed))
        return 1 if changed else 0
    if not changed:
        print("src/ already carries %s" % os.path.relpath(path_for(args[0]), REPO))
        return 0
    with open(dpath, "wb") as f:
        f.write(dcslua.dump(dname.decode() if isinstance(dname, bytes) else dname, d))
    print("written %s: %s" % (os.path.relpath(dpath, REPO), ", ".join(changed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
