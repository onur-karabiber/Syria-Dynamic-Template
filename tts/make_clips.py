# make_clips.py | v1.1.0
# tts/clips.csv -> src/Sounds/CAS1/<id>.ogg  (Piper TTS + ffmpeg radio chain)
# Also writes tts/audio_table.lua: paste into Comms_Director CFG.AUDIO.
# Usage:  python tts/make_clips.py              (all clips)
#         python tts/make_clips.py str_m4_sour  (only the listed ids)
#         python tts/make_clips.py --out DIR id (write to DIR, table untouched; A/B tests)
#
# v1.1.0: speech ~2x faster (Piper LENGTH_SCALE x ffmpeg TEMPO); radio chain adds
#         narrower band, soft-clip distortion, bit crush, pink-noise floor and
#         squelch bursts at key-up / key-down.
import argparse, os, subprocess, sys, tempfile, wave

ROOT   = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VOICES = os.path.join(ROOT, 'tts', 'voices')
CSV    = os.path.join(ROOT, 'tts', 'clips.csv')
OUTDIR = os.path.join(ROOT, 'src', 'Sounds', 'CAS1')
TABLE  = os.path.join(ROOT, 'tts', 'audio_table.lua')

# agency -> voice model file in tts/voices/
VOICE = {
    'DEPARTURE': 'en_US-ryan-medium.onnx',
    'STRIKE':    'en_US-joe-medium.onnx',
    'OVERLORD':  'en_GB-alan-medium.onnx',
    'EYEBALL':   'en_US-hfc_male-medium.onnx',
    'TEXACO':    'en_US-kusal-medium.onnx',
}
FALLBACK = None  # model file name used for any agency missing above

# Speed: total speed-up = TEMPO / LENGTH_SCALE  (0.70 / 1.40 -> 2.0x).
# Piper alone below ~0.6 starts slurring; the rest is done by ffmpeg atempo.
LENGTH_SCALE = 0.70
TEMPO        = 1.40

# Radio chain
KEYUP   = 0.07   # s squelch burst before speech
KEYDOWN = 0.12   # s squelch tail after speech
HISS    = 0.012  # pink-noise floor amplitude under the speech
BURST   = 0.22   # squelch burst amplitude
BAND    = 'highpass=f=400,highpass=f=400,lowpass=f=2700,lowpass=f=2700'
SPEECH  = ('atempo=%.3f,' + BAND + ','
           'acompressor=threshold=-24dB:ratio=8:attack=3:release=60:makeup=4,'
           'asoftclip=type=tanh,acrusher=bits=10:mix=0.35:mode=log,'
           'adelay=%d,apad=pad_dur=%.3f')


def load_voice(path, cache={}):
    if path not in cache:
        from piper import PiperVoice
        cache[path] = PiperVoice.load(path)
    return cache[path]


def synth(model, text, wav_path):
    voice = load_voice(model)
    with wave.open(wav_path, 'wb') as wf:
        try:                                    # piper-tts >= 1.3
            from piper import SynthesisConfig
            voice.synthesize_wav(text, wf, syn_config=SynthesisConfig(length_scale=LENGTH_SCALE))
        except ImportError:                     # piper-tts 1.2.x
            voice.synthesize(text, wf, length_scale=LENGTH_SCALE)
    with wave.open(wav_path) as wf:
        return wf.getnframes() / float(wf.getframerate())


def radio(wav, raw_len, ogg):
    total = KEYUP + raw_len / TEMPO + KEYDOWN
    fc = ('[0:a]' + SPEECH % (TEMPO, int(KEYUP * 1000), KEYDOWN) + ',aresample=22050[s];'
          'anoisesrc=d=%.3f:c=pink:a=%.4f:r=22050,%s[n];' % (total, HISS, BAND) +
          'anoisesrc=d=%.3f:c=white:a=%.3f:r=22050,%s,afade=t=out:d=%.3f[k1];'
          % (KEYUP, BURST, BAND, KEYUP) +
          'anoisesrc=d=%.3f:c=white:a=%.3f:r=22050,%s,afade=t=out:d=%.3f,adelay=%d[k2];'
          % (KEYDOWN, BURST, BAND, KEYDOWN, int((total - KEYDOWN) * 1000)) +
          '[s][n][k1][k2]amix=inputs=4:duration=longest:normalize=0,'
          'atrim=0:%.3f,alimiter=limit=0.9' % total)
    subprocess.check_call(['ffmpeg', '-y', '-v', 'error', '-i', wav, '-filter_complex', fc,
                           '-ac', '1', '-ar', '22050', '-c:a', 'libvorbis', '-q:a', '4', ogg])


def duration(path):
    out = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
                                   'format=duration', '-of', 'csv=p=0', path])
    return float(out.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ids', nargs='*')
    ap.add_argument('--out', help='output folder (A/B test); audio_table.lua not written')
    a = ap.parse_args()
    outdir = a.out or OUTDIR
    rows = []
    with open(CSV, encoding='utf-8') as f:
        for ln in f:
            ln = ln.strip()
            if ln and not ln.startswith('#'):
                cid, agency, text = ln.split(';', 2)
                rows.append((cid.strip(), agency.strip(), text.strip()))
    os.makedirs(outdir, exist_ok=True)
    table, failed = [], []
    for cid, agency, text in rows:
        ogg = os.path.join(outdir, cid + '.ogg')
        if not a.ids or cid in a.ids:
            name = VOICE.get(agency, FALLBACK)
            model = name and os.path.join(VOICES, name)
            if not model or not os.path.isfile(model) or not os.path.isfile(model + '.json'):
                print('ATLANDI  %-22s ses modeli yok: %s' % (cid, name)); failed.append(cid); continue
            with tempfile.TemporaryDirectory() as td:
                wav = os.path.join(td, 'raw.wav')
                radio(wav, synth(model, text, wav), ogg)
        if os.path.isfile(ogg):
            d = duration(ogg)
            table.append('        %-22s = { ch = "%s", len = %.1f },' % (cid, agency, d))
            print('OK       %-22s %5.1f s  %s' % (cid, d, agency))
    if not a.out:
        with open(TABLE, 'w', encoding='utf-8') as f:
            f.write('    -- generated by tts/make_clips.py; len = clip length (s)\n')
            f.write('    AUDIO = {\n' + '\n'.join(table) + '\n    },\n')
        print('\n%d clip, tablo: %s' % (len(table), TABLE))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
