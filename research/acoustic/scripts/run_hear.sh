#!/usr/bin/env bash
# HeAR (experiment d), clean audio only, after run_all.sh has finished (one model at a time).
set -uo pipefail
cd "$(dirname "$0")/.."
until grep -q "ALL EMBEDDINGS DONE" cache/run_all.log; do sleep 60; done
for ds in circor sprsound; do
  TORCH_THREADS=8 .venv/bin/python -I scripts/embed.py --model hear --dataset "$ds" --cond clean || exit 1
done
echo "HEAR DONE"
