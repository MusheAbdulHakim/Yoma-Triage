# Breathing check flow — Stitch reference (UI redesign round 2)

Stitch screen: *Yoma Care - Breathing Check Flow (6 Screens)* (`1635e5aae3144c37af5b5b65932a6204`)
in project `3335194134719283465`.

- `code.html` — the Stitch HTML/CSS, fetched through the Stitch MCP `download_file` tool.
  Reference for sizes and spacing only; nothing is ported.
- `screens-b-c.png`, `screens-d-e-f.png` — captures of the Stitch canvas supplied by the user
  with the round-2 brief (Ready, Recording frames 1–2; Analysing, Result variants,
  Microphone blocked).

The Stitch-hosted screenshot (`files/5663957688075891297`) returns HTTP 401 to `curl -L`
without the Stitch credential; see `../README.md` for how to add it.

The file has no Result-screen breathing advisory row, so that row follows the round-2 brief.
