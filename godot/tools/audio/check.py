"""Objective checks: peaks, loudness, loop seams, spectrogram PNGs."""
import numpy as np

from dsp import SR, lufs, lufs_mono, peak_db, rms_db, to_mono, highpass


def seam_report(x):
    """Compare the loop junction (end -> start) with ordinary sample steps.
    Returns (step_ratio, rms_last_vs_first_db, hf_ratio)."""
    x2 = x if x.ndim == 2 else x[:, None]
    d = np.abs(np.diff(x2, axis=0)).max(axis=1)
    typical = np.percentile(d, 99.9) + 1e-12
    jump = np.abs(x2[0] - x2[-1]).max()
    w = int(0.1 * SR)
    r_last, r_first = rms_db(x2[-w:]), rms_db(x2[:w])
    # high-passed energy right at the junction vs around it (click detector)
    seg = np.concatenate([x2[-2048:], x2[:2048]], axis=0).mean(axis=1)
    hp = highpass(seg, 6000, 4)
    e_j = np.sqrt(np.mean(hp[2048 - 64:2048 + 64] ** 2))
    e_ref = np.sqrt(np.mean(hp ** 2)) + 1e-12
    return float(jump / typical), float(r_last - r_first), float(e_j / e_ref)


def summarize(x, loop=False):
    mono = x.ndim == 1 or x.shape[1] == 1
    xm = x.reshape(-1) if mono else x
    info = {
        "peak_dbfs": round(float(peak_db(xm)), 2),
        "lufs": round(float(lufs_mono(xm) if mono else lufs(xm)), 2),
        "rms_dbfs": round(float(rms_db(xm)), 2),
        "duration_s": round(len(xm) / SR, 3),
        "channels": 1 if mono else 2,
    }
    if loop:
        sr_, rr, hf = seam_report(x if not mono else xm)
        info["seam_step_ratio"] = round(sr_, 3)
        info["seam_rms_diff_db"] = round(rr, 2)
        info["seam_hf_ratio"] = round(hf, 2)
    return info


def spectrogram_png(path, x, title, tmax=None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from scipy import signal
    m = to_mono(x)
    if tmax:
        m = m[: int(tmax * SR)]
    f, t, S = signal.spectrogram(m, SR, nperseg=2048, noverlap=1536)
    Sdb = 10 * np.log10(S + 1e-14)
    fig, ax = plt.subplots(2, 1, figsize=(14, 7), gridspec_kw={"height_ratios": [3, 1]})
    vmax = Sdb.max()
    ax[0].pcolormesh(t, f, Sdb, vmin=vmax - 90, vmax=vmax, shading="auto", cmap="magma")
    ax[0].set_yscale("symlog", linthresh=500)
    ax[0].set_ylim(30, 20000)
    ax[0].set_title(title)
    ax[0].set_ylabel("Hz")
    hop = int(0.05 * SR)
    env = [20 * np.log10(np.sqrt(np.mean(m[i:i + hop] ** 2)) + 1e-9) for i in range(0, len(m) - hop, hop)]
    ax[1].plot(np.arange(len(env)) * 0.05, env, lw=0.7)
    ax[1].set_ylabel("RMS dB")
    ax[1].set_xlabel("s")
    ax[1].set_ylim(-60, 0)
    ax[1].grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=70)
    plt.close(fig)
