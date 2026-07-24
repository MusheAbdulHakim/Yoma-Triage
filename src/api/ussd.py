"""
USSD Webhook Receiver for Ghana Telecom Gateways (Arkesel / Hubtel).
"""
from fastapi import APIRouter, BackgroundTasks, Depends, Form, Response
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.database import get_db
from src.db.models import Dispatch, Driver, Referral
from src.services.dispatch_orchestrator import CLAIMABLE, DispatchOrchestrator

router = APIRouter(prefix="/ussd", tags=["USSD Gateway"])


async def process_ussd(
    session: AsyncSession,
    background_tasks: BackgroundTasks,
    phone_number: str,
    text: str,
) -> Response:
    """Process a USSD response without waiting for external side effects."""
    user_input = text.strip()

    if user_input == "":
        return Response(
            content="CON RelayAI Emergency Referral\n1. Accept\n2. Decline",
            media_type="text/plain",
        )

    if not (user_input == "1" or user_input.endswith("1")) and not (
        user_input == "2" or user_input.endswith("2")
    ):
        return Response(content="END Invalid option selected.", media_type="text/plain")

    driver = await session.scalar(select(Driver).where(Driver.phone == phone_number))
    if not driver:
        return Response(content="END Unknown driver.", media_type="text/plain")

    dispatch = await session.scalar(
        select(Dispatch)
        .join(Referral, Dispatch.referral_id == Referral.id)
        .where(
            Referral.chps_compound_id == driver.chps_compound_id,
            or_(
                Dispatch.status.in_(CLAIMABLE),
                (Dispatch.status == "ACCEPTED") & (Dispatch.driver_id == driver.id),
            ),
        )
        .order_by(Dispatch.initiated_at.desc())
    )
    if not dispatch:
        return Response(content="END No active dispatch.", media_type="text/plain")

    orchestrator = DispatchOrchestrator()
    if user_input == "1" or user_input.endswith("1"):
        result = await orchestrator.handle_accept(session, dispatch.id, driver.id)
        await session.commit()
        if result["run_side_effects"]:
            background_tasks.add_task(
                orchestrator.run_accept_side_effects, dispatch.id, driver.id
            )
        return Response(content=result["ussd"], media_type="text/plain")

    result = await orchestrator.handle_decline(session, dispatch.id, driver.id)
    await session.commit()
    if result["run_side_effects"]:
        background_tasks.add_task(
            orchestrator.run_decline_side_effects, dispatch.id, driver.id
        )
    return Response(content=result["ussd"], media_type="text/plain")


@router.post("/callback")
async def handle_ussd(
    background_tasks: BackgroundTasks,
    session_id: str = Form(...),
    service_code: str = Form(...),
    phone_number: str = Form(...),
    text: str = Form(""),
    session: AsyncSession = Depends(get_db),
):
    """Return the gateway response immediately after the database transaction."""
    return await process_ussd(session, background_tasks, phone_number, text)
