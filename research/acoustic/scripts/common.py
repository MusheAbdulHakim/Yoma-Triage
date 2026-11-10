"""Shared paths, manifests, audio loading and the phone-degradation transforms (Steps 3-5)."""
from __future__ import annotations

import csv
import json
import re
import zlib
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parents[1]
DATA = HERE / "data"
CACHE = HERE / "cache"
RESULTS = HERE / "results"
SR = 16000                      # every model here takes 16 kHz mono
NATIVE_SR = {"sprsound": 8000, "circor": 4000}

# Weight licences, shown in every results table (decision 3).
LICENCE = {"yamnet_app": "Apache 2.0", "yamnet_float": "Apache 2.0",
           "opera": "CC BY-NC 4.0", "opera_win": "CC BY-NC 4.0", "opera_first8": "CC BY-NC 4.0",
           "envelope": "n/a (no model)"}

CONDITIONS = ["clean", "hp100", "hp150", "noise10", "noise5", "level-20"]


# ------------------------------------------------------------------ manifests
def band_years(age):
    if age is None:
        return "unknown"
    if age < 2 / 12:
        return "<2 mo"
    if age < 1:
        return "2-11 mo"
    if age < 6:
        return "1-5 y"
    return "6+ y"


SPR_RE = re.compile(r"^([^_]*)_([\d.]+)_(\d)_(p\d+)_(\d+)$")


def sprsound_manifest():
    """One row per unique recording in the year folders that has a patient ID and is usable."""
    repo = DATA / "sprsound" / "repo"
    rows = {}
    # BioCAS2022/test2022_json/ has inter_test_json/ and intra_test_json/ subfolders; the
    # matching audio is flat in test2022_wav/. So: year folder / first *_json level -> *_wav.
    for jp in sorted(repo.glob("BioCAS20*/*_json/**/*.json")):
        m = SPR_RE.match(jp.stem)
        if not m:
            continue
        pid, age, sex, loc, rid = m.groups()
        year, top = jp.relative_to(repo).parts[:2]
        wav = DATA / "sprsound" / "wav" / year / top.replace("_json", "_wav") / f"{jp.stem}.wav"
        j = json.loads(jp.read_text())
        ev = [e for e in (j.get("event_annotation") or [])]
        rec = j.get("record_annotation")
        r = rows.setdefault(rid, {"rid": rid, "pid": pid, "age": float(age), "loc": loc,
                                  "wav": str(wav), "events": [], "record": None,
                                  "split": top})
        r["events"] += [{"start": float(e["start"]), "end": float(e["end"]), "type": e["type"]}
                        for e in ev]
        r["record"] = r["record"] or rec
    out = []
    for r in rows.values():
        if not r["pid"]:
            continue                        # anonymised: cannot be grouped by patient
        if r["record"] == "Poor Quality":
            continue
        if not r["events"] and not r["record"]:
            continue
        types = {e["type"] for e in r["events"]}
        r["y_stridor"] = int("Stridor" in types)
        r["y_wheeze"] = int(bool(types & {"Wheeze", "Wheeze+Crackle"}))
        r["y_crackle"] = int(bool(types & {"Fine Crackle", "Coarse Crackle", "Wheeze+Crackle"}))
        r["band"] = band_years(r["age"])
        r["dataset"] = "sprsound"
        out.append(r)
    return out


CIRCOR_BAND = {"Neonate": "Neonate (0-27 d)", "Infant": "Infant (28 d-1 y)",
               "Child": "Child (1-11 y)", "Adolescent": "Adolescent (12-18 y)"}


def circor_manifest():
    """One row per recording; patient labels attached. Location from the filename."""
    pts = {}
    with open(DATA / "circor" / "training_data.csv") as f:
        for r in csv.DictReader(f):
            pts[r["Patient ID"]] = r
    out = []
    for line in (DATA / "circor" / "RECORDS").read_text().split():
        stem = line.split("/")[-1]
        pid, loc = stem.split("_")[0], stem.split("_")[1]
        p = pts[pid]
        mlocs = set((p["Murmur locations"] or "").split("+")) - {""}
        out.append({
            "rid": stem, "pid": pid, "loc": loc, "dataset": "circor",
            "wav": str(DATA / "circor" / f"{line}.wav"),
            "tsv": str(DATA / "circor" / f"{line}.tsv"),
            "murmur": p["Murmur"], "outcome": p["Outcome"],
            "y_murmur_rec": int(p["Murmur"] == "Present" and loc in mlocs),
            "band": CIRCOR_BAND.get(p["Age"].strip(), "unknown"),
        })
    return out


def manifest(dataset):
    return sprsound_manifest() if dataset == "sprsound" else circor_manifest()


# ------------------------------------------------------------------ audio
def load16k(path):
    """librosa.load(sr=16000) mono: the same resampling OPERA's official loader does (soxr_hq).
    SPRSound (8 kHz) and CirCor (4 kHz) are upsampled, so nothing exists above 4 / 2 kHz."""
    import librosa
    y, _ = librosa.load(path, sr=SR)
    return y.astype(np.float32)


def _seed(key: str, cond: str) -> int:
    return zlib.crc32(f"{key}|{cond}".encode())


def band_limited_noise(n, cutoff_hz, rng, colour="pink"):
    """Pink (1/f) noise, plus a weak 50 Hz mains hum, low-passed at `cutoff_hz`, unit RMS.
    Stationary clinic-like noise; real clinic noise (voices, crying) is not stationary."""
    from scipy.signal import butter, sosfilt
    w = rng.standard_normal(n)
    if colour == "pink":
        f = np.fft.rfftfreq(n, 1 / SR)
        spec = np.fft.rfft(w)
        spec[1:] /= np.sqrt(f[1:])
        spec[0] = 0
        w = np.fft.irfft(spec, n)
    t = np.arange(n) / SR
    w = w / (np.std(w) + 1e-12) + 0.3 * np.sin(2 * np.pi * 50 * t + rng.uniform(0, 6.28))
    sos = butter(8, min(cutoff_hz, SR / 2 - 100) / (SR / 2), btype="low", output="sos")
    w = sosfilt(sos, w)
    return (w / (np.std(w) + 1e-12)).astype(np.float32)


def degrade(y, cond, key, native_sr):
    """Phone-degradation conditions, applied to the 16 kHz signal. Noise is band-limited to the
    dataset's own band (native Nyquist) so the SNR is in-band and comparable across datasets."""
    from scipy.signal import butter, sosfiltfilt
    if cond == "clean":
        return y
    rng = np.random.default_rng(_seed(key, cond))
    if cond.startswith("hp"):
        fc = float(cond[2:])
        sos = butter(4, fc / (SR / 2), btype="high", output="sos")
        return sosfiltfilt(sos, y).astype(np.float32)
    if cond.startswith("noise"):
        snr = float(cond[5:])
        n = band_limited_noise(y.size, native_sr / 2, rng)
        p_sig = np.mean(y.astype(np.float64) ** 2) + 1e-20
        return (y + n * np.sqrt(p_sig / 10 ** (snr / 10))).astype(np.float32)
    if cond == "level-20":
        # 20 dB lower gain against a fixed sensor noise floor (-70 dBFS RMS) and 16-bit quantisation
        z = y * 0.1 + band_limited_noise(y.size, native_sr / 2, rng, "white") * 10 ** (-70 / 20)
        return (np.round(np.clip(z, -1, 1) * 32767) / 32767).astype(np.float32)
    raise ValueError(cond)
