from datetime import datetime

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from src.db.database import Base


class CHPSCompound(Base):
    __tablename__ = "chps_compounds"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    zone: Mapped[str] = mapped_column(String(120))
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    # Seed data only. Alerts go to the CHOs in the chos table, never to this number.
    cho_phone: Mapped[str] = mapped_column(String(32))
    drivers: Mapped[list["Driver"]] = relationship(back_populates="compound")


class Cho(Base):
    """A registered Community Health Officer: the identity OTP will verify later."""

    __tablename__ = "chos"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str] = mapped_column(String(32), unique=True)
    compound_id: Mapped[int] = mapped_column(ForeignKey("chps_compounds.id"))
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Driver(Base):
    __tablename__ = "drivers"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    phone: Mapped[str] = mapped_column(String(32), unique=True)
    vehicle_type: Mapped[str] = mapped_column(String(64))
    vehicle_desc: Mapped[str] = mapped_column(String(120), default="")
    chps_compound_id: Mapped[int] = mapped_column(ForeignKey("chps_compounds.id"))
    is_motor_king: Mapped[bool] = mapped_column(Boolean, default=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    availability: Mapped[str] = mapped_column(
        String(32), default="AVAILABLE"
    )  # AVAILABLE|ON_TRIP|OFF_DUTY
    compound: Mapped["CHPSCompound"] = relationship(back_populates="drivers")


class Facility(Base):
    __tablename__ = "facilities"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(160))
    type: Mapped[str] = mapped_column(String(64), default="district_hospital")
    phone: Mapped[str] = mapped_column(String(32))
    district: Mapped[str] = mapped_column(String(120))
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    has_maternity: Mapped[bool] = mapped_column(Boolean, default=True)
    has_icu: Mapped[bool] = mapped_column(Boolean, default=False)


class Referral(Base):
    __tablename__ = "referrals"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    chps_compound_id: Mapped[int] = mapped_column(ForeignKey("chps_compounds.id"))
    facility_id: Mapped[int] = mapped_column(ForeignKey("facilities.id"))
    # Who sent this. Null only for referrals older than this column.
    cho_id: Mapped[int | None] = mapped_column(ForeignKey("chos.id"), nullable=True)
    patient_hash: Mapped[str] = mapped_column(String(64))
    patient_name: Mapped[str] = mapped_column(String(120), default="Unknown")
    patient_age: Mapped[int | None] = mapped_column(Integer, nullable=True)
    patient_gender: Mapped[str | None] = mapped_column(String(16), nullable=True)
    emergency_type: Mapped[str] = mapped_column(String(64))
    severity: Mapped[str] = mapped_column(String(32), default="UNKNOWN")
    moews_score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    risk_level: Mapped[str] = mapped_column(String(32), default="UNKNOWN")
    clinical_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    compressed_sms_payload: Mapped[str | None] = mapped_column(String(256), nullable=True)
    # CONFIRMED|AWAITING_CONFIRMATION|MANUALLY_HANDLED|CANCELLED
    status: Mapped[str] = mapped_column(String(32), default="CREATED")
    vitals_json: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    client_request_id: Mapped[str | None] = mapped_column(String(36), unique=True, nullable=True)
    # How long this waited on the phone before reaching us, by the phone's own clock.
    queue_age_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ai_screen_result: Mapped[str | None] = mapped_column(String(32), nullable=True)
    ai_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    ai_model_version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    initiated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Dispatch(Base):
    __tablename__ = "dispatches"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    referral_id: Mapped[int] = mapped_column(ForeignKey("referrals.id"), unique=True)
    driver_id: Mapped[int | None] = mapped_column(ForeignKey("drivers.id"), nullable=True)
    facility_id: Mapped[int] = mapped_column(ForeignKey("facilities.id"))
    status: Mapped[str] = mapped_column(String(32), default="PENDING")
    # PENDING|TIER1_NOTIFIED|TIER2_NOTIFIED|ACCEPTED|HOSPITAL_NOTIFIED|COMPLETED|DIVERTED|FAILED
    # |CANCELLED
    current_tier: Mapped[int] = mapped_column(Integer, default=0)
    declined_driver_ids: Mapped[list] = mapped_column(JSON, default=list)
    # What the worker must do next, and when. Null means nothing is scheduled.
    next_action: Mapped[str | None] = mapped_column(String(32), nullable=True)
    next_action_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    initiated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    driver_assigned_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class DispatchLog(Base):
    __tablename__ = "dispatch_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    dispatch_id: Mapped[int] = mapped_column(ForeignKey("dispatches.id"))
    action: Mapped[str] = mapped_column(String(64))
    target_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    target_role: Mapped[str | None] = mapped_column(String(32), nullable=True)
    response: Mapped[str | None] = mapped_column(String(64), nullable=True)
    metadata_json: Mapped[dict | None] = mapped_column("metadata", JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class OutboundMessage(Base):
    """Transactional SMS outbox: see src/services/outbox.py."""

    __tablename__ = "outbound_messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    recipient: Mapped[str] = mapped_column(String(32))
    body: Mapped[str] = mapped_column(Text)
    purpose: Mapped[str] = mapped_column(String(32))
    dispatch_id: Mapped[int | None] = mapped_column(ForeignKey("dispatches.id"), nullable=True)
    status: Mapped[str] = mapped_column(String(16), default="PENDING")
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )
    provider_response: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Wallet(Base):
    __tablename__ = "wallets"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    referral_id: Mapped[int] = mapped_column(ForeignKey("referrals.id"))
    dispatch_id: Mapped[int] = mapped_column(ForeignKey("dispatches.id"))
    amount: Mapped[float] = mapped_column(Float)
    currency: Mapped[str] = mapped_column(String(8), default="GHS")
    source: Mapped[str] = mapped_column(String(64), default="community_fund_mock")
    status: Mapped[str] = mapped_column(String(32), default="INITIAL_DISBURSED")
    transaction_id: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    entity_type: Mapped[str] = mapped_column(String(64))
    entity_id: Mapped[str] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(64))
    actor_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    metadata_json: Mapped[dict | None] = mapped_column("metadata", JSON, nullable=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
