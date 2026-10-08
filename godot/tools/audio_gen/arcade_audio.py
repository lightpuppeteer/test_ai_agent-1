"""
Chiptune sounds and a little arcade music loop for the Island Arcade.

    python3 -I tools/audio_gen/arcade_audio.py <out_dir>
"""

import os
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import synth  # noqa: E402
from synth import SR, hz, midi, save_ogg, save_wav, t_axis  # noqa: E402


def square(f, dur, duty=0.5, vel=0.5, a=0.004, r=0.04):
    t = t_axis(dur)
    if np.isscalar(f):
        ph = f * t
    else:
        ph = np.cumsum(f) / SR
    x = np.where((ph % 1.0) < duty, 1.0, -1.0)
    e = synth.env_adsr(len(t), a=a, d=0.05, s=0.75, r=r)
    return x * e * vel


def tri(f, dur, vel=0.5):
    t = t_axis(dur)
    x = signal.sawtooth(2 * np.pi * f * t, 0.5)
    return x * synth.env_adsr(len(t), a=0.003, d=0.05, s=0.8, r=0.03) * vel


def noise(dur, vel=0.3, decay=30.0):
    t = t_axis(dur)
    return synth.RNG.uniform(-1, 1, len(t)) * np.exp(-t * decay) * vel


def seq(notes, step, inst=square, **kw):
    out = []
    for n in notes:
        if n is None:
            out.append(np.zeros(int(step * SR)))
        else:
            out.append(inst(hz(midi(n)), step, **kw))
    return np.concatenate(out)


def sweep(f0, f1, dur, duty=0.5, vel=0.5):
    t = t_axis(dur)
    f = f0 * (f1 / f0) ** (t / dur)
    return square(f, dur, duty, vel)


def make_sfx(out):
    w = lambda name, x: save_wav(os.path.join(out, name + ".wav"), x)  # noqa: E731
    w("arcade_coin", np.concatenate([square(hz(midi("B5")), 0.07, 0.5, 0.4), square(hz(midi("E6")), 0.22, 0.5, 0.4, r=0.15)]))
    w("arcade_jump", sweep(300, 900, 0.14, 0.25, 0.35))
    w("arcade_point", seq(["C6", "G6"], 0.06, vel=0.32, duty=0.25))
    w("arcade_treat", seq(["E6", "G6", "C7"], 0.045, vel=0.28, duty=0.25))
    w("arcade_hit", np.concatenate([sweep(500, 90, 0.25, 0.5, 0.4)]) + np.pad(noise(0.2, 0.35, 18), (0, int(0.05 * SR))))
    w("arcade_over", seq(["G5", "E5", "C5", None, "C4"], 0.14, vel=0.35, duty=0.5))
    w("arcade_win", seq(["C5", "E5", "G5", "C6", None, "G5", "C6"], 0.09, vel=0.35, duty=0.25))
    w("arcade_select", square(hz(midi("A5")), 0.05, 0.25, 0.3))
    w("arcade_plop", sweep(700, 250, 0.09, 0.5, 0.3))
    w("arcade_wrong", seq(["E4", "C4"], 0.11, vel=0.35, duty=0.5))
    t = t_axis(1.2)
    whirr = square(120 + 25 * np.sin(2 * np.pi * 9 * t), 1.2, 0.5, 0.18) * np.minimum(1, t * 20)
    w("arcade_claw", whirr)
    w("arcade_grab", np.concatenate([noise(0.05, 0.4, 60), sweep(200, 140, 0.12, 0.5, 0.3)]))


def make_music(out):
    """An upbeat 8-bar chiptune loop (lead + bass + arpeggio + noise hats)."""
    bpm = 132
    beat = 60.0 / bpm
    bars = 8
    n = int(bars * 4 * beat * SR)
    mix = np.zeros(n)

    def put(x, at):
        i = int(at * SR)
        j = min(n, i + len(x))
        if i < n:
            mix[i:j] += x[: j - i]

    prog = ["C", "A", "F", "G", "C", "A", "F", "G"]
    roots = {"C": "C3", "A": "A2", "F": "F2", "G": "G2"}
    triads = {"C": ["C5", "E5", "G5"], "A": ["A4", "C5", "E5"], "F": ["F4", "A4", "C5"], "G": ["G4", "B4", "D5"]}
    for b, ch in enumerate(prog):
        t0 = b * 4 * beat
        # Bass: octave bounce on eighths.
        r = midi(roots[ch])
        for k in range(8):
            put(tri(hz(r + (12 if k % 2 else 0)), beat * 0.48, 0.42), t0 + k * beat * 0.5)
        # Arpeggio on sixteenths.
        tri_n = triads[ch]
        for k in range(16):
            put(square(hz(midi(tri_n[k % 3])), beat * 0.24, 0.125, 0.08), t0 + k * beat * 0.25)
        # Hats + kick.
        for k in range(8):
            put(noise(0.04, 0.12 if k % 2 else 0.06, 90), t0 + k * beat * 0.5)
        for k in [0, 2]:
            put(sweep(160, 50, 0.12, 0.5, 0.4), t0 + k * beat)
    melody = ("E5:1 G5:.5 C6:.5 B5:1 G5:1 A5:1 C6:.5 A5:.5 E5:2 F5:1 A5:.5 C6:.5 D6:1 C6:1 B5:1 G5:1 D5:2 "
              "E5:.5 G5:.5 C6:1 E6:1 D6:.5 C6:.5 A5:1 C6:.5 E6:.5 A5:2 F5:.5 A5:.5 C6:1 A5:.5 F5:.5 G5:1 B5:1 D6:1 C6:1")
    t = 0.0
    for note, beats in synth.parse_melody(melody):
        if note is not None:
            put(square(hz(note), beats * beat * 0.9, 0.25, 0.16, r=0.06), t)
        t += beats * beat
    mix = mix / max(1e-9, np.max(np.abs(mix))) * 0.8
    stereo = np.stack([mix, mix], 1)
    save_ogg(os.path.join(out, "music_arcade.ogg"), stereo)


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    make_sfx(out)
    make_music(out)
