# Yoma Triage CHO App

Flutter app for Community Health Officers in **`mobile/`**.

Breathing screen (YAMNet on Android/iOS with stub fallback; web simulator), emergency referral with SQLite offline outbox, and dispatch status polling.

## Run

### Web (demo simulator)

```bash
cd mobile
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Use **Demo Normal** / **Demo Code Red** on the screening screen. Web does not run TFLite — advisory disclaimers always apply.

### Android

```bash
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`RECORD_AUDIO` is declared in `AndroidManifest.xml`. With `assets/models/yamnet.tflite` present, native YAMNet inference runs; otherwise the stub classifier is used.

### iOS

```bash
flutter run -d ios --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Microphone access requires the usage string in `ios/Runner/Info.plist` (`NSMicrophoneUsageDescription`).

## YAMNet model

| Item | Detail |
|------|--------|
| Path | `assets/models/yamnet.tflite` |
| Source | MediaPipe public YAMNet TFLite ([download](https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/1/yamnet.tflite)) |
| Fetch script | `../scripts/fetch_yamnet.sh` from repo root (override with `YAMNET_URL=...`) |

If the model file is missing, Android/iOS fall back to the **stub** classifier. Respiratory scoring uses AudioSet class indices 36–42 (breathing, wheeze, gasp, pant, snort, cough).

### Clinical honesty

- Screening output is **advisory only** — not a diagnosis and not clinically validated for obstetric care.
- YAMNet detects general audio events; it is **not** an obstetric diagnostic tool.
- CHO clinical judgment and MOEWS vitals always take precedence.

## Patient privacy

Referral JSON uses a cryptographically random **SHA-256 patient token** (`patient_hash`). Patient names stay in-memory on device only and are never written to the offline outbox or API payload.

## Verify

```bash
flutter analyze
flutter test
```

## Theme

Brand teal `#1A5F7A` via `lib/theme/yoma_theme.dart`.
