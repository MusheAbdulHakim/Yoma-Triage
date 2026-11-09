"""Verify Google's official YAMNet TFLite variants against the official TF2 SavedModel.

Models (downloaded by scripts/download_models.sh into cache/yamnet/):
  - savedmodel/                         Kaggle google/yamnet/tensorFlow2/yamnet/1 (reference)
  - yamnet_tflite_1.tflite              Kaggle/TF Hub lite-model/yamnet/tflite/1: scores, embeddings, spectrogram
  - yamnet_classification_tflite_1.tflite  lite-model/yamnet/classification/tflite/1: scores only
  - mobile/assets/models/yamnet.tflite  the app's copy (read only)

Input: the app's fixed 15,600-sample float32 window (0.975 s at 16 kHz), plus a 3-window clip.
The full TFLite variant has a dynamic input, so it is resized to 15,600 here.
Results are written to results/yamnet_verification.json.
"""
from __future__ import annotations

import gc
import json
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parents[1]
Y = HERE / "cache" / "yamnet"
APP = HERE.parents[1] / "mobile" / "assets" / "models" / "yamnet.tflite"


def inputs():
    rng = np.random.default_rng(42)
    t = np.arange(15600) / 16000
    xs = {
        "noise": (rng.normal(size=15600) * 0.1),
        "tone_400hz": 0.3 * np.sin(2 * np.pi * 400 * t),
        "breath_like": rng.normal(size=15600) * 0.1 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t)),
    }
    cv = HERE / "data" / "circor" / "training_data" / "2530_AV.wav"
    if cv.exists():
        import librosa
        y, _ = librosa.load(cv, sr=16000)
        xs["circor_2530_AV"] = y[:15600]
    return {k: np.clip(v, -1, 1).astype(np.float32) for k, v in xs.items()}


def run_tf(xs):
    import tensorflow as tf
    m = tf.saved_model.load(str(Y / "savedmodel"))
    out = {}
    for k, x in xs.items():
        s, e, sp = m(x)
        out[k] = (s.numpy(), e.numpy(), sp.numpy())
    del m
    gc.collect()
    return out


def run_tflite(path, xs, resize=True):
    from ai_edge_litert.interpreter import Interpreter
    it = Interpreter(model_path=str(path))
    inp = it.get_input_details()[0]
    if resize and list(inp["shape"]) != [15600]:
        it.resize_tensor_input(inp["index"], [15600])
    it.allocate_tensors()
    outs = it.get_output_details()
    out = {}
    for k, x in xs.items():
        it.set_tensor(inp["index"], x)
        it.invoke()
        by_width = {o["shape"][-1]: it.get_tensor(o["index"]) for o in outs}
        out[k] = by_width
    return out, [(o["name"], [int(d) for d in it.get_tensor(o["index"]).shape]) for o in outs]


def main():
    xs = inputs()
    tf_out = run_tf(xs)
    full, full_outs = run_tflite(Y / "yamnet_tflite_1.tflite", xs)
    cls, _ = run_tflite(Y / "yamnet_classification_tflite_1.tflite", xs, resize=False)
    app, _ = run_tflite(APP, xs, resize=False)
    rows = []
    for k in xs:
        s, e, sp = tf_out[k]
        r = {
            "input": k,
            "tf_shapes": {"scores": [int(d) for d in s.shape], "embeddings": [int(d) for d in e.shape], "log_mel": [int(d) for d in sp.shape]},
            "full_tflite_outputs": full_outs,
            "full_tflite_scores_maxabs": float(np.abs(full[k][521] - s).max()),
            "full_tflite_embeddings_maxabs": float(np.abs(full[k][1024] - e).max()),
            "embeddings_abs_max": float(np.abs(e).max()),
            "full_tflite_logmel_maxabs": float(np.abs(full[k][64] - sp).max()),
            "classification_tflite_scores_maxabs_vs_tf": float(np.abs(cls[k][521] - s).max()),
            "app_vs_classification_maxabs": float(np.abs(app[k][521] - cls[k][521]).max()),
            "top1_tf": int(s.mean(0).argmax()), "top1_app": int(app[k][521].mean(0).argmax()),
        }
        rows.append(r)
        print(json.dumps(r))
    (HERE / "results").mkdir(exist_ok=True)
    (HERE / "results" / "yamnet_verification.json").write_text(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()
