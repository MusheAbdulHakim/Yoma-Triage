# Fixes: Batch 3

**Branch:** `fix/batch-3` (4 commits, rebased onto `origin/main` at `5fc80bf` after `fix/batch-2` merged; pushed to `origin` for a PR, not merged)
**Source:** `FIXES_BATCH_2.md`, batch 3 brief

**Rebase:** the commits were first made on `fix/batch-2` as `9462b81`, `bcb06fb`, `0dff263` and `f380e60`. The rebase left the tree identical (no conflicts), and the hashes below are the rebased ones. All checks were rerun after it, with the same results as the table below.

**Base:** the brief says to branch from `fix/safety-batch-2`, but B1–B4 were finished on `fix/batch-2`, and `fix/safety-batch-2` has none of them. Rebuilding them there, or merging, would have duplicated finished work on a branch whose A1–A4 differ from the batch 2 brief. So `fix/batch-3` comes from `fix/batch-2`, and `fix/safety-batch-2` is untouched. Step 0's results are in `FIXES_BATCH_2.md`.

All items are done. **Nothing has run on a physical device or in a release build, so the `tel:` and `sms:` buttons have never opened a real dialler, and nothing has reached the real Africa's Talking API** (see [Verification limits](#verification-limits)).

| Item | Commit | Fixes |
|---|---|---|
| 1. CHO registration and home compound | `aec0b7b` | BUG-15 |
| 2. Offline manual fallback | `49226b3` | BUG-17, Principle 9 |
| 3. Spec sync | `6f2e6f5` | Spec and code disagreeing |
| Deprecated status constant from item 1 | `be602e9` | Cleanup, not a brief item |

---

## Decisions for you to review

Items 1–4 matter most.

1. **Unverified identity is now what authorizes a referral.** With the API key, which is in every app, anyone who knows a CHO's phone number can look up their name and compound and send referrals as them. OTP closes this; you asked for it later. Until then, `cho_phone` stops mistakes rather than an attacker.
2. **Registered CHOs may not get the SMS.** CHO alerts still go to `chps_compounds.cho_phone`, not the `chos` table. So a second CHO at a compound, or one whose number differs from the compound's, can send referrals but gets no late-accept, arrival or failure SMS. `add_cho` doesn't update the compound. The brief didn't cover this, so I left it. **I'd decide this before the pilot:** text every active CHO at the compound, or only the one who sent the referral.
3. **Nothing can deactivate a CHO or change their compound except direct SQL.** The app also has no way to redo setup without clearing its data. So a CHO who moves compounds needs a database edit and an app reinstall. The brief asked only for adding.
4. **The batch 2 question about 401 and 403 has a new answer.** A rejected CHO is now a correct, permanent 403, so 403 should stay permanent. I'd now keep only 401 (a bad API key) retrying. That question, along with dismissing failed referrals and the sender delay, is still open from batch 2.
5. **Driver and facility numbers are stored unencrypted on the phone,** as you specified, on what may be a shared device. It adds to the Act 843 review, alongside the queued vitals.
6. **The CHO check runs after the idempotency check (decision).** A retry of a referral that was already accepted still gets its dispatch, even if the CHO has since been deactivated. Otherwise a retry could report failure for a driver who is already on the way.
7. **Referrals don't record which CHO sent them.** `cho_phone` is checked, not stored, because the brief didn't ask for a column. You'll probably want this for audit.
8. **The phone lookup is a POST (decision),** so numbers stay out of URLs and access logs.
9. **Added to avoid blocking a referral:** if a compound has no known location, the facility picker lists facilities by name rather than refusing. This case comes up as soon as a compound is registered that isn't in the bundled catalog.
10. **The SMS wording is mine and hasn't been reviewed:** "Yoma Triage: Emergency transport needed at {compound}. Please call back now." and "Yoma Triage: Emergency referral coming from {compound}. Please prepare and call back."
11. **Off-duty drivers stay in the saved list (decision),** because a CHO calling by hand may still reach them. Inactive drivers are left out.

### Breaking changes

- **`POST /api/v1/referral` now requires `cho_phone`,** and rejects an unknown, inactive or wrong-compound CHO with 403.
- **Every CHO must be registered before using the app.** First-run setup needs a data connection.
- **Run `alembic upgrade head`** for the new `chos` table. Local databases that use `create_all` also need it, or a rebuild.
- **`python -m src.db.seed` now also registers a demo CHO for each compound.**
- **`docs/yoma-triage-product-spec.md` is deleted.** References in `todo.md` and the plans now point to `PRODUCT_SPEC.md`.
- **New Flutter dependency:** `url_launcher`.

---

## What changed

### 1. CHO registration and home compound

- **Table:** `chos` (id, name, phone unique, compound_id, active, created_at). `src/db/models.py`, `migrations/versions/0004_chos.py`
- **CLI:** `python -m src.admin.add_cho --name … --phone … --compound-id …` works in every environment with only `DATABASE_URL`. The CHO and its audit row commit together, and the audit row holds an ID rather than the phone number. It refuses a bad phone, an unknown compound and a duplicate. `src/admin/add_cho.py`
- **Lookup:** `POST /api/v1/cho/lookup`, behind the API key. It returns 404 if not registered and 403 if inactive, each with a plain message. `src/api/cho.py`
- **App:** first-run setup with no compound picker, and the app stores the identity. The compound #1 defaults are gone, including the fallback to the first compound in the catalog. A phone that isn't set up can't send, and it tells the CHO to call directly. `mobile/lib/screens/setup_screen.dart`, `mobile/lib/services/cho_store.dart`, `mobile/lib/main.dart`, `mobile/lib/screens/referral_screen.dart`
- **Referrals:** every one carries `cho_phone`, including queued ones and skip vitals. `src/api/referral.py`, `mobile/lib/models/referral.dart`, `mobile/lib/services/offline_queue.dart`

### 2. Offline manual fallback

- **Cache:** drivers (name, phone, Motor-King or not) and facility phones, in SharedPreferences. It refreshes after setup, when Home opens, when the sync service starts, and when the connection returns. A failed or malformed refresh never replaces a good list. `mobile/lib/services/contacts_store.dart`, `src/api/driver.py` (`GET /api/v1/compound/{id}/contacts`)
- **Buttons:** Call and SMS for each saved driver and the chosen facility, plus when the list was last updated. The panel makes no network calls. If the phone app won't open, it shows the number to dial by hand, and the number is always visible. `mobile/lib/widgets/manual_contacts_panel.dart`
- **Where it appears:** queued referral, failed referral, and a dispatch that is FAILED or queued. `queued_referral_screen.dart`, `failed_referrals_screen.dart`, `dispatch_status_screen.dart`
- **Platform:** `tel` and `sms` declared in `AndroidManifest.xml` and `Info.plist`.

### 3. Spec sync

`PRODUCT_SPEC.md` is now version 2.1, with a status table and open decisions at the top.

- **Updated:** Incomplete result (§9.3), skip vitals (§7.1.3), YAMNet never GREEN (§7.1.1, including the §7.1.1 change left behind on `fix/safety-batch-2`), Part V wording, CHO registration (§7.8), offline fallback (§7.9), durable cascade and outbox (§10.8), RAG (§10.9), and the endpoint table.
- **Status notes:** 28 "Not built" lines. Text about unbuilt features was kept.
- **Open decisions:** pilot scope (paediatric or obstetric) and acoustic in the pilot.
- **Guard:** `tests/test_spec_sync.py` checks the synced claims, checks that every endpoint in the table exists, and fails if anything links to the deleted file.

---

## Test evidence

| Check | After batch 2 | After this batch |
|---|---|---|
| `pytest`, `REQUIRE_POSTGRES_TESTS=1` | 411 passed, 4 skipped | **462 passed, 4 skipped** |
| Postgres tests alone | 43 passed | **43 passed** (plus 1 test skipped on `librosa`) |
| Backend coverage | 79% | **79%** |
| `ruff check .` | 10 errors | **10 errors**, the same four files, none on lines I wrote |
| `mypy src main.py` | 21 errors in 4 files | **21 errors in 4 files**, the same count, none in files added by this batch |
| `flutter analyze` | no issues | **no issues** |
| `flutter test` | 137 passed | **174 passed** |
| `flutter test --dart-define=MOEWS_ONLY=false` | 136 passed, 1 skipped | **173 passed, 1 skipped** |
| `flutter build web` | fails | **still fails (BUG-19)** |
| `scripts/demo_flow.py` | passes | **passes**, 0 phone numbers in the server log |

**About the numbers:** the `pytest` line was rerun after the final commit; the others come from just before that one-line status constant change. The 79% understates `add_cho.py`, because its CLI tests run in a subprocess that coverage doesn't see. The RAG packages weren't installed for this batch, so the three RAG-only tests skipped and weren't run.

**A real production-mode journey,** from migrations, with the Africa's Talking URL pointed at a closed local port so nothing could reach a live service:

| Step | Result |
|---|---|
| `alembic upgrade head`, then `alembic check` | No drift |
| `add_cho` with `ENVIRONMENT=production` | Added, with an audit row holding no phone number |
| The same phone again | Refused, exit 1 |
| Lookup with `024 000 0700` | Compound 7, normalized phone |
| Lookup of an unknown phone | 404 |
| First referral | 201 in 0.051 s |
| Referral from an unregistered CHO | 403 |
| Contacts | Drivers and facility phones |
| Memory | 83 MB idle, 84 MB after the referral |
| Phone numbers in the server log | 0 |

### Revert check

I undid each fix in a scratch copy and ran its tests, after confirming those tests pass unmodified. **All 48 were caught: 25 backend, 23 Dart.** The Dart run rejects compile errors, so none of those count as catches.

| Item | Undone | Caught |
|---|---|---|
| 1 Backend | No audit row; phone in audit; CLI refuses outside development; duplicate allowed; unknown compound allowed; phone not normalized; lookup returns inactive; lookup takes a bad phone; referral takes unknown, inactive or wrong-compound CHO; `cho_phone` optional; CHO check before replay; lookup without API key; model drifts from migration | 15/15 |
| 1 Dart | Setup skipped; failed lookup stores identity; server reason hidden; compound 1 used; `cho_phone` not sent; lost in outbox; unset phone can send; no location blocks the list | 8/8 |
| 2 Backend | Inactive drivers cached; Motor-King flag missing; facility phones missing; unknown compound returns empty | 4/4 |
| 2 Dart | Offline refresh wipes list; bad reply replaces list; every facility shown; wrong Call scheme; `+` in SMS; patient in SMS; update time hidden; launch failure silent; panel missing from queued, failed or FAILED; no refresh after setup, on Home, on reconnect, or on service start | 15/15 |
| 3 | GREEN claim back; Part V wording back; "Not built" removed; open decision removed; endpoint that doesn't exist; link to the deleted copy | 6/6 |

**One gap found while checking my own work:** nothing tested that the contact refresh actually fired, although that was an explicit requirement. I added those tests before committing item 2.

---

## Verification limits

- **No device.** The `tel:` and `sms:` buttons are tested up to the URI handed to the launcher, not through a real dialler or messaging app. Check on a real Android phone and iPhone, including the prefilled SMS body, whose handling varies between phones.
- **The "offline" tests simulate no signal** with a failing client. No test turned off a real radio.
- **Still not confirmed:** YAMNet on a device (BUG-1).
- **No live Africa's Talking traffic.**

---

## Deferred

| Item | Why |
|---|---|
| **OTP** | You asked for it later. See decision 1. |
| **CHO deactivation, moves, re-setup** | Not in this brief. See decision 3. |
| **Which CHO gets SMS** | Needs a decision. See decision 2. |
| **SMS referral when offline** | Not in this brief. **Skip vitals still can't dispatch without data.** The Call and SMS buttons now cover this manually, which is a real improvement but not dispatch. |
| **Stale queued referrals (BUG-12)** | Not in this brief. A referral queued for hours still dispatches live, and now the CHO may also have called a driver by hand, which makes a double dispatch more likely. I'd do this next. |
| **Batch 2 open questions** | 401 and 403, failed referral dismissal and retention, and the sender delay are all unanswered. |
| **Diversion (BUG-5), driver trip state (BUG-9), audit writes beyond CHO registration, web build (BUG-19)** | Not in this brief. |
| **Stale docs** | `docs/plans/at-sandbox-runbook.md`, `TASK_BOARD.md` and `docs/architecture-narrative.md` still describe older behaviour. I only changed their references to the deleted file. |

**The pilot rating in `AUDIT_REPORT.md` stands.** The two field blockers from batch 2 are now partly addressed: phones have a real compound, and a CHO without data can reach people by hand. Clinical sign-off, OTP, ethics clearance and real-device testing are still open.
