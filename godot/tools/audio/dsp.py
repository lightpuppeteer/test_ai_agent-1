"""Core DSP helpers: filters, envelopes, reverb, loudness, limiting, IO.

Everything works on float64 numpy arrays at 44.1 kHz. Stereo = shape (n, 2).
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.ndimage import minimum_filter1d, uniform_filter1d
from scipy.io import wavfile

SR = 44100
NYQ = SR / 2


# ----------------------------------------------------------------- basics
def db(x):
    return 20.0 * np.log10(np.maximum(np.abs(x), 1e-12))


def undb(d):
    return 10.0 ** (d / 20.0)


def mtof(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


def secs(n):
    return np.arange(n) / SR


def nsamp(seconds):
    return int(round(seconds * SR))


def to_stereo(x):
    if x.ndim == 1:
        return np.stack([x, x], axis=1)
    return x


def to_mono(x):
    if x.ndim == 2:
        return x.mean(axis=1)
    return x


def pan(x, p):
    """Constant-power pan. p in [-1, 1]. Mono in -> stereo out."""
    a = (p + 1) * np.pi / 4
    if x.ndim == 2:
        return x * np.array([np.cos(a), np.sin(a)]) * np.sqrt(2)
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * np.sqrt(2)


def add_at(buf, x, start):
    """Add x into buf at integer sample `start` (clipped to buf bounds)."""
    n = len(x)
    s0 = max(0, start)
    s1 = min(len(buf), start + n)
    if s1 <= s0:
        return
    buf[s0:s1] += x[s0 - start:s1 - start]


def add_wrap(buf, x, start):
    """Add x into a circular buffer (loop) at `start`."""
    N = len(buf)
    start %= N
    pos = 0
    while pos < len(x):
        s = (start + pos) % N
        take = min(len(x) - pos, N - s)
        buf[s:s + take] += x[pos:pos + take]
        pos += take


# ----------------------------------------------------------------- filters
def _sos(kind, fc, order=2, q=None):
    if kind in ("low", "high"):
        fc = min(fc, NYQ * 0.95)
        return signal.butter(order, fc, kind, fs=SR, output="sos")
    raise ValueError(kind)


def lowpass(x, fc, order=2):
    return signal.sosfilt(_sos("low", fc, order), x, axis=0)


def highpass(x, fc, order=2):
    return signal.sosfilt(_sos("high", fc, order), x, axis=0)


def bandpass(x, lo, hi, order=2):
    hi = min(hi, NYQ * 0.95)
    sos = signal.butter(order, [lo, hi], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def rbj(kind, f0, q=0.707, gain_db=0.0):
    """RBJ cookbook biquad -> (b, a)."""
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * min(f0, NYQ * 0.98) / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2 * q)
    if kind == "bp":  # constant 0 dB peak gain
        b = [alpha, 0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        sa = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + sa), 2 * A * ((A - 1) - (A + 1) * cw),
             A * ((A + 1) - (A - 1) * cw - sa)]
        a = [(A + 1) + (A - 1) * cw + sa, -2 * ((A - 1) + (A + 1) * cw),
             (A + 1) + (A - 1) * cw - sa]
    elif kind == "highshelf":
        sa = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw),
             A * ((A + 1) + (A - 1) * cw - sa)]
        a = [(A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw),
             (A + 1) - (A - 1) * cw - sa]
    elif kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    else:
        raise ValueError(kind)
    b = np.array(b) / a[0]
    a = np.array(a) / a[0]
    return b, a


def biquad(x, kind, f0, q=0.707, gain_db=0.0):
    b, a = rbj(kind, f0, q, gain_db)
    return signal.lfilter(b, a, x, axis=0)


def resonator(x, f0, q):
    return biquad(x, "bp", f0, q)


def onepole_smooth(x, tau):
    """Causal one-pole smoother with time constant tau seconds."""
    if tau <= 0:
        return x
    a = np.exp(-1.0 / (tau * SR))
    return signal.lfilter([1 - a], [1, -a], x, axis=0)


def wrap_apply(func, x, pre_s=1.5):
    """Apply a causal filter to a loop so the result is circular-seamless."""
    pre = min(len(x), nsamp(pre_s))
    xx = np.concatenate([x[-pre:], x], axis=0)
    return func(xx)[pre:]


def fft_filter_circular(x, freqs_gain_fn):
    """Zero-phase circular filtering in the frequency domain (perfect loops)."""
    n = len(x)
    X = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = freqs_gain_fn(f)
    if X.ndim == 2:
        g = g[:, None]
    return np.fft.irfft(X * g, n=n, axis=0)


# ----------------------------------------------------------------- envelopes
def env_adsr(n, a, d, s, r, gate):
    """Linear attack, exponential decay to s, exponential release after gate.
    All times in seconds; returns length-n envelope."""
    t = secs(n)
    e = np.empty(n)
    a = max(a, 1e-4)
    att = t < a
    e[att] = 0.5 - 0.5 * np.cos(np.pi * t[att] / a)  # smooth attack
    dec = ~att
    e[dec] = s + (1 - s) * np.exp(-(t[dec] - a) / max(d, 1e-4))
    if gate is not None:
        gi = min(n - 1, max(0, nsamp(gate)))
        g_level = e[gi]
        rel = t >= gate
        e[rel] = g_level * np.exp(-(t[rel] - gate) / max(r / 4.6, 1e-4))
    return e


def fade_edges(x, fin=0.002, fout=0.01):
    x = x.copy()
    ni, no = nsamp(fin), nsamp(fout)
    if ni > 0:
        w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ni))
        x[:ni] *= w if x.ndim == 1 else w[:, None]
    if no > 0:
        w = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, no))
        x[-no:] *= w if x.ndim == 1 else w[:, None]
    return x


def release_gate(n, gate, rel):
    """1 until gate, then smooth cosine fade over rel seconds, 0 after."""
    t = secs(n)
    e = np.ones(n)
    m = t >= gate
    u = np.clip((t[m] - gate) / max(rel, 1e-4), 0, 1)
    e[m] = 0.5 + 0.5 * np.cos(np.pi * u)
    return e


# ----------------------------------------------------------------- noise
def pink_noise(n, rng):
    """Pink-ish noise via FFT shaping (circular, so it loops)."""
    w = rng.standard_normal(n)
    X = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    X /= np.sqrt(f)
    y = np.fft.irfft(X, n=n)
    return y / (np.std(y) + 1e-12)


def brown_noise(n, rng):
    w = rng.standard_normal(n)
    X = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    X /= f
    y = np.fft.irfft(X, n=n)
    return y / (np.std(y) + 1e-12)


def smooth_random(n, rate_hz, rng, loop=True):
    """Smooth random control signal in [-1,1]-ish, periodic if loop."""
    w = rng.standard_normal(n)
    X = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1 / SR)
    X *= np.exp(-(f / rate_hz) ** 2)
    X[0] = 0
    y = np.fft.irfft(X, n=n)
    return y / (np.max(np.abs(y)) + 1e-12)


# ----------------------------------------------------------------- reverb
def make_ir(rt60=1.8, predelay=0.02, length=None, seed=1, hf_damp=0.45,
            lf_boost=1.1, early=True, width=1.0):
    """Synthesized stereo reverb impulse response: band-wise exponentially
    decaying decorrelated noise, smooth build-up, sparse early reflections."""
    rng = np.random.default_rng(seed)
    L = nsamp(length if length else rt60 * 1.25)
    t = secs(L)
    bands = [(None, 250, rt60 * lf_boost), (250, 1200, rt60),
             (1200, 4000, rt60 * (0.5 + 0.5 * hf_damp + 0.2)),
             (4000, 9000, rt60 * hf_damp), (9000, None, rt60 * hf_damp * 0.5)]
    ir = np.zeros((L, 2))
    for ch in range(2):
        noise = rng.standard_normal(L)
        acc = np.zeros(L)
        for lo, hi, rt in bands:
            if lo is None:
                y = lowpass(noise, hi, 4)
            elif hi is None:
                y = highpass(noise, lo, 4)
            else:
                y = bandpass(noise, lo, hi, 2)
            acc += y * 10 ** (-3 * t / rt)
        ir[:, ch] = acc
    # decorrelation / width control
    mid = ir.mean(axis=1, keepdims=True)
    ir = mid + (ir - mid) * width
    ir *= (1 - np.exp(-t / 0.018))[:, None]  # diffuse build-up
    if early:
        for k in range(10):
            d = rng.uniform(0.004, 0.05)
            g = rng.uniform(0.15, 0.45) * np.exp(-d / 0.03)
            idx = nsamp(d)
            ir[idx, k % 2] += g * rng.choice([-1, 1]) * np.sqrt(np.sum(ir[:, 0] ** 2) / 600)
    ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
    pd = nsamp(predelay)
    ir = np.concatenate([np.zeros((pd, 2)), ir], axis=0)
    return ir


def reverb(x, ir, loop=False):
    """Mono-sum in, stereo out convolution reverb. If loop, the tail is folded
    back onto the start (circular) so the result has the same length."""
    m = to_mono(x)
    n = len(m)
    out = np.stack([signal.fftconvolve(m, ir[:, 0]), signal.fftconvolve(m, ir[:, 1])], axis=1)
    if loop:
        res = out[:n].copy()
        pos = n
        while pos < len(out):
            take = min(n, len(out) - pos)
            res[:take] += out[pos:pos + take]
            pos += take
        return res
    return out


# ----------------------------------------------------------------- loudness
def _kweight(x):
    # BS.1770 K-weighting (pyloudnorm-style parametrisation for any fs)
    b1, a1 = rbj("highshelf", 1681.974450955533, 0.7071752369554196, 3.99984385397)
    b2, a2 = rbj("hp", 38.13547087602444, 0.5003270373238773)
    y = signal.lfilter(b1, a1, x, axis=0)
    return signal.lfilter(b2, a2, y, axis=0)


def lufs(x):
    """Integrated loudness (BS.1770-4 gated)."""
    x = to_stereo(x) if x.ndim == 1 else x
    y = _kweight(x)
    blk = nsamp(0.4)
    hop = nsamp(0.1)
    if len(y) < blk:
        ms = np.mean(y ** 2, axis=0)
        return -0.691 + 10 * np.log10(np.sum(ms) + 1e-12)
    cs = np.cumsum(np.concatenate([np.zeros((1, y.shape[1])), y ** 2]), axis=0)
    starts = np.arange(0, len(y) - blk + 1, hop)
    ms = (cs[starts + blk] - cs[starts]) / blk  # (nblocks, ch)
    z = np.sum(ms, axis=1)
    lk = -0.691 + 10 * np.log10(z + 1e-12)
    g = lk > -70
    if not np.any(g):
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(z[g])) - 10
    g2 = g & (lk > rel)
    return -0.691 + 10 * np.log10(np.mean(z[g2]))


def lufs_mono(x):
    """Loudness of a mono file as played centred (both speakers)."""
    return lufs(np.stack([x, x], axis=1))


def peak_db(x):
    return db(np.max(np.abs(x)))


def rms_db(x):
    return db(np.sqrt(np.mean(np.asarray(x) ** 2)))


# ----------------------------------------------------------------- dynamics
def compressor(x, thresh_db=-20, ratio=2.0, win=0.05, smooth=0.12, loop=False,
               makeup_db=0.0):
    mode = "wrap" if loop else "nearest"
    m = to_mono(np.abs(x)) if x.ndim == 2 else np.abs(x)
    p = np.sqrt(uniform_filter1d((to_mono(x) if x.ndim == 2 else x) ** 2,
                                 max(1, nsamp(win)), mode=mode)) * np.sqrt(2)
    lvl = db(p)
    over = np.maximum(lvl - thresh_db, 0)
    gdb = -over * (1 - 1 / ratio)
    gdb = uniform_filter1d(gdb, max(1, nsamp(smooth)), mode=mode)
    g = undb(gdb + makeup_db)
    return x * (g[:, None] if x.ndim == 2 else g)


def limiter(x, ceiling_db=-3.5, hold=0.006, release=0.06, loop=False):
    """Look-ahead-style peak limiter (zero-latency, symmetric smoothing).
    Guarantees |y| <= ceiling (up to float error) because the smoothing
    kernels are contained within the minimum-filter window."""
    mode = "wrap" if loop else "nearest"
    c = undb(ceiling_db)
    pk = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    req = np.minimum(1.0, c / np.maximum(pk, 1e-12))
    b1, b2 = max(1, nsamp(hold)), max(1, nsamp(release))
    g = minimum_filter1d(req, size=2 * (b1 + b2) + 1, mode=mode)
    g = uniform_filter1d(g, b1, mode=mode)
    g = uniform_filter1d(g, b2, mode=mode)
    g = np.minimum(g, req)  # float safety
    return x * (g[:, None] if x.ndim == 2 else g)


def master(x, target_lufs=-17.0, ceiling_db=-3.5, loop=False, comp=True,
           mono=False, iters=3):
    """Normalise to target loudness then limit peaks; iterate to converge."""
    y = x.copy()
    if comp:
        y = compressor(y, thresh_db=rms_db(y) + 6, ratio=1.8, loop=loop)
    measure = lufs_mono if mono else lufs
    for _ in range(iters):
        L = measure(y)
        y = y * undb(target_lufs - L)
        y = limiter(y, ceiling_db, loop=loop)
    return y


def normalize_peak(x, peak_dbfs):
    return x * undb(peak_dbfs) / (np.max(np.abs(x)) + 1e-12)


# ----------------------------------------------------------------- IO
def write_wav(path, x):
    wavfile.write(path, SR, np.asarray(x, dtype=np.float32))


def encode(path, x, fmt="ogg", quality=5):
    """Write float audio to OGG Vorbis via ffmpeg (or 16-bit WAV)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x, dtype=np.float32)
    if fmt == "wav":
        y = np.clip(x, -1, 1)
        wavfile.write(path, SR, (y * 32767).astype(np.int16))
        return
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp = tf.name
    try:
        wavfile.write(tmp, SR, x)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp,
                        "-c:a", "libvorbis", "-q:a", str(quality),
                        "-map_metadata", "-1", path], check=True)
    finally:
        os.unlink(tmp)


def decode(path):
    """Decode any audio file via ffmpeg -> float array (n, ch)."""
    info = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0",
                           "-show_entries", "stream=channels", "-of", "csv=p=0", path],
                          capture_output=True, text=True, check=True)
    ch = int(info.stdout.strip().split(",")[0])
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le",
                          "-acodec", "pcm_f32le", "-"], capture_output=True, check=True).stdout
    a = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    return a.reshape(-1, ch)
