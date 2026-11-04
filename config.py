# config.py | v1.1.0
# v1.1.0 (2026-11-04, Onur): Missions folder renamed "The Routine Things (With RAT)" -> "Syria Dynamic Template";
#         test variants go to its TESTs subfolder (TESTS_DIR, tools/make_test_variant.py >= v1.9.1).
# build.py ve extract.py'nin ortak ayarları: DCS Missions klasörü ve .miz adı.
# Başka bir makinede/klasörde: DCS_MISSIONS_DIR ortam değişkenini ayarla
# veya aşağıdaki yolu değiştir.

import os

MIZ_NAME = 'Syria_Dynamic_Template.miz'

MISSIONS_DIR = os.environ.get('DCS_MISSIONS_DIR') or os.path.join(
    os.path.expanduser('~'), 'Saved Games', 'DCS', 'Missions',
    'Syria Dynamic Template')
TESTS_DIR = os.path.join(MISSIONS_DIR, 'TESTs')   # v1.1.0


def deployed_miz():
    """DCS'in açtığı .miz: MISSIONS_DIR\\MIZ_NAME"""
    return os.path.join(MISSIONS_DIR, MIZ_NAME)
