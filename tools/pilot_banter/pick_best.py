# pick_best.py | v1.0.0
# Re-renders Pilot_Banter clips several times and keeps the take an ASR model understands best.
# Piper is stochastic: the same text gives a clearer or a muddier take each time; the cockpit
# (mask) chain makes short aviation words ("flaps", "probe", "speed brake") easy to lose.
#
#   python tools/pilot_banter/pick_best.py --prefix pc_ --below 0.75 --tries 6
#   python tools/pilot_banter/pick_best.py pc_c3_ok_1 pc_c7_in_1 --tries 8
#   then: python tts/make_clips.py --set pb --missing     (rewrites the AUDIO block with the new lengths)
#
# Score = share of the reference words found in the transcript (faster-whisper base.en, CPU int8),
# after normalising (yep = yeah, alright = all right, digits = words, apostrophes dropped).
# A clip already at or above --below is left alone; otherwise the best of the current file and
# --tries new takes is kept. --budget stops before a time limit (the PC's cloud shell allows 180 s
# per call; run again, finished clips are skipped once they pass).
# Needs: pip install faster-whisper (the base.en model is downloaded once from Hugging Face).
import argparse, os, re, shutil, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tts'))
import make_clips as mc  # noqa: E402

CSVS, OUTDIR, _ = mc.SETS['pb']
NUM = {'1': 'one', '2': 'two', '3': 'three', '4': 'four', '5': 'five'}
SAME = {'yeah': 'yep', 'yup': 'yep', 'allright': 'alright', 'okay': 'ok', 'k': 'ok', 'break': 'brake'}   # homophones


def norm(s):
    s = s.lower().replace("'", '').replace('all right', 'alright')
    out = []
    for w in re.findall(r'[a-z0-9]+', s):
        w = NUM.get(w, w)
        w = SAME.get(w, w)
        if w.endswith('s') and len(w) > 3:
            w = w[:-1]                            # hooks / hook's / hook
        out.append(w)
    return out


def score(asr, ogg, ref):
    import numpy as np
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', ogg, '-f', 'f32le', '-ac', '1', '-ar', '16000', '-'])
    segs, _ = asr.transcribe(np.frombuffer(raw, dtype=np.float32), beam_size=5, language='en')
    hyp = ' '.join(s.text for s in segs).strip()
    r, h = norm(ref), norm(hyp)
    return (sum(1 for w in r if w in h) / max(1, len(r))), hyp


def rows():
    out = {}
    for csv in CSVS:
        for ln in open(csv, encoding='utf-8'):
            ln = ln.strip()
            if ln and not ln.startswith('#'):
                p = ln.split(';')
                out[p[0].strip()] = (p[1].strip(), p[2].strip())
    return out


def render(voice, text, ogg):
    name = mc.VOICE.get(voice)
    if not isinstance(name, tuple): name = (name,)
    name, pitch, spk, lmul = tuple(name) + (None, 1.0, None, 1.0)[len(name):]
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, 'raw.wav')
        mc.synth_segments(os.path.join(mc.VOICES, name), text, wav, spk, lmul)
        mc.cockpit(wav, ogg)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('ids', nargs='*')
    ap.add_argument('--prefix', default=None)
    ap.add_argument('--below', type=float, default=0.75)
    ap.add_argument('--tries', type=int, default=6)
    ap.add_argument('--budget', type=float, default=1e9, help='seconds')
    a = ap.parse_args()
    t0 = time.time()
    from faster_whisper import WhisperModel
    asr = WhisperModel('base.en', device='cpu', compute_type='int8')
    R = rows()
    ids = a.ids or sorted(k for k in R if a.prefix and k.startswith(a.prefix))
    for cid in ids:
        if time.time() - t0 > a.budget:
            print('BUDGET   stop before %s' % cid); return 2
        voice, text = R[cid]
        if text.startswith('<'):
            continue                                   # synthesized noise
        ref = mc.plain_text(text)
        ogg = os.path.join(OUTDIR, cid + '.ogg')
        best, hyp = score(asr, ogg, ref) if os.path.isfile(ogg) else (-1, '')
        if best >= a.below:
            print('OK       %-18s %.2f  %s' % (cid, best, hyp)); continue
        first = best
        with tempfile.TemporaryDirectory() as td:
            for k in range(a.tries):
                cand = os.path.join(td, 'c%d.ogg' % k)
                render(voice, text, cand)
                sc, h = score(asr, cand, ref)
                if sc > best:
                    best, hyp = sc, h
                    shutil.copyfile(cand, ogg)
                if best >= 0.999:
                    break
        print('%-8s %-18s %.2f -> %.2f  ref: %s | asr: %s' % ('BETTER' if best > first else 'KEPT', cid, first, best, ref, hyp))
    return 0


if __name__ == '__main__':
    sys.exit(main())
