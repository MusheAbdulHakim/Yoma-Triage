"""Errors the API defines. The app trusts a refusal only if it carries one of these codes.

Without a code, a 4xx could have come from a captive portal or a proxy rather than from
this server, so the app has to keep the referral and retry it.
mobile/lib/services/api_client.dart lists the same codes; tests/test_api_errors.py fails
if the two differ.
"""
from __future__ import annotations

from fastapi import FastAPI, HTTPException, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

COMPOUND_NOT_FOUND = "COMPOUND_NOT_FOUND"
FACILITY_NOT_FOUND = "FACILITY_NOT_FOUND"
REFERRAL_NOT_FOUND = "REFERRAL_NOT_FOUND"
DISPATCH_NOT_FOUND = "DISPATCH_NOT_FOUND"
CHO_NOT_REGISTERED = "CHO_NOT_REGISTERED"
CHO_NOT_ACTIVE = "CHO_NOT_ACTIVE"
CHO_WRONG_COMPOUND = "CHO_WRONG_COMPOUND"
INVALID_PHONE = "INVALID_PHONE"
VALIDATION_ERROR = "VALIDATION_ERROR"
REFERRAL_ALREADY_RESOLVED = "REFERRAL_ALREADY_RESOLVED"
DISPATCH_NOT_CANCELLABLE = "DISPATCH_NOT_CANCELLABLE"
REFERRAL_EXPIRED = "REFERRAL_EXPIRED"

ALL_CODES = frozenset(
    {
        COMPOUND_NOT_FOUND,
        FACILITY_NOT_FOUND,
        REFERRAL_NOT_FOUND,
        DISPATCH_NOT_FOUND,
        CHO_NOT_REGISTERED,
        CHO_NOT_ACTIVE,
        CHO_WRONG_COMPOUND,
        INVALID_PHONE,
        VALIDATION_ERROR,
        REFERRAL_ALREADY_RESOLVED,
        DISPATCH_NOT_CANCELLABLE,
        REFERRAL_EXPIRED,
    }
)


class ApiError(HTTPException):
    def __init__(self, status_code: int, code: str, detail: str) -> None:
        if code not in ALL_CODES:
            raise ValueError(f"Unknown API error code: {code}")
        super().__init__(status_code=status_code, detail=detail)
        self.code = code


async def _api_error(_: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, ApiError)
    return JSONResponse(
        status_code=exc.status_code, content={"detail": exc.detail, "code": exc.code}
    )


async def _validation_error(_: Request, exc: Exception) -> JSONResponse:
    assert isinstance(exc, RequestValidationError)
    return JSONResponse(
        status_code=422,
        content={"detail": jsonable_encoder(exc.errors()), "code": VALIDATION_ERROR},
    )


def install_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ApiError, _api_error)
    app.add_exception_handler(RequestValidationError, _validation_error)
