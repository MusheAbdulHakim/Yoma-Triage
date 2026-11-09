#!/usr/bin/env bash
# Download the official model files used by the verification scripts into cache/ (git-ignored).
# None of these needs an account or accepting terms. HeAR is deliberately NOT here: it is
# gated behind the Health AI Developer Foundations terms (see CHECKPOINT_1.md).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p cache/yamnet/savedmodel cache/opera_ckpt

get() { [ -s "$2" ] && { echo "have $2"; return; }
        curl -sS -L --fail -o "$2.part" "$1" && mv "$2.part" "$2" && echo "got  $2"; }

# YAMNet, Google (Apache 2.0). Kaggle Models google/yamnet, mirrored at the old tfhub.dev URLs.
get "https://tfhub.dev/google/lite-model/yamnet/tflite/1?lite-format=tflite" \
    cache/yamnet/yamnet_tflite_1.tflite                       # scores + 1024-d embeddings + log-mel
get "https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1?lite-format=tflite" \
    cache/yamnet/yamnet_classification_tflite_1.tflite        # scores only (the app's variant)
if [ ! -s cache/yamnet/savedmodel/saved_model.pb ]; then
  curl -sS -L --fail -o cache/yamnet/sm.tgz \
    https://www.kaggle.com/api/v1/models/google/yamnet/tensorFlow2/yamnet/1/download
  tar -xzf cache/yamnet/sm.tgz -C cache/yamnet/savedmodel && rm cache/yamnet/sm.tgz
fi

# Official OPERA code (MIT) at the commit checked, and the OPERA-CE encoder weights
# (Hugging Face evelyn0414/OPERA, not gated, CC BY-NC 4.0: non-commercial use only).
if [ ! -d cache/OPERA/.git ]; then
  git clone -q https://github.com/evelyn0414/OPERA cache/OPERA
fi
git -C cache/OPERA checkout -q 3622310e667afb8aa40169050b4dd45de75946a2
.venv/bin/python -c "from huggingface_hub import hf_hub_download as d; \
print(d('evelyn0414/OPERA','encoder-operaCE.ckpt',local_dir='cache/opera_ckpt'))"

sha256sum cache/yamnet/*.tflite cache/opera_ckpt/encoder-operaCE.ckpt
