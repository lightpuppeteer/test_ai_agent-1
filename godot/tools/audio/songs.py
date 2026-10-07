"""The four music loops. Melodies are hand-written (beat, dur, midi[, vel]).

Keys/tempos:  day F major 100 BPM swung | golden Bb major 84 BPM light swing |
              night F major 70 BPM 3/4  | title F major 72 BPM (day theme).
All loops are rendered circularly (tails wrap to the start).
"""
import numpy as np

import instruments as I
from dsp import make_ir, master
from sequencer import Song, parse_chord, place, EP_SHAPE, OPEN_SHAPE

# ------------------------------------------------------------------ helpers


def voicing(chord, center, prev=None, shape_tab=EP_SHAPE, spread=7):
    root, q, _ = parse_chord(chord)
    shape = shape_tab[q]
    rots = []
    s = list(shape)
    for _ in range(len(shape)):
        rots.append(list(s))
        s = s[1:] + [s[0] + 12]
    best, best_cost = None, 1e9
    for r in rots:
        for o in range(2, 8):
            cand = [12 * o + root + i for i in r]
            mean = np.mean(cand)
            if abs(mean - center) > spread:
                continue
            cost = 0.6 * abs(mean - center)
            if prev:
                cost += sum(abs(a - b) for a, b in zip(sorted(cand), sorted(prev))) * 0.5
            if cost < best_cost:
                best, best_cost = cand, cost
    return best


def comp(song, track, bars, patterns, center=62, vel=1.0, seed=3, roll=0.0):
    rng = np.random.default_rng(seed)
    prev = None
    for bar in bars:
        pat = patterns[rng.integers(len(patterns))] if len(patterns) > 1 else patterns[0]
        for (beat, dur, v) in pat:
            ab = song.ab(bar, beat)
            ch = song.chord_at(ab)
            vo = voicing(ch, center, prev)
            prev = vo
            for i, m in enumerate(vo):
                song.note(track, ab, dur, m, v * vel * (0.92 + 0.08 * (i == len(vo) - 1)),
                          dt=i * roll)


def sustain_chords(song, track, bars, center, vel, shape_tab=EP_SHAPE, roll=0.0,
                   bass_lo=None, legato=1.0):
    prev = None
    for (b, e, ch) in song.chord_spans():
        bar = int(b // song.bpb)
        if bar not in bars:
            continue
        vo = voicing(ch, center, prev, shape_tab)
        prev = vo
        for i, m in enumerate(vo):
            song.note(track, b, (e - b) * legato, m, vel, dt=i * roll)


def bassline(song, track, bars, vel=0.8, style="walk", seed=5, lo=36):
    rng = np.random.default_rng(seed)
    spans = song.chord_spans()
    for idx, (b, e, ch) in enumerate(spans):
        bar = int(b // song.bpb)
        if bar not in bars:
            continue
        _, _, bass_pc = parse_chord(ch)
        root_pc, q, _ = parse_chord(ch)
        r = place(bass_pc, lo, lo + 12)
        f_pc = (root_pc + 7) % 12  # chord's own fifth (correct on slash chords)
        fifth = min((m for m in range(lo - 6, lo + 19) if m % 12 == f_pc and m != r),
                    key=lambda m: (abs(m - (r + 7)), m))
        nxt = spans[(idx + 1) % len(spans)][2]
        nr = place(parse_chord(nxt)[2], lo, lo + 12)
        length = e - b
        if style == "walk":
            if length >= 4:
                song.note(track, b, 1.3, r, vel)
                song.note(track, b + 2, 0.9, fifth, vel * 0.85)
                if rng.random() < 0.55:
                    appr = nr - 1 if rng.random() < 0.6 else nr + 2
                    song.note(track, b + 3, 0.6, appr, vel * 0.7)
                else:
                    song.note(track, b + 3.5, 0.4, r + 12 if r + 12 < lo + 20 else r, vel * 0.55)
            else:
                song.note(track, b, 1.2, r, vel)
                if length > 1.5:
                    song.note(track, b + 1.5, 0.4, fifth, vel * 0.6)
        elif style == "half":
            song.note(track, b, min(length, 2) * 0.9, r, vel)
            if length >= 4:
                song.note(track, b + 2, 1.7, fifth, vel * 0.8)
        elif style == "waltz":
            song.note(track, b, length * 0.95, r, vel)


def arps(song, track, bars, pattern, lo, vel=0.6, shape_tab=OPEN_SHAPE, step=0.5,
         accent=1.15):
    for bar in bars:
        for i, idx in enumerate(pattern):
            if idx is None:
                continue
            beat = i * step
            ab = song.ab(bar, beat)
            ch = song.chord_at(ab)
            root, q, _ = parse_chord(ch)
            r = place(root, lo, lo + 12)
            m = r + shape_tab[q][idx % 4] + 12 * (idx // 4)
            v = vel * (accent if beat == int(beat) else 1.0)
            song.note(track, ab, step * 1.8, m, v)


def mel(song, track, bar, items, shift=0, vel=1.0):
    song.notes(track, bar, items, octave_shift=shift, vel_scale=vel)


# ------------------------------------------------------------------ DAY
DAY_A = [
    [(0, 1, 76), (1, .5, 72), (1.5, .5, 69), (2, 1.5, 72), (3.5, .5, 69)],          # Fmaj7
    [(0, .5, 72), (.5, .5, 74), (1, 1, 77), (2, 2, 76)],                           # Dm7
    [(0, 1, 74), (1, .5, 70), (1.5, .5, 67), (2, 1.5, 70), (3.5, .5, 67)],         # Gm7
    [(0, .5, 70), (.5, .5, 72), (1, 1, 76), (2, 2, 74)],                           # C9
    [(0, 1, 72), (1, .5, 76), (1.5, .5, 79), (2, 1.5, 81), (3.5, .5, 79)],         # Am7
    [(0, 1, 78), (1, .5, 76), (1.5, .5, 74), (2, 1.5, 72), (3.5, .5, 74)],         # D7
]
DAY_A1_END = [
    [(0, 1.5, 70), (1.5, .5, 74), (2, .5, 72), (2.5, .5, 70), (3, 1, 69)],         # Gm7
    [(0, 2.5, 67), (3, .5, 72, .65), (3.5, .5, 74, .7)],                           # C9 + pickup
]
DAY_A2_END = [
    [(0, .5, 74), (.5, .5, 72), (1, 1, 70), (2, .5, 67), (2.5, .5, 70), (3, 1, 76)],  # Gm7 C7
    [(0, 2.5, 77), (3, .5, 70, .65), (3.5, .5, 72, .7)],                           # F6 -> B
]
DAY_A3_END = [
    DAY_A2_END[0],
    [(0, 1, 77), (1, .5, 72, .6), (1.5, .5, 69, .6), (2, 1.5, 77, .7)],             # F6 tag
]
DAY_B = [
    [(0, 1.5, 74), (1.5, .5, 77), (2, 2, 81)],                                     # Bbmaj7
    [(0, 1.5, 79), (1.5, .5, 77), (2, 2, 73)],                                     # Bbm6
    [(0, 1.5, 72), (1.5, .5, 76), (2, 2, 79)],                                     # Am7
    [(0, 1.5, 78), (1.5, .5, 76), (2, 1, 74), (3, 1, 72)],                         # D7
    [(0, 1.5, 70), (1.5, .5, 74), (2, 2, 77)],                                     # Gm7
    [(0, 1, 73), (1, .5, 76), (1.5, .5, 81), (2, 2, 79)],                          # A7
    [(0, 1, 77), (1, .5, 76), (1.5, .5, 74), (2, 1, 71), (3, .5, 74), (3.5, .5, 79)],  # Dm7 G7
    [(0, 1, 77), (1, 1, 74), (2, 1, 70), (3, .5, 72, .65), (3.5, .5, 74, .7)],     # Gm7 C7
]
DAY_B_GLOCK = [
    [(2.5, .5, 93), (3, .5, 89), (3.5, .5, 86)],
    [(2.5, .5, 89), (3, .5, 85), (3.5, .5, 82)],
    [(2.5, .5, 88), (3, .5, 84), (3.5, .5, 81)],
    [(2, .5, 90), (2.5, 1.5, 86)],
    [(2.5, .5, 91), (3, .5, 86), (3.5, .5, 82)],
    [(2.5, .5, 85), (3, .5, 88), (3.5, .5, 91)],
    [(0, 2, 89, .6)],
    [(2, 1.5, 88, .6)],
]
DAY_CHORDS_INTRO = ["Fmaj7", "Dm7", "Gm7", "C9"]
DAY_CHORDS_A1 = ["Fmaj7", "Dm7", "Gm7", "C9", "Am7", "D7", "Gm7", "C9"]
DAY_CHORDS_A2 = ["Fmaj7", "Dm7", "Gm7", "C9", "Am7", "D7", [(0, "Gm7"), (2, "C7")], "F6"]
DAY_CHORDS_B = ["Bbmaj7", "Bbm6", "Am7", "D7", "Gm7", "A7", [(0, "Dm7"), (2, "G7")],
                [(0, "Gm7"), (2, "C7")]]
DAY_CHORDS_A3 = DAY_CHORDS_A2[:7] + [[(0, "F6"), (2, "C7")]]

EP_PATTERNS = [
    [(0, .5, .5), (1.5, .45, .68), (3, .4, .45), (3.5, .5, .65)],
    [(.5, .4, .62), (1.5, .4, .55), (2.5, .4, .62), (3.5, .4, .55)],
    [(0, 1.3, .5), (1.5, .4, .62), (2.5, 1.2, .55)],
    [(.5, .45, .66), (2, .45, .5), (3.5, .45, .66)],
]


def song_day():
    s = Song("day", bpm=100, beats_per_bar=4, bars=36, swing=0.62, seed=101)
    s.set_chords(DAY_CHORDS_INTRO, 0)
    s.set_chords(DAY_CHORDS_A1, 4)
    s.set_chords(DAY_CHORDS_A2, 12)
    s.set_chords(DAY_CHORDS_B, 20)
    s.set_chords(DAY_CHORDS_A3, 28)
    lead = s.track("lead", I.ocarina, gain=0.48, pan_=0.05, send=0.22, line=True, human_t=0.008)
    ep = s.track("ep", I.epiano, gain=0.30, pan_=-0.28, send=0.2, human_t=0.006)
    mar = s.track("marimba", I.marimba, gain=0.30, pan_=0.32, send=0.18)
    kal = s.track("kalimba", I.kalimba, gain=0.22, pan_=0.4, send=0.25)
    gl = s.track("glock", I.glock, gain=0.15, pan_=-0.4, send=0.38)
    bs = s.track("bass", I.pizz_bass, gain=0.42, pan_=0.0, send=0.05, human_t=0.005)
    kk = s.track("kick", I.kick, gain=0.30, pan_=0.0, send=0.04, human_t=0.003)
    br = s.track("brush", I.brush, gain=0.18, pan_=-0.12, send=0.12, human_t=0.004)
    sh = s.track("shaker", I.shaker, gain=0.32, pan_=0.45, send=0.12, human_t=0.004)

    all_bars = range(36)
    comp(s, ep, all_bars, EP_PATTERNS, center=61, vel=0.85, seed=11)
    bassline(s, bs, all_bars, vel=0.8, style="walk", seed=7, lo=36)
    marimba_pat = [0, 2, None, 3, 1, 2, None, 3]
    marimba_pat2 = [0, None, 2, 3, None, 2, 1, None]
    for bar in list(range(0, 20)) + list(range(28, 36)):
        arps(s, mar, [bar], marimba_pat if bar % 2 == 0 else marimba_pat2, lo=53, vel=0.55)
    arps(s, kal, range(20, 28), [0, None, None, 2, None, 3, None, None], lo=60, vel=0.5)

    # melody
    mel(s, lead, 3, [(3, .5, 72, .65), (3.5, .5, 74, .7)])
    for sec, ends in ((4, DAY_A1_END), (12, DAY_A2_END), (28, DAY_A3_END)):
        for i, bar_items in enumerate(DAY_A + ends):
            mel(s, lead, sec + i, bar_items, vel=0.8)
    for i, bar_items in enumerate(DAY_B):
        mel(s, lead, 20 + i, bar_items, vel=0.78)
        mel(s, gl, 20 + i, DAY_B_GLOCK[i], vel=0.75)
    for i, bar_items in enumerate(DAY_A[:4]):  # glock doubles last A for a lift
        mel(s, gl, 28 + i, bar_items, shift=12, vel=0.45)

    # drums
    for bar in all_bars:
        b = s.ab(bar)
        for e in range(8):
            s.note(sh, b + e * 0.5, 0.2, 60, 0.55 if e % 2 else 0.33)
        if bar >= 4:
            s.note(kk, b, 0.5, 36, 0.62)
            if not (20 <= bar < 28):
                s.note(kk, b + 2, 0.5, 36, 0.5)
            if bar % 4 == 3:
                s.note(kk, b + 3.5, 0.5, 36, 0.35)
        if bar >= 2:
            s.note(br, b + 1, 0.3, 60, 0.6)
            s.note(br, b + 3, 0.3, 60, 0.65)
    ir = make_ir(rt60=1.7, predelay=0.022, seed=21, hf_damp=0.45)
    return s, s.mix(ir)


# ------------------------------------------------------------------ GOLDEN
GOLD_A = [
    [(0, 1.5, 77), (1.5, .5, 74), (2, 1, 72), (3, 1, 74)],                 # Bbmaj7
    [(0, 3, 69), (3, .5, 70), (3.5, .5, 72)],                              # Dm7
    [(0, 1.5, 74), (1.5, .5, 75), (2, 1, 79), (3, 1, 77)],                 # Ebmaj7
    [(0, 2, 78), (2, 1, 77), (3, 1, 75)],                                  # Ebm6
]
GOLD_A_END = [
    [(0, 1.5, 77), (1.5, .5, 74), (2, 1, 72), (3, 1, 69)],                 # Dm7
    [(0, 2, 74), (2, 1, 70), (3, 1, 67)],                                  # Gm7
    [(0, 1.5, 75), (1.5, .5, 74), (2, 2, 72)],                             # Cm7
    [(0, 2, 70), (2, 1, 69), (3, .5, 70, .6), (3.5, .5, 72, .65)],         # F7sus F7
]
GOLD_B = [
    [(0, 1.5, 79), (1.5, .5, 77), (2, 2, 74)],                             # Ebmaj7
    [(0, 1.5, 77), (1.5, .5, 75), (2, 2, 72)],                             # F/Eb
    [(0, 1.5, 75), (1.5, .5, 74), (2, 1, 72), (3, 1, 69)],                 # Am7b5
    [(0, 1.5, 72), (1.5, .5, 69), (2, 1.5, 66), (3.5, .5, 69)],            # D7b9
    [(0, 2, 74), (2, 1, 70), (3, 1, 74)],                                  # Gm7
    [(0, 1.5, 77), (1.5, .5, 75), (2, 2, 74)],                             # Gm7/F
    [(0, 1.5, 75), (1.5, .5, 74), (2, 1, 72), (3, 1, 67)],                 # Cm9
    [(0, 1, 70), (1, 1, 69), (2, 1, 72), (3, 1, 65, .65)],                 # F7sus F7
]
GOLD_A2_END = [
    [(0, 1.5, 77), (1.5, .5, 74), (2, 1, 71), (3, 1, 74)],                 # Dm7 G7
    [(0, 1.5, 75), (1.5, .5, 74), (2, 1, 72), (3, 1, 69)],                 # Cm7 F7
    [(0, 3.5, 70)],                                                        # Bb6
    [],                                                                    # Cm7 F7
]
GOLD_CH_INTRO = ["Bbmaj7", "Gm9", "Cm9", [(0, "F7sus"), (2, "F7")]]
GOLD_CH_A = ["Bbmaj7", "Dm7", "Ebmaj7", "Ebm6", "Dm7", "Gm7", "Cm7", [(0, "F7sus"), (2, "F7")]]
GOLD_CH_B = ["Ebmaj7", "F/Eb", "Am7b5", "D7b9", "Gm7", "Gm7/F", "Cm9", [(0, "F7sus"), (2, "F7")]]
GOLD_CH_A2 = ["Bbmaj7", "Dm7", "Ebmaj7", "Ebm6", [(0, "Dm7"), (2, "G7")],
              [(0, "Cm7"), (2, "F7")], "Bb6", [(0, "Cm7"), (2, "F7")]]


def song_golden():
    s = Song("golden", bpm=84, beats_per_bar=4, bars=28, swing=0.56, seed=202)
    s.set_chords(GOLD_CH_INTRO, 0)
    s.set_chords(GOLD_CH_A, 4)
    s.set_chords(GOLD_CH_B, 12)
    s.set_chords(GOLD_CH_A2, 20)
    lead = s.track("lead", I.clarinet, gain=0.5, pan_=0.08, send=0.28, line=True, human_t=0.01)
    ep = s.track("ep", I.epiano, gain=0.42, pan_=-0.3, send=0.25)
    pd = s.track("pad", I.soft_pad, gain=0.24, pan_=0.0, send=0.35, stereo_inst=True)
    gt = s.track("guitar", I.nylon, gain=0.2, pan_=0.35, send=0.22)
    bs = s.track("bass", I.pizz_bass, gain=0.50, pan_=0.0, send=0.06)
    sh = s.track("shaker", I.shaker, gain=0.22, pan_=-0.4, send=0.15)
    mb = s.track("musicbox", I.musicbox, gain=0.26, pan_=-0.45, send=0.4)
    bars = range(28)
    comp(s, ep, bars, [[(0, 1.8, .5), (2.5, 1.3, .45)], [(0, 3.5, .5)],
                       [(0, 1.5, .5), (1.5, .4, .45), (2.5, 1.4, .45)]],
         center=60, vel=0.8, seed=12, roll=0.012)
    sustain_chords(s, pd, set(bars), center=57, vel=0.55)
    pat_a = [0, 2, 1, 3, 2, 1, 3, 2]
    pat_b = [0, 1, 2, 3, 4 + 1, 3, 2, 1]
    arps(s, gt, range(0, 12), pat_a, lo=46, vel=0.5, accent=1.2)
    arps(s, gt, range(12, 20), pat_b, lo=46, vel=0.52, accent=1.2)
    arps(s, gt, range(20, 28), pat_a, lo=46, vel=0.5, accent=1.2)
    bassline(s, bs, bars, vel=0.7, style="half", lo=34)
    mel(s, lead, 3, [(3, 1, 65, .6)])
    for i, it in enumerate(GOLD_A + GOLD_A_END):
        mel(s, lead, 4 + i, it, vel=0.8)
    for i, it in enumerate(GOLD_B):
        mel(s, lead, 12 + i, it, vel=0.82)
    for i, it in enumerate(GOLD_A + GOLD_A2_END):
        mel(s, lead, 20 + i, it, vel=0.78)
    # music-box echoes in the gaps of the last A and the turnaround
    mel(s, mb, 21, [(3, .5, 81), (3.5, .5, 84)], vel=0.6)
    mel(s, mb, 26, [(1, 1, 86), (2, 1, 82), (3, 1, 77)], vel=0.55)
    mel(s, mb, 27, [(0, 1, 79), (1, .5, 77), (1.5, .5, 74), (2, 2, 72)], vel=0.5)
    for bar in range(12, 28):
        for e in range(8):
            s.note(sh, s.ab(bar) + e * 0.5, 0.2, 60, 0.5 if e % 2 else 0.3)
    ir = make_ir(rt60=2.1, predelay=0.028, seed=22, hf_damp=0.4)
    return s, s.mix(ir, master_lp=9500)


# ------------------------------------------------------------------ NIGHT (3/4)
NIGHT_A = [
    [(0, 1, 72), (1, 1, 77), (2, 1, 81)],      # Fmaj7
    [(0, 2, 79), (2, 1, 76)],                  # Am7
    [(0, 1, 74), (1, 1, 77), (2, 1, 81)],      # Bbmaj7
    [(0, 2, 79), (2, 1, 73)],                  # Bbm6
]
NIGHT_A1_END = [
    [(0, 1.5, 69), (1.5, .5, 72), (2, 1, 77)],  # Fmaj7
    [(0, 2, 76), (2, 1, 74)],                   # Dm7
    [(0, 1, 70), (1, 1, 74), (2, 1, 77)],       # Gm7
    [(0, 3, 79)],                               # C7sus
]
NIGHT_A2_END = [
    [(0, 1.5, 76), (1.5, .5, 74), (2, 1, 72)],  # Am7
    [(0, 2, 78), (2, 1, 76)],                   # D7
    [(0, 1, 74), (1, 1, 70), (2, 1, 76)],       # Gm7 C7
    [(0, 3, 77)],                               # Fmaj7
]
NIGHT_B = [
    [(0, 2, 81), (2, 1, 77)],                   # Dm7
    [(0, 2, 79), (2, 1, 76)],                   # Am7
    [(0, 2, 77), (2, 1, 74)],                   # Bbmaj7
    [(0, 2, 76), (2, 1, 72)],                   # Fmaj7
    [(0, 1, 74), (1, 1, 77), (2, 1, 81)],       # Gm7
    [(0, 2, 79), (2, 1, 76)],                   # Am7
    [(0, 2, 74), (2, 1, 72)],                   # Bbmaj7
    [(0, 3, 74)],                               # C9sus
]


def song_night():
    s = Song("night", bpm=70, beats_per_bar=3, bars=28, swing=0.5, seed=303)
    s.set_chords(["Fmaj9", "Bbmaj9", "Fmaj9", "Bbmaj9"], 0)
    s.set_chords(["Fmaj7", "Am7", "Bbmaj7", "Bbm6", "Fmaj7", "Dm7", "Gm7", "C7sus"], 4)
    s.set_chords(["Fmaj7", "Am7", "Bbmaj7", "Bbm6", "Am7", "D7", [(0, "Gm7"), (2, "C7")], "Fmaj7"], 12)
    s.set_chords(["Dm7", "Am7", "Bbmaj7", "Fmaj7", "Gm7", "Am7", "Bbmaj7", "C9sus"], 20)
    mb = s.track("musicbox", I.musicbox, gain=0.42, pan_=0.1, send=0.34, human_t=0.01)
    ce = s.track("celesta", I.celesta, gain=0.38, pan_=-0.2, send=0.34, human_t=0.01)
    pn = s.track("piano", I.piano, gain=0.42, pan_=-0.12, send=0.32, human_t=0.012)
    pl = s.track("piano_lo", I.piano, gain=0.40, pan_=-0.05, send=0.35, human_t=0.01)
    pd = s.track("pad", I.soft_pad, gain=0.22, pan_=0.0, send=0.38, stereo_inst=True)
    tw = s.track("twinkle", I.glock, gain=0.08, pan_=0.5, send=0.6)
    bars = set(range(28))
    sustain_chords(s, pd, bars, center=55, vel=0.55, shape_tab=OPEN_SHAPE)
    prev = None
    for (b, e, ch) in s.chord_spans():
        root, q, bass = parse_chord(ch)
        s.note(pl, b, (e - b), place(bass, 36, 48), 0.5)
        vo = voicing(ch, 62, prev)
        prev = vo
        for i, m in enumerate(vo):
            s.note(pn, b + (1 if e - b >= 3 else 0), max(1.0, e - b - 1) + 0.6, m, 0.32 + 0.03 * i, dt=0.03 * i)
    for i, it in enumerate(NIGHT_A + NIGHT_A1_END):
        mel(s, mb, 4 + i, it, vel=0.8)
    for i, it in enumerate(NIGHT_A + NIGHT_A2_END):
        mel(s, mb, 12 + i, it, vel=0.8)
        mel(s, ce, 12 + i, it, shift=-12, vel=0.45)
    for i, it in enumerate(NIGHT_B):
        mel(s, mb, 20 + i, it, vel=0.78)
        mel(s, ce, 20 + i, it, shift=-12, vel=0.55)
    # twinkles (starry pings), deterministic
    rng = np.random.default_rng(9)
    for bar in range(0, 28, 2):
        ch = s.chord_at(s.ab(bar))
        root, q, _ = parse_chord(ch)
        from sequencer import QUAL
        tones = [place((root + iv) % 12, 88, 100) for iv in QUAL[q]]
        beat = float(rng.choice([0.5, 1.5, 2.5, 1.0]))
        s.note(tw, s.ab(bar, beat), 0.5, int(rng.choice(tones)), float(rng.uniform(0.4, 0.7)))
    # intro: a gentle music-box arpeggio so the loop never feels empty
    for bar in range(4):
        ch = s.chord_at(s.ab(bar))
        root, q, _ = parse_chord(ch)
        r = place(root, 65, 77)
        sh = OPEN_SHAPE[q]
        mel(s, mb, bar, [(0, 1, r + sh[1] + 12, .4), (1, 1, r + sh[2] + 12, .45), (2, 1, r + sh[3] + 12, .4)])
    ir = make_ir(rt60=2.7, predelay=0.03, seed=23, hf_damp=0.38)
    return s, s.mix(ir, master_lp=9000)


# ------------------------------------------------------------------ TITLE
def song_title():
    s = Song("title", bpm=72, beats_per_bar=4, bars=16, swing=0.55, seed=404)
    s.set_chords(DAY_CHORDS_A1, 0)
    s.set_chords(DAY_CHORDS_A2, 8)
    mb = s.track("musicbox", I.musicbox, gain=0.45, pan_=0.08, send=0.42, human_t=0.009)
    ce = s.track("celesta", I.celesta, gain=0.38, pan_=-0.25, send=0.4, human_t=0.009)
    hp = s.track("harp", I.harp, gain=0.6, pan_=-0.3, send=0.38, human_t=0.008)
    pd = s.track("pad", I.soft_pad, gain=0.18, pan_=0.0, send=0.45, stereo_inst=True)
    bs = s.track("bass", I.harp, gain=0.5, pan_=0.0, send=0.25)
    for i, it in enumerate(DAY_A + DAY_A1_END):
        mel(s, mb, i, it, vel=0.8)
    a2_end = [DAY_A2_END[0], [(0, 2.5, 77), (3, .5, 72, .65), (3.5, .5, 74, .7)]]
    for i, it in enumerate(DAY_A + a2_end):
        mel(s, mb, 8 + i, it, vel=0.8)
        mel(s, ce, 8 + i, it, shift=-12, vel=0.5)
    bars = set(range(16))
    sustain_chords(s, pd, bars, center=57, vel=0.5, shape_tab=OPEN_SHAPE)
    arps(s, hp, range(16), [0, None, 1, 2, None, 3, 2, None], lo=48, vel=0.42)
    bassline(s, bs, bars, vel=0.6, style="half", lo=36)
    ir = make_ir(rt60=2.5, predelay=0.03, seed=24, hf_damp=0.38)
    return s, s.mix(ir, master_lp=9500)


SONGS = {
    "day": (song_day, -16.5),
    "golden": (song_golden, -17.0),
    "night": (song_night, -18.0),
    "title": (song_title, -17.5),
}


def render(name):
    fn, target = SONGS[name]
    song, mix = fn()
    out = master(mix, target_lufs=target, ceiling_db=-3.3, loop=True)
    return song, out
