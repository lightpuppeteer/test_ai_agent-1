"""'Animalese' syllable blips: formant-synthesized vowels (+ consonant onsets)
around a 300 Hz fundamental, meant to be pitch-shifted per speaker."""
import numpy as np

from dsp import SR, nsamp, secs, resonator, bandpass, lowpass, highpass, rms_db, undb

TWO_PI = 2 * np.pi
F0 = 300.0

VOWELS = {  # (formant Hz, bandwidth Hz, gain)
    "a": [(900, 110, 1.0), (1500, 120, 0.6), (2900, 200, 0.22)],
    "e": [(560, 80, 1.0), (2100, 130, 0.45), (2900, 200, 0.25)],
    "i": [(360, 60, 1.0), (2700, 160, 0.32), (3400, 250, 0.22)],
    "o": [(560, 80, 1.0), (950, 100, 0.7), (2700, 200, 0.14)],
    "u": [(380, 60, 1.0), (900, 100, 0.35), (2400, 200, 0.1)],
}


def source(n, f0=F0, rise=0.03, fall=-0.06, rng=None):
    """Band-limited glottal-ish source with a cute little pitch inflection."""
    t = secs(n)
    u = t / (n / SR)
    f = f0 * (1 + rise * np.sin(np.pi * np.clip(u * 2, 0, 1)) + fall * np.clip(u * 1.2 - 0.2, 0, 1))
    if rng is not None:
        f *= 1 + 0.004 * rng.standard_normal(n).cumsum() / np.sqrt(n)
    ph = TWO_PI * np.cumsum(f) / SR
    y = np.zeros(n)
    for k in range(1, int(7000 / f0)):
        y += np.sin(k * ph) / k ** 1.15
    return y


def formant(x, vowel):
    y = np.zeros_like(x)
    for fc, bw, g in VOWELS[vowel]:
        y += resonator(x, fc, fc / bw) * g
    return y


def env(n, att=0.008, rel=0.03):
    t = secs(n)
    T = n / SR
    a = np.clip(t / att, 0, 1)
    a = 0.5 - 0.5 * np.cos(np.pi * a)
    r = np.clip((T - t) / rel, 0, 1)
    r = 0.5 - 0.5 * np.cos(np.pi * r)
    return a * r


def blip_vowel(v, length=0.072):
    rng = np.random.default_rng(ord(v))
    n = nsamp(length)
    y = formant(source(n, rng=rng), v) * env(n)
    return y


def blip_consonant(c, length=0.075):
    rng = np.random.default_rng(ord(c) + 100)
    n = nsamp(length)
    t = secs(n)
    if c == "k":
        on = nsamp(0.012)
        burst = bandpass(rng.standard_normal(n), 1800, 3600, 2) * np.exp(-t / 0.006) * np.minimum(1, t / 0.0008)
        v = np.zeros(n)
        vn = n - on
        v[on:] = formant(source(vn, rng=rng), "a") * env(vn, 0.006, 0.03)
        y = burst * 0.6 + v
    elif c == "m":
        src = source(n, rise=0.02, rng=rng)
        nasal = resonator(src, 260, 3.5) + resonator(src, 1000, 8) * 0.15
        vow = formant(src, "a")
        xf = np.clip((t - 0.018) / 0.02, 0, 1)
        y = (nasal * 0.9 * (1 - xf) + vow * xf) * env(n, 0.01, 0.03)
    elif c == "s":
        on = nsamp(0.024)
        hiss = highpass(rng.standard_normal(n), 4500, 4) * np.clip(t / 0.006, 0, 1) * np.clip((0.028 - t) / 0.008, 0, 1)
        v = np.zeros(n)
        vn = n - on
        v[on:] = formant(source(vn, rng=rng), "i") * env(vn, 0.006, 0.03)
        y = hiss * 0.12 + v
    elif c == "t":
        on = nsamp(0.007)
        burst = bandpass(rng.standard_normal(n), 3000, 7000, 2) * np.exp(-t / 0.003) * np.minimum(1, t / 0.0005)
        v = np.zeros(n)
        vn = n - on
        v[on:] = formant(source(vn, rng=rng), "e") * env(vn, 0.005, 0.03)
        y = burst * 0.5 + v
    else:
        raise ValueError(c)
    return y


def all_blips():
    out = {}
    for v in "aeiou":
        out[v] = blip_vowel(v)
    for c in "kmst":
        out[c] = blip_consonant(c)
    # consistent loudness: equal RMS over the voiced part, then common peak cap
    for k in out:
        y = lowpass(highpass(out[k], 120, 2), 9000, 2)
        out[k] = y * undb(-20 - rms_db(y[nsamp(0.01):nsamp(0.06)]))
    pk = max(np.max(np.abs(y)) for y in out.values())
    scale = undb(-6.5) / pk
    return {k: y * scale for k, y in out.items()}
