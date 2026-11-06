# Fixes: Batch 2

**Branch:** `fix/batch-2` (11 commits; not merged, not pushed)
**Source:** `AUDIT_REPORT.md`, `FIXES_BATCH_1.md`

**Base:** the brief says to branch from `main` after `fix/safety-batch-1` is merged, but it isn't merged yet. I branched from the tip of `fix/safety-batch-1` (`f5fb33c`) rather than merge it myself. That is the same code `main` will have after a merge, so `git rebase main` should be clean or unnecessary.

All items are done. **Nothing has run on a physical device or in a release build, and nothing has reached the real Africa's Talking API** (see [Verification limits](#verification-limits)).

| Item | Commit | Fixes |
|---|---|---|
| A1. Partial vitals never hide a critical reading | `4f5b214` | Decision 1 from batch 1 |
| A2. Emergency: skip vitals | `4093e76` | Decision 3 from batch 1 |
| A3. Late-claim window 45 minutes, configurable | `1c413fd` | Decision 6 from batch 1 |
| A4. Parameters modules and sign-off sheet | `cb4a630` | Placeholder values |
| A5. Permanent errors shown as FAILED | `322f42b` | BUG-14 |
| A6. Seed guard, DATABASE_URL required | `4adb3e8` | Batch 1 deferred items |
| B1. Alembic | `55cb5b7` | No migrations |
| B2. Durable cascade timing | `726104a` | BUG-6 |
| B3. Transactional SMS outbox | `1778869` | BUG-8 (locks and SMS), PII in logs |
| B4. RAG and LLM out of the request path | `5917cfa` | BUG-8 (blocking), memory |
| Lint and type errors from this batch | `aec1903` | Cleanup, not a brief item |

## Measured against the audit

Real `uvicorn` on Postgres, with no RAG packages installed.

| Measurement | Audit | Now |
|---|---|---|
| First referral on a fresh server | **133.9 s** | **0.033 s** |
| Second referral | 0.04 s | 0.019 s |
| Memory, idle | 143 MB | **82 MB** |
| Memory, after first referral | **662 MB** | **82 MB** |
| Memory, after 22 referrals and their 44 SMS | not measured | 82 MB |
| Python environment size | 1.7 GB (with CPU torch) | **155 MB** |
| Server ready after start | about 4 s | 1.7 s |

These figures are from `5917cfa`. The cleanup commit after it changes only type hints and two small guards.

## Re-verification (batch 3, step 0)

Requested before batch 3 started. **Status of Part B, with commits on `fix/batch-2`:**

| Item | Commit | On `fix/safety-batch-2` |
|---|---|---|
| B1 Alembic | `55cb5b7` | not done |
| B2 Durable cascade and restart recovery | `726104a` | not done |
| B3 Transactional SMS outbox | `1778869` | not done |
| B4 RAG and LLM removed from the request path | `5917cfa` | not done (timeout version only) |

Nothing was missing, so step 0 added no code. `fix/safety-batch-2` was left untouched.

**B4 proof in a fresh virtualenv with only `requirements.txt`** (52 MB, no torch, langgraph, langchain, chromadb, sentence-transformers or Google packages):

| Measurement | Audit | Fresh virtualenv |
|---|---|---|
| Server starts | yes | yes, in 3.2 s, with no errors in its log |
| First referral | 133.9 s | **0.043 s** |
| Memory, idle | 143 MB | **85 MB** |
| Memory, after first referral | 662 MB | **85 MB** |
| Memory, after 21 referrals and their SMS | not measured | 85 MB |

`pytest` isn't in `requirements.txt`, so the test run added `requirements-dev.txt` (test tools only, still no RAG packages): **411 passed, 4 skipped**, with `REQUIRE_POSTGRES_TESTS=1`. Three of the skips need `requirements-rag.txt`, and one needs `librosa`.

**Dart revert check redone for the 4 changes the script bug had hidden.** This run requires a real exit code, rejects compile errors, and names the failing tests. All four are caught:

| Change undone | Tests that failed |
|---|---|
| Missing vital beats RED | Critical BP with temperature missing is RED; measured total of 5 with vitals missing is RED; one critical value and nothing else measured is RED |
| Skip button sends an ordinary referral | No network: the referral is kept; type and facility alone send it |
| SpO₂ and missing-vitals note hidden | AVPU not measured alone is Incomplete; GREEN without SpO₂ says so; all not measured says Incomplete |
| Skip flag lost in the outbox | A queued skip-vitals referral keeps its flag when flushed |

This also settles the earlier caveat about "Missing list hidden", which is the third row. The §7.1.1 spec update mentioned in decision 1 below is now in `fix/batch-3`.

---

## Decisions for you to review

Items 1–4 matter most.

1. **`fix/safety-batch-2` is now superseded but still exists.** It overlaps A1–A4 but differs from this brief (`vitals_not_taken`, a JSON file with generated Dart, a differently named sheet). I reused its logic and tests and left the branch alone. Delete it when you're ready. **Its spec update is not in this branch:** `PRODUCT_SPEC.md` §7.1.1 still says GREEN, because this brief didn't list it. You asked for that change earlier, so it's worth carrying over: `git cherry-pick cf58d84` should apply, or I can redo it.
2. **A5 treats every 4xx as permanent, as specified, and that has sharp edges.** A wrong or rotated `API_KEY` gives 401, which permanently fails every referral sent until the app is fixed. A captive portal or dead tunnel that answers 403 or 404 does the same, even though the server never saw the referral. These referrals won't retry, though the CHO is told clearly to call manually. Consider whether 401 and 403 should keep retrying.
3. **Failed referrals have no way to be dismissed.** The brief didn't cover it, so I stopped there rather than design one. The Home banner stays after the CHO has dealt with the patient, and the rows, including vitals in plaintext, stay on the phone indefinitely. It needs a decision on a "handled" action and on retention.
4. **A provider outage can delay emergency SMS.** The sender works through up to 20 messages one at a time, with an 8 s timeout each, so a hung provider can take about 160 s per batch. A new emergency waits behind that. Failing fast or sending in parallel would help; I didn't add either, because it wasn't in the brief.
5. **`HOSPITAL_NOTIFIED` now means "queued", not "sent".** Accept commits this status with the SMS still in the outbox. If that SMS ultimately fails, the status doesn't change, but the CHO is alerted.
6. **SMS delivery is at least once.** If the server dies after sending and before recording, the SMS goes out again when its lease expires. I accepted a duplicate as better than a lost emergency message. Your brief's constraint of not holding a lock during the send requires this.
7. **I cancel driver offers that are still waiting once the dispatch is taken (added).** Otherwise a retried offer could tell a driver about an emergency someone else already has. This adds a `CANCELLED` status.
8. **A driver still counts as "notified" while their SMS is waiting (decision).** Only a permanently failed offer removes eligibility. Otherwise a driver could be refused because the sender hadn't run yet.
9. **The outbox numbers are my placeholders, on the sign-off sheet:** poll every 2 s, 5 attempts, 15 s backoff doubling, 60 s lease, batch of 20. With these, a failed driver SMS takes about 4 minutes to alert the CHO. The cascade moves on regardless. The cascade poll is 5 s as you specified, so a tier can run up to 5 s late.
10. **"Never gated on MOEWS" reached the result screen (added).** A GREEN result used to offer only Continue Monitoring. It now also offers "Refer with clinical judgment". If scoring itself ever throws, the referral still dispatches as UNKNOWN.
11. **`RAG_ENABLED` gates code that nothing calls.** No request path uses it either way, so turning it on doesn't put RAG back in a referral. It only lets the code in `src/agents` and `src/rag` run when called directly.
12. **`/docs` policy, vital ranges, and the other batch 1 decisions are unchanged.**

### Small changes that came with A2

- Emergency type starts blank instead of defaulting to respiratory distress, so the path really requires it.
- The dropdowns no longer overflow a 320 px phone. A new test caught this.
- An early tap on the facility now waits for the catalog, instead of doing nothing on a slow phone.
- "Continue Monitoring" is back on results where referral is the lead action (in A1).

### Breaking changes

- **`DATABASE_URL` is required in every environment.** The default credential is gone.
- **Existing local databases need attention.** `create_all` can't add the new columns and table. Either recreate the database, or run `alembic stamp 0001` then `alembic upgrade head`.
- **Production needs `alembic upgrade head` before starting.** It no longer creates tables.
- **Installs:** `requirements.txt` no longer includes the RAG packages. Use `requirements-rag.txt` to work on that code.
- **USSD and SMS internals changed:** `process_ussd` no longer takes `BackgroundTasks`, `handle_accept` and friends return the reply string, and `DispatchOrchestrator` no longer takes a gateway.
- **`calculate_moews` and the codec are no longer LangChain tools.** Use `score_vitals` and plain function calls.
- **`clinical_summary` is now a fixed template**, so its wording changed.

---

## What changed

### A1. Partial vitals

- **Scoring:** RED if any measured vital scores 3 or the measured total is 5 or more. Otherwise INCOMPLETE if a required vital is missing. SpO₂ stays optional. `src/tools/moews_calculator.py`, `mobile/lib/services/moews_calculator.dart`
- **Result screen:** shows "Incomplete" and the missing vitals, or "SpO₂ not measured". `mobile/lib/screens/result_screen.dart`
- **In sync:** `tests/fixtures/moews_cases.json` runs through both engines (`tests/test_moews.py`, `mobile/test/moews_shared_cases_test.dart`).

### A2. Emergency: skip vitals

- **App:** a button at the top of the referral screen, visible without scrolling on a 320 px phone. `mobile/lib/screens/referral_screen.dart`, `mobile/test/skip_vitals_test.dart`
- **API:** `vitals_taken=false` gives risk UNKNOWN and dispatches at once. Sending it with vitals returns 422. `src/api/referral.py`
- **Hospital SMS:** says "Vitals not taken". `src/services/hospital_notifier.py`
- **Storage:** the flag is in `vitals_json`.

### A3. Late-claim window

`LATE_CLAIM_WINDOW_MINUTES` defaults to 45. `src/parameters.py`, `src/config.py`, `src/services/dispatch_orchestrator.py`

### A4. Parameters

- **Modules:** `src/parameters.py` and `mobile/lib/parameters.dart`.
- **Sync test:** `tests/test_parameters.py` fails if shared values differ, pins every MOEWS band edge, and fails if the sheet stops matching.
- **Sheet:** `docs/PARAMETERS_SIGNOFF.md` lists each value, where it came from, and a blank sign-off column. It opens with four questions for the clinical lead, starting with whether children are in scope.

### A5. Permanent errors

- **Classification:** any 4xx except 408 and 429 is permanent. Network errors, 5xx, 408 and 429 retry, as does a non-JSON success. `mobile/lib/services/api_client.dart`, `offline_queue.dart`
- **Display:** a new screen gives the reason and tells the CHO to call manually, and a Home banner covers failures from background retries. `mobile/lib/screens/failed_referrals_screen.dart`, `home_screen.dart`, `queued_referral_screen.dart`

### A6. Small guards

`src/db/seed.py` refuses outside development. `DATABASE_URL` is a startup check everywhere and has no default. `src/config.py`, `src/db/database.py`

### B1. Alembic

`alembic.ini`, `migrations/`. Three revisions: baseline, next action, outbound messages. Startup only runs `create_all` in development. `tests/test_migrations_pg.py` runs the migrations on real Postgres and fails if they differ from the models, and checks that they reverse.

### B2. Durable cascade

- **Stored:** `next_action` and `next_action_at` commit with each state change. All in-memory timers are gone. `src/db/models.py`, `src/services/dispatch_orchestrator.py`
- **Worker:** started in the lifespan, polls every 5 s with `FOR UPDATE SKIP LOCKED`, and runs immediately on startup. `src/services/workers.py`, `main.py`
- **Restart test:** `tests/test_durable_cascade_pg.py` starts a real server, SIGKILLs it mid-tier, confirms nothing moved while it was down, restarts it, and asserts the cascade reaches FAILED with the CHO notice.

### B3. Outbox

- **Table:** `outbound_messages`, with the columns you listed.
- **Writes:** every SMS is inserted in the same transaction as its state change. Accept, decline and arrival now do all their work in that transaction, so `BackgroundTasks` is gone. This also fixes dispatches getting stuck at `ACCEPTED` after a crash. `src/services/dispatch_orchestrator.py`, `src/api/ussd.py`, `src/api/sms_webhook.py`, `src/services/hospital_notifier.py`
- **Sender:** claims with `SKIP LOCKED` in a short transaction, sends with no transaction open, and records in another. It retries with backoff, then marks FAILED and alerts the CHO for driver and hospital messages. `src/services/outbox.py`
- **Logs:** phone numbers and bodies are out of application logs, and recipients are stripped from stored provider responses. `src/services/messaging_gateway.py`. The real demo run logged 0 phone numbers. `dispatch_logs.target_phone` still holds numbers in the database, which is not a log file.

### B4. RAG out of the request path

- **Referral:** scores locally. The summary is a fixed template with no advice. `src/api/referral.py`, `src/tools/clinical_summary.py`
- **Dependencies:** moved to `requirements-rag.txt`. `tests/test_no_rag_in_request_path.py` checks in a separate process that neither importing the app nor making a referral loads any RAG package.
- **Kept:** `src/agents` and `src/rag`, behind `RAG_ENABLED`, off by default.

---

## Test evidence

| Check | After batch 1 | After this batch |
|---|---|---|
| `pytest`, `REQUIRE_POSTGRES_TESTS=1`, no RAG packages | n/a | **411 passed, 4 skipped** |
| Same, with RAG packages | 221 passed, 1 skipped | **414 passed, 1 skipped** |
| Postgres tests alone | 8 passed | **43 passed** (plus 1 test skipped on `librosa`) |
| Backend coverage | 78% | **79%** (`outbox.py` 99%, `workers.py` 100%, `dispatch_orchestrator.py` 96%) |
| `ruff check .` | 12 errors | **10 errors**, all already there |
| `mypy src main.py` | not run (audit: 28) | **21 errors in 4 files** |
| `flutter analyze` | no issues | **no issues** |
| `flutter test` | 84 passed | **137 passed** |
| `flutter test --dart-define=MOEWS_ONLY=false` | 83 passed, 1 skipped | **136 passed, 1 skipped** |
| `scripts/demo_flow.py` | passes | **passes**, 0 phone numbers in the server log |

**The 4 skips without RAG packages:** 3 need `requirements-rag.txt` and pass in the full environment. The other needs `librosa` and skips in both.

**The 10 `ruff` errors** are in `scripts/demo_flow.py`, `scripts/train_opera_ce_head.py`, `src/acoustic/opera_ce_mel.py` and `tests/test_messaging_gateway.py`, none on lines I wrote.

**`mypy` isn't clean.** 17 of the 21 errors are in `dispatch_orchestrator.py`, nearly all because `session.get()` can return None for rows the foreign keys guarantee exist. That pattern was already there, but I rewrote this file and could have tightened it. It is not a runtime failure the tests have shown.

**Real server boots:**

| Scenario | Result |
|---|---|
| Production, before migrating | Starts, creates 0 tables |
| `alembic upgrade head`, then `alembic check` | 10 tables, no drift |
| Production after migrating | `/` 200, `/docs` 404, referral without key 401 |
| Production with no `DATABASE_URL` | Refuses: `DATABASE_URL must be set; ...` |

For the production boots, the Africa's Talking URL pointed at a closed local port, so nothing could reach a live service.

### Undo-and-check

I undid each fix in a scratch copy and ran its tests, after confirming those tests pass unmodified. **All 53 were caught: 40 backend, 13 Dart.**

| Item | Undone | Caught |
|---|---|---|
| A1 Python | Missing vital beats RED; total of 5; missing can be GREEN; SpO₂ required | 4/4 |
| A1 Dart | Same four, plus missing list hidden, wrong Incomplete label, SpO₂ note hidden | 7/7 |
| A2 Python | Skip still scores; flag allowed with vitals; SMS omits it; scoring failure blocks dispatch | 4/4 |
| A2 Dart | GREEN gates referral; flag lost in the outbox | 2/2 |
| A3 | 2-hour default; not configurable | 2/2 |
| A4 | Python value differs; Dart value differs; sheet goes stale | 3/3 |
| A5 (Dart) | 4xx retries; 429 permanent; failed stays pending; refused shows as queued | 4/4 |
| A6 | Seed outside development; no URL check; default credential | 3/3 |
| B1 | `create_all` in production; model drifts from migrations | 2/2 |
| B2 | Not stored; worker not started; no SKIP LOCKED; repeat ignores state; bad row blocks others; first run delayed | 6/6 |
| B3 | Lock held during send; no limit; no backoff; no CHO alert; CHO alerts itself; stale offers sent; no lease; late result overwrites; phone logged; provider body logged; recipient stored; USSD calls provider | 12/12 |
| B4 | RAG imported; advice in summary; torch back; flag on by default | 4/4 |

**Two of these need explaining.** "First run delayed" made a test hang rather than fail, so I counted the hang as caught. "Missing list hidden" first failed because my mutation didn't compile, which proves nothing, so I redid it with one that compiles. It still failed, by exit code. The output I captured didn't show which test failed.

**Three of my own errors surfaced during this batch, all fixed:** a script committed A4 while one sync test was failing (I amended it and made later commits conditional on passing tests). A mechanical test edit left three arrival tests with no assertion (`ruff` flagged it, and I restored them). And USSD could pick the older of two dispatches on a timestamp tie (now breaks the tie by `id`, with a regression test).

---

## Verification limits

- **No device, no release build.** BUG-1 (the YAMNet buffer from batch 1) is still unconfirmed on a phone. Acoustic screening stays off by default.
- **No live Africa's Talking traffic.** The outbox has only been tested against a fake gateway and a mocked provider, not real sandbox SMS or USSD.
- **The restart test covers one server, one kill.** Workers running at once are tested in one process, not across several servers.
- **Latency and memory are from one machine and a small run,** not a load test.
- **The RAG code has only unit tests with mocks.** I didn't run it for real with `RAG_ENABLED=true`.

---

## Deferred

| Item | Why |
|---|---|
| **Failed referral dismissal and retention** | Needs a design decision. See decision 3. |
| **`PRODUCT_SPEC.md` updates** | Not in this brief. §7.1.1, §7.1.2 and §9.3 still describe the old behaviour. See decision 1. |
| **Home compound (BUG-15)** | Not in this brief. **Every install still dispatches as compound #1**, including skip vitals. |
| **SMS fallback when offline** | Not in this brief. **Skip vitals still can't dispatch without a data connection.** The referral queues, and the screen says drivers haven't been told. |
| **Diversion lifecycle (BUG-5), driver trip state (BUG-9)** | Not in this brief. Arrival after a diversion is still refused, and accept still doesn't set `ON_TRIP`. |
| **Stale queued referrals (BUG-12)** | Not in this brief. A referral queued for hours still dispatches live when it syncs. |
| **Audit log writes** | Not in this brief. `audit_logs` is still empty. |
| **Web build (BUG-19), OPERA-CE input shape** | Not in this brief. Both unchanged. |
| **Stale docs** | `docs/plans/at-sandbox-runbook.md` still has old USSD parsing, and `todo.md`, `TASK_BOARD.md` and `docs/architecture-narrative.md` still describe the old design. |
| **`src/tools/momo_escrow.py`** | Still dead code that imports the undeclared `requests`. |

**The pilot rating in `AUDIT_REPORT.md` stands.** This batch removes the worst reliability problems, but the two items that stop skip vitals working in the field, plus clinical sign-off, authentication and ethics clearance, are all still open.
