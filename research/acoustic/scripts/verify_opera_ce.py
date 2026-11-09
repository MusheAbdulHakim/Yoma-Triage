"""Verify the repo's OPERA-CE encoder exports against the official model and preprocessing.

Compares, on the same audio:
  1. Official: OPERA `get_entire_signal_librosa` -> mel (T, 64) -> official Encoder (PyTorch,
     weights `encoder-operaCE.ckpt` from HF evelyn0414/OPERA) -> 1280-d embedding.
  2. Repo ONNX  (mobile/assets/models/opera_ce_encoder.onnx), same mel.
  3. Repo TFLite (mobile/assets/models/opera_ce_encoder.tflite), input [1, 64, 251] float16,
     fed (a) mel.T (true transpose) and (b) the (251, 64) buffer reshaped as-is, which is what
     the app does when it copies a flat row-major (251 x 64) list into the tensor.
  4. The app/backend preprocessing (src/acoustic/opera_ce_mel.py logic, re-implemented here so
     nothing outside research/ is imported or changed) and a symmetric-Hann variant matching
     mobile/lib/services/opera_ce_mel.dart, against the official preprocessing.

Runs one model at a time and caches every stage to cache/opera_verify/*.npz, so it resumes.
Usage: .venv/bin/python scripts/verify_opera_ce.py
"""
from __future__ import annotations

import gc
import json
import sys
from pathlib import Path

import librosa
import numpy as np

HERE = Path(__file__).resolve().parents[1]           # research/acoustic
REPO = HERE.parents[1]
OPERA = HERE / "cache" / "OPERA"
CKPT = HERE / "cache" / "opera_ckpt" / "encoder-operaCE.ckpt"
ONNX = REPO / "mobile" / "assets" / "models" / "opera_ce_encoder.onnx"
TFLITE = REPO / "mobile" / "assets" / "models" / "opera_ce_encoder.tflite"
OUT = HERE / "cache" / "opera_verify"
OUT.mkdir(parents=True, exist_ok=True)
SR = 16000

sys.path.insert(0, str(OPERA))
from src.util import get_entire_signal_librosa, pre_process_audio_mel_t  # noqa: E402  official


# ---------------------------------------------------------------- test audio
def make_test_audio() -> dict[str, Path]:
    """Seeded synthetic clips plus two CirCor recordings (open, ODC-By), all written as wav."""
    import soundfile as sf
    d = OUT / "audio"
    d.mkdir(exist_ok=True)
    rng = np.random.default_rng(1234)
    t = np.arange(int(8.0 * SR)) / SR
    clips = {
        # breath-like: band noise with a 0.5 Hz (30 bpm) envelope
        "synthetic_breath_8s": rng.normal(size=t.size) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t)) * 0.1,
        # wheeze-like tone (400 Hz) over noise, 8 s
        "synthetic_wheeze_8s": 0.05 * np.sin(2 * np.pi * 400 * t) + rng.normal(size=t.size) * 0.02,
        # 3 s clip: exercises the official repeat padding vs the app's zero padding
        "synthetic_short_3s": (rng.normal(size=3 * SR) * 0.1),
        # 12 s clip: official uses the whole clip (T > 251); the app truncates to 8 s
        "synthetic_long_12s": rng.normal(size=12 * SR) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.4 * np.arange(12 * SR) / SR)) * 0.1,
    }
    paths = {}
    for name, y in clips.items():
        p = d / f"{name}.wav"
        if not p.exists():
            sf.write(p, y.astype(np.float32), SR)
        paths[name] = p
    for rec in ("2530_AV", "2530_MV"):
        p = HERE / "data" / "circor" / "training_data" / f"{rec}.wav"
        if p.exists():
            paths[f"circor_{rec}"] = p
    return paths


# ---------------------------------------------------------------- preprocessing
def official_mel(path: Path) -> np.ndarray:
    folder, stem = str(path.parent), path.stem
    return get_entire_signal_librosa(folder, stem, spectrogram=True, input_sec=8, pad=True).astype(np.float32)


def official_mel_fixed251(path: Path) -> np.ndarray:
    """Official preprocessing, then first 251 frames: the only shape a fixed [1,64,251] model takes."""
    m = official_mel(path)
    if m.shape[0] >= 251:
        return m[:251]
    return np.concatenate([m, np.zeros((251 - m.shape[0], 64), np.float32)])


def app_mel(path: Path, symmetric_hann: bool = False) -> np.ndarray:
    """src/acoustic/opera_ce_mel.mel_for_encoder logic: no trim, zero pad / truncate to 8 s."""
    y, _ = librosa.load(path, sr=SR)
    n = 8 * SR
    y = y[:n] if y.size >= n else np.concatenate([y, np.zeros(n - y.size, np.float32)])
    if symmetric_hann:   # Dart: w[i] = 0.5 - 0.5 cos(2 pi i / (n - 1)); librosa uses periodic Hann
        win = np.hanning(1024)
        S = np.abs(librosa.stft(y, n_fft=1024, hop_length=512, window=win)) ** 2
        S = librosa.feature.melspectrogram(S=S, sr=SR, n_mels=64, fmin=50, fmax=8000)
    else:
        S = librosa.feature.melspectrogram(y=y, sr=SR, n_mels=64, fmin=50, fmax=8000, n_fft=1024, hop_length=512)
    S = librosa.power_to_db(S, ref=np.max)
    S = (S - S.min()) / (S.max() - S.min())
    return S.T.astype(np.float32)[:251]


# ---------------------------------------------------------------- models (one at a time)
def run_official(mels: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    import torch
    from efficientnet_pytorch import EfficientNet

    class Encoder(torch.nn.Module):  # verbatim from OPERA src/model/models_cola.py (Encoder)
        def __init__(self, drop_connect_rate=0.1):
            super().__init__()
            self.cnn1 = torch.nn.Conv2d(1, 3, kernel_size=3)
            self.efficientnet = EfficientNet.from_name("efficientnet-b0", include_top=False,
                                                       drop_connect_rate=drop_connect_rate)

        def forward(self, x):
            x = x.unsqueeze(1)
            x = self.cnn1(x)
            x = self.efficientnet(x)
            return x.squeeze(3).squeeze(2)

    sd = torch.load(CKPT, map_location="cpu", weights_only=False)["state_dict"]
    enc_sd = {k[len("encoder."):]: v for k, v in sd.items() if k.startswith("encoder.")}
    enc = Encoder()
    enc.load_state_dict(enc_sd, strict=True)  # every encoder weight must match by name
    enc.eval()
    out = {}
    with torch.no_grad():
        for k, m in mels.items():
            out[k] = enc(torch.tensor(m[None], dtype=torch.float32)).numpy()[0]
    del enc, sd
    gc.collect()
    return out


def run_onnx(mels: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    import onnxruntime as ort
    s = ort.InferenceSession(str(ONNX), providers=["CPUExecutionProvider"])
    i = s.get_inputs()[0]
    print(f"ONNX input {i.name} {i.shape} {i.type}; output {s.get_outputs()[0].shape}")
    out = {k: s.run(None, {i.name: m[None].astype(np.float32)})[0][0] for k, m in mels.items()}
    del s
    gc.collect()
    return out


def run_tflite(mels: dict[str, np.ndarray]) -> dict[str, np.ndarray]:
    from ai_edge_litert.interpreter import Interpreter
    it = Interpreter(model_path=str(TFLITE))
    it.allocate_tensors()
    inp, outp = it.get_input_details()[0], it.get_output_details()[0]
    print(f"TFLite input {inp['shape']} {inp['dtype'].__name__}; output {outp['shape']} {outp['dtype'].__name__}")
    out = {}
    for k, m in mels.items():
        x = m.reshape(inp["shape"]) if k.endswith("|flat") else m.T[None]
        it.set_tensor(inp["index"], x.astype(inp["dtype"]))
        it.invoke()
        out[k] = it.get_tensor(outp["index"])[0].astype(np.float32)
    del it
    gc.collect()
    return out


def cached(name, fn, *a):
    p = OUT / f"{name}.npz"
    if p.exists():
        return dict(np.load(p))
    r = fn(*a)
    np.savez(p, **r)
    return r


def cos(a, b):
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b)))


def main():
    audio = make_test_audio()
    mel_off = cached("mel_official", lambda: {k: official_mel(p) for k, p in audio.items()})
    mel_251 = cached("mel_official_251", lambda: {k: official_mel_fixed251(p) for k, p in audio.items()})
    mel_app = cached("mel_app", lambda: {k: app_mel(p) for k, p in audio.items()})
    mel_dart = cached("mel_app_symhann", lambda: {k: app_mel(p, True) for k, p in audio.items()})

    # Embeddings from the official encoder on: official variable-length mel, the fixed 251 cut,
    # the app mel and the Dart-like mel. Keys are prefixed so one torch load serves all.
    feeds = {**{f"off|{k}": v for k, v in mel_off.items()},
             **{f"off251|{k}": v for k, v in mel_251.items()},
             **{f"app|{k}": v for k, v in mel_app.items()},
             **{f"dart|{k}": v for k, v in mel_dart.items()}}
    emb_t = cached("emb_torch", run_official, feeds)
    emb_o = cached("emb_onnx", run_onnx, {k: v for k, v in mel_251.items()})
    tfl_feeds = {**{f"{k}|T": v for k, v in mel_251.items()}, **{f"{k}|flat": v for k, v in mel_251.items()}}
    emb_l = cached("emb_tflite", run_tflite, tfl_feeds)

    rows = []
    for k in audio:
        ref = emb_t[f"off251|{k}"]
        r = {
            "clip": k,
            "official_frames": int(mel_off[k].shape[0]),
            "onnx_vs_torch_maxabs": float(np.abs(emb_o[k] - ref).max()),
            "tflite_T_vs_torch_maxabs": float(np.abs(emb_l[f"{k}|T"] - ref).max()),
            "tflite_T_vs_torch_cos": cos(emb_l[f"{k}|T"], ref),
            "tflite_flat_vs_torch_maxabs": float(np.abs(emb_l[f"{k}|flat"] - ref).max()),
            "tflite_flat_vs_torch_cos": cos(emb_l[f"{k}|flat"], ref),
            "ref_abs_max": float(np.abs(ref).max()),
            "mel_app_vs_official251_maxabs": float(np.abs(mel_app[k] - mel_251[k]).max()),
            "mel_dart_vs_app_maxabs": float(np.abs(mel_dart[k] - mel_app[k]).max()),
            "emb_app_vs_official_cos": cos(emb_t[f"app|{k}"], emb_t[f"off|{k}"]),
            "emb_dart_vs_app_cos": cos(emb_t[f"dart|{k}"], emb_t[f"app|{k}"]),
            "emb_fixed251_vs_official_full_cos": cos(ref, emb_t[f"off|{k}"]),
        }
        rows.append(r)
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "opera_ce_verification.json").write_text(json.dumps(rows, indent=2))
    for r in rows:
        print(json.dumps(r))


if __name__ == "__main__":
    main()
