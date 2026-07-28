# OPERA-CE on-device spike (AI1b)

MIT-licensed respiratory foundation (EfficientNet-B0 ≈ 4M params). Best open fallback if HeAR HAI-DEF ToS blocks redistribution.

## Goal

Produce a TFLite/LiteRT asset loadable by Flutter (`tflite_flutter`) for advisory cough/breath-event scoring, feature-flagged as `SCREENING_MODEL=opera_ce`.

## Upstream

- Paper: [arXiv:2406.16148](https://arxiv.org/abs/2406.16148)
- Code: [evelyn0414/OPERA](https://github.com/evelyn0414/OPERA)
- Family: OPERA-CT (~31M), **OPERA-CE (~4M)**, OPERA-GT (~21M encoder)

## Spike steps (engineering)

1. Clone OPERA; load OPERA-CE checkpoint in PyTorch.
2. Export ONNX (`torch.onnx.export`) with fixed 16 kHz mono audio window matching app capture.
3. Convert ONNX → TFLite (`onnx2tf` or TF converter); verify ops supported by TFLite built-ins / Flex.
4. Bundle under `mobile/assets/models/opera_ce.tflite` (git-lfs if large).
5. Wire `createOperaCeClassifier()`; dual-run vs YAMNet when `SCREENING_DUAL_RUN=true`.
6. Model card + checksum; feature flag default remains `yamnet` until lab set ≥100 clips.

### Helper in this repo

```bash
python scripts/spikes/export_opera_ce.py --check
OPERA_ROOT=/path/to/OPERA python scripts/spikes/export_opera_ce.py --export
```

`--check` verifies whether `mobile/assets/models/opera_ce.tflite` is present and prints sha256. `--export` is a scaffold that confirms torch + OPERA_ROOT; finish the real `torch.onnx.export` against OPERA’s CE forward pass in that tree.

## Current app behavior

Until the TFLite pack is present, `SCREENING_MODEL=opera_ce` returns **INCONCLUSIVE** with reason `opera_ce model pack not installed` (never silent GREEN). Same for `hear_event` pending ToS + asset.

## Non-goals

- Shipping OPERA-CT/GT on mid-range CHO phones in v1
- Disease-class labels as CHO diagnosis
- Waiting on CHO OTP (deferred) before this spike
