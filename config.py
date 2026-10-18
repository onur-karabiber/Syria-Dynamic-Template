# config.py | v1.0.0
# build.py ve extract.py'nin ortak ayarları: DCS Missions klasörü ve .miz adı.
# Başka bir makinede/klasörde: DCS_MISSIONS_DIR ortam değişkenini ayarla
# veya aşağıdaki yolu değiştir.

import os

MIZ_NAME = 'Syria_Dynamic_Template.miz'

MISSIONS_DIR = os.environ.get('DCS_MISSIONS_DIR') or os.path.join(
    os.path.expanduser('~'), 'Saved Games', 'DCS', 'Missions',
    'The Routine Things (With RAT)')


def deployed_miz():
    """DCS'in açtığı .miz: MISSIONS_DIR\\MIZ_NAME"""
    return os.path.join(MISSIONS_DIR, MIZ_NAME)
