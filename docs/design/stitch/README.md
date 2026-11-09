# Stitch design references — UI redesign round 1

Project: Yoma Care Emergency App UI (`3335194134719283465`)

| Folder | Stitch screen | Screen ID |
|---|---|---|
| `home-minimal/` | Yoma Care Home - Minimal | `0c1ca010c6984cd793e3054544b54792` |
| `record-vitals/` | Yoma Care - Record vitals (Updated) | `242b9643b86c4c138167a04d56b1c4fd` |
| `home-failed-referral/` | Yoma Care Home - Failed Referral (Dark Navy) | `699afd1d8b2a479798c6c22735046150` |
| `result-variants/` | Yoma Care - Result (4 Variants Updated) | `9b099c50b9a4433a8b27f10451c55b5f` |
| `referral-form/` | Yoma Care - Emergency Referral Form | `5cee8d13c1494c83bf85d1de65259fcd` |

Each folder has:

- `code.html` — the Stitch HTML/CSS, downloaded through the Stitch MCP `download_file` tool.
  Reference material only (colours, sizes, spacing, radii, fonts); nothing here is
  ported into the app.
- `render-from-code.png` — `code.html` rendered locally in headless Chromium. **Not** the
  Stitch-hosted screenshot. Fonts and Tailwind come from their CDNs at render time, so it is
  close to, but not pixel-identical with, the Stitch image.

## Missing: the Stitch-hosted screenshots

The hosted `downloadUrl`s return HTTP 401 to a plain `curl -L` (they need the Stitch
credential). The MCP tool returns screenshots only as inline base64, which cannot be written
to disk reliably from the agent session. To add them, run (with your Stitch API key):

```sh
curl -L -H "X-Goog-Api-Key: $STITCH_API_KEY" -o home-minimal/screen.jpg \
  "https://stitch.googleapis.com/v1/projects/3335194134719283465/files/5974181460452335033:download"
# record-vitals        files/screenshot_00065fc75a35e657044f4d1b13332889
# home-failed-referral files/screenshot_00065fc743eaca4c05fda7e092289259
# result-variants      files/screenshot_00065fc78bcec8560479fbccca111d45
# referral-form        files/screenshot_00065fc7f90c23de09688609b7088613
```

(The API may return a JSON wrapper rather than raw bytes; if so, decode its base64 field.)

## Known issues in the designs themselves

- Result, RED and AMBER variants: the "Fixed Bottom Actions" block repeats the Why list
  instead of holding buttons. The app keeps its existing action buttons for those levels.
- Teal differs between screens: `#0D5C63` (Home), `#0E6569` (Record vitals), `#005F60`
  (Result, Referral — labelled "Brand Teal"). The app uses `#005F60`.
- Fonts differ: Inter (Home, Record vitals) vs Atkinson Hyperlegible Next (Result, Referral).
  The app uses Atkinson Hyperlegible Next everywhere.
