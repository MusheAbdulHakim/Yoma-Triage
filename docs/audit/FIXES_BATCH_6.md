# Fixes: Batch 6

**Branch:** `fix/batch-6`, from `origin/main` at `9073198` (batch 5 merged), pushed to `origin` for a PR, not merged
**Source:** `docs/audit/AUDIT_REPORT.md` (BUG-5, BUG-9, security High "driver can DIVERT"), batch 6 brief

All five items are done, one commit each with tests, plus the demo, the emulator scenario and release signing. **Nothing has run on a physical phone, and nothing reached Africa's Talking, MTN MoMo or Supabase** (see [Verification limits](#verification-limits)).

| Item | Commit | Fixes |
|---|---|---|
| 1. Diversion lifecycle | `9dcbea9` | BUG-5 |
| 2. Only the destination facility can CONFIRM or DIVERT, with a code | `e93c3a7` | Security High "driver can DIVERT" |
| 3. Driver trip state, USSD context and availability | `c3fbba5` | BUG-9 (and the rest of BUG-10's menu) |
| 4. Notifications completeness | `e90970f` | Audit §6: CHO SMS on accept, hospital SMS on arrival |
| 5. Lifecycle test on Postgres | `8d80599` | |
| Demo includes a diversion | `45cf24b` | |
| Release signing from `key.properties` | `2a108d3` | Audit security High "debug key"; you supplied `~/yoma-release.jks` |
| Emulator: diversion scenario, s4/s5 on the new menu | `b105c0d` | |
| Docs: this report, spec 2.4, runbooks | the last commit | |

---

## Decisions for you to review

Items 1–5 matter most.

1. **DIVERT takes a facility code, and the notice lists the three nearest.** The brief offered a list of codes in the notice or matching the facility's name. I chose the list: a code is exact, while names are ambiguous ("Tamale", "TTH", "Tamale Teaching", two hospitals in one town) and typos would need fuzzy matching, where a wrong guess sends a patient to the wrong place. The code is the facility's id, so any facility can be named, not only the three listed. "Nearest" is straight-line distance from the current destination; facilities with no coordinates go last. A wrong code gets a reply listing the three again.
2. **The hospital code is separate from the Ref number drivers see.** The brief asks for a per-dispatch code for hospitals and a short dispatch code in USSD. If they were the same, every driver offered the referral would know the hospital's code, and could spoof the hospital's sender ID with it. So the hospital code is four random digits that appear only in the hospital's notice, and USSD uses the Ref number the driver's offer SMS already shows (the referral id). Codes are unique among open dispatches, and a diversion gives the new facility a new code, so the old facility's code stops working.
3. **USSD picks a referral by typing its Ref number, not by list position.** AT sends only the keys pressed, so a list numbered 1, 2, 3 can shift between screens (one is taken, another arrives) and "1" would then mean a different referral. Typing the Ref binds the choice to what the driver saw. The cost is one extra screen: accepting is now `1`, the Ref, `1` (three screens, was one). The offer SMS says exactly which keys to press. Menu map: root 1 Open referrals / 2 Confirm arrival / 3 Availability; `src/api/ussd.py` has the full map.
4. **A diversion is allowed until arrival, including after CONFIRM**, and puts the dispatch back to HOSPITAL_NOTIFIED, waiting on the new facility's CONFIRM. The audit noted DIVERT was rejected after CONFIRM; a hospital that confirmed and then finds it has no bed must still be able to send the patient on.
5. **Every hospital reply gets an SMS back, and AT always gets `GOOD`.** Before, unreadable or rejected replies returned `BAD …` to AT and the hospital heard nothing. JSON callers (demos) now get HTTP 200 with a `status` saying why (`NEED_CODE`, `UNKNOWN_CODE`, `NOT_YOUR_DISPATCH`, `UNKNOWN_FACILITY`, `DIVERT_REJECTED`, `INVALID`) instead of 400/404.
6. **A driver who declined still sees the referral while nobody has it**, as BUG-4's fix intended (they may change their mind). A driver on a trip sees no offers at all.
7. **A driver who goes Off duty mid-trip stays Off duty after arrival.** Only ON_TRIP is reset to AVAILABLE. The USSD Availability menu refuses changes during a trip; the REST endpoint doesn't (unchanged).
8. **"The dispatch failing sets them back to AVAILABLE" has no path to act on today.** Only an unclaimed dispatch can become FAILED. The release is wired into that path anyway, so a future change that fails a claimed dispatch can't strand its driver ON_TRIP. Arrival and cancellation are the live paths, and both are tested.
9. **A late accept sends every CHO the late alert, now with the vehicle, and no second "driver accepted" SMS.** An on-time accept sends only the referring CHO the routine one.
10. **Audit rows:** every driver availability change writes `audit_logs` (`entity_type=driver`, `action=driver_availability`, actor `dispatch`, `driver` or `api`, with from, to and the dispatch). Dispatch events stay in `dispatch_logs`, which now also records rejected hospital replies (`hospital_command_rejected`) with the sender's real role: `hospital`, `driver`, `cho` or `unknown`.
11. **Release signing falls back to the debug key, with a warning, when `key.properties` is missing**, so the emulator pass and test builds keep working. I couldn't read the keystore's alias without its password, so **you need to create `mobile/android/key.properties`** (format in `docs/deploy-environments.md`). Making production releases refuse to build without it, like A3's settings check, is a one-line change if you want it.
12. **The wording is mine and hasn't been reviewed:** the USSD screens, the hospital replies, the CHO accept and arrival SMS, the hospital arrival SMS and the diversion notices.

### Breaking changes

- **Hospitals must quote the code.** `CONFIRM`, `confirmed` and `CONFIRM <dispatch id>` without a code are refused with a reply asking for it. **Dispatches whose hospital was notified before this deploy have no code**, so their hospital can't CONFIRM or DIVERT by SMS; arrival still completes them. Deploy between trips if you can.
- **The USSD menu changed** (decision 3). Drivers need telling, and `docs/plans/demo-day-runbook.md` and `at-sandbox-runbook.md` are updated.
- **Migration `0007`** adds `dispatches.hospital_code` (nullable, indexed). Run `alembic upgrade head` before starting the new code.
- **Nothing sets DIVERTED any more.** Rows that already have it count as an open trip and can finish. Reports that treat DIVERTED as an end state should stop.
- **New SMS purposes:** `divert_old_hospital`, `cho_driver_accepted`, `hospital_arrival`. **New dispatch log actions:** `hospital_command_rejected`, `cho_accept_notify`, `hospital_arrival_notify`. **New dispatch API fields:** `facility_name`, `diverted_from`.
- **Driver availability now changes by itself.** Anything that sets it through the API should expect ON_TRIP.

---

## What changed

### 1. Diversion lifecycle (BUG-5)

- **Not a terminal status.** `DispatchOrchestrator.divert` changes the referral's and dispatch's facility and sets the status back to HOSPITAL_NOTIFIED, under the dispatch row lock. Arrival at the new facility completes it. `dispatch_orchestrator.py`
- **Who is told, in the same transaction:** the new facility gets the pre-arrival notice headed "DIVERTED here from …"; the old facility gets "Referral #N diverted to X. Do not expect this patient."; an unsent notice to the old facility is dropped; the driver and the referring CHO get the new destination.
- **The app** keeps polling after a diversion (and after a DIVERTED status from an older server), and shows "Going to: X" and "Diverted from Y by the hospital". `dispatch_status_screen.dart`, from the new `facility_name` and `diverted_from` in `GET /api/v1/dispatch/{id}`.
- **Refused, with a reply:** diverting to where the patient is already going, and diverting a dispatch that isn't open.

### 2. Who can CONFIRM and DIVERT

- **Facility only.** A reply acts only if the sender is the registered phone of the dispatch's current destination (any Ghana number format). Drivers, CHOs, other hospitals and strangers get "Code 4821 is not a referral for this number", and the attempt is logged with their real role. `sms_webhook.py`
- **The code.** Four random digits (`secrets`), unique among open dispatches, set when a facility is notified and replaced on diversion. Replies are `CONFIRM 4821` (or `CONFIRMED`, `YES`, `OK`) and `DIVERT 4821 7`. Migration `0007`. `hospital_notifier.py`
- **The notice** ends `Code: 4821`, `Reply CONFIRM 4821, or DIVERT 4821 <facility code>`, `Facility codes: 3 Near, 5 …, 2 …`, and now names the referral number.
- **Replies for each mistake:** no code, unknown code, not your referral, unknown facility (with the codes), already confirmed, already complete, not understood.

### 3. Driver trip state and USSD (BUG-9)

- **ON_TRIP.** Accepting sets it; arrival and cancellation set AVAILABLE (only from ON_TRIP, and only if the driver has no other open trip). An ON_TRIP driver isn't a candidate for new referrals, an offer already queued for them is dropped before sending, and accepting another returns "You are on a trip. Confirm arrival first." `dispatch_orchestrator.py`, `driver_pool.py`, `outbox.py`
- **USSD context.** Root shows the driver's state and how many referrals are open. A referral's screen shows its emergency type, compound, destination and how long ago it was sent. With several offers the driver sees them listed by Ref, oldest first, and picks one. `ussd.py`
- **Arrival** applies to the driver's own trip: one trip, `2` then `1`; several (only possible for trips from before this batch), pick by Ref. A repeat of `2*1` within 15 minutes gets the same "Arrival confirmed".
- **Availability menu:** `3`, then 1 Available or 2 Off duty. Refused during a trip.
- **Also fixed:** an offer dropped before it was sent no longer counts as the driver having been notified, so it can't make them eligible later.

### 4. Notifications

| Moment | CHO who referred | Every CHO at the compound | Driver | Destination facility | Old facility |
|---|---|---|---|---|---|
| Referral | | | offer (tier drivers) | | |
| Accept | **driver name, vehicle, phone, destination (new)** | | | pre-arrival with code | |
| Late accept (after the cascade gave up) | | late alert, **now with vehicle** | | pre-arrival with code | |
| Hospital CONFIRM | | | | confirm receipt | |
| DIVERT | new destination | | new destination | **pre-arrival, new code (new)** | **"diverted, don't expect" (new)** |
| Arrival | arrived, **names the facility** | | | **"patient has arrived" (new)** | |
| Cancel after accept | | | stand down | cancelled | |

`tests/test_notifications.py` checks the exact set of new messages at every step of the straight, divert, late and cancel paths.

### 5. Lifecycle test

`tests/test_lifecycle_pg.py`, on Postgres through the real endpoints: refer → offers → decline → second driver accepts → hospital CONFIRM → a driver's DIVERT refused → hospital DIVERT → new facility CONFIRM → arrival → COMPLETED. After each step it sends the outbox and checks the dispatch status, both drivers' availability, every new outbox message, every new dispatch log line (including the sender's send results) and every new audit row; 13 messages in all, each sent once.

### Release signing

`build.gradle.kts` signs releases with the key in `mobile/android/key.properties` (gitignored; keystore defaults to `~/yoma-release.jks`), or with the debug key and a warning without it. Checked with a throwaway keystore: the APK's signer was the throwaway certificate with the file, and "Android Debug" without it. The throwaway keystore and file were deleted.

---

## Found while doing this

- **The concurrency test was flaky because of BUG-9.** `test_parallel_accepts_have_exactly_one_winner` failed once in the first full run (both drivers "Accepted"), and passed alone 12 times. Cause: a driver who won an earlier round still held that trip, nothing ever finished it, and if their lookup ran just after the other driver's claim committed, "newest open dispatch" fell back to their old trip and answered "Accepted!" for it. Real double-claims didn't happen (one `ussd_accept` row), but a driver could be told they had a patient they didn't. Item 3 removes the cause; the test now finishes each round's trip, and passed 5 of 5 runs after.

---

## Test evidence

| Check | After batch 5 | After this batch |
|---|---|---|
| `pytest`, `REQUIRE_POSTGRES_TESTS=1` | 599 passed, 4 skipped | **671 passed, 4 skipped** |
| `ruff check .` | 10 errors | **9 errors**, all in files this batch didn't touch (the 10th, an import order in `demo_flow.py`, is fixed) |
| `mypy src main.py` | 11 errors in 4 files | **7 errors in 4 files**, all from before; 4 fewer, as the dispatch code now uses `get_one` |
| `flutter analyze` | no issues | **no issues** |
| `flutter test` | 320 passed, 2 skipped | **323 passed, 2 skipped** |
| `flutter test --dart-define=MOEWS_ONLY=false` | 321 passed, 1 skipped | **324 passed, 1 skipped** |
| `scripts/demo_flow.py` | passes | **passes**, now through a diversion to COMPLETED; 0 phone numbers and 0 tracebacks in the server log |
| Migrations up and down, compared with the models | no drift | **no drift** (`tests/test_migrations_pg.py`) |
| Emulator pass, both AVDs | every scenario passes | **every scenario passes on both**, including the new s11 (see below) |

### Revert check

I undid each fix in a scratch copy and ran its tests, after confirming they pass unmodified. **43/43 caught**, after one gap was closed.

| Item | Undone | Caught |
|---|---|---|
| 1 Backend | DIVERTED set again; no notice to the new facility; old facility not told; unsent notice to it kept; legacy DIVERTED can't finish; confirmed dispatch can't be diverted; API without `diverted_from` or `facility_name` | 8/8 |
| 1 Dart | Polling stops at DIVERTED; destination not shown; diversion not shown | 3/3 |
| 2 | Any sender may act; a driver's phone may act; rejection logged as the hospital, or not logged; no SMS back; a dispatch number passes as a code; no code confirms anyway; codes not unique; code not replaced on diversion; no facility codes, or not nearest first; unknown facility gets no list | 12/12 |
| 3 | Accept doesn't set ON_TRIP; arrival or cancel doesn't free the driver; ON_TRIP may claim; end of trip overrides OFF_DUTY; queued offer still sent; unsent offer counts as notified; no audit row; accept or arrival acts on the newest, not the chosen; offers newest first; offer screen without compound and destination; ON_TRIP driver still listed offers; availability not saved, or changeable mid-trip; repeat arrival answered differently | 16/16 |
| 4 | No CHO accept SMS; it leaves out the vehicle; late accept sends both; no hospital arrival SMS | 4/4 |

**What this check found:** listing offers to an ON_TRIP driver was missed at first. The offers menu has its own trip check, and the root menu's count was only tested with no other referral open. The missing case is a referral offered to the driver *before* they took a trip; `test_root_menu_counts_no_offers_during_a_trip` covers it and catches the revert.

### Emulator pass

The full pass ran both AVDs with every default scenario, plus s11. **API 24: every scenario passed. API 34: all but two passed, and both passed when rerun:**

- **s1** never ran: the runner stopped it after 15 minutes at "Downloading packages", a host network stall. Rerun: passed in 132 s.
- **s4** couldn't find the Confirm Referral button on the form, before any USSD or SMS step. The same test passed at 320 dp minutes later, and on API 24. Rerun: passed in 106 s. I don't know why it missed; it looks like the scroll-into-view flakiness batch 5 saw.

**s11 (new)** passed on both, in 87 s and 91 s. On each it showed the screen follow the trip from Tamale Teaching Hospital to Sagnarigu Polyclinic, with "Diverted from …" and the spinner still running; the driver's DIVERT refused; each hospital confirm with its own code; COMPLETED; the exact SMS to each party; and the driver back to AVAILABLE. Release timings: cold start first frame 1.4–2.7 s on API 24, Confirm Referral to drivers notified 1.7–1.9 s.

---

## Verification limits

- **No physical phone, and no real USSD gateway.** The menus were driven by HTTP the way AT posts them; how they look on a feature phone's screen, and whether AT trims the longer ones, is untested.
- **No live SMS.** The hospital codes, replies and diversion notices went to the mock gateway only. Whether staff read and reply with the code in practice is the real test.
- **Real signing** wasn't done: it needs your keystore's alias and passwords (decision 11).
- **Facility codes by distance** use the seeded coordinates, which come from geocoding district seats (audit §4).

---

## Deferred

| Item | Why |
|---|---|
| **A reason on DIVERT, and a new ETA** | Not in this brief. The spec asks for both. |
| **Partial unique index on open hospital codes** | Two accepts committing at the same moment could, very rarely, pick the same code for the same facility. The code is checked before use; an index would make it impossible. |
| **USSD Delay option, patient SMS on accept** | Not in this brief. |
| **Driver PIN** | Audit security High; caller ID is still the driver's only identity. |
| **Production releases refusing the debug key** | Your call (decision 11). |

**The pilot rating in `AUDIT_REPORT.md` stands.** Clinical sign-off of the placeholders, OTP, ethics clearance, real signing and real-device testing are still open.
