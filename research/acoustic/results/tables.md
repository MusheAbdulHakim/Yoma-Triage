
#### Stridor (SPRSound, per recording). EXPLORATORY: only 9 patients with stridor

| Experiment | Weight licence | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model [Wheeze (proxy: no stridor class)] | Apache 2.0 | 859 (9) | 5950 (29) | 0.68 (0.54–0.84) | 0.41 (0.14–0.74) | 0.94 (0.92–0.95) |
| (a) YAMNet zero-shot, app's int8 model, app's respiratory score | Apache 2.0 | 859 (9) | 5950 (29) | 0.78 (0.61–0.93) | 0.66 (0.28–1.00) | 0.65 (0.62–0.68) |
| (a) YAMNet zero-shot, official float model [Wheeze (proxy: no stridor class)] | Apache 2.0 | 859 (9) | 5950 (29) | 0.51 (0.39–0.69) | 0.66 (0.29–1.00) | 0.31 (0.28–0.34) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 859 (9) | 5950 (29) | 0.81 (0.56–0.93) | 0.69 (0.33–0.88) | 0.89 (0.88–0.91) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 859 (9) | 5950 (29) | 0.62 (0.50–0.77) | 0.52 (0.38–0.70) | 0.71 (0.69–0.73) |
| (c) OPERA-CE, mean of 8 s windows + LR | CC BY-NC 4.0 | 859 (9) | 5950 (29) | 0.58 (0.44–0.75) | 0.48 (0.33–0.73) | 0.76 (0.74–0.78) |
| (c) OPERA-CE, first 8 s + LR | CC BY-NC 4.0 | 859 (9) | 5950 (29) | 0.68 (0.58–0.81) | 0.52 (0.29–0.74) | 0.75 (0.73–0.77) |

#### Wheeze (SPRSound, per recording)

| Experiment | Weight licence | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model [Wheeze] | Apache 2.0 | 859 (157) | 5950 (606) | 0.62 (0.59–0.65) | 0.28 (0.21–0.34) | 0.96 (0.95–0.97) |
| (a) YAMNet zero-shot, app's int8 model, app's respiratory score | Apache 2.0 | 859 (157) | 5950 (606) | 0.71 (0.66–0.76) | 0.48 (0.40–0.55) | 0.83 (0.81–0.85) |
| (a) YAMNet zero-shot, official float model [Wheeze] | Apache 2.0 | 859 (157) | 5950 (606) | 0.62 (0.57–0.66) | 0.53 (0.44–0.60) | 0.69 (0.66–0.72) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 859 (157) | 5950 (606) | 0.86 (0.83–0.90) | 0.73 (0.67–0.80) | 0.83 (0.81–0.85) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 859 (157) | 5950 (606) | 0.76 (0.71–0.81) | 0.66 (0.58–0.74) | 0.72 (0.69–0.75) |
| (c) OPERA-CE, mean of 8 s windows + LR | CC BY-NC 4.0 | 859 (157) | 5950 (606) | 0.75 (0.70–0.80) | 0.64 (0.54–0.72) | 0.74 (0.71–0.76) |
| (c) OPERA-CE, first 8 s + LR | CC BY-NC 4.0 | 859 (157) | 5950 (606) | 0.75 (0.70–0.80) | 0.58 (0.48–0.67) | 0.80 (0.78–0.82) |

#### Crackles (SPRSound, per recording)

| Experiment | Weight licence | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model [Crackle] | Apache 2.0 | 859 (255) | 5950 (1251) | 0.50 (0.47–0.54) | 0.15 (0.11–0.20) | 0.89 (0.87–0.90) |
| (a) YAMNet zero-shot, app's int8 model, app's respiratory score | Apache 2.0 | 859 (255) | 5950 (1251) | 0.50 (0.46–0.54) | 0.13 (0.09–0.17) | 0.89 (0.88–0.91) |
| (a) YAMNet zero-shot, official float model [Crackle] | Apache 2.0 | 859 (255) | 5950 (1251) | 0.42 (0.38–0.46) | 1.00 (1.00–1.00) | 0.00 (0.00–0.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 859 (255) | 5950 (1251) | 0.79 (0.77–0.82) | 0.70 (0.66–0.74) | 0.74 (0.72–0.76) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 859 (255) | 5950 (1251) | 0.71 (0.68–0.74) | 0.62 (0.57–0.68) | 0.68 (0.65–0.70) |
| (c) OPERA-CE, mean of 8 s windows + LR | CC BY-NC 4.0 | 859 (255) | 5950 (1251) | 0.70 (0.67–0.73) | 0.62 (0.56–0.67) | 0.68 (0.65–0.70) |
| (c) OPERA-CE, first 8 s + LR | CC BY-NC 4.0 | 859 (255) | 5950 (1251) | 0.69 (0.66–0.72) | 0.64 (0.59–0.70) | 0.66 (0.63–0.68) |

#### Heart murmur, Present vs Absent (CirCor, per patient; Unknown excluded)

| Experiment | Weight licence | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model [Heart murmur] | Apache 2.0 | 874 (179) | 874 (179) | 0.44 (0.39–0.49) | 0.03 (0.01–0.06) | 0.97 (0.95–0.98) |
| (a) YAMNet zero-shot, official float model [Heart murmur] | Apache 2.0 | 874 (179) | 874 (179) | 0.43 (0.38–0.48) | 0.02 (0.00–0.04) | 0.97 (0.96–0.98) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 874 (179) | 874 (179) | 0.81 (0.77–0.85) | 0.59 (0.53–0.66) | 0.88 (0.86–0.91) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 874 (179) | 874 (179) | 0.76 (0.71–0.80) | 0.56 (0.49–0.63) | 0.81 (0.78–0.84) |
| (c) OPERA-CE, mean of 8 s windows + LR | CC BY-NC 4.0 | 874 (179) | 874 (179) | 0.74 (0.70–0.78) | 0.59 (0.51–0.65) | 0.79 (0.75–0.82) |
| (c) OPERA-CE, first 8 s + LR | CC BY-NC 4.0 | 874 (179) | 874 (179) | 0.72 (0.68–0.77) | 0.53 (0.46–0.60) | 0.79 (0.76–0.82) |

#### Outcome, Abnormal vs Normal (CirCor, per patient)

| Experiment | Weight licence | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model [Heart murmur (proxy)] | Apache 2.0 | 942 (456) | 942 (456) | 0.46 (0.42–0.50) | 0.79 (0.75–0.83) | 0.21 (0.17–0.24) |
| (a) YAMNet zero-shot, official float model [Heart murmur (proxy)] | Apache 2.0 | 942 (456) | 942 (456) | 0.44 (0.40–0.48) | 0.01 (0.00–0.02) | 1.00 (0.99–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 942 (456) | 942 (456) | 0.64 (0.60–0.68) | 0.36 (0.32–0.41) | 0.84 (0.80–0.87) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 942 (456) | 942 (456) | 0.62 (0.59–0.66) | 0.47 (0.42–0.52) | 0.70 (0.66–0.74) |
| (c) OPERA-CE, mean of 8 s windows + LR | CC BY-NC 4.0 | 942 (456) | 942 (456) | 0.64 (0.60–0.67) | 0.47 (0.42–0.51) | 0.73 (0.69–0.77) |
| (c) OPERA-CE, first 8 s + LR | CC BY-NC 4.0 | 942 (456) | 942 (456) | 0.59 (0.55–0.62) | 0.37 (0.32–0.41) | 0.81 (0.78–0.84) |

### By age band


#### Stridor (SPRSound, per recording). EXPLORATORY: only 9 patients with stridor

| Experiment | Weight licence | Age band | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 1-5 y | 481 (5) | 3255 (18) | 0.55 (0.46–0.73) | 0.17 (0.00–0.50) | 0.93 (0.91–0.95) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 2-11 mo | 55 (3) | 349 (10) | 0.75 (0.63–0.92) | 0.80 (0.67–1.00) | 0.71 (0.63–0.80) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 6+ y | 324 (1) | 2336 (1) | 1.00 (0.99–1.00) | 1.00 (1.00–1.00) | 0.98 (0.97–0.99) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | <2 mo | 2 (0) | 10 (0) | – | – | 0.90 (0.83–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 1-5 y | 481 (5) | 3255 (18) | 0.76 (0.36–0.96) | 0.61 (0.00–0.94) | 0.88 (0.86–0.90) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 2-11 mo | 55 (3) | 349 (10) | 0.81 (0.56–0.95) | 0.80 (0.67–1.00) | 0.76 (0.69–0.83) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 6+ y | 324 (1) | 2336 (1) | 0.93 (0.91–0.94) | 1.00 (1.00–1.00) | 0.93 (0.92–0.95) |
| (b) YAMNet embeddings + LR | Apache 2.0 | <2 mo | 2 (0) | 10 (0) | – | – | 1.00 (1.00–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 1-5 y | 481 (5) | 3255 (18) | 0.58 (0.32–0.69) | 0.39 (0.00–0.47) | 0.70 (0.67–0.73) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 2-11 mo | 55 (3) | 349 (10) | 0.49 (0.31–0.85) | 0.70 (0.50–1.00) | 0.38 (0.29–0.48) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 6+ y | 324 (1) | 2336 (1) | 0.97 (0.97–0.98) | 1.00 (1.00–1.00) | 0.78 (0.75–0.81) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | <2 mo | 2 (0) | 10 (0) | – | – | 0.80 (0.67–1.00) |

#### Wheeze (SPRSound, per recording)

| Experiment | Weight licence | Age band | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 1-5 y | 481 (98) | 3255 (366) | 0.61 (0.57–0.64) | 0.27 (0.19–0.34) | 0.95 (0.94–0.96) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 2-11 mo | 55 (26) | 349 (120) | 0.64 (0.56–0.74) | 0.48 (0.31–0.66) | 0.79 (0.72–0.87) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 6+ y | 324 (33) | 2336 (120) | 0.54 (0.52–0.57) | 0.10 (0.05–0.16) | 0.99 (0.98–0.99) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | <2 mo | 2 (0) | 10 (0) | – | – | 0.90 (0.83–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 1-5 y | 481 (98) | 3255 (366) | 0.86 (0.81–0.90) | 0.75 (0.67–0.82) | 0.81 (0.77–0.84) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 2-11 mo | 55 (26) | 349 (120) | 0.79 (0.71–0.85) | 0.91 (0.82–0.96) | 0.45 (0.34–0.56) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 6+ y | 324 (33) | 2336 (120) | 0.83 (0.78–0.89) | 0.51 (0.38–0.66) | 0.90 (0.88–0.92) |
| (b) YAMNet embeddings + LR | Apache 2.0 | <2 mo | 2 (0) | 10 (0) | – | – | 0.90 (0.83–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 1-5 y | 481 (98) | 3255 (366) | 0.76 (0.71–0.80) | 0.69 (0.60–0.78) | 0.69 (0.65–0.72) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 2-11 mo | 55 (26) | 349 (120) | 0.72 (0.64–0.81) | 0.88 (0.79–0.96) | 0.32 (0.21–0.44) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 6+ y | 324 (33) | 2336 (120) | 0.61 (0.51–0.74) | 0.35 (0.19–0.56) | 0.80 (0.77–0.83) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | <2 mo | 2 (0) | 10 (0) | – | – | 0.90 (0.83–1.00) |

#### Crackles (SPRSound, per recording)

| Experiment | Weight licence | Age band | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 1-5 y | 481 (144) | 3255 (738) | 0.50 (0.45–0.56) | 0.18 (0.11–0.25) | 0.87 (0.84–0.89) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 2-11 mo | 55 (24) | 349 (106) | 0.55 (0.47–0.65) | 0.34 (0.25–0.48) | 0.71 (0.59–0.83) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | 6+ y | 324 (86) | 2336 (404) | 0.47 (0.44–0.51) | 0.05 (0.02–0.08) | 0.94 (0.92–0.95) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | <2 mo | 2 (1) | 10 (3) | 0.50 (0.50–0.67) | 0.00 (0.00–0.00) | 0.86 (0.83–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 1-5 y | 481 (144) | 3255 (738) | 0.81 (0.78–0.85) | 0.74 (0.68–0.79) | 0.74 (0.71–0.76) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 2-11 mo | 55 (24) | 349 (106) | 0.75 (0.68–0.82) | 0.85 (0.78–0.92) | 0.50 (0.41–0.59) |
| (b) YAMNet embeddings + LR | Apache 2.0 | 6+ y | 324 (86) | 2336 (404) | 0.77 (0.73–0.80) | 0.61 (0.53–0.67) | 0.77 (0.74–0.80) |
| (b) YAMNet embeddings + LR | Apache 2.0 | <2 mo | 2 (1) | 10 (3) | 0.38 (0.33–0.38) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 1-5 y | 481 (144) | 3255 (738) | 0.72 (0.69–0.75) | 0.64 (0.57–0.70) | 0.68 (0.65–0.71) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 2-11 mo | 55 (24) | 349 (106) | 0.68 (0.59–0.76) | 0.82 (0.71–0.90) | 0.44 (0.36–0.54) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | 6+ y | 324 (86) | 2336 (404) | 0.67 (0.61–0.73) | 0.54 (0.44–0.65) | 0.69 (0.65–0.73) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | <2 mo | 2 (1) | 10 (3) | 0.86 (0.00–0.86) | 0.33 (0.33–0.33) | 0.86 (0.00–1.00) |

#### Heart murmur, Present vs Absent (CirCor, per patient; Unknown excluded)

| Experiment | Weight licence | Age band | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Adolescent (12-18 y) | 69 (16) | 69 (16) | 0.35 (0.19–0.51) | 0.00 (0.00–0.00) | 0.98 (0.94–1.00) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Child (1-11 y) | 627 (132) | 627 (132) | 0.40 (0.34–0.46) | 0.04 (0.01–0.07) | 0.96 (0.94–0.97) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Infant (28 d-1 y) | 101 (25) | 101 (25) | 0.58 (0.44–0.71) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Neonate (0-27 d) | 5 (1) | 5 (1) | 0.75 (0.25–1.00) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | unknown | 72 (5) | 72 (5) | 0.62 (0.21–0.94) | 0.20 (0.00–0.67) | 0.99 (0.95–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Adolescent (12-18 y) | 69 (16) | 69 (16) | 0.82 (0.68–0.94) | 0.50 (0.25–0.74) | 0.94 (0.88–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Child (1-11 y) | 627 (132) | 627 (132) | 0.83 (0.78–0.87) | 0.61 (0.53–0.69) | 0.88 (0.86–0.91) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Infant (28 d-1 y) | 101 (25) | 101 (25) | 0.68 (0.54–0.83) | 0.56 (0.38–0.75) | 0.82 (0.73–0.90) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Neonate (0-27 d) | 5 (1) | 5 (1) | 0.75 (0.25–1.00) | 1.00 (1.00–1.00) | 0.75 (0.33–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | unknown | 72 (5) | 72 (5) | 0.84 (0.69–0.98) | 0.40 (0.00–1.00) | 0.93 (0.85–0.98) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Adolescent (12-18 y) | 69 (16) | 69 (16) | 0.69 (0.53–0.85) | 0.50 (0.27–0.75) | 0.77 (0.66–0.88) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Child (1-11 y) | 627 (132) | 627 (132) | 0.76 (0.70–0.81) | 0.57 (0.48–0.64) | 0.81 (0.78–0.85) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Infant (28 d-1 y) | 101 (25) | 101 (25) | 0.73 (0.58–0.86) | 0.60 (0.40–0.80) | 0.72 (0.62–0.82) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Neonate (0-27 d) | 5 (1) | 5 (1) | 0.25 (0.00–0.75) | 0.00 (0.00–0.00) | 0.75 (0.25–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | unknown | 72 (5) | 72 (5) | 0.78 (0.35–1.00) | 0.60 (0.00–1.00) | 0.93 (0.86–0.99) |

#### Outcome, Abnormal vs Normal (CirCor, per patient)

| Experiment | Weight licence | Age band | Patients (positive) | Units (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Adolescent (12-18 y) | 72 (40) | 72 (40) | 0.44 (0.31–0.56) | 0.70 (0.56–0.83) | 0.16 (0.04–0.30) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Child (1-11 y) | 664 (321) | 664 (321) | 0.40 (0.35–0.45) | 0.78 (0.74–0.83) | 0.20 (0.16–0.24) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Infant (28 d-1 y) | 126 (79) | 126 (79) | 0.57 (0.47–0.67) | 0.89 (0.81–0.95) | 0.26 (0.14–0.38) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | Neonate (0-27 d) | 6 (3) | 6 (3) | 0.78 (0.20–1.00) | 0.33 (0.00–1.00) | 0.33 (0.00–1.00) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | unknown | 74 (13) | 74 (13) | 0.65 (0.49–0.78) | 0.85 (0.60–1.00) | 0.21 (0.11–0.32) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Adolescent (12-18 y) | 72 (40) | 72 (40) | 0.63 (0.50–0.76) | 0.25 (0.12–0.40) | 1.00 (1.00–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Child (1-11 y) | 664 (321) | 664 (321) | 0.62 (0.58–0.66) | 0.35 (0.30–0.40) | 0.84 (0.80–0.88) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Infant (28 d-1 y) | 126 (79) | 126 (79) | 0.62 (0.52–0.72) | 0.51 (0.40–0.62) | 0.66 (0.51–0.79) |
| (b) YAMNet embeddings + LR | Apache 2.0 | Neonate (0-27 d) | 6 (3) | 6 (3) | 0.67 (0.11–1.00) | 0.33 (0.00–1.00) | 1.00 (1.00–1.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | unknown | 74 (13) | 74 (13) | 0.43 (0.25–0.62) | 0.15 (0.00–0.38) | 0.89 (0.80–0.96) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Adolescent (12-18 y) | 72 (40) | 72 (40) | 0.52 (0.39–0.65) | 0.30 (0.17–0.45) | 0.88 (0.76–0.97) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Child (1-11 y) | 664 (321) | 664 (321) | 0.62 (0.57–0.66) | 0.44 (0.39–0.49) | 0.71 (0.66–0.75) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Infant (28 d-1 y) | 126 (79) | 126 (79) | 0.61 (0.51–0.71) | 0.72 (0.61–0.83) | 0.45 (0.31–0.59) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | Neonate (0-27 d) | 6 (3) | 6 (3) | 0.67 (0.12–1.00) | 0.67 (0.00–1.00) | 0.33 (0.00–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | unknown | 74 (13) | 74 (13) | 0.44 (0.23–0.65) | 0.15 (0.00–0.38) | 0.82 (0.72–0.92) |

### External validation: trained on SPRSound, tested on ICBHI 2017 children


#### Wheeze (per recording; 49 children, 76 recordings)

| Experiment | Weight licence | ICBHI audio | Patients (positive) | Recordings (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | full band (44.1 kHz) | 49 (13) | 76 (18) | 0.49 (0.33–0.65) | 0.56 (0.35–0.79) | 0.47 (0.31–0.62) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | band-limited to 4 kHz (as SPRSound) | 49 (13) | 76 (18) | 0.47 (0.32–0.63) | 0.67 (0.47–0.89) | 0.31 (0.17–0.46) |
| (a) YAMNet zero-shot, official float model | Apache 2.0 | full band (44.1 kHz) | 49 (13) | 76 (18) | 0.47 (0.34–0.60) | 0.72 (0.55–0.89) | 0.17 (0.08–0.28) |
| (a) YAMNet zero-shot, official float model | Apache 2.0 | band-limited to 4 kHz (as SPRSound) | 49 (13) | 76 (18) | 0.54 (0.42–0.66) | 0.83 (0.67–1.00) | 0.24 (0.12–0.37) |
| (b) YAMNet embeddings + LR | Apache 2.0 | full band (44.1 kHz) | 49 (13) | 76 (18) | 0.36 (0.21–0.50) | 0.56 (0.31–0.79) | 0.36 (0.24–0.49) |
| (b) YAMNet embeddings + LR | Apache 2.0 | band-limited to 4 kHz (as SPRSound) | 49 (13) | 76 (18) | 0.41 (0.27–0.54) | 0.44 (0.21–0.68) | 0.33 (0.20–0.45) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | full band (44.1 kHz) | 49 (13) | 76 (18) | 0.67 (0.55–0.80) | 0.56 (0.33–0.78) | 0.59 (0.44–0.72) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | band-limited to 4 kHz (as SPRSound) | 49 (13) | 76 (18) | 0.69 (0.55–0.83) | 0.28 (0.09–0.50) | 0.81 (0.69–0.92) |

#### Crackle (per recording; 49 children, 76 recordings)

| Experiment | Weight licence | ICBHI audio | Patients (positive) | Recordings (positive) | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|---|---|
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | full band (44.1 kHz) | 49 (17) | 76 (24) | 0.46 (0.33–0.58) | 0.54 (0.33–0.71) | 0.48 (0.34–0.62) |
| (a) YAMNet zero-shot, app's int8 model | Apache 2.0 | band-limited to 4 kHz (as SPRSound) | 49 (17) | 76 (24) | 0.45 (0.30–0.58) | 0.62 (0.36–0.81) | 0.35 (0.20–0.48) |
| (a) YAMNet zero-shot, official float model | Apache 2.0 | full band (44.1 kHz) | 49 (17) | 76 (24) | 0.48 (0.34–0.60) | 1.00 (1.00–1.00) | 0.00 (0.00–0.00) |
| (a) YAMNet zero-shot, official float model | Apache 2.0 | band-limited to 4 kHz (as SPRSound) | 49 (17) | 76 (24) | 0.55 (0.40–0.69) | 1.00 (1.00–1.00) | 0.00 (0.00–0.00) |
| (b) YAMNet embeddings + LR | Apache 2.0 | full band (44.1 kHz) | 49 (17) | 76 (24) | 0.58 (0.44–0.72) | 0.33 (0.14–0.59) | 0.73 (0.61–0.84) |
| (b) YAMNet embeddings + LR | Apache 2.0 | band-limited to 4 kHz (as SPRSound) | 49 (17) | 76 (24) | 0.54 (0.42–0.68) | 0.29 (0.13–0.48) | 0.79 (0.65–0.92) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | full band (44.1 kHz) | 49 (17) | 76 (24) | 0.48 (0.35–0.64) | 0.42 (0.22–0.63) | 0.52 (0.35–0.70) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | band-limited to 4 kHz (as SPRSound) | 49 (17) | 76 (24) | 0.50 (0.34–0.65) | 0.96 (0.86–1.00) | 0.08 (0.02–0.15) |

### Phone-degradation test (models trained on clean audio)


#### Stridor (SPRSound, per recording). EXPLORATORY: only 9 patients with stridor

| Experiment | Weight licence | Condition | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|
| (b) YAMNet embeddings + LR | Apache 2.0 | clean | 0.81 (0.56–0.93) | 0.69 (0.33–0.88) | 0.89 (0.88–0.91) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 100 Hz | 0.80 (0.55–0.93) | 0.66 (0.29–0.88) | 0.90 (0.88–0.91) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 150 Hz | 0.79 (0.55–0.93) | 0.69 (0.33–0.88) | 0.84 (0.83–0.86) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 10 dB SNR | 0.56 (0.48–0.63) | 0.28 (0.11–0.45) | 0.71 (0.68–0.75) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 5 dB SNR | 0.65 (0.55–0.72) | 0.48 (0.25–0.64) | 0.74 (0.70–0.77) |
| (b) YAMNet embeddings + LR | Apache 2.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.69 (0.45–0.82) | 0.38 (0.07–0.67) | 0.82 (0.79–0.84) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clean | 0.62 (0.50–0.77) | 0.52 (0.38–0.70) | 0.71 (0.69–0.73) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 100 Hz | 0.60 (0.50–0.76) | 0.52 (0.36–0.73) | 0.63 (0.61–0.66) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 150 Hz | 0.43 (0.26–0.71) | 0.45 (0.20–0.87) | 0.50 (0.47–0.54) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 10 dB SNR | 0.41 (0.21–0.71) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 5 dB SNR | 0.44 (0.24–0.73) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.65 (0.45–0.81) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |

#### Wheeze (SPRSound, per recording)

| Experiment | Weight licence | Condition | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|
| (b) YAMNet embeddings + LR | Apache 2.0 | clean | 0.86 (0.83–0.90) | 0.73 (0.67–0.80) | 0.83 (0.81–0.85) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 100 Hz | 0.87 (0.83–0.90) | 0.73 (0.67–0.80) | 0.83 (0.81–0.85) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 150 Hz | 0.85 (0.82–0.88) | 0.79 (0.74–0.85) | 0.74 (0.72–0.77) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 10 dB SNR | 0.53 (0.50–0.57) | 0.91 (0.88–0.94) | 0.19 (0.17–0.21) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 5 dB SNR | 0.55 (0.52–0.58) | 0.94 (0.91–0.96) | 0.13 (0.11–0.15) |
| (b) YAMNet embeddings + LR | Apache 2.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.67 (0.61–0.72) | 0.06 (0.03–0.09) | 0.99 (0.99–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clean | 0.76 (0.71–0.81) | 0.66 (0.58–0.74) | 0.72 (0.69–0.75) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 100 Hz | 0.76 (0.71–0.80) | 0.78 (0.72–0.85) | 0.56 (0.53–0.58) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 150 Hz | 0.65 (0.59–0.71) | 0.98 (0.96–0.99) | 0.05 (0.04–0.05) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 10 dB SNR | 0.51 (0.46–0.55) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 5 dB SNR | 0.54 (0.49–0.59) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.53 (0.47–0.58) | 0.00 (0.00–0.00) | 1.00 (1.00–1.00) |

#### Crackles (SPRSound, per recording)

| Experiment | Weight licence | Condition | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|
| (b) YAMNet embeddings + LR | Apache 2.0 | clean | 0.79 (0.77–0.82) | 0.70 (0.66–0.74) | 0.74 (0.72–0.76) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 100 Hz | 0.79 (0.77–0.82) | 0.71 (0.66–0.75) | 0.73 (0.71–0.75) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 150 Hz | 0.78 (0.75–0.80) | 0.74 (0.70–0.78) | 0.66 (0.64–0.68) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 10 dB SNR | 0.43 (0.39–0.47) | 0.04 (0.02–0.05) | 0.96 (0.95–0.96) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 5 dB SNR | 0.39 (0.35–0.43) | 0.04 (0.03–0.05) | 0.92 (0.92–0.93) |
| (b) YAMNet embeddings + LR | Apache 2.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.54 (0.50–0.58) | 0.22 (0.18–0.27) | 0.77 (0.75–0.80) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clean | 0.71 (0.68–0.74) | 0.62 (0.57–0.68) | 0.68 (0.65–0.70) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 100 Hz | 0.70 (0.67–0.73) | 0.71 (0.66–0.76) | 0.57 (0.55–0.60) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 150 Hz | 0.56 (0.52–0.59) | 0.60 (0.55–0.66) | 0.47 (0.45–0.50) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 10 dB SNR | 0.51 (0.46–0.56) | 0.28 (0.21–0.36) | 0.73 (0.69–0.76) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 5 dB SNR | 0.50 (0.46–0.56) | 0.45 (0.36–0.54) | 0.57 (0.52–0.61) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.49 (0.45–0.54) | 0.25 (0.19–0.31) | 0.73 (0.69–0.77) |

#### Heart murmur, Present vs Absent (CirCor, per patient; Unknown excluded)

| Experiment | Weight licence | Condition | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|
| (b) YAMNet embeddings + LR | Apache 2.0 | clean | 0.81 (0.77–0.85) | 0.59 (0.53–0.66) | 0.88 (0.86–0.91) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 100 Hz | 0.81 (0.77–0.85) | 0.60 (0.52–0.67) | 0.89 (0.87–0.92) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 150 Hz | 0.81 (0.77–0.85) | 0.56 (0.49–0.63) | 0.92 (0.90–0.94) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 10 dB SNR | 0.72 (0.68–0.77) | 0.74 (0.68–0.80) | 0.54 (0.50–0.57) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 5 dB SNR | 0.69 (0.64–0.74) | 0.57 (0.50–0.64) | 0.72 (0.68–0.75) |
| (b) YAMNet embeddings + LR | Apache 2.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.56 (0.52–0.60) | 0.66 (0.59–0.73) | 0.50 (0.47–0.55) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clean | 0.76 (0.71–0.80) | 0.56 (0.49–0.63) | 0.81 (0.78–0.84) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 100 Hz | 0.73 (0.68–0.77) | 0.45 (0.38–0.52) | 0.88 (0.86–0.91) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 150 Hz | 0.61 (0.56–0.65) | 0.01 (0.00–0.03) | 1.00 (0.99–1.00) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 10 dB SNR | 0.60 (0.55–0.64) | 0.32 (0.26–0.39) | 0.76 (0.72–0.79) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 5 dB SNR | 0.55 (0.50–0.59) | 0.26 (0.20–0.33) | 0.78 (0.75–0.81) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.64 (0.60–0.69) | 0.49 (0.41–0.56) | 0.76 (0.73–0.79) |

#### Outcome, Abnormal vs Normal (CirCor, per patient)

| Experiment | Weight licence | Condition | AUROC (95% CI) | Sensitivity (95% CI) | Specificity (95% CI) |
|---|---|---|---|---|---|
| (b) YAMNet embeddings + LR | Apache 2.0 | clean | 0.64 (0.60–0.68) | 0.36 (0.32–0.41) | 0.84 (0.80–0.87) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 100 Hz | 0.64 (0.60–0.68) | 0.36 (0.32–0.40) | 0.85 (0.81–0.88) |
| (b) YAMNet embeddings + LR | Apache 2.0 | high-pass 150 Hz | 0.63 (0.59–0.67) | 0.30 (0.26–0.35) | 0.88 (0.85–0.91) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 10 dB SNR | 0.62 (0.58–0.65) | 0.69 (0.65–0.73) | 0.42 (0.38–0.47) |
| (b) YAMNet embeddings + LR | Apache 2.0 | clinic-like noise, 5 dB SNR | 0.59 (0.55–0.63) | 0.49 (0.44–0.53) | 0.62 (0.58–0.66) |
| (b) YAMNet embeddings + LR | Apache 2.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.40 (0.36–0.43) | 0.75 (0.71–0.79) | 0.18 (0.15–0.22) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clean | 0.62 (0.59–0.66) | 0.47 (0.42–0.52) | 0.70 (0.66–0.74) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 100 Hz | 0.61 (0.57–0.65) | 0.75 (0.71–0.79) | 0.37 (0.33–0.41) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | high-pass 150 Hz | 0.56 (0.53–0.60) | 0.44 (0.39–0.48) | 0.69 (0.65–0.73) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 10 dB SNR | 0.56 (0.52–0.59) | 0.05 (0.03–0.07) | 0.99 (0.97–0.99) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | clinic-like noise, 5 dB SNR | 0.53 (0.49–0.57) | 0.11 (0.08–0.14) | 0.91 (0.88–0.93) |
| (c) OPERA-CE embeddings + LR | CC BY-NC 4.0 | level -20 dB (noise floor -70 dBFS, 16-bit) | 0.57 (0.53–0.61) | 0.11 (0.08–0.14) | 0.95 (0.94–0.97) |

### OPERA-CE long clips: fixed-length rules against the official whole-clip embedding

| Dataset | Clips longer than 8 s after trimming | Rule | Cosine to whole-clip, median (5th percentile) |
|---|---|---|---|
| sprsound | 5890 of 5950 | mean of 8 s windows | 0.998 (0.973) |
| sprsound | 5890 of 5950 | first 8 s after trimming | 0.998 (0.974) |
| circor | 3128 of 3163 | mean of 8 s windows | 0.988 (0.946) |
| circor | 3128 of 3163 | first 8 s after trimming | 0.981 (0.918) |

| Task | Weight licence | Whole clip (official) AUROC | Mean of 8 s windows AUROC | First 8 s AUROC |
|---|---|---|---|---|
| stridor (exploratory) | CC BY-NC 4.0 | 0.62 (0.50–0.77) | 0.58 (0.44–0.75) | 0.68 (0.58–0.81) |
| wheeze | CC BY-NC 4.0 | 0.76 (0.71–0.81) | 0.75 (0.70–0.80) | 0.75 (0.70–0.80) |
| crackle | CC BY-NC 4.0 | 0.71 (0.68–0.74) | 0.70 (0.67–0.73) | 0.69 (0.66–0.72) |
| murmur | CC BY-NC 4.0 | 0.76 (0.71–0.80) | 0.74 (0.70–0.78) | 0.72 (0.68–0.77) |
| outcome | CC BY-NC 4.0 | 0.62 (0.59–0.66) | 0.64 (0.60–0.67) | 0.59 (0.55–0.62) |

### Non-AI baselines

| Measure | Weight licence | Condition | Recordings estimated / total | Patients | MAE (95% CI) | Median AE | Bias | Within ±5 /min |
|---|---|---|---|---|---|---|---|---|
| Breathing rate, SPRSound (breaths/min; event-rate proxy reference) | n/a (no model) | clean | 3050 / 3050 | 681 | 19.6 (18.5–20.8) | 8.7 | +10.7 | 41% |
| Breathing rate, SPRSound (breaths/min; event-rate proxy reference) | n/a (no model) | high-pass 150 Hz | 3050 / 3050 | 681 | 19.3 (18.1–20.4) | 8.3 | +10.4 | 42% |
| Breathing rate, SPRSound (breaths/min; event-rate proxy reference) | n/a (no model) | clinic-like noise, 10 dB SNR | 3050 / 3050 | 681 | 20.1 (19.0–21.2) | 9.2 | +10.9 | 40% |
| Breathing rate, SPRSound (breaths/min; event-rate proxy reference) | n/a (no model) | clinic-like noise, 5 dB SNR | 3050 / 3050 | 681 | 20.4 (19.3–21.5) | 9.8 | +11.1 | 39% |
| Heart rate, CirCor (beats/min; S1 segmentation) | n/a (no model) | clean | 3162 / 3162 | 942 | 32.1 (30.4–33.8) | 5.3 | +13.4 | 49% |
| Heart rate, CirCor (beats/min; S1 segmentation) | n/a (no model) | high-pass 150 Hz | 3162 / 3162 | 942 | 45.9 (44.4–47.5) | 43.4 | +14.6 | 23% |
| Heart rate, CirCor (beats/min; S1 segmentation) | n/a (no model) | clinic-like noise, 10 dB SNR | 3162 / 3162 | 942 | 32.4 (30.6–34.1) | 5.5 | +13.3 | 49% |
| Heart rate, CirCor (beats/min; S1 segmentation) | n/a (no model) | clinic-like noise, 5 dB SNR | 3162 / 3162 | 942 | 32.1 (30.5–33.8) | 5.5 | +12.8 | 49% |
| Breathing rate, ICBHI children (breaths/min; annotated cycles) | n/a (no model) | clean | 76 / 76 | 49 | 12.3 (7.2–19.1) | 1.2 | +8.6 | 70% |
| Breathing rate, ICBHI children (breaths/min; annotated cycles) | n/a (no model) | band-limited to 4 kHz (as SPRSound) | 76 / 76 | 49 | 12.3 (7.2–19.1) | 1.2 | +8.6 | 70% |
| Breathing rate, ICBHI children (breaths/min; annotated cycles) | n/a (no model) | high-pass 150 Hz | 76 / 76 | 49 | 12.3 (7.1–19.1) | 1.1 | +8.7 | 70% |
| Breathing rate, ICBHI children (breaths/min; annotated cycles) | n/a (no model) | clinic-like noise, 10 dB SNR | 76 / 76 | 49 | 16.1 (10.8–22.7) | 5.7 | +10.1 | 49% |
| Breathing rate, ICBHI children (breaths/min; annotated cycles) | n/a (no model) | clinic-like noise, 5 dB SNR | 76 / 76 | 49 | 14.3 (10.0–19.6) | 5.5 | +6.6 | 46% |

| Measure | Weight licence | Age band | Recordings | Patients | MAE (95% CI) | Within ±5 /min |
|---|---|---|---|---|---|---|
| Breathing rate, SPRSound | n/a (no model) | 1-5 y | 1847 | 400 | 18.4 (17.1–19.8) | 43% |
| Breathing rate, SPRSound | n/a (no model) | 2-11 mo | 223 | 47 | 22.7 (19.5–26.2) | 27% |
| Breathing rate, SPRSound | n/a (no model) | 6+ y | 976 | 235 | 21.1 (18.9–23.4) | 41% |
| Breathing rate, ICBHI | n/a (no model) | 1-5 y | 45 | 28 | 8.2 (3.7–14.7) | 78% |
| Breathing rate, ICBHI | n/a (no model) | 2-11 mo | 13 | 8 | 9.6 (5.1–13.5) | 54% |
| Breathing rate, ICBHI | n/a (no model) | 6+ y | 18 | 13 | 24.4 (7.8–44.0) | 61% |
| Heart rate, CirCor | n/a (no model) | Adolescent (12-18 y) | 259 | 72 | 29.4 (23.7–35.6) | 56% |
| Heart rate, CirCor | n/a (no model) | Child (1-11 y) | 2386 | 664 | 29.7 (27.8–31.7) | 53% |
| Heart rate, CirCor | n/a (no model) | Infant (28 d-1 y) | 269 | 126 | 45.1 (40.4–50.0) | 25% |
| Heart rate, CirCor | n/a (no model) | Neonate (0-27 d) | 10 | 6 | 49.0 (21.5–79.5) | 10% |
| Heart rate, CirCor | n/a (no model) | unknown | 238 | 74 | 43.3 (38.0–49.3) | 31% |

| Condition | Weight licence | Recordings | Spearman ρ, estimated vs reference beat-interval CV | Reference CV median | Estimated CV median |
|---|---|---|---|---|---|
| clean | n/a (no model) | 3162 | 0.13 | 0.052 | 0.191 |
| high-pass 150 Hz | n/a (no model) | 3162 | 0.08 | 0.052 | 0.213 |
| clinic-like noise, 10 dB SNR | n/a (no model) | 3162 | 0.12 | 0.052 | 0.192 |
| clinic-like noise, 5 dB SNR | n/a (no model) | 3162 | 0.12 | 0.052 | 0.195 |

### Coswara real phone audio against simulated degradation (medians)

| Audio | Recordings | Level (dBFS) | Energy below 150 Hz | Spectral centroid (Hz) | Frame-energy range (dB) |
|---|---|---|---|---|---|
| Coswara phone, full band | 125 | -37.9 | 0.01 | 1548 | 46.6 |
| Coswara phone, band-limited to 4 kHz | 125 | -38.6 | 0.01 | 1146 | 46.8 |
| sprsound: clean | 300 | -38.2 | 0.44 | 174 | 19.1 |
| sprsound: high-pass 100 Hz | 300 | -38.9 | 0.33 | 188 | 20.6 |
| sprsound: high-pass 150 Hz | 300 | -41.3 | 0.07 | 222 | 22.5 |
| sprsound: clinic-like noise, 10 dB SNR | 300 | -37.8 | 0.47 | 189 | 12.7 |
| sprsound: clinic-like noise, 5 dB SNR | 300 | -37.0 | 0.51 | 215 | 9.9 |
| sprsound: level -20 dB (noise floor -70 dBFS, 16-bit) | 300 | -57.9 | 0.41 | 291 | 12.4 |
| Coswara phone, band-limited to 2 kHz | 125 | -40.5 | 0.02 | 670 | 44.5 |
| circor: clean | 300 | -28.2 | 0.39 | 330 | 21.2 |
| circor: high-pass 100 Hz | 300 | -30.9 | 0.12 | 434 | 22.9 |
| circor: high-pass 150 Hz | 300 | -32.2 | 0.01 | 495 | 22.6 |
| circor: clinic-like noise, 10 dB SNR | 300 | -27.8 | 0.43 | 315 | 15.4 |
| circor: clinic-like noise, 5 dB SNR | 300 | -27.0 | 0.48 | 294 | 12.0 |
| circor: level -20 dB (noise floor -70 dBFS, 16-bit) | 300 | -48.1 | 0.39 | 340 | 19.7 |
