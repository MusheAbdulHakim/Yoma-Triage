"""OPERA-CE encoder export spike (ONNX → optional TFLite).

OPERA-CE is an **EfficientNet-B0 embedding encoder** (MIT), not a cough/breath
classifier. This script:

1. Downloads `encoder-operaCE.ckpt` from Hugging Face if missing
2. Exports the CNN encoder to ONNX (mel spectrogram → 1280-d embedding)
3. Optionally converts ONNX → TFLite when `tensorflow` is installed

Flutter `SCREENING_MODEL=opera_ce` stays INCONCLUSIVE until a **classification
head** + on-device mel frontend ship on top of this encoder.

Usage:
  python scripts/spikes/export_opera_ce.py --check
  OPERA_ROOT=/tmp/OPERA-spike python scripts/spikes/export_opera_ce.py --export
  OPERA_ROOT=/tmp/OPERA-spike python scripts/spikes/export_opera_ce.py --export --tflite
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "mobile" / "assets" / "models"
ONNX_PATH = OUT_DIR / "opera_ce_encoder.onnx"
TFLITE_PATH = OUT_DIR / "opera_ce.tflite"
SPIKE_DOC = ROOT / "docs" / "spikes" / "opera-ce-tflite.md"

# Mel shape matching OPERA util.pre_process_audio_mel_t for ~8 s @ 16 kHz
# (hop=512 → ~251 frames, n_mels=64). Encoder expects (B, T, F).
MEL_FRAMES = 251
MEL_BINS = 64
EMBED_DIM = 1280


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_pack() -> int:
    print(f"Expected TFLite (classifier pack): {TFLITE_PATH}")
    print(f"Expected ONNX encoder:             {ONNX_PATH}")
    if ONNX_PATH.is_file():
        print(f"ONNX: present ({ONNX_PATH.stat().st_size} bytes) sha256={_sha256(ONNX_PATH)}")
    else:
        print("ONNX: missing")
        return 1
    if TFLITE_PATH.is_file():
        print(
            f"TFLite: present ({TFLITE_PATH.stat().st_size} bytes) "
            f"sha256={_sha256(TFLITE_PATH)}"
        )
    else:
        print(
            "TFLite classifier pack: missing — Flutter SCREENING_MODEL=opera_ce "
            "stays INCONCLUSIVE (encoder ONNX alone is not enough)."
        )
        print(f"See: {SPIKE_DOC}")
    # Encoder milestone OK even without TFLite classifier pack.
    return 0


def _resolve_opera_root(explicit: str) -> Path:
    raw = explicit or os.environ.get("OPERA_ROOT", "")
    if raw:
        return Path(raw)
    # Common local spike checkout
    for candidate in (Path("/tmp/OPERA-spike"), ROOT / ".cache" / "OPERA"):
        if candidate.is_dir():
            return candidate
    return Path("/tmp/OPERA-spike")


def _ensure_ckpt(opera_root: Path) -> Path:
    ckpt = opera_root / "cks" / "model" / "encoder-operaCE.ckpt"
    # HF hub may nest as cks/model/cks/model/... depending on version
    alt = opera_root / "cks" / "model" / "cks" / "model" / "encoder-operaCE.ckpt"
    if ckpt.is_file():
        return ckpt
    if alt.is_file():
        return alt
    ckpt.parent.mkdir(parents=True, exist_ok=True)
    try:
        from huggingface_hub import hf_hub_download
    except ImportError as exc:
        raise SystemExit(
            "Install huggingface_hub (and torch) in the spike venv first."
        ) from exc
    path = hf_hub_download(
        "evelyn0414/OPERA",
        "encoder-operaCE.ckpt",
        local_dir=str(ckpt.parent),
    )
    return Path(path)


def _build_encoder():
    import torch
    from efficientnet_pytorch import EfficientNet

    class Encoder(torch.nn.Module):
        def __init__(self, drop_connect_rate: float = 0.1) -> None:
            super().__init__()
            self.cnn1 = torch.nn.Conv2d(1, 3, kernel_size=3)
            self.efficientnet = EfficientNet.from_name(
                "efficientnet-b0",
                include_top=False,
                drop_connect_rate=drop_connect_rate,
            )

        def forward(self, x):  # (B, T, F)
            x = x.unsqueeze(1)
            x = self.cnn1(x)
            x = self.efficientnet(x)
            return x.squeeze(3).squeeze(2)

    return Encoder()


def export_onnx(opera_root: Path) -> Path:
    import torch

    ckpt_path = _ensure_ckpt(opera_root)
    print(f"Loading checkpoint: {ckpt_path}")
    blob = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    state = blob["state_dict"] if isinstance(blob, dict) and "state_dict" in blob else blob

    model = _build_encoder()
    enc_state = {
        k.replace("encoder.", "", 1): v
        for k, v in state.items()
        if k.startswith("encoder.")
    }
    missing, unexpected = model.load_state_dict(enc_state, strict=False)
    print(f"load_state_dict missing={len(missing)} unexpected={len(unexpected)}")
    model.eval()

    dummy = torch.zeros(1, MEL_FRAMES, MEL_BINS, dtype=torch.float32)
    with torch.no_grad():
        out = model(dummy)
    assert out.shape == (1, EMBED_DIM), out.shape

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model,
        dummy,
        str(ONNX_PATH),
        input_names=["mel"],
        output_names=["embedding"],
        dynamic_axes={"mel": {0: "batch"}, "embedding": {0: "batch"}},
        opset_version=18,
    )
    # Collapse external weight sidecars into one portable file.
    try:
        import onnx

        loaded = onnx.load(str(ONNX_PATH), load_external_data=True)
        onnx.save_model(loaded, str(ONNX_PATH), save_as_external_data=False)
        sidecar = ONNX_PATH.with_suffix(ONNX_PATH.suffix + ".data")
        if sidecar.is_file():
            sidecar.unlink()
    except Exception as exc:  # noqa: BLE001
        print(f"warning: could not inline ONNX external data: {exc}")

    print(f"Wrote {ONNX_PATH} ({ONNX_PATH.stat().st_size} bytes)")
    print(f"sha256: {_sha256(ONNX_PATH)}")
    print(
        "Input: mel float32 [B, 251, 64] (OPERA mel_db.T @ 16 kHz, n_mels=64, hop=512). "
        "Output: embedding float32 [B, 1280]."
    )
    return ONNX_PATH


def convert_tflite(onnx_path: Path) -> Path | None:
    """Best-effort ONNX → TFLite. Returns path or None if converter unavailable."""
    try:
        import tensorflow as tf  # type: ignore
    except ImportError:
        print(
            "tensorflow not installed — skip TFLite. "
            "Install tensorflow or onnx2tf in the spike venv, then re-run --tflite."
        )
        return None

    try:
        import onnx  # type: ignore
        from onnx_tf.backend import prepare  # type: ignore
    except ImportError:
        # Prefer onnx2tf if available
        try:
            import subprocess

            tmp_dir = Path("/tmp/opera_ce_tf")
            tmp_dir.mkdir(parents=True, exist_ok=True)
            cmd = [
                sys.executable,
                "-m",
                "onnx2tf",
                "-i",
                str(onnx_path),
                "-o",
                str(tmp_dir),
            ]
            print("Running:", " ".join(cmd))
            subprocess.check_call(cmd)
            saved = next(tmp_dir.rglob("*.tflite"), None)
            if saved is None:
                # Convert saved_model
                sm = next(tmp_dir.glob("saved_model*"), tmp_dir)
                converter = tf.lite.TFLiteConverter.from_saved_model(str(sm))
                converter.target_spec.supported_ops = [
                    tf.lite.OpsSet.TFLITE_BUILTINS,
                    tf.lite.OpsSet.SELECT_TF_OPS,
                ]
                data = converter.convert()
                TFLITE_PATH.write_bytes(data)
                print(f"Wrote {TFLITE_PATH} ({TFLITE_PATH.stat().st_size} bytes)")
                return TFLITE_PATH
            TFLITE_PATH.write_bytes(saved.read_bytes())
            print(f"Wrote {TFLITE_PATH} from {saved}")
            return TFLITE_PATH
        except Exception as exc:  # noqa: BLE001
            print(f"onnx2tf path failed: {exc}")
            print(
                "Manual next step: onnx2tf -i "
                f"{onnx_path} -o /tmp/opera_ce_tf && copy *.tflite to {TFLITE_PATH}"
            )
            return None

    model = onnx.load(str(onnx_path))
    tf_rep = prepare(model)
    sm_dir = Path("/tmp/opera_ce_saved_model")
    if sm_dir.exists():
        import shutil

        shutil.rmtree(sm_dir)
    tf_rep.export_graph(str(sm_dir))
    converter = tf.lite.TFLiteConverter.from_saved_model(str(sm_dir))
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    data = converter.convert()
    TFLITE_PATH.write_bytes(data)
    print(f"Wrote {TFLITE_PATH} ({TFLITE_PATH.stat().st_size} bytes)")
    print(f"sha256: {_sha256(TFLITE_PATH)}")
    return TFLITE_PATH


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify exported packs")
    parser.add_argument("--export", action="store_true", help="Export ONNX encoder")
    parser.add_argument(
        "--tflite",
        action="store_true",
        help="Also attempt ONNX→TFLite after export (or if ONNX already exists)",
    )
    parser.add_argument("--opera-root", default="", help="Cloned OPERA repo path")
    args = parser.parse_args()

    if not (args.check or args.export or args.tflite):
        raise SystemExit(check_pack())

    if args.check and not (args.export or args.tflite):
        raise SystemExit(check_pack())

    opera_root = _resolve_opera_root(args.opera_root)

    if args.export:
        if not opera_root.is_dir():
            print(
                f"OPERA_ROOT missing ({opera_root}). Clone:\n"
                "  git clone --depth 1 https://github.com/evelyn0414/OPERA.git /tmp/OPERA-spike",
                file=sys.stderr,
            )
            raise SystemExit(2)
        export_onnx(opera_root)

    if args.tflite:
        if not ONNX_PATH.is_file():
            print(f"Need {ONNX_PATH} first — run with --export", file=sys.stderr)
            raise SystemExit(2)
        convert_tflite(ONNX_PATH)

    raise SystemExit(check_pack())


if __name__ == "__main__":
    main()
