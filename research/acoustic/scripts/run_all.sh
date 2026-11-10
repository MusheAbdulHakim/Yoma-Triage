#!/usr/bin/env bash
# Steps 3-5 end to end, one model at a time. Every stage is resumable: re-run after a crash
# or an OOM kill and finished shards / results are skipped.
#   bash scripts/run_all.sh [circor|sprsound ...]     (default: both)
set -uo pipefail
cd "$(dirname "$0")/.."
PY=".venv/bin/python -I"   # -I: never import code from the data directories
CONDS=clean,hp100,hp150,noise10,noise5,level-20
# Repeats until every shard exists (shards whose audio is still downloading are skipped).
until [ -f cache/emb/sprsound/opera/level-20/features.npz ] && [ -f cache/emb/circor/opera/level-20/features.npz ]; do
  for ds in ${@:-circor sprsound}; do
    $PY scripts/embed.py --model yamnet_app   --dataset "$ds" --cond clean   || exit 1
    $PY scripts/embed.py --model yamnet_float --dataset "$ds" --cond "$CONDS" || exit 1
    $PY scripts/embed.py --model opera        --dataset "$ds" --cond "$CONDS" || exit 1
  done
  sleep 60   # audio still arriving: wait before the next pass
done
echo "ALL EMBEDDINGS DONE"
