# Lab-set collection SOP (advisory acoustic labels)

## Purpose

Collect ≥100 short phone recordings to train / gate an OPERA-CE **advisory**
head. Labels are engineering buckets, not diagnoses.

## Consent & ethics

1. Use only the IRB/ethics-approved protocol for this project.
2. Prefer de-identified volunteers or public datasets with compatible licenses.
3. Do not place identifiable patient audio in git, CI caches, or chat logs.
4. Record retention: follow the protocol; delete on request.

## Capture (CHO phone SOP)

| Setting | Value |
|---------|--------|
| Sample rate | 16 kHz mono PCM WAV |
| Duration | 8–15 s (pipeline pads/trims to 8 s for OPERA-CE) |
| Mic | Phone bottom mic, ~10–20 cm from chest/mouth per protocol |
| Environment | Note bucket: quiet / outdoor / speech / cry |

## Manifest

Copy `manifest.example.csv` → `manifest.csv` (keep local):

```csv
path,label
clips/quiet_001.wav,normal
clips/cough_001.wav,abnormal
```

`label` ∈ {`normal`, `abnormal`}.

## Buckets (minimum)

- ≥25 normal / quiet breath
- ≥25 abnormal / cough-like
- ≥25 noise / outdoor
- ≥25 cry / speech confounders

## Gating

Do not install `opera_ce_head.tflite` into `mobile/assets/models/` until:

1. n ≥ 100 labeled clips
2. Held-out accuracy / calibration reviewed
3. Fail-closed mid-band behavior re-checked on device
4. PRODUCT_SPEC / model card updated with limitations
