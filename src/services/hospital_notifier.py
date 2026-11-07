from sqlalchemy.ext.asyncio import AsyncSession

from src.db.models import Driver, Facility, Referral
from src.services.outbox import enqueue_sms
from src.tools.moews_calculator import missing_vitals


class HospitalNotifier:
    def notify_pre_arrival(
        self,
        session: AsyncSession,
        referral: Referral,
        driver: Driver,
        facility: Facility,
        dispatch_id: int,
        *,
        diverted_from: str | None = None,
    ) -> None:
        """Queue the pre-arrival SMS in the caller's transaction."""
        token = referral.patient_hash[:12]
        vitals = referral.vitals_json or {}
        missing = missing_vitals(vitals) if vitals else []
        if vitals.get("vitals_taken") is False:
            not_measured = "Vitals not taken\n"
        else:
            not_measured = f"Not measured: {', '.join(missing)}\n" if missing else ""
        diverted = f"DIVERTED here from {diverted_from}\n" if diverted_from else ""
        message = (
            "YOMA TRIAGE EMERGENCY REFERRAL\n"
            f"{diverted}"
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
        enqueue_sms(
            session,
            recipient=facility.phone,
            body=message,
            purpose="hospital_pre_arrival",
            dispatch_id=dispatch_id,
        )
