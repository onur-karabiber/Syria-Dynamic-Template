# config.py | v1.2.0
# v1.2.0 (2026-11-05, Onur: ITG stays its own mission, scripts shared): MISSIONS profiles for build.py /
#         extract.py --mission. SDT (default) is unchanged; ITG = Into The Grey (missions/ITG/src, own scripts in
#         missions/ITG/scripts searched before scripts/).
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


# v1.2.0: mission profiles (build.py / extract.py --mission <KEY>). Paths are relative to the repo root.
#   src      unpacked ME data of the mission
#   scripts  script search path: the first folder that has the file wins
#   dir/miz  deployed .miz (DCS opens this one)
#   out      build output
#   shared   folders packed from the template's src/ (not kept in the mission's own src; extract skips them)
MISSIONS = {
    'SDT': {'src': 'src', 'scripts': ['scripts'],
            'dir': MISSIONS_DIR, 'miz': MIZ_NAME,
            'out': os.path.join('build', MIZ_NAME), 'shared': []},
    'ITG': {'src': os.path.join('missions', 'ITG', 'src'),
            'scripts': [os.path.join('missions', 'ITG', 'scripts'), 'scripts'],
            'dir': os.environ.get('DCS_ITG_DIR') or os.path.join(
                os.path.expanduser('~'), 'Saved Games', 'DCS', 'Missions', 'Into The Grey'),
            'miz': 'Into The Grey.miz',
            'out': os.path.join('build', 'Into The Grey.miz'),
            # P1 (2026-11-05): assets of the shared modules (CV_Comms, AIRBOSS Raynor voices, Score_Display,
            # PlaneCaptain_Carrier), packed from src/ so they stay identical to SDT / SEA2STEEL
            'shared': ['Sounds/CV', 'Sounds/SCORE', 'ScoreCards', 'PlaneCaptain',
                       'Sounds/AIRBOSS/Airboss Soundfiles',
                       'Sounds/AIRBOSS/Airboss Soundpack LSO Raynor',
                       'Sounds/AIRBOSS/Airboss Soundpack Marshal Raynor']},
}


def profile(key='SDT'):
    p = dict(MISSIONS[key.upper()])
    p['key'] = key.upper()
    p['deployed'] = os.path.join(p['dir'], p['miz'])
    return p
