# YAMNet model card — Yoma Triage CHO app (v0)

| Field | Value |
|-------|--------|
| **Model** | MediaPipe / AudioSet YAMNet TFLite |
| **Asset** | `mobile/assets/models/yamnet.tflite` (~4.1 MB) |
| **License** | Apache-2.0 (upstream) |
| **Intended use** | On-device advisory detection of generic AudioSet breath/cough-like events for CHO triage UX |
| **Out of scope** | Obstetric diagnosis; pneumonia/bronchiolitis claims; population screening without study |
| **Input** | ~0.975 s windows @ 16 kHz mono PCM |
| **“Abnormal” mapping** | Max score over AudioSet indices `{36,37,39,40,41,42}` (Breathing, Wheeze, Gasp, Pant, Snort, Cough) |
| **Thresholds (app)** | `>0.7` → RED; `<0.5` → INCONCLUSIVE; else GREEN |
| **Human oversight** | CHO confirmation required; MOEWS is clinical spine; acoustic GREEN never downgrades MOEWS RED/YELLOW |
| **Failure mode** | Load/infer failure → INCONCLUSIVE / stub; never silent GREEN |
| **Kill switch** | `--dart-define=MOEWS_ONLY=true` skips acoustic path |
| **Telemetry** | Scores-only: label, confidence, `model_version` (`yamnet-audioset-v0`) — no audio/embeddings |
| **Validation** | Not Ghana-validated; lab/demo only until ethics + clinical protocol |
| **Contact** | Yoma Triage engineering / clinical lead |

## Upgrade path

- Prefer HeAR **MobileNet event detector** if HAI-DEF ToS allows redistribution.
- Else **OPERA-CE** (MIT) after TFLite export spike.
- Never run HeAR ViT-L foundation on CHO phones.
