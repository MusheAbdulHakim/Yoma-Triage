# Final Review Fix Report

## Fixes

- Updated SMS risk-code decoding to the coordinator contract: `0/1/2/3` now decode to `GREEN/YELLOW/RED/UNKNOWN`.
- Restricted dispatch acceptance to drivers in the current tier's eligible candidate set, preventing tier-two drivers from claiming a tier-one dispatch.
- Seeded the initial protocol corpus when the clinical RAG engine is lazily initialized, preserving idempotency through the existing empty-store check.
- Made USSD background tasks required and aligned the demo startup hint with the README.

## Tests

- `./venv/bin/python -m pytest -q`
- Result: `28 passed in 20.27s`
