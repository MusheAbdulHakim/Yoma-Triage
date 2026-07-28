# Acoustic lab set (placeholder)

Hold ≥100 labeled clips before swapping the production acoustic default off YAMNet:

| Bucket | Target | Notes |
|--------|--------|-------|
| Normal / quiet breath | ≥25 | Quiet room, phone SOP |
| Abnormal / cough-like | ≥25 | Still advisory labels only |
| Noise / outdoor | ≥25 | Wind, motorcycle, chatter |
| Cry / speech confounders | ≥25 | Must not silent-GREEN |

Do **not** commit identifiable patient audio. Store offline under ethics protocol; keep only scores + `model_version` on the referral path.

OPERA-CE next step: train a tiny head on these labels atop `opera_ce_encoder.onnx` embeddings, then export `opera_ce.tflite`.
