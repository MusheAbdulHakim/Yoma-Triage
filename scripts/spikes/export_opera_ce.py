"""OPERA-CE TFLite export spike helper.

Does not download weights by default (large). When OPERA_ROOT points at a
checked-out https://github.com/evelyn0414/OPERA tree with CE checkpoint,
runs a best-effort ONNX export smoke.

Usage:
  python scripts/spikes/export_opera_ce.py --check
  OPERA_ROOT=/path/to/OPERA python scripts/spikes/export_opera_ce.py --export
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "mobile" / "assets" / "models"
TARGET = OUT_DIR / "opera_ce.tflite"
SPIKE_DOC = ROOT / "docs" / "spikes" / "opera-ce-tflite.md"


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_pack() -> int:
    print(f"Expected pack: {TARGET}")
    if not TARGET.is_file():
        print("STATUS: missing — SCREENING_MODEL=opera_ce stays INCONCLUSIVE")
        print(f"See: {SPIKE_DOC}")
        return 1
    print(f"STATUS: present ({TARGET.stat().st_size} bytes)")
    print(f"sha256: {_sha256(TARGET)}")
    return 0


def export_onnx_stub(opera_root: Path) -> int:
    """Best-effort: import torch + OPERA CE and write ONNX next to assets.

    Full TFLite conversion remains manual (onnx2tf / TF converter) per spike doc.
    """
    if not opera_root.is_dir():
        print(f"OPERA_ROOT not found: {opera_root}", file=sys.stderr)
        return 2
    try:
        import torch  # type: ignore
    except ImportError:
        print("Install torch in the spike venv first.", file=sys.stderr)
        return 2

    # Placeholder path — real class names depend on OPERA repo layout.
    print(
        "Spike scaffold only: wire OPERA-CE forward() → torch.onnx.export here.\n"
        f"OPERA_ROOT={opera_root}\n"
        f"torch={torch.__version__}\n"
        "After ONNX succeeds, convert with onnx2tf and place opera_ce.tflite "
        f"at {TARGET}"
    )
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify TFLite pack")
    parser.add_argument("--export", action="store_true", help="Attempt ONNX export")
    parser.add_argument(
        "--opera-root",
        default="",
        help="Path to cloned OPERA repo (or set OPERA_ROOT)",
    )
    args = parser.parse_args()
    if args.check or not (args.check or args.export):
        code = check_pack()
        if not args.export:
            raise SystemExit(code)
    if args.export:
        import os

        root = Path(args.opera_root or os.environ.get("OPERA_ROOT", ""))
        raise SystemExit(export_onnx_stub(root))


if __name__ == "__main__":
    main()
