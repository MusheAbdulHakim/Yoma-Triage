"""Compute and cache per-recording features for ONE model, one dataset, one condition.

  .venv/bin/python scripts/embed.py --model yamnet_float --dataset sprsound --cond clean

Models
  yamnet_app    the app's file (official int8 classification variant): 15,600-sample windows,
                half-overlapping, max score over windows (as yamnet_classifier_io.dart does)
  yamnet_float  official float variant with embeddings: whole clip (input resized), frame
                embeddings mean-pooled (1024) and scores max-pooled (521)
  opera         official OPERA-CE: librosa 16 kHz load, trim, repeat-pad to 8 s, mel, whole clip
                -> 1280. On clean audio also the two fixed-length rules for long clips:
                emb_win (mean of 8 s windows) and emb_first8 (first 8 s after trimming)

Resumable: features are written in shards of 200 recordings under
cache/emb/<dataset>/<model>/<cond>/ and finished shards are skipped. merge -> features.npz.
"""
from __future__ import annotations

import argparse
import gc
import os
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import CACHE, HERE, NATIVE_SR, SR, degrade, load16k, manifest  # noqa: E402

SHARD = 200
YAMNET_FLOAT = CACHE / "yamnet" / "yamnet_tflite_1.tflite"
YAMNET_APP = HERE.parents[1] / "mobile" / "assets" / "models" / "yamnet.tflite"
APP_RESP = [36, 37, 39, 40, 41, 42]
MAX_HEAR_WINDOWS = 4   # yamnetRespiratoryClassIndices in the app


class YamnetApp:
    def __init__(self):
        from ai_edge_litert.interpreter import Interpreter
        self.it = Interpreter(model_path=str(YAMNET_APP))
        self.it.allocate_tensors()
        self.i = self.it.get_input_details()[0]["index"]
        self.o = self.it.get_output_details()[0]["index"]

    def __call__(self, y):
        n = 15600
        wins = [y[o:o + n] for o in range(0, max(len(y) - n, 0) + 1, n // 2)] if len(y) >= n \
            else [np.pad(y, (0, n - len(y)))]
        s = []
        for w in wins:
            self.it.set_tensor(self.i, w.astype(np.float32))
            self.it.invoke()
            s.append(self.it.get_tensor(self.o)[0].copy())
        s = np.max(np.stack(s), 0)
        return {"scores_max": s, "app_resp": np.array([s[APP_RESP].max()], np.float32)}


class YamnetFloat:
    def __init__(self):
        from ai_edge_litert.interpreter import Interpreter
        self.it = Interpreter(model_path=str(YAMNET_FLOAT))
        d = self.it.get_input_details()[0]
        self.i = d["index"]
        self.outs = {o["shape_signature"][-1]: o["index"] for o in self.it.get_output_details()}
        self.cur = None

    def __call__(self, y):
        if len(y) < 15600:
            y = np.pad(y, (0, 15600 - len(y)))
        if self.cur != len(y):
            self.it.resize_tensor_input(self.i, [len(y)])
            self.it.allocate_tensors()
            self.cur = len(y)
        self.it.set_tensor(self.i, y.astype(np.float32))
        self.it.invoke()
        e = self.it.get_tensor(self.outs[1024])
        s = self.it.get_tensor(self.outs[521])
        return {"emb_mean": e.mean(0), "scores_max": s.max(0),
                "app_resp": np.array([s.max(0)[APP_RESP].max()], np.float32)}


class Opera:
    def __init__(self, rules):
        import torch
        torch.set_num_threads(int(os.environ.get("TORCH_THREADS", "4")))
        sys.path.insert(0, str(CACHE / "OPERA"))
        from src.util import get_entire_signal_librosa  # official pad + mel
        from efficientnet_pytorch import EfficientNet

        class Encoder(torch.nn.Module):  # verbatim OPERA src/model/models_cola.py
            def __init__(self):
                super().__init__()
                self.cnn1 = torch.nn.Conv2d(1, 3, kernel_size=3)
                self.efficientnet = EfficientNet.from_name("efficientnet-b0", include_top=False,
                                                           drop_connect_rate=0.1)

            def forward(self, x):
                x = self.cnn1(x.unsqueeze(1))
                return self.efficientnet(x).squeeze(3).squeeze(2)

        sd = torch.load(CACHE / "opera_ckpt" / "encoder-operaCE.ckpt", map_location="cpu", weights_only=False)["state_dict"]
        self.enc = Encoder()
        self.enc.load_state_dict({k[8:]: v for k, v in sd.items() if k.startswith("encoder.")},
                                 strict=True)
        self.enc.eval()
        del sd
        self.torch = torch
        self.mel = lambda yt: get_entire_signal_librosa("", "", spectrogram=True, input_sec=8,
                                                        pad=True, from_cycle=True, yt=yt)
        self.rules = rules

    def _emb(self, m):
        with self.torch.no_grad():
            return self.enc(self.torch.tensor(m[None], dtype=self.torch.float32)).numpy()[0]

    def __call__(self, y):
        import librosa
        yt, _ = librosa.effects.trim(y, frame_length=1600, hop_length=800)  # as the official loader
        if yt.size < 1600:
            yt = y
        m = self.mel(yt)
        out = {"emb": self._emb(m), "n_frames": np.array([m.shape[0]], np.float32)}
        if self.rules:
            n = 8 * SR
            chunks = [yt[o:o + n] for o in range(0, len(yt), n)]
            if len(chunks) > 1 and len(chunks[-1]) < 2 * SR:
                chunks = chunks[:-1]          # drop a final remainder shorter than 2 s
            out["emb_win"] = np.mean([self._emb(self.mel(c)) for c in chunks], 0)
            out["emb_first8"] = self._emb(self.mel(yt[:n]))
        return out


class Hear:
    """Google HeAR (PyTorch port, HF google/hear-pytorch, HAI-DEF terms). Official usage from
    the model card / quick-start notebook: preprocess_audio (google-health/hear, Apache 2.0) on
    2 s 16 kHz clips -> ViT-L -> pooler_output (512). Per recording: non-overlapping 2 s windows
    (a final remainder under 0.5 s is dropped unless it is the only window; shorter windows are
    zero-padded), at most MAX_HEAR_WINDOWS of them evenly spaced, embeddings averaged.
    ViT-L runs at ~1.2 s per window on this CPU (8 threads), so whole clips (~70k windows) were
    out of reach; 4 windows = 8 s, the same audio length as the app's OPERA-CE input."""

    def __init__(self):
        import torch
        from transformers import AutoModel
        torch.set_num_threads(int(os.environ.get("TORCH_THREADS", "4")))
        sys.path.insert(0, str(CACHE / "hear" / "repo"))
        from python.data_processing.audio_utils import preprocess_audio
        self.pre = preprocess_audio
        self.torch = torch
        self.m, info = AutoModel.from_pretrained(str(CACHE / "hear" / "pytorch"),
                                                 output_loading_info=True)
        bad = {k: v for k, v in info.items() if v}   # missing/unexpected/mismatched keys
        if bad:
            raise RuntimeError(f"HeAR weights did not load cleanly: {bad}")
        self.m.eval()

    def __call__(self, y):
        n = 2 * SR
        wins = [y[o:o + n] for o in range(0, len(y), n)]
        if len(wins) > 1 and len(wins[-1]) < SR // 2:
            wins = wins[:-1]
        if len(wins) > MAX_HEAR_WINDOWS:   # compute budget: evenly spaced windows, 8 s in all
            wins = [wins[i] for i in np.linspace(0, len(wins) - 1, MAX_HEAR_WINDOWS).round().astype(int)]
        wins = [np.pad(w, (0, n - len(w))) for w in wins]
        embs = []
        with self.torch.no_grad():
            for b in range(0, len(wins), 16):
                x = self.torch.tensor(np.stack(wins[b:b + 16]), dtype=self.torch.float32)
                out = self.m.forward(self.pre(x), return_dict=True, output_hidden_states=True)
                embs.append(out.pooler_output.numpy())
        return {"emb": np.concatenate(embs).mean(0)}


def run(model, dataset, cond, limit=None):
    rows = manifest(dataset)
    if limit:
        rows = rows[:limit]
    d = CACHE / "emb" / dataset / model / cond
    d.mkdir(parents=True, exist_ok=True)
    fn = None
    missing = 0
    t0 = time.time()
    for s in range(0, len(rows), SHARD):
        p = d / f"shard_{s // SHARD:04d}.npz"
        if p.exists():
            continue
        if not all(Path(r["wav"]).exists() for r in rows[s:s + SHARD]):
            missing += 1                       # audio still downloading: pick it up next run
            continue
        if fn is None:
            fn = {"yamnet_app": YamnetApp, "yamnet_float": YamnetFloat, "hear": Hear}.get(model)
            fn = fn() if fn else Opera(rules=(cond == "clean"))
        feats = {}
        for r in rows[s:s + SHARD]:
            y = load16k(r["wav"])
            y = degrade(y, cond, r["rid"], NATIVE_SR[dataset])
            for k, v in fn(y).items():
                feats.setdefault(k, []).append(np.asarray(v, np.float32))
        np.savez(p, rid=np.array([r["rid"] for r in rows[s:s + SHARD]]),
                 **{k: np.stack(v) for k, v in feats.items()})
        print(f"{dataset}/{model}/{cond}: {min(s + SHARD, len(rows))}/{len(rows)} "
              f"({time.time() - t0:.0f}s)", flush=True)
    del fn
    gc.collect()
    if missing:
        print(f"{dataset}/{model}/{cond}: {missing} shard(s) waiting for audio; not merged")
        return False
    merge(d)
    return True


def merge(d: Path):
    shards = sorted(d.glob("shard_*.npz"))
    parts = [dict(np.load(p)) for p in shards]
    out = {k: np.concatenate([p[k] for p in parts]) for k in parts[0]}
    np.savez(d / "features.npz", **out)
    print(f"merged {d} -> {len(out['rid'])} recordings")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, choices=["yamnet_app", "yamnet_float", "opera", "hear"])
    ap.add_argument("--dataset", required=True, choices=["sprsound", "circor"])
    ap.add_argument("--cond", default="clean")
    ap.add_argument("--limit", type=int)
    a = ap.parse_args()
    for c in a.cond.split(","):
        run(a.model, a.dataset, c, a.limit)
