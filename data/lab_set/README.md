# Acoustic lab set

Hold **≥100** ethics-approved labeled clips before treating an OPERA-CE head as
anything other than an engineering prototype. Default production acoustic model
remains YAMNet until that bar is met and reviewed.

| Bucket | Target | Notes |
|--------|--------|-------|
| Normal / quiet breath | ≥25 | Quiet room, phone SOP |
| Abnormal / cough-like | ≥25 | Advisory labels only — not ICD codes |
| Noise / outdoor | ≥25 | Wind, motorcycle, chatter |
| Cry / speech confounders | ≥25 | Must not silent-GREEN |

## Layout

```
data/lab_set/
  README.md              ← this file
  manifest.example.csv   ← copy to manifest.csv (gitignored if it points at PHI)
  COLLECTION_SOP.md      ← capture + consent checklist
  clips/                 ← local only; do not commit identifiable audio
  synthetic_smoke/       ← CI tones only (safe to commit)
```

## Train head (after ≥100 real clips)

```bash
# venv with: librosa onnxruntime scikit-learn onnx soundfile
python scripts/train_opera_ce_head.py embed --manifest data/lab_set/manifest.csv
python scripts/train_opera_ce_head.py train --manifest data/lab_set/manifest.csv --tflite
# Review metrics → copy opera_ce_head.tflite into mobile/assets/models/ only after sign-off
```

## Rules

- Do **not** commit identifiable patient audio.
- Store clips offline under the ethics protocol; referral path keeps scores + `model_version` only.
- Synthetic smoke clips prove the pipeline; a head trained only on them must **not** ship in the app pack.
- Flutter `SCREENING_MODEL=opera_ce` stays **INCONCLUSIVE** until `opera_ce_head.tflite` is present (encoder-only is fail-closed).
