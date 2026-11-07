"""The whole journey on real Postgres, through the real endpoints (batch 6 item 5).

refer → offer → decline → second driver accepts → hospital CONFIRM → DIVERT → arrival at
the new facility → COMPLETED. After every step the outbox is sent, and the test checks
the dispatch status, both drivers' availability, every new outbox message, every new
dispatch log line and every new audit log row. Anything missing or extra fails.
"""
from __future__ import annotations

import uuid
from collections import Counter

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from src.db.models import AuditLog, Dispatch, DispatchLog, Driver, Facility, OutboundMessage, Wallet
from src.services.outbox import OutboxSender
from tests.postgres_support import (
    CHO_PHONE,
    DRIVER_PHONES,
    pg_sessions,  # noqa: F401 - pytest fixture
    postgres_url,  # noqa: F401 - pytest fixture
)
from tests.test_outbox_pg import FakeGateway
from tests.ussd_paths import CONFIRM_ARRIVAL, accept, decline

pytestmark = pytest.mark.postgres

DRIVER_1, DRIVER_2 = DRIVER_PHONES[1], DRIVER_PHONES[2]
HOSPITAL_1, HOSPITAL_2 = "+233240000200", "+233240000201"


class Journey:
    """Remembers what it has already checked, so each step sees only what it caused."""

    def __init__(self, sessions, client: AsyncClient):
        self.sessions = sessions
        self.client = client
        self.gateway = FakeGateway()
        self.seen = {"outbox": 0, "logs": 0, "audit": 0}
        self.dispatch_id: int | None = None

    async def _new(self, model, key: str, order):
        async with self.sessions() as session:
            rows = list(await session.scalars(select(model).order_by(order)))
        fresh, self.seen[key] = rows[self.seen[key] :], len(rows)
        return fresh

    async def step(
        self,
        *,
        status: str,
        availability: tuple[str, str],
        outbox: list[tuple[str, str]],
        logs: list[tuple[str, str | None, str | None]],
        audit: list[tuple[str, str, str, str]] = (),
    ) -> list[OutboundMessage]:
        """Send what was queued, then check everything the step changed."""
        while await OutboxSender(self.gateway).run_once():
            pass
        async with self.sessions() as session:
            dispatch = await session.get(Dispatch, self.dispatch_id)
            drivers = [await session.get(Driver, i) for i in (1, 2)]
        assert dispatch.status == status
        assert (drivers[0].availability, drivers[1].availability) == availability

        messages = await self._new(OutboundMessage, "outbox", OutboundMessage.id)
        assert Counter((m.recipient, m.purpose) for m in messages) == Counter(outbox)
        assert {m.status for m in messages} <= {"SENT"}

        new_logs = await self._new(DispatchLog, "logs", DispatchLog.id)
        assert Counter((g.action, g.target_role, g.response) for g in new_logs) == Counter(logs)
        assert {g.dispatch_id for g in new_logs} <= {self.dispatch_id}

        rows = await self._new(AuditLog, "audit", AuditLog.id)
        assert [
            (r.entity_id, r.actor_id, r.metadata_json["from"], r.metadata_json["to"])
            for r in rows
        ] == list(audit)
        assert all(
            (r.entity_type, r.action, r.metadata_json["dispatch_id"])
            == ("driver", "driver_availability", self.dispatch_id)
            for r in rows
        )
        return messages

    async def ussd(self, phone: str, text: str) -> str:
        response = await self.client.post(
            "/ussd/callback",
            data={
                "sessionId": str(uuid.uuid4()),
                "serviceCode": "*1#",
                "phoneNumber": phone,
                "text": text,
            },
        )
        assert response.status_code == 200
        return response.text

    async def hospital(self, phone: str, text: str) -> dict:
        response = await self.client.post(
            "/api/v1/sms/inbound", json={"from": phone, "text": text}
        )
        assert response.status_code == 200
        return response.json()

    async def code(self) -> str:
        async with self.sessions() as session:
            return (await session.get(Dispatch, self.dispatch_id)).hospital_code


def _sent(status: str, *pairs: tuple[str, str]) -> list[tuple[str, str, str]]:
    """Dispatch log lines the sender writes, one per message: (action, role, SENT)."""
    return [(action, role, status) for action, role in pairs]


@pytest.mark.asyncio
async def test_refer_to_completed_through_a_diversion(pg_sessions, monkeypatch):  # noqa: F811
    from main import app

    monkeypatch.setattr("src.api.ussd.settings.AT_USSD_SERVICE_CODE", "")
    async with pg_sessions() as session:
        session.add(
            Facility(
                id=2, name="Navrongo War Memorial Hospital", phone=HOSPITAL_2, district="D"
            )
        )
        await session.commit()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        journey = Journey(pg_sessions, client)

        # Refer: both Motor-King drivers are offered it.
        response = await client.post(
            "/api/v1/referral",
            json={
                "chps_compound_id": 1,
                "facility_id": 1,
                "patient_hash": "0123456789abcdef" * 4,
                "cho_phone": CHO_PHONE,
                "emergency_type": "pph",
                "client_request_id": str(uuid.uuid4()),
                "vitals_taken": False,
            },
        )
        assert response.status_code == 201, response.text
        journey.dispatch_id = response.json()["dispatch"]["id"]
        ref = response.json()["referral"]["id"]
        await journey.step(
            status="TIER1_NOTIFIED",
            availability=("AVAILABLE", "AVAILABLE"),
            outbox=[(DRIVER_1, "driver_offer"), (DRIVER_2, "driver_offer")],
            logs=_sent("SENT", ("sms_send", "driver"), ("sms_send", "driver")),
        )

        # Driver 1 declines; driver 2 is still to answer, so the cascade waits.
        assert await journey.ussd(DRIVER_1, decline(ref)) == "END Referral declined."
        await journey.step(
            status="TIER1_NOTIFIED",
            availability=("AVAILABLE", "AVAILABLE"),
            outbox=[],
            logs=[
                ("ussd_decline", "driver", "DECLINED"),
                ("decline_tier_remaining", "system", "WAIT"),
            ],
        )

        # Driver 2 accepts: on a trip, the hospital and the CHO are told.
        assert "Accepted" in await journey.ussd(DRIVER_2, accept(ref))
        await journey.step(
            status="HOSPITAL_NOTIFIED",
            availability=("AVAILABLE", "ON_TRIP"),
            outbox=[(HOSPITAL_1, "hospital_pre_arrival"), (CHO_PHONE, "cho_driver_accepted")],
            logs=[
                ("ussd_accept", "driver", "ACCEPTED"),
                ("momo_escrow", "driver", "MOCK_RECORDED"),
                *_sent("SENT", ("hospital_notify", "hospital"), ("cho_accept_notify", "cho")),
            ],
            audit=[("2", "dispatch", "AVAILABLE", "ON_TRIP")],
        )
        first_code = await journey.code()

        # The hospital confirms, quoting its code.
        result = await journey.hospital(HOSPITAL_1, f"CONFIRM {first_code}")
        assert result["status"] == "CONFIRMED"
        await journey.step(
            status="HOSPITAL_CONFIRMED",
            availability=("AVAILABLE", "ON_TRIP"),
            outbox=[(HOSPITAL_1, "inbound_confirm_ack")],
            logs=[
                ("hospital_confirm", "hospital", "CONFIRMED"),
                *_sent("SENT", ("inbound_confirm_ack", "inbound_reply")),
            ],
        )

        # A driver can't divert, even with the code.
        result = await journey.hospital(DRIVER_2, f"DIVERT {first_code} 2")
        assert result["status"] == "NOT_YOUR_DISPATCH"
        await journey.step(
            status="HOSPITAL_CONFIRMED",
            availability=("AVAILABLE", "ON_TRIP"),
            outbox=[(DRIVER_2, "inbound_reply")],
            logs=[
                ("hospital_command_rejected", "driver", "NOT_YOUR_DISPATCH"),
                *_sent("SENT", ("inbound_status_reply", "inbound_reply")),
            ],
        )

        # The hospital diverts to facility 2. The trip goes on.
        result = await journey.hospital(HOSPITAL_1, f"DIVERT {first_code} 2")
        assert result == {"status": "DIVERTED", "dispatch_id": journey.dispatch_id, "facility_id": 2}
        messages = await journey.step(
            status="HOSPITAL_NOTIFIED",
            availability=("AVAILABLE", "ON_TRIP"),
            outbox=[
                (HOSPITAL_2, "hospital_pre_arrival"),
                (HOSPITAL_1, "divert_old_hospital"),
                (DRIVER_2, "divert_driver"),
                (CHO_PHONE, "divert_cho"),
            ],
            logs=[
                ("hospital_divert", "hospital", "DIVERTED"),
                *_sent(
                    "SENT",
                    ("hospital_notify", "hospital"),
                    ("divert_notify", "hospital"),
                    ("divert_notify", "driver"),
                    ("divert_notify", "cho"),
                ),
            ],
        )
        second_code = await journey.code()
        assert second_code != first_code
        notice = next(m.body for m in messages if m.purpose == "hospital_pre_arrival")
        assert f"Code: {second_code}" in notice
        assert "DIVERTED here from Hospital" in notice
        assert (await client.get(f"/api/v1/dispatch/{journey.dispatch_id}")).json()[
            "facility_name"
        ] == "Navrongo War Memorial Hospital"

        # The new facility confirms with its own code.
        result = await journey.hospital(HOSPITAL_2, f"CONFIRM {second_code}")
        assert result["status"] == "CONFIRMED"
        await journey.step(
            status="HOSPITAL_CONFIRMED",
            availability=("AVAILABLE", "ON_TRIP"),
            outbox=[(HOSPITAL_2, "inbound_confirm_ack")],
            logs=[
                ("hospital_confirm", "hospital", "CONFIRMED"),
                *_sent("SENT", ("inbound_confirm_ack", "inbound_reply")),
            ],
        )

        # Arrival at the new facility completes it, and frees driver 2.
        assert await journey.ussd(DRIVER_2, CONFIRM_ARRIVAL) == (
            "END Arrival confirmed. Referral complete."
        )
        await journey.step(
            status="COMPLETED",
            availability=("AVAILABLE", "AVAILABLE"),
            outbox=[(CHO_PHONE, "cho_arrival"), (HOSPITAL_2, "hospital_arrival")],
            logs=[
                ("arrival_confirm", "driver", "COMPLETED"),
                *_sent(
                    "SENT",
                    ("cho_arrival_notify", "cho"),
                    ("hospital_arrival_notify", "hospital"),
                ),
            ],
            audit=[("2", "dispatch", "ON_TRIP", "AVAILABLE")],
        )

    async with pg_sessions() as session:
        dispatch = await session.get(Dispatch, journey.dispatch_id)
        wallets = list(await session.scalars(select(Wallet)))
    assert dispatch.facility_id == 2
    assert dispatch.completed_at is not None
    assert [(w.dispatch_id, w.status) for w in wallets] == [
        (journey.dispatch_id, "INITIAL_DISBURSED")
    ]
    # Every message went out exactly once.
    assert len(journey.gateway.sent) == journey.seen["outbox"] == 13
