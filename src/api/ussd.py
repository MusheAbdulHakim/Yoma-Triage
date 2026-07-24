"""
USSD Webhook Receiver for Ghana Telecom Gateways (Arkesel / Hubtel).
"""
from fastapi import APIRouter, BackgroundTasks, Depends, Form, Response
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.db.database import get_db
from src.db.models import Dispatch, Driver, Referral
from src.services.dispatch_orchestrator import CLAIMABLE, DispatchOrchestrator

router = APIRouter(prefix="/ussd", tags=["USSD Gateway"])


@router.post("/callback")
async def handle_ussd(
    session_id: str = Form(...),
    service_code: str = Form(...),
    phone_number: str = Form(...),
    text: str = Form(""),
    background_tasks: BackgroundTasks = None,
    session: AsyncSession = Depends(get_db),
):
    """
    Processes USSD inputs from drivers responding to emergency referrals.
    Format required by Ghanaian Telco gateways: 'CON' (continue) or 'END' (terminate).
    """
    user_input = text.strip()

    if user_input == "":
        response_text = "CON RelayAI Emergency Referral\n1. Accept Transfer (CHPS-104)\n2. Reject"
        return Response(content=response_text, media_type="text/plain")

    if user_input not in {"1", "2"}:
        return Response(content="END Invalid option selected.", media_type="text/plain")

    driver = await session.scalar(select(Driver).where(Driver.phone == phone_number))
    if not driver:
        return Response(content="END No active dispatch.", media_type="text/plain")

    dispatch = await session.scalar(
        select(Dispatch)
        .join(Referral, Dispatch.referral_id == Referral.id)
        .where(
            Referral.chps_compound_id == driver.chps_compound_id,
            Dispatch.status.in_(CLAIMABLE),
        )
        .order_by(Dispatch.initiated_at.desc())
    )
    if not dispatch:
        return Response(content="END No active dispatch.", media_type="text/plain")

    orchestrator = DispatchOrchestrator()
    if user_input == "1":
        result = await orchestrator.handle_accept(session, dispatch.id, driver.id)
        await session.commit()
        if result["run_side_effects"]:
            background_tasks.add_task(
                orchestrator.run_accept_side_effects, dispatch.id, driver.id
            )
        return Response(content=result["ussd"], media_type="text/plain")

    result = await orchestrator.handle_decline(session, dispatch.id, driver.id)
    await session.commit()
    return Response(content=result["ussd"], media_type="text/plain")
