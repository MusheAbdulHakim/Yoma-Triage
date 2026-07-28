# OPERA-CE encoder model card (spike)

| Field | Value |
|-------|--------|
| **Artifacts** | `opera_ce_encoder.onnx` (~16 MB), `opera_ce_encoder.tflite` (~8 MB float16) |
| **Upstream** | [OPERA-CE](https://huggingface.co/evelyn0414/OPERA) `encoder-operaCE.ckpt` (MIT) |
| **Architecture** | EfficientNet-B0 backbone + 1→3 Conv stem (Cola encoder) |
| **Role** | **Embedding encoder only** (1280-d) — not a cough/breath event classifier |
| **Input** | Mel spectrogram float32 `[B, 251, 64]` = OPERA `pre_process_audio_mel_t(...).T` for ~8 s @ 16 kHz (`n_mels=64`, `n_fft=1024`, `hop=512`, `fmin=50`, `fmax=8000` in upstream call path) |
| **Output** | float32 `[B, 1280]` embedding |
| **On-device status** | Encoder ONNX + float16 TFLite shipped. **Classifier pack `opera_ce.tflite` not shipped** — Flutter `SCREENING_MODEL=opera_ce` remains INCONCLUSIVE |
| **Next** | (1) Train/distill a small advisory head on ethics-approved labels (2) Port mel frontend or bake into TFLite (3) Ship `opera_ce.tflite` as the app pack |
| **Telemetry** | Scores-only when a head exists; never upload embeddings on the referral path |
| **Human oversight** | MOEWS floor + CHO confirm; acoustic GREEN never downgrades MOEWS |

## Reproduce export

```bash
git clone --depth 1 https://github.com/evelyn0414/OPERA.git /tmp/OPERA-spike
python3 -m venv /tmp/opera-ce-venv && source /tmp/opera-ce-venv/bin/activate
pip install torch --index-url https://download.pytorch.org/whl/cpu
pip install efficientnet_pytorch onnx onnxscript huggingface_hub onnxruntime
OPERA_ROOT=/tmp/OPERA-spike python scripts/spikes/export_opera_ce.py --export
python scripts/spikes/export_opera_ce.py --check
```
