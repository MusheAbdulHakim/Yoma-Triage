from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import DispatchLog, Driver, Facility, Referral
from src.services.messaging_gateway import MessagingGateway
from src.tools.moews_calculator import missing_vitals


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
        token = referral.patient_hash[:12]
        vitals = referral.vitals_json or {}
        missing = missing_vitals(vitals) if vitals else []
        if vitals.get("vitals_not_taken"):
            not_measured = "Vitals: NOT TAKEN\n"
        else:
            not_measured = f"Not measured: {', '.join(missing)}\n" if missing else ""
        message = (
            "YOMA TRIAGE EMERGENCY REFERRAL\n"
            f"From compound #{referral.chps_compound_id}\n"
            f"Patient token: {token}\n"
            f"Condition: {referral.emergency_type}\n"
            f"Severity: {referral.risk_level}\n"
            f"{not_measured}"
            f"Driver: {driver.name}\n"
            f"Driver phone: {driver.phone}\n"
            f"Dispatch: #{dispatch_id}\n"
            f"Reply CONFIRM {dispatch_id} or DIVERT {dispatch_id} <facility_id>"
        )
        result = await self.gateway.send_sms(facility.phone, message, dispatch_id, "hospital")
        session.add(
            DispatchLog(
                dispatch_id=dispatch_id,
                action="hospital_notify" if result["status"] != "FAILED" else "hospital_notify_failed",
                target_phone=facility.phone,
                target_role="hospital",
                response=result["status"],
                metadata_json={
            **result,
            "message_preview": message.split("\n", 1)[0],
            "patient_token_prefix": token,
            "dispatch_id": dispatch_id,
        },
            )
        )
