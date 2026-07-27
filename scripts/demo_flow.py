"""Run the Yoma Triage MVP's judge-visible local API demonstration."""
import asyncio
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

import httpx


BASE_URL = __import__("os").getenv("DEMO_API_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
HAPPY_PATH_HASH = "0123456789abcdef" * 4
DECLINE_PATH_HASH = "fedcba9876543210" * 4


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
        "emergency_type": "Obstetric haemorrhage",
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

    hospital = "+233240000200"
    return {
        "ibrahim": by_name["Ibrahim"],
        "musah": by_name["Musah"],
        "abdul": by_name["Abdul"],
        "hospital": hospital,
    }


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


async def ussd(client: httpx.AsyncClient, phone_number: str, choice: str) -> str:
    from src.config import settings

    service_code = settings.AT_USSD_SERVICE_CODE or "*123#"
    response = await client.post(
        "/ussd/callback",
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

    async with httpx.AsyncClient(base_url=BASE_URL, timeout=60.0) as client:
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
        ibrahim, musah, abdul, hospital = (
            actors["ibrahim"],
            actors["musah"],
            actors["abdul"],
            actors["hospital"],
        )
        demo.log(f"Actors: Ibrahim={ibrahim} Musah={musah} Abdul={abdul}")

        # Happy path: accept, mock payment, hospital notification, and confirmation.
        referral, dispatch = await create_referral(
            client, critical_referral(HAPPY_PATH_HASH)
        )
        assert "patient_name" not in referral
        assert "Ama" not in str(referral)
        dispatch_id = dispatch["id"]
        demo.log(f"Referral created: #REF-{referral['id']:03d}")
        demo.log(
            f"MOEWS: {referral['moews_score']} ({referral['risk_level']}) — "
            "Critical: BP 70/50, HR 140, RR 35"
        )
        initial_logs = await wait_for_actions(client, dispatch_id, "sms_send")
        assert any(log["target_phone"] == ibrahim for log in initial_logs)
        demo.log(f"Cascade: SMS → Driver Ibrahim ({ibrahim})")

        accept_response = await ussd(client, ibrahim, "1")
        assert "Accepted" in accept_response, accept_response
        demo.log("Ibrahim: ACCEPTED via USSD")
        accepted_logs = await wait_for_actions(
            client, dispatch_id, "momo_escrow", "hospital_notify"
        )
        momo = next(log for log in accepted_logs if log["action"] == "momo_escrow")
        transaction_id = momo["metadata"]["transaction_id"]
        hospital_log = next(
            log for log in accepted_logs if log["action"] == "hospital_notify"
        )
        demo.log(f"Mock MoMo: GHS 22.50 fuel stipend logged (tx={transaction_id})")
        demo.log(
            f"Hospital SMS → {hospital_log['target_phone']} "
            f"({hospital_log['response']})"
        )
        meta = hospital_log.get("metadata") or {}
        msg = meta.get("message") or ""
        if "Driver phone:" in msg:
            demo.log("Hospital SMS includes driver phone ✓")
        else:
            demo.log("WARN: hospital SMS metadata missing Driver phone line")

        status = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["status"]
        assert status == "HOSPITAL_NOTIFIED"
        demo.log("Status: HOSPITAL_NOTIFIED ✓")

        confirmation = await client.post(
            "/api/v1/sms/inbound",
            json={"from": hospital, "text": f"CONFIRM {dispatch_id}"},
        )
        confirmation.raise_for_status()
        assert confirmation.json()["status"] == "CONFIRMED"
        demo.log("Hospital: CONFIRM received ✓")

        arrival_response = await ussd(client, ibrahim, "3")
        assert "Arrival confirmed" in arrival_response, arrival_response
        await wait_for_actions(client, dispatch_id, "arrival_confirm", "cho_arrival_notify")
        completed = (await client.get(f"/api/v1/dispatch/{dispatch_id}")).json()["status"]
        assert completed == "COMPLETED"
        demo.log("Ibrahim: ARRIVAL confirmed via USSD ✓")
        demo.log("Status: COMPLETED ✓")

        # Decline path: Ibrahim declines; escalation reaches Musah then Abdul.
        _, decline_dispatch = await create_referral(
            client, critical_referral(DECLINE_PATH_HASH)
        )
        decline_id = decline_dispatch["id"]
        demo.log(
            f"Referral created: #REF-{decline_dispatch['referral_id']:03d} (decline path)"
        )
        decline_response = await ussd(client, ibrahim, "2")
        assert "declined" in decline_response.lower(), decline_response
        demo.log("Ibrahim: DECLINED via USSD")
        await wait_for_actions(client, decline_id, "ussd_decline")
        escalation_logs = await wait_for_sms_recipients(
            client, decline_id, musah, abdul
        )
        notified_phones = {
            log["target_phone"] for log in escalation_logs if log["action"] == "sms_send"
        }
        assert musah in notified_phones and abdul in notified_phones
        demo.log(f"Cascade: Musah ({musah}) alerted; escalated SMS → Abdul ({abdul})")

        accept_response = await ussd(client, abdul, "1")
        assert "Accepted" in accept_response, accept_response
        await wait_for_actions(client, decline_id, "momo_escrow", "hospital_notify")
        demo.log("Abdul: ACCEPTED via USSD; hospital notified")

        diversion = await client.post(
            "/api/v1/sms/inbound",
            json={"from": hospital, "text": f"DIVERT {decline_id} 2"},
        )
        diversion.raise_for_status()
        assert diversion.json()["status"] == "DIVERTED"
        demo.log("Hospital: DIVERT to Navrongo War Memorial Hospital ✓")

    demo.log("Demo complete ✓")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (AssertionError, RuntimeError, httpx.HTTPError, ModuleNotFoundError) as exc:
        print(f"Demo failed: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
