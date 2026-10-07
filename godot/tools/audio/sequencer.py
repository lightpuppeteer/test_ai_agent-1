"""Tiny loop-aware sequencer: swing, humanisation, circular rendering, mixing."""
import zlib

import numpy as np

from dsp import (SR, nsamp, mtof, pan, reverb, make_ir, to_stereo, lowpass,
                 highpass, wrap_apply, biquad, lufs, peak_db)

# chord qualities: intervals from root
QUAL = {
    "maj7": [0, 4, 7, 11], "maj9": [0, 4, 7, 11, 14], "6": [0, 4, 7, 9],
    "69": [0, 4, 7, 9, 14], "m7": [0, 3, 7, 10], "m9": [0, 3, 7, 10, 14],
    "m6": [0, 3, 7, 9], "7": [0, 4, 7, 10], "9": [0, 4, 7, 10, 14],
    "13": [0, 4, 10, 14, 21], "7b9": [0, 4, 7, 10, 13], "7sus": [0, 5, 7, 10],
    "9sus": [0, 5, 7, 10, 14], "m7b5": [0, 3, 6, 10], "maj": [0, 4, 7],
    "m": [0, 3, 7], "add9": [0, 4, 7, 14],
}
# rootless-ish keyboard voicings (intervals above root, played mid-register)
EP_SHAPE = {
    "maj7": [4, 7, 11, 14], "maj9": [4, 7, 11, 14], "6": [4, 7, 9, 14],
    "69": [4, 7, 9, 14], "m7": [3, 7, 10, 14], "m9": [3, 7, 10, 14],
    "m6": [3, 7, 9, 14], "7": [4, 7, 10, 14], "9": [4, 10, 14, 19],
    "13": [4, 10, 14, 21], "7b9": [4, 7, 10, 13], "7sus": [5, 7, 10, 14],
    "9sus": [5, 10, 14, 19], "m7b5": [3, 6, 10, 15], "maj": [4, 7, 12, 16],
    "m": [3, 7, 12, 15], "add9": [4, 7, 14, 16],
}
# open guitar/harp style voicings (root at bottom)
OPEN_SHAPE = {
    "maj7": [0, 7, 11, 16], "maj9": [0, 7, 11, 14], "6": [0, 7, 9, 16],
    "69": [0, 7, 9, 14], "m7": [0, 7, 10, 15], "m9": [0, 7, 10, 14],
    "m6": [0, 7, 9, 15], "7": [0, 7, 10, 16], "9": [0, 7, 10, 14],
    "13": [0, 10, 16, 21], "7b9": [0, 7, 10, 13], "7sus": [0, 7, 10, 17],
    "9sus": [0, 7, 10, 14], "m7b5": [0, 6, 10, 15], "maj": [0, 7, 12, 16],
    "m": [0, 7, 12, 15], "add9": [0, 7, 14, 16],
}
NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
        "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10,
        "B": 11}


def parse_chord(name):
    """'Fmaj7', 'Bbm6', 'C9', 'F/Eb' style -> (root_pc, quality, bass_pc)."""
    bass = None
    if "/" in name:
        name, b = name.split("/")
        bass = NOTE[b]
    r = name[:2] if len(name) > 1 and name[1] in "#b" else name[:1]
    q = name[len(r):] or "maj"
    return NOTE[r], q, (NOTE[r] if bass is None else bass)


def place(pc, lo, hi):
    """Lowest midi note with pitch class pc in [lo, hi)."""
    m = lo + ((pc - lo) % 12)
    return m if m < hi else m - 12


class Song:
    def __init__(self, name, bpm, beats_per_bar, bars, swing=0.5, seed=0):
        self.name = name
        self.bpm = bpm
        self.bpb = beats_per_bar
        self.bars = bars
        self.swing = swing
        self.rng = np.random.default_rng(seed)
        self.N = nsamp(bars * beats_per_bar * 60.0 / bpm)
        self.tracks = {}
        self.chords = []  # (abs_beat_start, chord_name)

    # ---- time
    def beat_time(self, b):
        whole = np.floor(b)
        fr = b - whole
        s = self.swing
        tf = np.where(fr < 0.5, fr * 2 * s, s + (fr - 0.5) * 2 * (1 - s))
        return float((whole + tf) * 60.0 / self.bpm)

    def ab(self, bar, beat=0.0):
        return bar * self.bpb + beat

    # ---- chords
    def set_chords(self, bar_chords, start_bar=0):
        """bar_chords: list per bar, each a chord name or list of
        (beat, name) tuples."""
        for i, c in enumerate(bar_chords):
            bar = start_bar + i
            if isinstance(c, str):
                self.chords.append((self.ab(bar), c))
            else:
                for beat, name in c:
                    self.chords.append((self.ab(bar, beat), name))
        self.chords.sort()

    def chord_at(self, abs_beat):
        cur = self.chords[-1][1]
        for b, c in self.chords:
            if b <= abs_beat + 1e-6:
                cur = c
            else:
                break
        return cur

    def chord_spans(self):
        total = self.bars * self.bpb
        out = []
        for i, (b, c) in enumerate(self.chords):
            e = self.chords[i + 1][0] if i + 1 < len(self.chords) else total
            out.append((b, e, c))
        return out

    # ---- tracks
    def track(self, name, inst, gain=1.0, pan_=0.0, send=0.2, line=False,
              human_t=0.006, human_v=0.07, hp=None, lp=None, stereo_inst=False):
        self.tracks[name] = dict(inst=inst, gain=gain, pan=pan_, send=send,
                                 line=line, events=[], human_t=human_t,
                                 human_v=human_v, hp=hp, lp=lp,
                                 stereo_inst=stereo_inst)
        return name

    def note(self, track, abs_beat, dur_beats, midi, vel=0.7, dt=0.0):
        self.tracks[track]["events"].append([abs_beat, dur_beats, midi, vel, dt])

    def notes(self, track, bar, items, octave_shift=0, vel_scale=1.0):
        """items: list of (beat, dur, midi[, vel])"""
        for it in items:
            v = it[3] if len(it) > 3 else 0.75
            self.note(track, self.ab(bar, it[0]), it[1], it[2] + octave_shift, v * vel_scale)

    # ---- render
    def _timed_events(self, tr):
        ev = []
        for (b, d, m, v, dt) in tr["events"]:
            t0 = self.beat_time(b) + dt
            t1 = self.beat_time(b + d) + dt
            jt = float(np.clip(self.rng.normal(0, tr["human_t"]), -2.5 * tr["human_t"], 2.5 * tr["human_t"]))
            jv = float(np.clip(self.rng.normal(1, tr["human_v"]), 0.75, 1.25))
            ev.append((t0 + jt, max(0.02, t1 - t0), m, float(np.clip(v * jv, 0.05, 1.1))))
        ev.sort()
        return ev

    def render_track(self, tr):
        N = self.N
        P = nsamp(12.0)
        rng = np.random.default_rng(zlib.crc32(tr["inst"].__name__.encode()))
        ev = self._timed_events(tr)
        L = N + 2 * P
        if tr["line"]:
            notes = []
            for off in (-N, 0, N):
                for (t0, d, m, v) in ev:
                    s = t0 + off / SR
                    if -P / SR < s < (N + P) / SR:
                        notes.append((s + P / SR, s + d + P / SR, m, v))
            y = tr["inst"](notes, L, rng)
            out = y[P:P + N]
        else:
            buf = np.zeros((L, 2)) if tr["stereo_inst"] else np.zeros(L)
            for (t0, d, m, v) in ev:
                note_rng = np.random.default_rng(int(abs(t0 * 1000)) + int(m * 7))
                y = tr["inst"](float(mtof(m)), d, v, note_rng)
                for off in (-N, 0, N):
                    s = int(round(t0 * SR)) + off + P
                    if s >= L or s + len(y) <= 0:
                        continue
                    s0, s1 = max(0, s), min(L, s + len(y))
                    buf[s0:s1] += y[s0 - s:s1 - s]
            out = buf[P:P + N]
        if tr["hp"]:
            out = wrap_apply(lambda z: highpass(z, tr["hp"]), out)
        if tr["lp"]:
            out = wrap_apply(lambda z: lowpass(z, tr["lp"]), out)
        return out

    def mix(self, ir, verbose=True, master_lp=11000, presence_db=4.0, presence_hz=2500):
        N = self.N
        dry = np.zeros((N, 2))
        send = np.zeros((N, 2))
        stems = {}
        for name, tr in self.tracks.items():
            if not tr["events"]:
                continue
            y = self.render_track(tr)
            st = pan(y, tr["pan"]) * tr["gain"]
            stems[name] = st
            dry += st
            send += st * tr["send"]
        wet = reverb(send, ir, loop=True)
        out = dry + wet
        out = wrap_apply(lambda z: highpass(z, 32, 2), out)
        out = wrap_apply(lambda z: lowpass(z, master_lp, 2), out)
        if presence_db:
            out = wrap_apply(lambda z: biquad(z, "highshelf", presence_hz, 0.6, presence_db), out)
        if verbose:
            tot = lufs(out)
            print(f"  [{self.name}] stems (LUFS, rel to mix {tot:.1f}):")
            for k, s in stems.items():
                print(f"     {k:10s} {lufs(s) - tot:+6.1f} LU   peak {peak_db(s):6.1f}")
            print(f"     {'reverb':10s} {lufs(wet) - tot:+6.1f} LU")
        return out
