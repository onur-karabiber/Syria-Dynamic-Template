# extract.py | v1.1.1
# Mission Editor'de kaydedilmiş .miz  ->  src/   (build.py'nin tersi)
#
#   python extract.py                  # config.py'deki Missions\...\Syria_Dynamic_Template.miz
#   python extract.py "yol\dosya.miz"  # belirli bir .miz
#   python extract.py -n               # dry-run: hiçbir şey yazmaz/silmez, sadece raporlar
#
# Kurallar:
#   - .miz içindeki her dosya src/ altına yazılır; yalnızca içeriği farklı olan
#     (boyut + CRC32) veya yeni olanlar yazılır, böylece git diff'i temiz kalır.
#   - l10n/DEFAULT/*.lua atlanır (scripts/ tek doğruluk kaynağıdır, build.py de
#     bunları zaten yok sayar).
#   - .miz'de olmayan dosyalar src/'den silinir. Bu yalnızca .miz'in en üst
#     seviyede içerdiği klasör/dosyalar için geçerlidir: .miz'de hiç Sounds/
#     yoksa src/Sounds/ olduğu gibi kalır.
#   - Normalize (v1.1.0): mission, options, warehouses, l10n/DEFAULT/dictionary ve
#     mapResource Lua tabloları, ME'nin her kayıtta değiştirdiği anahtar sırası
#     yerine anahtar-sıralı biçimde yazılır (dcslua.py). Veri aynı kalır, git diff
#     yalnızca gerçek değişikliği gösterir. Yazmadan önce çıktı tekrar ayrıştırılıp
#     orijinalle tip dahil karşılaştırılır; ayrıştırma/doğrulama başarısız olursa
#     dosya HAM yazılır ve uyarı verilir. --no-normalize ile kapatılır.
#   - Satır sonu (v1.1.1): normalize edilen dosyalar LF yazılır; karşılaştırmada
#     src'deki CRLF (Windows'ta git autocrlf checkout'u) fark sayılmaz.
#   - Güvenlik: 'mission' girdisi olmayan arşiv reddedilir; 50'den fazla dosya
#     silinecekse --force gerekir; arşivde dışarı taşan yol (../, sürücü harfi)
#     varsa iptal edilir.

import argparse
import os
import sys
import zipfile
import zlib

import config
import dcslua

SRC_DIR = 'src'
EMBED_DIR = 'l10n/DEFAULT'
MAX_DELETE = 50
# arşiv yolu -> beklenen üst seviye Lua değişkeni
NORMALIZE = {
    'mission': 'mission',
    'options': 'options',
    'warehouses': 'warehouses',
    'l10n/DEFAULT/dictionary': 'dictionary',
    'l10n/DEFAULT/mapResource': 'mapResource',
}
CHUNK = 1 << 20


def is_embedded_lua(arc):
    return arc.startswith(EMBED_DIR + '/') and arc.lower().endswith('.lua')


def clean_arc(name):
    arc = name.replace('\\', '/')
    if arc.startswith('/') or ':' in arc or '..' in arc.split('/'):
        raise ValueError("Güvensiz yol .miz içinde: %r" % name)
    return arc


def file_crc(path):
    crc = 0
    with open(path, 'rb') as f:
        while True:
            b = f.read(CHUNK)
            if not b:
                break
            crc = zlib.crc32(b, crc)
    return crc & 0xFFFFFFFF


def plan(miz, src_dir=SRC_DIR, normalize=True, verify=False):
    """.miz'i src_dir ile karşılaştırır, hiçbir şey yazmaz.
    new/changed: src'ye yazılacaklar, deleted: src'den silinecekler.
    normalize=True: NORMALIZE'daki dosyalar anahtar-sıralı biçimleriyle karşılaştırılır
    (ME'nin sadece sıra değiştiren kaydı fark sayılmaz). verify=True: yazılacak
    normalize çıktısı ayrıca yeniden ayrıştırılıp doğrulanır."""
    entries = {}   # arc -> {size, crc, member, data (normalize edilmişse bytes)}
    skipped = 0
    normalized = []
    warnings = []
    with zipfile.ZipFile(miz) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            arc = clean_arc(info.filename)
            if is_embedded_lua(arc):
                skipped += 1
                continue
            e = {'size': info.file_size, 'crc': info.CRC,
                 'member': info.filename, 'data': None}
            var = NORMALIZE.get(arc)
            if normalize and var:
                try:
                    data = dcslua.normalize(z.read(info.filename), var, verify)
                    e['size'] = len(data)
                    e['crc'] = zlib.crc32(data) & 0xFFFFFFFF
                    e['data'] = data
                    normalized.append(arc)
                except dcslua.LuaError as ex:
                    warnings.append("%s: %s -> ham yazılacak" % (arc, ex))
            entries[arc] = e

    on_disk = {}
    for root, _dirs, files in os.walk(src_dir):
        for fn in files:
            disk = os.path.join(root, fn)
            on_disk[os.path.relpath(disk, src_dir).replace(os.sep, '/')] = disk

    tops = {a.split('/')[0] for a in entries}
    new = sorted(a for a in entries if a not in on_disk)
    changed = []
    for arc, e in sorted(entries.items()):
        disk = on_disk.get(arc)
        if disk is None:
            continue
        if e['data'] is not None:
            with open(disk, 'rb') as f:
                if f.read().replace(b'\r\n', b'\n') != e['data']:
                    changed.append(arc)
        elif os.path.getsize(disk) != e['size'] or file_crc(disk) != e['crc']:
            changed.append(arc)
    deleted = sorted(a for a in on_disk
                     if a.split('/')[0] in tops
                     and a not in entries
                     and not is_embedded_lua(a))
    kept = sorted({a.split('/')[0] for a in on_disk} - tops)
    return {'entries': entries, 'new': new, 'changed': changed,
            'deleted': deleted, 'kept_tops': kept, 'skipped_lua': skipped,
            'normalized': normalized, 'warnings': warnings,
            'has_mission': 'mission' in entries}


def apply_plan(miz, p, src_dir=SRC_DIR):
    with zipfile.ZipFile(miz) as z:
        for arc in p['new'] + p['changed']:
            dest = os.path.join(src_dir, *arc.split('/'))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            tmp = dest + '.tmp'
            e = p['entries'][arc]
            if e['data'] is not None:
                with open(tmp, 'wb') as fout:
                    fout.write(e['data'])
            else:
                with z.open(e['member']) as fin, open(tmp, 'wb') as fout:
                    while True:
                        b = fin.read(CHUNK)
                        if not b:
                            break
                        fout.write(b)
            os.replace(tmp, dest)
    for arc in p['deleted']:
        path = os.path.join(src_dir, *arc.split('/'))
        os.remove(path)
        d = os.path.dirname(path)
        while os.path.abspath(d) != os.path.abspath(src_dir) and not os.listdir(d):
            os.rmdir(d)
            d = os.path.dirname(d)


def show(label, names, limit=30):
    if not names:
        return
    print("%s (%d):" % (label, len(names)))
    for n in names[:limit]:
        print("  " + n)
    if len(names) > limit:
        print("  ... +%d dosya daha" % (len(names) - limit))


def main():
    ap = argparse.ArgumentParser(description=".miz -> src/ (build.py'nin tersi)")
    ap.add_argument('miz', nargs='?', help="varsayılan: %s" % config.deployed_miz())
    ap.add_argument('-n', '--dry-run', action='store_true',
                    help="yazma/silme yapmadan raporla")
    ap.add_argument('--force', action='store_true',
                    help="%d'den fazla dosya silmeye izin ver" % MAX_DELETE)
    ap.add_argument('--no-normalize', action='store_true',
                    help="Lua tablolarını anahtar-sıralı yazma, ME'nin ham çıktısını olduğu gibi yaz")
    args = ap.parse_args()

    miz = os.path.abspath(args.miz) if args.miz else config.deployed_miz()
    os.chdir(os.path.dirname(os.path.abspath(__file__)))

    if not os.path.isfile(miz):
        print("HATA: .miz bulunamadı: %s" % miz)
        return 1
    try:
        p = plan(miz, normalize=not args.no_normalize, verify=True)
    except (zipfile.BadZipFile, ValueError) as e:
        print("HATA: %s" % e)
        return 1
    if not p['has_mission']:
        print("HATA: arşivde 'mission' dosyası yok, DCS mission'ı değil. Hiçbir şey yapılmadı.")
        return 1
    if len(p['deleted']) > MAX_DELETE and not args.force:
        print("HATA: %d dosya silinecek (sınır %d). Doğru .miz mi? Eminsen --force ile tekrar çalıştır."
              % (len(p['deleted']), MAX_DELETE))
        show("Silinecek", p['deleted'], 10)
        return 1

    print("Kaynak: %s" % miz)
    show("Yeni", p['new'])
    show("Değişen", p['changed'])
    show("Silinen", p['deleted'])
    if p['kept_tops']:
        print("Dokunulmadı (.miz'de yok): %s" % ", ".join(p['kept_tops']))
    if p['normalized']:
        print("Anahtar-sıralı yazıldı/karşılaştırıldı: %s" % ", ".join(p['normalized']))
    for w in p['warnings']:
        print("UYARI: " + w)
    if p['skipped_lua']:
        print("Atlandı: %d adet l10n/DEFAULT/*.lua (scripts/ geçerli)" % p['skipped_lua'])

    n = len(p['new']) + len(p['changed']) + len(p['deleted'])
    if n == 0:
        print("src/ zaten .miz ile aynı, değişiklik yok.")
        return 0
    if args.dry_run:
        print("Dry-run: hiçbir şey yazılmadı.")
        return 0
    apply_plan(miz, p)
    print("Tamam: %d yeni, %d değişen, %d silinen. 'git status' ile kontrol et."
          % (len(p['new']), len(p['changed']), len(p['deleted'])))
    return 0


if __name__ == '__main__':
    sys.exit(main())
