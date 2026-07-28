#!/usr/bin/env python3
"""Train / export OPERA-CE classification head from ethics-approved lab clips.

Does **not** invent clinical labels. Requires a lab-set manifest:

  path,label
  clips/normal_001.wav,normal
  clips/abnormal_001.wav,abnormal

Labels: `normal` | `abnormal` (advisory only). Mid-band fail-closed lives in the app.

Usage:
  # Extract embeddings only (inspect / resume)
  python scripts/train_opera_ce_head.py embed --manifest data/lab_set/manifest.csv

  # Train logistic head + export ONNX (optional TFLite via onnx2tf)
  python scripts/train_opera_ce_head.py train --manifest data/lab_set/manifest.csv

  # Pipeline smoke: synthesize non-clinical tones, train, export (CI only)
  python scripts/train_opera_ce_head.py smoke
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.acoustic.opera_ce_mel import (  # noqa: E402
    EMBED_DIM,
    MEL_BINS,
    MEL_FRAMES,
    SAMPLE_RATE,
    mel_for_encoder,
)

ONNX_ENCODER = ROOT / "mobile" / "assets" / "models" / "opera_ce_encoder.onnx"
HEAD_ONNX = ROOT / "mobile" / "assets" / "models" / "opera_ce_head.onnx"
HEAD_TFLITE = ROOT / "mobile" / "assets" / "models" / "opera_ce_head.tflite"
EMBED_CACHE = ROOT / "data" / "lab_set" / ".cache" / "embeddings.npz"
LAB_DIR = ROOT / "data" / "lab_set"


def _load_wav_mono_16k(path: Path) -> np.ndarray:
    with wave.open(str(path), "rb") as wf:
        assert wf.getnchannels() == 1, path
        assert wf.getsampwidth() == 2, path
        sr = wf.getframerate()
        raw = wf.readframes(wf.getnframes())
    audio = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if sr != SAMPLE_RATE:
        # Linear resample (lab SOP should record @ 16 kHz)
        duration = audio.shape[0] / sr
        n = int(duration * SAMPLE_RATE)
        x_old = np.linspace(0.0, 1.0, audio.shape[0], endpoint=False)
        x_new = np.linspace(0.0, 1.0, n, endpoint=False)
        audio = np.interp(x_new, x_old, audio).astype(np.float32)
    return audio


def _run_encoder(mel_batch: np.ndarray) -> np.ndarray:
    import onnxruntime as ort

    if not ONNX_ENCODER.is_file():
        raise SystemExit(f"Missing encoder ONNX: {ONNX_ENCODER}")
    sess = ort.InferenceSession(str(ONNX_ENCODER), providers=["CPUExecutionProvider"])
    name = sess.get_inputs()[0].name
    out = sess.run(None, {name: mel_batch.astype(np.float32)})[0]
    assert out.shape[-1] == EMBED_DIM, out.shape
    return out.astype(np.float32)


def _read_manifest(path: Path) -> list[tuple[Path, int]]:
    rows: list[tuple[Path, int]] = []
    with path.open(newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            p = Path(row["path"])
            if not p.is_absolute():
                p = (path.parent / p).resolve()
            label = row["label"].strip().lower()
            if label in {"normal", "green", "0"}:
                y = 0
            elif label in {"abnormal", "red", "1"}:
                y = 1
            else:
                raise SystemExit(f"Unknown label {label!r} in {path}")
            rows.append((p, y))
    return rows


def cmd_embed(manifest: Path, out: Path) -> None:
    rows = _read_manifest(manifest)
    xs = []
    ys = []
    paths = []
    for wav_path, y in rows:
        audio = _load_wav_mono_16k(wav_path)
        mel = mel_for_encoder(audio)
        assert mel.shape == (1, MEL_FRAMES, MEL_BINS), mel.shape
        emb = _run_encoder(mel)[0]
        xs.append(emb)
        ys.append(y)
        paths.append(str(wav_path))
        print(f"embedded {wav_path.name} label={y} ||emb||={float(np.linalg.norm(emb)):.3f}")
    out.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        out,
        X=np.stack(xs),
        y=np.asarray(ys, dtype=np.int64),
        paths=np.asarray(paths),
    )
    print(f"Wrote {out} ({len(xs)} clips)")


def cmd_train(manifest: Path | None, embeddings: Path, export_tflite: bool) -> None:
    if manifest is not None and (not embeddings.is_file() or manifest.stat().st_mtime > embeddings.stat().st_mtime):
        cmd_embed(manifest, embeddings)
    if not embeddings.is_file():
        raise SystemExit(f"Need embeddings at {embeddings} (run embed first)")

    blob = np.load(embeddings, allow_pickle=True)
    X = blob["X"].astype(np.float64)
    y = blob["y"].astype(np.int64)
    if len(np.unique(y)) < 2:
        raise SystemExit("Need both normal and abnormal labels to train a head")
    if X.shape[0] < 8:
        print(
            f"WARNING: only {X.shape[0]} clips — head will overfit; lab target is ≥100",
            file=sys.stderr,
        )

    # Closed-form / sklearn logistic; keep dependency light with numpy IRLS-ish via lstsq on features
    try:
        from sklearn.linear_model import LogisticRegression
        from sklearn.model_selection import cross_val_score
    except ImportError as exc:
        raise SystemExit("pip install scikit-learn for head training") from exc

    clf = LogisticRegression(max_iter=2000, class_weight="balanced")
    if X.shape[0] >= 10:
        scores = cross_val_score(clf, X, y, cv=min(5, X.shape[0] // 2), scoring="accuracy")
        print(f"CV accuracy mean={scores.mean():.3f} std={scores.std():.3f}")
    clf.fit(X, y)
    print(f"Train accuracy={clf.score(X, y):.3f} n={X.shape[0]}")

    # Export ONNX: y = Wx + b → 2 logits (classes_ order)
    import onnx
    from onnx import TensorProto, helper, numpy_helper

    classes = list(clf.classes_)
    # Ensure column order [normal=0, abnormal=1]
    coef = clf.coef_.astype(np.float32)  # (1, 1280) for binary
    intercept = clf.intercept_.astype(np.float32)
    # sklearn binary: P(class=1) via single logit; expand to 2-class logits [ -z, z ]
    w_abn = coef.reshape(1, EMBED_DIM)
    b_abn = intercept.reshape(1)
    W = np.vstack([-w_abn, w_abn]).astype(np.float32)  # (2, 1280)
    B = np.concatenate([-b_abn, b_abn]).astype(np.float32)

    W_init = numpy_helper.from_array(W, name="W")
    B_init = numpy_helper.from_array(B, name="B")
    nodes = [
        helper.make_node("Gemm", ["embedding", "W", "B"], ["logits"], alpha=1.0, beta=1.0, transB=1),
    ]
    graph = helper.make_graph(
        nodes,
        "opera_ce_head",
        [helper.make_tensor_value_info("embedding", TensorProto.FLOAT, [None, EMBED_DIM])],
        [helper.make_tensor_value_info("logits", TensorProto.FLOAT, [None, 2])],
        [W_init, B_init],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 18)])
    onnx.checker.check_model(model)
    HEAD_ONNX.parent.mkdir(parents=True, exist_ok=True)
    onnx.save(model, str(HEAD_ONNX))
    meta = {
        "classes": [int(c) for c in classes],
        "n_train": int(X.shape[0]),
        "encoder": str(ONNX_ENCODER.name),
        "note": "Advisory head only — not clinically validated",
    }
    HEAD_ONNX.with_suffix(".json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"Wrote {HEAD_ONNX}")

    if export_tflite:
        _onnx_to_tflite(HEAD_ONNX, HEAD_TFLITE)


def _onnx_to_tflite(onnx_path: Path, tflite_path: Path) -> None:
    import shutil
    import subprocess

    tmp = Path("/tmp/opera_ce_head_tf")
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)
    try:
        subprocess.check_call(["onnx2tf", "-i", str(onnx_path), "-o", str(tmp)])
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"TFLite export skipped: {exc}", file=sys.stderr)
        return
    candidates = sorted(tmp.rglob("*.tflite"))
    if not candidates:
        print("onnx2tf produced no tflite", file=sys.stderr)
        return
    tflite_path.write_bytes(candidates[0].read_bytes())
    print(f"Wrote {tflite_path} ({tflite_path.stat().st_size} bytes)")


def _write_tone_wav(path: Path, freq_hz: float, seconds: float = 8.0, amp: float = 0.2) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    n = int(SAMPLE_RATE * seconds)
    t = np.arange(n, dtype=np.float32) / SAMPLE_RATE
    audio = (amp * np.sin(2 * np.pi * freq_hz * t)).astype(np.float32)
    # Add light noise so mel is non-degenerate
    rng = np.random.default_rng(int(freq_hz * 10))
    audio += 0.01 * rng.standard_normal(n).astype(np.float32)
    pcm = np.clip(audio * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm.tobytes())


def cmd_smoke() -> None:
    """Non-clinical synthetic tones — proves embed→train→export; do not ship as clinical head."""
    smoke_dir = LAB_DIR / "synthetic_smoke"
    manifest = smoke_dir / "manifest.csv"
    rows = []
    for i, freq in enumerate([200.0, 250.0, 300.0, 350.0]):
        p = smoke_dir / f"normal_{i}.wav"
        _write_tone_wav(p, freq)
        rows.append((p.relative_to(smoke_dir), "normal"))
    for i, freq in enumerate([1200.0, 1500.0, 1800.0, 2100.0]):
        p = smoke_dir / f"abnormal_{i}.wav"
        _write_tone_wav(p, freq, amp=0.35)
        rows.append((p.relative_to(smoke_dir), "abnormal"))
    with manifest.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["path", "label"])
        w.writeheader()
        for rel, label in rows:
            w.writerow({"path": str(rel), "label": label})
    readme = smoke_dir / "README.md"
    readme.write_text(
        "# Synthetic smoke clips (NOT clinical)\n\n"
        "Deterministic sine tones for CI of the OPERA-CE head pipeline only.\n"
        "Do **not** ship a head trained only on these as a clinical model.\n"
    )
    emb = smoke_dir / "embeddings.npz"
    cmd_embed(manifest, emb)
    cmd_train(None, emb, export_tflite=False)
    # Do not copy smoke head into mobile/assets — keep under synthetic_smoke
    smoke_head = smoke_dir / "opera_ce_head.onnx"
    if HEAD_ONNX.is_file():
        smoke_head.write_bytes(HEAD_ONNX.read_bytes())
        HEAD_ONNX.unlink()
        meta = HEAD_ONNX.with_suffix(".json")
        if meta.is_file():
            (smoke_dir / "opera_ce_head.json").write_text(meta.read_text())
            meta.unlink()
    print(f"Smoke head kept at {smoke_head} (not installed into app assets)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_emb = sub.add_parser("embed", help="Write embeddings.npz from manifest")
    p_emb.add_argument("--manifest", type=Path, required=True)
    p_emb.add_argument("--out", type=Path, default=EMBED_CACHE)

    p_tr = sub.add_parser("train", help="Train logistic head + export ONNX")
    p_tr.add_argument("--manifest", type=Path, default=None)
    p_tr.add_argument("--embeddings", type=Path, default=EMBED_CACHE)
    p_tr.add_argument("--tflite", action="store_true")

    sub.add_parser("smoke", help="Synthetic non-clinical pipeline smoke test")

    args = parser.parse_args()
    if args.cmd == "embed":
        cmd_embed(args.manifest, args.out)
    elif args.cmd == "train":
        cmd_train(args.manifest, args.embeddings, args.tflite)
    elif args.cmd == "smoke":
        cmd_smoke()
    else:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
