#!/usr/bin/env bash
# Download dataset AUDIO for the experiments (Step 3). Not run before the checkpoint review.
# Everything goes to data/ (git-ignored). Resumable: finished parts are skipped.
#
# Usage: bash scripts/download_audio.sh [circor-samples] [circor] [sprsound] [coswara] [icbhi]
#   circor    PhysioNet, ODC-By 1.0, ~560 MB
#   sprsound  GitHub, CC BY 4.0: the year folders' wav files (6,567 recordings, ~1.2 GB)
#   coswara   GitHub, CC BY 4.0, ~16.8 GB: only a few date folders are needed for the
#             phone-degradation sanity check; set COSWARA_DATES="20200413 ..." to choose
#   icbhi     NOT automatic. The official site's TLS certificate expired on 2022-11-26.
#             Needs the user's decision; see CHECKPOINT_1.md.
set -euo pipefail
cd "$(dirname "$0")/.."
D=data

for what in "$@"; do
case "$what" in
circor-samples)   # the two recordings used by verify_opera_ce.py / verify_yamnet.py
  mkdir -p "$D/circor/training_data"
  for r in 2530_AV 2530_MV; do
    [ -s "$D/circor/training_data/$r.wav" ] || curl -sS -L --fail \
      -o "$D/circor/training_data/$r.wav" \
      "https://physionet.org/files/circor-heart-sound/1.0.3/training_data/$r.wav"
  done
  (cd "$D/circor" && grep -E ' training_data/2530_(AV|MV)\.wav$' SHA256SUMS.txt | sha256sum -c) ;;
circor)
  mkdir -p "$D/circor"
  # -c resumes partial files, -N skips files that are already complete.
  wget -q -r -N -c -np -nH --cut-dirs=3 -P "$D/circor" \
    https://physionet.org/files/circor-heart-sound/1.0.3/training_data/
  (cd "$D/circor" && grep ' training_data/' SHA256SUMS.txt | sha256sum -c --quiet) \
    && echo "circor: checksums OK" ;;
sprsound)
  R="$D/sprsound/repo"
  [ -d "$R/.git" ] || bash scripts/download_metadata.sh
  git -C "$R" sparse-checkout add '/BioCAS2022/train2022_wav/*' '/BioCAS2022/test2022_wav/*' \
    '/BioCAS2023/test2023_wav/*' '/BioCAS2024/test2024_wav/*' '/BioCAS2025/test2025_wav/*'
  # The Classification/, Detection/ and Compression/ folders only duplicate these recordings
  # (checked: 0 recording IDs outside the year folders), so they are not fetched.
  echo "sprsound: wav files checked out" ;;
coswara)
  R="$D/coswara/repo"
  [ -d "$R/.git" ] || git clone -q --filter=blob:none --no-checkout \
      https://github.com/iiscleap/Coswara-Data "$R"
  git -C "$R" sparse-checkout set --no-cone '/*.csv' '/*.py' \
      $(for d in ${COSWARA_DATES:-20200413}; do echo "/$d/*"; done)
  git -C "$R" checkout -q master
  echo "coswara: extract with: cat <date>/*.tar.gz.* | tar -xz" ;;
icbhi)
  echo "ICBHI: waiting for the user's decision (expired TLS certificate). Not downloaded." ;;
*) echo "unknown dataset: $what" >&2; exit 2 ;;
esac
done
