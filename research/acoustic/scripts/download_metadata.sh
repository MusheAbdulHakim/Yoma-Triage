#!/usr/bin/env bash
# Download dataset METADATA only (labels, ages, file lists): no audio, no accounts, no terms.
# Everything lands in research/acoustic/data/ (git-ignored). Safe to re-run: existing files are kept.
#
# Usage: bash scripts/download_metadata.sh
set -euo pipefail
cd "$(dirname "$0")/.."
D=data
mkdir -p "$D"/{circor,sprsound,icbhi,coswara}

get() { # url dest
  [ -s "$2" ] && { echo "have $2"; return; }
  curl -sS -L --fail --compressed -o "$2.part" "$1" && mv "$2.part" "$2" && echo "got  $2"
}

# CirCor DigiScope v1.0.3 (PhysioNet, ODC-By 1.0, open access)
C=https://physionet.org/files/circor-heart-sound/1.0.3
get "$C/training_data.csv" "$D/circor/training_data.csv"
get "$C/RECORDS"           "$D/circor/RECORDS"
get "$C/LICENSE.txt"       "$D/circor/LICENSE.txt"
get "$C/SHA256SUMS.txt"    "$D/circor/SHA256SUMS.txt"

# SPRSound (GitHub, CC BY 4.0): sparse, blob-less clone of the JSON annotations, CSVs and
# READMEs only. Patient ID and age are in every filename. Pinned to the commit checked.
SPR_COMMIT=bca1e51422a42a042441010081519610ef3845d0
if [ ! -d "$D/sprsound/repo/.git" ]; then
  git clone -q --filter=blob:none --no-checkout \
    https://github.com/SJTU-YONGFU-RESEARCH-GRP/SPRSound "$D/sprsound/repo"
fi
(
  cd "$D/sprsound/repo"
  git sparse-checkout set --no-cone '/*.md' '/LICENSE' '/Patient Summary/*' \
    '/**/*.json' '/**/*.csv' '/**/*.txt'
  git checkout -q "$SPR_COMMIT"
)

# ICBHI 2017. The official site's TLS certificate expired on 2022-11-26, so it cannot be
# fetched securely. The two small metadata text files come from the Internet Archive's copy
# instead. The audio zip is NOT fetched here: see CHECKPOINT_1.md (decision for the user).
WB=https://web.archive.org/web/2026id_/https://bhichallenge.med.auth.gr/sites/default/files/ICBHI_final_database
for f in ICBHI_Challenge_demographic_information.txt ICBHI_challenge_train_test.txt ICBHI_Challenge_diagnosis.txt; do
  get "$WB/$f" "$D/icbhi/$f" || echo "WARN: could not fetch $f from the Internet Archive"
done

# Coswara (GitHub, CC BY 4.0): metadata CSVs only (the audio is ~16.8 GB of split tarballs).
CW=https://raw.githubusercontent.com/iiscleap/Coswara-Data/master
get "$CW/combined_data.csv" "$D/coswara/combined_data.csv"
get "$CW/LICENSE.md"        "$D/coswara/LICENSE.md"

echo "metadata done"
