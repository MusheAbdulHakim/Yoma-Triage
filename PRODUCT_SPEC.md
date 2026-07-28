# Yoma Triage: Product Specification & Technical Design

## Document Control

| Field | Value |
|-------|-------|
| **Document Title** | Yoma Triage: Intelligent Clinical Triage, Edge Computing Decision Support, and Resilient Multi-Channel Emergency Referral Orchestration Platform for Northern Ghana |
| **Version** | 2.0 |
| **Date** | 23 July 2026 |
| **Status** | Final Draft for UNICEF StartUp Lab Hackathon |
| **Classification** | Internal / Hackathon Submission / Developer Reference |

---

# PART I — Executive Summary

## The Problem

Maternal and neonatal mortality remains one of the most critical healthcare challenges in Sub-Saharan Africa, particularly within the geographically remote and economically constrained Savannah and Sahelian belts of Northern Ghana. The maternal mortality ratio in Ghana persists at approximately 310 deaths per 100,000 live births, while specialized tertiary clinical audits document numbers as high as 801 deaths per 100,000 live births during periods of acute regional stress. These outcomes deviate from the United Nations Sustainable Development Goal Target 3.1, which mandates a global reduction to fewer than 70 maternal deaths per 100,000 live births by 2030.

The primary drivers of these preventable deaths are clinical complications such as postpartum hemorrhage, severe pre-eclampsia/eclampsia, and neonatal sepsis. These conditions are highly treatable if managed within the critical therapeutic window. However, the healthcare system in Northern Ghana is severely constrained by the physical and logistical barriers outlined in the traditional "Three Delays" model of maternal mortality.

While the First Delay (deciding to seek care) has been partially mitigated by public health education and the fee-exemption incentives of the Free Maternal Care Policy, the **Second Delay** (reaching a competent referral facility) remains an unresolved bottleneck. Rural primary care relies on over 6,500 Community-based Health Planning and Services (CHPS) compounds. These facilities are staffed by Community Health Officers (CHOs) who operate in clinical isolation without on-site specialist support, reliable diagnostic tools, or coordinated emergency transport.

## The Opportunity

This clinical crisis exists alongside a rapidly growing digital infrastructure. Ghana has achieved mobile penetration rates exceeding 132% and smartphone adoption rates of approximately 98% in active operational corridors. Mobile financial services have transformed regional economics through secure transaction rails such as MTN Mobile Money (MoMo) and Telecel Cash, which process billions of dollars in transaction value annually across millions of active accounts.

Simultaneously, progress in edge computing has enabled highly quantized Small Language Models (SLMs) to execute complex natural language processing and clinical decision support directly on inexpensive mobile hardware. This technical convergence allows the deployment of diagnostic support and logistical orchestration tools at the absolute edge of the primary care network, operating independently of cloud connectivity.

The UNICEF StartUp Lab hackathon explicitly calls for "early risk detection" and "improved referral follow-up" — the exact two problems Yoma Triage solves.

## The Solution

Yoma Triage is an offline-first, intelligent clinical triage and emergency referral orchestration platform designed specifically for rural primary care environments. Rather than introducing redundant diagnostic or physical transport assets, Yoma Triage acts as an intelligent coordination layer that bridges the gap between frontline clinical detection and definitive hospital care. The platform consists of two core components:

**Yoma Care (mobile / CHO app)** — An offline-first Flutter application (Android, iOS, and responsive web) for Community Health Officers. It guides CHOs through standardized triage, calculates MOEWS physiological risk scores, queues referrals offline, and aggregates clinical data into highly compressed SMS-safe payloads. For the hackathon demo, acoustic respiratory screening uses on-device YAMNet TFLite as an **advisory** AudioSet event detector — not a clinically validated obstetric diagnosis. On-device SLM triage is pilot backlog, not the current demo cut.

**Yoma Dispatch (gateway)** — A backend-mediated multi-channel communication gateway that transmits compressed clinical and transport data over standard USSD, SMS, and (later) Interactive Voice Response (IVR) networks. The mobile app never calls Africa’s Talking directly.

```
+-------------------------------------------------------------------------------+
|                               YOMA TRIAGE PRODUCT IDENTITY                        |
+-------------------------------------------------------------------------------+
|         WHAT IT IS                        |         WHAT IT IS NOT            |
+-------------------------------------------+-----------------------------------+
| • An intelligent routing protocol         | • A primary diagnostic system     |
| • A communication bridge for low-signal   | • A long-term Electronic Health   |
|   areas                                  |   Record (EHR) database           |
| • An automated dispatcher for existing    | • A logistics fleet owner         |
|   fleets                                 |                                   |
+-------------------------------------------------------------------------------+
```

## Why Now

- The UNICEF StartUp Lab hackathon provides a direct pathway to incubation and field piloting
- Ghana Health Service has adopted the SERC referral model into national CHPS implementation guidelines
- Africa's Talking has production-grade APIs across all Ghanaian telcos (MTN, AirtelTigo, Telecel)
- Google's HeAR event detectors (2025) provide purpose-built respiratory AI in TFLite format
- The KNUST National Health Access Platform (2025) has validated offline-first referral workflows in Northern Ghana

## Why Northern Ghana

Northern Ghana bears a disproportionate burden of maternal and child mortality. The Upper East and Upper West regions have the highest facility-based maternal mortality ratios in the country. CHPS compounds in these regions are understaffed (average 2.1 staff per zone in Karaga district), underequipped, and operating with paper-based systems. The SERC model originated here. The need is here. The hackathon is here.

## Why Yoma Triage

No existing solution connects AI-powered screening to emergency transport dispatch. LHIMS is online-only and lacks offline capabilities. DHIS2 is for epidemiological tracking, not real-time dispatch. CommCare supports custom forms but lacks automated multi-channel voice/USSD dispatching and real-time escrow payment integrations. MaaCheck, iMedic, and DeepBreath all stop at "detect and alert." Yoma Triage bridges these gaps by providing an offline-first clinical decision support system that converts clinical vitals into low-bandwidth coordination metrics, linking frontline workers with emergency logistics.

## Contextual Viability

Deploying health technology in Northern Ghana requires addressing severe systemic constraints, including frequent power grid failures, absent or intermittent internet connectivity, high clinical staff turnover, and strict budget limitations. Yoma Triage is engineered to function reliably on a remote Tuesday afternoon during a rainstorm when cellular towers are offline, the local nurse is alone, and a mother is actively bleeding. By converting the mobile devices already present in the field into a reliable clinical router, Yoma Triage eliminates the coordination failures that contribute to preventable rural mortality.

---

# PART II — Understanding the Problem

## The Three Delays Model

The Three Delays Model, first described by Thaddeus and Maine (1994), identifies three categories of delay that contribute to maternal mortality in developing countries:

1. **Delay in deciding to seek care** — lack of awareness, family resource constraints, cultural norms, quality concerns
2. **Delay in reaching care** — poor roads, scarcity of vehicles, no communication system to coordinate transport
3. **Delay in receiving care** — inaccessibility of competent providers, no lab/imaging at community level

In Northern Ghana, all three delays operate simultaneously. But the **Second Delay** — reaching care — is particularly lethal because it is the most addressable with technology.

### The Six Delays Model

To address the limitations of the traditional Three Delays framework, recent public health literature proposes a revised "Six Delays Model" (BMJ Global Health, 2025). This expanded framework adds three distinct stages to capture the operational complexity of pyramidal health systems:

4. **Delay in deciding to refer** — the CHO's decision-making process when identifying complications
5. **Delay in reaching the referral center** — the inter-facility transfer logistics
6. **Delay in receiving care at the referral center** — the hospital's preparation and response

By separating the initial care-seeking journey from the subsequent inter-facility transfer, this model highlights the critical role of inter-facility communication and transport logistics in patient survival. Yoma Triage specifically targets Delays 4 and 5 — the decision to refer and the coordination of transport.

## The Second Delay in Northern Ghana

The Second Delay is not about roads alone. It is about coordination.

The geography of Northern Ghana is characterized by highly dispersed settlements, low population density, and unpaved roads that are frequently washed out during the rainy season. The physical distance between a primary CHPS compound and the nearest district hospital often exceeds 15 kilometers, with neonatal and maternal mortality risk increasing significantly with travel time. Research demonstrates that children from households located more than 60 minutes from a health facility face a 25.6% increase in neonatal mortality risk compared to those within 10 minutes, with the risk of death rising to 26.6% for distances exceeding 10 kilometers.

A 2016 study in Global Health: Science and Practice documented emergency referral across four northern districts and found:

- Ambulances were typically absent, in repair, or located so remotely they were useless
- Patients reached facilities by walking, riding bicycles, donkey carts, or motorbikes
- Only 6% of facilities could provide basic emergency pregnancy care
- 39% of women who died or nearly died during childbirth delivered at unequipped facilities

## Existing Transport Initiatives and the "Motor-King" Framework

To address the lack of standard emergency vehicles in rural areas, various development partners and the Ghana Health Service have deployed three-wheeler motorized tricycles modified to serve as "Motor-King" community ambulances. Under initiatives like the KOICA CHPS-Plus project and Catholic Relief Services' HOPE-MCH project, hundreds of these tricycle ambulances have been distributed to CHPS zones across the Upper East and Northern regions.

These tricycle ambulances are fitted with basic stretchers, first aid kits, protective canopies, and double rear tires for stability on rough terrain. They are designed to navigate narrow, unpaved paths that are impassable for standard wheeled ambulances.

```
+-------------------------------------------------------------------------------+
|                       EXISTING RURAL TRANSPORT PARADIGM                       |
+-------------------------------------------------------------------------------+
|  CHPS Compound   === (Informal Voice Call) ===>   Motor-King Driver Contacts  |
|  - Isolated      | - Personal mobile phone      - Untracked availability     |
|  - No telemetry  | - Personal airtime cost      - Subjective fuel status     |
|                  | - No status logging          - Informal pricing pressure  |
|                  v                                                            |
|  Uncoordinated, fragmented dispatch leading to prolonged transport delays    |
+-------------------------------------------------------------------------------+
```

Despite their physical suitability, these tricycle networks operate on an ad-hoc, uncoordinated basis. There is no central registry of active drivers, no real-time tracking of vehicle availability, and no structured dispatch mechanism. When an emergency occurs, the CHO must manually call known local drivers, often facing busy lines, unanswered calls, or drivers who are out of fuel.

Furthermore, because the National Health Insurance Scheme explicitly excludes emergency transport costs, rural families are often forced to pay for fuel and driver fees out-of-pocket, leading to catastrophic expenses or delayed transfers while funds are mobilized.

## Why Fragmented Communication and Voice Calls Cause Critical Delays

The current mechanism for coordinating referrals within the Ghana Health Service relies on unstructured voice calls. This model has several systemic limitations:

- **Telecom Cost Barriers**: Health workers must use their personal mobile phones and private airtime to coordinate referrals. When a CHO is out of prepaid credits, referral communication is delayed or abandoned.
- **Ineffective Hospital Preparation**: Receiving district hospitals are rarely prepared for incoming emergency transfers. Due to a lack of pre-arrival data, emergency departments cannot prepare surgical suites, secure compatible blood types, or mobilize specialist staff in advance.
- **Referral Note Decay**: Under GHS guidelines, all referrals must be accompanied by a completed paper-based standard referral form. In practice, over 70% of referred patients arrive with incomplete referral notes or none at all. CHOs operating under high stress often prioritize patient care over document completion, leading to a complete loss of clinical history when the patient is handed over to the receiving facility.

## The Current Referral Workflow

The baseline emergency workflow within Northern Ghana's rural districts operates as a series of disconnected, manual steps:

```
[Patient Deterioration at Home]
             |
             v
[Delay 1: Deciding to Seek Care (Family consultations, financial hesitation)]
             |
             v
[Travel to Frontline CHPS Compound via Foot or Commercial Motorcycle]
             |
             v
[Frontline Assessment by CHO (No digital clinical decision support)]
             |
             v
[Manual Stabilization & Search for Transport (CHO calls local driver on private phone)]
      |-- Carrier Network Congestion
      |-- CHO out of personal airtime credits
      -- Driver unavailable or out of fuel
             |
             v
[Delay 2: Reaching Referral Facility (Transit on unpaved roads via unmonitored Motor-King)]
             |
             v
[Arrival Unannounced at District Hospital (Paper referral form missing or incomplete)]
             |
             v
[Delay 3: Receiving Care (Redundant diagnostics, unnotified surgical team, unready blood bank)]
             |
             v
[Definitive Treatment Initiated (Often delayed beyond the therapeutic window)]
```

### Analysis of Primary Bottlenecks

- **Diagnostic Delay at the Edge**: In rural clinics, newly deployed CHOs often face high cognitive loads and diagnostic isolation during acute emergencies. Without real-time decision support, clinicians may delay the decision to refer a patient with atypical complications. This manual triage process lacks the objective structure needed to identify clinical deterioration before the patient's condition becomes critical.
- **Transport Brokerage Collapse**: The lack of a centralized, real-time dispatch system forces CHOs to spend critical minutes calling individual drivers from personal contact lists. When a driver is unreachable or lacks fuel, the CHO must restart the search, losing valuable time while the patient remains unstable.
- **The Telecommunication Cost Barrier**: Referral coordination is frequently delayed because frontline health workers must use personal mobile airtime to call drivers and receiving hospitals. If a CHO is out of prepaid credits, they must purchase airtime or send a physical message, creating a direct point of failure.
- **Complete Absence of Hospital Telemetry**: Paper-based referral forms are rarely completed or delivered during acute transfers. Consequently, receiving hospitals have no advance notice of a patient's arrival or clinical status. This forces emergency department staff to perform redundant diagnostic workups and delays the mobilization of critical resources like blood units or surgical teams.

---

# PART III — User Research

## Methodology

User personas are composite profiles built from published research on CHPS operations in Northern Ghana. Sources include:

- PLOS One (2026): Northern Ghana CHPS zone staffing and operations study
- MOTECH Ghana (2010): Mobile Technology for Community Health survey
- Global Health: Science and Practice (2016): Emergency referral in northern Ghana
- SERC Model documentation (2012-2015): Upper East Region referral system
- UNICEF/KOICA CHPS+ project reports (2025)
- Nature Scientific Reports (2025): CHPS compound technology usage

Each persona represents a real role in the CHPS ecosystem with constraints drawn from empirical data.

## Persona 1: Abiba — Community Health Officer

| Attribute | Detail |
|-----------|--------|
| **Age** | 28-35 |
| **Location** | CHPS compound, Kassena-Nankana East Municipal |
| **Education** | Two-year postsecondary certificate in community health nursing |
| **Phone** | Shared Android smartphone (provided by CHPS+ project) |
| **Digital literacy** | Basic — uses phone for calls and WhatsApp, not comfortable with complex apps |
| **Daily workload** | 15-25 patients, home visits, community health education |
| **Language** | Dagbani (primary), English (medical documentation) |

**Goals:**
- Provide quality care to her community
- Detect complications early and refer appropriately
- Maintain paper registers accurately
- Keep her community health volunteers motivated

**Pain points:**
- Cannot detect subtle breathing distress in infants — relies on visual observation
- When she identifies an emergency, she spends 30-60 minutes coordinating transport
- Phone calls to drivers often go unanswered
- No way to notify the hospital before the patient arrives
- Paper registers are lost or damaged
- Feels isolated — no specialist to consult with

**Opportunities:**
- Would use a simple, one-button screening tool if it helped her detect problems earlier
- Would use SMS-based dispatch if it saved her from making multiple phone calls
- Wants to feel confident in her referral decisions

## Persona 2: Fatima — Midwife

| Attribute | Detail |
|-----------|--------|
| **Age** | 32-40 |
| **Location** | CHPS compound, Tamale Metro |
| **Education** | Midwifery certificate |
| **Phone** | Personal feature phone (Nokia basic) |
| **Digital literacy** | Low — SMS and voice calls only |
| **Daily workload** | Antenatal care, deliveries, postnatal follow-up |
| **Language** | Dagbani, Gonja |

**Goals:**
- Safe deliveries for every mother
- Early detection of maternal complications
- Quick referral when complications exceed her capacity

**Pain points:**
- Postpartum hemorrhage can escalate in minutes — she needs transport NOW
- No emergency transport system in her zone
- Often alone at the compound — no one to help coordinate
- Feature phone limits her to calls and SMS

**Opportunities:**
- Would benefit from a system that automatically alerts drivers when she sends an SMS
- Needs voice-based notifications in Dagbani

## Persona 3: Amina — Caregiver (Mother)

| Attribute | Detail |
|-----------|--------|
| **Age** | 18-30 |
| **Location** | Village near CHPS compound |
| **Education** | Primary school (incomplete) |
| **Phone** | No phone / shared family phone |
| **Digital literacy** | None |
| **Language** | Dagbani only |

**Goals:**
- Her child gets better
- She doesn't lose her child
- She can afford the transport and treatment

**Pain points:**
- Doesn't recognize early signs of respiratory distress
- When told her child needs hospital referral, she doesn't know how to arrange transport
- Cannot afford transport costs (GHS 50-100 for a Motor-King ride)
- Husband works in Tamale — unreachable during the day
- Relies on neighbors and family for emergency support

**Opportunities:**
- Would respond to voice-based health education in Dagbani
- Would benefit from a community emergency fund that covers transport costs
- Needs to be notified in simple language when transport is arranged

## Persona 4: Ibrahim — Motor-King Driver

| Attribute | Detail |
|-----------|--------|
| **Age** | 25-40 |
| **Location** | CHPS compound catchment area |
| **Phone** | Basic phone (feature phone) |
| **Digital literacy** | Low — SMS and voice calls |
| **Vehicle** | Three-wheeled motorcycle (Motor-King) |
| **Income** | Variable — depends on fares |
| **Language** | Dagbani |

**Goals:**
- Earn a living from transport
- Help his community when needed
- Be recognized as a reliable emergency responder

**Pain points:**
- No advance notice of emergencies — waits at the CHPS compound or goes about his day
- Sometimes the phone rings when he's on another trip
- No way to confirm he's accepted the dispatch
- Fuel costs are his responsibility — no reimbursement mechanism
- Occasionally asked to transport patients to distant hospitals without payment

**Opportunities:**
- Would register as an emergency driver if there was a simple way to receive alerts
- Would respond to SMS alerts if he could confirm via USSD
- Needs a reimbursement mechanism for emergency fuel costs

## Persona 5: Nurse Efua — District Hospital Receiving Nurse

| Attribute | Detail |
|-----------|--------|
| **Age** | 30-45 |
| **Location** | Tamale Teaching Hospital / District Hospital |
| **Phone** | Hospital phone (shared) |
| **Digital literacy** | Moderate — uses DHIS2 for reporting |
| **Language** | English, Dagbani |

**Goals:**
- Receive patients with adequate preparation time
- Have clinical information before the patient arrives
- Manage emergency department flow efficiently

**Pain points:**
- Patients arrive without notification
- No clinical history available
- Emergency department is often surprised by incoming referrals
- No way to communicate back to the referring CHPS compound

**Opportunities:**
- Would appreciate advance SMS notification with patient details and ETA
- Would use a simple dashboard to confirm receipt of referral
- Wants to provide feedback to referring facilities

## Persona 6: Dr. Mohammed — Medical Superintendent

| Attribute | Detail |
|-----------|--------|
| **Age** | 40-55 |
| **Location** | District Hospital |
| **Phone** | Personal smartphone |
| **Digital literacy** | High |
| **Language** | English, Dagbani |

**Goals:**
- Ensure his hospital is prepared for incoming emergencies
- Track referral volumes and patterns
- Advocate for resources based on data
- Reduce preventable deaths

**Pain points:**
- No visibility into what's happening at CHPS compound level
- Cannot plan resource allocation based on referral patterns
- Referral data is scattered across paper registers

**Opportunities:**
- Would use a dashboard showing real-time referral activity across his catchment area
- Would advocate for Yoma Triage adoption if he saw evidence of reduced delays
- Wants data to justify budget requests to the District Health Directorate

---

# PART IV — Current Workflow

## Referral Process Flowchart

The following represents the current (broken) emergency referral process in a typical CHPS compound:

```
PHASE 1: DETECTION
━━━━━━━━━━━━━━━━━━━
Mother brings child to CHPS compound
        ↓
CHO observes child (visual inspection only)
        ↓
CHO notes "breathing fast" in paper register
        ↓
No auscultation tool available
        ↓
CHO makes clinical judgment based on experience
        ↓
Decision: "This child needs hospital care"
        ↓
[TIME ELAPSED: 5-15 minutes]


PHASE 2: COORDINATION
━━━━━━━━━━━━━━━━━━━━━━
CHO picks up phone
        ↓
Calls Motor-King driver #1
        ↓
No answer (phone off / in another call)
        ↓
Calls Motor-King driver #2
        ↓
Driver is at another location — "I can come in 20 minutes"
        ↓
CHO calls ambulance service
        ↓
Ambulance is at the district hospital — 45 minutes away
        ↓
CHO asks family to find transport
        ↓
Family calls neighbor with motorcycle
        ↓
Neighbor is not available
        ↓
CHO makes more phone calls
        ↓
Finally finds a willing driver
        ↓
[TIME ELAPSED: 30-90 minutes]


PHASE 3: TRANSPORT
━━━━━━━━━━━━━━━━━━━
Family borrows money for fuel (GHS 50-100)
        ↓
Driver arrives at CHPS compound
        ↓
Patient loaded onto Motor-King
        ↓
Driver navigates to district hospital
        ↓
Road conditions vary (poor in rainy season)
        ↓
[TIME ELAPSED: 20-60 minutes]


PHASE 4: ARRIVAL
━━━━━━━━━━━━━━━━━
Patient arrives at hospital
        ↓
Hospital was NOT notified
        ↓
Receiving nurse scrambles to prepare
        ↓
No clinical history available
        ↓
CHO's paper register is at the CHPS compound
        ↓
[TIME ELAPSED: 10-20 minutes for triage]


PHASE 5: FOLLOW-UP
━━━━━━━━━━━━━━━━━━━
CHO has no way to confirm patient arrived
        ↓
CHO calls hospital (when she can)
        ↓
Sometimes reaches someone, sometimes doesn't
        ↓
No documentation of the referral outcome
        ↓
Paper register entry: "Referred to hospital"
        ↓
No follow-up mechanism
```

## Bottleneck Analysis

| Phase | Bottleneck | Impact | Yoma Triage Solution |
|-------|-----------|--------|-----------------|
| Detection | No auscultation tool | Delayed recognition of distress | Acoustic AI screening (Breathe) |
| Coordination | Sequential phone calls | 30-90 minute delay | Parallel SMS dispatch (Go) |
| Coordination | No status visibility | CHO doesn't know if driver is coming | Real-time dispatch status via SMS |
| Transport | No reimbursement mechanism | Drivers reluctant to respond | MoMo escrow for fuel costs |
| Transport | No fallback if Motor-King unavailable | Patient stranded | Volunteer drivers + personal contacts |
| Arrival | Hospital not notified | Unprepared receiving team | Automated SMS to hospital |
| Follow-up | No confirmation mechanism | CHO doesn't know if patient arrived | Driver confirms arrival via USSD |

---

# PART V — Yoma Triage Vision

## What Yoma Triage Is

Yoma Triage is the intelligent coordination layer between frontline detection and definitive care.

It is not a diagnostic system. It does not tell the CHO what disease the child has. It provides a screening signal — Normal or Code Red — that helps the CHO make a faster, more confident referral decision.

It is not an ambulance service. It does not own vehicles or employ drivers. It coordinates existing community transport resources — Motor-King drivers, volunteer drivers, personal contacts — through a structured dispatch system that works over SMS and voice.

It is not a replacement for clinical judgment. The CHO remains the decision-maker at every step. Yoma Triage provides data and coordination; the CHO provides expertise and authority.

## What Yoma Triage Solves

Yoma Triage addresses the two failures that kill children in Northern Ghana:

1. **Detection failure** — By providing acoustic respiratory screening that runs on a smartphone, Yoma Triage helps CHOs detect breathing distress earlier than visual observation alone.

2. **Transport failure** — By providing a cascading dispatch system that works over SMS and voice, Yoma Triage ensures that when a referral is needed, transport is arranged in minutes, not hours.

## What Yoma Triage Does Not Solve

Yoma Triage does not solve:
- Road infrastructure (requires government investment)
- Hospital capacity (requires health system strengthening)
- CHPS compound staffing (requires workforce development)
- Family willingness to seek care (requires community education)
- Treatment quality (requires clinical training and supplies)

Yoma Triage focuses on the narrow, addressable gap between detection and transport. Everything else is outside its scope.

**Critical design choice:** Yoma Triage respects patient and family autonomy. If a family refuses transport, the system documents the refusal but never forces referral. The CHO manages the relationship, provides health education, and remains available if the family changes their mind. See Journey 5 in Part XII for a detailed scenario.

---

# PART VI — Product Principles

## Principle 1: Offline-First

Yoma Triage must work with no internet connectivity. The acoustic AI runs entirely on-device. The dispatch system operates via SMS and USSD, which work on 2G networks. The backend syncs when connectivity is available but never requires it for core functionality.

**Test:** Would this work in a CHPS compound in Karaga district where the only connectivity is 2G and the power goes out twice a day?

## Principle 2: AI Assists, Never Replaces

The AI provides screening signals and risk scores. It never makes clinical decisions. The CHO decides whether to refer. The driver decides whether to accept. The hospital decides how to treat. AI augments human judgment; it does not substitute for it.

**Test:** If the AI is wrong, is there a human who can catch the error before it harms a patient?

## Principle 3: Human-in-the-Loop

Every critical action requires human confirmation. The CHO confirms the referral. The driver accepts or declines. The hospital acknowledges receipt. No automated system acts without human authorization.

**Test:** Can any automated action in the system cause patient harm without a human explicitly authorizing it?

## Principle 4: Low-Literacy by Design

The system must work for users with minimal literacy. Voice notifications in local languages. Simple visual indicators (red/green). USSD menus with numbered options. No complex text input required.

**Test:** Can Abiba's mother, who speaks only Dagbani and cannot read, understand that transport has been arranged?

## Principle 5: Voice-First

Voice notifications are not a fallback — they are the primary interface for drivers and patients. TTS in Dagbani and other local languages. Simple, clear messages. No technical jargon.

**Test:** Can Ibrahim, driving his Motor-King with the phone in his pocket, understand the emergency alert without looking at the screen?

## Principle 6: SMS/USSD as the Backbone

SMS and USSD work on every phone, on every network, in every village. They are the most reliable communication channels in Northern Ghana. Yoma Triage builds on them, not around them.

**Test:** Does the core dispatch flow work entirely via SMS and USSD, with no dependency on smartphones or data connections?

## Principle 7: Minimal Data Collection

Collect only what is necessary for the referral to succeed. Patient name and phone number. Location. Severity. Driver information. Transport cost. Nothing more. No diagnosis. No clinical notes. No medical history.

**Test:** If this data were leaked, would it cause harm? If yes, don't collect it.

## Principle 8: Explainable AI

Every AI output must be explainable in plain language. "This child's breathing sounds faster than normal" — not "Model confidence: 0.87." The CHO needs to understand WHY the AI is suggesting a referral, not just that it is.

**Test:** Can the CHO explain to the caregiver why the child needs to go to the hospital, based on what the AI told her?

## Principle 9: Fail Safely

When any component fails — network, AI, dispatch — the system degrades gracefully. The CHO can always fall back to manual coordination. The driver can always call the CHO directly. The hospital can always be reached by phone. Yoma Triage enhances the existing system; it never replaces it to the point where failure is catastrophic.

**Test:** If Yoma Triage's servers go down tomorrow, does the CHPS compound's emergency referral process revert to today's manual system — or does it break entirely?

---

# PART VII — Functional Specification

## 7.1 Referral Initiation

### 7.1.1 Acoustic Screening (Breathe)

**Trigger:** CHO suspects respiratory distress in a child under 5.

**Flow:**
1. CHO opens Yoma Triage app on smartphone
2. CHO selects "Screen Breathing"
3. CHO holds phone near child's chest (microphone facing the child)
4. App records 60 seconds of audio
5. On-device AI (YAMNet or HeAR event detector) analyzes the audio
6. App displays result:
   - **GREEN: Normal** — Breathing sounds within normal range. Continue monitoring.
   - **RED: Code Red** — Abnormal breathing pattern detected. Consider referral.
7. CHO reviews the AI's reasoning: "Faster than normal rate detected" / "Wheezing sounds detected"
8. CHO decides: Refer or Continue Monitoring
9. If Refer: CHO confirms referral, triggering dispatch

**Technical details:**
- Audio recorded at 16kHz, mono, PCM format
- YAMNet processes 0.975-second windows continuously
- Classification: normal breathing, wheeze, crackle, stridor
- Confidence threshold: >0.7 for Code Red
- Entire process runs on-device — no internet required
- Model size: 4.13 MB (YAMNet) or 5-10 MB (HeAR event detector)

**Safety guardrails:**
- AI output is advisory only — CHO makes the referral decision
- If AI confidence is below 0.5, app displays "Inconclusive — use clinical judgment"
- App never overrides CHO decision
- If app crashes during recording, CHO can restart — no data loss

### 7.1.2 Manual Referral Trigger

For cases where the acoustic screening is not applicable (maternal hemorrhage, neonatal sepsis, etc.), the CHO can trigger a referral manually:

1. CHO opens Yoma Triage app
2. CHO selects "Emergency Referral"
3. CHO selects emergency type from dropdown:
   - Respiratory distress
   - Maternal hemorrhage
   - Neonatal sepsis
   - Suspected malaria (severe)
   - Other emergency
4. CHO enters patient name (or "Unknown")
5. CHO confirms referral

This ensures Yoma Triage is useful beyond respiratory screening.

## 7.2 Transport Brokerage

### 7.2.1 Cascade Dispatch

When a referral is triggered, the system executes a cascading dispatch sequence:

```
T+0 seconds: Referral triggered
        ↓
T+0: SMS sent to Motor-King driver(s) in the CHPS zone
        ↓
T+90 seconds: No response → Voice call to Motor-King driver(s)
        ↓
T+180 seconds: No response → SMS sent to fallback drivers
        ↓
T+270 seconds: No response → Voice call to fallback drivers
        ↓
T+360 seconds: No response → SMS sent to personal emergency contacts
        ↓
T+450 seconds: No response → CHO notified: "No driver available — coordinate manually"
```

**Key parameters:**
- SMS delivery time: 2-5 seconds (Africa's Talking)
- Voice call connection time: 10-20 seconds
- Response timeout per tier: 90 seconds
- Total maximum cascade time: ~8 minutes
- If no response after full cascade, CHO reverts to manual coordination

### 7.2.2 Driver Response

Drivers respond via USSD:

1. Driver receives SMS: "EMERGENCY: Patient at [CHPS compound]. Reply via *XXX# to accept or decline."
2. Driver dials `*XXX#` (Yoma Triage USSD code)
3. USSD menu displays:
   ```
   EMERGENCY DISPATCH
   1. Accept — I'm on my way
   2. Decline — I can't make it
   3. Delay — I'll be there in 15 minutes
   ```
4. Driver selects option
5. System updates dispatch status and notifies CHO

**If driver accepts:**
- CHO receives SMS: "Ibrahim (Motor-King, Red tricycle) has accepted. ETA: 12 minutes."
- Patient receives SMS (if phone available): "Your transport is on the way. Driver: Ibrahim. Vehicle: Red tricycle."
- Hospital receives SMS: "Emergency referral from [CHPS compound]. Patient: [name]. Condition: [type]. ETA: [time]."

**If driver declines:**
- System proceeds to next tier in cascade

**If driver delays:**
- CHO receives SMS: "Ibrahim can be there in 15 minutes. Accept delay?"
- CHO replies via USSD: Yes/No
- If No: system proceeds to next tier

### 7.2.3 Driver Pool Management

**Registration:**
- Motor-King drivers register at the CHPS compound with: name, phone, vehicle type, vehicle description, license plate (if any)
- Registration happens once — driver data is stored in the system
- CHOs can add/remove drivers from their zone's pool

**Availability:**
- Drivers can mark themselves as "Available" / "On Trip" / "Off Duty" via USSD
- System only dispatches to "Available" drivers
- If all registered drivers are unavailable, system proceeds to fallback tier

### 7.2.4 Fallback Tiers

**Tier 1: Motor-King drivers** (registered, trained, equipped)
**Tier 2: Fallback drivers** (registered volunteers with personal vehicles)
**Tier 3: Personal emergency contacts** (patient's family/friends added by CHO or patient)

For personal emergency contacts:
- CHO adds contact: name, phone, relationship
- System sends SMS: "EMERGENCY: [Patient name] needs transport to [hospital]. Can you help? Reply YES or NO."
- If YES: contact becomes the de facto driver
- If NO: system continues cascade

## 7.3 Hospital Handoff

### 7.3.1 Pre-Arrival Notification

When a driver accepts the dispatch, the system automatically sends an SMS to the receiving hospital:

```
YOMA TRIAGE EMERGENCY REFERRAL
From: [CHPS compound name]
Patient: [Patient name]
Age: [Age/Gender]
Condition: [Emergency type]
Severity: Code Red
AI Screen: [Normal/Code Red/Not screened]
Driver: [Driver name]
ETA: [Estimated time of arrival]
Time: [Current time]
```

### 7.3.2 Hospital Confirmation

The hospital receives the SMS and can reply:
- `CONFIRM` — We are prepared for this patient
- `DIVERT` — Send to [alternative hospital] (with reason)

If DIVERT:
- System notifies driver: "Hospital unable to receive. Diverting to [alternative]. New ETA: [time]."
- System notifies CHO: "Hospital diverting patient to [alternative]."

### 7.3.3 Arrival Confirmation

When the driver arrives at the hospital:
1. Driver dials `*XXX#` (USSD)
2. Selects "Confirm Arrival"
3. System sends confirmation to CHO: "Patient arrived at [hospital]. Time: [time]."
4. System sends confirmation to hospital: "Patient [name] has arrived."
5. Dispatch status updated to "Completed"

## 7.4 Emergency Wallet

### 7.4.1 Purpose

Transport costs are a primary barrier to emergency referral in Northern Ghana. NHIS covers treatment but not transport. Families often cannot afford the GHS 50-100 needed for a Motor-King ride to the hospital.

### 7.4.2 Mechanism

**Escrow Contract Engine:**

To remove the transport cost barrier, Yoma Triage integrates an automated, multi-party escrow framework using local mobile money APIs. Each registered facility has access to an Emergency Transport Wallet funded by development partners (such as UNICEF) or GHS regional budgets.

**Verifiable Transaction Flow:**

1. **Activation**: When a driver accepts an emergency referral via USSD or IVR, the system locks a pre-calculated transit fee (based on distance and road quality) in the platform's escrow wallet.
2. **Fuel Payout**: A small, automated mobile money payout (30% of the total fare) is immediately disbursed to the driver's registered MTN MoMo or Telecel Cash wallet to cover immediate fuel costs.
3. **Completion Handshake**: Once the driver delivers the patient to the referral hospital, the receiving triage nurse inputs a unique receipt code on the hospital terminal, or the driver dials a confirmation code. This triggers the instant release of the remaining 70% of the fare directly to the driver's mobile money account.

This 30/70 split model ensures drivers are incentivized to respond immediately (fuel money upfront) while maintaining accountability (full payment only on verified delivery).

**Funding Sources:**

| Source | Description | Status |
|--------|-------------|--------|
| Community Emergency Fund | Pre-funded MoMo merchant account from NGO grants | Primary for pilot |
| NHIS Transport Voucher | Integrate transit costs into NHIS reimbursement framework | Phase 2 |
| LEAP Integration | Livelihood Empowerment Against Poverty cash transfers for poorest families | Phase 2 |
| Patient MoMo Wallet | Direct patient payment for non-emergency cases | Fallback |

### 7.4.3 Simulated for Hackathon

For the hackathon demo **and current code path**, the MoMo escrow is a **mock ledger only**:
- USSD accept records `momo_escrow` with response `MOCK_RECORDED` — **no MTN MoMo API call**
- Drivers are told the stipend is mock until MoMo is live
- Demo pitch: "Ledger records the intended 30% fuel stipend; production connects MTN MoMo when merchant keys ship"

**What's demo-only vs. production-required:**

| Component | Hackathon MVP | Production Required |
|-----------|---------------|-------------------|
| MoMo escrow | Simulated UI flow | Africa's Talking Payments API + MTN MoMo merchant account |
| Voice calls | English TTS only | Dagbani TTS + pre-recorded messages |
| USSD code | `*XXX#` placeholder | Provisioned shared code (USD 100 setup + GHS 900/month) |
| Driver payment | Manual reimbursement | Automated MoMo disbursement on arrival confirmation |
| Community fund | Not implemented | MoMo merchant account with NGO/grant funding |

## 7.5 Voice Notifications

### 7.5.1 Purpose

Voice notifications ensure that users with low literacy or feature phones receive critical information in their local language.

### 7.5.2 Implementation

Using Africa's Talking Voice API:
- Text-to-speech in Dagbani (primary) and English (fallback)
- Automated calls to drivers with emergency alerts
- Pre-recorded messages for common scenarios

### 7.5.3 Message Templates

**Driver alert (Dagbani):**
"Emergency referral. Patient at [compound]. Go now."

**Driver alert (English):**
"Emergency referral. Patient at [compound name]. Please proceed immediately."

**Patient confirmation (Dagbani):**
"Your transport is coming. Driver [name]. Be ready."

### 7.5.4 Limitations

- Africa's Talking Voice API has limited sandbox support — production credentials needed for live calls
- TTS quality in Dagbani may require custom voice recordings
- For hackathon: demonstrate English TTS, acknowledge Dagbani as Phase 2

## 7.6 Volunteer Fallback

When no Motor-King drivers are available:
1. System checks fallback driver pool (registered volunteers)
2. If no fallback drivers: system checks personal emergency contacts
3. If no personal contacts: system notifies CHO — "No drivers available. Coordinate manually."
4. CHO can add new contacts on-the-fly via the app

## 7.7 Community Contacts

### 7.7.1 Purpose

In emergencies, the patient's personal network is often the fastest source of transport. Yoma Triage allows CHOs to register personal emergency contacts for each patient.

### 7.7.2 Flow

1. CHO adds contact: name, phone, relationship (e.g., "Husband — Mohammed, 024XXXXXXX")
2. Contact is stored with the patient record
3. During cascade dispatch, if Motor-King and fallback drivers don't respond, system contacts personal contacts
4. Personal contacts receive SMS: "EMERGENCY: [Patient] needs transport to hospital. Can you help?"

---

# PART VIII — AI Strategy

## Included Components

### 8.1 Acoustic Respiratory Screening (YAMNet/HeAR)

**What it does:** Classifies breathing sounds as normal or abnormal (Code Red) using on-device AI.

**Why it's included:**
- Peer-reviewed evidence supports AI-based respiratory sound classification (DeepBreath 2023, Malawi study 2025, Bangladesh study 2026)
- YAMNet is pre-trained, quantized, and runs at 4.13 MB — no training required
- HeAR event detectors (Google, 2025) are purpose-built for respiratory event detection
- The latest research (iMedic 2025, MaaCheck 2026) shows smartphone microphones work for this purpose

**Justification:**
- CHOs currently rely on visual observation, which misses early-stage distress
- Acoustic screening provides an objective, repeatable signal
- Runs entirely on-device — no internet required
- Advisory only — CHO makes the final decision

**Limitations:**
- YAMNet is trained on general AudioSet classes, not specifically on pediatric respiratory sounds
- HeAR event detectors are more targeted but require HuggingFace terms agreement
- Neither model has been validated on Northern Ghana pediatric populations
- Local fine-tuning is Phase 2

### 8.2 Clinical Triage (SLM — Small Language Model)

**What it does:** Provides structured clinical decision support based on symptoms and vital signs.

**Why it's included:**
- CHOs make triage decisions based on experience alone
- A quantized SLM (Phi-3 Mini 3.8B or Gemma 2B) can run on-device with 4-bit quantization
- Trained on WHO IMCI/IMPAC guidelines, the SLM can suggest triage categories without internet

**Justification:**
- Suggests, never decides — the CHO remains the decision-maker
- Based on established WHO guidelines — not novel medical reasoning
- Provides consistent triage criteria across CHPS compounds
- Can be updated with new guidelines via offline model updates

**Limitations:**
- Requires validation against clinical expert panels
- May not handle edge cases well
- Local language support (Dagbani) is limited in current SLMs
- Must be clearly framed as "decision support" not "diagnosis"

### 8.3 Referral Prioritization

**What it does:** Ranks referrals by urgency based on AI screening results and symptom severity.

**Why it's included:**
- When multiple emergencies occur simultaneously, prioritization saves lives
- Simple rule-based prioritization (not ML) is sufficient for MVP
- Can be upgraded to ML-based prioritization in Phase 2

**Implementation:**
- Code Red referrals are prioritized over Code Yellow
- Maternal hemorrhage is prioritized over respiratory distress
- Neonatal emergencies are prioritized over pediatric

### 8.4 Voice-to-Text Clinical Dictation (Phase 2)

**What it does:** Allows CHOs to verbally dictate clinical symptoms, which are converted to structured text and fed into the triage engine.

**Why it's included:**
- Most community nurses are uncomfortable with touchscreens, leading to high data entry error rates
- Voice dictation eliminates the need for typing, reducing triage latency
- Whisper-tiny (39M parameters) can be hosted on-device for complete offline processing

**Implementation (Phase 2):**
- Deploy whisper-tiny (open-source, multilingual) as a local speech recognition engine
- Local language support (Dagbani) via community-contributed training datasets
- Whisper-tiny is optimized for Android via ONNX runtime
- Requires on-device fine-tuning for local language support (community-contributed datasets)

## Excluded Components

### 8.5 Disease Diagnosis

**Why excluded:**
- Diagnosis requires clinical training, laboratory tests, and imaging
- AI-based diagnosis in LMICs without validation is dangerous
- Regulatory burden for diagnostic AI is significant
- Yoma Triage is a screening and coordination tool, not a diagnostic system

### 8.6 Drug Prescribing

**Why excluded:**
- Prescribing requires licensed clinical authority
- AI prescribing in low-resource settings without pharmacist oversight is unsafe
- Outside the scope of CHPS compound capabilities

### 8.7 Autonomous Clinical Decisions

**Why excluded:**
- Every clinical decision must be made by a licensed health worker
- AI provides data and suggestions; humans decide and act
- This is a non-negotiable safety boundary

---

# PART IX — Clinical Safety

## 9.1 What the AI Must Never Do

| Prohibition | Rationale |
|-------------|-----------|
| Diagnose a disease | Diagnosis requires clinical training and laboratory confirmation |
| Prescribe medication | Prescribing requires licensed clinical authority |
| Override a CHO's clinical decision | The CHO is the authorized decision-maker at the CHPS compound |
| Act autonomously without human confirmation | Every critical action requires human authorization |
| Provide prognosis or life expectancy estimates | Prognosis requires comprehensive clinical assessment |
| Recommend specific treatment protocols | Treatment decisions are beyond the scope of screening |

## 9.2 Clinical Responsibility Framework

```
┌─────────────────────────────────────────────────────┐
│                CLINICAL RESPONSIBILITY               │
├─────────────────────────────────────────────────────┤
│                                                     │
│  AI provides:        CHO decides:      System acts: │
│  - Screening signal  - Whether to refer - Dispatch  │
│  - Risk score        - Which hospital   - Notify    │
│  - Triage suggestion - When to refer    - Confirm   │
│  - Reasoning         - How to communicate           │
│                                                     │
│  AI role:            CHO role:         System role: │
│  Data provider       Decision-maker    Coordinator  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## 9.3 The Standardized MOEWS Triage Protocol

To ensure objective clinical triage, Yoma Triage implements a Modified Obstetric Early Warning Score (MOEWS) framework tailored for low-resource primary care settings. This system converts physiological vitals into a standardized, color-coded risk assessment.

### Scoring Criteria

| Physiological Parameter | Red Alert (3 pts) | Yellow Alert (1 pt) | Normal (0 pts) | Yellow Alert (1 pt) | Red Alert (3 pts) |
|------------------------|-------------------|--------------------|-----------------|--------------------|--------------------|
| **Systolic BP (mmHg)** | <80 | 80-90 | 90-140 | 140-150 | >150 |
| **Diastolic BP (mmHg)** | — | — | 60-90 | 90-100 | >100 |
| **Heart Rate (BPM)** | <50 or >130 | 50-60 or 110-130 | 60-110 | — | — |
| **Respiratory Rate (tpm)** | <10 or >30 | 10-14 or 24-30 | 14-24 | — | — |
| **Temperature (°C)** | <35.0 or >39.0 | 35.0-36.0 or 38.0-39.0 | 36.0-38.0 | — | — |
| **Oxygen Saturation (%)** | <90 | 90-94 | ≥95 | — | — |
| **Consciousness** | Voice/Pain/Unresponsive | — | Alert | — | — |

### Risk Score Calculation

The system calculates a cumulative triage risk score using the formula:

```
Total Score = Σ(parameter scores)
```

where each parameter score is derived from the vital value according to the table above.

### Triage Categories

- **Green (Score: 0-2)**: Standard care. The patient is stable and can be managed locally or scheduled for a routine consultation.
- **Yellow (Score: 3-4, or any single parameter scoring 1)**: Elevated risk. The CHO must inform the district referral coordinator, increase vital monitoring frequency to every 30 minutes, and initiate a soft transport reservation.
- **Red (Score: ≥5, or any single parameter scoring 3)**: Critical emergency. The system triggers immediate transport brokerage, dispatches clinical telemetry, and alerts the receiving district hospital to prepare emergency resources.

### Integration with Acoustic Screening

For respiratory distress cases, the acoustic AI screening result is combined with the MOEWS score:
- If acoustic screening returns Code Red AND MOEWS score ≥3, the referral is automatically classified as Red
- If acoustic screening returns Code Red but MOEWS score <3, the CHO reviews the AI's reasoning and decides
- If acoustic screening returns Normal but MOEWS score ≥5, the system still triggers Red classification based on vitals alone

This ensures that the AI never overrides clinical data, and clinical data never overrides the AI when both signal danger.

## 9.4 Emergency Overrides

If the system fails at any point, the CHO can always:

1. **Manually trigger a referral** — without AI screening
2. **Call drivers directly** — using personal phone
3. **Call the hospital directly** — using hospital phone number
4. **Arrange transport independently** — using community resources
5. **Document the referral on paper** — if the app is unavailable

The system never removes the CHO's ability to act independently.

## 9.5 Fallback Procedures

| Failure | Fallback |
|---------|----------|
| AI screening fails (app crash) | CHO uses visual assessment, triggers manual referral |
| Network unavailable | SMS queued for delivery when network returns; CHO can call drivers directly |
| No drivers available | CHO coordinates manually with family/neighbors |
| Hospital unreachable | CHO arranges transport to nearest available facility |
| MoMo payment fails | Transport funded by community fund or patient directly |
| App completely unavailable | Paper-based referral — system reverts to today's manual process |

## 9.6 Negative Outcomes

When a patient dies or has a poor outcome despite referral, the system must handle this with clinical sensitivity and accountability.

### 9.6.1 Outcome Recording

- Driver confirms arrival at hospital (or reports patient died en route)
- CHO records outcome when available: "Arrived alive," "Arrived deceased," "Outcome unknown"
- Outcome data is anonymized for quality improvement — no patient-identifying information is retained beyond 90 days

### 9.6.2 Clinical Review Trigger

If a patient dies:
1. System flags the referral for clinical review
2. District Health Directorate is notified (anonymized)
3. CHO is offered a debrief conversation with a clinical supervisor
4. No blame is assigned — the review is for system improvement

### 9.6.3 System Improvement Loop

Negative outcomes feed into:
- AI model retraining (if the screening was inaccurate)
- Dispatch timing optimization (if delays contributed)
- Training material updates (if CHO decision-making was a factor)
- Resource allocation (if hospital capacity was the bottleneck)

### 9.6.4 Sensitivity Protocol

- Outcome notifications are never sent to the driver or family via automated SMS
- CHO communicates outcomes to family in person
- System uses neutral language: "Outcome recorded" not "Patient died"
- Mental health support resources are available for CHOs involved in adverse outcomes

## 9.7 Escalation Paths

```
Level 1: CHO detects emergency → Yoma Triage dispatch
Level 2: No driver responds → CHO calls drivers directly
Level 3: No transport available → CHO contacts District Health Directorate
Level 4: District hospital unable to receive → CHO arranges transfer to regional hospital
Level 5: All systems fail → CHO uses personal judgment and community resources
```

At no point does the failure of Yoma Triage leave the CHO without options.

---

# PART X — Technical Architecture

## 10.1 System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOMA TRIAGE SYSTEM ARCHITECTURE                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────┐                                        │
│  │   MOBILE APP         │                                        │
│  │   (Flutter)          │                                        │
│  │                      │                                        │
│  │  ┌──────────────┐   │                                        │
│  │  │ Audio Record  │   │                                        │
│  │  │ (16kHz, PCM)  │   │                                        │
│  │  └──────┬───────┘   │                                        │
│  │         ↓           │                                        │
│  │  ┌──────────────┐   │                                        │
│  │  │ TFLite Engine │   │                                        │
│  │  │ (YAMNet/HeAR) │   │                                        │
│  │  └──────┬───────┘   │                                        │
│  │         ↓           │                                        │
│  │  ┌──────────────┐   │                                        │
│  │  │ Result Screen │   │                                        │
│  │  │ (GREEN / RED) │   │                                        │
│  │  └──────┬───────┘   │                                        │
│  │         ↓           │                                        │
│  │  ┌──────────────┐   │                                        │
│  │  │ SMS Trigger   │───┼──→ Africa's Talking SMS API           │
│  │  └──────────────┘   │                                        │
│  └─────────────────────┘                                        │
│                                                                  │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │   BACKEND            │    │   AFRICA'S TALKING   │             │
│  │   (FastAPI)          │    │   GATEWAY            │             │
│  │                      │    │                      │             │
│  │  ┌──────────────┐   │    │  ┌──────────────┐   │             │
│  │  │ Dispatch      │   │←──│  │ SMS API       │   │             │
│  │  │ Orchestrator  │   │    │  └──────────────┘   │             │
│  │  └──────┬───────┘   │    │  ┌──────────────┐   │             │
│  │         ↓           │    │  │ Voice API     │   │             │
│  │  ┌──────────────┐   │    │  └──────────────┘   │             │
│  │  │ Driver Pool   │   │    │  ┌──────────────┐   │             │
│  │  │ Manager       │   │    │  │ USSD Gateway  │   │             │
│  │  └──────┬───────┘   │    │  └──────────────┘   │             │
│  │         ↓           │    │  ┌──────────────┐   │             │
│  │  ┌──────────────┐   │    │  │ Payments API  │   │             │
│  │  │ Hospital      │   │    │  │ (MoMo)        │   │             │
│  │  │ Notifier      │   │    │  └──────────────┘   │             │
│  │  └──────────────┘   │    └─────────────────────┘             │
│  └─────────────────────┘                                        │
│                                                                  │
│  ┌─────────────────────┐                                        │
│  │   DATABASE           │                                        │
│  │   (PostgreSQL)       │                                        │
│  │                      │                                        │
│  │  Referral            │                                        │
│  │  Driver              │                                        │
│  │  Facility            │                                        │
│  │  Patient             │                                        │
│  │  Journey             │                                        │
│  │  Notification        │                                        │
│  │  Wallet              │                                        │
│  │  Audit               │                                        │
│  └─────────────────────┘                                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 10.2 Mobile App (Flutter)

**Dependencies:**
```yaml
dependencies:
  tflite_flutter: ^0.12.1    # TFLite inference engine
  record: ^5.x               # Audio recording (PCM/WAV at 16kHz)
  http: ^1.1.0               # API calls to backend
  sqflite: ^2.3.0            # Local SQLite for offline referral queue
  connectivity_plus: ^5.0.0  # Network status detection
```

**Key components:**
- `audio_recorder.dart` — Handles 16kHz PCM recording via `record` package
- `tflite_classifier.dart` — Loads and runs YAMNet/HeAR TFLite model
- `result_screen.dart` — Displays GREEN/RED result with reasoning
- `referral_trigger.dart` — Sends referral trigger to backend via HTTP; backend handles all Africa's Talking integrations (SMS, Voice, USSD)
- `offline_queue.dart` — Queues referrals when network unavailable

**Architecture decision: Backend-mediated dispatch.** The mobile app never calls Africa's Talking directly. All SMS, Voice, and USSD interactions are handled by the backend. This centralizes state management, ensures the dispatch cascade is tracked in the database, and allows offline queueing to work correctly.

**Offline behavior:**
- AI inference runs entirely on-device (no network required)
- Referral triggers are queued locally when offline (stored in SQLite)
- When network returns, queued referrals are sent to backend
- Backend processes dispatch and sends SMS/Voice via Africa's Talking
- Driver responses arrive via SMS (works on 2G) and are relayed to backend via USSD callback
- If backend is unreachable, CHO falls back to manual phone calls

## 10.3 Backend (FastAPI)

**Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `POST /api/v1/referral` | POST | Receive referral trigger from mobile app |
| `GET /api/v1/dispatch/{id}` | GET | Get dispatch status |
| `POST /api/v1/ussd/callback` | POST | Handle USSD responses from drivers |
| `POST /api/v1/voice/callback` | POST | Handle voice call events |
| `POST /api/v1/sms/inbound` | POST | Handle inbound SMS (hospital confirmation) |
| `GET /api/v1/driver/{id}/status` | GET | Get driver availability |
| `POST /api/v1/driver/{id}/availability` | POST | Update driver availability |
| `GET /api/v1/compound/{id}/drivers` | GET | List drivers for a CHPS compound |

**Key services:**
- `dispatch_orchestrator.py` — Manages cascade dispatch sequence
- `driver_pool_manager.py` — Manages driver registration and availability
- `hospital_notifier.py` — Sends pre-arrival notifications
- `sms_service.py` — Africa's Talking SMS integration
- `voice_service.py` — Africa's Talking Voice integration
- `ussd_handler.py` — Africa's Talking USSD callback handler

## 10.4 Africa's Talking Integration

| API | Use Case | Sandbox? |
|-----|----------|----------|
| SMS | Dispatch alerts, patient confirmation, hospital notification | Yes (free) |
| Voice | Automated calls to drivers when SMS not responded to | Limited |
| USSD | Driver accept/decline, hospital confirmation | Yes (free) |
| Payments | MoMo escrow (production only) | No (simulated for hackathon) |

**Important:** The USSD code (`*XXX#`) must be provisioned before the hackathon demo. For sandbox testing, use Africa's Talking's built-in USSD simulator. For a live demo, contact Africa's Talking to request a temporary test USSD code — they historically provide whitelisted tester accounts for hackathon participants.

**Sandbox setup:**
1. Sign up at `https://account.africastalking.com/apps/sandbox`
2. Get sandbox API key and username
3. Test with sandbox phone numbers
4. Use simulator at `https://simulator.africastalking.com:1517/`

**Production setup:**
1. Register for production account
2. Provision shared USSD code (~USD 100 setup + GHS 900/month)
3. Provision voice number (GHS 500 + 15% VAT)
4. Load SMS credits (GHS 5-20 for hackathon demo)

## 10.5 Low-Bandwidth Data Compression Protocol

To transmit detailed clinical vitals over standard 2G GSM cellular SMS channels, Yoma Triage implements a highly efficient binary compression format similar to the DHIS2 Android SMS protocol. This system packs variables into ultra-dense, Base64-encoded strings.

### Payload Structure (140-octet SMS)

A standard 140-octet SMS payload (1,120 bits) is allocated as follows:

**Header Core (112 bits):**
- Application Identifier (8 bits): Identifies the Yoma Triage packet format
- Schema Version (8 bits): Ensures compatibility with server-side parsers
- CRC-16 Payload Checksum (16 bits): Validates data integrity
- Hashed Facility Identifier (32 bits): Identifies the initiating CHPS compound
- Hashed User Token (32 bits): Identifies the clinical officer initiating the transfer
- Timestamp Delta (16 bits): Minutes since last sync epoch

**Clinical Registry Vector (320 bits):**
- Patient Age Category (8 bits): Encodes age range and demographic token
- Parity & Gravidity (16 bits): Essential obstetric history
- Systolic & Diastolic BP (16 bits): Direct millibar representation
- Heart Rate & Respiratory Rate (16 bits): Physical clinical vital counts
- Temperature (16 bits): Quantized with a scale multiplier
- Saturation and AVPU status (16 bits): High-precision vital metrics
- Primary Presentation Code (32 bits): High-density diagnostic categorical array
- Pre-referral Treatment Array (72 bits): Bitfield mapping administered medications
- MOEWS Score (8 bits): 0-15 triage risk score
- Gestational Age (8 bits): Weeks since LMP (0-42 weeks)
- Fundal Height (8 bits): Centimeters (0-40 cm)
- Fetal Heart Rate (16 bits): Beats per minute (0-200 bpm)
- Blood Group (8 bits): ABO + Rh factor encoding
- Allergy Flags (16 bits): Common medication allergy bitfield
- Comorbidity Flags (16 bits): HIV, malaria, anaemia, diabetes bitfield
- Last Menstrual Period Delta (16 bits): Days since LMP
- Gravidity (8 bits): Total pregnancies (0-15)
- Parity (8 bits): Live births (0-15)
- Previous C-Section (4 bits): Yes/no + indication
- Active Labor (4 bits): Yes/no + cervical dilation stage

**Transit Core Registry (128 bits):**
- Requested Transport Type (8 bits): Matches triage risk level with vehicle types
- Target Referral Facility Code (32 bits): Identifies the destination hospital
- Nearest Facility Code (32 bits): Backup facility if primary unavailable
- GPS Latitude (32 bits): Fixed-point coordinate (5 decimal precision)
- GPS Longitude (32 bits): Fixed-point coordinate (5 decimal precision)
- Security Token (24 bits): Validates authorization and integrity

**Padding (272 bits):** Reserved for future schema extensions and alignment

### Compression Result

The resulting binary payload is serialized, CRC-16 checked, and converted to base64, generating a secure alphanumeric text string for SMS transmission:

```
UkxBSS0yNTZ7ImFnZSI6MjgsImJwIjoxMjAvODAsImhyIjoxMTAsInRlbXAiOjM4LjIsInNwb2MiOjk4LCJtb2V3cyI6NH0=
```

This compressed string is easily transmitted across standard, low-signal 2G cellular connections, bypassing network congestion and avoiding high mobile data costs.

### Synchronization and Fallback Architecture

The mobile application uses a hybrid synchronization engine that monitors network signal quality and automatically selects the most efficient transmission path:

```
[New Emergency Triage Submission]
                 |
                 v
       [Check Connectivity]
        |-- Active 3G/4G/Wi-Fi Network
        |     -- Transmit standard encrypted JSON payload via secure HTTPS APIs
        |
        -- Data Offline (No internet)
              |
              v
  [Serialize to Local SQLite / Room DB] (Saves clinical record locally)
              |
              v
  [Compile Data into Compressed Base64 String]
              |
              v
  [Dispatch over GSM SMS Telemetry Gateway]
        |-- Success (Remote server receives and decodes Base64 SMS packet)
        -- Network Drop (No cellular signal)
              |
              v
  [Queue in Local Outbox] (App retries automatically when GSM signal is restored)
```

## 10.6 Database (PostgreSQL on Supabase)

**Why Supabase:**
- Free tier with 500MB storage
- PostgreSQL with real-time subscriptions
- Built-in auth and row-level security
- REST API auto-generated from schema
- Easy to migrate to self-hosted later

**Schema:** See Part XI (Data Architecture)

## 10.7 Authentication & Security

**Compliance:** Yoma Triage handles patient data and must comply with Ghana's Data Protection Act, 2012 (Act 843). All patient data is processed with minimal collection principles, stored with encryption, and retained only as long as necessary for the referral to succeed.

**Authentication:**
- CHOs authenticate via phone number + OTP (SMS)
- Drivers authenticate via phone number + PIN
- Hospital staff authenticate via email + password
- API keys for service-to-service communication

**Security:**
- All data encrypted at rest (PostgreSQL)
- All API calls over HTTPS
- No patient data stored on mobile device beyond current session
- Audio recordings deleted after processing (never stored)
- Audit trail for all system actions

---

# PART XI — Data Architecture

## 11.1 Entity Relationship Diagram

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  chps_compound   │     │  driver          │     │  emergency_contact│
├──────────────────┤     ├──────────────────┤     ├──────────────────┤
│ id (PK)          │     │ id (PK)          │     │ id (PK)          │
│ name             │     │ name             │     │ patient_name     │
│ zone             │     │ phone (unique)   │     │ patient_phone    │
│ latitude         │     │ vehicle_type     │     │ contact_name     │
│ longitude        │     │ vehicle_desc     │     │ contact_phone    │
│ cho_phone        │     │ chps_compound_id │     │ relationship     │
│                  │     │ is_motor_king    │     │ chps_compound_id │
│                  │     │ is_active        │     │                  │
└────────┬─────────┘     └────────┬─────────┘     └────────┬─────────┘
         │                        │                        │
         │    ┌──────────────────┐│    ┌──────────────────┐│
         │    │  referral        ││    │  facility        ││
         │    ├──────────────────┤│    ├──────────────────┤│
         │    │ id (PK)          ││    │ id (PK)          ││
         ├───→│ chps_compound_id ││    │ name             ││
         │    │ patient_name     ││    │ type             ││
         │    │ patient_age      ││    │ phone            ││
         │    │ patient_gender   │    │ district         ││
         │    │ emergency_type   │    │ has_maternity     ││
         │    │ severity         │    │ has_icu           ││
         │    │ ai_screen_result │    │ blood_bank_status ││
         │    │ ai_confidence    │    └──────────────────┘│
         │    │ status           │                         │
         │    │ outcome          │                         │
         │    │ initiated_at     │                         │
         │    └────────┬─────────┘                         │
         │             │                                   │
         │    ┌────────▼─────────┐                         │
         │    │  dispatch        │                         │
         │    ├──────────────────┤                         │
         │    │ id (PK)          │                         │
         │    │ referral_id      │                         │
         │    │ driver_id        │                         │
         │    │ status           │                         │
         │    │ initiated_at     │                         │
         │    │ driver_assigned  │                         │
         │    │ completed_at     │                         │
         │    └────────┬─────────┘                         │
         │             │                                   │
         │    ┌────────▼─────────┐                         │
         │    │  dispatch_log    │                         │
         │    ├──────────────────┤                         │
         │    │ id (PK)          │                         │
         │    │ dispatch_id      │                         │
         │    │ action           │                         │
         │    │ target_phone     │                         │
         │    │ target_role      │                         │
         │    │ response         │                         │
         │    │ created_at       │                         │
         │    └──────────────────┘                         │
         │                                                 │
         │    ┌──────────────────┐                         │
         │    │  wallet          │                         │
         │    ├──────────────────┤                         │
         │    │ id (PK)          │                         │
         │    │ referral_id      │                         │
         │    │ amount           │                         │
         │    │ currency         │                         │
         │    │ source           │                         │
         │    │ status           │                         │
         │    │ created_at       │                         │
         │    └──────────────────┘                         │
         │                                                 │
         │    ┌──────────────────┐                         │
         │    │  audit_log       │                         │
         │    ├──────────────────┤                         │
         │    │ id (PK)          │                         │
         │    │ entity_type      │                         │
         │    │ entity_id        │                         │
         │    │ action           │                         │
         │    │ actor_id         │                         │
         │    │ timestamp        │                         │
         │    │ metadata (JSON)  │                         │
         │    └──────────────────┘                         │
```

## 11.2 What Data Is Stored

To comply with Ghana's Data Protection Act (Act 843) and protect patient privacy, the platform separates essential operational tracking data from sensitive personal identification markers:

| Data | Purpose | Retention | Security |
|------|---------|-----------|----------|
| Patient hash (SHA-256) | Referral identification | 90 days, then anonymized | One-way hash, no reverse lookup |
| Patient age category | Triage context | 90 days, then anonymized | Encrypted at rest |
| Emergency type | Referral routing | Permanent (anonymized) | Encrypted at rest |
| MOEWS score | Clinical triage | Permanent (anonymized) | Encrypted at rest |
| Clinical telemetry payload | Pre-arrival hospital notification | 90 days, then deleted | AES-256-GCM encrypted |
| Pre-referral interventions | Clinical history | 90 days, then deleted | Encrypted at rest |
| Driver phone numbers | Dispatch coordination | Permanent (driver-owned) | Encrypted at rest |
| Facility information | Referral routing | Permanent | Encrypted at rest |
| Transit timestamps | Operational monitoring | Permanent (anonymized) | Encrypted at rest |
| Route coordinates | Active referral tracking only | Deleted after referral completes | Encrypted in transit |
| Wallet transactions | Financial accountability | 7 years (regulatory) | AES-256 encrypted |
| Audit trail | Security and compliance | 7 years (regulatory) | Tamper-proof, encrypted |

## 11.3 What Data Is Never Stored

| Data | Rationale |
|------|-----------|
| Patient names and direct identification markers | Protects anonymity — hashed tokens used instead |
| Raw voice input recordings | Processed on-device, never uploaded |
| Driver location history outside active referrals | Privacy protection |
| Plaintext NHIS registration numbers | Encrypted at source |
| Plaintext user PIN codes and authentication passwords | Never stored in any form |
| Detailed medical history unrelated to active emergency | Minimal data collection principle |
| Audio recordings from acoustic screening | Processed on-device, immediately discarded |
| GPS location of patients | Not required — CHPS compound location is sufficient |

## 11.4 On-Device Security

The local Room/SQLite database is secured using SQLCipher, applying AES-256 symmetric encryption to protect all stored records. The decryption keys are managed via the Android Keystore system and are bound to biometric or clinical PIN credentials.

> **Implementation status (2026-07-28):** The shipping Flutter outbox uses **plaintext SQLite / SharedPreferences**, not SQLCipher. Treat the paragraph above as a **pilot hardening target**, not as shipped behavior.

Network security protocols: Active cellular data transfers use secure HTTPS channels with TLS 1.3 encryption and strict certificate pinning. SMS telemetry strings are encrypted locally using AES-256-GCM prior to Base64 encoding, ensuring data remains secure during transit over carrier networks.

> **Implementation status (2026-07-28):** HTTPS depends on deployment TLS. **Certificate pinning and AES-256-GCM SMS are not implemented.** Hospital/driver SMS are plaintext. Protect APIs with `API_KEY` / `AT_WEBHOOK_SECRET` (CHO OTP still deferred).


---

# PART XII — User Journeys

## Journey 1: Child with Respiratory Distress

```
08:00 — Mother brings 2-year-old Kwame to CHPS compound
        He's breathing fast. Mother is worried.

08:05 — CHO Abiba observes Kwame
        Chest indrawing visible. Breathing rate elevated.
        Abiba opens Yoma Triage app → selects "Screen Breathing"

08:06 — Abiba holds phone near Kwame's chest
        60-second recording begins
        App displays: "Recording... 30 seconds remaining"

08:07 — Recording complete
        AI analyzes: "Code Red — Wheezing detected. Confidence: 82%"
        Abiba reviews reasoning: "Abnormal breathing pattern detected"

08:08 — Abiba confirms referral
        App sends SMS to backend
        Backend triggers cascade dispatch

08:08 — SMS sent to Ibrahim (Motor-King driver)
        Ibrahim receives: "EMERGENCY: Patient at Tamale South CHPS. Reply via *XXX#"

08:09 — Ibrahim dials *XXX#
        Selects "1. Accept — I'm on my way"
        System confirms: "Driver Ibrahim accepted. ETA: 12 minutes."

08:09 — Abiba receives SMS: "Ibrahim accepted. ETA: 12 minutes."
        Abiba tells mother: "Transport is coming. Be ready."

08:09 — System sends SMS to Tamale District Hospital:
        "Emergency referral from Tamale South CHPS.
         Patient: Kwame, 2M.
         Condition: Respiratory distress.
         Severity: Code Red.
         Driver: Ibrahim.
         ETA: 12 minutes."

08:21 — Ibrahim arrives at CHPS compound
        Kwame loaded onto Motor-King
        Abiba gives Ibrahim the patient card

08:35 — Ibrahim arrives at hospital
        Ibrahim dials *XXX# → "Confirm Arrival"
        System sends confirmation to Abiba

08:35 — Hospital receives confirmation
        Receiving nurse was notified at 08:09
        Nurse has prepared oxygen and nebulizer
        Kwame receives immediate care

TOTAL TIME: 35 minutes (detection to hospital arrival)
COMPARED TO: 2-4 hours (current manual process)
```

## Journey 2: No Available Driver

```
14:00 — CHO Fatima detects postpartum hemorrhage in Amina
        Fatima triggers emergency referral via Yoma Triage

14:00 — SMS sent to all Motor-King drivers in zone
        Driver 1: On a trip — no response
        Driver 2: Phone off — no response

14:01:30 — Voice call to drivers
        Driver 1: Voicemail
        Driver 2: No answer

14:03 — System proceeds to fallback tier
        SMS sent to volunteer drivers
        Volunteer driver Abdul: "I can come in 20 minutes"

14:04 — Fatima receives: "Abdul (volunteer, motorcycle) accepted. ETA: 20 minutes."
        Fatima assesses: 20 minutes is too long for hemorrhage

14:04 — Fatima adds Amina's husband as personal contact
        System sends SMS to husband: "EMERGENCY: Your wife needs transport to hospital NOW."

14:05 — Husband replies: "I'm on my way. 5 minutes."

14:10 — Husband arrives on motorcycle
        Amina transported to hospital

TOTAL TIME: 10 minutes (detection to transport)
FALLBACK SUCCESS: Personal contact provided faster transport than registered drivers
```

## Journey 3: Network Outage

```
09:00 — Network outage in Tamale area
        2G and 3G unavailable

09:15 — CHO Abiba detects respiratory distress
        Opens Yoma Triage app
        App displays: "Network unavailable. Referral will be sent when connection returns."

09:16 — Abiba triggers referral
        App queues referral locally
        App displays: "Referral queued. Will send when network returns."

09:16 — Abiba uses personal phone to call Ibrahim directly
        Ibrahim answers
        Abiba arranges transport manually

09:30 — Ibrahim arrives, transports patient

10:00 — Network returns
        App sends queued referral to backend
        Backend processes referral (now historical)
        Dispatch log updated: "Manually coordinated by CHO during network outage"

LESSON: The system degrades gracefully. CHO can always act manually.
```

## Journey 4: Hospital Rejects Referral

```
10:00 — CHO Fatima triggers referral for neonatal sepsis
        Driver accepted, en route to Tamale Teaching Hospital

10:15 — Hospital receives pre-arrival notification
        Hospital nurse checks ICU capacity
        ICU full — no beds available

10:16 — Hospital replies: "DIVERT — Send to Regional Hospital. Reason: ICU full."

10:16 — System notifies driver: "Hospital unable to receive. Diverting to Regional Hospital."
        New ETA: 25 minutes (further distance)

10:16 — System notifies Fatima: "Hospital diverting patient to Regional Hospital."

10:40 — Patient arrives at Regional Hospital
        Regional Hospital was automatically notified
        Bed available — patient admitted

LESSON: Diversion protocol ensures patient reaches a facility that can treat them.
```

## Journey 5: Family Refuses Transport

```
11:00 — CHO Abiba screens child with respiratory distress
        Code Red result
        Abiba explains to mother: "Your child needs hospital care."

11:02 — Mother refuses: "My child is just coughing. I'll go home and give herbs."
        Abiba explains risks in Dagbani
        Mother still refuses

11:05 — Abiba documents refusal in Yoma Triage
        System logs: "Referral declined by caregiver. Reason: caregiver preference."
        Abiba provides health education materials
        Abiba asks mother to return if child worsens

11:05 — No dispatch triggered (no referral confirmed)

14:00 — Mother returns with child in severe distress
        Child now in respiratory failure
        Abiba triggers emergency referral
        Driver dispatched immediately
        Child transported to hospital

LESSON: Yoma Triage documents refusals but never forces referrals. The CHO manages the relationship.
```

---

# PART XIII — Pilot Design

## 13.1 Pilot Location

**Districts:** Kassena-Nankana East Municipal (Upper East Region) and Savelugu Municipal (Northern Region), Ghana

**Rationale:**
- Established CHPS networks with documented emergency referral challenges
- Kassena-Nankana East: documented in research on neonatal mortality and transport outcomes
- Savelugu Municipal: documented in research on health worker perspectives on malaria referral
- Severe geographic and environmental conditions that test the platform's resilience
- KOICA CHPS+ project presence — existing Motor-King infrastructure
- Mix of urban and rural catchment areas

## 13.2 Pilot Scope

| Parameter | Value |
|-----------|-------|
| CHPS compounds | 50 (functional compounds across both districts) |
| Sub-district health centers | 10 |
| District/regional hospitals | 3-5 |
| Drivers registered | 150 (Motor-King operators and community transport drivers) |
| Duration | 6 months |
| Users | 50 CHOs, 10-15 midwives |
| Patients served (est.) | 5,000-10,000 |

## 13.3 Success Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| Triage decision latency (arrival to referral decision) | 45 min | <10 min | App timestamp |
| Transport matching latency (referral to driver acceptance) | 90 min | <5 min | Dispatch log |
| Systemic transit latency (referral confirmation to hospital arrival) | 2-4 hours | <60 min (40% reduction) | Arrival confirmation |
| Referral form completeness | <30% | >95% | Digital referral record vs. paper |
| Payment processing speed | 14 days | <10 minutes | Wallet transaction log |
| Hospital pre-notification rate | ~5% | >90% | SMS log |
| CHO satisfaction score | N/A | >4.0/5.0 | Monthly survey |
| Driver response rate | N/A | >70% | Dispatch log |
| Time from detection to hospital arrival | 2-4 hours | <45 min | Arrival confirmation |
| Referral completion rate | ~40% | >80% | Dispatch status |

## 13.4 Training Plan

**Phase 1: Master Training (Week 1)**
- Midwifery supervisors and district coordinators complete standardized simulation drills on edge-AI triage, MOEWS parameters, and USSD mechanics
- Train-the-trainer model: each supervisor trains 5-10 CHOs

**Phase 2: On-Site Simulation Drills (Week 2-3)**
- CHOs and frontline nurses complete hands-on simulation training on-site
- Focus on tablet usage, vital inputting, and error recovery under high-stress scenarios
- Register drivers in the system
- Register hospital contacts
- Set up community emergency fund (see below)

**Community Emergency Fund Setup:**
1. Establish MoMo merchant account (requires business registration)
2. Seed fund with GHS 5,000-10,000 per CHPS zone (from NGO grant or district health budget)
3. Set minimum balance alert at GHS 1,000
4. Replenishment protocol: CHO reports low balance to district coordinator
5. Fund is managed by the District Health Directorate, not individual CHOs
6. Each transport deduction is logged and auditable
7. Monthly reconciliation with MoMo statement

**Phase 3: Pilot Launch (Week 4)**
- CHOs use Yoma Triage for all referrals
- Weekly check-ins with CHOs
- Daily monitoring of dispatch metrics

**Phase 4: Remote Refresher Training (Month 2-6)**
- Continuous remote follow-up training delivered via interactive IVR calls using Viamo and Agoo platforms
- This approach lowers training costs and fits seamlessly into standard clinic workflows
- UNICEF has demonstrated this model with 10 million+ engagements via the Agoo 5100 platform
- Monthly feedback sessions
- Adjust cascade timing based on response data
- Add drivers based on availability patterns
- Refine AI thresholds based on clinical outcomes

## 13.5 Evaluation Methodology

**Quantitative:**
- Referral time metrics (before/after comparison)
- Dispatch success rates
- System uptime and reliability
- AI screening accuracy (compared to clinical outcomes)

**Qualitative:**
- CHO interviews (monthly)
- Driver focus groups (quarterly)
- Hospital staff feedback (monthly)
- Caregiver satisfaction surveys (sample)

**Independent evaluation:**
- Partner with University for Development Studies (UDS) for independent evaluation
- Publish findings in peer-reviewed journal

---

# PART XIV — Business & Sustainability

## 14.1 Operating Costs (Per CHPS Compound, Monthly)

| Cost Item | Monthly (GHS) | Monthly (USD) |
|-----------|---------------|---------------|
| Africa's Talking SMS (est. 200 messages) | 10.60 | 0.85 |
| Africa's Talking Voice (est. 50 calls) | 15.00 | 1.20 |
| Africa's Talking USSD (shared code) | 37.50 | 3.00 |
| Server hosting (Railway/Render) | 15.00 | 1.20 |
| Supabase database | 0 (free tier) | 0 |
| **Total per compound** | **78.10** | **6.25** |

## 14.2 Revenue Model

| Revenue Stream | Price | Year 1 | Year 3 | Year 5 |
|----------------|-------|--------|--------|--------|
| CHPS Compound SaaS | $30/compound/month | $18K | $360K | $1.8M |
| Hospital Dashboard | $150/hospital/month | $12K | $120K | $380K |
| Regional Analytics | $15K/region/year | — | $45K | $380K |
| **Total** | | **$30K** | **$525K** | **$2.56M** |

## 14.3 Partnership Strategy

**Ghana Health Service:**
- Integration with CHPS implementation guidelines and Networks of Practice operational guidelines
- Data sharing agreement for DHIS2
- Procurement through district health directorates
- Alignment with National Digital Health Strategy 2023-2027

**UNICEF Innovation Office:**
- Initial pilot funding and hardware procurement
- Integration of IVR training modules
- Evaluation and evidence generation

**MTN Ghana:**
- MoMo API access for escrow and driver payments
- Zero-rated USSD shortcodes and subsidized SMS packages
- Co-marketing opportunity

**Viamo/Agoo:**
- IVR-based remote training and refresher courses
- Voice-based health education in local languages
- UNICEF partnership for 10 million+ engagement platform

**National Health Insurance Authority (NHIA):**
- Integrate emergency transit costs into NHIS reimbursement framework
- Allow clinics to claim transit fees from NHIS to replenish local emergency wallets
- Align with Free Maternal Care Policy exemptions

**Livelihood Empowerment Against Poverty (LEAP):**
- Integrate social registries for poorest households
- Ensure automated out-of-pocket exemptions during emergency transits
- Direct cash transfers and health insurance waivers for vulnerable families

## 14.4 Long-Term Sustainability

**Year 1-2:** Grant-funded (UNICEF, USAID, KOICA)
**Year 3:** Transition to SaaS model with GHS procurement + NHIS transit cost reimbursement
**Year 4-5:** Self-sustaining through subscription revenue + NHIS claims
**Year 5+:** Expansion to other West African countries (Nigeria, Kenya) + Global Digital Health Good certification

---

# PART XV — Risks

## 15.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Network outage prevents dispatch | High | High | Offline-first design; SMS works on 2G; manual fallback |
| AI model produces false negatives | Medium | High | Confidence thresholds; CHO confirmation required; clinical validation |
| Africa's Talking API downtime | Low | High | Dual-SIM fallback; manual calling as backup |
| Device failure (phone breaks) | Medium | Medium | Shared devices at CHPS compounds; paper-based fallback |
| TFLite model too slow on low-end phones | Medium | Medium | Test on target devices; use quantized models; fallback to rule-based |

## 15.2 Clinical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AI screening misses critical case | Medium | High | AI is advisory only; CHO makes decision; continuous monitoring |
| CHO over-relies on AI | Medium | High | Training emphasizes AI as decision support; regular refresher training |
| Wrong patient information entered | High | Low | Minimal data collection; name only (no diagnosis) |
| Hospital not prepared on arrival | Medium | Medium | Pre-arrival notification; confirmation protocol |

## 15.3 Operational Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Drivers don't respond to alerts | High | High | Cascading dispatch; personal contacts; manual fallback; community fund incentive |
| CHOs don't adopt the system | Medium | High | Co-design with CHOs; simple UX; demonstrate time savings |
| Staff turnover (trained CHOs leave) | High | Medium | Self-paced onboarding modules; train-the-trainer model |
| Community fund depleted | Medium | Medium | Monitoring dashboard; automatic alerts at low balance; replenishment protocol |

## 15.4 Political Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| GHS does not approve digital health tools | Low | High | Align with existing CHPS guidelines; engage GHS advisory committees early |
| Government budget cuts to CHPS | Medium | High | Diversify funding: NGO grants, SaaS revenue, international donors |
| Competing national platform adopted | Medium | Medium | Design for interoperability; DHIS2 integration; open standards |

## 15.5 Financial Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Grant funding ends before sustainability | Medium | High | Accelerate SaaS revenue; target GHS procurement budget |
| Exchange rate volatility (GHS/USD) | High | Medium | Price in GHS locally; hedge with USD contracts |
| Lower-than-expected adoption | Medium | High | Start with willing compounds; demonstrate evidence; expand based on results |

---

# PART XVI — Roadmap

## Phase 1: Hackathon MVP (This Week)

**Deliverables:**
- Flutter app with acoustic screening (YAMNet) AND clinical triage (SLM — quantized Phi-3 Mini or Gemma 2B)
- FastAPI backend with dispatch cascade
- Africa's Talking SMS + USSD integration
- Demo data (drivers, compounds, hospitals)
- Live demo script

**Success criteria:**
- End-to-end flow works: screening → triage → dispatch → driver accept → confirmation
- Both AI components run on-device (YAMNet for breathing, SLM for triage suggestions)
- Judges understand the problem and solution
- Technical architecture is defensible

## Phase 2: Pilot (Months 1-6)

**Deliverables:**
- 50 CHPS compounds in Kassena-Nankana East and Savelugu Municipalities
- 150 registered drivers (Motor-King operators)
- 3-5 hospital integrations (NHIA-connected facilities)
- Community emergency fund established (NHIS transit cost reimbursement + LEAP exemptions)
- Train-the-trainer model delivered + Viamo IVR remote refresher courses

**Success criteria:**
- Referral time reduced by 50%
- Referral completion rate >80%
- CHO satisfaction >4.0/5.0
- Evidence published

## Phase 3: District Rollout (Months 7-12)

**Deliverables:**
- Expand to 300 CHPS compounds across 5 districts
- SLM fine-tuned on Ghana clinical data (improved accuracy)
- DHIS2 data sync
- Hospital Dashboard with LHIMS integration
- GHS procurement contract

**Hospital Dashboard:**
- Web-based dashboard for referral coordination centers at district hospitals
- LHIMS (Local Health Information Management System) integration for digital record creation
- ICU, blood bank, and operating room status tracking
- Bed availability, surgical scheduling, and stockout reporting
- Triage confirmation via dashboard (replaces SMS confirmation)
- Digital referral record creation with auto-populated patient hash and vitals

**Success criteria:**
- District-level adoption by Health Directorate
- Demonstrated reduction in maternal/child mortality
- Sustainable revenue model

## Phase 4: Regional Rollout (Months 13-24)

**Deliverables:**
- 2,500 CHPS compounds across Northern Region
- Regional analytics dashboard
- Multi-district coordination
- ISO 27001 preparation

**Success criteria:**
- Regional Health Directorate adoption
- Replicable model for other regions
- Series A funding secured

## Phase 5: National Scale (Years 3-5)

**Deliverables:**
- 6,000+ CHPS compounds nationwide
- Integration with National Ambulance Service
- Expansion to Nigeria and Kenya
- HIPAA compliance

**Success criteria:**
- National GHS adoption
- Measurable reduction in maternal/child mortality
- Self-sustaining revenue model
- Regional expansion underway

---

# Appendices

## Appendix A: Africa's Talking API Quick Reference

| Service | Endpoint | Method |
|---------|----------|--------|
| SMS | `https://api.africastalking.com/version1/messaging` | POST |
| Voice | `https://voice.africastalking.com/call` | POST |
| USSD | Callback-based (your server receives POST, returns text) | POST |
| Payments | `https://payments.africastalking.com` | POST |

## Appendix B: Flutter Dependencies

```yaml
dependencies:
  tflite_flutter: ^0.12.1
  record: ^5.x
  http: ^1.1.0
  shared_preferences: ^2.2.0
  connectivity_plus: ^5.0.0
```

## Appendix C: Key Research Citations

1. Thaddeus & Maine (1994). "Too far to walk: Maternal mortality in context."
2. Heitmann et al. (2023). "DeepBreath — automated detection of respiratory pathology." npj Digital Medicine.
3. Malawi Digital Auscultation Study (2025). Journal of Global Health.
4. Bangladesh AI Lung Sounds (2026). PLOS One.
5. Google HeAR (2025). Health AI Developer Foundations.
6. MOTECH Ghana (2010). Mobile Technology for Community Health.
7. SERC Model (2012-2015). Upper East Region Emergency Referral.
8. PLOS One (2026). Northern Ghana CHPS zone staffing study.
9. KNUST National Health Access Platform (2025).
10. UNICEF/KOICA CHPS+ Project Reports (2025).

---

*Document prepared for UNICEF StartUp Lab Hackathon, July 2026.*
*Yoma Triage — Bridging the Detection-to-Care Gap in Primary Healthcare.*
