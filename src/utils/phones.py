"""Phone number helpers for Ghana MSISDN matching."""
from __future__ import annotations

import re

_GHANA_E164 = re.compile(r"^\+233\d{9}$")


def is_valid_ghana_phone(normalized: str) -> bool:
    """True for a number already normalized to +233 followed by nine digits."""
    return bool(_GHANA_E164.match(normalized))


def normalize_ghana_phone(phone: str) -> str:
    """Normalize local Ghana numbers to E.164 (+233…)."""
    normalized = "".join(str(phone).split())
    if normalized.startswith("+233"):
        return normalized
    if normalized.startswith("233"):
        return f"+{normalized}"
    if normalized.startswith("0"):
        return f"+233{normalized[1:]}"
    if normalized.startswith("+"):
        return normalized
    return f"+233{normalized}"
