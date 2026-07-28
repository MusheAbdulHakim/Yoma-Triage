# Checksums for screening model assets

| File | sha256 | Notes |
|------|--------|-------|
| `yamnet.tflite` | `4d8b4a53282dc83ef04e3e7dbc4fbc98082e34e44ed798e16c3a0cdd4c584faf` | Default AudioSet AED |
| `opera_ce_encoder.onnx` | `c22c613a8bac171c35437510dcada0ef2cf43335675ed9ce6e4a89900e1c29b3` | Encoder only (mel → 1280-d) |
| `opera_ce_encoder.tflite` | `325326490a625aabc5c8e8b287240ca09d89e237b38f1e7af5a32ab26898fab5` | Encoder float16 TFLite via onnx2tf |
| `opera_ce.tflite` | — | Classifier pack — **not shipped** |

Regenerate encoder:

```bash
OPERA_ROOT=/tmp/OPERA-spike python scripts/spikes/export_opera_ce.py --export --tflite
python scripts/spikes/export_opera_ce.py --check
```
