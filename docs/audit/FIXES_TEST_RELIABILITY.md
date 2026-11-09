# Test reliability fixes (`fix/test-reliability`)

**Base:** branched from `origin/main` at `3866918` (merge of PR #15, `rehearsal/at-sandbox`).

**Note:** `feat/ui-redesign` was not merged into `main` when this work started. The changes
here touch only `src/config.py` and the test setup, so the branch should rebase cleanly
after that merge.

## 1. `test_killed_mid_tier_cascade_continues_after_restart`

### Verdict: the test's environment, not the restart recovery (BUG-6 is not regressed)

**What the test checks.** It starts the API as a subprocess on a fresh Postgres database,
creates a referral, kills the server mid-tier, and restarts it. It then checks two things:

1. the cascade continues, so the dispatch reaches FAILED;
2. the "give up" SMS to the CHO is logged (`cho_give_up`).

**What failed.**

- Step 1 passed: the dispatch reached FAILED after the restart, so the durable cascade
  timing works.
- Step 2 failed: the dispatch log never got a `cho_give_up` row.

**Why.**

- `cho_give_up` is written by the SMS outbox only after the gateway reports the message as
  sent (`OutboxSender._record`).
- The test's server subprocess inherited the developer's environment, and `src/config.py`
  ran `load_dotenv()`. The local `.env` holds Africa's Talking sandbox credentials
  (`AT_API_KEY`, `AT_USERNAME`), so `settings.at_configured` was true and the server sent
  real SMS to the sandbox instead of mocking them.
- With the server's log captured, every send shows `AT SMS HTTP 401 (sandbox_form)`. The
  sandbox rejected the credentials, so the outbox backed off and retried, and nothing was
  logged within the test's 5-second wait.

**Evidence.** The test was run with the local `.env`, and with only the Africa's Talking
credentials blanked (`AT_API_KEY= AT_USERNAME=`):

| Commit | With the local `.env` | Credentials blanked |
|---|---|---|
| `5917cfa` (2nd commit after the test was added in `726104a`) | fail | pass |
| `9fe1d01` (PR #11 merge) | fail | pass |
| `cae05ca` | fail | pass |
| `origin/main` `3866918` | fail | pass (twice) |

**Why there is no bisect result.**

- No commit in the range turns the test from passing to failing in the same environment,
  so `git bisect` has no good/bad pair to search between. With the local `.env` it fails
  everywhere; with the credentials unset it passes everywhere.
- `726104a` itself could not run in today's test environment: its app imported the old
  RAG stack (`langchain_core`, `langgraph`, `langchain_chroma` → ChromaDB). Installing
  that stack was stopped as too heavy for this machine.
- `5917cfa`, which removed RAG from the request path, is the earliest commit that runs.

**When it "started failing".** When the developer's `.env` gained Africa's Talking sandbox
credentials, for the sandbox rehearsal merged as PR #15. That is an environment change, not
a code change.

**Fix (the cause, not the expectation).** The test's expectation, that a mock gateway logs
the give-up SMS, is right. What was wrong is that the suite let a developer's `.env` reach
the server it starts. See section 2: the same fix covers both.

## 2. Tests independent of the local `.env`

**Cause.** Four `test_startup_config` tests start subprocesses with `ENVIRONMENT` and
`DATABASE_URL` removed. `src/config.py` then called `load_dotenv()` from the repo directory,
which put the developer's values back. The tests then checked the `.env` instead of what
they had set:

- the docs stayed enabled;
- startup and seeding tried the `.env` database instead of refusing.

The same leak also forced earlier rounds to run the suite with `AT_WEBHOOK_SECRET=` on the
command line.

**Fix** (`a3a99aa`):

- **`src/config.py`:** `load_dotenv()` runs unless `YOMA_SKIP_DOTENV=1`. Normal use (servers,
  scripts, development) is unchanged.
- **`tests/conftest.py`**, before anything imports the config:
  - sets `YOMA_SKIP_DOTENV=1`;
  - removes every app setting from the environment (`APP_SETTINGS`: the `AT_*` keys,
    `API_KEY`, `DATABASE_URL`, `ENVIRONMENT`, the cascade and outbox timings and others);
  - sets only what the suite needs: `ENVIRONMENT=development` and an in-memory SQLite
    `DATABASE_URL`.

  Servers and scripts that tests start inherit this, so they read no `.env` either.
- **New tests in `tests/test_startup_config.py`:**
  - `test_suite_never_reads_a_developers_dotenv`: a throwaway `.env` is ignored with the
    switch and read without it;
  - `test_conftest_starts_the_suite_from_a_known_environment`: no real SMS credentials
    reach the suite.

## 3. Full suite with `REQUIRE_POSTGRES_TESTS=1`

Run on this machine with the developer's real `.env` in place, and no environment overrides
on the command line:

```
REQUIRE_POSTGRES_TESTS=1 python -m pytest -q
709 passed, 4 skipped in 143.10s — 0 failed
```

The 4 skips are optional dependencies, not Postgres tests. With
`REQUIRE_POSTGRES_TESTS=1`, a missing Postgres would have failed instead.

- `tests/test_opera_ce_mel.py`: needs `librosa`, the optional acoustic model features.
- `tests/test_clinical_path.py`, and two in `tests/test_task8_referral_flow.py`: need
  `requirements-rag.txt`, the optional RAG stack, which is not in the request path.

All Postgres tests ran, including all of `tests/test_durable_cascade_pg.py` (12 tests) and
`tests/test_late_claim_pg.py`.

**Before this fix,** with the same `.env`: 5 failed (the restart test and the 4 startup
tests), and the webhook tests also needed `AT_WEBHOOK_SECRET=` on the command line.
