# Yoma Triage CHO App

Flutter **cross-platform** CHO client in **`mobile/`** — same codebase for:

| Platform | Screening | Offline outbox |
|----------|-----------|----------------|
| **Android** | Mic + YAMNet TFLite (stub fallback) | SQLite |
| **iOS** | Mic + YAMNet TFLite (stub fallback) | SQLite |
| **Web** | Demo Normal / Demo Code Red simulator | SharedPreferences |

Emergency referral + dispatch status polling work on all three.

## Run

Always pass `API_BASE_URL` for physical phones (LAN IP or `PUBLIC_BASE_URL` / ngrok). Emulator/simulator defaults are in `lib/config.dart`.

Screening length comes from repo-root `.env` → `SCREENING_DURATION_SEC` (app default **15** if omitted). Source `.env` then pass both defines:

```bash
cd /var/www/html/unicef
set -a && source .env && set +a
cd mobile
flutter run -d emulator-5554 \
  --dart-define=API_BASE_URL="${PUBLIC_BASE_URL:-http://10.0.2.2:8000}" \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
```

### Web (demo simulator)

```bash
cd mobile
flutter pub get
flutter run -d chrome --web-port=8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
```

### Android

```bash
# Emulator (host API via 10.0.2.2 by default)
flutter run -d android \
  --dart-define=API_BASE_URL=http://10.0.2.2:8000 \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"

# Physical device (use your machine LAN IP or tunnel)
flutter run -d android \
  --dart-define=API_BASE_URL=https://YOUR-TUNNEL.ngrok-free.app \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
```

`RECORD_AUDIO` is in `AndroidManifest.xml`.

### iOS

```bash
# Simulator (loopback reaches the Mac API)
flutter run -d ios \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"

# Physical iPhone (LAN IP or tunnel; mic permission prompt on first screen)
flutter run -d ios \
  --dart-define=API_BASE_URL=https://YOUR-TUNNEL.ngrok-free.app \
  --dart-define=SCREENING_DURATION_SEC="${SCREENING_DURATION_SEC:-15}"
```

Microphone: `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist`.

Requires Xcode + CocoaPods on macOS for device/simulator builds.

## YAMNet model

| Item | Detail |
|------|--------|
| Path | `assets/models/yamnet.tflite` |
| Source | MediaPipe public YAMNet TFLite ([download](https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/1/yamnet.tflite)) |
| Fetch script | `../scripts/fetch_yamnet.sh` from repo root (override with `YAMNET_URL=...`) |

If the model file is missing, **Android and iOS** fall back to the **stub** classifier. Respiratory scoring uses AudioSet class indices 36–42 (breathing, wheeze, gasp, pant, snort, cough).

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
