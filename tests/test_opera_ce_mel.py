"""OPERA-CE mel frontend shape/range checks."""
from __future__ import annotations

import pytest

pytest.importorskip("librosa")

import numpy as np

from src.acoustic.opera_ce_mel import MEL_BINS, MEL_FRAMES, TARGET_SAMPLES, mel_for_encoder


def test_mel_for_encoder_shape_and_range():
    rng = np.random.default_rng(0)
    audio = (rng.standard_normal(TARGET_SAMPLES) * 0.1).astype(np.float32)
    mel = mel_for_encoder(audio)
    assert mel.shape == (1, MEL_FRAMES, MEL_BINS)
    assert float(mel.min()) >= 0.0
    assert float(mel.max()) <= 1.0 + 1e-5
