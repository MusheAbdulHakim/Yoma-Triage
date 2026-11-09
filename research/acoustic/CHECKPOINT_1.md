# Acoustic feasibility study: checkpoint 1 (datasets and models)

Branch `research/acoustic-benchmark`. Research only: nothing in `mobile/`, `src/` or `main.py`
was changed. No audio, weights or caches are committed (see `.gitignore`).

Steps 1–2 are done. **Experiments (Steps 3–5) have not started**: they wait for your review
and for the four decisions below.

## Decisions needed before the experiments

1. **HeAR needs an agreement. Stopped, as you asked.**
   - Both Hugging Face repos (`google/hear`, `google/hear-pytorch`) are gated (`gated: auto`).
     To get access you must be logged in to Hugging Face and accept the *Health AI Developer
     Foundations terms of use*: https://developers.google.com/health-ai-developer-foundations/terms
     (last modified 15 Nov 2024).
   - The model card's intended use is "Research and development of health-related acoustic
     biomarkers". The terms themselves have no explicit "research is permitted" clause.
   - The terms define *Clinical Use* as "any use in diagnosis or treatment of patients
     (including as part of a research study)". Read that clause before accepting:
     - benchmarking on public datasets is not use on patients;
     - a field study with CHOs might be.
   - **What I need from you:** either access (an HF account that has accepted the terms, and
     a read token in `HF_TOKEN`), or a decision to drop experiment (d).
2. **ICBHI 2017: the official download site's TLS certificate expired on 2022-11-26.**
   - `bhichallenge.med.auth.gr` cannot be fetched securely. The data needs no account; the
     site says "freely available for research".
   - The three small metadata files used here came from the Internet Archive's copy.
   - The audio zip (with the crackle/wheeze annotations) has not been downloaded. Options:
     - (a) you download `ICBHI_final_database.zip` in a browser, accepting the warning, and
       put it in `research/acoustic/data/icbhi/`;
     - (b) you allow me to fetch it with certificate checking turned off for that one host;
     - (c) use the Internet Archive's copy of the zip, if it has one;
     - (d) skip ICBHI (the paediatric subset is small: see below).
3. **OPERA-CE weights are licensed CC BY-NC 4.0 (non-commercial).**
   - The code is MIT, but the weights are not.
   - Fine for this research. Whether a deployed app may use them depends on who deploys it
     and how. That is a legal question for you, not something I can settle.
4. **Go-ahead for Steps 3–5**, with the scope changes the data forces:
   - stridor has only 9 patients;
   - under-2-months coverage is near zero;
   - no dataset covers the phone capture methods.

   See the evidence summary at the end.

## Step 1: datasets

All facts below come from each dataset's own documentation, licence file or paper. Counts
were computed from the metadata files: `scripts/download_metadata.sh` fetches them, then
`scripts/age_bands.py` counts them (results in `results/age_bands.json`).

### Summary

| | SPRSound | ICBHI 2017 | CirCor DigiScope (PhysioNet 2022) | Coswara |
|---|---|---|---|---|
| **Get it** | Public GitHub repo, no account | Direct links, no account (expired TLS cert) | PhysioNet open access, no account | Public GitHub repo, no account |
| **Licence** | CC BY 4.0 (`LICENSE`) | None stated beyond "freely available for research" | ODC-By 1.0 | CC BY 4.0 |
| **Population** | Children, 1 month to 18 years (README) | 77 adults, 49 children | Paediatric, 0–21 years | Mostly adults (paper: 15–90 years) |
| **Device** | Yunting model II digital stethoscope, 8 kHz | Children: all Meditron digital stethoscope | Littmann 3200 digital stethoscope, 4 kHz | Participant's own smartphone or computer, in air |
| **Capture method** | (c) stethoscope | (c) stethoscope | (c) stethoscope | (a) in air, but adult breathing at the mouth, not chest |
| **Task labels** | Stridor, wheeze, crackles (+ rhonchi) | Crackles, wheezes | Murmur | None of ours (COVID status) |
| **Grunting** | No | No | No | No |

### SPRSound (SJTU Paediatric Respiratory Sound Database)

**Obtain.**

- https://github.com/SJTU-YONGFU-RESEARCH-GRP/SPRSound, checked at commit `bca1e51`
  (2026-07-23).
- The README asks for no registration. The TBioCAS paper says "free access for all
  registered users"; the repo has no gate.
- The only data-use agreement I found is for challenge submissions, not downloads.
- All 6,567 recordings are in the year folders (`BioCAS2022` to `BioCAS2025`). Checked:
  `Classification/`, `Detection/` and `Compression/` contain no recording outside them.

**Licence.** CC BY 4.0.

**Cite.**

- Q. Zhang et al., "SPRSound: Open-Source SJTU Paediatric Respiratory Sound Database",
  *IEEE TBioCAS* 16(5):867–881, 2022.
- The README also asks for the BioCAS 2022 and 2023 Grand Challenge papers, and the 2024
  *IEEE Data Descriptions* paper.

**Device.**

- "Yunting model II Stethoscopes": a contact digital stethoscope at 8 kHz, 16 bit.
- Sites: four on the back (left and right posterior, left and right lateral). Sites p5–p8
  were added in 2024–25.
- Recorded at Shanghai Children's Medical Center.

**Labels (exact).**

- Record level: `Normal`, `CAS`, `DAS`, `CAS & DAS`, `Poor Quality`. The 2024 and 2025 test
  JSONs may have event labels only.
- Event level, with start and end in ms: `Normal`, `Rhonchi`, `Wheeze`, `Stridor`,
  `Coarse Crackle`, `Fine Crackle`, `Wheeze+Crackle`.
- Events are labelled respiratory segments (mean 1.3 s). The documentation never says one
  event is one breath.

**Age.**

- Age in years (decimal) is in every filename (`patient_age_gender_location_recnum`) and in
  the patient-summary CSVs.
- 390 recordings in the 2023–2025 test sets have the patient ID blanked (`_2.5_1_p4_…`). They
  cannot be grouped by patient, so they are counted separately and will be left out of
  patient-grouped cross-validation.

| Band | Patients | Recordings | Stridor: patients / recs | Wheeze*: patients / recs | Crackle*: patients / recs | Recs without patient ID |
|---|---|---|---|---|---|---|
| < 2 months | 2 | 10 | 0 / 0 | 0 / 0 | 1 / 3 | 0 |
| 2–11 months | 55 | 354 | 3 / 10 | 26 / 120 | 24 / 106 | 20 |
| 1–5 years | 484 | 3,331 | 5 / 18 | 98 / 366 | 144 / 738 | 288 |
| 6 years and older | 330 | 2,482 | 1 / 1 | 33 / 120 | 86 / 404 | 82 |

\* Wheeze includes `Wheeze+Crackle`. Crackle includes `Fine Crackle`, `Coarse Crackle` and
`Wheeze+Crackle`. A recording counts once if it has at least one such event.

- Stridor across the whole release: 31 recordings. 29 of them have a patient ID, from
  **9 patients**. None are under 2 months.
- A patient whose recordings span a birthday can appear in two bands.

### ICBHI 2017 (Respiratory Sound Database)

**Obtain.**

- Direct links under `bhichallenge.med.auth.gr/sites/default/files/ICBHI_final_database/`:
  `ICBHI_final_database.zip`, `events.zip`, the demographics, diagnosis and train/test
  files.
- The certificate expired on 2022-11-26 (decision 2 above). The facts here come from the
  Internet Archive copy of the challenge page (2026-10-11) and from the paper.

**Licence.** None stated beyond "freely available for research".

**Cite.** Rocha B.M. et al., "An open access database for the evaluation of respiratory sound
classification algorithms", *Physiol. Meas.* 40:035001, 2019. doi:10.1088/1361-6579/ab03ea.

**Devices** (filename suffix):

- AKG C417L microphone: an air-coupled electret in a chest capsule, adults only;
- 3M Littmann Classic II SE;
- Littmann 3200;
- Welch Allyn Meditron.

**Labels (exact).**

- Per respiratory cycle: start, end, crackles present (0/1), wheezes present (0/1).
- `events.zip` holds only `crackle` and `wheeze`.
- No stridor, no grunting.
- Per-patient diagnosis: e.g. `URTI`, `Bronchiolitis`, `Pneumonia`, `LRTI`, `Healthy`.

**Paediatric subset** (age < 19 years, as the paper defines it): 49 children and 76 recordings,
**all recorded with the Meditron stethoscope** by the Aveiro team.

| Band | Patients | Recordings | Diagnoses (patients) |
|---|---|---|---|
| < 2 months | 0 | 0 | none (youngest is 0.25 years) |
| 2–11 months | 8 | 13 | Healthy 5, Bronchiolitis 1, LRTI 1, URTI 1 |
| 1–5 years | 28 | 45 | Healthy 11, URTI 10, Bronchiolitis 5, LRTI 1, Pneumonia 1 |
| 6–18 years | 13 | 18 | |
| Adults | 76 | 838 | (not used) |
| Age missing | 1 | 6 | |

- Crackle and wheeze counts for the children need the annotation files inside the audio zip
  (decision 2).

### CirCor DigiScope / PhysioNet Challenge 2022

**Obtain.** https://physionet.org/content/circor-heart-sound/1.0.3/ is open access with no
account. It is 449.5 MB zipped.

**Licence.** ODC-By 1.0.

**Cite.**

- Oliveira J. et al., "The CirCor DigiScope Dataset: From Murmur Detection to Murmur
  Classification", *IEEE JBHI*, 2022, doi:10.1109/JBHI.2021.3137048.
- The dataset itself: doi:10.13026/tshs-mw03.
- The PhysioNet citation the page asks for.

**Device.** Littmann 3200 digital stethoscope (DigiScope Collector), 4 kHz, 16 bit.

**Sites.** `PV`, `TV`, `AV`, `MV`, `Phc`. Campaigns were in Brazil.

**Labels (exact).**

- `Murmur`: `Present` / `Absent` / `Unknown`, per patient, with the locations where heard.
- Systolic and diastolic timing, shape, grading, pitch and quality.
- `Outcome`: `Normal` / `Abnormal`, the cardiologist's overall assessment. This is not the
  same as murmur.
- **There is no innocent-versus-pathological label.**

**Age.** The dataset uses NICHD categories, not ages, so the requested bands can only be
approximated:

- `Neonate` (0–27 days) lies inside "< 2 months";
- `Infant` (28 days to 1 year) straddles "< 2 months" and "2–11 months";
- `Child` (1–11 years) straddles "1–5 years" and "older".

| CirCor category | Patients | Recordings | Murmur Present / Absent / Unknown |
|---|---|---|---|
| Neonate (0–27 d) | 6 | 10 | 1 / 4 / 1 |
| Infant (28 d–1 y) | 126 | 269 | 25 / 76 / 25 |
| Child (1–11 y) | 664 | 2,386 | 132 / 495 / 37 |
| Adolescent (12–18 y) | 72 | 259 | 16 / 53 / 3 |
| Missing | 74 | 239 | 5 / 67 / 2 |

The training set is 942 patients and 3,163 recordings. That matches the Challenge page.

### Coswara (optional)

**Obtain.**

- https://github.com/iiscleap/Coswara-Data is a plain public repo, about 16.8 GB of split
  tarballs.
- No account and no agreement. **Openly downloadable.**

**Licence.** CC BY 4.0.

**Cite.** Bhattacharya D. et al., *Scientific Data* 10:397 (2023),
doi:10.1038/s41597-023-02266-0.

**Device.** Recorded in a browser on the participant's own smartphone or computer, mostly at
48 kHz.

**Content:**

- breathing (deep/shallow);
- cough (deep/shallow);
- three vowels;
- counting.

**Ages.** The paper says 15–90 years. The metadata (2,746 participants) has 5 with an age
under 6, recorded as 1 or 2 years, which are probably entry errors. There are no infants.

**Use here:** only the phone-degradation sanity check. It is real phone audio, but adult
breathing at the mouth, with no chest sounds and none of our labels.

### Capture-method coverage, per task

| Task | (a) Phone a few cm from the chest | (b) Phone pressed to the chest | (c) Stethoscope in contact |
|---|---|---|---|
| Stridor | none | none | SPRSound (back sites) |
| Wheeze | none | none | SPRSound; ICBHI children |
| Crackles | none | none | SPRSound; ICBHI children |
| Heart murmur | none | none | CirCor |
| Breathing rate | none* | none | SPRSound/ICBHI timings (stethoscope) |
| Grunting | none | none | none |

\* Coswara is real phone audio, but of adult mouth breathing, not the chest.

**No public dataset covers capture methods (a) or (b) for any task.** The planned
"phone degradation" test only simulates a phone (high-pass filter, clinic noise, lower
level). It shows how fast performance falls, not how a real phone performs. Only the local
three-method recordings can answer that.

### Grunting: the data gap

- **No obtainable dataset has labelled infant grunting.**
  - SPRSound's event types, ICBHI's annotations (crackle and wheeze only), CirCor (heart
    sounds) and Coswara (adult breathing, cough and voice) contain no grunting label.
  - Nothing has been substituted (no cries, no other sounds).
- Grunting is therefore not part of Steps 3–5. It needs local recordings, under ethics
  approval:
  - **Who:** infants under 2 months at the Day 1, Day 7 and Week 6 postnatal visits, plus
    sick young infants at CWCs and referral points, where grunting is common enough to
    collect positives.
  - **Recordings:** every infant is recorded with all three methods in one sitting:
    (a) phone a few cm from the chest, (b) phone pressed to the chest, microphone edge to
    the skin, (c) stethoscope attachment.
    - Randomise the order.
    - Make each recording at least 60 s, with the infant calm where possible.
    - Note who held the device and what device model was used.
  - **Reference standard:**
    - A clinician's bedside judgment of grunting (present/absent), made independently of
      the recordings.
    - A 60-second breath count, as the reference for breathing rate.
    - Two independent reviewers label grunting episodes on the audio, with timestamps and
      a third reviewer for disagreements. A short synchronised video helps them; it needs
      separate consent and storage rules.
  - **Context to record:**
    - age in days, weight and SpO₂;
    - ambient noise level (a noise-only clip before each recording);
    - setting.
  - **Consent and data:**
    - Parental consent.
    - De-identified IDs, so recordings can be grouped by patient.
    - Storage that never leaves the approved system.
  - **Rough size:** to estimate a sensitivity of about 90% to within ±10% (95% CI), about
    35 infants **with** grunting are needed. How many infants must be recorded to find 35
    depends on how common grunting is in the recruited group. The final report will give
    a full sample-size calculation.

## Step 2: models

### YAMNet

Reproduce with `scripts/inspect_tflite.py` and `scripts/verify_yamnet.py`. Results are in
`results/yamnet_verification.json`.

**The app's `mobile/assets/models/yamnet.tflite` is Google's official
`lite-model/yamnet/classification/tflite/1`.**

- It is the same size (4,126,810 bytes). Only 23 bytes differ, all in the timestamp of the
  embedded label-file zip (2021 vs 2023 repack). Its outputs equal the official file's
  exactly (max abs diff 0.0).
- Input: `waveform_binary` [15600] float32. Output: `tower0/network/layer32/final_output`
  [1, 521] float32 scores.
- Weights are int8 (DEQUANTIZE/QUANTIZE ops), with an RFFT2D frontend. It needs no Select TF
  ops.
- **It does not expose embeddings.** The 1024-wide tensors are internal only.

**Google publishes a second official variant with embeddings:**
`lite-model/yamnet/tflite/1` (Kaggle `google/yamnet/tfLite/tflite`).

- Input: `waveform` with a dynamic length.
- Outputs:
  - `Identity` [N, 521] scores;
  - `Identity_1` [N, 1024] **embeddings**;
  - `Identity_2` [96·N, 64] log-mel.
- Float32 weights, 16,096,668 bytes. **It needs no Select TF ops** (25 builtin ops).
- **No custom export is needed.** Resizing the input to 15,600 at runtime gives exactly one
  frame per window, the app's fixed input.

**Checked against official TensorFlow** (Kaggle SavedModel `google/yamnet/tensorFlow2/yamnet/1`,
TF 2.21), on four 15,600-sample inputs including a real CirCor recording:

| Output | Max abs diff vs TF | Scale of the values |
|---|---|---|
| Embeddings (1024) | 3.8e-6 to 4.7e-4 | up to 8.7 |
| Scores (521) | 3.0e-7 to 6.9e-5 | 0–1 |
| Log-mel | 1.4e-6 to 8.3e-4 | |

The largest differences came from the pure 400 Hz tone; noise and heart sounds stay
around 1e-5 or below.

**Quantization (reported separately, as asked).** The app's int8 classification variant does
**not** closely track the float model.

- Score max abs diff vs TF: 0.11–0.99.
- On 8 real one-second CirCor windows: the top-1 class differed in all 8, the top-5 classes
  overlapped by 0–2, and the Spearman rank correlation was 0.36–0.66.
- I did not isolate the cause: int8 weights, or the variant's own RFFT2D frontend.
- These are low-confidence, out-of-domain inputs (heart sounds), so the gap is likely
  smaller on everyday sounds. But YAMNet zero-shot results on this task will differ
  between the two files.
- Step 3 will report zero-shot results for both.

**APK impact (not changed).** Using embeddings means replacing the 4.1 MB file with the
16.1 MB variant, which also gives the 521 scores: about **+12 MB** raw, with no
`SELECT_TF_OPS` and no Flex delegate. Quantizing it would need its own check against TF,
done the same way as above.

### OPERA-CE

**Official source.**

- **Paper:** Zhang Y. et al., "Towards Open Respiratory Acoustic Foundation Models:
  Pretraining and Benchmarking", NeurIPS 2024 Datasets and Benchmarks, arXiv:2406.16148.
- **Code:** https://github.com/evelyn0414/OPERA, MIT, checked at `3622310`.
- **Weights:** HF `evelyn0414/OPERA`, file `encoder-operaCE.ckpt`, not gated,
  **CC BY-NC 4.0**.

**Model and training data.**

- EfficientNet-B0 encoder, 1280-d output, about 4M parameters.
- Pretraining data (paper, Table 1): COVID-19 Sounds, UK COVID-19 and COUGHVID (all
  "microphone"), and ICBHI and HF Lung (both "stethoscope").
  - The paper says "microphone", not "smartphone", so whether this was smartphone audio is
    not confirmed.
  - It includes **no infant data and no grunting**. ICBHI includes 49 children.

**Official preprocessing** (`src/util.py`: `get_entire_signal_librosa`, then
`pre_process_audio_mel_t`; called by `extract_opera_feature` in
`src/benchmark/model_util.py`):

1. `librosa.load(sr=16000)`, mono.
2. Trim leading and trailing silence: `librosa.effects.trim(frame_length=1600, hop_length=800)`.
3. If shorter than 8 s, pad to 8 s by **repeating** the clip (`split_pad_sample`, type
   `repeat`).
4. Mel spectrogram: 64 mels, f_min 50, **f_max 8000** (the caller overrides the default
   2000), n_fft 1024, hop 512, librosa defaults otherwise (periodic Hann, centred, zero
   padding).
5. `power_to_db(ref=np.max)` (top_db 80), then min–max to [0, 1].
6. Transpose to **(T, 64)**. The **whole clip** goes in, at any length (T > 251 if over
   8 s), batch 1. The output is `Encoder` (`cnn1` Conv2d(1→3, k=3), then EfficientNet-B0 with
   no top), 1280-d.

An 8.0 s clip gives exactly 251 frames.

**Repo files checked** (`scripts/verify_opera_ce.py`, results in
`results/opera_ce_verification.json`). Six inputs:

- four seeded synthetic clips: 8 s, 3 s and 12 s;
- two real CirCor recordings (23.6 s and 26.7 s).

The reference is the official encoder with all weights loaded (`strict=True`).

| File | Input it takes | Max abs diff vs official | Cosine |
|---|---|---|---|
| `opera_ce_encoder.onnx` | `mel` [B, 251, 64] float32 (frames, mels) | ≤ 1.0e-5 | 1.0 |
| `opera_ce_encoder.tflite`, fed mel.T | `mel` [1, **64, 251**] **float16** (mels, frames) | ≤ 0.011 (outputs up to 3.9) | ≥ 0.99999 |
| same TFLite, fed the (251 × 64) buffer as-is | | up to 5.2 | **0.40–0.57** |

**Both exports are faithful to the official model.** The TFLite's difference is float16
rounding. Its axes are swapped relative to the official layout.

**What the app's preprocessing would need to change.** This is a list only; the app was not
changed. Items 1–3 must change; 4–5 are optional or minor.

1. **Axis order.**
   - `OperaCeMel.melForEncoder` builds a row-major (251 × 64) buffer, and
     `opera_ce_classifier_io.dart` copies it flat into the [1, 64, 251] tensor.
   - That scrambles the input: cosine 0.40–0.57 against the official embedding.
   - It must transpose to (64 × 251) first, or the model should be re-exported to take
     (251, 64).
2. **float16 input and output.**
   - The TFLite input and output tensors are float16; the app passes plain double lists.
   - This is a likely cause of the Android load and run failure in `CHECKSUMS.md`
     ("Bad state: failed precondition"). It is **unconfirmed**: no device or emulator was
     used, as instructed.
   - Re-exporting with float32 input and output (weights can stay float16) would remove the
     question.
3. **Padding, trimming and length.** The app does not trim silence, **zero**-pads short
   clips and **truncates** at 8 s.
   - A 3 s clip: cosine **0.60** against the official embedding.
   - The 23–27 s CirCor recordings: cosine 0.91–0.96 (8 s cut against the whole clip).
   - Recordings of exactly 8 s with no silence match exactly.
   - A fixed [1, 64, 251] model cannot take a whole long clip. So the app should match the
     official trim and repeat-padding, and for clips over 8 s use one rule, applied the
     same way in training and on the phone. For example: average 8 s windows, or keep the
     first 8 s after trimming.
   - Step 3 will measure both rules against the official whole-clip embedding.
4. **Hann window in Dart.** The Dart code uses a symmetric Hann window (N−1); librosa uses a
   periodic one (N). The effect is negligible: mel max diff ≤ 0.0026, embedding cosine
   ≥ 0.9999995. Changing it is still a one-line fix.
5. **Backend.** `src/acoustic/opera_ce_mel.py` has the same padding and truncation
   behaviour as item 3. Its mel otherwise equals the official mel exactly on 8 s clips.

### HeAR

Stopped at the agreement: see decision 1.

- Its input is 2 s of 16 kHz mono (n, 32000).
- Its output is a 512-d embedding.
- Routes: HF `google/hear` (TF/Keras), `google/hear-pytorch` and Vertex Model Garden.
- Kaggle `google/hear` returned 404.

## What the evidence can and cannot support

- **Murmur (CirCor):** the most data. 179 patients have a murmur, but there are only 6 neonates in
  total, and the stethoscope is the only capture method.
- **Wheeze and crackles (SPRSound, plus ICBHI children if obtained):** enough for 2–11 months
  and 1–5 years. **Not under 2 months** (2 patients).
- **Stridor (SPRSound):** 9 patients in total. Cross-validation by patient is possible, but
  the confidence intervals will be very wide. Results will be stated as exploratory.
- **Under 2 months** (the Day 1, Day 7 and Week 6 population): essentially absent from every
  public dataset. 2 patients in SPRSound, 6 neonates in CirCor, none in ICBHI or Coswara.
  Nothing here can show the models work for newborns.
- **Phone capture (a) and (b):** not covered by any dataset. Only simulated.

## Reproduce

```bash
cd research/acoustic
python3.12 -m venv .venv
.venv/bin/pip install torch==2.15.0 torchaudio==2.11.1 --index-url https://download.pytorch.org/whl/cpu
.venv/bin/pip install -r requirements.txt
bash scripts/download_metadata.sh   # labels, ages, file lists (no audio)
bash scripts/download_models.sh     # YAMNet variants + SavedModel, OPERA code + weights
bash scripts/download_audio.sh circor-samples   # the 2 CirCor recordings, checksum-verified
.venv/bin/python scripts/age_bands.py
.venv/bin/python scripts/inspect_tflite.py ../../mobile/assets/models/*.tflite
.venv/bin/python scripts/verify_yamnet.py
.venv/bin/python scripts/verify_opera_ce.py
```

- `verify_opera_ce.py` and `verify_yamnet.py` also use two CirCor recordings
  (`training_data/2530_AV.wav`, `2530_MV.wav`) if they are present. Fetch them with
  `download_audio.sh circor-samples` before running those two scripts; it checks them
  against PhysioNet's `SHA256SUMS.txt`.
- `scripts/download_audio.sh` with the dataset names fetches the full audio for Step 3. It
  has not been run.
