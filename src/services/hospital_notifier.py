from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import DispatchLog, Driver, Facility, Referral
from src.services.messaging_gateway import MessagingGateway


class HospitalNotifier:
    def __init__(self, gateway: MessagingGateway):
        self.gateway = gateway

    async def notify_pre_arrival(
        self,
        session: AsyncSession,
        referral: Referral,
        driver: Driver,
        facility: Facility,
        dispatch_id: int,
    ) -> None:
        message = (
            "RELAYAI EMERGENCY REFERRAL\n"
            f"From compound #{referral.chps_compound_id}\n"
            f"Patient: {referral.patient_name}\n"
            f"Condition: {referral.emergency_type}\n"
            f"Severity: {referral.risk_level}\n"
            f"Driver: {driver.name}\n"
            f"Ref: #{referral.id}"
        )
        result = await self.gateway.send_sms(facility.phone, message, dispatch_id, "hospital")
        session.add(
            DispatchLog(
                dispatch_id=dispatch_id,
                action="hospital_notify" if result["status"] != "FAILED" else "hospital_notify_failed",
                target_phone=facility.phone,
                target_role="hospital",
                response=result["status"],
                metadata_json=result,
            )
        )
