# refresh_scripts.py | v1.0.0
# Refreshes the embedded Lua scripts of a .miz that build.py does not build
# (e.g. "Close Air Support (L).miz") from scripts/ (source of truth), IN PLACE,
# after a backup. Only .lua files named in l10n/DEFAULT/mapResource are touched;
# mission, triggers, sounds and pictures are copied unchanged.
#
#   python tools/refresh_scripts.py "<path>/Close Air Support (L).miz" [--dry-run]
#
#   backup -> <dir>/BackUps/<name>_before-refresh-<YYYYmmdd-HHMMSS>.miz
#   A mapped .lua with no counterpart in scripts/ is reported and left as is.
#   Adding a NEW script still needs the ME (or an installer): this tool never
#   edits mapResource or the mission.

import datetime
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, REPO)
import dcslua  # noqa: E402

PREFIX = "l10n/DEFAULT/"


def first_line(b):
    return b.split(b"\n", 1)[0].decode("utf-8", "replace").strip()


def main(src, dry):
    with zipfile.ZipFile(src) as z:
        mapres = dcslua.parse(z.read(PREFIX + "mapResource"))[1]
        luas = sorted({v.decode() for v in mapres.values()
                       if isinstance(v, bytes) and v.lower().endswith(b".lua")})
        new = {}
        for nm in luas:
            arc = PREFIX + nm
            disk = os.path.join(REPO, "scripts", nm)
            if not os.path.isfile(disk):
                print("skip (not in scripts/):", nm)
                continue
            if arc not in z.namelist():
                print("WARN mapped but not embedded:", nm)
            data = open(disk, "rb").read()
            old = z.read(arc) if arc in z.namelist() else b""
            if old != data:
                new[arc] = data
                print("refresh: %-42s %s -> %s" % (nm, first_line(old) or "(none)", first_line(data)))
        if not new:
            print("up to date, nothing written")
            return 0
        if dry:
            print("dry run: %d script(s) would change" % len(new))
            return 0
        bdir = os.path.join(os.path.dirname(os.path.abspath(src)), "BackUps")
        os.makedirs(bdir, exist_ok=True)
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = os.path.join(bdir, "%s_before-refresh-%s.miz"
                              % (os.path.splitext(os.path.basename(src))[0], stamp))
        shutil.copy2(src, backup)
        print("backup", backup)
        tmp = src + ".tmp"
        with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as out:
            for info in z.infolist():
                out.writestr(info, new.get(info.filename, z.read(info.filename)))
    with zipfile.ZipFile(tmp) as t:
        bad = t.testzip()
        if bad:
            os.remove(tmp)
            sys.exit("zip test failed on %s, original untouched" % bad)
    os.replace(tmp, src)
    print("written: %s (%d script(s))" % (src, len(new)))
    return 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    if len(args) != 1:
        sys.exit('usage: refresh_scripts.py "<mission.miz>" [--dry-run]')
    sys.exit(main(args[0], "--dry-run" in sys.argv[1:]))
