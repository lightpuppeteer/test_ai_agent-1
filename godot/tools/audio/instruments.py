"""Synthesized instruments.

Note instruments:  fn(freq_hz, dur_s, vel[0..1], rng) -> mono (or stereo) array
Line instruments:  fn(notes, n, rng) -> mono array, where notes is a list of
                   (t_on_s, t_off_s, midi, vel) relative to the render window.
All oscillators are additive (band-limited) or low-index FM kept below Nyquist.
"""
import numpy as np
from scipy import signal

from dsp import (SR, NYQ, secs, nsamp, lowpass, highpass, bandpass, biquad,
                 onepole_smooth, release_gate, mtof)

TWO_PI = 2 * np.pi
LIMIT = 16000.0  # highest partial we ever synthesize


def _vamp(vel, curve=1.6):
    return float(np.clip(vel, 0, 1.2)) ** curve


def _attack(n, a):
    e = np.ones(n)
    k = min(n, max(1, nsamp(a)))
    e[:k] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, k))
    return e


def modal(freq, ratios, amps, taus, length, attack=0.0015, rng=None, phases=None):
    n = nsamp(length)
    t = secs(n)
    y = np.zeros(n)
    for i, (r, a, tau) in enumerate(zip(ratios, amps, taus)):
        f = freq * r
        if f >= LIMIT or a == 0:
            continue
        ph = 0.0 if phases is None else phases[i]
        y += a * np.exp(-t / tau) * np.sin(TWO_PI * f * t + ph)
    return y * _attack(n, attack)


def _click(n, amp, fc_lo, fc_hi, dur, rng):
    k = nsamp(dur)
    z = np.zeros(n)
    if k < 4:
        return z
    nz = rng.standard_normal(k) * np.exp(-np.linspace(0, 6, k))
    nz = bandpass(nz, fc_lo, fc_hi, 2)
    z[:k] = nz * amp
    return z


# ------------------------------------------------------------------ mallets
def marimba(freq, dur, vel, rng):
    v = _vamp(vel)
    tau1 = float(np.clip(0.55 * (330 / freq) ** 0.45, 0.18, 1.1))
    L = tau1 * 5.5
    y = modal(freq, [1, 3.99, 9.2], [1, 0.3 + 0.3 * vel, 0.08 * vel],
              [tau1, tau1 * 0.16, tau1 * 0.05], L, attack=0.0012)
    y += _click(len(y), 0.09 * vel, 1500, 6000, 0.006, rng)
    return lowpass(y, 9000) * v


def kalimba(freq, dur, vel, rng):
    v = _vamp(vel)
    tau1 = float(np.clip(1.1 * (330 / freq) ** 0.35, 0.4, 1.8))
    y = modal(freq, [1, 5.95, 11.6], [1, 0.18 + 0.12 * vel, 0.04],
              [tau1, 0.10, 0.04], tau1 * 5, attack=0.0015)
    y += _click(len(y), 0.04 * vel, 2000, 7000, 0.004, rng)
    return y * v


def glock(freq, dur, vel, rng):
    v = _vamp(vel)
    tau1 = float(np.clip(1.6 * (1000 / freq) ** 0.3, 0.6, 2.4))
    y = modal(freq, [1, 2.76, 5.40, 8.93], [1, 0.32, 0.10, 0.04],
              [tau1, tau1 * 0.25, tau1 * 0.12, tau1 * 0.06], tau1 * 4.5, attack=0.0008)
    y += _click(len(y), 0.03 * vel, 3000, 9000, 0.003, rng)
    return lowpass(y, 11000) * v


def celesta(freq, dur, vel, rng):
    v = _vamp(vel)
    tau1 = float(np.clip(1.5 * (523 / freq) ** 0.35, 0.6, 2.6))
    y = modal(freq, [1, 2.0, 3.0, 4.16, 1.0012], [1, 0.08, 0.10, 0.04, 0.25],
              [tau1, tau1 * 0.4, tau1 * 0.18, tau1 * 0.1, tau1 * 0.8], tau1 * 4.5,
              attack=0.002)
    gate = max(dur, 0.25) + 0.6
    y *= release_gate(len(y), gate, 0.35)
    return lowpass(y, 9000) * v


def musicbox(freq, dur, vel, rng):
    v = _vamp(vel)
    tau1 = float(np.clip(2.6 * (523 / freq) ** 0.5, 0.9, 3.5))
    ph = rng.uniform(0, 2 * np.pi, 5)
    y = modal(freq, [1, 1.0028, 6.267, 17.55, 3.0],
              [1, 0.22, 0.17, 0.03, 0.03],
              [tau1, tau1 * 0.7, tau1 * 0.12, 0.05, tau1 * 0.2], tau1 * 4.2,
              attack=0.0006, phases=ph)
    y += _click(len(y), 0.05 * vel, 3000, 10000, 0.0025, rng)
    return lowpass(y, 10000) * v


# ------------------------------------------------------------------ keys
def epiano(freq, dur, vel, rng):
    """FM Rhodes-ish: 1:1 FM pair with decaying index + short high 'tine'."""
    v = _vamp(vel, 1.4)
    tau = float(np.clip(2.4 * (261 / freq) ** 0.5, 0.9, 4.0))
    gate = dur
    rel = 0.18
    n = nsamp(gate + rel + 0.05)
    t = secs(n)
    amp = np.exp(-t / tau) * _attack(n, 0.002) * release_gate(n, gate, rel)
    I = (0.7 + 1.9 * vel) * np.exp(-t / 0.5) + 0.3 + 0.25 * vel
    ph = TWO_PI * freq * t
    det = TWO_PI * freq * 1.0009 * t
    body = np.sin(ph + I * np.sin(ph)) * 0.65 + np.sin(det + 0.6 * I * np.sin(det)) * 0.35
    r = 14.0
    while freq * r * 2 > LIMIT and r > 3:
        r -= 1
    ib = (0.5 + 1.2 * vel) * np.exp(-t / 0.012)
    tine = np.sin(ph + ib * np.sin(r * ph)) * np.exp(-t / 0.2) * 0.32 * vel
    y = amp * (body + tine)
    y = lowpass(y, 7500)
    return y * v


def piano(freq, dur, vel, rng):
    """Additive soft piano: inharmonic partials, two detuned strings,
    two-stage decay, velocity-dependent brightness."""
    v = _vamp(vel, 1.5)
    B = 0.00025 * (freq / 261) ** 0.5
    tau_slow = float(np.clip(7.0 * (261 / freq) ** 0.6, 1.5, 11))
    tau_fast = 0.5
    gate = dur
    rel = 0.35
    L = min(gate + rel + 0.05, tau_slow * 4)
    n = nsamp(L)
    t = secs(n)
    y = np.zeros(n)
    bright = 1.2 + 1.3 * (1 - vel)
    kmax = int(min(40, 6000 / freq))
    phases = rng.uniform(0, 2 * np.pi, (kmax + 1, 2))
    for k in range(1, kmax + 1):
        fk = k * freq * np.sqrt(1 + B * k * k)
        if fk > LIMIT:
            break
        ak = (1.0 / k ** bright) * abs(np.sin(np.pi * k * 0.13)) / np.sin(np.pi * 0.13)
        damp = 1 + (fk / 1800.0) ** 1.2
        env = 0.65 * np.exp(-t / (tau_fast / damp)) + 0.35 * np.exp(-t / (tau_slow / damp))
        for s, cents in enumerate((-0.6, 0.6)):
            fks = fk * 2 ** (cents / 1200)
            y += 0.5 * ak * env * np.sin(TWO_PI * fks * t + phases[k, s])
    y *= _attack(n, 0.003) * release_gate(n, gate, rel)
    y += _click(n, 0.02 * vel, 200, 2000, 0.008, rng)
    return lowpass(y, 5000) * v


# ------------------------------------------------------------------ plucks
def _pluck(freq, dur, vel, rng, pos, tilt, tau0, bright_hz, fmax, rel, B=0.0,
           noise_amp=0.03, attack=0.0015):
    n = nsamp(min(dur + rel + 0.05, tau0 * 5))
    t = secs(n)
    y = np.zeros(n)
    kmax = int(fmax / freq)
    for k in range(1, max(2, kmax + 1)):
        fk = k * freq * np.sqrt(1 + B * k * k)
        if fk > min(fmax, LIMIT):
            break
        ak = abs(np.sin(np.pi * k * pos)) / k ** tilt
        tk = tau0 / (1 + (fk / bright_hz) ** 1.4)
        y += ak * np.exp(-t / tk) * np.sin(TWO_PI * fk * t + rng.uniform(-0.3, 0.3))
    y *= _attack(n, attack) * release_gate(n, dur, rel)
    y += _click(n, noise_amp * vel, 800, 5000, 0.006, rng)
    return y / (np.sin(np.pi * pos) + 1e-9)


def nylon(freq, dur, vel, rng):
    v = _vamp(vel)
    tau0 = float(np.clip(1.8 * (196 / freq) ** 0.4, 0.8, 3.0))
    y = _pluck(freq, max(dur, 0.3), vel, rng, pos=0.16, tilt=1.0, tau0=tau0,
               bright_hz=1400 + 1600 * vel, fmax=7000, rel=0.25, B=0.00004)
    y = biquad(y, "peak", 220, 1.2, 2.5)
    return lowpass(y, 4500) * v * 0.6


def harp(freq, dur, vel, rng):
    v = _vamp(vel)
    tau0 = float(np.clip(2.6 * (262 / freq) ** 0.5, 1.0, 4.0))
    y = _pluck(freq, max(dur, 1.0), vel, rng, pos=0.5, tilt=1.6, tau0=tau0,
               bright_hz=2000, fmax=6000, rel=0.6, noise_amp=0.01)
    return lowpass(y, 5000) * v * 0.6


def pizz_bass(freq, dur, vel, rng):
    v = _vamp(vel, 1.3)
    tau0 = float(np.clip(1.1 * (55 / freq) ** 0.2, 0.5, 1.4))
    y = _pluck(freq, dur, vel, rng, pos=0.22, tilt=1.25, tau0=tau0,
               bright_hz=500 + 300 * vel, fmax=2500, rel=0.09, noise_amp=0.0,
               attack=0.004)
    n = len(y)
    th = np.zeros(n)
    k = min(n, nsamp(0.02))
    th[:k] = np.sin(TWO_PI * freq * secs(k)) * np.exp(-np.linspace(0, 4, k))
    y += 0.15 * th
    y += _click(n, 0.05 * vel, 300, 1200, 0.012, rng)
    y = biquad(y, "peak", 90, 0.9, 2.0)
    return lowpass(y, 2400) * v * 0.7


# ------------------------------------------------------------------ pad
def pad(freq, dur, vel, rng, attack=1.0, rel=1.6, bright=1800):
    """Warm detuned additive saw pad, stereo."""
    v = _vamp(vel, 1.2)
    n = nsamp(dur + rel + 0.05)
    t = secs(n)
    env = np.minimum(1.0, t / attack) ** 1.5 * release_gate(n, dur, rel)
    out = np.zeros((n, 2))
    kmax = int(min(14, 3500 / freq))
    vib = 0.0015 * np.sin(TWO_PI * 0.23 * t + rng.uniform(0, 6))
    for ch, dets in enumerate(((-8, 3), (-3, 8))):
        for c in dets:
            f = freq * 2 ** (c / 1200)
            ph0 = rng.uniform(0, 2 * np.pi, kmax + 1)
            phase = TWO_PI * np.cumsum(f * (1 + vib)) / SR
            for k in range(1, kmax + 1):
                out[:, ch] += np.sin(k * phase + ph0[k]) / k ** 1.4
    out *= env[:, None] * v * 0.25
    return lowpass(out, bright, 2)


def soft_pad(freq, dur, vel, rng):
    return pad(freq, dur, vel, rng, attack=1.6, rel=2.2, bright=1200)


# ------------------------------------------------------------------ drums
def kick(freq, dur, vel, rng):
    v = _vamp(vel)
    n = nsamp(0.35)
    t = secs(n)
    f = 48 + 70 * np.exp(-t / 0.03)
    ph = TWO_PI * np.cumsum(f) / SR
    y = np.sin(ph) * np.exp(-t / 0.13) * _attack(n, 0.001)
    y += _click(n, 0.08, 400, 2500, 0.004, rng)
    return lowpass(y, 1200) * v


def brush(freq, dur, vel, rng):
    v = _vamp(vel)
    n = nsamp(0.32)
    t = secs(n)
    z = rng.standard_normal(n)
    z = bandpass(z, 1800, 9000, 2)
    e = (1 - np.exp(-t / 0.006)) * np.exp(-t / 0.075)
    tap = bandpass(rng.standard_normal(n), 300, 2500, 2) * np.exp(-t / 0.012) * 0.5
    return (z * e + tap) * v


def brush_swish(freq, dur, vel, rng):
    v = _vamp(vel)
    n = nsamp(dur + 0.1)
    t = secs(n)
    z = bandpass(rng.standard_normal(n), 2500, 9000, 2)
    e = np.sin(np.pi * np.clip(t / (dur + 0.1), 0, 1)) ** 2
    return z * e * v * 0.5


def shaker(freq, dur, vel, rng):
    v = _vamp(vel)
    n = nsamp(0.11)
    t = secs(n)
    z = highpass(rng.standard_normal(n), 5000, 2)
    e = (1 - np.exp(-t / 0.008)) * np.exp(-t / 0.028)
    return lowpass(z * e, 12000) * v


def rim(freq, dur, vel, rng):
    v = _vamp(vel)
    n = nsamp(0.12)
    t = secs(n)
    y = np.sin(TWO_PI * 1700 * t) * np.exp(-t / 0.012) + 0.5 * np.sin(TWO_PI * 820 * t) * np.exp(-t / 0.02)
    return y * v * _attack(n, 0.0005)


# ------------------------------------------------------------------ lines
def _line_controls(notes, n, glide=0.03, att=0.035, rel=0.11, scoop_cents=-40):
    """Build per-sample pitch (midi), amplitude and note-age tracks for a
    monophonic line. Legato notes get a tongued dip instead of silence."""
    t = secs(n)
    pitch = np.zeros(n)
    amp = np.zeros(n)
    age = np.full(n, 10.0)
    notes = sorted(notes)
    if not notes:
        return pitch, amp, age
    base = notes[0][2]
    for i, (on, off, m, vel) in enumerate(notes):
        s = int(np.clip(nsamp(on), 0, n))
        e = int(np.clip(nsamp(notes[i + 1][0]), 0, n)) if i + 1 < len(notes) else n
        if i == 0:
            pitch[:s] = m
        pitch[s:max(s, e)] = m
        age[s:max(s, e)] = t[s:max(s, e)] - on
    pitch = onepole_smooth(pitch - base, glide) + base
    for i, (on, off, m, vel) in enumerate(notes):
        legato_prev = i > 0 and on - notes[i - 1][1] < 0.02
        s0 = int(np.clip(nsamp(on), 0, n))
        e0 = int(np.clip(nsamp(off + rel * 3), 0, n))
        if e0 <= s0:
            continue
        tt = t[s0:e0] - on
        a_t = att * (0.6 if legato_prev else 1.0)
        up = np.clip(tt / a_t, 0, 1)
        up = 0.5 - 0.5 * np.cos(np.pi * up)
        if legato_prev:
            up = 0.55 + 0.45 * up
        down = np.where(tt < (off - on), 1.0, np.exp(-(tt - (off - on)) / (rel / 3)))
        shape = (0.9 + 0.1 * np.exp(-tt / 0.15)) * np.exp(-np.maximum(tt - 0.3, 0) / 3.5)
        amp[s0:e0] = np.maximum(amp[s0:e0], vel * up * down * shape)
        if not legato_prev and scoop_cents:
            k = min(e0 - s0, nsamp(0.06))
            pitch[s0:s0 + k] += (scoop_cents / 100) * np.exp(-np.arange(k) / (0.015 * SR))
    return pitch, amp, age


def _vibrato(n, note_age, rate, depth_cents, delay=0.22, ramp=0.35, rng=None):
    t = secs(n)
    depth = np.clip((note_age - delay) / ramp, 0, 1) * depth_cents / 100
    jitter = 0.0
    if rng is not None:
        jitter = 0.15 * np.sin(TWO_PI * 0.7 * t + rng.uniform(0, 6))
    return depth * np.sin(TWO_PI * rate * t + jitter * 3)


def _additive_line(pitch, amp, harmonics, n):
    f = mtof(pitch)
    phase = TWO_PI * np.cumsum(f) / SR
    y = np.zeros(n)
    for k, a in enumerate(harmonics, start=1):
        if a == 0:
            continue
        mask = (k * f) < LIMIT
        y += a * np.sin(k * phase) * mask
    return y * amp


def ocarina(notes, n, rng):
    """Whistle / ocarina lead with breath, chiff and delayed vibrato."""
    pitch, amp, age = _line_controls(notes, n, glide=0.018, att=0.04, rel=0.12)
    pitch = pitch + _vibrato(n, age, 5.3, 14, rng=rng)
    y = _additive_line(pitch, amp, [1.0, 0.16, 0.08, 0.03, 0.012], n)
    noise = rng.standard_normal(n)
    breath = bandpass(noise, 1500, 6000, 2) * amp * 0.035
    chiff = bandpass(noise, 2500, 8000, 2) * np.exp(-np.clip(age, 0, 10) / 0.02) * amp * 0.12
    y = y + breath + chiff
    return lowpass(y, 7000)


def clarinet(notes, n, rng):
    """Soft clarinet/recorder hybrid: odd-leaning harmonics, warm."""
    pitch, amp, age = _line_controls(notes, n, glide=0.016, att=0.06, rel=0.16,
                                     scoop_cents=-25)
    pitch = pitch + _vibrato(n, age, 4.6, 9, delay=0.35, ramp=0.5, rng=rng)
    # brightness grows a little with amplitude
    dark = _additive_line(pitch, amp, [1.0, 0.06, 0.30, 0.03, 0.10, 0.015, 0.035], n)
    bright = _additive_line(pitch, amp, [1.0, 0.10, 0.45, 0.06, 0.22, 0.04, 0.10, 0.02, 0.04], n)
    a = np.clip(amp, 0, 1)
    y = dark * (1 - 0.5 * a) + bright * 0.5 * a
    noise = rng.standard_normal(n)
    y += bandpass(noise, 800, 4000, 2) * amp * 0.012
    y = lowpass(y, 3800, 2)
    return y
