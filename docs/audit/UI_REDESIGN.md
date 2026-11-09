# UI redesign

Visual redesign of the CHO app against the Stitch designs in project *Yoma Care Emergency App
UI* (`3335194134719283465`). App behaviour, flows, validation and data are meant to stay
exactly as they are. Where a design would change behaviour, it was **not** built; those
places are listed under [Conflicts with existing behaviour](#conflicts-with-existing-behaviour-not-built).

## Round 1

Branch `feat/ui-redesign`, cut from `origin/main` at `3866918` (*Merge pull request #15 from
rehearsal/at-sandbox*). That tip already includes `fix/batch-5`, `fix/batch-6`,
`rehearsal/at-sandbox` and `test/emulator-pass`, so this is the UI they left.

Commits, in order:

| Commit | What |
|---|---|
| `docs(design)` | Stitch reference code for the five screens (`docs/design/stitch/`) |
| `feat(ui): design system` | Tokens, type, components, bundled font; applied app-wide |
| `feat(ui): redesign Home` | Designs 1 and 3, with the Home layout update |
| `feat(ui): redesign Record vitals` | Design 2 |
| `feat(ui): redesign Result` | Design 4 |
| `feat(ui): restyle the Emergency referral form` | Design 5, the parts that don't change behaviour |
| `test(ui): accessibility checks` | Step 4 |
| `test(emulator)` / `docs` | Screenshot scenario, screenshots, this file |

### Design sources

`docs/design/stitch/<screen>/code.html` holds each screen's Stitch HTML/CSS, fetched through
the Stitch MCP. `render-from-code.png` is that HTML rendered locally in headless Chromium,
**not** the Stitch-hosted screenshot. The hosted download URLs return HTTP 401 to `curl -L`
(they need the Stitch credential), and the MCP returns images only as inline base64, which
couldn't be written to disk reliably. `docs/design/stitch/README.md` has the one-line
commands to add the real images.

The Stitch HTML was read for values only; nothing was ported. Everything is Flutter widgets.

### Design system

`mobile/lib/theme/yoma_theme.dart` and `mobile/lib/widgets/yoma_components.dart`.

| Token | Value | Source |
|---|---|---|
| Brand teal | `#005F60` (pressed `#004A4B`) | "Brand Teal" in the Result and Referral designs |
| Dark navy | `#0F2744` | Failed-referral strip |
| Background | `#F8FAFC` (slate-50); surfaces `#FFFFFF` | All designs |
| Greys | Tailwind slate 100–900 | All designs |
| Triage RED | `#DC2626`, white text (4.83:1) | Result design |
| Triage AMBER | `#F59E0B`, grey-900 text (8.31:1) | Result design |
| Triage GREEN | `#15803D`, white text (5.02:1). Already meets AA, so not darkened | Result design |
| Incomplete | `#F1F5F9` fill, `#94A3B8` dashed border | Result design |
| Error / warning / success | `#B42318` / `#B54708` / `#067647` | Added: semantic colours, so triage colours stay for risk level only |

Type scale is the Result design's (`headline-lg` 26/34 … `label-sm` 12/16); spacing 4/8/12/16/24/32;
radii 8 / 12 (buttons, inputs, chips) / 16 (large cards); Tailwind `shadow-sm` and `shadow-md`.
Themed: primary (filled, 56 dp), outlined, text and disabled buttons, cards, inputs (teal
focus border), and components `YomaCard`, `YomaChoiceChip`, `StatusStrip` (light / navy),
`StatusStripItem`, `RiskBadge`, `TriageLevel` (word + icon per level), dashed border.

**Font.** Home and Record vitals specify Inter; Result and Referral specify Atkinson
Hyperlegible Next. Because they differ, **Atkinson Hyperlegible Next is used everywhere.**
It is bundled under `mobile/assets/fonts/atkinson_hyperlegible_next/` with `OFL.txt`, and
never fetched at runtime. Upstream (google/fonts) ships only a variable font, so static
400/500/600/700 instances were cut from it with fontTools `varLib.instancer` (Flutter does
not map `FontWeight` onto a variable font's weight axis by itself). The licence is also
registered with `LicenseRegistry`, so it shows on the app's licence page.

The theme is applied app-wide. Screens outside this round (setup, screening, queued,
dispatch, stale, failed, unsent, facility picker) inherit it without hand changes. Old
colour names (`YomaColors.danger/caution/safe`) now point at the semantic colours, so those
screens keep rendering without borrowing the triage palette. Their tests pass unchanged.

### What changed per screen

**Home** (designs 1 and 3, laid out per the *Home layout update* below)

- Slim top bar: "Yoma Care" and the CHPS compound name from the CHO's identity.
- Emergency referral: teal card, ambulance icon above the label, about 96 dp tall. It is
  pinned directly under the top bar, first and largest in every state. The ambulance is the
  design's Lucide outline, drawn with `CustomPainter`, because Material Icons has no ambulance.
- One full-width outlined action under it, with the mode's existing behaviour: **Check
  breathing** with the sound-wave icon and a grey *Advisory* tag (acoustic mode, opens the
  breath check, which is today's "Screen Breathing"), or **Record vitals** with the
  heart-pulse icon (MOEWS-only mode, opens vitals as today).
- Warnings: the existing collapsed banner is now the bottom status strip. It is light while
  the most urgent warning is only waiting (expiring, retrying, catalog stale) and navy when
  it is a failure or a referral needing an answer ("NOT sent", "Still needs transport?").
  Contents, order, wording and tap-to-open are unchanged; the open list uses matching rows.
  The strip sits at the bottom when there is room and scrolls with the rest when there isn't,
  so it can never cover Emergency referral.
- TEST BUILD label unchanged (app-wide builder). The non-production env line is kept, small.

**Record vitals** (design 2)

- One compact card per vital: label left, value right with its unit, and a **Not measured /
  Clear** toggle with a 48 dp tap area. A not-measured card turns grey with a NOT MEASURED tag.
- Blood pressure is one card. Systolic and diastolic sit on their own row under the label,
  each field wide enough for 3 digits, each still a separate vital with its own toggle.
- Consciousness is four large chips (Alert, Voice, Pain, Unresponsive) plus Not measured.
  Nothing is preselected, consciousness included.
- **See result – N left** counts the answers the form still requires.
- Focused field border is teal. Validation limits and messages are unchanged.
- The advisory device-HR fill-in (not in the design) is kept, as a text button under Heart rate.

**Result** (design 4)

- Risk card coloured by level and named in words: *Critical / Elevated / Stable / Incomplete*,
  with the MOEWS name (e.g. "MOEWS RED") and score underneath.
- All numbers come from the app's scoring. "Why" rows come from `explainMoews`
  (`lib/services/moews_explanation.dart`), which reads the per-parameter scores and the
  MOEWS bands. Critical parameters come first, labelled "very high" / "very low" with a
  filled dot; borderline ones say "high" / "low" with an outlined dot.
- INCOMPLETE: grey card, dashed border, list titled "Not measured", Confirm Referral as the
  main button.
- GREEN: Continue Monitoring as the main button; "Oxygen saturation not measured" when SpO₂
  is missing. With nothing abnormal, Why says every measured vital is in the normal range.
- Acoustic advisory line kept for acoustic mode, restyled as a grey secondary card with no
  triage colours.
- Disclaimer ("Advisory only — not a diagnosis…") kept, as one grey line at the top.

**Emergency referral form** (design 5, partly; see conflicts)

- Emergency type as large chips built from the app's **current** list: Respiratory
  distress, Postpartum hemorrhage, Neonatal asphyxia, Eclampsia. The design's examples were
  not added. Nothing is preselected; the validation message is unchanged.
- "Send to" is one card with a chevron and no "Change" link. It opens the existing facility
  picker, and the "(tap to confirm facility)" / "(confirmed)" requirement is unchanged.
- Title "Emergency referral"; teal submit button; neutral AI-screen note; error text in the
  warning colour (the old `Colors.orange` was 2.2:1 on white).

### Home layout update (requested mid-round)

The Home layout follows the reference image the user sent mid-round, which replaces the
"Home – Minimal" layout: a short (~96 dp) emergency card, then full-width outlined buttons
directly under it, with no large empty area. As instructed, Check breathing sits **between**
Emergency referral and Record vitals (the image showed it last). In MOEWS-only mode, Check
breathing isn't built at all, so there is no gap. Tests cover the button order and spacing
in both modes, Check breathing being absent in MOEWS-only mode, and Emergency referral fully
visible and tappable with every warning open at 320 dp and 130% text.

The reference image arrived as an image in the conversation, not a file, so it could not be
saved next to the screenshots. Please add it as
`docs/testing/screenshots/ui-redesign/reference_home_layout_update.png`.

Today Home offers only **one** action besides Emergency referral in each mode, so in
acoustic mode it shows Emergency referral and Check breathing, without Record vitals. See
conflict 1.

### Conflicts with existing behaviour (not built)

These parts of the designs or the brief would change behaviour, so they were left as they
are. Each needs a decision.

1. **Record vitals in acoustic mode (Home).** Today vitals are reached in acoustic mode only
   through the breath check (the screening result travels with the referral as
   `ai_screen_result` / model version). A direct Record vitals button would be a new path,
   and it needs a decision on what screening result such a referral carries ("not done"?
   `moews_only`?). *Decision needed: add the path, and with which result?*
2. **Offline pill (Home).** Home has no connectivity indicator today, so there is nothing to
   restyle. Adding one is a new feature: it needs a source of truth (connectivity_plus, or
   the queue's last failure) and a decision on wording when there's Wi-Fi without internet.
   *Decision needed.*
3. **SpO₂ optional (Record vitals).** The design marks Oxygen saturation "(optional)", and
   the brief says it is never counted. The scoring already treats missing SpO₂ as optional
   (it never makes a result INCOMPLETE), but the form still requires an answer (a value or
   Not measured), with the error "Enter a value or tick Not measured". Making it optional
   changes validation. So for now it is not labelled optional, and the counter includes it,
   because it is required. *Decision needed: accept a blank SpO₂?*
4. **Disabled See result (Record vitals).** The design greys the button out until the form
   is complete. Today it is always enabled, and a tap with gaps shows which fields are
   missing. Disabling it would remove that guidance. Kept enabled.
5. **Referral form structure.** The design has no patient name and no vitals fields; today's
   form requires the patient name (local only, "Name, or type Unknown") and has editable
   vitals, prefilled from the vitals step. So:
   - the read-only **vitals summary row** with the risk badge was not built (it would sit
     beside editable fields and could go stale while they are edited; `RiskBadge` is ready
     for it);
   - **"Vitals not taken – the hospital will be told"** was not built. Today skip-vitals is
     the red "Emergency: skip vitals" button on the same screen, not a separate path, and it
     keeps its text and behaviour;
   - **Send disabled until a type is chosen** was not built. Today Send validates on tap and
     says "Choose the emergency type"; skip-vitals says "Choose the emergency type first".
   *Decision needed: should the form become the design's short form (which removes the name
   and inline vitals), or keep today's fields?*

### Other deviations from the designs, and why

- **Teal**: the designs use three teals (`#0D5C63`, `#0E6569`, `#005F60`). One is used: `#005F60`.
- **Font**: Atkinson Hyperlegible Next everywhere (see above).
- **Disabled button text**: grey-600 on grey-200 (6.15:1) instead of the design's slate-500
  (3.86:1).
- **Placeholder dash**: grey-500 (4.55:1) instead of slate-300 (1.42:1), which is illegible.
- **Amber dots**: `#D97706` (3.19:1 against white, the non-text minimum) instead of the card's
  `#F59E0B` (2.15:1).
- **Result, RED and AMBER**: the design's bottom area repeats the Why list instead of holding
  buttons (a bug in the design). The app keeps its buttons there.
- **Button labels** kept as the app has them ("Confirm Referral", "Continue Monitoring",
  "Refer with clinical judgment", "Confirm Referral" on the form) rather than the design's
  sentence case and "Send referral". These labels are referred to across tests, the
  integration harness and training material; changing them is cheap if wanted.
- **Result, GREEN secondary** says "Refer with clinical judgment" (today's wording), not the
  design's "Confirm referral".
- **Result headline** uses the design's words (Critical / Elevated / Stable) **and** keeps
  "MOEWS RED/YELLOW/GREEN" on the line under it, so the term CHOs know stays visible.
- **Result "Why" for GREEN** says "Every measured vital is in the normal range" instead of
  listing each normal value.
- **Disclaimer and acoustic line** (not in the design) kept, as grey secondary elements.
- **Record vitals labels** follow the design: Breathing rate (was Respiratory rate), Oxygen
  saturation (was SpO2), Consciousness (was AVPU). Error messages, including "tick Not
  measured", are unchanged as instructed, though "tick" now refers to a button.
- **Blood pressure "Not measured"**: one toggle per field (systolic, diastolic), not one for
  the card, because they are separate vitals today.
- **Vitals cards** are more compact than the design (label and toggle stacked left, value
  right) so more of the form fits on 360×640.
- **Home strip colour**: "Still needs transport?" counts as urgent (navy) along with
  failures, because Home already ranks it as urgent.
- **Referral Send-to card** also shows "(tap to confirm facility)" / "(confirmed)" and the
  compound name, because facility confirmation is required before sending.
- **Home**: no "Offline" pill (conflict 2). "Community Health Officer" and the help sentence
  are gone, per the design.

### Contrast (WCAG AA)

Every text/background pair used on the redesigned screens, computed from the tokens
(`test/ui_redesign_a11y_test.dart` asserts the same pairs; Flutter's `textContrastGuideline`
also passes on each rendered screen). **No pair is below AA.**

| Screen | Pair | Ratio | Needs |
|---|---|---|---|
| Home | App and clinic name (grey-900 / grey-700 on canvas) | 17.06 / 9.90 | 4.5 |
| Home | Emergency referral label, white on teal (pressed) | 7.48 (10.09) | 3.0 |
| Home | Action label, teal on white | 7.48 | 3.0 |
| Home | Advisory tag, grey-700 on grey-100 | 9.45 | 4.5 |
| Home | Light strip title / subtitle on white | 14.63 / 7.58 | 4.5 |
| Home | Navy strip title (white) / subtitle (`#DCE3EC`) | 15.06 / 11.65 | 4.5 |
| Vitals | Field label, grey-800 on white | 14.63 | 4.5 |
| Vitals | Value, grey-900 on input fill | 17.06 | 3.0 |
| Vitals | Placeholder dash, grey-500 on input fill | 4.55 | 3.0 |
| Vitals | Unit, grey-600 on input fill | 7.24 | 4.5 |
| Vitals | Not measured / Clear, grey-700 on white / grey-100 | 10.35 / 9.45 | 4.5 |
| Vitals | NOT MEASURED tag, grey-700 on grey-200 | 8.40 | 4.5 |
| Vitals | Helper / HR band helper / error | 7.58 / 5.43 / 6.57 | 4.5 |
| Vitals | Chip, grey-800 on white; selected white on teal | 14.63 / 7.48 | 4.5 |
| Vitals | See result, white on teal; disabled grey-600 on grey-200 | 7.48 / 6.15 | 3.0 |
| Result | Critical: white on RED (headline / score line) | 4.83 | 3.0 / 4.5 |
| Result | Elevated: grey-900 on AMBER | 8.31 | 4.5 |
| Result | Stable: white on GREEN | 5.02 | 4.5 |
| Result | Incomplete: grey-900 on grey-100 | 16.30 | 4.5 |
| Result | Why rows, grey-800 on white | 14.63 | 4.5 |
| Result | Disclaimer / not-measured note on canvas | 9.90 / 7.24 | 4.5 |
| Result | Acoustic card text / confidence on grey-100 | 9.45 / 6.92 | 4.5 |
| Referral | Section label; "(tap to confirm facility)" teal on white | 17.06 / 7.48 | 4.5 |
| Referral | Warning text on canvas; skip-vitals white on error red | 5.19 / 6.57 | 4.5 / 3.0 |
| App | TEST BUILD label, white on `#C62828` | 5.62 | 4.5 |

Pairs in the designs that would have failed, and were changed: disabled button text 3.86,
placeholder 1.42, amber `#F59E0B` dots 2.15 (non-text), old referral error orange 2.2.

### Accessibility

`mobile/test/ui_redesign_a11y_test.dart`, for Home (both modes, every warning), Record vitals,
Result (all four levels) and the referral form:

- Tap targets ≥ 48 dp and every tap target labelled (`androidTapTargetGuideline`,
  `labeledTapTargetGuideline`): pass.
- Rendered text contrast (`textContrastGuideline`): pass.
- 130% text at 320×568 and 360×640, scrolled to the end: no overflow.
- Risk card announced as "Risk level: Critical. MOEWS RED. Score 7…" (and so on per level).
- Icons: the emergency card, action buttons, strip and toggles carry semantic labels; Why
  rows say "Critical: …" / "Borderline: …"; chips announce selected state.

Caveat: widget tests render with Flutter's test font, not Atkinson, so their overflow checks
are approximate. The 320 dp emulator run (`small_ui_*` screenshots, with the harness's
cut-off checks) covers the real font.

### Tests

- `flutter analyze`: no issues.
- `flutter test`: 374 passed (default), 375 passed (`MOEWS_ONLY=false`) at the end of round 1.
- Updated for the new UI without weakening them: label and title changes ("Record vitals",
  "Check breathing", "Emergency referral", "Result"); the vitals button found by key
  (its label now counts down); the AVPU helper taps chips; "not measured carries over"
  now checks the Clear state of each toggle instead of a checkbox; Incomplete checks every
  missing vital by name in the list; the referral picker is opened by the Send-to card's
  key. Integration tests find Home by the Emergency referral key.
- New: `home_layout_test` (layout update group), `ui_redesign_result_test`,
  `ui_redesign_a11y_test`, and integration scenario `ui` (`s12_ui_redesign_test.dart`).

### Emulator pass and screenshots

**Not completed.** Every full run of `scripts/run_emulator_pass.py` in this round was cut
short: one when the session ended during the release build, one when the API 34 emulator was
killed (out of memory while other work ran alongside it). Scenarios that did run passed
(s1, responsive, s3–s6 on API 34; `ui` and `breathing` on their own); s2 failed on a
leftover "Community Health Officer" wait in the release-APK steps (fixed in round 3).
The `ui` scenario's screenshots exist in `mobile/build/emulator_pass/` but were not copied
into `docs/testing/screenshots/`. A device check of the fresh debug build is in
"Verification" below.

### Open questions

1. **Emergency types are an open clinical decision.** The chips use the app's current four
   (Respiratory distress, Postpartum hemorrhage, Neonatal asphyxia, Eclampsia). The design
   suggests a different, plainer set (Heavy bleeding, Fits (eclampsia), Breathing problem,
   Newborn not breathing, Other). Changing the list changes what is sent to the server
   (`emergency_type`), so it needs clinical and backend sign-off.
2. Conflicts 1–5 above.
3. Are *Critical / Elevated / Stable* the right words for CHOs, next to MOEWS RED / YELLOW /
   GREEN? "Stable" in particular may read as an all-clear.
4. Should button labels move to sentence case ("Confirm referral") and the form's submit
   become "Send referral"?
5. The Stitch-hosted design images need adding (see `docs/design/stitch/README.md`).

## Round 2 — breathing check flow

Same branch (`feat/ui-redesign`, confirmed in sync with `origin` before starting). Design:
*Yoma Care - Breathing Check Flow (6 Screens)* (`1635e5aae3144c37af5b5b65932a6204`),
saved under `docs/design/stitch/breathing-check/` (Stitch HTML, plus the two canvas captures
supplied with the brief; the hosted image still returns 401 to `curl -L`). The file has no
Result-screen advisory row, so that row follows the brief. Built with the round-1 tokens and
font only; no new colours or fonts.

These screens exist only in acoustic mode (`MOEWS_ONLY=false`); in the default build Home
has no way in.

### What changed per screen

**Recording** — solid teal circle (60% of the pulse area, up to 232 dp) with the countdown
"N s" / REMAINING, a 4 dp ring just outside it showing time elapsed, and three soft teal rings
pulsing outward. The rings' reach follows the live microphone level: quiet keeps them close,
loud sends them to the edge. The level comes from `record`'s `onAmplitudeChanged` (it polls
the platform's own amplitude every 120 ms), smoothed, and is used for display only — the
PCM file, its length and the classifier are untouched. Only the ring painter repaints per
frame (own repaint boundary, `repaint:` listenable); no widget rebuilds per frame. With
"Remove animations" on (`MediaQuery.disableAnimations`), one static ring. "LISTENING" pill,
"Listening… keep the phone still", "Do not speak or move until complete", outlined **Stop**
(same behaviour as the old "Stop & Analyze Early").

**Silence hint** — "Can't hear breathing – move the phone closer" under the circle after
3 s of level below ≈ -50 dBFS; it clears when sound returns. Shown only once level readings
are arriving, so a phone without amplitude support never gets a false alarm. It changes
nothing in the recording or classification (tested).

**Analysing** — teal spinner, "Checking the recording…", outlined Cancel. The batch 5
behaviour is unchanged: analysis runs off the main thread, Cancel stops it and continues to
vitals with INCONCLUSIVE (`cancelled`).

**Microphone blocked** — mic-off icon, "Microphone not allowed", "Allow the microphone in
Settings to check breathing, or skip this step", teal **Open settings** (this app's system
settings page) and outlined **Skip to vitals** (the existing denied path: INCONCLUSIVE,
`unavailable`, straight to vitals). For a microphone that fails for another reason the title
is "The microphone could not start" and there is no Open settings.

**Open settings** — `app_settings` 9.0.1 (`AppSettings.openAppSettings()`). No existing
dependency can do it: `url_launcher` cannot fire Android's
`ACTION_APPLICATION_DETAILS_SETTINGS` intent. `app_settings` is small and single-purpose;
`permission_handler` would also do it but is far larger.

**Breathing check result** — "Possible breathing problem": white card, 6 dp navy left
border, alert icon, "Unusual breathing sounds were detected", grey Advisory tag. "Couldn't
tell": white card, grey dashed border, question-mark icon, "Use your own judgement and record
vitals". The existing mapping decides: only an acoustic RED is a possible problem; everything
else (INCONCLUSIVE, cancelled, unavailable, and any GREEN) is "Couldn't tell". Never a normal
or healthy-looking result, and no red/yellow/green. Teal **Continue to vitals**.

**Ready** — "Check breathing", the chest-and-phone line drawing (from the design's SVG), three
numbered steps — the third reads "Keep the phone still for N seconds" with N from
`ScreeningConfig.durationSec` — the grey "This is advice only. Always use your own judgement."
note, and a teal Start.

**Result screen advisory row** — replaces round 1's grey acoustic card: below the Why list, one
row "Breathing check (advisory)" with the sound-wave icon and an outlined badge "Possible
breathing problem" / "Couldn't tell". Dark grey, no triage colours, no score or confidence.
The MOEWS heart-rate line that lived in that card ("Heart rate contributes MOEWS …") stays,
on its own line.

**Screen reader** — on start "Recording. Keep the phone still for N seconds."; then "N seconds
left" every 5 s (not every second); "Checking the recording"; the silence hint when it
appears (announcement plus live region); the result card announced as "Breathing check:
<variant>. <line>." Numbered steps read "Step N: …".

### Conflicts with existing behaviour (built, but switched off)

Two of the design's screens add a step to today's flow, where Check breathing starts
recording at once and the analysis goes straight to Record vitals:

1. **Ready** puts a Start tap before recording.
2. **Breathing check result** puts a Continue tap between the analysis and vitals.

Both are built and tested, but behind `--dart-define=BREATHING_STEPS=true` (default off), so
the flow is unchanged. *Decision needed: turn them on?* The screenshots show them (the test
switches them on for the shot). The mic-blocked Skip to vitals goes straight to vitals even
with the result step on, as the denied path does today.

### Other deviations from the design, and why

- **One commit for the five breathing screens** (`4e346e7`) rather than one per screen: they
  are stages of one screen (`ScreeningScreen`) in one file, as today. The Result row,
  plumbing and tests are separate commits.
- **Background tint** `#F0F3FF` (lavender) in the design is not a round-1 token; the pill, step
  numbers and illustration use the round-1 brand tint `#E6F3F3` instead.
- **Dashed border** grey-500 (4.76:1), not slate-300 (1.48:1); round 1's Incomplete card
  border moved from grey-400 to grey-500 too.
- **REMAINING** in solid white (7.48:1) rather than white at 80%.
- **Title bar** kept on every stage (with back), where the design drops it on Recording and
  Analysing: back is how a CHO leaves today, and leaving mid-analysis stops the model.
- **Analysing subline** is "You can keep using the phone." (today's message) instead of the
  design's "Analyzing breath rate and sound patterns", which describes something the model
  doesn't do (it doesn't measure breath rate).
- **Result screen footnote** "Field guidance: Results do not replace nurse auscultation" not
  added; the existing "This is advice only…" line is used instead.
- **Web demo** buttons are neutral outlined buttons (they were green/red).

### Contrast (WCAG AA), new pairs

| Pair | Ratio | Needs |
|---|---|---|
| Countdown and REMAINING, white on teal | 7.48 | 4.5 |
| LISTENING pill / step numbers, teal on brand tint | 6.59 | 4.5 |
| Step text, grey-800 on white | 14.63 | 4.5 |
| Titles, navy on canvas / white | 14.40 / 15.06 | 4.5 |
| Secondary lines and advice note, grey-600 on canvas / white | 7.24 / 7.58 | 4.5 |
| Silence hint, grey-800 on grey-100 | 13.35 | 4.5 |
| Advisory tag, grey-700 on grey-100 | 9.45 | 4.5 |
| Advisory row label and badge, grey-800 on white | 14.63 | 4.5 |
| Progress arc / spinner, teal on canvas (non-text) | 7.15 | 3.0 |
| Navy left border on white (non-text) | 15.06 | 3.0 |
| Dashed border, grey-500 on white (non-text) | 4.76 | 3.0 |
| Badge border, grey-600 on white (non-text) | 7.58 | 3.0 |
| Mic-off icon, navy on its 10% navy tint | 12.39 | 3.0 |

No pair is below AA. The progress *track* (grey-200 on canvas, 1.18:1) is decorative; the
arc carries the information.

### Accessibility and tests

- `test/ui_redesign_breathing_test.dart` (14 tests): only reachable in acoustic mode; a GREEN
  never shows as normal (no "normal", no triage colours) and passes through unchanged; RED
  shows the Advisory card; without the result step it goes straight to vitals; Cancel →
  INCONCLUSIVE (`cancelled`); mic denied → Open settings and Skip to vitals → INCONCLUSIVE
  (`unavailable`), nothing classified; countdown and Ready text use the configured length;
  rings animate, static with Remove animations; the silence hint after 3 s, gone on sound,
  classification untouched; no hint without level readings; announcements every 5 s and for
  the hint.
- `test/ui_redesign_a11y_test.dart` now also covers Ready, Recording, Microphone blocked and
  the Result advisory row: 48 dp targets, labels, rendered contrast, 130% text at 320/360 dp.
  It caught one real overflow (the advisory row label at 320 dp/130%), fixed.
- Updated without weakening: "Stop & Analyze Early" → the Stop key; the mic-failure tests
  check the new titles, the Open settings button (present only for permission) and that no
  exception text shows; the acoustic-card assertions now check the advisory row, including
  that an acoustic GREEN reads "Couldn't tell".
- `flutter analyze`: no issues. `flutter test`: 404 passed (default), 405 passed (`MOEWS_ONLY=false`).

### Emulator pass and main-thread stalls

`breathing` scenario on the API 24 / 2 GB AVD (debug build, GPU rendering): main thread
longest block 154 ms while recording and 250 ms while analysing; batch 5 measured 148 ms
(API 24) with software rendering and a different test (a plain spinner screen, `s10`), so
this is not like-for-like. Recording frames: median 10.5 ms, 222 of 887 over 16.7 ms, the
worst ones around the two screenshots taken inside that window. A control run (static ring
vs pulse, no screenshots) was added afterwards but its full-pass run did not complete.

### Open questions (round 2)

1. Turn on the Ready and result steps (`BREATHING_STEPS`)? They add a tap each.
2. The design's Home (Screen A) still shows Record vitals in acoustic mode and an Offline
   pill — round 1 conflicts 1 and 2, still open.
3. Is ≈ -50 dBFS for 3 s the right silence threshold on real phones? It is a UI hint only, but
   a too-sensitive hint would nag; it needs a field check on a budget phone.
4. The emulator now renders on the host NVIDIA GPU (local tooling only, see below), so its
   frame figures are not like-for-like with batch 5's software-rendered ones.

## Round 3 — Emergency referral form (updated) and dispatch status

Same branch, confirmed in sync with `origin` before starting. Built in a separate git
worktree while the round 1–2 emulator pass was running (the pass builds from the working
tree), then fast-forwarded onto `feat/ui-redesign`.

Designs saved under `docs/design/stitch/`: `referral-form-updated/` (*Emergency Referral Form
(Updated)*, `a7ac6059…`, now the form's source of truth), `dispatch-status/` (*Dispatch Status
(3 Variants)*, `fadab637…`) and the original `referral-form/` (kept for comparison). HTML via
the Stitch MCP; the hosted URLs still return 401 to `curl -L`.

### Flutter skills used (this round and kept for the next rounds)

All Flutter skills here come from the `dart-flutter` plugin. Loaded and followed:

| Skill | What it changed |
|---|---|
| `flutter-build-responsive-layout` (from round 2) | Bodies scroll and size from `LayoutBuilder` constraints, not device type; Call/SMS go side by side only when the row is wide enough for both at the current text scale. |
| `flutter-fix-layout-issues` | Overflows fixed at the cause: the "Checking for updates…" row's text made `Flexible`, buttons stacked rather than squeezed. I found the culprit by hooking `FlutterError.onError` for the full report. |
| `dart-use-pattern-matching` | One switch expression per timeline step (status → label/state), guards for status groups, records in loops; exhaustive and easy to test. |
| `flutter-apply-architecture-best-practices` | The status → timeline mapping is a pure function (`lib/services/dispatch_timeline.dart`) with no BuildContext, unit-tested on its own; the screen only renders it. Not taken further: the polling/cancel state stays in the screen, because moving it into a ViewModel would risk the behaviour this round must keep. |
| `flutter-add-widget-test` (from round 2) | Its checklist for each new test: build, find by key, interact, pump (fixed durations where something animates or polls), verify. |
| `flutter-add-integration-test` (from round 2) | The device scenarios follow its rules (no `pumpAndSettle` with live polling, keys for targets), on the project's own harness rather than `flutter drive`. |
| `dart-run-static-analysis` | `flutter analyze` after every change; no issues. |

No accessibility-, theming- or animation-specific Flutter skill exists here; the Expo skills
(`expo-animation`, `expo-design-system`) are for React Native and were not used.

### Emergency referral form

- **Send referral** pinned at the bottom, grey (disabled) until an emergency type is chosen,
  with "Choose the emergency type to send" under it. Everything else (name, vitals, facility
  confirmation) is still checked when it's tapped, with the same messages. *Note:* round 1
  reported this as a conflict (it changes how a missing type is communicated: a disabled
  button instead of the "Choose the emergency type" error). It was asked for again, it
  changes nothing about what is sent or when, so it is built.
- **Vitals summary** "Vitals:" with a risk badge (Critical / Elevated / Stable / Incomplete
  and the score). Round 1's objection — a read-only summary beside editable fields could go
  stale — is solved by scoring it live from the form's own fields with the app's MOEWS, so it
  always matches them. Shown when the form came from the vitals step, or once any vital has
  been answered.
- **Emergency: skip vitals** keeps its text and behaviour, and moves into the pinned bar,
  with "Vitals not taken – the hospital will be told" under it. The batch-5 test that the
  skip button is on screen without scrolling at 320×568 failed once the bar was pinned; this
  keeps the one-tap path always visible. The old "Dispatches now. Needs only the emergency
  type and facility." line is replaced by the new one.
- Emergency type chips: the app's current four, none preselected. Send to: chevron only,
  existing picker. Patient name and editable vitals stay (the design has neither; removing
  them would change behaviour).

### Dispatch status

States, each from the dispatch the app already polls:

1. **In progress** (PENDING / TIER1 / TIER2): "Notifying drivers", then "Waiting for a driver
   to accept"; teal "Call a driver instead" link opens the existing Call/SMS panel.
2. **Driver accepted** (ACCEPTED / HOSPITAL_NOTIFIED): "Driver accepted" + driver name;
   current "Waiting for hospital to confirm". HOSPITAL_CONFIRMED: "Hospital confirmed",
   current "On the way to <facility>". COMPLETED: "Arrived" (and "Hospital notified" unless
   the screen saw a confirmation — a trip can complete without one).
3. **No driver** (FAILED): current "No driver has accepted", dark navy card "No driver has
   accepted. Call one now." over the Call/SMS rows (the panel already appears for FAILED).
4. **Diverted**: a done "Diverted" step ("From <old facility>, by the hospital") with a light
   teal note "Now going to <facility>" (brand tint, never yellow).
5. **Not sent yet** (`QueuedReferralScreen`, no dispatch yet): current "Saved on this phone –
   will send when signal returns", the offline policy's honesty text, Retry sync, then a dark
   navy "Urgent? Call a driver now" card over Call/SMS (calling still marks the referral for
   confirmation, as today).

All states: timeline with filled teal circle + check (done), teal ring + dot (current),
grey outline (future); future steps use neutral wording ("Driver accepts", "Hospital
confirms", "Arrives at hospital"), past tense only once it happened. Title "Referral status"
with **Ref <referral id>** — the driver-facing Ref from batch 6, which the API already
returns as `referral_id`; the hospital code is not in the API response and never shown
(tested with a response that includes one). "Cancel referral" is a quiet 48 dp text button
with the existing confirmation and cancel. No ETA (the old "ETA: 12m" line is gone), no map,
no patient name, no triage colours. A small "Checking for updates…" row shows while it polls.

Call/SMS rows: existing cached contacts, "Contacts last updated: …" kept, scroll with the page
(tested to the last row at 320 dp/130%, no overlap); Call and SMS sit side by side, or stack
when narrow; screen readers hear "Call Ibrahim" / "SMS Ibrahim".

### Conflicts with existing behaviour (not built)

1. **Times on completed steps.** The app has no step times: `GET /dispatch/{id}` returns
   status, driver name, facility, diverted_from, tier and a placeholder ETA, but none of the
   timestamps the database holds (`initiated_at`, `driver_assigned_at`, `completed_at`, the
   dispatch log). Showing times needs the API to send them. *Decision needed: extend the API
   (small, backend), or keep the timeline without times?* Phone-observed times were
   considered and rejected: they would show when the phone happened to poll, not when it
   happened.
2. **Vehicle on "Driver accepted"** ("Driver A, motorbike ambulance"). The driver's vehicle
   type is in the database but not in the dispatch response; only the name is shown.
3. **Late acceptance after the cascade failed.** FAILED is a terminal state for the screen's
   polling today, so an open status screen never sees a later acceptance. The timeline
   supports it ("Driver accepted" + "Accepted after the alerts had stopped") when it has seen
   FAILED first, and the server already SMSes the CHO about a late accept; but showing it live
   needs polling to continue after FAILED. *Decision needed.*
4. **"Call a driver instead" while drivers are being alerted** is built (the brief asks for it,
   using the existing panel), but note the risk: a CHO who calls a driver while the cascade
   is still offering the trip could end up with two drivers. The queued screen already guards
   this by asking before alerting drivers once someone was called; the live-dispatch screen has
   no such guard. *Open question.*

### Other deviations from the designs, and why

- **Back arrow** kept (the design's status screen has none): back is how a CHO leaves today.
- **"Back to Home"** button and the "Request: <id>" line kept (existing; not in the design).
- **Navy card icon** white, not the design's amber-300: no triage colours on this screen.
- **Design's fourth/fifth steps**: the design labels the current step "Hospital confirmed"
  (past tense while still waiting); the app says "Waiting for hospital to confirm" as the
  brief requires.
- **Status shown by key, not raw text**: tests now find `dispatch_status_<STATUS>` instead of
  the raw "TIER1_NOTIFIED" text, which no longer appears; integration tests likewise, and
  the release script waits for "Waiting for a driver to accept".
- **"Going to: <facility>"** stays as a small grey line (the diversion tests and screen
  readers use it; the timeline also says it).
- **Commits**: the dispatch states share one screen file, so they are grouped by file (timeline
  model/view; status screen; not-sent-yet screen + Call/SMS rows) rather than one per state.

### Contrast (WCAG AA), new pairs

| Pair | Ratio | Needs |
|---|---|---|
| Navy help card, white on `#0F2744` | 15.06 | 4.5 |
| Diverted note, teal on brand tint | 6.59 | 4.5 |
| Current step label / "Call a driver instead", teal on canvas | 7.15 | 4.5 |
| Done label grey-900 / future label grey-600, on canvas | 17.06 / 7.24 | 4.5 |
| Step detail grey-700 on canvas | 9.90 | 4.5 |
| Ref and "Cancel referral", grey-700 on white / canvas | 10.35 / 9.90 | 4.5 |
| Contact role line grey-600 on white; last-updated grey-700 on canvas | 7.58 / 9.90 | 4.5 |
| Send referral disabled, grey-600 on grey-200 | 6.15 | 3.0 (large) |
| Skip note / send hint, grey-700 on white | 10.35 | 4.5 |
| Risk badge (form summary) | see round 1 | — |
| Done circle teal on canvas; current ring teal (non-text) | 7.15 | 3.0 |
| Future circle outline grey-400 on white (non-text) | **2.56** | 3.0 |

The future-step outline is below 3:1; the step's state is also carried by its grey label and
by the spoken "Not yet: …", so it is not the only cue, but it should be darkened to grey-500
(4.76:1). Not changed in this round because the emulator pass was building from the tree.

### Accessibility and tests

- `test/ui_redesign_dispatch_test.dart` (18): wording for every status (at most one current
  step; past-tense labels only on done steps); waiting / accepted / on the way / completed
  wording; no driver; diverted note; late accept; not sent yet; each step spoken as one
  sentence ("Done: Driver accepted, Ibrahim"); screen per status by key; Ref shown, a
  hospital code in the response never appears; Call a driver instead; Cancel referral (48 dp,
  same confirmation); navy card colour; teal note colour; no ETA; 8 contacts at 320 dp/130%
  text scroll to the last, no rows overlap, buttons 48 dp, "Call Driver 8" / "SMS Driver 8".
- Form: Send disabled until a type is chosen, then name/vitals still validated on tap
  (`vital_inputs_test`, `skip_vitals_test`).
- Accessibility suite: four dispatch states and Not sent yet added (48 dp, labels, rendered
  contrast, 130% text at 320/360 dp).
- `flutter analyze`: no issues. `flutter test`: 442 passed (default), 443 passed
  (`MOEWS_ONLY=false`).

### Open questions (round 3)

1. Extend `GET /dispatch/{id}` with step times and the driver's vehicle (conflicts 1–2)?
2. Keep polling after FAILED so a late acceptance appears live (conflict 3)?
3. "Call a driver instead" during the cascade: add a confirm step, or hide it (conflict 4)?
4. Emergency types are still an open clinical decision (round 1, question 1).

## Verification (fresh install, 2026-11-09)

The emulators were showing the original UI: neither AVD had a normal build of this branch
installed (API 34 had an integration-test build from the pass; API 24 had none). Both were
uninstalled and given fresh debug builds of `daa91cf` (API 24 with `MOEWS_ONLY=false` for
acoustic mode); Home in both modes, Record vitals, Result, the referral form and a real
dispatch status were checked against the Stitch renders. That check found the Record
vitals accessibility bug (fields and four "Not measured" toggles missing from the
accessibility tree) and the clipped validation messages, fixed below.

## Round 4 — decisions, design-system palette, copy, fidelity

Same branch. Flutter skills used: `dart-flutter:flutter-build-responsive-layout`,
`flutter-fix-layout-issues`, `dart-use-pattern-matching`,
`flutter-apply-architecture-best-practices`, `flutter-add-widget-test`,
`flutter-add-integration-test`, `dart-run-static-analysis`.

| Step | Commits |
|---|---|
| 1 Push rounds 2–3, commit this report | `f3368cc` |
| 2 Record vitals accessibility | `3f6fe91` |
| 3 Decisions | `a2a3b8d`, `bb5c867`, `8217ab3` |
| 4 Palette and Recording screen | `a447916`, `f4e4aa8`, `74fcc49` |
| 5 Copy | `423772a` |
| 6 Fidelity | `3262aeb` and the commit that adds this section |

### Step 2 — Record vitals accessibility bug

- **What was wrong:**
  - each "Not measured" toggle was merged into its field's semantics node;
  - the number fields had no name of their own. The placeholder ("—") was the only text,
    and a `Semantics` wrapper does not name a `TextField`'s own node;
  - TalkBack users heard one unnamed editable field per vital, with the toggle hidden inside it.
- **Fix:**
  - each toggle is its own container node, labelled "Blood pressure, systolic: not
    measured" and so on;
  - each field is named through `InputDecoration.label` (floating behaviour "never", so it
    looks the same);
  - validation messages are no longer drawn inside the narrow field. They show at full
    width below the row (key `<field>_error`; for BP, "Systolic: …").
- **Why round 1 missed it:** `labeledTapTargetGuideline` skips every node flagged
  `isTextField`. So a field with a toggle merged into it, or a field with no name, passes
  that guideline. The round-1 checks were the Flutter guidelines plus finders, and finders
  find widgets, not semantics nodes.
- **The stronger check:** `test/ui_redesign_a11y_test.dart` now walks the real semantics
  tree (`semanticsNodes`). `expectSeparateNamedControls` asserts that:
  - every editable field and every tappable node has its own non-empty label;
  - no node is both a text field and a button.

  It runs on every redesigned screen: Home in both modes, Record vitals, Result, the
  referral form, the breathing screens and the dispatch states. On Record vitals it also
  asserts six named fields and seven separate toggles. Checked: the new tests fail on the
  old code.

### Step 3 — decisions

- **Offline pill:**
  - Home shows "Offline" (key `home_offline`) when `connectivity_plus` reports no network;
  - it is display only, and the queue logic is unchanged;
  - a test seam (`online` stream) covers both states. The fidelity shots were taken online,
    so the pill does not appear in them.
- **Patient name:** it was never used to tell queued referrals apart. It was not
  serialized, not stored in the queue, and not shown on any list. It was removed (form
  field and model), so it can never reach the server.
- **Form vitals:**
  - the form's editable vitals are replaced by one summary row, "Vitals: Not recorded" or
    the risk badge, with key `referral_vitals_summary`;
  - the row opens Record vitals with the current values; "Save vitals" returns them;
  - Emergency: skip vitals is unchanged;
  - Send still requires vitals or the skip.
- **Step times:**
  - `GET /dispatch/{id}` now returns `step_times` (sent, drivers_notified, driver_accepted,
    hospital_notified, hospital_confirmed, diverted, completed);
  - they are taken from the existing dispatch and SMS log rows; nothing new is logged;
  - tested in `tests/test_dispatch_step_times.py`;
  - the timeline shows each time in local time ("17:43", or "Yesterday, 09:12").

### Step 4 — palette (Clinical Field Resilience)

- Design system saved in `docs/design/stitch/design-system/`, and the pulse frames in
  `docs/design/stitch/breathing-check/pulse-frames-1-3.png`.
- Font: Atkinson Hyperlegible Next, bundled.
- All colours live in `lib/theme/yoma_theme.dart`. `test/color_tokens_test.dart` fails on
  any `Color(0x…)` or `Colors.*` outside it.
- Red, amber and green appear only in `TriageColors` (risk levels and destructive actions:
  Emergency: skip vitals). Cancel referral stays a quiet text link, as in round 3.

| Before | After | Use |
|---|---|---|
| teal `#005F60` (brand) | primary `#0F2744` | primary buttons incl. Emergency referral, active, focus, timeline markers |
| — | secondary `#1B3B6F` | outlined buttons, selected chips |
| `#B54708` warning / note | tertiary `#2C5E8A` | links, info accents, pulse rings (tints) |
| `#0F172A` navy | neutral `#0B192C` | dark cards and strips |
| `#1E293B` text | `#0E1C2F` | main text |
| `#F8FAFC` canvas | `#F9F9FF` | background |
| `#94A3B8` | `#C4C6CE` outline-variant | hairlines |
| `#64748B` | `#74777E` outline | borders, incomplete |
| `#DCE3EC` muted on dark | `#EBF1FF` | muted text on navy |
| `#B42318`, `#C62828` | error `#BA1A1A` | errors |
| `#067647` success | removed | (green only for triage) |
| `#DC2626` | triage red `#C5221F` | Critical / skip vitals |
| `#D97706`, `#F59E0B` | triage amber `#B45309` | Elevated |
| `Colors.red/white/black` literals | tokens | — |

- Contrast: every text pair on the redesigned screens meets AA (the suite checks it).
- The round-3 future-step circle outline was below 3:1 (outline-variant `#C4C6CE`); it now
  uses outline `#74777E` (4.48:1 on white).
- **Recording screen:** rebuilt to the pulse frames:
  - LISTENING pill; a 138 dp circle with the seconds remaining; an arc showing time left;
  - three tertiary rings that follow the microphone level;
  - Stop as a secondary outlined button;
  - round-2 behaviour kept: silence hint, reduced motion (static ring), auto stop.

### Step 5 — copy

- **No raw codes:** emergency types read from `models/emergency_type.dart` ("pph" → "Heavy
  bleeding"), and statuses read as words.
- **Plurals and relative times:** `countOf` gives "1 warning" and "Saved 1 minute ago".
- **Dates:** "Today, 17:43" and "Yesterday, 09:12" (`services/friendly_time.dart`, 24-hour
  setting respected).
- **Warning list:** the open list no longer repeats its header as the first row.
- **Debug footer:** "Env · model" shows only in test builds, as a small footer.
- Tested in `test/copy_rules_test.dart` and `test/friendly_time_test.dart`.

### Step 6 — fidelity at 360×640 dp

- **Setup:** API 34 emulator at `1080x1920` density 480 (360×640 dp), animations on, debug
  builds of this branch.
- **Side-by-sides:** in `docs/testing/screenshots/ui-redesign/fidelity/` (1 Home MOEWS,
  2 Home acoustic, 3 Recording, 4 Record vitals, 5 Referral form).
- **Fixed in this step:**
  - Home: the title is 18 bold primary; the Emergency referral label is larger; secondary
    buttons are 56 dp with a 2 dp border, a 16 bold label and a 20 dp icon;
  - Recording: no grey status-bar band; "1 second" plural;
  - Record vitals: units are always visible ("— mmHg");
  - Record vitals: "Not measured" sits under the value on the right, as in the design.
    Before, it sat between label and field, which wrapped "Breathing rate" onto two lines;
  - Form: chips are 58 dp; the selected chip uses the design's secondary tint, border and
    bold text.
- **Differences left on purpose:**
  1. Colour: the Stitch renders are teal. The app uses the design-system palette, as
     instructed in step 4.
  2. Home, acoustic mode: there is no Record vitals button. This is round-1 conflict 1 and
     is still undecided.
  3. Home: the Offline pill is not visible because the emulator was online. It appears
     when offline (tested).
  4. Home MOEWS: the Stitch Home render shows a taller Emergency button and a "1 referral
     waiting" strip. The app sizes the button as in Screen A, and the strip appears only
     when something is queued.
  5. Text size: the app's text is larger than the renders because the bundled Atkinson
     Hyperlegible Next is wider than the render's font, and because round 1 set the field
     and label sizes for 48 dp targets.
  6. Record vitals:
     - BP is two fields (systolic and diastolic, each with its own Not measured);
     - the HR helper text and "Fill HR from device (advisory)" are kept as existing
       behaviour;
     - See result stays enabled with "N left" (open question 2);
     - there is no "Clear" chip state: tapping the link again clears.
  7. Referral form:
     - no "Other" type (the type list is the clinical decision from round 1);
     - the facility picker keeps its confirm wording and location line;
     - the vitals row reads "Not recorded" until vitals exist;
     - Emergency: skip vitals is a red button because it is destructive.
  8. Recording: the silence hint shows in the shots because the emulator microphone is
     silent. This is round-2 behaviour.
- **Checks:** `flutter analyze` reports no issues. `flutter test`: 471 passed in the
  default mode and 472 passed with `MOEWS_ONLY=false`. Backend:
  `tests/test_dispatch_step_times.py` and `test_referral_validation.py` pass (run with
  `AT_WEBHOOK_SECRET=`). The 4 `test_startup_config` failures come from the local `.env`
  and were failing before.

### Open questions (round 4)

1. Record vitals in acoustic mode on Home (round-1 conflict 1)?
2. SpO₂ "(optional)", and See result disabled until complete (as the design shows)?
3. Keep polling after FAILED so a late accept shows live?
4. "Call a driver instead" during the cascade: confirm step or hide?
5. Risk words Critical / Elevated / Stable: confirm with clinical leads.
6. Recording arc: time remaining (built) or time elapsed?

## Round 5: round-4 screens fixed, decisions, fidelity on the remaining screens

Same branch, with every commit pushed. Flutter skills used:

- `dart-flutter:flutter-build-responsive-layout`
- `flutter-fix-layout-issues`
- `dart-use-pattern-matching`
- `flutter-add-widget-test`
- `dart-run-static-analysis`
- `flutter-apply-architecture-best-practices`

Commits, in order:

| Step | Commit | What |
|---|---|---|
| 0 | `88f4688` | Record vitals: compact cards, count of required vitals, first-gap jump |
| 0 | `36d903a` | Referral form: one bottom button, one-line Send to, vitals row link |
| 0 | `be3afa1` | Home: heart-pulse icon |
| 0 | `e1b2cc7` | Recording: rings reach the edge with breathing; test shot tool |
| 1.1 | `665c763` | Acoustic Home: three actions; Not screened |
| 1.2 | `94b4756` | Keep checking after FAILED until the late-claim window ends |
| 1.3 | `8a1f9d9` | "Did a driver agree to come?" |
| 1.4 | `6676785` | Sign-off sheet: risk words |
| 2 | `c242e43`, `f169428`, `59b00d1` | Result, dispatch status and breathing fidelity; accessibility suite |
| 3 | this commit | Side-by-sides, report |

### Step 0: typography (no theme change, and why)

The brief said the type scale was far larger than the designs. Measured at the same dp scale,
it is not. The theme's sizes already equal the Clinical Field Resilience scale and the Stitch
code:

| Element | Stitch code | App theme |
|---|---|---|
| App bar title | `text-xl` 20 / bold | 20 / bold |
| Card label (vitals, sections) | `text-base` 16 / semibold | 16 / w600 |
| Buttons | `label-lg` 16 / bold | 16 / bold |
| Chips | `text-[14px]` / semibold | 14 / w600 |
| Small links ("Not measured") | `text-xs` 12 | 12 |

The impression came from round 4's side-by-sides. That composer scaled both images to the same
**pixel height**. The Record vitals reference is 360×1400 px, so it was drawn at about 44% of
the app's scale and every app text looked twice as big.

Every side-by-side in this round puts the Stitch phone at the **same dp scale** as the app
(360 dp → 540 px). Real differences found that way were fixed where they were:

- the vitals cards;
- the result-card text, which was 16/14 against the design's 14/12;
- the dispatch banner, which was 16 against the design's 14.

Tap targets stay 48 dp through padding.

### Step 0: Record vitals, form, Home, Recording

**Record vitals:**

- Label, a two-line "Not measured" and the value sit on one row. All six vitals show at
  360×640; only the second row of consciousness chips needs about 68 dp of scroll.
- On narrow screens or with large text, the layout is stacked (as before).
- "See result – N left" counts blood pressure (one item), heart rate, breathing rate,
  temperature and consciousness, so it shows 5 when nothing is filled. SpO₂ is never counted,
  shows "(optional)", and may be left blank.
- Blood pressure has one card and one "Not measured" for both fields. An empty pair gives one
  message.
- The "Normal adult band…" helper is gone. "From device ›" is a small link in the Heart rate
  card.
- See result stays enabled. With gaps, it scrolls to the first missing or wrong vital, marks
  its card red and announces it by name (for example, "Consciousness missing. Choose a level
  or tick Not measured.").
- Form's own generic first-error announcement is switched off for this form, so a screen
  reader hears one message.
- Tests: `test/vitals_required_test.dart`.

**Referral form:**

- There is one bottom button: "Send referral" with vitals, or "Send now (vitals not taken)"
  without. The second uses the existing skip-vitals path and hospital notice. The red button
  is gone.
- The button is disabled until a type is chosen.
- The vitals row reads "Not recorded – Record vitals ›".
- Send to is one line plus a small "Tap to confirm" until confirmed; the confirm behaviour is
  unchanged. The origin line and the CHPS name are off the form; the picker still shows the
  origin.
- Tests: `test/referral_form_layout_test.dart`. Type chips, Send to and the vitals row scroll
  fully clear of the bottom area at 360 dp and at 320 dp with 130% text.

**Home:** the design's Lucide heart-pulse for Record vitals.

**Recording:**

- Before, the rings only reached the box edge at about −5 dBFS, so with real breathing they
  stayed near the circle. They also faded to 8%.
- Now:
  - −55 to −20 dBFS spans the level;
  - the rings travel the full way from about −30 dBFS, as in pulse frame 3;
  - silence keeps them near the circle, as in frame 1;
  - the faintest ring is about 18%.
- The silence hint threshold is unchanged at −50 dBFS.
- Tested with a fake microphone stream (`test/recording_pulse_test.dart`).
- Audio was not played into an emulator microphone: the emulator would not start this round
  (see Step 3).

### Step 1: decisions

1. **Acoustic Home** shows Emergency referral, Check breathing, Record vitals, in that order.
   This order follows the decision; the design's Screen A puts Record vitals second.
   - A referral without a breathing check sends `ai_screen_result` `NOT_SCREENED`. That covers
     a referral straight from Home and one via Record vitals from Home.
   - The form says "No breathing check – the hospital will be told".
   - The hospital SMS adds "Breathing check: not screened" (`tests/test_not_screened.py`).
   - MOEWS-only builds are unchanged.
2. **After FAILED:**
   - `GET /dispatch/{id}` returns `late_claim_until`: `initiated_at` plus
     `LATE_CLAIM_WINDOW_MINUTES` (45), in UTC. The orchestrator now uses the same function to
     accept late claims.
   - Until that time, the status screen checks every 30 s and says "Still checking: a driver
     can accept until 12:42".
   - A late acceptance shows as accepted ("Accepted after the alerts had stopped").
   - After the window it stops.
3. **Call a driver instead:**
   - There is no confirm before the call.
   - A tel: call from the status screen before any driver accepted arms one question for when
     the CHO returns to the app: "Did a driver agree to come?". Yes runs the existing cancel;
     No keeps waiting.
   - It is asked once per call.
4. **Critical / Elevated / Stable** is now question 6 in `docs/PARAMETERS_SIGNOFF.md`.

### Step 2: fidelity on the remaining screens

Fixed:

- **Result:**
  - Buttons are in sentence case.
  - Stable's secondary button is "Confirm referral".
  - Stable lists BP, heart rate, breathing rate and temperature "– normal" with grey dots.
  - The Incomplete card has no subtitle.
  - Missing systolic and diastolic are one "Blood pressure" row.
- **Dispatch status:**
  - With no driver, not sent yet or no connection, the banner and the Call/SMS rows come
    first.
  - Rows are compact: name and role on the left, Call and SMS on the right, drivers first,
    then the hospital.
  - The current step is in the tertiary colour with a halo.
  - The driver is shown in a bordered card.
  - There is more space between steps.
  - The spinner line and the raw "Request: …" id are removed.
  - The banner text is 14 bold.
- **Breathing:**
  - The dashed border on "Couldn't tell" was painted behind the white fill and never showed;
    it is now drawn in front.
  - Card text is at the design's sizes.
  - "settings" is lower case.
- **Copy:** no raw codes, plurals or dates were found on these screens beyond the "Request:"
  id, which is removed.

Differences left on purpose. Each is a decision above or an earlier documented correction:

1. **Colour:** the design-system palette (round 4) instead of the renders' teal, and the
   design-system amber.
2. **MOEWS name** under the risk word, and the disclaimer line (round 1, for CHO
   familiarity and safety).
3. **Critical/Elevated:** the design's bottom area repeats the Why list (a design bug); the app
   has its buttons there.
4. **Timeline wording:**
   - Future-tense labels and the darker future labels (round 3, contrast and wording rules).
   - Times follow the phone's 12/24-hour setting. The shots show "9:12 AM" because the
     renderer's locale is 12-hour.
5. **Dispatch extras:**
   - Ref, "Going to: <hospital>" (the destination changes on a diversion), "Back to Home"
     (the design gives no way back) and "Cancel referral" (round-3 brief).
   - "Contacts last updated" stays, because the rows are a cached copy.
6. **Analysing subtitle:** "You can keep using the phone." instead of "Analyzing breath rate
   and sound patterns". The model does not measure breath rate, so the design's line would
   claim something false.
7. **Breathing result footer:** the Ready screen's "This is advice only…" instead of "Field
   guidance: Results do not replace nurse auscultation" (CHOs are not nurses).
8. **Dashed border:** grey-500 instead of slate-300, for 3:1 non-text contrast.
9. **MOEWS Home Emergency button:** sized to Screen A (round 4) rather than the older
   home-minimal render.

### Accessibility

The semantics-tree check (`expectSeparateNamedControls`), the 48 dp and label guidelines and
rendered contrast now also run on:

- Analysing;
- both breathing results;
- hospital confirmed and arrived;
- the late acceptance;
- "Did a driver agree to come?";
- acoustic Home with three actions, offline.

These join every screen from rounds 1–4.

### Step 3: side-by-sides and checks

- **Side-by-sides:** in `docs/testing/screenshots/ui-redesign/fidelity/`, replacing round 4's:
  1. Home MOEWS (offline);
  2. Home acoustic;
  3. Recording against pulse frames 1 and 3;
  4. Record vitals (empty, and after See result with gaps);
  5. Referral form (no type, type chosen, vitals recorded);
  6. Result (four variants and the advisory row);
  7. Dispatch status (waiting, accepted, confirmed, arrived, no driver, late acceptance, "Did
     a driver agree?");
  8. Breathing (ready, analysing, both results, microphone blocked).

  Every Stitch phone is at the same dp scale as the app.
- **How the app images were made:** the API 34 emulator crashed during cold boot three times
  (exit 139). That happened on the NVIDIA GPU with and without Vulkan, while KVM and NVIDIA
  OpenGL both checked out fine. So the app images are **Flutter renders**: the same engine,
  the bundled Atkinson Hyperlegible Next and Material Icons, at 360×640 dp ×3. They come from
  `test/shots/*_shot.dart`, which is not part of the default test run. They have no system
  status bar, and the back arrow is missing because each screen is shown as the first route.
  A device pass is still owed.
- **`flutter analyze`:** no issues.
- **`flutter test`:** 509 passed (default), 510 passed (`MOEWS_ONLY=false`).
- **Backend:** `test_not_screened`, `test_dispatch_step_times` (with `late_claim_until`),
  `test_skip_vitals`, `test_hospital_privacy`, `test_diversion` and `test_parameters` pass
  (run with `AT_WEBHOOK_SECRET=`).

### Open questions (round 5)

1. Why does the API 34 emulator now crash during cold boot (exit 139)? It worked in round 4.
   Needs a look before the device pass.
2. Should "Going to: <hospital>" and "Back to Home" on the status screen stay? The design has
   neither.
3. The design's "Driver A – motorbike ambulance" needs the vehicle from the API (round 3,
   conflict 2).
