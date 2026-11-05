# set_start_time.py | v1.0.1
# v1.0.1: usage example uses the 2026-11-05 mission name (SEA2STEEL.miz).
# Sets the mission start time (top-level ["start_time"], seconds after local midnight) in a .miz IN PLACE
# after a backup, or in a plain mission file (src/mission). Nothing else is touched; the top-level key is
# matched as exactly one tab of indentation, so unit/group "start_time" fields stay as they are.
# Waypoint times (ETA) and trigger times in DCS are relative to the mission start, so they move with it.
#
#   python tools/set_start_time.py "<...>/SEA2STEEL.miz" 06:00
#   python tools/set_start_time.py src/mission 06:00
#   backup (.miz only) -> <dir>/BackUps/<name>_before-start-HHMM-<YYYYmmdd-HHMMSS>.miz
import datetime, os, re, shutil, sys, zipfile

PAT = re.compile(rb'^\t\["start_time"\] = (\d+),$', re.M)


def patch(data, secs):
    m = PAT.findall(data)
    if len(m) != 1:
        sys.exit("expected one top-level start_time, found %d" % len(m))
    old = int(m[0])
    return PAT.sub(b'\t["start_time"] = %d,' % secs, data), old


def hhmm(s):
    return "%02d:%02d" % (s // 3600, s % 3600 // 60)


def main(path, t):
    h, mi = (int(x) for x in t.split(":"))
    secs = h * 3600 + mi * 60
    if not path.lower().endswith(".miz"):
        data = open(path, "rb").read()
        new, old = patch(data, secs)
        open(path, "wb").write(new)
        print("%s: start %s -> %s" % (path, hhmm(old), hhmm(secs)))
        return
    with zipfile.ZipFile(path) as z:
        new, old = patch(z.read("mission"), secs)
        if old == secs:
            print("already %s, nothing written" % hhmm(secs)); return
        bdir = os.path.join(os.path.dirname(os.path.abspath(path)), "BackUps")
        os.makedirs(bdir, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = os.path.join(bdir, "%s_before-start-%s-%s.miz" % (
            os.path.splitext(os.path.basename(path))[0], hhmm(secs).replace(":", ""), stamp))
        shutil.copy2(path, backup)
        print("backup", backup)
        tmp = path + ".tmp"
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
            for info in z.infolist():
                out.writestr(info, new if info.filename == "mission" else z.read(info.filename))
    with zipfile.ZipFile(tmp) as t2:
        if t2.testzip():
            os.remove(tmp); sys.exit("zip test failed, original untouched")
    os.replace(tmp, path)
    print("%s: start %s -> %s" % (path, hhmm(old), hhmm(secs)))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: set_start_time.py <file.miz | mission> HH:MM")
    main(sys.argv[1], sys.argv[2])
