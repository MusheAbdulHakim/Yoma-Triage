def test_models_register_tables():
    from src.db.models import Base
    names = set(Base.metadata.tables.keys())
    for required in {
        "chps_compounds", "drivers", "facilities", "referrals",
        "dispatches", "dispatch_logs", "wallets", "audit_logs",
    }:
        assert required in names
