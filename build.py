# build.py | v2.1.0
# src/ + scripts/ -> build/Syria_Dynamic_Template.miz
# v2.1.0: after a successful build the .miz is also copied to the DCS Missions
# folder (config.py). The copy is REFUSED when the .miz already there differs
# from src/ (= Mission Editor edits not yet extracted with extract.py would be
# overwritten); --force overrides, --no-deploy skips the copy. The build in
# build/ is written either way.
# v2.0.0: Lua scripts are embedded at build time. Every *.lua named in
# src/l10n/DEFAULT/mapResource (the Mission Editor "Do Script File"
# references) is taken from scripts/ - scripts/ is the single source of
# truth. Stale .lua copies under src/l10n/DEFAULT/ are ignored. The build
# stops BEFORE writing anything if a referenced script is missing.

import argparse
import os
import re
import shutil
import sys
import zipfile

import config
import extract

SRC_DIR = 'src'
SCRIPTS_DIR = 'scripts'
EMBED_DIR = 'l10n/DEFAULT'
OUTPUT_DIR = 'build'
FINAL_MIZ = os.path.join(OUTPUT_DIR, 'Syria_Dynamic_Template.miz')


def referenced_scripts():
    """Lua file names the mission references (mapResource values)."""
    path = os.path.join(SRC_DIR, 'l10n', 'DEFAULT', 'mapResource')
    with open(path, encoding='utf-8') as f:
        text = f.read()
    return sorted(set(re.findall(r'=\s*"([^"]+\.lua)"', text)))


def find_missing(names):
    return [n for n in names if not os.path.isfile(os.path.join(SCRIPTS_DIR, n))]


def src_files():
    """(archive name, disk path) for everything in src/ except stale embedded .lua."""
    for root, _dirs, files in os.walk(SRC_DIR):
        for fn in files:
            disk = os.path.join(root, fn)
            arc = os.path.relpath(disk, SRC_DIR).replace(os.sep, '/')
            if arc.startswith(EMBED_DIR + '/') and arc.lower().endswith('.lua'):
                continue
            yield arc, disk


def deploy(force):
    """build/'deki .miz'i Missions klasörüne kopyalar. 0 ok, 2 reddedildi, 3 yazılamadı."""
    target = config.deployed_miz()
    if not os.path.isdir(config.MISSIONS_DIR):
        print("Missions klasörü yok, kopyalama atlandı: %s" % config.MISSIONS_DIR)
        return 0
    if os.path.isfile(target) and not force:
        p = extract.plan(target, SRC_DIR)
        drift = p['new'] + p['changed'] + p['deleted']
        if drift:
            print("KOPYALANMADI: %s src/ ile aynı değil (%d dosya)." % (target, len(drift)))
            extract.show("Yeni", p['new'], 10)
            extract.show("Değişen", p['changed'], 10)
            extract.show("Src'de olup .miz'de olmayan", p['deleted'], 10)
            print("ME'de yaptığın değişiklikler varsa önce 'python extract.py' çalıştır.")
            print("Üstüne yazmak istiyorsan: python build.py --force")
            return 2
    tmp = target + '.tmp'
    try:
        shutil.copyfile(FINAL_MIZ, tmp)
        os.replace(tmp, target)
    except OSError as e:
        print("HATA: Missions'a yazılamadı (DCS dosyayı açık tutuyor olabilir): %s" % e)
        if os.path.exists(tmp):
            os.remove(tmp)
        return 3
    print("Kopyalandı: %s" % target)
    return 0


def main():
    ap = argparse.ArgumentParser(description="src/ + scripts/ -> .miz")
    ap.add_argument('--no-deploy', action='store_true',
                    help="Missions klasörüne kopyalama")
    ap.add_argument('--force', action='store_true',
                    help="Missions'taki .miz src/'den farklı olsa da üzerine yaz")
    args = ap.parse_args()
    os.chdir(os.path.dirname(os.path.abspath(__file__)))

    names = referenced_scripts()
    missing = find_missing(names)
    if missing:
        print("HATA: mapResource'ta adı geçen script(ler) scripts/ içinde yok:")
        for n in missing:
            print("  -", n)
        print("Build iptal edildi, hiçbir dosya yazılmadı.")
        return 1

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    tmp = FINAL_MIZ + '.tmp'
    if os.path.exists(tmp):
        os.remove(tmp)

    print("Paketleniyor...")
    count = 0
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as z:
        for arc, disk in src_files():
            z.write(disk, arc)
            count += 1
        print("Gömülen scriptler (scripts/ -> %s/):" % EMBED_DIR)
        for n in names:
            disk = os.path.join(SCRIPTS_DIR, n)
            z.write(disk, '%s/%s' % (EMBED_DIR, n))
            with open(disk, encoding='utf-8', errors='replace') as f:
                head = f.readline().strip()[:70]
            print("  %-44s %s" % (n, head))

    os.replace(tmp, FINAL_MIZ)
    print("Build başarılı! %d dosya + %d script. Dosya konumu: %s"
          % (count, len(names), FINAL_MIZ))
    if args.no_deploy:
        return 0
    return deploy(args.force)


if __name__ == '__main__':
    sys.exit(main())
