"""Clinical and operational numbers, loaded from config/clinical_parameters.json.

That file is the only place these values are set. The CHO app gets the same values
through a generated Dart file, and docs/clinical-parameters-signoff.md is generated
for review. After changing it, run: python scripts/generate_clinical_params.py
A missing or unreadable file stops the server rather than falling back to guesses.
"""
from __future__ import annotations

import json
from pathlib import Path

PARAMETERS_PATH = Path(__file__).resolve().parents[1] / "config" / "clinical_parameters.json"

PARAMS: dict = json.loads(PARAMETERS_PATH.read_text(encoding="utf-8"))
