"""Coswara as a real phone-audio reference for the degradation test (decision 7, item 9).

Compares simple signal statistics of real smartphone breathing recordings (Coswara
breathing-deep / breathing-shallow, adult, in air at the mouth) with the stethoscope datasets,
clean and under each simulated degradation. Coswara is band-limited to the same band as the
dataset it is compared with: 4 kHz for SPRSound (8 kHz audio), 2 kHz for CirCor (4 kHz audio),
by resampling down to that dataset's rate and back up to 16 kHz, exactly as the dataset audio is.

Statistics, per recording (all on the 16 kHz signal):
  level_dbfs     RMS level, dB re full scale
  lf_share_150   share of in-band energy below 150 Hz
  centroid_hz    spectral centroid
  dyn_range_db   95th minus 10th percentile of 50 ms frame energy (a rough SNR proxy)
Writes results/coswara_reference.json. Uses at most 300 recordings per group (seeded).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import librosa
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import CONDITIONS, DATA, NATIVE_SR, RESULTS, SR, degrade, load16k, manifest  # noqa: E402

N = 300


def stats(y):
    y = y.astype(np.float64)
    rms = np.sqrt(np.mean(y ** 2)) + 1e-12
    S = np.abs(np.fft.rfft(y)) ** 2
    f = np.fft.rfftfreq(len(y), 1 / SR)
    fr = librosa.util.frame(y, frame_length=800, hop_length=800) if len(y) >= 800 else y[:, None]
    e = 10 * np.log10(np.mean(fr ** 2, axis=0) + 1e-12)
    return {"level_dbfs": 20 * np.log10(rms), "lf_share_150": S[f < 150].sum() / (S.sum() + 1e-20),
            "centroid_hz": float((f * S).sum() / (S.sum() + 1e-20)),
            "dyn_range_db": float(np.percentile(e, 95) - np.percentile(e, 10))}


def band_limit(y, native):
    return librosa.resample(librosa.resample(y, orig_sr=SR, target_sr=native), orig_sr=native, target_sr=SR)


def agg(lst):
    return {k: {"median": float(np.median([d[k] for d in lst])),
                "iqr": [float(np.percentile([d[k] for d in lst], 25)),
                        float(np.percentile([d[k] for d in lst], 75))]} for k in lst[0]} | {"n": len(lst)}


def main():
    rng = np.random.default_rng(0)
    cos = sorted(p for p in (DATA / "coswara" / "audio").rglob("breathing-*.wav"))
    cos = [cos[i] for i in rng.permutation(len(cos))[:N]]
    res = {"coswara_files": len(cos)}
    raw = []
    for p in cos:
        try:
            y = load16k(str(p))
        except Exception:
            continue
        if len(y) > SR:
            raw.append(y)
    res["coswara_full_band"] = agg([stats(y) for y in raw])
    for ds in ["sprsound", "circor"]:
        nat = NATIVE_SR[ds]
        res[f"coswara_bandlimited_{nat // 2}hz"] = agg([stats(band_limit(y, nat)) for y in raw])
        rows = manifest(ds)
        rows = [rows[i] for i in rng.permutation(len(rows))[:N]]
        for c in CONDITIONS:
            res[f"{ds}|{c}"] = agg([stats(degrade(load16k(r["wav"]), c, r["rid"], nat)) for r in rows])
        print(ds, "done", flush=True)
    RESULTS.mkdir(exist_ok=True)
    (RESULTS / "coswara_reference.json").write_text(json.dumps(res, indent=1))
    for k, v in res.items():
        if isinstance(v, dict):
            print(f"{k:28s}", {s: round(v[s]['median'], 3) for s in v if s != 'n'})


if __name__ == "__main__":
    main()
