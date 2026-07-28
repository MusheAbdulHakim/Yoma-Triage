# OPERA-CE on-device spike (AI1b)

MIT-licensed respiratory foundation (EfficientNet-B0 ≈ 4M params). Best open fallback if HeAR HAI-DEF ToS blocks redistribution.

## Goal

1. Export OPERA-CE **encoder** to ONNX (done in-repo as spike artifact).
2. Convert to TFLite/LiteRT + mel frontend + **classification head** for Flutter (`SCREENING_MODEL=opera_ce`).

## Upstream

- Paper: [arXiv:2406.16148](https://arxiv.org/abs/2406.16148)
- Code: [evelyn0414/OPERA](https://github.com/evelyn0414/OPERA)
- Weights: [encoder-operaCE.ckpt](https://huggingface.co/evelyn0414/OPERA/resolve/main/encoder-operaCE.ckpt) (~57 MB)

## Spike results (2026-07-28)

| Step | Status |
|------|--------|
| Clone OPERA + download CE ckpt | Done (local `/tmp` spike env) |
| Export EfficientNet encoder → ONNX | **Done** — `mobile/assets/models/opera_ce_encoder.onnx` (~16 MB single-file) |
| Numerical check vs PyTorch | **Pass** (max abs diff ~1e-4 on random mel) |
| ONNX → TFLite | **Blocked** in this environment (heavy `onnx2tf`/TF install); re-run `--tflite` when tensorflow/onnx2tf available |
| Classification head | **Not started** — encoder alone cannot emit GREEN/RED |
| Flutter pack `opera_ce.tflite` | Missing → app returns INCONCLUSIVE (never silent GREEN) |

Model card: [`docs/model-cards/opera-ce-encoder-v0.md`](../model-cards/opera-ce-encoder-v0.md)

### Helper

```bash
python scripts/spikes/export_opera_ce.py --check
OPERA_ROOT=/tmp/OPERA-spike python scripts/spikes/export_opera_ce.py --export
OPERA_ROOT=/tmp/OPERA-spike python scripts/spikes/export_opera_ce.py --export --tflite
```

## Current app behavior

`SCREENING_MODEL=opera_ce` → INCONCLUSIVE until `mobile/assets/models/opera_ce.tflite` exists (classifier pack). The ONNX encoder is an intermediate artifact for head training / TFLite conversion — not loaded by Flutter yet.

## Non-goals

- Shipping OPERA-CT/GT on mid-range CHO phones in v1
- Disease-class labels as CHO diagnosis
- Waiting on CHO OTP (deferred) before this spike
- Treating encoder embeddings as a clinical score
