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
ENCODER_TFLITE_PATH = OUT_DIR / "opera_ce_encoder.tflite"
# Classifier pack (mel + head) — not produced by this encoder-only spike.
CLASSIFIER_TFLITE_PATH = OUT_DIR / "opera_ce.tflite"
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
    print(f"Expected ONNX encoder:               {ONNX_PATH}")
    print(f"Expected TFLite encoder:             {ENCODER_TFLITE_PATH}")
    print(f"Expected TFLite classifier (app):    {CLASSIFIER_TFLITE_PATH}")
    if ONNX_PATH.is_file():
        print(f"ONNX: present ({ONNX_PATH.stat().st_size} bytes) sha256={_sha256(ONNX_PATH)}")
    else:
        print("ONNX: missing")
        return 1
    if ENCODER_TFLITE_PATH.is_file():
        print(
            f"Encoder TFLite: present ({ENCODER_TFLITE_PATH.stat().st_size} bytes) "
            f"sha256={_sha256(ENCODER_TFLITE_PATH)}"
        )
    else:
        print("Encoder TFLite: missing — run --tflite after onnx2tf is installed")
    if CLASSIFIER_TFLITE_PATH.is_file():
        print(
            f"Classifier TFLite: present ({CLASSIFIER_TFLITE_PATH.stat().st_size} bytes) "
            f"sha256={_sha256(CLASSIFIER_TFLITE_PATH)}"
        )
    else:
        print(
            "Classifier pack opera_ce.tflite: missing — Flutter SCREENING_MODEL=opera_ce "
            "stays INCONCLUSIVE (encoder alone is not enough)."
        )
        print(f"See: {SPIKE_DOC}")
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
    """Best-effort ONNX → encoder TFLite via onnx2tf (float16 preferred)."""
    import shutil
    import subprocess

    tmp_dir = Path("/tmp/opera_ce_tf")
    if tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    cmd = ["onnx2tf", "-i", str(onnx_path), "-o", str(tmp_dir)]
    print("Running:", " ".join(cmd))
    try:
        subprocess.check_call(cmd)
    except FileNotFoundError:
        print("onnx2tf not on PATH — pip install onnx2tf in the spike venv.")
        return None
    except subprocess.CalledProcessError as exc:
        print(f"onnx2tf failed: {exc}")
        return None

    # Prefer smaller float16 encoder pack for phones.
    candidates = sorted(tmp_dir.rglob("*float16*.tflite")) + sorted(
        tmp_dir.rglob("*.tflite")
    )
    if not candidates:
        print("onnx2tf produced no .tflite files")
        return None
    src = candidates[0]
    ENCODER_TFLITE_PATH.write_bytes(src.read_bytes())
    print(
        f"Wrote {ENCODER_TFLITE_PATH} from {src.name} "
        f"({ENCODER_TFLITE_PATH.stat().st_size} bytes)"
    )
    print(f"sha256: {_sha256(ENCODER_TFLITE_PATH)}")
    print(
        "Note: this is the encoder pack only. App classifier remains "
        f"{CLASSIFIER_TFLITE_PATH.name} (not written)."
    )
    return ENCODER_TFLITE_PATH


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
