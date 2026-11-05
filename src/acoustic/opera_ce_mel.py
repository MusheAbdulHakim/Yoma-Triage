"""OPERA-CE mel frontend matching upstream `pre_process_audio_mel_t`.

Upstream call path uses f_max=8000 (not the util.py default of 2000).
Output is min-max normalized mel_db.T with shape (T, 64); encoder expects (B, T, F).
"""
from __future__ import annotations

import numpy as np

SAMPLE_RATE = 16_000
N_MELS = 64
F_MIN = 50.0
F_MAX = 8000.0
N_FFT = 1024
HOP = 512
# ~8 s @ 16 kHz with librosa center=True → 251 frames
TARGET_SAMPLES = 8 * SAMPLE_RATE
MEL_FRAMES = 251
MEL_BINS = N_MELS
EMBED_DIM = 1280


def pad_or_trim(audio: np.ndarray, length: int = TARGET_SAMPLES) -> np.ndarray:
    audio = np.asarray(audio, dtype=np.float32).reshape(-1)
    if audio.shape[0] >= length:
        return audio[:length].copy()
    out = np.zeros(length, dtype=np.float32)
    out[: audio.shape[0]] = audio
    return out


def pre_process_audio_mel_t(
    audio: np.ndarray,
    sample_rate: int = SAMPLE_RATE,
    n_mels: int = N_MELS,
    f_min: float = F_MIN,
    f_max: float = F_MAX,
    nfft: int = N_FFT,
    hop: int = HOP,
) -> np.ndarray:
    """Return float32 mel_db.T shaped (frames, n_mels), typically (251, 64)."""
    import librosa

    audio = np.asarray(audio, dtype=np.float32).reshape(-1)
    S = librosa.feature.melspectrogram(
        y=audio,
        sr=sample_rate,
        n_mels=n_mels,
        fmin=f_min,
        fmax=f_max,
        n_fft=nfft,
        hop_length=hop,
    )
    S = librosa.power_to_db(S, ref=np.max)
    if S.max() != S.min():
        mel_db = (S - S.min()) / (S.max() - S.min())
    else:
        mel_db = S
    return mel_db.T.astype(np.float32)


def mel_for_encoder(audio: np.ndarray) -> np.ndarray:
    """Pad/trim to 8 s and return (1, 251, 64) float32 batch for the ONNX/TFLite encoder."""
    mel = pre_process_audio_mel_t(pad_or_trim(audio))
    if mel.shape[0] > MEL_FRAMES:
        mel = mel[:MEL_FRAMES]
    elif mel.shape[0] < MEL_FRAMES:
        pad = np.zeros((MEL_FRAMES - mel.shape[0], MEL_BINS), dtype=np.float32)
        mel = np.concatenate([mel, pad], axis=0)
    return mel[np.newaxis, ...]
