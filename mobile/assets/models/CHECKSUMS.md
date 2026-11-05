# Model pack checksums

| File | sha256 | Notes |
|------|--------|-------|
| `yamnet.tflite` | (see release notes) | AudioSet YAMNet |
| `opera_ce_encoder.onnx` | `c22c613a8bac171c35437510dcada0ef2cf43335675ed9ce6e4a89900e1c29b3` | Encoder only (mel → 1280-d) |
| `opera_ce_encoder.tflite` | `325326490a625aabc5c8e8b287240ca09d89e237b38f1e7af5a32ab26898fab5` | Encoder float16 TFLite via onnx2tf |
| `opera_ce_head.tflite` | — | Advisory head — **not shipped** until ≥100 lab clips + review |
| `opera_ce.tflite` | — | Optional combined pack — not required (app uses encoder + optional head) |

Reproduce encoder:

```bash
OPERA_ROOT=/tmp/OPERA-spike python scripts/spikes/export_opera_ce.py --export --tflite
python scripts/spikes/export_opera_ce.py --check
```

Train head (after lab set):

```bash
python scripts/train_opera_ce_head.py train --manifest data/lab_set/manifest.csv --tflite
```
