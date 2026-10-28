# make_clips.py | v1.8.0
# tts/clips.csv -> src/Sounds/CAS1/<id>.ogg  (Piper TTS + ffmpeg radio chain)
# CV comms:  python tts/make_clips.py --set cv   (tts/cv_clips.csv -> src/Sounds/CV/,
#            table tts/cv_audio_table.lua -> paste into CV_Comms CFG.AUDIO)
# LTCC transit: python tts/make_clips.py --set fc (tts/fc_clips.csv -> src/Sounds/FC/,
#            table tts/fc_audio_table.lua -> paste into Field_Comms CFG.AUDIO)
# Pilot banter (CAS (L) only): python tts/make_clips.py --set pb
#            (tts/pb_clips.csv -> tools/pilot_banter/out/Sounds/PB/, NOT src/Sounds, so the
#            template build never packs it; the AUDIO block in scripts/Pilot_Banter.lua is
#            rewritten in place between its BEGIN AUDIO / END AUDIO markers - no paste step)
#
# v1.8.0: --set pb. Cockpit chain instead of the radio chain: the pilot talking to himself
#         is not a transmission (no squelch, no 400-2700 Hz radio band, no bit crush, no
#         noise floor). 150-5000 Hz, a small boxy resonance (oxygen mask), gentle
#         compression, natural speed (atempo 1.0; voice PILOT_IN = PILOT model and speaker
#         at length_mult 1.35 -> length_scale 0.945). Lua table entries carry the text too.
#
# v1.7.0: CAP net voices for Comms_Director v1.5.0 (all '>OVERLORD' channel):
#         CHECK31 ryan-high, CHECK21 john-medium, VIPER21 bryce-medium (three distinct men,
#         none of them already on the CAS1 net). ryan-high is used for full sentences only
#         (its one-syllable token problem, below, does not apply).
# v1.6.0: high-quality Piper models on the busiest voices: PILOT libritts-high speaker 851
#         (all sets; ryan-high rejected: one-syllable tokens collapse to ~0.15-0.2 s,
#         "two" never exceeds 0.23 s at any length_scale),
#         MARSHAL / APPROACH libritts-high speakers 736 / 69 (two distinct men),
#         OVERLORD lessac-high, DEPARTURE ljspeech-high. VOICE entries may be
#         (model, pitch, speaker_id, length_mult): speaker_id for multi-speaker models,
#         length_mult scales LENGTH_SCALE per voice. All three sets re-rendered.
# v1.5.0: --set fc (Field_Comms LTCC->CVN-73 transit). Civil/foreign ATC cast on
#         en_GB voices, Navy side keeps the CAS1 US voices (STRIKE joe, PILOT john).
# Also writes tts/audio_table.lua: paste into Comms_Director CFG.AUDIO.
# Usage:  python tts/make_clips.py              (all clips)
#         python tts/make_clips.py str_m4_sour  (only the listed ids)
#         python tts/make_clips.py --out DIR id (write to DIR, table untouched; A/B tests)
#
# v1.4.1: GAIN_DB 2.3 -> 5.5 (still quiet in test); peaks now limited harder.
# v1.4.0: speech 25% slower (TEMPO 1.40 -> 1.05: 2.0x -> 1.5x net) and +30% level
#         (GAIN_DB 2.3 before the limiter, limit 0.9 -> 0.97). All sets re-rendered.
# v1.3.1: table len always 2 decimals (CAS1 set now chains token clips too).
# v1.3.0: --set cv (CV_Comms clip set). Optional 4th csv field 'tok' = token clip:
#         no squelch bursts, leading/trailing silence trimmed, short tail pad
#         (pad = 4th field 'tok:0.25' for a comma pause). Text <KEYUP>/<KEYDOWN>
#         renders a squelch-burst-only clip. Clips are chained at runtime.
#         Table len written with 2 decimals.
#         voices: MARSHAL hfc_male, APPROACH kusal (CV set; norman rejected:
#         it emits long noise/breath segments on one-word tokens).
# v1.2.1: voices: DEPARTURE lessac (f), OVERLORD kristin (f), PILOT john (no pitch shift).
# v1.2.0: pilot (HORNET 51) voice. clips.csv agency field may be VOICE>CHANNEL
#         (e.g. PILOT>OVERLORD): voice from VOICE[VOICE], ch in audio_table = CHANNEL.
#         VOICE entries may be (model, pitch); pitch < 1 lowers the voice, speed kept.
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
    'DEPARTURE': 'en_US-ljspeech-high.onnx',   # female (v1.6.0, was lessac-medium)
    'STRIKE':    'en_US-joe-medium.onnx',
    'OVERLORD':  'en_US-lessac-high.onnx',     # female (v1.6.0, was kristin-medium)
    'EYEBALL':   'en_US-hfc_male-medium.onnx',
    'TEXACO':    'en_US-kusal-medium.onnx',
    'PILOT':     ('en_US-libritts-high.onnx', 1.0, 851, 1.0),  # v1.6.0, was john-medium (ryan-high rejected, see header)
    'PILOT_IN':  ('en_US-libritts-high.onnx', 1.0, 851, 1.35), # v1.8.0 same pilot, natural speed (--set pb)
    'MARSHAL':   ('en_US-libritts-high.onnx', 1.0, 736, 1.0),  # v1.6.0, was hfc_male (norman: garbage on 1-word tokens)
    'APPROACH':  ('en_US-libritts-high.onnx', 1.0, 69, 1.0),   # v1.6.0, was kusal
    'CHECK31':   'en_US-ryan-high.onnx',      # v1.7.0 CAP-1 lead (Comms_Director CAP net)
    'CHECK21':   'en_US-john-medium.onnx',    # v1.7.0 CAP-2 lead
    'VIPER21':   'en_US-bryce-medium.onnx',   # v1.7.0 INTER-2 lead
    # Field_Comms (--set fc). Civil / foreign ATC is cast British so the switch
    # to Strike (US Navy, joe) lands as an audible change of world; Cyprus ATC
    # English is British-influenced anyway. No Turkish Piper voice exists.
    'LTCC_INFO': 'en_US-ljspeech-high.onnx',               # ATIS: recorded-broadcast timbre
    'LTCC_DEL':  'en_GB-cori-high.onnx',                   # female
    'LTCC_GND':  'en_GB-alan-medium.onnx',                 # male, RP
    'LTCC_TWR':  'en_GB-northern_english_male-medium.onnx',# male, clearly not alan
    'LTCC_DEP':  'en_GB-jenny_dioco-medium.onnx',          # female
    'ANKARA':    'en_US-bryce-medium.onnx',                # male
    'NICOSIA':   'en_GB-southern_english_female-medium.onnx',
}

SETS = {   # --set name -> (csv, outdir, table)
    'cas1': (CSV, OUTDIR, TABLE),
    'cv':   (os.path.join(ROOT, 'tts', 'cv_clips.csv'),
             os.path.join(ROOT, 'src', 'Sounds', 'CV'),
             os.path.join(ROOT, 'tts', 'cv_audio_table.lua')),
    'fc':   (os.path.join(ROOT, 'tts', 'fc_clips.csv'),
             os.path.join(ROOT, 'src', 'Sounds', 'FC'),
             os.path.join(ROOT, 'tts', 'fc_audio_table.lua')),
    'pb':   (os.path.join(ROOT, 'tts', 'pb_clips.csv'),                       # v1.8.0
             os.path.join(ROOT, 'tools', 'pilot_banter', 'out', 'Sounds', 'PB'),
             os.path.join(ROOT, 'scripts', 'Pilot_Banter.lua')),
}
COCKPIT_SETS = {'pb'}   # v1.8.0: cockpit chain + in-place Lua AUDIO block (markers below)
LUA_BEGIN = '-- BEGIN AUDIO'
LUA_END   = '-- END AUDIO'
TOK_PAD = 0.06   # s silence after a token clip (default, 'tok:<s>' overrides)
FALLBACK = None  # model file name used for any agency missing above

# Speed: total speed-up = TEMPO / LENGTH_SCALE  (1.05 / 0.70 -> 1.5x; v1.4.0, was 2.0x).
# Piper alone below ~0.6 starts slurring; the rest is done by ffmpeg atempo.
LENGTH_SCALE = 0.70
TEMPO        = 1.05
GAIN_DB      = 5.5    # v1.4.1 (v1.4.0: 2.3)
LIMIT        = 0.97

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


def synth(model, text, wav_path, speaker=None, length_mult=1.0):
    voice = load_voice(model)
    ls = LENGTH_SCALE * length_mult
    with wave.open(wav_path, 'wb') as wf:
        try:                                    # piper-tts >= 1.3
            from piper import SynthesisConfig
            voice.synthesize_wav(text, wf, syn_config=SynthesisConfig(length_scale=ls, speaker_id=speaker))
        except ImportError:                     # piper-tts 1.2.x
            voice.synthesize(text, wf, length_scale=ls, speaker_id=speaker)
    with wave.open(wav_path) as wf:
        return wf.getnframes() / float(wf.getframerate())


def radio(wav, raw_len, ogg, pitch=1.0):
    total = KEYUP + raw_len / TEMPO + KEYDOWN
    shift = '' if pitch == 1.0 else 'asetrate=%d,aresample=22050,' % round(22050 * pitch)
    fc = ('[0:a]' + shift + SPEECH % (TEMPO / pitch, int(KEYUP * 1000), KEYDOWN)
          + ',aresample=22050[s];'
          'anoisesrc=d=%.3f:c=pink:a=%.4f:r=22050,%s[n];' % (total, HISS, BAND) +
          'anoisesrc=d=%.3f:c=white:a=%.3f:r=22050,%s,afade=t=out:d=%.3f[k1];'
          % (KEYUP, BURST, BAND, KEYUP) +
          'anoisesrc=d=%.3f:c=white:a=%.3f:r=22050,%s,afade=t=out:d=%.3f,adelay=%d[k2];'
          % (KEYDOWN, BURST, BAND, KEYDOWN, int((total - KEYDOWN) * 1000)) +
          '[s][n][k1][k2]amix=inputs=4:duration=longest:normalize=0,'
          'atrim=0:%.3f,volume=%.1fdB,alimiter=limit=%.2f' % (total, GAIN_DB, LIMIT))
    subprocess.check_call(['ffmpeg', '-y', '-v', 'error', '-i', wav, '-filter_complex', fc,
                           '-ac', '1', '-ar', '22050', '-c:a', 'libvorbis', '-q:a', '4', ogg])


def radio_token(wav, ogg, pad):
    trim = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,'
            'areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,areverse')
    fc = ('[0:a]' + trim + ',atempo=%.3f,' % TEMPO + BAND + ','
          'acompressor=threshold=-24dB:ratio=8:attack=3:release=60:makeup=4,'
          'asoftclip=type=tanh,acrusher=bits=10:mix=0.35:mode=log,'
          'apad=pad_dur=%.3f,aresample=22050[s];' % pad +
          'anoisesrc=d=30:c=pink:a=%.4f:r=22050,%s[n];' % (HISS, BAND) +
          '[s][n]amix=inputs=2:duration=first:normalize=0,volume=%.1fdB,alimiter=limit=%.2f' % (GAIN_DB, LIMIT))
    subprocess.check_call(['ffmpeg', '-y', '-v', 'error', '-i', wav, '-filter_complex', fc,
                           '-ac', '1', '-ar', '22050', '-c:a', 'libvorbis', '-q:a', '4', ogg])


# v1.8.0: cockpit voice (pilot to himself). No radio band / squelch / crush / hiss.
COCKPIT_GAIN_DB = 3.0
COCKPIT = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02,'
           'areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05,areverse,'
           'highpass=f=150,lowpass=f=5000,'
           'equalizer=f=900:t=q:w=1.2:g=3,'          # boxy mask resonance
           'aecho=0.85:0.5:5:0.18,'                  # 5 ms reflection inside the mask
           'acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=2,'
           'adelay=120,apad=pad_dur=0.25,aresample=22050,'
           'volume=%.1fdB,alimiter=limit=%.2f')


def cockpit(wav, ogg):
    subprocess.check_call(['ffmpeg', '-y', '-v', 'error', '-i', wav,
                           '-af', COCKPIT % (COCKPIT_GAIN_DB, LIMIT),
                           '-ac', '1', '-ar', '22050', '-c:a', 'libvorbis', '-q:a', '4', ogg])


def write_lua_block(path, entries):
    """v1.8.0: replace the lines between LUA_BEGIN and LUA_END in a Lua script."""
    lines = open(path, encoding='utf-8').read().split('\n')
    b = next((i for i, l in enumerate(lines) if l.strip().startswith(LUA_BEGIN)), None)
    e = next((i for i, l in enumerate(lines) if l.strip().startswith(LUA_END)), None)
    if b is None or e is None or e <= b:
        raise SystemExit('markers %r / %r not found in %s' % (LUA_BEGIN, LUA_END, path))
    ind = lines[b][:len(lines[b]) - len(lines[b].lstrip())]
    body = [ind + 'AUDIO = {'] + entries + [ind + '},']
    out = '\n'.join(lines[:b + 1] + body + lines[e:])
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(out)


def lua_str(t):
    return '"' + t.replace('\\', '\\\\').replace('"', '\\"') + '"'


def squelch(ogg, which):
    d = KEYUP if which == 'up' else KEYDOWN
    fc = ('anoisesrc=d=%.3f:c=white:a=%.3f:r=22050,%s,afade=t=out:d=%.3f[k];'
          % (d, BURST, BAND, d) +
          'anoisesrc=d=%.3f:c=pink:a=%.4f:r=22050,%s[n];' % (d, HISS, BAND) +
          '[k][n]amix=inputs=2:duration=longest:normalize=0,volume=%.1fdB,alimiter=limit=%.2f' % (GAIN_DB, LIMIT))
    subprocess.check_call(['ffmpeg', '-y', '-v', 'error', '-filter_complex', fc,
                           '-ac', '1', '-ar', '22050', '-c:a', 'libvorbis', '-q:a', '4', ogg])


def duration(path):
    out = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries',
                                   'format=duration', '-of', 'csv=p=0', path])
    return float(out.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ids', nargs='*')
    ap.add_argument('--out', help='output folder (A/B test); audio_table.lua not written')
    ap.add_argument('--set', default='cas1', choices=sorted(SETS))
    a = ap.parse_args()
    csv, outdir0, table_path = SETS[a.set]
    outdir = a.out or outdir0
    rows = []
    with open(csv, encoding='utf-8') as f:
        for ln in f:
            ln = ln.strip()
            if ln and not ln.startswith('#'):
                parts = ln.split(';')
                cid, agency = parts[0].strip(), parts[1].strip()
                text = parts[2].strip()
                mode = parts[3].strip() if len(parts) > 3 else ''
                rows.append((cid, agency, text, mode))
    os.makedirs(outdir, exist_ok=True)
    table, failed = [], []
    for cid, agency, text, mode in rows:
        ogg = os.path.join(outdir, cid + '.ogg')
        if (not a.ids or cid in a.ids) and text in ('<KEYUP>', '<KEYDOWN>'):
            squelch(ogg, 'up' if text == '<KEYUP>' else 'down')
        elif not a.ids or cid in a.ids:
            vkey, _, _ = agency.partition('>')
            name = VOICE.get(vkey, FALLBACK)
            if not isinstance(name, tuple): name = (name,)
            name, pitch, spk, lmul = tuple(name) + (None, 1.0, None, 1.0)[len(name):]
            model = name and os.path.join(VOICES, name)
            if not model or not os.path.isfile(model) or not os.path.isfile(model + '.json'):
                print('ATLANDI  %-22s ses modeli yok: %s' % (cid, name)); failed.append(cid); continue
            with tempfile.TemporaryDirectory() as td:
                wav = os.path.join(td, 'raw.wav')
                raw = synth(model, text, wav, spk, lmul)
                if a.set in COCKPIT_SETS:
                    cockpit(wav, ogg)
                elif mode.startswith('tok'):
                    pad = float(mode.split(':')[1]) if ':' in mode else TOK_PAD
                    radio_token(wav, ogg, pad)
                else:
                    radio(wav, raw, ogg, pitch)
        if os.path.isfile(ogg):
            d = duration(ogg)
            ch = agency.partition('>')[2] or agency
            if a.set in COCKPIT_SETS:
                table.append('        %-18s = { len = %.2f, text = %s },' % (cid, d, lua_str(text)))
            else:
                fmt = '        %-22s = { ch = "%s", len = %.2f },'
                table.append(fmt % (cid, ch, d))
            print('OK       %-22s %5.1f s  %s' % (cid, d, agency))
    if not a.out and a.set in COCKPIT_SETS:
        write_lua_block(table_path, table)
        print('\n%d clip, AUDIO block rewritten: %s' % (len(table), table_path))
    elif not a.out:
        with open(table_path, 'w', encoding='utf-8') as f:
            f.write('    -- generated by tts/make_clips.py; len = clip length (s)\n')
            f.write('    AUDIO = {\n' + '\n'.join(table) + '\n    },\n')
        print('\n%d clip, tablo: %s' % (len(table), table_path))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
