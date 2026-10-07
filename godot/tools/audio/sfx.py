"""Jingles, UI/interaction SFX, footsteps and car sounds."""
import numpy as np

import instruments as I
from dsp import (SR, nsamp, secs, mtof, lowpass, highpass, bandpass, biquad,
                 resonator, pan, reverb, make_ir, fade_edges, lufs, limiter,
                 normalize_peak, undb, add_at, to_stereo, onepole_smooth)

TWO_PI = 2 * np.pi


# ================================================================== helpers
class OneShot:
    """Small non-looping arranger for jingles (stereo)."""

    def __init__(self, length, seed=0):
        self.n = nsamp(length)
        self.dry = np.zeros((self.n, 2))
        self.send = np.zeros((self.n, 2))
        self.rng = np.random.default_rng(seed)

    def hit(self, inst, t, dur, midi, vel=0.7, gain=1.0, pan_=0.0, send=0.25):
        rng = np.random.default_rng(int(t * 1000) + int(midi * 13))
        y = inst(float(mtof(midi)), dur, vel, rng)
        st = pan(y, pan_) * gain
        s = nsamp(t)
        add_at(self.dry, st, s)
        add_at(self.send, st * send, s)

    def line(self, inst, notes, gain=1.0, pan_=0.0, send=0.25):
        y = inst(notes, self.n, self.rng)
        st = pan(y, pan_) * gain
        self.dry += st
        self.send += st * send

    def render(self, rt60=1.0, wet=1.0, fade_out=0.25):
        ir = make_ir(rt60=rt60, predelay=0.012, seed=31, hf_damp=0.5)
        w = reverb(self.send, ir)[: self.n] * wet
        y = self.dry + w
        y = highpass(y, 60, 2)
        y = biquad(y, "highshelf", 2500, 0.6, 3.0)
        return fade_edges(y, 0.0005, fade_out)


def finish_jingle(y, target_lufs=-15.0, ceiling=-3.5):
    L = lufs(y)
    y = y * undb(target_lufs - L)
    y = limiter(y, ceiling)
    return y


def finish_mono(y, peak=-3.0, fin=0.0005, fout=0.01):
    y = fade_edges(y, fin, fout)
    return normalize_peak(y, peak)


def tone(freq, length, harmonics=(1.0,), decay=0.1, attack=0.002, sweep=None):
    """Additive tone with optional exponential pitch sweep (f0 -> f1)."""
    n = nsamp(length)
    t = secs(n)
    if sweep:
        f0, f1, ts = sweep
        f = f1 + (f0 - f1) * np.exp(-t / ts)
    else:
        f = np.full(n, freq)
    ph = TWO_PI * np.cumsum(f) / SR
    y = np.zeros(n)
    for k, a in enumerate(harmonics, 1):
        y += a * np.sin(k * ph) * ((k * f) < 16000)
    env = np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t / decay)
    return y * env


def grains(n, rng, rate, gdur=0.004, env=None, lo=1000, hi=6000):
    """Granular crackle: sparse noise grains (cloth, grass, sand)."""
    out = np.zeros(n)
    rate_t = np.full(n, rate) if env is None else rate * env
    p = rate_t / SR
    hits = np.nonzero(rng.random(n) < p)[0]
    g = nsamp(gdur)
    for h in hits:
        k = min(g, n - h)
        if k <= 2:
            continue
        gr = rng.standard_normal(k) * np.hanning(k) * rng.uniform(0.2, 1.0)
        out[h:h + k] += gr
    return bandpass(out, lo, hi, 2)


def creak(n, rng, start, length, f0=90, f1=160, modes=(520, 1150, 2300), amp=1.0):
    """Stick-slip friction creak: jittery impulse train into wooden modes."""
    out = np.zeros(n)
    t = start
    end = start + length
    while t < end:
        u = (t - start) / length
        f = f0 + (f1 - f0) * u + rng.normal(0, 8)
        a = np.sin(np.pi * u) ** 0.7 * rng.uniform(0.5, 1.0)
        i = nsamp(t)
        if i < n:
            out[i] += a
        t += 1.0 / max(30, f)
    y = np.zeros(n)
    for m, q in zip(modes, (14, 18, 10)):
        y += resonator(out, m * rng.uniform(0.95, 1.05), q)
    return y * amp


def thump(n, f0=110, f1=50, decay=0.06, start=0.0):
    k = n - nsamp(start)
    t = secs(k)
    f = f1 + (f0 - f1) * np.exp(-t / 0.02)
    y = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / decay) * np.minimum(1, t / 0.002)
    out = np.zeros(n)
    out[nsamp(start):] = y
    return out


def noise_burst(n, rng, start, attack, decay, lo, hi, order=2):
    t = secs(n) - start
    e = np.where(t < 0, 0, np.minimum(1, np.maximum(t, 0) / max(attack, 1e-4)) * np.exp(-np.maximum(t, 0) / decay))
    return bandpass(rng.standard_normal(n), lo, hi, order) * e


# ================================================================== jingles
def jingle_quest_start():
    o = OneShot(1.6, seed=1)
    for i, m in enumerate([72, 77, 81, 84]):
        t = i * 0.075
        o.hit(I.marimba, t, 0.2, m, 0.8, gain=0.5, pan_=0.15)
        o.hit(I.glock, t, 0.2, m + 12, 0.55, gain=0.16, pan_=-0.2, send=0.35)
    for m in [65, 69, 72, 76, 79]:
        o.hit(I.epiano, 0.3, 0.9, m, 0.55, gain=0.22, pan_=-0.1)
    o.hit(I.pizz_bass, 0.3, 0.6, 41, 0.8, gain=0.5)
    o.hit(I.glock, 0.30, 0.8, 93, 0.7, gain=0.2, pan_=0.3, send=0.4)
    o.hit(I.glock, 0.40, 0.8, 96, 0.6, gain=0.16, pan_=-0.3, send=0.4)
    o.hit(I.kalimba, 0.52, 0.5, 89, 0.5, gain=0.15, pan_=0.4, send=0.4)
    o.hit(I.kalimba, 0.60, 0.5, 91, 0.45, gain=0.13, pan_=-0.4, send=0.4)
    return finish_jingle(o.render(rt60=1.0, fade_out=0.3))


def jingle_quest_step():
    o = OneShot(0.85, seed=2)
    for t, m, v in [(0.0, 81, 0.7), (0.1, 84, 0.75), (0.2, 89, 0.7)]:
        o.hit(I.kalimba, t, 0.3, m, v, gain=0.5, pan_=0.1)
        o.hit(I.glock, t, 0.3, m + 12, v * 0.6, gain=0.12, pan_=-0.15, send=0.35)
    return finish_jingle(o.render(rt60=0.8, fade_out=0.2), target_lufs=-16.5)


def jingle_quest_complete():
    o = OneShot(2.9, seed=3)
    melody = [(0.00, 0.10, 72), (0.12, 0.10, 77), (0.24, 0.16, 81),
              (0.42, 0.10, 79), (0.54, 0.10, 81), (0.66, 1.15, 84)]
    o.line(I.ocarina, [(a, a + d, m, 0.85) for a, d, m in melody], gain=0.5, send=0.25)
    for a, d, m in melody:
        o.hit(I.marimba, a, d, m, 0.65, gain=0.32, pan_=0.25)
    chords = [(0.0, [62, 65, 69, 72], 46), (0.42, [64, 67, 70, 74], 48),
              (0.66, [65, 69, 72, 76, 79], 41)]
    for t, ch, b in chords:
        for i, m in enumerate(ch):
            o.hit(I.epiano, t + 0.008 * i, 0.38 if t < 0.6 else 1.6, m, 0.55, gain=0.22, pan_=-0.25)
        o.hit(I.pizz_bass, t, 0.35 if t < 0.6 else 1.2, b, 0.8, gain=0.5)
    o.hit(I.kick, 0.66, 0.2, 36, 0.6, gain=0.35, send=0.05)
    o.hit(I.brush_swish, 0.5, 0.25, 60, 0.6, gain=0.15, pan_=0.2)
    for i, m in enumerate([89, 93, 96, 101]):
        o.hit(I.glock, 0.9 + i * 0.09, 0.4, m, 0.55, gain=0.15, pan_=-0.3 + 0.2 * i, send=0.45)
    return finish_jingle(o.render(rt60=1.2, fade_out=0.5))


def jingle_memory():
    o = OneShot(2.6, seed=4)
    arp = [65, 69, 72, 76, 79, 81]
    for i, m in enumerate(arp):
        o.hit(I.musicbox, i * 0.13, 0.4, m, 0.6 + 0.04 * i, gain=0.5, pan_=-0.3 + 0.12 * i, send=0.45)
    o.hit(I.musicbox, 0.84, 1.2, 84, 0.75, gain=0.5, pan_=0.1, send=0.5)
    o.hit(I.celesta, 0.84, 1.2, 72, 0.5, gain=0.25, pan_=-0.1, send=0.5)
    o.hit(I.musicbox, 1.15, 1.0, 88, 0.45, gain=0.35, pan_=0.3, send=0.5)
    for m in [53, 60, 64, 69]:
        o.hit(lambda f, d, v, r: I.pad(f, d, v, r, attack=0.35, rel=1.0, bright=1400),
              0.0, 1.3, m, 0.5, gain=0.18, send=0.4)
    return finish_jingle(o.render(rt60=1.6, wet=1.1, fade_out=0.6), target_lufs=-17.0)


def jingle_item():
    o = OneShot(1.1, seed=5)
    for i, m in enumerate([84, 89, 93]):
        o.hit(I.glock, i * 0.07, 0.3, m, 0.7, gain=0.3, pan_=-0.2 + 0.2 * i, send=0.35)
        o.hit(I.celesta, i * 0.07, 0.3, m - 12, 0.6, gain=0.3, pan_=0.1, send=0.3)
    rng = np.random.default_rng(55)
    for k in range(7):
        t = 0.2 + k * 0.05 + rng.uniform(0, 0.03)
        o.hit(I.glock, t, 0.1, int(rng.choice([96, 98, 100, 101, 103])), 0.3 - 0.03 * k,
              gain=0.12, pan_=float(rng.uniform(-0.6, 0.6)), send=0.5)
    return finish_jingle(o.render(rt60=0.9, fade_out=0.25), target_lufs=-16.0)


# ================================================================== UI
def ui_confirm():
    n = nsamp(0.22)
    y = np.zeros(n)
    a = tone(0, 0.2, (1, 0.25, 0.08), decay=0.06, sweep=(1290, 1318, 0.01))
    b = tone(0, 0.2, (1, 0.25, 0.08), decay=0.08, sweep=(1720, 1760, 0.01))
    add_at(y, a, 0)
    add_at(y, b * 0.9, nsamp(0.055))
    return finish_mono(lowpass(y, 8000), -3)


def ui_cancel():
    n = nsamp(0.24)
    y = np.zeros(n)
    a = tone(0, 0.2, (1, 0.15), decay=0.06, sweep=(900, 880, 0.01))
    b = tone(0, 0.2, (1, 0.15), decay=0.09, sweep=(680, 587, 0.03))
    add_at(y, a * 0.9, 0)
    add_at(y, b, nsamp(0.07))
    return finish_mono(lowpass(y, 4000), -4)


def svf_bandpass(x, fc, q=1.2):
    """Time-varying state-variable band-pass (Chamberlin), fc per sample."""
    y = np.zeros(len(x))
    low = band = 0.0
    damp = 1.0 / q
    f = 2 * np.sin(np.pi * np.minimum(fc, SR / 6) / SR)
    for i in range(len(x)):
        high = x[i] - low - damp * band
        band += f[i] * high
        low += f[i] * band
        y[i] = band
    return y


def _swish(n, rng, f_from, f_to, dur):
    t = secs(n)
    fc = f_from * (f_to / f_from) ** np.clip(t / dur, 0, 1)
    sw = svf_bandpass(rng.standard_normal(n), fc, 1.5)
    return sw * np.sin(np.pi * np.clip(t / (dur * 1.15), 0, 1)) ** 2


def ui_open():
    rng = np.random.default_rng(10)
    n = nsamp(0.32)
    sw = _swish(n, rng, 500, 3000, 0.14) * 0.12
    pl = np.zeros(n)
    add_at(pl, I.kalimba(1046.5, 0.2, 0.7, rng)[: n], nsamp(0.07))
    add_at(pl, I.kalimba(1568.0, 0.2, 0.5, rng)[: n] * 0.6, nsamp(0.12))
    return finish_mono(sw + pl * 0.6, -3, fout=0.04)


def ui_close():
    rng = np.random.default_rng(11)
    n = nsamp(0.3)
    sw = _swish(n, rng, 2800, 450, 0.14) * 0.12
    pl = np.zeros(n)
    add_at(pl, I.kalimba(1174.7, 0.2, 0.6, rng)[: n] * 0.6, 0)
    add_at(pl, I.kalimba(784.0, 0.2, 0.7, rng)[: n], nsamp(0.06))
    return finish_mono(sw + pl * 0.6, -4, fout=0.04)


def ui_prompt():
    y = tone(0, 0.13, (1, 0.12), decay=0.035, attack=0.003, sweep=(420, 1150, 0.018))
    return finish_mono(lowpass(y, 6000), -4)


def ui_toast():
    rng = np.random.default_rng(12)
    n = nsamp(0.7)
    y = np.zeros(n)
    add_at(y, I.glock(1046.5, 0.3, 0.6, rng), 0)
    add_at(y, I.glock(1568.0, 0.3, 0.55, rng) * 0.8, nsamp(0.09))
    add_at(y, I.kalimba(523.25, 0.3, 0.5, rng) * 0.5, 0)
    y = y[:n]
    return finish_mono(lowpass(y, 9000), -4, fout=0.15)


def ui_text_advance():
    y = tone(0, 0.06, (1, 0.1), decay=0.014, attack=0.0015, sweep=(1900, 1350, 0.01))
    return finish_mono(y, -6, fout=0.01)


def photo_shutter():
    rng = np.random.default_rng(13)
    n = nsamp(0.36)
    y = np.zeros(n)
    imp = np.zeros(n)
    imp[nsamp(0.002)] = 1.0
    imp[nsamp(0.004)] = -0.6
    y += resonator(imp, 3200, 9) * 1.2 + resonator(imp, 5200, 7) * 0.8
    y += noise_burst(n, rng, 0.0, 0.0005, 0.006, 2000, 9000) * 0.5
    imp2 = np.zeros(n)
    imp2[nsamp(0.075)] = 1.0
    imp2[nsamp(0.078)] = 0.5
    y += resonator(imp2, 1800, 8) * 1.4 + resonator(imp2, 950, 10) * 1.0 + resonator(imp2, 4100, 9) * 0.6
    y += noise_burst(n, rng, 0.075, 0.0005, 0.01, 1200, 7000) * 0.4
    # tiny film-advance whir
    t = secs(n)
    wh = bandpass(rng.standard_normal(n), 1500, 4000, 2) * (1 + 0.8 * np.sin(TWO_PI * 90 * t))
    wh *= np.clip((t - 0.12) / 0.03, 0, 1) * np.exp(-np.maximum(t - 0.12, 0) / 0.06) * 0.05
    y += wh
    return finish_mono(lowpass(y, 11000), -3, fout=0.05)


def pickup_pop():
    rng = np.random.default_rng(14)
    n = nsamp(0.42)
    y = np.zeros(n)
    add_at(y, tone(0, 0.12, (1, 0.2), decay=0.04, attack=0.002, sweep=(320, 980, 0.02)), 0)
    add_at(y, I.glock(1760.0, 0.2, 0.6, rng)[: n] * 0.5, nsamp(0.045))
    add_at(y, I.glock(2637.0, 0.2, 0.5, rng)[: n] * 0.3, nsamp(0.09))
    return finish_mono(y, -3, fout=0.12)


def sit_down():
    rng = np.random.default_rng(15)
    n = nsamp(0.65)
    t = secs(n)
    rust_env = np.clip(t / 0.05, 0, 1) * np.exp(-np.maximum(t - 0.05, 0) / 0.12)
    y = grains(n, rng, 900, 0.006, rust_env, 1200, 6000) * 0.35
    y += bandpass(rng.standard_normal(n), 600, 3500, 2) * rust_env * 0.05
    y += creak(n, rng, 0.12, 0.26, f0=85, f1=140) * 0.12
    y += thump(n, 120, 60, 0.05, start=0.1) * 0.5
    y += lowpass(noise_burst(n, rng, 0.1, 0.002, 0.03, 80, 600), 500) * 0.4
    return finish_mono(lowpass(y, 9000), -4, fout=0.1)


def stand_up():
    rng = np.random.default_rng(16)
    n = nsamp(0.5)
    t = secs(n)
    rust_env = np.clip(t / 0.08, 0, 1) * np.exp(-np.maximum(t - 0.08, 0) / 0.1)
    y = grains(n, rng, 800, 0.006, rust_env, 1200, 6000) * 0.35
    y += bandpass(rng.standard_normal(n), 700, 4000, 2) * rust_env * 0.05
    y += creak(n, rng, 0.02, 0.18, f0=150, f1=95) * 0.09
    return finish_mono(lowpass(y, 9000), -5, fout=0.1)


def lie_down():
    rng = np.random.default_rng(17)
    n = nsamp(0.85)
    t = secs(n)
    env = np.clip(t / 0.12, 0, 1) * np.exp(-np.maximum(t - 0.18, 0) / 0.18)
    env2 = np.exp(-((t - 0.45) / 0.08) ** 2) * 0.7
    y = grains(n, rng, 1200, 0.008, env + env2, 500, 3500) * 0.3
    y += bandpass(rng.standard_normal(n), 300, 2000, 2) * (env + env2) * 0.06
    y += lowpass(noise_burst(n, rng, 0.2, 0.03, 0.08, 40, 400), 300) * 0.5
    y += thump(n, 90, 45, 0.08, start=0.22) * 0.3
    return finish_mono(lowpass(y, 7000), -5, fout=0.15)


def jump():
    y = tone(0, 0.2, (1, 0.22, 0.06), decay=0.07, attack=0.006, sweep=(260, 780, 0.05))
    return finish_mono(lowpass(y, 6000), -4, fout=0.03)


def land():
    rng = np.random.default_rng(18)
    n = nsamp(0.2)
    y = thump(n, 120, 50, 0.045) * 0.8
    y += lowpass(noise_burst(n, rng, 0.0, 0.002, 0.03, 60, 800), 600) * 0.6
    t = secs(n)
    y += grains(n, rng, 1500, 0.004, np.exp(-t / 0.04), 1500, 6000) * 0.12
    return finish_mono(y, -4, fout=0.05)


def bubble(f0, length, rng, rise=0.6, decay=None):
    n = nsamp(length)
    t = secs(n)
    decay = decay or float(np.clip(0.02 * (1000 / f0) ** 0.8, 0.004, 0.04))
    f = f0 * (1 + rise * t / max(decay * 3, 1e-3))
    y = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / decay) * np.minimum(1, t / 0.0008)
    return y


def splash_small():
    rng = np.random.default_rng(19)
    n = nsamp(0.48)
    t = secs(n)
    y = noise_burst(n, rng, 0.0, 0.004, 0.06, 600, 5000) * 0.5
    y += noise_burst(n, rng, 0.02, 0.01, 0.12, 2500, 9000) * 0.15
    y += lowpass(noise_burst(n, rng, 0.0, 0.003, 0.04, 80, 500), 400) * 0.4
    for k in range(9):
        ts = rng.uniform(0.01, 0.3)
        b = bubble(rng.uniform(700, 2600), 0.08, rng)
        add_at(y, b * rng.uniform(0.08, 0.25) * np.exp(-ts / 0.2), nsamp(ts))
    return finish_mono(lowpass(y, 10000), -4, fout=0.1)


def sparkle_loop():
    """3 s loopable shimmer (circular placement)."""
    rng = np.random.default_rng(20)
    N = nsamp(3.0)
    y = np.zeros(N)
    from dsp import add_wrap
    for k in range(34):
        ts = rng.uniform(0, 3.0)
        f = float(rng.choice([2093, 2349, 2637, 3136, 3520, 4186, 4699, 5274]))
        n = nsamp(0.35)
        tt = secs(n)
        p = np.sin(TWO_PI * f * tt) + 0.2 * np.sin(TWO_PI * f * 2.76 * tt) * np.exp(-tt / 0.03)
        p *= np.exp(-tt / rng.uniform(0.06, 0.15)) * np.minimum(1, tt / 0.002)
        add_wrap(y, p * rng.uniform(0.25, 1.0), nsamp(ts))
    from dsp import fft_filter_circular, pink_noise, smooth_random
    hiss = fft_filter_circular(pink_noise(N, rng), lambda f: ((f > 5000) & (f < 12000)).astype(float))
    am = 0.5 + 0.5 * smooth_random(N, 3.0, rng)
    y += hiss * am * 0.03
    return normalize_peak(y, -9)


# ================================================================== footsteps
def step(surface, idx):
    rng = np.random.default_rng(1000 + idx * 17 + {"grass": 0, "sand": 100, "stone": 200, "wood": 300}[surface])
    if surface == "grass":
        n = nsamp(0.17)
        t = secs(n)
        env = np.clip(t / 0.008, 0, 1) * np.exp(-t / rng.uniform(0.035, 0.05))
        y = grains(n, rng, 5000, 0.0025, env, 2500, 8000) * 0.5
        y += bandpass(rng.standard_normal(n), 900, 3000, 2) * env * 0.12
        y += thump(n, 90, 55, 0.025) * 0.18
        y = lowpass(y, 9000)
    elif surface == "sand":
        n = nsamp(0.22)
        t = secs(n)
        env = np.clip(t / 0.018, 0, 1) * np.exp(-np.maximum(t - 0.02, 0) / rng.uniform(0.045, 0.06))
        y = grains(n, rng, 7000, 0.002, env, 900, 4500) * 0.45
        y += bandpass(rng.standard_normal(n), 400, 2000, 2) * env * 0.15
        y += lowpass(noise_burst(n, rng, 0.0, 0.006, 0.03, 50, 300), 250) * 0.5
        y = lowpass(y, 6000)
    elif surface == "stone":
        n = nsamp(0.14)
        t = secs(n)
        imp = np.zeros(n)
        imp[0] = 1.0
        imp[nsamp(0.0015)] = -0.5
        y = np.zeros(n)
        for f, q, a in [(rng.uniform(1700, 2200), 9, 0.5), (rng.uniform(2800, 3600), 10, 0.35),
                        (rng.uniform(900, 1200), 6, 0.4)]:
            y += resonator(imp, f, q) * a
        y += noise_burst(n, rng, 0.0, 0.0005, 0.004, 1500, 8000) * 0.25
        y += noise_burst(n, rng, 0.01, 0.01, 0.025, 3000, 9000) * 0.04  # scuff
        y += thump(n, 140, 70, 0.02) * 0.35
        y = lowpass(y, 7000)
    elif surface == "wood":
        n = nsamp(0.24)
        t = secs(n)
        imp = np.zeros(n)
        imp[0] = 1.0
        y = np.zeros(n)
        for f, q, a in [(rng.uniform(150, 190), 7, 1.0), (rng.uniform(380, 450), 9, 0.6),
                        (rng.uniform(850, 1000), 8, 0.3), (rng.uniform(1900, 2300), 6, 0.12)]:
            y += resonator(imp, f, q) * a
        y += noise_burst(n, rng, 0.0, 0.0005, 0.005, 1000, 6000) * 0.12
        y += thump(n, 110, 60, 0.03) * 0.3
        y = lowpass(y, 6000)
    else:
        raise ValueError(surface)
    y = y * rng.uniform(0.9, 1.0)
    return finish_mono(y, -8.0 + rng.uniform(-1.0, 0.0), fout=0.02)


# ================================================================== car
def car_engine_loop():
    """2.0 s idle loop: 45 Hz firing (90 cycles), two alternating cylinders,
    exhaust/valve resonances. Perfectly periodic -> seamless, pitch-shiftable."""
    rng = np.random.default_rng(30)
    N = nsamp(2.0)  # 88200 = 90 * 980
    P = 980
    from dsp import add_wrap, fft_filter_circular
    pulses = np.zeros(N)
    noise_imp = np.zeros(N)
    for c in range(90):
        a = (1.0 if c % 2 == 0 else 0.82) * rng.uniform(0.9, 1.08)
        pos = c * P + int(rng.normal(0, 6))
        pulses[pos % N] += a
        noise_imp[pos % N] += a * rng.uniform(0.6, 1.0)
    L = nsamp(0.06)
    t = secs(L)
    shape = (np.sin(TWO_PI * 95 * t) * np.exp(-t / 0.012) * 1.0 +
             np.sin(TWO_PI * 230 * t) * np.exp(-t / 0.008) * 0.6 +
             np.sin(TWO_PI * 520 * t) * np.exp(-t / 0.005) * 0.35 +
             np.sin(TWO_PI * 1250 * t) * np.exp(-t / 0.003) * 0.15)
    y = np.zeros(N)
    nz = np.zeros(N)
    burst = rng.standard_normal(L) * np.exp(-t / 0.004)
    for i in np.nonzero(pulses)[0]:
        add_wrap(y, shape * pulses[i], i)
        add_wrap(nz, burst * noise_imp[i], i)
    nz = fft_filter_circular(nz, lambda f: np.exp(-((np.log2(np.maximum(f, 1) / 1800)) ** 2) / 1.5))
    y = y + nz * 0.25
    # cute "putt" exhaust resonance + gentle lowpass, all circular
    def eq(f):
        f = np.maximum(f, 1)
        g = 1 / np.sqrt(1 + (f / 3200) ** 4)
        g *= 1 + 1.2 * np.exp(-((np.log2(f / 300)) ** 2) / 0.3)
        g *= 1 / np.sqrt(1 + (30 / f) ** 4)
        return g
    y = fft_filter_circular(y, eq)
    tt = secs(N)
    y += 0.03 * np.sin(TWO_PI * 315 * tt) + 0.015 * np.sin(TWO_PI * 630 * tt)
    return normalize_peak(y, -3.0)


def car_horn():
    n = nsamp(0.62)
    y = np.zeros(n)
    for start, length in [(0.0, 0.14), (0.22, 0.24)]:
        m = nsamp(length)
        t = secs(m)
        seg = np.zeros(m)
        for f in (523.0, 659.0):
            fr = f * (1 - 0.03 * np.exp(-t / 0.02))
            ph = TWO_PI * np.cumsum(fr) / SR
            for k in range(1, 12, 1):
                if k * f > 9000:
                    break
                seg += (1.0 / k if k % 2 else 0.35 / k) * np.sin(k * ph)
        env = np.minimum(1, t / 0.008) * np.clip((length - t) / 0.025, 0, 1)
        add_at(y, seg * env, nsamp(start))
    y = bandpass(y, 350, 3500, 2)
    y = biquad(y, "peak", 1300, 2.0, 5)
    return finish_mono(y, -3, fout=0.03)


def car_door():
    rng = np.random.default_rng(31)
    n = nsamp(0.5)
    y = thump(n, 95, 55, 0.08) * 0.9
    y += lowpass(noise_burst(n, rng, 0.0, 0.002, 0.04, 40, 500), 400) * 0.8
    imp = np.zeros(n)
    imp[nsamp(0.006)] = 1
    imp[nsamp(0.028)] = 0.7
    y += resonator(imp, 2600, 10) * 0.5 + resonator(imp, 4200, 12) * 0.3
    y += noise_burst(n, rng, 0.006, 0.0005, 0.005, 2000, 8000) * 0.15
    y += noise_burst(n, rng, 0.028, 0.0005, 0.005, 2000, 8000) * 0.1
    imp2 = np.zeros(n)
    imp2[nsamp(0.04)] = 1
    y += resonator(imp2, 1100, 25) * 0.15  # little panel rattle
    return finish_mono(lowpass(y, 9000), -3, fout=0.1)
