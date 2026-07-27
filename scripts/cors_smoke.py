#!/usr/bin/env python3
"""Live CORS smoke against a running Yoma Triage API (no hardcoded tunnel URLs)."""
from __future__ import annotations

import os
import sys
from urllib.parse import urlparse

import httpx

API = os.getenv("DEMO_API_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
# Origins Flutter web commonly uses when started with a fixed --web-port.
DEFAULT_ORIGINS = [
    "http://localhost:8080",
    "http://127.0.0.1:8080",
    "http://localhost:5000",
    "http://127.0.0.1:5000",
    "http://localhost:7357",
    "http://127.0.0.1:7357",
]


def _origins() -> list[str]:
    raw = os.getenv("CORS_SMOKE_ORIGINS", "").strip()
    if raw:
        return [o.strip() for o in raw.split(",") if o.strip()]
    return list(DEFAULT_ORIGINS)


def check_origin(client: httpx.Client, origin: str) -> tuple[bool, str]:
    pre = client.options(
        f"{API}/api/v1/referral",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )
    acao = pre.headers.get("access-control-allow-origin")
    ok = pre.status_code == 200 and acao == origin
    detail = f"OPTIONS http={pre.status_code} acao={acao!r}"
    get = client.get(f"{API}/", headers={"Origin": origin})
    get_acao = get.headers.get("access-control-allow-origin")
    ok = ok and get_acao == origin
    detail += f" | GET acao={get_acao!r}"
    return ok, detail


def main() -> int:
    origins = _origins()
    print(f"API={API}")
    failed = 0
    with httpx.Client(timeout=10.0) as client:
        health = client.get(f"{API}/")
        health.raise_for_status()
        body = health.json()
        public = body.get("public_base_url")
        if public:
            # Public tunnel as API host is fine; as browser Origin only if Flutter is served there.
            host = urlparse(public).hostname
            print(f"public_base_url set (host={host}); not used as Flutter Origin unless you serve web there")

        for origin in origins:
            ok, detail = check_origin(client, origin)
            mark = "PASS" if ok else "FAIL"
            print(f"[{mark}] {origin} — {detail}")
            if not ok:
                failed += 1

        evil_ok, evil_detail = check_origin(client, "http://evil.example.com")
        # Expect FAIL (no echo)
        if evil_ok:
            print(f"[FAIL] evil origin unexpectedly allowed — {evil_detail}")
            failed += 1
        else:
            print(f"[PASS] evil origin denied — {evil_detail}")

    if failed:
        print(
            "\nAdd missing origins to CORS_ORIGINS in .env and reload the API.\n"
            "Flutter web SOP: flutter run -d chrome --web-port=8080 "
            "--dart-define=API_BASE_URL=http://127.0.0.1:8000",
            file=sys.stderr,
        )
        return 1
    print("\nCORS smoke OK for configured Flutter web origins.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
