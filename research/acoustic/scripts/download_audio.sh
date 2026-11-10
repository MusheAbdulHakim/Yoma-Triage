#!/usr/bin/env bash
# Download dataset AUDIO for the experiments (Steps 3-5) into data/ (git-ignored).
# Files are fetched one by one, 16 at a time (this host's link is latency-bound, and git's
# partial-clone fetch ran at ~12 KB/s). Resumable: files already present are skipped.
#
# Usage: bash scripts/download_audio.sh [circor-samples] [circor] [sprsound] [coswara] [icbhi]
#   circor    PhysioNet, ODC-By 1.0: every training recording's .wav and .tsv (segmentation)
#   sprsound  GitHub, CC BY 4.0: the year folders' wav files (6,567 recordings, ~1.2 GB).
#             Classification/, Detection/ and Compression/ only duplicate them (checked).
#   coswara   GitHub, CC BY 4.0: date folders in COSWARA_DATES (default the two smallest,
#             20200911 and 20200505, ~115 MB), extracted. Used only as real phone audio.
#   icbhi     Not downloaded: decision 2 (expired TLS certificate; skipped, see the report).
set -euo pipefail
cd "$(dirname "$0")/.."
D=data
P=${PARALLEL:-16}

# fetch_list <base-url> <dest-dir>: reads relative paths on stdin, downloads missing ones.
fetch_list() {
  local base=$1 dest=$2
  grep -v '^$' | while read -r rel; do [ -s "$dest/$rel" ] || echo "$rel"; done |
    xargs -r -P "$P" -I{} sh -c 'mkdir -p "$(dirname "$2/$1")" &&
      curl -sS -L --fail --retry 5 --retry-delay 2 -o "$2/$1.part" "$3/$1" &&
      mv "$2/$1.part" "$2/$1" || echo "FAILED $1" >&2' _ {} "$dest" "$base"
}

for what in "$@"; do
case "$what" in
circor-samples)   # the two recordings used by verify_opera_ce.py / verify_yamnet.py
  printf 'training_data/2530_AV.wav\ntraining_data/2530_MV.wav\n' |
    fetch_list https://physionet.org/files/circor-heart-sound/1.0.3 "$D/circor"
  (cd "$D/circor" && grep -E ' training_data/2530_(AV|MV)\.wav$' SHA256SUMS.txt | sha256sum -c) ;;
circor)
  [ -s "$D/circor/RECORDS" ] || bash scripts/download_metadata.sh
  sed 's/$/.wav/' "$D/circor/RECORDS" > "$D/circor/.list"
  sed 's/$/.tsv/' "$D/circor/RECORDS" >> "$D/circor/.list"
  # PhysioNet's open-data S3 mirror (listed on the dataset page) is ~3x faster here than
  # physionet.org; every file is checked against PhysioNet's SHA256SUMS.txt below.
  fetch_list https://physionet-open.s3.amazonaws.com/circor-heart-sound/1.0.3 "$D/circor" < "$D/circor/.list"
  (cd "$D/circor" && grep -E ' training_data/.*\.(wav|tsv)$' SHA256SUMS.txt | sha256sum -c --quiet) \
    && echo "circor: checksums OK" ;;
sprsound)
  R="$D/sprsound/repo"
  [ -d "$R/.git" ] || bash scripts/download_metadata.sh
  SPR_COMMIT=bca1e51422a42a042441010081519610ef3845d0
  (cd "$R" && ls BioCAS20*/*_json/*.json) | sed -E 's#_json/(.*)\.json$#_wav/\1.wav#' |
    fetch_list "https://raw.githubusercontent.com/SJTU-YONGFU-RESEARCH-GRP/SPRSound/$SPR_COMMIT" \
      "$D/sprsound/wav"
  echo "sprsound: $(find "$D/sprsound/wav" -name '*.wav' | wc -l) wav files" ;;
coswara)
  C="$D/coswara"
  for d in ${COSWARA_DATES:-20200911 20200505}; do
    curl -sS "https://api.github.com/repos/iiscleap/Coswara-Data/git/trees/master?recursive=1" |
      python3 -c "import json,sys; [print(x['path']) for x in json.load(sys.stdin)['tree'] \
        if x['type']=='blob' and x['path'].startswith('$d/')]" |
      fetch_list https://raw.githubusercontent.com/iiscleap/Coswara-Data/master "$C/raw"
    [ -d "$C/audio/$d" ] || { mkdir -p "$C/audio" &&
      cat "$C/raw/$d"/*.tar.gz.* | tar -xz -C "$C/audio"; }
  done
  echo "coswara: $(find "$C/audio" -name '*.wav' | wc -l) wav files" ;;
icbhi)
  echo "ICBHI: skipped (expired TLS certificate; certificate checks are not disabled)." ;;
*) echo "unknown dataset: $what" >&2; exit 2 ;;
esac
done
