# Task 7 Report — USSD callback

- Added `process_ussd` for testable, immediate USSD responses.
- Driver lookup is by phone; dispatch lookup includes claimable items plus the driver's accepted dispatch.
- Accept side effects are queued with `BackgroundTasks` only after committing the claim.
- Repeat accept returns the identical `END Accepted!` response and does not queue a second task.
- Added `tests/test_ussd_idempotency.py`.
- Verified: `./venv/bin/python -m pytest -v` — 14 passed.
- Commit: `7f2708f feat: fast idempotent USSD accept/decline with background side effects`

## Task 7 review fix

- Declines now record the locked dispatch state and commit before queuing escalation through `BackgroundTasks`.
- `run_decline_side_effects(dispatch_id, driver_id)` performs tier notification SMS in a separate database session after the USSD response.
- The regression tests assert that a decline schedules its background work and does not await `gateway.send_sms` in the request path.
- Test output: `./venv/bin/python -m pytest tests/test_ussd_idempotency.py tests/test_dispatch.py -v` — 7 passed.
