"""Run the Yoma Triage MVP's judge-visible local API demonstration."""
import asyncio
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import httpx

# The seeded CHO for compound 1.
DEMO_CHO_PHONE = "+233240000100"
BASE_URL = __import__("os").getenv("DEMO_API_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
HAPPY_PATH_HASH = "0123456789abcdef" * 4
DECLINE_PATH_HASH = "fedcba9876543210" * 4


def _api_headers() -> dict[str, str]:
    from src.config import settings

    key = settings.API_KEY.strip()
    return {"X-API-Key": key} if key else {}


def _webhook_params() -> dict[str, str]:
    from src.config import settings

    secret = settings.AT_WEBHOOK_SECRET.strip()
    return {"secret": secret} if secret else {}


class Demo:
    def __init__(self) -> None:
        self.started_at = time.monotonic()

    def log(self, message: str) -> None:
        elapsed = int(time.monotonic() - self.started_at)
        print(f"[{elapsed // 60:02d}:{elapsed % 60:02d}] {message}")


def ensure_seed() -> None:
    result = subprocess.run(
        [sys.executable, "-m", "src.db.seed"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Unable to seed demo data")


def critical_referral(patient_hash: str) -> dict[str, Any]:
    return {
        "chps_compound_id": 1,
        "facility_id": 1,
        "patient_hash": patient_hash,
        "client_request_id": str(uuid.uuid4()),
        "cho_phone": DEMO_CHO_PHONE,
        "emergency_type": "pph",
        "gestational_weeks": 38,
        "vitals": {
            "systolic_bp": 70,
            "diastolic_bp": 50,
            "heart_rate": 140,
            "respiratory_rate": 35,
            "temperature": 37.0,
            "spo2": 92,
            "consciousness_level": "V",
        },
    }


async def resolve_demo_actors(client: httpx.AsyncClient) -> dict[str, str]:
    """Resolve live seed phones (may differ from demo_data.json after remaps)."""
    drivers_resp = await client.get("/api/v1/compound/1/drivers")
    drivers_resp.raise_for_status()
    by_name = {d["name"]: d["phone"] for d in drivers_resp.json()["drivers"]}
    required = ("Ibrahim", "Musah", "Abdul")
    missing = [n for n in required if n not in by_name]
    if missing:
        raise RuntimeError(f"Missing demo drivers in compound 1: {', '.join(missing)}")

    contacts = await client.get("/api/v1/compound/1/contacts")
    contacts.raise_for_status()
    facilities = {f["id"]: f["phone"] for f in contacts.json()["facilities"]}
    return {
        "ibrahim": by_name["Ibrahim"],
        "musah": by_name["Musah"],
        "abdul": by_name["Abdul"],
        "hospital": facilities[1],
        "hospital_2": facilities[2],
    }


async def hospital_code(dispatch_id: int) -> str:
    """The code in the hospital's notice. A real hospital reads it off its SMS."""
    from sqlalchemy.ext.asyncio import create_async_engine

    from src.config import settings
    from src.db.models import Dispatch

    engine = create_async_engine(settings.DATABASE_URL)
    try:
        async with engine.connect() as conn:
            code = await conn.scalar(
                Dispatch.__table__.select()
                .with_only_columns(Dispatch.hospital_code)
                .where(Dispatch.id == dispatch_id)
            )
    finally:
        await engine.dispose()
    if not code:
        raise AssertionError(f"Dispatch {dispatch_id} has no hospital code yet")
    return code


async def hospital_says(
    client: httpx.AsyncClient, phone: str, text: str
) -> dict[str, Any]:
    response = await client.post(
        "/api/v1/sms/inbound", params=_webhook_params(), json={"from": phone, "text": text}
    )
    response.raise_for_status()
    return response.json()


async def create_referral(
    client: httpx.AsyncClient, payload: dict[str, Any]
) -> tuple[dict[str, Any], dict[str, Any]]:
    response = await client.post("/api/v1/referral", json=payload)
    response.raise_for_status()
    body = response.json()
    return body["referral"], body["dispatch"]


async def dispatch_logs(client: httpx.AsyncClient, dispatch_id: int) -> list[dict[str, Any]]:
    response = await client.get(f"/api/v1/dispatch/{dispatch_id}/logs")
    response.raise_for_status()
    return response.json()["logs"]


async def wait_for_actions(
    client: httpx.AsyncClient, dispatch_id: int, *actions: str
) -> list[dict[str, Any]]:
    required = set(actions)
    for _ in range(60):
        logs = await dispatch_logs(client, dispatch_id)
        if required.issubset({log["action"] for log in logs}):
            return logs
        await asyncio.sleep(0.25)
    raise AssertionError(f"Timed out waiting for dispatch logs: {', '.join(actions)}")


async def wait_for_sms_recipients(
    client: httpx.AsyncClient, dispatch_id: int, *phones: str
) -> list[dict[str, Any]]:
    required = set(phones)
    for _ in range(60):
        logs = await dispatch_logs(client, dispatch_id)
        recipients = {
            log["target_phone"] for log in logs if log["action"] == "sms_send"
        }
        if required.issubset(recipients):
            return logs
        await asyncio.sleep(0.25)
    raise AssertionError(f"Timed out waiting for SMS recipients: {', '.join(phones)}")


async def wait_for_hospital_notice(
    client: httpx.AsyncClient, dispatch_id: int, phone: str
) -> None:
    for _ in range(60):
        logs = await dispatch_logs(client, dispatch_id)
        if any(
            log["action"] == "hospital_notify" and log["target_phone"] == phone for log in logs
        ):
            return
        await asyncio.sleep(0.25)
    raise AssertionError(f"Timed out waiting for the hospital notice to {phone}")


async def ussd(client: httpx.AsyncClient, phone_number: str, choice: str) -> str:
    from src.config import settings

    service_code = settings.AT_USSD_SERVICE_CODE or "*123#"
    response = await client.post(
        "/ussd/callback",
        params=_webhook_params(),
        data={
            "sessionId": f"demo-{time.monotonic_ns()}",
            "serviceCode": service_code,
            "phoneNumber": phone_number,
            "text": choice,
        },
    )
    response.raise_for_status()
    return response.text


async def main() -> None:
    demo = Demo()
    ensure_seed()
    demo.log("Seed data ready: Tamale South CHPS, drivers, and hospitals")

    async with httpx.AsyncClient(
        base_url=BASE_URL, timeout=60.0, headers=_api_headers()
    ) as client:
        try:
            health = await client.get("/")
            health.raise_for_status()
        except httpx.HTTPError as exc:
            raise RuntimeError(
                f"Yoma Triage API is unavailable at {BASE_URL}. "
                "Start it with ./venv/bin/python main.py "
                "(or set DEMO_API_BASE_URL)."
            ) from exc

        actors = await resolve_demo_actors(client)
        ibrahim, musah, abdul = actors["ibrahim"], actors["musah"], actors["abdul"]
        hospital, hospital_2 = actors["hospital"], actors["hospital_2"]
        demo.log(f"Actors: Ibrahim={ibrahim} Musah={musah} Abdul={abdul}")

        # Happy path: accept, mock payment, hospital notification, and confirmation.
        referral, dispatch = await create_referral(
            client, critical_referral(HAPPY_PATH_HASH)
        )
        assert "patient_name" not in referral
        assert "Ama" not in str(referral)
        dispatch_id, ref = dispatch["id"], referral["id"]
        demo.log(f"Referral created: #REF-{ref:03d}")
        demo.log(
            f"MOEWS: {referral['moews_score']} ({referral['risk_level']}) — "
            "Critical: BP 70/50, HR 140, RR 35"
        )
        initial_logs = await wait_for_actions(client, dispatch_id, "sms_send")
        assert any(log["target_phone"] == ibrahim for log in initial_logs)
        demo.log(f"Cascade: SMS → Driver Ibrahim ({ibrahim})")

        offer_screen = await ussd(client, ibrahim, f"1*{ref}")
        assert f"Ref {ref}: PPH bleeding" in offer_screen, offer_screen
        demo.log(f"Ibrahim's USSD shows: {offer_screen.splitlines()[0][4:]}")
        accept_response = await ussd(client, ibrahim, f"1*{ref}*1")
        assert "Accepted" in accept_response, accept_response
        demo.log("Ibrahim: ACCEPTED via USSD (now ON TRIP)")
        accepted_logs = await wait_for_actions(
            client, dispatch_id, "momo_escrow", "hospital_notify", "cho_accept_notify"
        )
        momo = next(log for log in accepted_logs if log["action"] == "momo_escrow")
        transaction_id = momo["metadata"]["transaction_id"]
        hospital_log = next(
            log for log in accepted_logs if log["action"] == "hospital_notify"
        )
        demo.log(f"Mock MoMo: GHS 22.50 fuel stipend logged (tx={transaction_id})")
        demo.log(
            f"Hospital SMS → {hospital_log['target_phone']} "
            f"({hospital_log['response']}); CHO told the driver is coming"
        )
        meta = hospital_log.get("metadata") or {}
        if meta.get("patient_token_prefix") or meta.get("message_preview"):
            demo.log("Hospital notify logged without full SMS body ✓")
        else:
            demo.log("WARN: hospital notify metadata missing privacy-safe fields")

        status = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["status"]
        assert status == "HOSPITAL_NOTIFIED"
        demo.log("Status: HOSPITAL_NOTIFIED ✓")

        code = await hospital_code(dispatch_id)
        refused = await hospital_says(client, ibrahim, f"CONFIRM {code}")
        assert refused["status"] == "NOT_YOUR_DISPATCH", refused
        demo.log("Driver's phone tries CONFIRM: refused ✓")
        confirmation = await hospital_says(client, hospital, f"CONFIRM {code}")
        assert confirmation["status"] == "CONFIRMED", confirmation
        demo.log(f"Hospital: CONFIRM {code} received ✓")

        arrival_response = await ussd(client, ibrahim, "2*1")
        assert "Arrival confirmed" in arrival_response, arrival_response
        await wait_for_actions(
            client, dispatch_id, "arrival_confirm", "cho_arrival_notify", "hospital_arrival_notify"
        )
        completed = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["status"]
        assert completed == "COMPLETED"
        demo.log("Ibrahim: ARRIVAL confirmed via USSD ✓ (CHO and hospital told)")
        demo.log("Status: COMPLETED ✓")

        # Decline path: exhaust tier-1 Motor-Kings, then escalate to personal (Abdul).
        decline_referral, decline_dispatch = await create_referral(
            client, critical_referral(DECLINE_PATH_HASH)
        )
        decline_id, decline_ref = decline_dispatch["id"], decline_referral["id"]
        demo.log(f"Referral created: #REF-{decline_ref:03d} (decline path)")
        decline_response = await ussd(client, ibrahim, f"1*{decline_ref}*2")
        assert "declined" in decline_response.lower(), decline_response
        demo.log("Ibrahim: DECLINED via USSD")
        await wait_for_actions(client, decline_id, "ussd_decline", "decline_tier_remaining")
        demo.log("Cascade: same-tier Motor-King still available (Musah) — no premature escalate")

        decline_musah = await ussd(client, musah, f"1*{decline_ref}*2")
        assert "declined" in decline_musah.lower(), decline_musah
        demo.log("Musah: DECLINED via USSD (tier-1 exhausted)")
        await wait_for_actions(client, decline_id, "sms_send")
        escalation_logs = await wait_for_sms_recipients(client, decline_id, abdul)
        notified_phones = {
            log["target_phone"] for log in escalation_logs if log["action"] == "sms_send"
        }
        assert abdul in notified_phones
        demo.log(f"Cascade: escalated SMS → Abdul ({abdul})")

        accept_response = await ussd(client, abdul, f"1*{decline_ref}*1")
        assert "Accepted" in accept_response, accept_response
        await wait_for_actions(client, decline_id, "momo_escrow", "hospital_notify")
        demo.log("Abdul: ACCEPTED via USSD; hospital notified")

        # Diversion: the hospital sends the patient elsewhere, and the trip carries on.
        code = await hospital_code(decline_id)
        diversion = await hospital_says(client, hospital, f"DIVERT {code} 2")
        assert diversion["status"] == "DIVERTED", diversion
        diverted = (await client.get(f"/api/v1/dispatch/{decline_id}")).json()
        assert diverted["status"] == "HOSPITAL_NOTIFIED", diverted
        assert diverted["facility_id"] == 2
        demo.log(
            f"Hospital: DIVERT {code} 2 → {diverted['facility_name']} "
            f"(from {diverted['diverted_from']}) ✓"
        )
        await wait_for_actions(client, decline_id, "divert_notify")
        await wait_for_hospital_notice(client, decline_id, hospital_2)
        demo.log("New hospital, old hospital, Abdul and the CHO all told ✓")

        new_code = await hospital_code(decline_id)
        confirmation = await hospital_says(client, hospital_2, f"CONFIRM {new_code}")
        assert confirmation["status"] == "CONFIRMED", confirmation
        demo.log(f"New hospital: CONFIRM {new_code} received ✓")

        arrival_response = await ussd(client, abdul, "2*1")
        assert "Arrival confirmed" in arrival_response, arrival_response
        await wait_for_actions(client, decline_id, "arrival_confirm", "hospital_arrival_notify")
        completed = (await client.get(f"/api/v1/dispatch/{decline_id}")).json()
        assert completed["status"] == "COMPLETED", completed
        demo.log(f"Abdul: ARRIVAL at {completed['facility_name']} confirmed ✓")
        demo.log("Status: COMPLETED after diversion ✓")

    demo.log("Demo complete ✓")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (AssertionError, RuntimeError, httpx.HTTPError, ModuleNotFoundError) as exc:
        print(f"Demo failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
