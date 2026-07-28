# HAI-DEF / HeAR terms-of-use review checklist (AI1a)

**Status:** Ready for legal review — engineering must not redistribute HeAR weights until cleared.  
**OTP auth:** deferred (explicit product decision).

## Scope under review

| Artifact | Role | On-device? |
|----------|------|-----------|
| HeAR **foundation** (ViT-L → 512-d embeddings) | Server / Vertex training accelerator | **No** |
| HeAR **health event detectors** (MobileNet-V3 Small/Large) | Phone-mic advisory gate vs YAMNet | **Yes, if ToS allows** |

Upstream: [HeAR model card](https://developers.google.com/health-ai-developer-foundations/hear/model-card), [event detector notebook](https://github.com/Google-Health/hear/blob/master/notebooks/hear_event_detector_demo.ipynb), Health AI Developer Foundations terms of use.

## Questions for counsel

1. May we **redistribute** MobileNet event-detector weights inside a Ghana CHO APK for a non-commercial / public-health pilot?
2. May we convert detectors to **LiteRT/TFLite** and ship binary assets under HAI-DEF ToS?
3. Are there **territorial**, **attribution**, or **prohibited use** (clinical decision support) constraints for CHPS maternity triage?
4. May we use HeAR **foundation** embeddings on our servers to train/distill a compact head, then ship only the distilled TFLite (no ViT-L on phone)?
5. What logging / telemetry of scores is allowed under ToS + Ghana DPA (we use scores-only)?

## Engineering fallback (already planned)

If ToS is slow or blocks redistribution → **OPERA-CE (MIT)** export spike (`SCREENING_MODEL=opera_ce`). Keep YAMNet Apache-2.0 as default until either clears.

## Decision log

| Date | Decision | Owner |
|------|----------|-------|
| | | |

## Do not ship

- HeAR foundation ViT-L on CHO phones  
- Removal of advisory disclaimers  
- Clinical claims based on HeAR without Ghana validation study  
