# Acoustic feasibility study, phase 1: can an AI model recognise clinically relevant breathing and heart sounds?

Branch `research/acoustic-benchmark`. Research only: nothing in `mobile/`, `src/` or
`main.py` was changed. Dataset facts and model checks are in
[`CHECKPOINT_1.md`](CHECKPOINT_1.md). This report adds the experiments (Steps 3–5). Every
results table, with confidence intervals and age bands, is in
[`results/tables.md`](results/tables.md). The raw numbers are in `results/*.json`.

> **Read this first: these results are about children in general, not newborns.**
> The Day 1, Day 7 and Week 6 babies are almost absent from every public dataset:
>
> | Dataset | Under 2 months |
> |---|---|
> | SPRSound | 2 patients, 10 recordings (none with stridor or wheeze; 1 with crackles) |
> | CirCor | 6 neonates (0–27 days), 10 recordings. Infants aged 28 days to 2 months cannot be separated from older infants: the dataset gives age categories, not ages |
> | ICBHI 2017 | 0 (the youngest child is 3 months) |
> | Coswara | 0 (adults) |
>
> Nothing here shows that any method works for newborns.
>
> **Stridor results are exploratory.** Only 9 patients (29 recordings) in SPRSound have
> stridor, after excluding recordings without a patient ID or marked "Poor Quality". Every
> stridor figure below is marked as exploratory.
>
> **Every labelled recording was made with a stethoscope.** No public dataset covers a phone
> held near the chest or pressed against it. The phone conditions here are simulated.

## Summary in plain language

1. **The app's current YAMNet model can't detect these sounds as it is.** Used directly,
   with no training on medical audio (zero-shot), it scores near chance:
   - crackles: AUROC 0.50;
   - heart murmur: 0.44;
   - wheeze: 0.62.

   The app's combined "respiratory" score does a little better on wheeze (0.71), but misses
   about half of the children who wheeze.
2. **A small classifier trained on top of YAMNet does much better on stethoscope
   recordings** (AUROC, 95% CI):
   - wheeze: 0.86 (0.83–0.90);
   - crackles: 0.79 (0.77–0.82);
   - heart murmur: 0.81 (0.77–0.85).

   This classifier is a logistic regression on YAMNet's embeddings, and YAMNet's weights are
   Apache 2.0. In these tests it beat OPERA-CE, a model built for respiratory sounds, on
   every task. HEAR_SUMMARY
3. **It does not yet carry over to a different stethoscope or a noisy room.**
   - **Different stethoscope:** trained on SPRSound and tested unchanged on ICBHI's
     children, the YAMNet classifier falls to chance (wheeze 0.36–0.41, crackles 0.54–0.58).
   - **Noise:** with simulated clinic noise at 10 dB SNR, wheeze falls to 0.53 and crackles
     to 0.43.
   - **What this means:** the models learned the sound of one device in one hospital. Real
     use needs training data from the device and setting where it will be used.
4. **The question that matters for Yoma, whether a phone works, can't be answered from public
   data.** No public dataset has a phone in air (a) or pressed to the chest (b). Real phone
   audio (Coswara) has almost no energy below 150 Hz:
   - Coswara phone audio: 1–2% of its energy is below 150 Hz;
   - the stethoscope recordings: about 40% is below 150 Hz.

   Most of a heart sound, and much of a breath sound, is below 150 Hz. On top of that,
   removing everything below 150 Hz stops the simple heart-rate counter working (median
   error goes from 5 to 43 beats/min).
5. **Breathing rate can be counted without AI, in quiet conditions.** A plain loudness-envelope
   counter was within ±5 breaths/min on 70% of ICBHI children's recordings. Its median error
   was 1.2 breaths/min against the annotated breath cycles. In clinic-like noise, the median
   error rose to about 5.5 breaths/min.
6. **Grunting, the sign that matters most for young infants, has no public data at all.** It
   needs local recordings (protocol below).

**Recommendation:**
- **First task:** wheeze, then crackles.
- **Model:** a classifier on YAMNet embeddings. It is Apache 2.0 and a YAMNet model is already
  in the app.
- **First step:** a local recording study that records every child with all three capture
  methods, before any detection reaches users.

Details are in [Recommendation](#recommendation).

## What was done

### Data used

| Dataset | Used for | Patients | Recordings | Native sample rate | Capture |
|---|---|---|---|---|---|
| SPRSound (CC BY 4.0) | Stridor (exploratory), wheeze, crackles; breathing-rate proxy | 859 | 5,950 | 8 kHz | (c) stethoscope |
| CirCor DigiScope (ODC-By 1.0) | Murmur; Outcome; heart rate | 942 (874 for murmur) | 3,163 | 4 kHz | (c) stethoscope |
| ICBHI 2017, **children only** | External test for wheeze and crackles; breathing rate against annotated cycles | 49 | 76 | 44.1 kHz | (c) stethoscope (Meditron, one LittC2SE) |
| Coswara (CC BY 4.0) | Real phone-audio reference for the degradation test only | 125 breathing recordings | | 48 kHz | (a) in air, adult mouth breathing |

**SPRSound exclusions:**
- recordings whose patient ID is blank, since they can't be grouped by patient;
- recordings marked "Poor Quality";
- recordings with neither events nor a record label.

**Labels.**
- **Wheeze:** at least one `Wheeze` or `Wheeze+Crackle` event.
- **Crackles:** at least one `Fine Crackle`, `Coarse Crackle` or `Wheeze+Crackle` event.
- **Stridor:** at least one `Stridor` event.
- **CirCor**, two separate tasks as asked:
  - **Murmur Present vs Absent**, with Unknown excluded. A recording counts as positive if the
    patient has a murmur and it was heard at that site. The patient's score is the highest of
    their recordings.
  - **Outcome Abnormal vs Normal.** The patient's score is the average over their recordings.
    **Outcome is the cardiologist's overall assessment, and it is the closer proxy for "this
    child has a heart problem".** A murmur can be innocent, and CirCor has no
    innocent-versus-pathological label.

**ICBHI 2017.**
- The user obtained it by hand. I did not bypass the site's expired certificate.
- Only children (under 19, the dataset's definition) are used. The 77 adults are not.
- One file is listed as `226_1b1_Pl_sc_Meditron` but is stored as `226_1b1_Pl_sc_LittC2SE`. It
  was matched by patient, site and recording index.
- Bias in OPERA-CE's favour: OPERA-CE was pretrained on unlabelled ICBHI audio, so its ICBHI
  result is likely flattering.

### Models (experiments a–e)

| Exp. | Model | How used | Weight licence |
|---|---|---|---|
| a | YAMNet, **the app's model** (`mobile/assets/models/yamnet.tflite`, Google's int8 classification variant) | Zero-shot. The app's own windowing: 0.975 s windows with half overlap, highest score over the windows. Fixed class mapping: wheeze → `Wheeze`; stridor → `Wheeze` (proxy, as there is no stridor class); crackles → `Crackle`; murmur and Outcome → `Heart murmur`. Also the app's own respiratory score: the highest of Breathing, Wheeze, Gasp, Pant, Snort and Cough | Apache 2.0 |
| a | YAMNet, Google's official float model | Zero-shot, whole clip, same class mapping | Apache 2.0 |
| b | YAMNet, Google's official embeddings variant | Mean of the 1,024-d embeddings → logistic regression | Apache 2.0 |
| c | OPERA-CE | Official preprocessing as verified in Step 2. It reproduces the official embedding exactly (max abs diff 0.0). 1,280-d → logistic regression | **CC BY-NC 4.0** |
| d | HeAR (`google/hear-pytorch`) | Official `preprocess_audio`, 2 s windows, at most 4 evenly spaced windows (8 s), embeddings averaged, 512-d → logistic regression. Clean audio only | **HAI-DEF terms of use (not an open licence)** |
| e | None (signal processing) | Envelope autocorrelation for breathing rate and heart rate | n/a |

**Resampling.** Every model takes 16 kHz mono, loaded with `librosa.load(sr=16000)` (soxr
high quality), which is OPERA-CE's own loader.
- **SPRSound** (8 kHz) is upsampled 2×. It has no content above 4 kHz.
- **CirCor** (4 kHz) is upsampled 4×. It has no content above 2 kHz.
- **ICBHI** (44.1 kHz) is downsampled to 16 kHz, so it keeps content up to 8 kHz. It was also
  tested band-limited to 4 kHz, to match SPRSound.
- **Within each model:**
  - YAMNet computes its own 64-band log-mel (125–7,500 Hz) internally;
  - OPERA-CE uses librosa's mel spectrogram;
  - HeAR uses its official mel-PCEN front end.

**Evaluation.**
- **Cross-validation:** 5-fold, stratified and grouped by patient, so no child is ever in both
  training and test. A nested 3-fold inner loop on the training folds chooses the
  regularisation strength and the decision threshold (Youden's J).
- **Unit of analysis:** a recording for SPRSound and ICBHI; a patient for CirCor.
- **CIs:** 95%, from 1,000 bootstrap resamples of patients.
- **Zero-shot thresholds** are also set on the training folds.

**Phone-degradation test.** Each model is trained on clean audio, then tested on degraded
audio. The degradations, applied at 16 kHz:
- **High-pass** at 100 Hz and at 150 Hz, as phone microphones and their processing do.
- **Clinic-like noise** at 10 dB and at 5 dB SNR:
  - pink noise plus a weak 50 Hz mains hum;
  - limited to each dataset's own band, so the SNR is in-band;
  - stationary, unlike real clinic noise.
- **Level −20 dB**, against a −70 dBFS sensor noise floor, with 16-bit quantisation.

**Fair comparison with real phone audio.** Coswara's phone audio was band-limited to 4 kHz
and to 2 kHz before comparing it with SPRSound and CirCor.

## Results

AUROC with 95% CI, on clean audio. Sensitivity and specificity with their CIs, and all age
bands, are in [`results/tables.md`](results/tables.md).

| Task | Patients (positive) | (a) App int8, zero-shot | (a) Float, zero-shot | (b) YAMNet + LR | (c) OPERA-CE + LR | (d) HeAR + LR |
|---|---|---|---|---|---|---|
| Weight licence | | Apache 2.0 | Apache 2.0 | Apache 2.0 | CC BY-NC 4.0 | HAI-DEF terms |
| **Stridor (EXPLORATORY, 9 patients)** | 859 (9) | 0.68 (0.54–0.84); respiratory score 0.78 (0.61–0.93) | 0.51 (0.39–0.69) | 0.81 (0.56–0.93) | 0.62 (0.50–0.77) | HEAR_stridor |
| Wheeze | 859 (157) | 0.62 (0.59–0.65); respiratory score 0.71 (0.66–0.76) | 0.62 (0.57–0.66) | **0.86 (0.83–0.90)** | 0.76 (0.71–0.81) | HEAR_wheeze |
| Crackles | 859 (255) | 0.50 (0.47–0.54) | 0.42 (0.38–0.46) | **0.79 (0.77–0.82)** | 0.71 (0.68–0.74) | HEAR_crackle |
| Murmur, Present vs Absent | 874 (179) | 0.44 (0.39–0.49) | 0.43 (0.38–0.48) | **0.81 (0.77–0.85)** | 0.76 (0.71–0.80) | HEAR_murmur |
| Outcome, Abnormal vs Normal | 942 (456) | 0.46 (0.42–0.50) | 0.44 (0.40–0.48) | 0.64 (0.60–0.68) | 0.62 (0.59–0.66) | HEAR_outcome |

Sensitivity and specificity at the threshold chosen in training, for the best model (b):

| Task | Weight licence | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|
| Stridor (EXPLORATORY, 9 patients) | Apache 2.0 | 0.69 (0.33–0.88) | 0.89 (0.88–0.91) |
| Wheeze | Apache 2.0 | 0.73 (0.67–0.80) | 0.83 (0.81–0.85) |
| Crackles | Apache 2.0 | 0.70 (0.66–0.74) | 0.74 (0.72–0.76) |
| Murmur | Apache 2.0 | 0.59 (0.53–0.66) | 0.88 (0.86–0.91) |
| Outcome | Apache 2.0 | 0.36 (0.32–0.41) | 0.84 (0.80–0.87) |

### The app's int8 model against Google's float model (decision 4)

Zero-shot, the app's int8 model and the float model are equally poor. Apart from
exploratory stridor, their AUROCs differ by at most 0.08, and every one is within 0.12 of
chance:

| Task | App int8 | Float |
|---|---|---|
| Wheeze | 0.62 | 0.62 |
| Crackles | 0.50 | 0.42 |
| Murmur | 0.44 | 0.43 |

So int8 quantisation is not the problem. YAMNet's AudioSet classes don't recognise
stethoscope sounds.

The gap that matters is between zero-shot use (a) and a trained classifier on the embeddings
(b): +0.24 AUROC for wheeze, +0.29 for crackles, +0.37 for murmur.

The app's model file is the classification variant, and it does not output embeddings. To
use (b), the app needs Google's embeddings variant instead:
- the official float file is 16 MB;
- the app's current int8 classification file is 4.1 MB.

The int8 embeddings were not tested here.

### By age band (model b, clean, AUROC)

| Task | Weight licence | <2 mo | 2–11 mo | 1–5 y | 6+ y |
|---|---|---|---|---|---|
| Stridor (EXPLORATORY) | Apache 2.0 | 2 pts, 0 positive: – | 55 pts (3+): 0.81 (0.56–0.95) | 481 pts (5+): 0.76 (0.36–0.96) | 324 pts (1+): not interpretable |
| Wheeze | Apache 2.0 | 2 pts, 0 positive: – | 55 (26+): 0.79 (0.71–0.85) | 481 (98+): 0.86 (0.81–0.90) | 324 (33+): 0.83 (0.78–0.89) |
| Crackles | Apache 2.0 | 2 (1+): not interpretable | 55 (24+): 0.75 (0.68–0.82) | 481 (144+): 0.81 (0.78–0.85) | 324 (86+): 0.77 (0.73–0.80) |

CirCor gives age categories, not ages:

| Task | Weight licence | Neonate (0–27 d) | Infant (28 d–1 y) | Child (1–11 y) | Adolescent (12–18 y) |
|---|---|---|---|---|---|
| Murmur | Apache 2.0 | 5 (1+): not interpretable | 101 (25+): 0.68 (0.54–0.83) | 627 (132+): 0.83 (0.78–0.87) | 69 (16+): 0.82 (0.68–0.94) |
| Outcome | Apache 2.0 | 6 (3+): not interpretable | 126 (79+): 0.62 (0.52–0.72) | 664 (321+): 0.62 (0.58–0.66) | 72 (40+): 0.63 (0.50–0.76) |

Murmur detection is weaker in infants (0.68) than in older children (0.83). Infant heart
rates are faster and the sounds closer together, which is the same reason the heart-rate
counter fails in infants (below).

### External validation: trained on SPRSound, tested on ICBHI children

| Task | Model | Weight licence | ICBHI full band | ICBHI band-limited to 4 kHz |
|---|---|---|---|---|
| Wheeze (13 children, 18 recordings positive) | (b) YAMNet + LR | Apache 2.0 | 0.36 (0.21–0.50) | 0.41 (0.27–0.54) |
| | (c) OPERA-CE + LR (pretrained on ICBHI: optimistic) | CC BY-NC 4.0 | 0.67 (0.55–0.80) | 0.69 (0.55–0.83) |
| | (d) HeAR + LR | HAI-DEF terms | HEAR_icbhi_wheeze_full | HEAR_icbhi_wheeze_4k |
| Crackles (17 children, 24 recordings positive) | (b) YAMNet + LR | Apache 2.0 | 0.58 (0.44–0.72) | 0.54 (0.42–0.68) |
| | (c) OPERA-CE + LR (pretrained on ICBHI: optimistic) | CC BY-NC 4.0 | 0.48 (0.35–0.64) | 0.50 (0.34–0.65) |
| | (d) HeAR + LR | HAI-DEF terms | HEAR_icbhi_crackle_full | HEAR_icbhi_crackle_4k |

**What this shows:**
- The within-dataset results don't transfer to a different stethoscope, hospital and
  annotation team.
- Cutting ICBHI's audio to 4 kHz (SPRSound's band) changed little. The failure isn't about
  the bandwidth; it's about everything else that differs (device, chest sites, labelling,
  patients).
- The test is small (49 children), so the CIs are wide. Still, the YAMNet wheeze result is
  below chance, with an upper CI bound of 0.54.
- OPERA-CE's 0.67–0.69 for wheeze is the only result above chance, and it is the one biased
  by pretraining on ICBHI.

### Phone-degradation test (models trained on clean audio)

AUROC for model (b), YAMNet + LR (Apache 2.0). Model (c), OPERA-CE (CC BY-NC 4.0), is in
`results/tables.md` and degrades faster.

| Task | Clean | High-pass 100 Hz | High-pass 150 Hz | Noise 10 dB | Noise 5 dB | Level −20 dB |
|---|---|---|---|---|---|---|
| Stridor (EXPLORATORY) | 0.81 | 0.80 | 0.79 | 0.56 | 0.65 | 0.69 |
| Wheeze | 0.86 | 0.87 | 0.85 | 0.53 | 0.55 | 0.67 |
| Crackles | 0.79 | 0.79 | 0.78 | 0.43 | 0.39 | 0.54 |
| Murmur | 0.81 | 0.81 | 0.81 | 0.72 | 0.69 | 0.56 |
| Outcome | 0.64 | 0.64 | 0.63 | 0.62 | 0.59 | 0.40 |

- **High-pass filtering hardly matters for YAMNet.** For OPERA-CE it does: at 150 Hz, murmur
  drops from 0.76 to 0.61 and crackles from 0.71 to 0.56.
- **Noise and low level break both models' respiratory results.**
  - The scores drift, so a threshold set on clean audio flags almost everything or almost
    nothing. For example, wheeze under noise at 10 dB is sensitivity 0.91 and specificity
    0.19.
  - AUROC also falls to about chance, so the information is lost, not just shifted.
  - Murmur survives noise better (0.69–0.72).
- **Training included no noisy audio.** Training with noise mixed in (augmentation) is the
  obvious next step. Even so, the drop shows how much the recording conditions matter.
- **HeAR was tested on clean audio only,** for compute reasons (about 1.2 s per 2 s window on
  this CPU).

**Simulated degradation against real phone audio (Coswara).** Medians, with Coswara
band-limited to each dataset's band so the comparison is fair:

| Audio | Energy below 150 Hz | Spectral centroid | Frame-energy range |
|---|---|---|---|
| Coswara phone, limited to 4 kHz | 1% | 1,146 Hz | 47 dB |
| SPRSound clean / high-pass 150 Hz | 44% / 7% | 174 / 222 Hz | 19 / 23 dB |
| Coswara phone, limited to 2 kHz | 2% | 670 Hz | 45 dB |
| CirCor clean / high-pass 150 Hz | 39% / 1% | 330 / 495 Hz | 21 / 23 dB |

- The 150 Hz high-pass brings the low-frequency share close to a real phone's.
- Real phone audio is still much brighter and more dynamic. That is partly because Coswara is
  breathing at the mouth, not chest sounds through tissue.
- So the simulated "phone" is mild compared with a real phone in air.
- Whether a phone pressed to the chest behaves more like a stethoscope can only be measured
  locally.

### OPERA-CE long clips: which fixed-length rule (decision 10)

OPERA-CE's official code embeds a whole clip of any length. The app needs a fixed input
length. Two rules were compared with the whole-clip embedding, using SPRSound (5,890 of 5,950
clips longer than 8 s after trimming) and CirCor (3,128 of 3,163):

| Rule | Cosine to whole-clip, median (5th percentile): SPRSound | CirCor | AUROC: wheeze / crackles / murmur / Outcome |
|---|---|---|---|
| Whole clip (official) | 1 | 1 | 0.76 / 0.71 / 0.76 / 0.62 |
| **Mean of 8 s windows** | 0.998 (0.973) | **0.988 (0.946)** | 0.75 / 0.70 / 0.74 / **0.64** |
| First 8 s after trimming | 0.998 (0.974) | 0.981 (0.918) | 0.75 / 0.69 / 0.72 / 0.59 |

**Recommendation: if the app keeps OPERA-CE, average the embeddings of consecutive 8 s
windows.**
- It stays closer to the official embedding on long heart recordings.
- It matches or beats "first 8 s" on every task except stridor. Stridor is exploratory, and
  its CIs overlap: 0.58 against 0.68.
- It uses the whole recording, so a noisy first few seconds matters less.

Drop a final remainder shorter than 2 s, as done here.

### Non-AI baselines (experiment e)

| Measure | Reference | Condition | Median error | Within ±5 /min | Weight licence |
|---|---|---|---|---|---|
| Breathing rate, ICBHI children (76 recordings, 49 children) | Annotated breath cycles | clean / 4 kHz / high-pass 150 Hz | 1.2 / 1.2 / 1.1 breaths/min | 70% | n/a (no model) |
| | | noise 10 dB / 5 dB | 5.7 / 5.5 | 49% / 46% | n/a |
| Breathing rate, SPRSound (3,050 recordings) | Event-onset rate (proxy) | clean | 8.7 | 41% | n/a |
| Heart rate, CirCor (3,162 recordings) | S1 segmentation | clean | 5.3 beats/min | 49% (55% within ±10%) | n/a |
| | | high-pass 150 Hz | 43.4 | 23% | n/a |
| | | noise 10 dB / 5 dB | 5.5 / 5.5 | 49% | n/a |

- **Breathing rate.** On ICBHI's true breath-cycle reference, the plain envelope counter works
  in quiet conditions. Noise roughly quadruples its median error. The SPRSound figure is
  weaker mainly because its reference is a proxy (SPRSound never says one event is one breath)
  and its clips are short, about 9 s.
- **Heart rate.**
  - The counter works in older children: about 55% of recordings within ±5 beats/min.
  - It fails in infants (median error 46) and neonates (median 42): their fast rates and
    close-together sounds confuse it.
  - It fails completely once the audio is high-passed at 150 Hz.
  - A heart-rate feature for young infants would need a better method and, for phone
    capture, a microphone that keeps low frequencies.
- **Rhythm regularity.** The estimated beat-to-beat variability barely tracks the reference
  (Spearman ρ = 0.13). CirCor has no arrhythmia labels, so regularity can't be validated here
  anyway.

## Capture-method coverage, per task

| Task | (a) Phone in air, a few cm from the chest | (b) Phone pressed to the chest | (c) Stethoscope |
|---|---|---|---|
| Stridor (exploratory) | none | none | SPRSound (9 patients) |
| Wheeze | none | none | SPRSound; ICBHI children (external) |
| Crackles | none | none | SPRSound; ICBHI children (external) |
| Murmur / Outcome | none | none | CirCor |
| Breathing rate | simulated only | none | ICBHI children (annotated cycles); SPRSound (proxy) |
| Heart rate | simulated only | none | CirCor |
| Grunting | none | none | none |

**Every result in this report is evidence for (c), the stethoscope, only.** The degradation
test simulates some effects of a phone; it doesn't measure a phone.

## Licences

Every results table has a "Weight licence" column.

- **YAMNet:** Apache 2.0. It can be used in any product, commercial or not, with attribution.
- **OPERA-CE:** the weights are **CC BY-NC 4.0**.
  - **They can't be used in a commercial product without permission from their authors or
    retraining** the model on data whose licence allows it.
  - The user states that Yoma is a non-commercial app, which is within the licence.
  - Charging for the app, licensing it, or deploying it through a commercial partner would
    each need that permission or new weights.
  - The OPERA code licence is separate from the weights licence.
- **HeAR:** Google's Health AI Developer Foundations (HAI-DEF) terms of use, not an open
  licence.
  - Access is gated, and the terms include a "Clinical Use" clause. Using HeAR in a tool that
    informs clinical decisions brings obligations under that clause, including validation and
    regulatory responsibilities on the deployer.
  - It was evaluated here for research, after the user obtained access. Read the terms in
    full before any deployment.
- **Datasets:**
  - SPRSound and Coswara: CC BY 4.0.
  - CirCor: ODC-By 1.0.
  - ICBHI: no licence stated beyond "freely available for research".
  - Training a deployed model on ICBHI needs that checked.

## Grunting: the gap, and the local recording protocol

**No obtainable dataset has labelled infant grunting.** Nothing was substituted. The
protocol below also produces the phone data (a and b) that every other task lacks.

- **Who:**
  - infants under 2 months at the Day 1, Day 7 and Week 6 postnatal visits;
  - sick young infants at CWCs and referral points, where grunting, wheeze and crackles are
    common enough to collect positives;
  - older children with wheeze or crackles, to test the tasks above on phones.
- **Recordings:** every patient is recorded with **all three methods** in one sitting:
  - (a) phone a few cm from the chest;
  - (b) phone pressed to the chest, microphone edge to the skin;
  - (c) stethoscope attachment.

  Randomise the order. Make each recording at least 60 s long, with the child calm where
  possible. Note who held the device and the device model.
- **Reference standard:**
  - A clinician's bedside judgement of grunting, wheeze and stridor (present or absent),
    made without seeing the AI output.
  - A 60-second breath count, the reference for breathing rate.
  - Two independent reviewers label sound events on the audio, with timestamps. A third
    reviewer resolves disagreements.
- **Synchronised video (OPTIONAL).**
  - Research team only.
  - Needs **separate parental consent and its own storage and retention rules**.
  - It helps reviewers tell grunting from crying or movement. The study works without it.
  - Listed separately so the ethics submission can include or exclude it.
- **Context to record:**
  - age in days, weight, SpO₂;
  - a 10 s noise-only clip before each recording, to measure ambient noise;
  - the setting.
- **Consent and data:**
  - Parental consent.
  - De-identified IDs, so recordings can be grouped by patient.
  - Audio never leaves the approved storage.

## Recommendation

**First task: wheeze** in children from 2 months up. Add crackles once that works.
- **Why wheeze:** it had the best and tightest result: AUROC 0.86 (0.83–0.90), with stable
  results in every age band that has data (0.79–0.86).
- **Why not the others:**
  - Murmur (0.81) is close behind, but a murmur alone isn't the clinical question; Outcome is,
    and Outcome reached only 0.64.
  - Stridor has too few patients.
  - Grunting has no data.

**Model: a logistic-regression classifier on YAMNet embeddings** (Google's embeddings
variant).
- It beat OPERA-CE on every task. HEAR_RECOMMENDATION
- Its weights are Apache 2.0.
- A YAMNet model already runs in the app.
- It barely changed under high-pass filtering.
- Retrain it on local recordings with noise augmentation before trusting it: the external
  validation and the noise test both show it does not generalise yet.
- Don't use the app's current zero-shot YAMNet scores as a detector.

**Hardware.** The evidence covers only a stethoscope (c). The first local study should
include:
- a low-cost stethoscope attachment or contact chest piece for the phone;
- **and** phone-only capture (a and b), so the gap can be measured directly.

Use one or two common phone models, the kind the CHOs actually have. Record at 16 kHz or
higher, with automatic gain control and noise suppression switched off if the phone allows.
The heart-rate and degradation results show why: removing low frequencies destroys heart
sounds, and noise is what hurts most.

**Sample size for the local study.**
- **Precision target:** sensitivity of about 85% to within ±7.5% (95% CI) needs about 90
  children with wheeze: n = 1.96² × 0.85 × 0.15 / 0.075² ≈ 87. Specificity of about 85% to
  within ±5% needs about 200 children without.
- **Allow for clustering:** about 1.5× for several recordings per child, so roughly **130
  positive and 300 negative children**.
- **Reaching the positive count:** if about 25% of recruited sick children wheeze, about 500
  children in total gives that.
- **Grunting:** a sensitivity of 90% within ±10% needs about 35 infants with grunting:
  1.96² × 0.9 × 0.1 / 0.1² ≈ 35. With clustering, about 50.
  - If 10% of recruited sick young infants grunt: about 500 infants.
  - If 20% grunt: about 250 infants.
  - A short pilot (about 50 infants) should measure the real rate before the main study is
    sized.
- **Every child is recorded with all three methods,** so the same children give the phone
  against stethoscope comparison with no extra recruitment.

## Limitations

- **Not newborns.** Only 2 SPRSound patients, 6 CirCor neonates and no ICBHI or Coswara
  patients are under 2 months.
- **Stridor is exploratory:** 9 patients, CIs from about 0.56 to 0.93.
- **Stethoscope only.** No public dataset covers phone capture. The degradation conditions are
  simulated and milder than a real phone in air.
- **Bandwidth gap.**
  - SPRSound (8 kHz) has nothing above 4 kHz, and CirCor (4 kHz) nothing above 2 kHz.
  - A full-band phone recording contains energy those models never saw in training: breath
    noise, voices and handling noise above 2–4 kHz.
  - The ICBHI test (full band against 4 kHz) changed little, but it is small.
  - Before deployment, either low-pass the app's audio to the training band or train on
    full-band local recordings. The first is simpler and was used for the fair Coswara
    comparison here.
- **One dataset per task for training.**
  - Within-dataset results are optimistic. The only external test (ICBHI) shows the models
    don't transfer.
  - Murmur and Outcome have no external test at all.
- **Labels.**
  - SPRSound labels come from one hospital's annotators.
  - CirCor's murmur label says nothing about whether the murmur is innocent.
  - The SPRSound breathing-rate reference is a proxy.
- **OPERA-CE was pretrained on ICBHI,** so its ICBHI result is biased upwards.
- **HeAR:**
  - It used an 8 s budget per recording (4 windows of 2 s), so long recordings were sampled,
    not covered.
  - It was tested on clean audio only.
  - The official PyTorch release (`google/hear-pytorch`) was used. All 392 weights loaded
    with none missing or unexpected. It was not compared numerically with the TensorFlow
    release.
- **Simple classifiers only:** a logistic regression on frozen embeddings, not fine-tuning.
  Fine-tuning may do better within a dataset. It does not fix the transfer problem.
- **Noise:** the simulated noise is stationary. Real clinics have voices, crying and handling
  noise, which are likely harder.

## Reproduce

```bash
cd research/acoustic
bash scripts/download_audio.sh circor sprsound coswara   # ICBHI is placed by hand in data/icbhi/
bash scripts/run_all.sh        # YAMNet and OPERA-CE embeddings, all conditions (resumable)
bash scripts/run_hear.sh       # ICBHI embeddings, then HeAR (needs HF_TOKEN in ../../.env)
.venv/bin/python -I scripts/evaluate.py         # cross-validation, external test, CIs
.venv/bin/python -I scripts/baselines.py        # breathing and heart rate
.venv/bin/python -I scripts/coswara_reference.py
.venv/bin/python -I scripts/make_tables.py      # results/tables.md
```

Audio, embeddings and model files are in `data/` and `cache/`, which are git-ignored.
