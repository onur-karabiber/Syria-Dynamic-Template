# refresh_scripts.py | v1.3.0
# v1.3.0: kneeboard entries go to KNEEBOARD/IMAGES/ (upper case, as the ME writes them; DCS did not
#         show pages under KNEEBOARD/images/). Existing KNEEBOARD/images/* entries are moved there.
# v1.2.0: --kneeboard DIR also syncs KNEEBOARD/images/*.png from DIR (e.g. the output of
#         make_kneeboard.py --scripted-jtac); changed files replaced, new files added.
# v1.1.0: --sounds <SET> (repeatable) also syncs Sounds/<SET>/*.ogg from src/Sounds/<SET>/
#         (changed files replaced, new files added; files only in the .miz are kept).
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
KB = "KNEEBOARD/IMAGES/"   # v1.3.0: case as written by the ME


def first_line(b):
    return b.split(b"\n", 1)[0].decode("utf-8", "replace").strip()


def main(src, dry, sound_sets=(), kb_dir=None):
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
        names = set(z.namelist())
        added = {}
        moved = {}                                              # v1.3.0: wrong-case kneeboard dir
        for n in sorted(names):
            if n.upper().startswith(KB.upper()) and not n.startswith(KB) and not n.endswith("/"):
                moved[n] = KB + n[len(KB):]
                print("kneeboard: %s -> %s (moved)" % (n, moved[n]))
        for o, t in moved.items():
            if t not in names:
                added[t] = new.pop(o, None) or z.read(o)
        names = (names - set(moved)) | set(added)
        for st in sound_sets:                                   # v1.1.0
            d = os.path.join(REPO, "src", "Sounds", st)
            for f in sorted(os.listdir(d)):
                if not f.lower().endswith(".ogg"):
                    continue
                arc = "Sounds/%s/%s" % (st, f)
                data = open(os.path.join(d, f), "rb").read()
                if arc in names:
                    if z.read(arc) != data:
                        new[arc] = data
                        print("sound:   %s (changed)" % arc)
                else:
                    added[arc] = data
                    print("sound:   %s (new)" % arc)
        if kb_dir:                                              # v1.2.0
            for f in sorted(os.listdir(kb_dir)):
                if not f.lower().endswith(".png"):
                    continue
                arc = KB + f
                data = open(os.path.join(kb_dir, f), "rb").read()
                if arc in added:
                    if added[arc] != data:
                        added[arc] = data
                        print("kneeboard: %s (changed)" % arc)
                elif arc in names:
                    if z.read(arc) != data:
                        new[arc] = data
                        print("kneeboard: %s (changed)" % arc)
                else:
                    added[arc] = data
                    print("kneeboard: %s (new)" % arc)
        if not new and not added and not moved:
            print("up to date, nothing written")
            return 0
        if dry:
            print("dry run: %d file(s) would change, %d added, %d moved" % (len(new), len(added), len(moved)))
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
                if info.filename in moved:
                    continue
                out.writestr(info, new.get(info.filename, z.read(info.filename)))
            for arc, data in added.items():
                out.writestr(arc, data, compress_type=zipfile.ZIP_STORED)
    with zipfile.ZipFile(tmp) as t:
        bad = t.testzip()
        if bad:
            os.remove(tmp)
            sys.exit("zip test failed on %s, original untouched" % bad)
    os.replace(tmp, src)
    print("written: %s (%d changed, %d added)" % (src, len(new), len(added)))
    return 0


if __name__ == "__main__":
    argv, sets, args, kb = sys.argv[1:], [], [], None
    i = 0
    while i < len(argv):
        if argv[i] == "--sounds" and i + 1 < len(argv):
            sets.append(argv[i + 1]); i += 2; continue
        if argv[i] == "--kneeboard" and i + 1 < len(argv):
            kb = argv[i + 1]; i += 2; continue
        if argv[i] != "--dry-run":
            args.append(argv[i])
        i += 1
    if len(args) != 1:
        sys.exit('usage: refresh_scripts.py "<mission.miz>" [--dry-run] [--sounds SET ...] [--kneeboard DIR]')
    sys.exit(main(args[0], "--dry-run" in argv, sets, kb))
