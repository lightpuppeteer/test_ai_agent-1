"""Seamless stereo ambience loops. Every layer is built circularly: noise is
shaped in the frequency domain over the full loop length, envelopes are
periodic, and discrete events wrap around the loop end."""
import numpy as np

from dsp import (SR, nsamp, secs, pink_noise, brown_noise, smooth_random,
                 fft_filter_circular, add_wrap, make_ir, reverb, lufs, limiter,
                 undb, lowpass, bandpass, highpass)

TWO_PI = 2 * np.pi


def band(lo=None, hi=None, order=2):
    """Smooth magnitude response for circular FFT filtering."""
    def g(f):
        f = np.maximum(f, 1e-3)
        r = np.ones_like(f)
        if hi:
            r /= np.sqrt(1 + (f / hi) ** (2 * order))
        if lo:
            r /= np.sqrt(1 + (lo / f) ** (2 * order))
        return r
    return g


def circ_noise(N, rng, lo=None, hi=None, color="pink", order=2):
    base = {"pink": pink_noise, "brown": brown_noise}.get(color)
    x = base(N, rng) if base else rng.standard_normal(N)
    y = fft_filter_circular(x, band(lo, hi, order))
    return y / (np.std(y) + 1e-12)


def periodic_env(N, centers, fn):
    """Sum of fn(dt) over centers, with circular distance."""
    t = secs(N)
    T = N / SR
    e = np.zeros(N)
    for c in centers:
        dt = (t - c + T / 2) % T - T / 2
        e += fn(dt)
    return e


def circ_reverb(x, rt60=1.0, seed=7, predelay=0.015):
    ir = make_ir(rt60=rt60, predelay=predelay, seed=seed, hf_damp=0.5)
    out = np.zeros_like(x)
    for ch in range(2):
        out[:, ch] = reverb(x[:, ch], ir, loop=True)[:, ch]
    return out


def finish_amb(y, target_lufs=-27.0, ceiling=-10.5):
    for _ in range(3):
        y = y * undb(target_lufs - lufs(y))
        y = limiter(y, ceiling, loop=True)
    return y


def circ_grains(N, rng, rate_env, gdur, lo, hi):
    pad = nsamp(gdur) + 10
    out = np.zeros(N + pad)
    p = rate_env / SR
    hits = np.nonzero(rng.random(N) < p)[0]
    g = nsamp(gdur)
    win = np.hanning(g)
    for h in hits:
        out[h:h + g] += rng.standard_normal(g) * win * rng.uniform(0.2, 1.0)
    out[:pad] += out[N:]
    out = out[:N]
    return fft_filter_circular(out, band(lo, hi))


# ------------------------------------------------------------------ waves
def waves():
    rng = np.random.default_rng(40)
    periods = [7.5, 8.5, 8.0, 8.0]
    T = sum(periods)
    N = nsamp(T)
    starts = np.cumsum([0] + periods[:-1])
    out = np.zeros((N, 2))
    t = secs(N)
    rumble_env = np.zeros(N)
    crash_env = np.zeros(N)
    foam_env = np.zeros(N)
    pans = []
    for s, p, k in zip(starts, periods, range(4)):
        brk = s + 0.42 * p + rng.uniform(-0.2, 0.2)
        size = rng.uniform(0.8, 1.0)
        rumble_env += size * periodic_env(N, [brk], lambda d: np.where(d < 0, np.exp(-(d / 1.6) ** 2), np.exp(-d / 1.2)))
        crash_env += size * periodic_env(N, [brk], lambda d: np.where(d < 0, np.exp(-(d / 0.25) ** 2), np.exp(-d / 0.9)))
        foam_env += size * periodic_env(N, [brk + 0.3], lambda d: np.where(d < 0, np.exp(-(d / 0.4) ** 2),
                                                                     np.exp(-d / 2.4) * (1 - 0.3 * np.exp(-d / 0.3))))
        pans.append((brk, rng.uniform(-0.5, 0.5)))
    # slow stereo drift of each wave
    pan_ctl = periodic_env(N, [b for b, _ in pans], lambda d: np.zeros_like(d))
    for b, pv in pans:
        pan_ctl += pv * periodic_env(N, [b], lambda d: np.exp(-(d / 3.0) ** 2))
    pan_ctl = np.clip(pan_ctl, -0.6, 0.6)
    gl = np.cos((pan_ctl + 1) * np.pi / 4) * np.sqrt(2)
    gr = np.sin((pan_ctl + 1) * np.pi / 4) * np.sqrt(2)
    for ch, g in enumerate((gl, gr)):
        rumble = circ_noise(N, rng, 30, 380, "brown")
        crash = circ_noise(N, rng, 150, 4500, "pink")
        foam = circ_noise(N, rng, 1800, 11000, "white")
        fizz = circ_grains(N, rng, 4000 * np.clip(foam_env, 0, 1.2) + 50, 0.002, 2500, 10000)
        bed = circ_noise(N, rng, 60, 900, "pink")
        y = (rumble * (0.25 + 0.7 * rumble_env) * 0.5 + crash * crash_env * 0.4 +
             foam * foam_env * 0.12 + fizz * foam_env * 0.25 + bed * 0.08)
        out[:, ch] = y * (0.6 + 0.4 * g)
    out = 0.85 * out + 0.15 * out[:, ::-1]
    return finish_amb(out, -27.0)


# ------------------------------------------------------------------ birds
def _syll(f_contour, amp_env, harm=0.12):
    ph = TWO_PI * np.cumsum(f_contour) / SR
    return (np.sin(ph) + harm * np.sin(2 * ph)) * amp_env


def bird_phrase(kind, rng):
    if kind == "tweet":
        L = rng.uniform(0.06, 0.1)
        n = nsamp(L)
        u = np.linspace(0, 1, n)
        f0 = rng.uniform(2800, 3600)
        f = f0 + rng.uniform(900, 1600) * np.sin(np.pi * u) ** 1.5
        y = _syll(f, np.sin(np.pi * u) ** 1.2)
        reps = int(rng.integers(1, 4))
        gap = nsamp(rng.uniform(0.08, 0.14))
        out = np.zeros(reps * (n + gap))
        for r in range(reps):
            out[r * (n + gap):r * (n + gap) + n] += y * (1 - 0.15 * r)
        return out
    if kind == "trill":
        k = int(rng.integers(6, 12))
        nl, gl = nsamp(0.028), nsamp(0.016)
        f0 = rng.uniform(4000, 5200)
        out = np.zeros(k * (nl + gl))
        u = np.linspace(0, 1, nl)
        for r in range(k):
            f = f0 * (1 - 0.02 * r) + 700 * (1 - u)
            out[r * (nl + gl):r * (nl + gl) + nl] += _syll(f, np.sin(np.pi * u) ** 2) * (0.7 + 0.3 * np.sin(np.pi * r / k))
        return out
    if kind == "feebee":
        a, b = rng.uniform(3700, 4100), None
        b = a * rng.uniform(0.8, 0.86)
        na, nb, ng = nsamp(0.2), nsamp(0.26), nsamp(0.06)
        ua, ub = np.linspace(0, 1, na), np.linspace(0, 1, nb)
        ya = _syll(a * (1 - 0.01 * ua) + 30 * np.sin(TWO_PI * 30 * ua * 0.2), np.sin(np.pi * ua) ** 0.6, 0.05)
        yb = _syll(b * (1 + 0.02 * ub), np.sin(np.pi * ub) ** 0.6, 0.05)
        return np.concatenate([ya, np.zeros(ng), yb])
    if kind == "chirp":
        out = []
        for r in range(int(rng.integers(2, 4))):
            n = nsamp(rng.uniform(0.035, 0.05))
            u = np.linspace(0, 1, n)
            f = rng.uniform(4800, 5600) - 2200 * u
            out += [_syll(f, np.sin(np.pi * u) ** 1.5), np.zeros(nsamp(rng.uniform(0.06, 0.1)))]
        return np.concatenate(out)
    raise ValueError(kind)


def gull_call(rng):
    out = []
    for r in range(int(rng.integers(2, 4))):
        L = rng.uniform(0.32, 0.45)
        n = nsamp(L)
        u = np.linspace(0, 1, n)
        f0 = 900 + 380 * np.sin(np.pi * np.clip(u * 1.4, 0, 1)) - 220 * u
        ph = TWO_PI * np.cumsum(f0) / SR
        y = np.zeros(n)
        for k in range(1, 9):
            y += np.sin(k * ph) / k ** 0.7
        y = bandpass(y, 1200, 3200, 2) + 0.3 * y
        y *= np.sin(np.pi * u) ** 0.8 * (1 + 0.2 * rng.standard_normal(n) * 0.2)
        out += [y, np.zeros(nsamp(rng.uniform(0.12, 0.25)))]
    y = np.concatenate(out)
    return lowpass(y, 3000, 2)


def birds_day():
    rng = np.random.default_rng(41)
    T = 30.0
    N = nsamp(T)
    wind = np.stack([circ_noise(N, rng, 80, 700, "pink") for _ in range(2)], axis=1)
    gust = 0.6 + 0.4 * smooth_random(N, 0.12, rng)
    leaves = np.stack([circ_noise(N, rng, 2500, 8000, "white") for _ in range(2)], axis=1)
    leaf_env = np.clip(smooth_random(N, 0.3, rng), 0, 1) ** 2
    bed = wind * gust[:, None] * 0.05 + leaves * leaf_env[:, None] * 0.006
    ev = np.zeros((N, 2))
    t = 0.3
    kinds = ["tweet", "trill", "feebee", "chirp", "tweet", "chirp"]
    # a few "birds" each with own position and preferred song
    birds = [dict(pan=rng.uniform(-0.8, 0.8), dist=rng.uniform(0.35, 1.0), kind=kinds[i]) for i in range(6)]
    while t < T - 0.2:
        b = birds[int(rng.integers(len(birds)))]
        y = bird_phrase(b["kind"], rng) * b["dist"] * rng.uniform(0.7, 1.0)
        if b["dist"] < 0.6:
            y = lowpass(y, 5000, 2)
        a = (b["pan"] + 1) * np.pi / 4
        add_wrap(ev[:, 0], y * np.cos(a), nsamp(t))
        add_wrap(ev[:, 1], y * np.sin(a), nsamp(t))
        # little call-and-response sometimes
        if rng.random() < 0.35:
            t += len(y) / SR + rng.uniform(0.15, 0.4)
            y2 = y * 0.8
            add_wrap(ev[:, 0], y2 * np.cos(a), nsamp(t))
            add_wrap(ev[:, 1], y2 * np.sin(a), nsamp(t))
        t += len(y) / SR + rng.uniform(1.2, 3.6)
    for tg in (7.3, 21.8):
        y = gull_call(rng) * 0.22
        p = rng.uniform(-0.6, 0.6)
        a = (p + 1) * np.pi / 4
        add_wrap(ev[:, 0], y * np.cos(a), nsamp(tg))
        add_wrap(ev[:, 1], y * np.sin(a), nsamp(tg))
    wet = circ_reverb(ev, rt60=0.9, seed=8)
    ev = ev * 0.18 + wet * 0.05
    return finish_amb(bed + ev, -28.0)


# ------------------------------------------------------------------ crickets
def night_crickets():
    rng = np.random.default_rng(42)
    T = 30.0
    N = nsamp(T)
    t = secs(N)
    out = np.zeros((N, 2))
    specs = [
        # carrier, chirps per loop, pulses, pulse rate, gain, pan
        (4400, 48, 3, 30, 1.0, -0.5),
        (4750, 40, 4, 32, 0.7, 0.55),
        (4100, 36, 3, 27, 0.55, 0.1),
        (5000, 54, 2, 35, 0.4, -0.15),
        (4550, 44, 3, 29, 0.35, 0.8),
    ]
    for fc, nch, pulses, prate, g, p in specs:
        period = T / nch
        y = np.zeros(N)
        pl = nsamp(0.014)
        u = np.linspace(0, 1, pl)
        pulse_env = np.sin(np.pi * u) ** 2
        phase0 = rng.uniform(0, period)
        # sings in bouts (periodic gating so the loop stays seamless)
        bout = np.clip(0.5 + 0.9 * smooth_random(N, 0.08, rng), 0, 1)
        for c in range(nch):
            st = phase0 + c * period + rng.normal(0, 0.006)
            for k in range(pulses):
                ts = st + k / prate
                i = nsamp(ts) % N
                amp = (1 - 0.12 * k) * bout[i]
                seg = np.sin(TWO_PI * fc * (u * pl / SR)) * pulse_env * amp
                add_wrap(y, seg, i)
        # carrier phase continuity isn't required: short Hann-windowed pulses
        a = (p + 1) * np.pi / 4
        out[:, 0] += y * np.cos(a) * g
        out[:, 1] += y * np.sin(a) * g
    # distant tree-cricket trill bed
    tr = np.zeros(N)
    trill_rate = 50.0
    k = int(T * trill_rate)
    pl = nsamp(0.01)
    u = np.linspace(0, 1, pl)
    pulse = np.sin(TWO_PI * 2900 * u * pl / SR) * np.sin(np.pi * u) ** 2
    for i in range(k):
        add_wrap(tr, pulse * (0.6 + 0.4 * np.sin(TWO_PI * i / k * 3) ** 2), nsamp(i / trill_rate))
    out += np.stack([tr * 0.12, tr * 0.09], axis=1)
    wind = np.stack([circ_noise(N, rng, 60, 500, "pink") for _ in range(2)], axis=1)
    gust = 0.6 + 0.4 * smooth_random(N, 0.1, rng)
    wet = circ_reverb(out, rt60=1.2, seed=9)
    y = out * 0.6 + wet * 0.35 + wind * gust[:, None] * 0.04
    return finish_amb(y, -29.0)


# ------------------------------------------------------------------ wind
def wind():
    rng = np.random.default_rng(43)
    T = 30.0
    N = nsamp(T)
    gust = 0.55 + 0.45 * smooth_random(N, 0.1, rng)
    gust2 = 0.5 + 0.5 * smooth_random(N, 0.25, rng)
    out = np.zeros((N, 2))
    for ch in range(2):
        dark = circ_noise(N, rng, 40, 450, "pink")
        mid = circ_noise(N, rng, 300, 1600, "pink")
        hi = circ_noise(N, rng, 1500, 6000, "pink")
        gg = np.roll(gust, nsamp(0.4) * ch)
        out[:, ch] = dark * (0.4 + 0.6 * gg) * 0.6 + mid * gg ** 2 * 0.25 * gust2 + hi * gg ** 3 * 0.04
    leaves = circ_grains(N, rng, 600 * np.clip(gust - 0.6, 0, 1) * 2 + 5, 0.003, 2500, 8000)
    out += np.stack([leaves * 0.03, np.roll(leaves, nsamp(1.3)) * 0.03], axis=1)
    return finish_amb(out, -28.0)


# ------------------------------------------------------------------ fountain
def fountain():
    rng = np.random.default_rng(44)
    T = 20.0
    N = nsamp(T)
    out = np.zeros((N, 2))
    for ch in range(2):
        bed = circ_noise(N, rng, 300, 5000, "pink")
        flick = 0.65 + 0.35 * smooth_random(N, 25.0, rng)
        low = circ_noise(N, rng, 90, 500, "pink")
        bub = np.zeros(N)
        count = int(T * 140)
        for _ in range(count):
            f0 = float(np.exp(rng.uniform(np.log(500), np.log(3500))))
            tau = float(np.clip(0.02 * (1000 / f0) ** 0.8, 0.004, 0.035))
            n = nsamp(tau * 5)
            tt = secs(n)
            f = f0 * (1 + 0.5 * tt / (tau * 3))
            y = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-tt / tau) * np.minimum(1, tt / 0.0008)
            add_wrap(bub, y * rng.uniform(0.05, 1.0) ** 2, int(rng.integers(N)))
        splash = circ_grains(N, rng, np.full(N, 2500.0), 0.002, 2000, 9000)
        out[:, ch] = bed * flick * 0.25 + low * 0.18 + bub * 0.12 + splash * 0.1
    wet = circ_reverb(out, rt60=0.7, seed=10)
    return finish_amb(out + wet * 0.25, -27.0)
