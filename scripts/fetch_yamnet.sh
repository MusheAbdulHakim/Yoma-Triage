#!/usr/bin/env bash
# Fetch official YAMNet TFLite model (~4 MB) into mobile/assets/models/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/mobile/assets/models/yamnet.tflite"
URL="https://storage.googleapis.com/audioset/yamnet.tflite"

mkdir -p "$(dirname "$DEST")"
echo "Downloading YAMNet from $URL …"
curl -fsSL --retry 3 --retry-delay 2 -o "$DEST" "$URL"
ls -lh "$DEST"
echo "Done: $DEST"
