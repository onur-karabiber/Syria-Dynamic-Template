# make_sfx.py | v0.1.0
# Synthesised score-card sound effects (no third-party audio, no licence
# questions). Output: out/Sounds/SCORE/{reward,penalty,mission_end}.ogg
#   reward      ~0.45 s  A5 -> E6 (rising perfect fifth), bell partials
#   penalty     ~0.40 s  E3 -> Eb3 (falling minor second), filtered square buzz
#   mission_end ~1.30 s  C5-E5-G5-C6 arpeggio, soft brass-like saw stack
# Mono 44.1 kHz, peak -3 dBFS, Vorbis via ffmpeg.
#
# Usage:  python make_sfx.py        (needs numpy + ffmpeg on PATH)

import os
import subprocess
import wave
import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "Sounds", "SCORE")


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env_ad(n, attack, decay_tau):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / decay_tau)


def bell(freq, dur):
    t = t_axis(dur)
    parts = [(1.0, 1.0, 0.22), (2.0, 0.35, 0.10), (3.01, 0.18, 0.06), (4.2, 0.08, 0.04)]
    y = np.zeros_like(t)
    for mult, amp, tau in parts:
        y += amp * np.sin(2 * np.pi * freq * mult * t) * env_ad(len(t), 0.003, tau)
    return y


def buzz(freq, dur):
    t = t_axis(dur)
    y = np.zeros_like(t)
    for k in range(1, 16, 2):                       # odd harmonics -> square
        y += np.sin(2 * np.pi * freq * k * t) / k * (0.75 ** (k // 2))
    e = np.clip(t / 0.006, 0, 1) * np.clip((dur - t) / 0.03, 0, 1)
    return y * e


def brass(freq, dur):
    t = t_axis(dur)
    y = np.zeros_like(t)
    for k in range(1, 9):                           # saw-ish, rolled off
        y += np.sin(2 * np.pi * freq * k * t + 0.3 * k) / k * (0.8 ** k)
    e = np.clip(t / 0.025, 0, 1) * np.exp(-t / (dur * 0.9))
    return y * e


def place(buf, sig, at):
    i = int(at * SR)
    buf[i:i + len(sig)] += sig[: max(0, len(buf) - i)]


def lowpass(y, cutoff):
    # one-pole, run forward and backward (zero phase)
    a = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        out = np.empty_like(y)
        acc = 0.0
        for i, v in enumerate(y):
            acc = (1 - a) * v + a * acc
            out[i] = acc
        y = out[::-1]
    return y


def normalise(y, peak_db=-3.0):
    y = y - np.mean(y)
    return y / np.max(np.abs(y)) * (10 ** (peak_db / 20))


def write_ogg(name, y):
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype("<i2").tobytes())
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                    "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
    os.remove(wav)
    print(name, round(len(y) / SR, 2), "s", os.path.getsize(ogg), "bytes")


def main():
    # reward: A5 -> E6
    y = np.zeros(int(SR * 0.45))
    place(y, bell(880.0, 0.40), 0.00)
    place(y, bell(1318.51, 0.38), 0.07)
    write_ogg("reward", normalise(y))

    # penalty: E3 -> Eb3, low buzz
    y = np.zeros(int(SR * 0.40))
    place(y, buzz(164.81, 0.17), 0.00)
    place(y, buzz(155.56, 0.20), 0.19)
    write_ogg("penalty", normalise(lowpass(y, 1400)))

    # mission end: C5 E5 G5 C6, last note held
    y = np.zeros(int(SR * 1.30))
    for f, at, d in ((523.25, 0.00, 0.30), (659.26, 0.12, 0.30),
                     (783.99, 0.24, 0.35), (1046.50, 0.38, 0.90)):
        place(y, brass(f, d), at)
    write_ogg("mission_end", normalise(lowpass(y, 3500)))


if __name__ == "__main__":
    main()
