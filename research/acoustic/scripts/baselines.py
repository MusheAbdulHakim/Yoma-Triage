"""Non-AI baselines (experiment e), clean and degraded. Writes results/baselines.json.

Breathing rate (SPRSound)
  Method: 16 kHz audio -> band-pass 150-800 Hz -> RMS envelope (50 ms frames, 20 ms hop) ->
  low-pass 2 Hz -> autocorrelation; the breath period is the highest peak between 0.6 and 4 s
  (15-100 breaths/min).
  Reference: the annotated events. Rate = 60 / median interval between event onsets, on
  recordings with at least 4 events. This is a PROXY: SPRSound does not state that one event is
  one breath (events have median 1.3 s, separated by median 0.7 s gaps).

Heart rate and rhythm regularity (CirCor)
  Method: band-pass 25-400 Hz -> Shannon energy envelope (20 ms frames, 5 ms hop) -> low-pass
  8 Hz -> autocorrelation; the beat period is the highest peak between 0.3 and 1.5 s
  (40-200 bpm). Regularity: beats = envelope peaks at least 0.6 periods apart; coefficient of
  variation (CV) of the beat-to-beat intervals.
  Reference: the dataset's S1 segmentation (.tsv, state 1). HR = 60 / median S1-S1 interval;
  regularity = CV of S1-S1 intervals. CirCor has no arrhythmia label, so regularity can only be
  compared with the segmentation, not with a diagnosis.

Errors: mean absolute error (MAE), median AE, share within +/-5 per minute (and +/-10% for HR);
95% CI of the MAE by bootstrapping patients (1000 resamples).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy.signal import butter, find_peaks, sosfiltfilt
from scipy.stats import spearmanr

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import NATIVE_SR, RESULTS, SR, degrade, load16k, manifest  # noqa: E402

CONDS = ["clean", "hp150", "noise10", "noise5"]


def _bp(y, lo, hi, fs=SR):
    return sosfiltfilt(butter(4, [lo / (fs / 2), hi / (fs / 2)], btype="band", output="sos"), y)


def _frames(y, win, hop):
    n = 1 + max(0, (len(y) - win) // hop)
    idx = np.arange(win)[None, :] + hop * np.arange(n)[:, None]
    return y[idx]


def _acf_period(env, fs_env, lo_s, hi_s):
    e = env - env.mean()
    if len(e) < int(hi_s * fs_env) + 2 or not np.any(e):
        return None, 0.0
    ac = np.correlate(e, e, "full")[len(e) - 1:]
    ac = ac / (ac[0] + 1e-12)
    a, b = int(lo_s * fs_env), min(int(hi_s * fs_env), len(ac) - 1)
    k = a + int(np.argmax(ac[a:b + 1]))
    return k / fs_env, float(ac[k])


def breath_rate(y):
    x = _bp(y, 150, 800)
    env = np.sqrt(np.mean(_frames(x, 800, 320) ** 2, axis=1))          # 50 ms / 20 ms -> 50 Hz
    env = sosfiltfilt(butter(2, 2 / 25, output="sos"), env)
    p, _ = _acf_period(env, 50, 0.6, 4.0)
    return None if p is None else 60 / p


def heart(y):
    x = _bp(y, 25, 400)
    x = x / (np.max(np.abs(x)) + 1e-12)
    se = -np.mean(_frames(x ** 2 * np.log(x ** 2 + 1e-12), 320, 80), axis=1)  # 20 ms / 5 ms -> 200 Hz
    env = sosfiltfilt(butter(2, 8 / 100, output="sos"), se)
    p, strength = _acf_period(env, 200, 0.3, 1.5)
    if p is None:
        return None, None
    pk, _ = find_peaks(env, distance=max(1, int(0.6 * p * 200)))
    iv = np.diff(pk) / 200
    cv = float(np.std(iv) / np.mean(iv)) if len(iv) >= 3 else None
    return 60 / p, cv


def ref_breath(r):
    on = np.sort([e["start"] for e in r["events"]]) / 1000
    if len(on) < 4:
        return None
    return 60 / np.median(np.diff(on))


def ref_heart(tsv):
    try:
        a = np.loadtxt(tsv, ndmin=2)
    except Exception:
        return None, None
    s1 = a[a[:, 2] == 1, 0]
    if len(s1) < 4:
        return None, None
    iv = np.diff(s1)
    iv = iv[(iv > 0.25) & (iv < 2.0)]            # ignore gaps across unannotated stretches
    if len(iv) < 3:
        return None, None
    return 60 / np.median(iv), float(np.std(iv) / np.mean(iv))


def err_summary(est, ref, pid, band, n_boot=1000, pct=False):
    est, ref, pid, band = map(np.asarray, (est, ref, pid, band))
    ok = np.array([e is not None for e in est])
    out = {"n_total": int(len(est)), "n_estimated": int(ok.sum())}
    est, ref, pid, band = est[ok].astype(float), ref[ok].astype(float), pid[ok], band[ok]

    def summ(e, r, p):
        ae = np.abs(e - r)
        d = {"n": int(len(e)), "n_patients": int(len(np.unique(p))),
             "mae": float(ae.mean()), "median_ae": float(np.median(ae)),
             "bias": float(np.mean(e - r)), "within_5": float(np.mean(ae <= 5))}
        if pct:
            d["within_10pct"] = float(np.mean(ae <= 0.1 * r))
        rng = np.random.default_rng(0)
        pats = np.unique(p)
        idx = {q: np.where(p == q)[0] for q in pats}
        bs = [ae[np.concatenate([idx[q] for q in rng.choice(pats, len(pats))])].mean()
              for _ in range(n_boot)]
        d["mae_ci"] = [float(np.percentile(bs, 2.5)), float(np.percentile(bs, 97.5))]
        return d
    out["all"] = summ(est, ref, pid)
    out["bands"] = {b: summ(est[band == b], ref[band == b], pid[band == b])
                    for b in sorted(set(band)) if (band == b).sum() >= 5}
    return out


def main():
    out_p = RESULTS / "baselines.json"
    res = json.loads(out_p.read_text()) if out_p.exists() else {}
    spr = [r for r in manifest("sprsound") if ref_breath(r) is not None]
    for c in CONDS:
        k = f"breath|{c}"
        if k in res:
            continue
        est = [breath_rate(degrade(load16k(r["wav"]), c, r["rid"], NATIVE_SR["sprsound"])) for r in spr]
        res[k] = err_summary(est, [ref_breath(r) for r in spr], [r["pid"] for r in spr],
                             [r["band"] for r in spr])
        res[k]["reference_rate_median"] = float(np.median([ref_breath(r) for r in spr]))
        print(k, json.dumps(res[k]["all"]), flush=True)
        out_p.write_text(json.dumps(res, indent=1))
    cir = []
    for r in manifest("circor"):
        hr, cv = ref_heart(r["tsv"])
        if hr is not None:
            cir.append((r, hr, cv))
    for c in CONDS:
        k = f"heart|{c}"
        if k in res:
            continue
        est = [heart(degrade(load16k(r["wav"]), c, r["rid"], NATIVE_SR["circor"])) for r, _, _ in cir]
        res[k] = err_summary([e[0] for e in est], [h for _, h, _ in cir], [r["pid"] for r, _, _ in cir],
                             [r["band"] for r, _, _ in cir], pct=True)
        pairs = [(e[1], cv) for e, (_, _, cv) in zip(est, cir) if e[1] is not None and cv is not None]
        rho = spearmanr([a for a, _ in pairs], [b for _, b in pairs])
        res[k]["regularity"] = {"n": len(pairs), "spearman_rho": float(rho.statistic),
                                "p": float(rho.pvalue),
                                "ref_cv_median": float(np.median([b for _, b in pairs])),
                                "est_cv_median": float(np.median([a for a, _ in pairs])),
                                "ref_cv_over_0.15": int(sum(b > 0.15 for _, b in pairs))}
        res[k]["reference_hr_median"] = float(np.median([h for _, h, _ in cir]))
        print(k, json.dumps(res[k]["all"]), json.dumps(res[k]["regularity"]), flush=True)
        out_p.write_text(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
