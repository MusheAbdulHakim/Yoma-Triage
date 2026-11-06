"""Every clinical and operational constant on the server, in one place.

mobile/lib/parameters.dart is the app's counterpart. tests/test_parameters.py fails if
the values both sides share ever differ. docs/PARAMETERS_SIGNOFF.md lists each value for
clinical review. All of these are unapproved placeholders until that sheet is signed.
"""
from __future__ import annotations

from typing import Any

# Entry limits: these catch typos and impossible readings. They do not judge risk.
VITAL_RANGES = {
    "systolic_bp": (0, 300),
    "diastolic_bp": (0, 200),
    "heart_rate": (0, 300),
    "respiratory_rate": (0, 120),
    "temperature": (20, 45),
    "spo2": (0, 100),
}
GESTATIONAL_WEEKS_MAX = 45

# MOEWS bands (spec 9.3). Below red_below or above red_above scores 3. Inside a yellow
# range scores 1. Anything else scores 0. A boundary value takes the higher score.
MOEWS_BANDS: dict[str, dict[str, Any]] = {
    "systolic_bp": {
        "red_below": 80, "yellow_low": (80, 90), "yellow_high": (140, 150), "red_above": 150,
    },
    "diastolic_bp": {
        "red_below": 60, "yellow_low": None, "yellow_high": (90, 100), "red_above": 100,
    },
    "heart_rate": {
        "red_below": 50, "yellow_low": (50, 60), "yellow_high": (110, 130), "red_above": 130,
    },
    "respiratory_rate": {
        "red_below": 10, "yellow_low": (10, 14), "yellow_high": (24, 30), "red_above": 30,
    },
    "temperature": {
        "red_below": 35, "yellow_low": (35, 36), "yellow_high": (38, 39), "red_above": 39,
    },
    "spo2": {
        "red_below": 90, "yellow_low": (90, 94), "yellow_high": None, "red_above": None,
    },
}
MOEWS_RED_PARAMETER_SCORE = 3
MOEWS_RED_TOTAL = 5
MOEWS_YELLOW_TOTAL = 3

# Dispatch timing. CASCADE_TIER_SECONDS and LATE_CLAIM_WINDOW_MINUTES can be overridden
# by environment variables of the same name.
CASCADE_TIER_SECONDS = 90
MIN_FIELD_CASCADE_TIER_SECONDS = 60
LATE_CLAIM_WINDOW_MINUTES = 45
PLACEHOLDER_ETA_MINUTES = 30
# A referral that waited longer than this on the phone isn't dispatched until the CHO says
# it's still needed. STALE_AFTER_MINUTES can be overridden by an environment variable.
STALE_AFTER_MINUTES = 20
# How often the worker looks for overdue cascade steps. WORKER_POLL_SECONDS overrides it.
WORKER_POLL_SECONDS = 5

# SMS outbox. OUTBOX_POLL_SECONDS can be overridden by an environment variable of the
# same name. Retries wait the backoff, doubling each time, up to the attempt limit.
OUTBOX_POLL_SECONDS = 2
OUTBOX_MAX_ATTEMPTS = 5
OUTBOX_BACKOFF_SECONDS = 15
OUTBOX_SENDING_LEASE_SECONDS = 60
OUTBOX_BATCH_SIZE = 20
# Sent in parallel, so one hung send can't hold up the rest. OUTBOX_SEND_CONCURRENCY and
# OUTBOX_SEND_TIMEOUT_SECONDS can be overridden by environment variables of the same name.
OUTBOX_SEND_CONCURRENCY = 5
OUTBOX_SEND_TIMEOUT_SECONDS = 5

# Records on the phone: unsent or refused referrals are deleted after this long, once the
# CHO has been warned. The app does the deleting; this keeps both sides' sheets in step.
LOCAL_RECORD_TTL_HOURS = 72

# Payments: mock ledger only. No money moves.
FUEL_STIPEND_GHS = 22.5
