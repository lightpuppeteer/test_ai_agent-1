"""
Offline synthesiser for the game's music and sound effects.

    python3 -I tools/audio_gen/synth.py <out_dir>

Everything is generated from code (no samples), so it is ours to use and easy to
tweak: tempos, chords and melodies are plain lists below. Output is OGG Vorbis
(music, loops) and WAV (short effects).
"""

import math
import os
import subprocess
import sys

import numpy as np
from scipy import signal

SR = 32000
RNG = np.random.default_rng(7)

NOTE_INDEX = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
              "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    """'A4' → 69, 'Bb3' → 58."""
    n, o = (name[:2], name[2:]) if len(name) > 2 and name[1] in "#b" else (name[:1], name[1:])
    return 12 * (int(o) + 1) + NOTE_INDEX[n]


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


CHORDS = {
    "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "6": [0, 4, 7, 9],
    "sus": [0, 5, 7, 10], "m9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14], "add9": [0, 4, 7, 14],
}


def chord(name, octave=3):
    """'Fmaj7' → root midi, intervals."""
    root = name[:2] if len(name) > 1 and name[1] in "#b" else name[:1]
    kind = name[len(root):] or "maj7"
    return midi(root + str(octave)), CHORDS[kind]


# ---------------------------------------------------------------------------
# Instruments (mono numpy arrays)
# ---------------------------------------------------------------------------

def env_adsr(n, a=0.005, d=0.1, s=0.6, r=0.1, sustain_len=None):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(n - a_n - d_n - r_n, 0) if sustain_len is None else int(sustain_len * SR)
    e = np.concatenate([np.linspace(0, 1, a_n, False), np.linspace(1, s, d_n, False), np.full(s_n, s),
                        np.linspace(s, 0, r_n)])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def kalimba(f, dur=1.2, vel=1.0):
    t = t_axis(dur)
    e = np.exp(-t * 5.5)
    x = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 30)
    x += 0.12 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 9)
    click = RNG.normal(0, 1, len(t)) * np.exp(-t * 400) * 0.08
    return (x * e + click) * vel * np.minimum(1, t / 0.002)


def marimba(f, dur=1.0, vel=1.0):
    t = t_axis(dur)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * 6) + 0.3 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 22)
    x += 0.08 * np.sin(2 * np.pi * f * 10 * t) * np.exp(-t * 60)
    return x * vel * np.minimum(1, t / 0.003)


def epiano(f, dur=1.6, vel=1.0):
    """FM electric piano (Rhodes-like)."""
    t = t_axis(dur)
    idx = 1.6 * np.exp(-t * 3.5) + 0.3
    mod = np.sin(2 * np.pi * f * t)
    x = np.sin(2 * np.pi * f * t + idx * mod)
    tine = 0.18 * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t * 40)
    e = np.exp(-t * 1.6) * np.minimum(1, t / 0.004)
    return (x + tine) * e * vel


def music_box(f, dur=2.0, vel=1.0):
    t = t_axis(dur)
    x = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t * 6)
    x += 0.2 * np.sin(2 * np.pi * f * 5.97 * t) * np.exp(-t * 12)
    return x * np.exp(-t * 2.2) * np.minimum(1, t / 0.001) * vel


def pluck(f, dur=1.5, vel=1.0, bright=0.5):
    """Karplus–Strong nylon-ish guitar."""
    n = int(dur * SR)
    period = max(2, int(SR / f))
    buf = RNG.uniform(-1, 1, period)
    # Soften the excitation (fingers, not a pick).
    buf = np.convolve(buf, np.ones(3) / 3, "same")
    out = np.zeros(n)
    decay = 0.996 - (1 - bright) * 0.004
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = decay * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return out * vel * 0.7


def bass(f, dur=0.8, vel=1.0):
    t = t_axis(dur)
    x = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 2 * t) + 0.1 * np.sin(2 * np.pi * f * 3 * t)
    e = np.exp(-t * 3.0) * np.minimum(1, t / 0.008)
    return x * e * vel


def pad(f, dur=4.0, vel=1.0):
    t = t_axis(dur)
    x = np.zeros_like(t)
    for d in (-0.08, 0.0, 0.07):
        ff = f * 2 ** (d / 12)
        x += signal.sawtooth(2 * np.pi * ff * t + RNG.uniform(0, 6))
    b, a = signal.butter(2, 1200 / (SR / 2))
    x = signal.lfilter(b, a, x) / 3
    e = env_adsr(len(t), a=min(1.2, dur * 0.3), d=0.5, s=0.8, r=min(1.5, dur * 0.3))
    return x * e * vel


def flute(f, dur=1.0, vel=1.0):
    t = t_axis(dur)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(1, t / 0.3)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    x = np.sin(ph) + 0.2 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    breath = RNG.normal(0, 1, len(t))
    b, a = signal.butter(2, [f * 0.8 / (SR / 2), min(0.99, f * 3 / (SR / 2))], "band")
    x += 0.15 * signal.lfilter(b, a, breath)
    e = env_adsr(len(t), a=0.06, d=0.1, s=0.85, r=0.12)
    return x * e * vel


def shaker(dur=0.12, vel=1.0):
    t = t_axis(dur)
    n = RNG.normal(0, 1, len(t))
    b, a = signal.butter(2, 5000 / (SR / 2), "high")
    return signal.lfilter(b, a, n) * np.exp(-t * 40) * np.minimum(1, t / 0.01) * vel


def rim(dur=0.08, vel=1.0):
    t = t_axis(dur)
    x = np.sin(2 * np.pi * 1700 * t) * np.exp(-t * 90) + RNG.normal(0, 0.3, len(t)) * np.exp(-t * 200)
    return x * vel


def kick(dur=0.3, vel=1.0):
    t = t_axis(dur)
    f = 50 + 70 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * vel


# ---------------------------------------------------------------------------
# Mixing helpers
# ---------------------------------------------------------------------------

class Track:
    def __init__(self, length_s):
        self.n = int(length_s * SR)
        self.l = np.zeros(self.n + SR * 6)
        self.r = np.zeros(self.n + SR * 6)

    def add(self, x, at_s, gain=1.0, pan=0.0):
        i = int(at_s * SR)
        x = x * gain
        gl = math.cos((pan + 1) * math.pi / 4)
        gr = math.sin((pan + 1) * math.pi / 4)
        end = min(len(self.l), i + len(x))
        self.l[i:end] += x[: end - i] * gl
        self.r[i:end] += x[: end - i] * gr

    def render(self, reverb=0.25, loop=True):
        ir = reverb_ir(2.2)
        wl = signal.fftconvolve(self.l, ir)[: len(self.l)]
        wr = signal.fftconvolve(self.r, ir[::-1] * 0.9 + np.roll(ir, 37) * 0.1)[: len(self.r)]
        l = self.l * (1 - reverb * 0.5) + wl * reverb
        r = self.r * (1 - reverb * 0.5) + wr * reverb
        if loop:
            # Wrap the tail past the loop point back onto the start: seamless loop.
            tail_l, tail_r = l[self.n:], r[self.n:]
            l, r = l[: self.n].copy(), r[: self.n].copy()
            k = min(len(tail_l), self.n)
            l[:k] += tail_l[:k]
            r[:k] += tail_r[:k]
        st = np.stack([l, r], 1)
        return st / (np.max(np.abs(st)) + 1e-9) * 0.85


def reverb_ir(seconds):
    t = t_axis(seconds)
    ir = RNG.normal(0, 1, len(t)) * np.exp(-t * 3.2)
    b, a = signal.butter(1, 5000 / (SR / 2))
    ir = signal.lfilter(b, a, ir)
    ir[0] = 0
    return ir / np.sqrt(np.sum(ir ** 2)) * 0.6


def save_ogg(path, stereo):
    wav = path.replace(".ogg", ".tmp.wav")
    save_wav(wav, stereo)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.remove(wav)


def save_wav(path, x):
    from scipy.io import wavfile
    x = np.asarray(x)
    x = x / max(1e-9, np.max(np.abs(x))) * 0.9 if np.max(np.abs(x)) > 0.9 else x
    wavfile.write(path, SR, (x * 32767).astype(np.int16))


# ---------------------------------------------------------------------------
# Compositions
# ---------------------------------------------------------------------------

def parse_melody(text):
    """'A4:1 C5:.5 r:1 …' → [(note|None, beats)]"""
    out = []
    for tok in text.split():
        n, d = tok.split(":")
        out.append((None if n == "r" else midi(n), float(d)))
    return out


def song(bpm, bars, chords, melody, lead, comp, swing=0.0, perc=True, bass_style="walk",
         lead_gain=0.5, comp_gain=0.22, bass_gain=0.42, pads=0.0, arps=False, reverb=0.28):
    beat = 60.0 / bpm
    tr = Track(bars * 4 * beat)

    def tswing(b):
        frac = b % 1.0
        return b + (swing if abs(frac - 0.5) < 1e-6 else 0.0)

    # Chords: one or two per bar ("Am7 D7").
    for bar, spec in enumerate(chords):
        names = spec.split()
        per = 4 / len(names)
        for k, nm in enumerate(names):
            root, iv = chord(nm, 3)
            start = (bar * 4 + k * per) * beat
            notes = [root + 12 + i for i in iv[1:]] + [root + 12]
            # comping rhythm: on beat and the "and" of 2
            hits = [0.0, 1.5] if per >= 4 else [0.0]
            if arps:
                for j, b in enumerate(np.arange(0, per, 0.5)):
                    m = notes[j % len(notes)] + (12 if j % 4 == 3 else 0)
                    tr.add(comp(hz(m), 1.6, 0.8), start + tswing(b) * beat, comp_gain, pan=0.3 * math.sin(j))
            else:
                for h in hits:
                    for m in notes:
                        tr.add(comp(hz(m), 1.8, 0.7), start + tswing(h) * beat + RNG.uniform(0, 0.01), comp_gain / 2.2, pan=-0.25)
            if pads > 0:
                for m in notes[:3]:
                    tr.add(pad(hz(m), per * beat + 0.8), start, pads, pan=0.0)
            # Bass
            if bass_style == "walk" and per >= 4:
                pattern = [(0, root - 12), (2, root - 12 + iv[2] - 12 + 12), (3, root - 12 + 10 if iv[1] == 3 else root - 12 + 11)]
                pattern = [(0, root - 12), (2, root - 12 + iv[2]), (3.5, root - 12 + 12)]
            else:
                pattern = [(0, root - 12)] if per < 4 else [(0, root - 12), (2.5, root - 12 + iv[2])]
            for b, m in pattern:
                if b < per:
                    tr.add(bass(hz(m), beat * 1.6), start + tswing(b) * beat, bass_gain)
    # Melody
    t = 0.0
    for m, d in melody:
        if m is not None:
            tr.add(lead(hz(m), max(0.6, d * beat * 1.6), 0.9), tswing(t) * beat, lead_gain, pan=0.15)
        t += d
    # Percussion: gentle shaker on 8ths, rim on 2 and 4, soft kick on 1.
    if perc:
        for b in np.arange(0, bars * 4, 0.5):
            tr.add(shaker(0.1, 0.5 if b % 1 else 0.8), tswing(b) * beat, 0.05, pan=0.4)
            if b % 4 in (1.0, 3.0):
                tr.add(rim(), b * beat, 0.06, pan=-0.2)
            if b % 4 == 0.0:
                tr.add(kick(), b * beat, 0.16)
    return tr.render(reverb=reverb)


DAY_CHORDS = ["Fmaj7", "Am7 D7", "Gm7", "C7", "Fmaj7", "Bbmaj7", "Am7 D7", "Gm7 C7",
              "Bbmaj7", "Am7", "Gm7", "Csus C7", "Fmaj7", "Dm7", "Gm7 C7", "F6"]
DAY_MELODY = parse_melody("""
A4:1 C5:.5 A4:.5 G4:1 F4:1   E4:1.5 F4:.5 A4:1 C5:1   D5:1 C5:.5 Bb4:.5 A4:1 G4:1   E4:2 G4:1 C5:1
A4:1 C5:.5 F5:.5 E5:1 C5:1   D5:1.5 C5:.5 Bb4:1 D5:1   C5:1 A4:.5 C5:.5 D5:1 F#4:1   G4:1.5 A4:.5 Bb4:1 E4:1
D5:1 F5:1 E5:.5 D5:.5 C5:1   C5:1 E5:1 D5:.5 C5:.5 A4:1   Bb4:1 D5:1 C5:.5 Bb4:.5 A4:1   G4:2 r:1 C5:1
A4:1 G4:.5 A4:.5 C5:1 F5:1   E5:1 D5:1 A4:2   Bb4:1 A4:.5 G4:.5 E4:1 G4:1   F4:3 r:1
""")

GOLDEN_CHORDS = ["Dbmaj7", "Cm7", "Bbm7", "Ebsus Eb7", "Abmaj7", "Fm7", "Bbm7 Eb7", "Abmaj7",
                 "Dbmaj7", "C7", "Fm7", "Bbm7 Eb7"]
GOLDEN_MELODY = parse_melody("""
F5:2 Eb5:1 C5:1   G4:2 Bb4:1 C5:1   Db5:1.5 C5:.5 Bb4:1 Ab4:1   G4:3 r:1
C5:2 Eb5:1 Ab5:1   G5:1.5 F5:.5 Eb5:2   F5:1 Eb5:1 Db5:1 C5:1   Ab4:3 r:1
F5:1.5 Ab5:.5 G5:1 F5:1   E5:2 G4:2   Ab4:1 C5:1 Eb5:1 F5:1   G5:1 F5:1 Eb5:2
""")

NIGHT_CHORDS = ["Cmaj7", "Am7", "Fmaj7", "G6", "Em7", "Am7", "Dm7 G7", "Cmaj7"]
NIGHT_MELODY = parse_melody("""
E5:1 G5:1 C6:1 B5:1   A5:2 E5:2   F5:1 A5:1 C6:1 A5:1   G5:3 r:1
B5:1 G5:1 E5:1 G5:1   C6:2 A5:2   F5:1 A5:1 G5:1 F5:1   E5:3 r:1
""")


def make_music(out):
    print("music: day")
    save_ogg(os.path.join(out, "music_day.ogg"),
             song(102, 16, DAY_CHORDS, DAY_MELODY, kalimba, epiano, swing=0.08, lead_gain=0.55, comp_gain=0.2))
    print("music: golden")
    save_ogg(os.path.join(out, "music_golden.ogg"),
             song(84, 12, GOLDEN_CHORDS, GOLDEN_MELODY, epiano, pluck, swing=0.05, arps=True, perc=True,
                  lead_gain=0.5, comp_gain=0.16, pads=0.03, bass_style="simple", reverb=0.34))
    print("music: night")
    night_mel = NIGHT_MELODY + NIGHT_MELODY
    save_ogg(os.path.join(out, "music_night.ogg"),
             song(66, 16, NIGHT_CHORDS + NIGHT_CHORDS, night_mel, music_box, epiano, arps=True, perc=False,
                  lead_gain=0.42, comp_gain=0.1, pads=0.035, bass_style="simple", bass_gain=0.3, reverb=0.42))
    print("music: title")
    title_mel = parse_melody("C5:1 E5:1 G5:1 C6:1 B5:2 G5:2 A5:1 G5:1 E5:1 D5:1 C5:3 r:1")
    save_ogg(os.path.join(out, "music_title.ogg"),
             song(78, 4, ["Fmaj7", "Em7", "Dm7 G7", "Cmaj7"], title_mel, music_box, pluck, arps=True, perc=False,
                  lead_gain=0.45, comp_gain=0.12, pads=0.04, bass_style="simple", reverb=0.4))


# ---------------------------------------------------------------------------
# Sound effects
# ---------------------------------------------------------------------------

def bandnoise(dur, lo, hi, decay, attack=0.004):
    t = t_axis(dur)
    n = RNG.normal(0, 1, len(t))
    b, a = signal.butter(2, [lo / (SR / 2), min(0.99, hi / (SR / 2))], "band")
    return signal.lfilter(b, a, n) * np.exp(-t * decay) * np.minimum(1, t / attack)


def mix(*xs):
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[: len(x)] += x
    return out


def footstep(surface, i):
    if surface == "grass":
        x = mix(bandnoise(0.16, 900, 5000, 28) * 0.8, bandnoise(0.12, 200, 800, 40) * 0.5)
    elif surface == "sand":
        x = bandnoise(0.2, 300, 3000, 18, attack=0.02) * 0.7
    elif surface == "stone":
        x = mix(bandnoise(0.08, 1500, 7000, 70) * 0.6, bandnoise(0.1, 150, 600, 50) * 0.8)
    else:  # wood
        t = t_axis(0.14)
        x = mix(np.sin(2 * np.pi * (150 + 30 * i) * t) * np.exp(-t * 35), bandnoise(0.14, 400, 2500, 50) * 0.4)
    x *= RNG.uniform(0.85, 1.0)
    return x


def tone_seq(notes, inst=marimba, step=0.09, dur=0.6, gain=0.6):
    total = step * len(notes) + dur
    out = np.zeros(int(total * SR))
    for k, n in enumerate(notes):
        x = inst(hz(midi(n)), dur)
        i = int(k * step * SR)
        out[i:i + len(x)] += x * gain
    return out


def vowel(formants, dur=0.075, f0=200):
    t = t_axis(dur)
    src = signal.sawtooth(2 * np.pi * f0 * t, 0.98)
    x = np.zeros_like(t)
    for fc, bw, g in formants:
        b, a = signal.butter(2, [max(50, fc - bw) / (SR / 2), (fc + bw) / (SR / 2)], "band")
        x += g * signal.lfilter(b, a, src)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7
    return x * e


def make_sfx(out):
    for s in ("grass", "sand", "stone", "wood"):
        for i in range(3):
            save_wav(os.path.join(out, f"step_{s}_{i}.wav"), footstep(s, i) * 0.8)
    ui = {
        "ui_blip": tone_seq(["E6", "A6"], step=0.05, dur=0.25, gain=0.5),
        "ui_open": tone_seq(["C6", "E6", "G6"], step=0.04, dur=0.3, gain=0.45),
        "ui_close": tone_seq(["G6", "E6", "C6"], step=0.04, dur=0.3, gain=0.45),
        "ui_step": tone_seq(["G5", "C6"], inst=kalimba, step=0.08, dur=0.6, gain=0.5),
        "ui_quest_start": tone_seq(["C5", "E5", "G5", "C6"], inst=kalimba, step=0.09, dur=0.8, gain=0.5),
        "ui_quest_done": tone_seq(["C5", "E5", "G5", "C6", "E6", "G6", "C7"], inst=kalimba, step=0.075, dur=1.0, gain=0.45)
        + 0,
        "ui_pickup": tone_seq(["A5", "E6"], inst=kalimba, step=0.07, dur=0.5, gain=0.55),
        "ui_talk": tone_seq(["D6"], step=0.0, dur=0.15, gain=0.5),
    }
    t = t_axis(0.18)
    ui["ui_camera"] = np.concatenate([bandnoise(0.05, 1000, 8000, 80), np.zeros(int(0.03 * SR)), bandnoise(0.08, 600, 6000, 60)])
    ui["sit"] = bandnoise(0.25, 100, 900, 18, attack=0.03) * 0.8
    ui["jump"] = np.sin(2 * np.pi * np.cumsum(300 + 500 * t_axis(0.12) / 0.12) / SR) * np.exp(-t_axis(0.12) * 18) * 0.4
    ui["splash"] = bandnoise(0.6, 400, 6000, 7, attack=0.01) * 0.6
    for k, v in ui.items():
        save_wav(os.path.join(out, f"{k}.wav"), v)
    # Animalese-ish babble: five vowel syllables.
    vowels = {"a": [(800, 120, 1.0), (1200, 150, 0.6)], "e": [(450, 90, 1.0), (2000, 200, 0.5)],
              "i": [(300, 70, 1.0), (2400, 250, 0.45)], "o": [(500, 90, 1.0), (850, 120, 0.6)],
              "u": [(330, 70, 1.0), (750, 100, 0.5)]}
    for k, f in vowels.items():
        x = vowel(f, 0.08, 220)
        click = bandnoise(0.02, 2000, 7000, 150) * 0.15
        x[: len(click)] += click
        save_wav(os.path.join(out, f"babble_{k}.wav"), x * 0.8)
    # Ambience loops.
    print("ambience")
    n = 20 * SR
    t = np.arange(n) / SR
    brown = np.cumsum(RNG.normal(0, 1, n))
    brown -= signal.savgol_filter(brown, 4001, 1)
    swell = 0.55 + 0.45 * (0.5 + 0.5 * np.sin(2 * np.pi * t / 6.6)) ** 2 * (0.7 + 0.3 * np.sin(2 * np.pi * t / 20 + 1))
    hiss = bandnoise(20, 600, 5000, 0) * 0.25
    waves = brown / np.max(np.abs(brown)) * swell + hiss * swell ** 2
    # crossfade ends for a seamless loop
    fade = int(1.0 * SR)
    waves[:fade] = waves[:fade] * np.linspace(0, 1, fade) + waves[-fade:] * np.linspace(1, 0, fade)
    waves = waves[:-fade]
    save_ogg(os.path.join(out, "amb_ocean.ogg"), np.stack([waves, np.roll(waves, 3000)], 1) * 0.8)
    crick = np.zeros(n)
    for k in range(260):
        i = RNG.integers(0, n - SR)
        f = RNG.uniform(4200, 5200)
        tt = t_axis(0.12)
        chirp = np.sin(2 * np.pi * f * tt) * (np.sin(2 * np.pi * 30 * tt) > 0) * np.exp(-tt * 10)
        crick[i:i + len(chirp)] += chirp * RNG.uniform(0.2, 0.6)
    save_ogg(os.path.join(out, "amb_night.ogg"), np.stack([crick, np.roll(crick, 9000)], 1) * 0.5)
    water = bandnoise(8, 800, 6000, 0) * (0.7 + 0.3 * RNG.random(int(8 * SR)))
    save_ogg(os.path.join(out, "amb_fountain.ogg"), np.stack([water, water], 1) * 0.5)
    for k in range(4):
        tt = t_axis(0.35)
        f0 = RNG.uniform(2500, 4200)
        f = f0 * (1 + 0.25 * np.sin(2 * np.pi * RNG.uniform(10, 16) * tt))
        b = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / 0.35) ** 2
        if k % 2:
            b = np.concatenate([b, np.zeros(int(0.05 * SR)), b * 0.8])
        save_wav(os.path.join(out, f"bird_{k}.wav"), b * 0.5)
    # Car engine loop (exactly 1 s, harmonic so it loops cleanly).
    tt = np.arange(SR) / SR
    eng = sum(np.sin(2 * np.pi * 40 * h * tt + h) / h for h in range(1, 8)) + 0.2 * RNG.normal(0, 1, SR) * 0.05
    save_wav(os.path.join(out, "car_engine.wav"), eng / np.max(np.abs(eng)) * 0.6)


def make_story_sfx(out):
    """Sounds for the story moments."""
    t = t_axis(0.35)
    # Door: a wooden knock-thump plus a little latch click.
    door = mix(np.sin(2 * np.pi * 110 * t) * np.exp(-t * 18) * 0.8, bandnoise(0.35, 300, 2000, 25) * 0.5,
               np.concatenate([np.zeros(int(0.12 * SR)), bandnoise(0.05, 2000, 6000, 120) * 0.4]))
    save_wav(os.path.join(out, "door.wav"), door * 0.8)
    # Chest: creaky lid + sparkly arpeggio.
    tc = t_axis(0.5)
    creak = np.sin(2 * np.pi * np.cumsum(180 + 120 * np.sin(2 * np.pi * 3 * tc)) / SR) * np.exp(-tc * 4) * 0.3
    sparkle = tone_seq(["E6", "G#6", "B6", "E7"], inst=kalimba, step=0.06, dur=0.6, gain=0.5)
    save_wav(os.path.join(out, "chest.wav"), mix(creak, np.concatenate([np.zeros(int(0.25 * SR)), sparkle])))
    # Smooch: a soft "mwah".
    ts = t_axis(0.25)
    sm = vowel([(500, 120, 1.0), (900, 150, 0.4)], 0.18, 240) * 0.6
    pop = bandnoise(0.03, 1500, 6000, 200) * 0.6
    save_wav(os.path.join(out, "smooch.wav"), mix(pop, np.concatenate([np.zeros(int(0.02 * SR)), sm])))
    # LEVEL UP: an 8-bit-ish arcade jingle.
    lv = np.zeros(0)
    for n in ["C5", "E5", "G5", "C6", "G5", "C6", "E6", "G6", "C7"]:
        tt = t_axis(0.07)
        sq = np.sign(np.sin(2 * np.pi * hz(midi(n)) * tt)) * 0.3 * np.exp(-tt * 6)
        lv = np.concatenate([lv, sq])
    tt = t_axis(0.5)
    lv = np.concatenate([lv, np.sign(np.sin(2 * np.pi * hz(midi("C7")) * tt)) * 0.3 * np.exp(-tt * 4)])
    save_wav(os.path.join(out, "levelup.wav"), lv)
    # Fireworks.
    tl = t_axis(1.0)
    launch = bandnoise(1.0, 1500, 7000, 3, attack=0.05) * 0.4 * np.linspace(1, 0.2, len(tl))
    whistle = np.sin(2 * np.pi * np.cumsum(1200 + 900 * tl) / SR) * 0.08 * np.exp(-tl * 1.5)
    save_wav(os.path.join(out, "firework_launch.wav"), launch + whistle)
    boom = mix(np.sin(2 * np.pi * np.cumsum(70 + 60 * np.exp(-t_axis(1.5) * 8)) / SR) * np.exp(-t_axis(1.5) * 4),
               bandnoise(1.5, 200, 4000, 3, attack=0.002) * 0.6,
               bandnoise(1.5, 3000, 9000, 2.5, attack=0.2) * 0.25)
    save_wav(os.path.join(out, "firework_boom.wav"), boom * 0.9)
    # Volcano eruption: deep rumble + blast + crackle.
    te = t_axis(5.0)
    rumble = bandnoise(5.0, 25, 160, 0.5, attack=0.3) * 1.2
    blast = bandnoise(5.0, 60, 1500, 1.5, attack=0.01)
    crackle = np.zeros(len(te))
    for k in range(120):
        i = RNG.integers(0, len(te) - 2000)
        crackle[i:i + 400] += RNG.normal(0, 1, 400) * np.exp(-np.arange(400) / 60) * RNG.uniform(0.1, 0.4)
    save_ogg(os.path.join(out, "eruption.ogg"), np.stack([rumble + blast + crackle * 0.5] * 2, 1) * 0.6)
    # Meow.
    tm = t_axis(0.45)
    f0 = 520 + 260 * np.sin(np.pi * tm / 0.45)
    meow = signal.sawtooth(2 * np.pi * np.cumsum(f0) / SR, 0.5)
    b, a = signal.butter(2, [700 / (SR / 2), 2600 / (SR / 2)], "band")
    meow = signal.lfilter(b, a, meow) * np.sin(np.pi * tm / 0.45) ** 1.5
    save_wav(os.path.join(out, "meow.wav"), meow * 0.8)
    # Pop.
    tp = t_axis(0.12)
    save_wav(os.path.join(out, "pop.wav"), np.sin(2 * np.pi * np.cumsum(900 - 600 * tp / 0.12) / SR) * np.exp(-tp * 30) * 0.6)


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    which = sys.argv[2] if len(sys.argv) > 2 else "all"
    if which in ("all", "sfx"):
        make_sfx(out)
    if which in ("all", "music"):
        make_music(out)
    if which in ("all", "story"):
        make_story_sfx(out)
