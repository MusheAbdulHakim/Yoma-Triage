"""Close stale referrals the CHO never answered (B4).

A referral that waited too long on the phone is stored as AWAITING_CONFIRMATION and not
dispatched until the CHO answers "Still needs transport?". If the answer never comes, for
example because the phone's record was deleted, it would stay open forever and skew
reports. After EXPIRE_UNCONFIRMED_HOURS on the server it becomes EXPIRED_UNCONFIRMED, with
an audit row. The cascade worker runs this on each poll.
"""
from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from src.config import settings
from src.db.database import async_session
from src.db.models import AuditLog, Referral

AWAITING_CONFIRMATION = "AWAITING_CONFIRMATION"
EXPIRED_UNCONFIRMED = "EXPIRED_UNCONFIRMED"


async def expire_unconfirmed_referrals(
    *, now: datetime | None = None, limit: int = 100, sessions=None
) -> int:
    """Expire every overdue unanswered referral, in one transaction. Returns how many.

    Rows are locked with SKIP LOCKED, so one the CHO is answering right now is left for
    the next poll, and the answer and the expiry can't both win.
    """
    cutoff = (now or datetime.now(UTC)) - timedelta(hours=settings.EXPIRE_UNCONFIRMED_HOURS)
    async with (sessions or async_session)() as session:
        overdue = list(
            await session.scalars(
                select(Referral)
                .where(
                    Referral.status == AWAITING_CONFIRMATION,
                    Referral.initiated_at <= cutoff,
                )
                .order_by(Referral.id)
                .limit(limit)
                .with_for_update(skip_locked=True)
            )
        )
        for referral in overdue:
            referral.status = EXPIRED_UNCONFIRMED
            session.add(
                AuditLog(
                    entity_type="referral",
                    entity_id=str(referral.id),
                    action="referral_expired_unconfirmed",
                    actor_id="worker",
                    metadata_json={
                        "queue_age_seconds": referral.queue_age_seconds,
                        "expire_after_hours": settings.EXPIRE_UNCONFIRMED_HOURS,
                    },
                )
            )
        await session.commit()
    return len(overdue)
