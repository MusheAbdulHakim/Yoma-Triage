#!/usr/bin/env bash
# After run_all.sh: ICBHI children (all models; full band and 4 kHz band-limited), then HeAR
# (experiment d) on clean CirCor and SPRSound. One model at a time; resumable.
set -uo pipefail
cd "$(dirname "$0")/.."
PY=".venv/bin/python -I"
until grep -q "ALL EMBEDDINGS DONE" cache/run_all.log; do sleep 60; done
$PY scripts/embed.py --model yamnet_app   --dataset icbhi --cond clean,bl4k || exit 1
$PY scripts/embed.py --model yamnet_float --dataset icbhi --cond clean,bl4k || exit 1
$PY scripts/embed.py --model opera        --dataset icbhi --cond clean,bl4k || exit 1
for ds in icbhi circor sprsound; do
  c=clean; [ "$ds" = icbhi ] && c=clean,bl4k
  TORCH_THREADS=8 $PY scripts/embed.py --model hear --dataset "$ds" --cond "$c" || exit 1
done
echo "HEAR DONE"
