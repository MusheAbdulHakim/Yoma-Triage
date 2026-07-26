# **Yoma Triage: Intelligent Clinical Triage, Edge Computing Decision Support, and Resilient Multi-Channel Emergency Referral Orchestration Platform for Northern Ghana**

## **Part I — Executive Summary**

### **The Problem**

Maternal and neonatal mortality remains one of the most critical healthcare challenges in Sub-Saharan Africa, particularly within the geographically remote and economically constrained Savannah and Sahelian belts of Northern Ghana1. The maternal mortality ratio in Ghana persists at approximately 310 deaths per 100,000 live births, while specialized tertiary clinical audits document numbers as high as 801 deaths per 100,000 live births during periods of acute regional stress2. These outcomes deviate from the United Nations Sustainable Development Goal Target 3.1, which mandates a global reduction to fewer than 70 maternal deaths per 100,000 live births by 20302.  
The primary drivers of these preventable deaths are clinical complications such as postpartum hemorrhage, severe pre-eclampsia/eclampsia, and neonatal sepsis2. These conditions are highly treatable if managed within the critical therapeutic window2. However, the healthcare system in Northern Ghana is severely constrained by the physical and logistical barriers outlined in the traditional "Three Delays" model of maternal mortality7.  
While the First Delay (deciding to seek care) has been partially mitigated by public health education and the fee-exemption incentives of the Free Maternal Care Policy, the Second Delay (reaching a competent referral facility) remains an unresolved bottleneck7. Rural primary care relies on over 6,500 Community-based Health Planning and Services (CHPS) compounds12. These facilities are staffed by Community Health Officers (CHOs) who operate in clinical isolation without on-site specialist support, reliable diagnostic tools, or coordinated emergency transport3.

### **The Opportunity**

This clinical crisis exists alongside a rapidly growing digital infrastructure. Ghana has achieved mobile penetration rates exceeding 132% and smartphone adoption rates of approximately 98% in active operational corridors15. Mobile financial services have transformed regional economics through secure transaction rails such as MTN Mobile Money (MoMo) and Telecel Cash, which process billions of dollars in transaction value annually across millions of active accounts17.  
Simultaneously, progress in edge computing has enabled highly quantized Small Language Models (SLMs) to execute complex natural language processing and clinical decision support directly on inexpensive mobile hardware20. This technical convergence allows the deployment of diagnostic support and logistical orchestration tools at the absolute edge of the primary care network, operating independently of cloud connectivity20.

### **The Solution**

Yoma Triage is an offline-first, intelligent clinical triage and emergency referral orchestration platform designed specifically for rural primary care environments20. Rather than introducing redundant diagnostic or physical transport assets, Yoma Triage acts as an intelligent coordination layer that bridges the gap between frontline clinical detection and definitive hospital care23. The platform consists of two core components:

* **Yoma Care (mobile / CHO app)**: An offline-first Flutter application (Android, iOS, and responsive web) for Community Health Officers. Hackathon demo uses MOEWS + advisory on-device YAMNet TFLite screening; on-device SLM triage remains pilot backlog.  
* **Yoma Dispatch (gateway)**: A backend-mediated multi-channel communication gateway that transmits compressed clinical and transport data over standard USSD, SMS, and (later) Interactive Voice Response (IVR) networks. The mobile app never calls Africa’s Talking directly.

Yoma Triage coordinates the emergency response by matching the clinical urgency of the patient with available community transport providers—such as "Motor-King" tricycle ambulances and National Ambulance Service (NAS) units—while preparing the receiving district hospital before the patient arrives9.

### **Contextual Viability**

Deploying health technology in Northern Ghana requires addressing severe systemic constraints, including frequent power grid failures, absent or intermittent internet connectivity, high clinical staff turnover, and strict budget limitations3. Yoma Triage is engineered to function reliably on a remote Tuesday afternoon during a rainstorm when cellular towers are offline, the local nurse is alone, and a mother is actively bleeding2. By converting the mobile devices already present in the field into a reliable clinical router, Yoma Triage eliminates the coordination failures that contribute to preventable rural mortality25.

## **Part II — Understanding the Problem**

### **The Three Delays Model and Maternal Mortality**

The Three Delays Model is the standard framework for evaluating maternal and neonatal mortality in low-resource settings7. This model identifies three critical phases along the patient journey:

* **The First Delay (Deciding to Seek Care)**: Driven by community-level factors, including the inability to recognize obstetric danger signs, cultural norms requiring family or spousal consent, and fear of high healthcare costs7. In Ghana, the Free Maternal Care Policy has helped reduce this barrier by waiving registration fees and clinical premiums under the National Health Insurance Scheme (NHIS)11.  
* **The Second Delay (Reaching a Referral Facility)**: Driven by geographic isolation, poor road infrastructure, and a lack of reliable transport8. This delay remains a major bottleneck in Northern Ghana, where patients must navigate long distances on unpaved roads to reach emergency obstetric care23.  
* **The Third Delay (Receiving Quality Clinical Treatment)**: Occurs after arrival at the referral facility7. It is driven by resource constraints, including shortages of trained staff, lack of blood banking capabilities, and delayed emergency interventions2.

To address the limitations of this traditional model, recent public health literature proposes a revised "Six Delays Model"36. This expanded framework adds three distinct stages to capture the operational complexity of pyramidal health systems: the delay in deciding to refer, the delay in reaching the referral center, and the delay in receiving care at the referral center36. By separating the initial care-seeking journey from the subsequent inter-facility transfer, this model highlights the critical role of inter-facility communication and transport logistics in patient survival23.

### **The Significance of the Second Delay in Northern Ghana**

In the rural districts of Northern Ghana, the second delay is the primary systemic point of failure9. While many pregnant women follow recommendations for facility-based antenatal care and skilled delivery, emergency complications require rapid transfer from community-level CHPS compounds to district hospitals7.  
The geography of Northern Ghana is characterized by highly dispersed settlements, low population density, and unpaved roads that are frequently washed out during the rainy season39. The physical distance between a primary CHPS compound and the nearest district hospital often exceeds 15 kilometers, with neonatal and maternal mortality risk increasing significantly with travel time35. Research demonstrates that children from households located more than 60 minutes from a health facility face a 25.6% increase in neonatal mortality risk compared to those within 10 minutes, with the risk of death rising to 26.6% for distances exceeding 10 kilometers35.  
Because CHPS compounds are designed to provide basic preventive and primary clinical services, they are not equipped with blood banks, surgical theaters, or advanced medications required to manage severe complications3. When a life-threatening emergency arises, the patient's survival depends entirely on the speed and coordination of the transfer to a district hospital3.

### **Existing Transport Initiatives and the "Motor-King" Framework**

To address the lack of standard emergency vehicles in rural areas, various development partners and the Ghana Health Service have deployed three-wheeler motorized tricycles modified to serve as "Motor-King" community ambulances9. Under initiatives like the KOICA CHPS-Plus project and Catholic Relief Services' HOPE-MCH project, hundreds of these tricycle ambulances have been distributed to CHPS zones across the Upper East and Northern regions9.  
These tricycle ambulances are fitted with basic stretchers, first aid kits, protective canopies, and double rear tires for stability on rough terrain9. They are designed to navigate narrow, unpaved paths that are impassable for standard wheeled ambulances9.

\+-------------------------------------------------------------------------------+  
|                       EXISTING RURAL TRANSPORT PARADIGM                       |  
\+-------------------------------------------------------------------------------+  
|  CHPS Compound   \=== (Informal Voice Call) \===\>   Motor-King Driver Contacts  |  
|  \- Isolated      │ \- Personal mobile phone      \- Untracked availability     |  
|  \- No telemetry  │ \- Personal airtime cost      \- Subjective fuel status     |  
|                  │ \- No status logging          \- Informal pricing pressure  |  
|                  v                                                            |  
|  Uncoordinated, fragmented dispatch leading to prolonged transport delays    |  
\+-------------------------------------------------------------------------------+

Despite their physical suitability, these tricycle networks operate on an ad-hoc, uncoordinated basis9. There is no central registry of active drivers, no real-time tracking of vehicle availability, and no structured dispatch mechanism9. When an emergency occurs, the CHO must manually call known local drivers, often facing busy lines, unanswered calls, or drivers who are out of fuel10.  
Furthermore, because the National Health Insurance Scheme explicitly excludes emergency transport costs, rural families are often forced to pay for fuel and driver fees out-of-pocket, leading to catastrophic expenses or delayed transfers while funds are mobilized11.

### **Why Fragmented Communication and Voice Calls Cause Critical Delays**

The current mechanism for coordinating referrals within the Ghana Health Service relies on unstructured voice calls38. This model has several systemic limitations:

* **Telecom Cost Barriers**: Health workers must use their personal mobile phones and private airtime to coordinate referrals38. When a CHO is out of prepaid credits, referral communication is delayed or abandoned38.  
* **Ineffective Hospital Preparation**: Receiving district hospitals are rarely prepared for incoming emergency transfers38. Due to a lack of pre-arrival data, emergency departments cannot prepare surgical suites, secure compatible blood types, or mobilize specialist staff in advance23.  
* **Referral Note Decay**: Under GHS guidelines, all referrals must be accompanied by a completed paper-based standard referral form44. In practice, over 70% of referred patients arrive with incomplete referral notes or none at all45. CHOs operating under high stress often prioritize patient care over document completion, leading to a complete loss of clinical history when the patient is handed over to the receiving facility45.

## **Part III — User Research**

The table below outlines the primary actors within the rural referral network of Northern Ghana, detailing their operational goals, constraints, and opportunities for digital integration:

| Persona Role | Primary Operational Goals | Core Constraints & Pain Points | Digital Literacy & Tech Profile | Core Opportunities for Yoma Triage |
| :---- | :---- | :---- | :---- | :---- |
| **Community Health Officer (CHO)** \[cite: 13, 14\] | Stabilize patients locally; initiate safe, rapid referrals when complications exceed facility capacity23. | Clinical isolation; lack of specialist support; out-of-pocket airtime costs to coordinate transfers3. | High comfort with Android interfaces and WhatsApp; limited by frequent power and network outages29. | Offline clinical decision support; automated, free communication over subsidized USSD/SMS20. |
| **Frontline Midwife** \[cite: 38, 40\] | Deliver babies safely; prevent postpartum hemorrhage (PPH) and manage pre-eclampsia/eclampsia2. | Rapid maternal deterioration; high administrative burden of manual paper registries45. | Competent smartphone and computer user30; single-midwife staffing limits availability for manual logging. | Automated physiological risk calculations; instant generation of complete digital referral notes24. |
| **Caregiver / Family Member** \[cite: 14, 23\] | Ensure patient survival; avoid catastrophic out-of-pocket healthcare and transport costs11. | Lack of visibility into transit progress; communication barriers with formal dispatch systems11. | Low overall literacy; owns basic 2G feature phones; zero internet data or smartphone access31. | Interactive, localized voice and SMS updates detailing transit status and fee exemptions25. |
| **Motor-King Driver** \[cite: 9, 28\] | Earn a reliable livelihood; support community emergency transport needs28. | Financial loss due to delayed fuel and maintenance reimbursements from local health committees28. | Low digital literacy; highly dependent on voice calls and simple, numeric USSD menus26. | Automated voice-driven dispatching; guaranteed, instant mobile money disbursements upon verification17. |
| **Ambulance Driver / EMT (NAS)** \[cite: 28, 54\] | Navigate safely to remote sites; stabilize patients in transit; execute clean hospital handovers23. | Poor road routing information; lack of coordination leading to inappropriate hospital destinations35. | High digital competency; limited by standard ruggedized equipment and lack of integrated dashboards. | Direct geographic routing; pre-arrival access to the patient's edge-generated clinical chart23. |
| **Receiving Ward Nurse** \[cite: 23, 46\] | Efficiently manage patient admissions, allocate bed capacity, and coordinate surgical readiness23. | Patients arriving unannounced; incomplete or absent paper referral forms; redundant diagnostic workups44. | Competent in desktop software and hospital admin systems; limited by high patient volumes29. | Real-time visual intake queue displaying incoming patients and their clinical priorities23. |
| **Medical Superintendent** \[cite: 23, 59\] | Maximize clinical quality; optimize resource allocation; reduce institutional mortality ratios2. | Inefficient surgical block allocation; blood bank stockouts; slow data collection for clinical audits2. | High professional literacy; constrained by rigid national reporting platforms that do not interface15. | Automatic integration of referral metrics into standard maternal mortality audit databases46. |
| **District Health Director** \[cite: 9, 14\] | Allocate health budgets equitably; identify epidemiological anomalies; ensure clinical safety9. | Lack of real-time visibility into system performance; reliance on delayed, paper-aggregated reports16. | High administrative competency; limited by fragmented platforms and lack of integrated digital frameworks15. | Consolidated district dashboards with automated performance metrics and verifiable outcomes15. |

## **Part IV — Current Workflow and Systemic Bottlenecks**

### **The Current Referral Workflow**

The baseline emergency workflow within Northern Ghana's rural districts operates as a series of disconnected, manual steps. This traditional, uncoordinated referral pathway is outlined below:

\[Patient Deterioration at Home\]  
             │  
             ▼  
\[Delay 1: Deciding to Seek Care (Family consultations, financial hesitation)\]  
             │  
             ▼  
\[Travel to Frontline CHPS Compound via Foot or Commercial Motorcycle\]  
             │  
             ▼  
\[Frontline Assessment by CHO (No digital clinical decision support)\] \[cite: 13, 14, 23\]  
             │  
             ▼  
\[Manual Stabilization & Search for Transport (CHO calls local driver on private phone)\]  
      ├── Carrier Network Congestion  
      ├── CHO out of personal airtime credits  
      └── Driver unavailable or out of fuel  
             │  
             ▼  
\[Delay 2: Reaching Referral Facility (Transit on unpaved roads via unmonitored Motor-King)\] \[cite: 9, 36\]  
             │  
             ▼  
\[Arrival Unannounced at District Hospital (Paper referral form missing or incomplete)\]  
             │  
             ▼  
\[Delay 3: Receiving Care (Redundant diagnostics, unnotified surgical team, unready blood bank)\] \[cite: 7, 23, 45\]  
             │  
             ▼  
\[Definitive Treatment Initiated (Often delayed beyond the therapeutic window)\]

### **Analysis of Primary Bottlenecks**

* **Diagnostic Delay at the Edge**: In rural clinics, newly deployed CHOs often face high cognitive loads and diagnostic isolation during acute emergencies3. Without real-time decision support, clinicians may delay the decision to refer a patient with atypical complications2. This manual triage process lacks the objective structure needed to identify clinical deterioration before the patient's condition becomes critical48.  
* **Transport Brokerage Collapse**: The lack of a centralized, real-time dispatch system forces CHOs to spend critical minutes calling individual drivers from personal contact lists10. When a driver is unreachable or lacks fuel, the CHO must restart the search, losing valuable time while the patient remains unstable23.  
* **The Telecommunication Cost Barrier**: Referral coordination is frequently delayed because frontline health workers must use personal mobile airtime to call drivers and receiving hospitals38. If a CHO is out of prepaid credits, they must purchase airtime or send a physical message, creating a direct point of failure38.  
* **Complete Absence of Hospital Telemetry**: Paper-based referral forms are rarely completed or delivered during acute transfers45. Consequently, receiving hospitals have no advance notice of a patient's arrival or clinical status38. This forces emergency department staff to perform redundant diagnostic workups and delays the mobilization of critical resources like blood units or surgical teams23.

## **Part V — Yoma Triage Vision**

### **The Core Philosophy**

Yoma Triage is designed around a clear operational philosophy: it is not a diagnostic system, nor is it a transport fleet owner9. Instead, Yoma Triage serves as the *intelligent coordination layer* between frontline clinical detection and definitive hospital care23.  
The platform does not attempt to replace human clinical judgment or bypass existing health structures14. Rather, it optimizes the utilization of existing resources—such as community tricycle ambulances, national EMS units, and district hospital beds—by automating the exchange of data and logistics23.

\+-------------------------------------------------------------------------------------+  
|                               YOMA TRIAGE PRODUCT IDENTITY                              |  
\+-------------------------------------------------------------------------------------+  
|         WHAT IT IS         │                      WHAT IT IS NOT                    |  
\+----------------------------+--------------------------------------------------------+  
| • An intelligent routing   | • A primary diagnostic system generating clinical      |  
|   protocol.     |   diagnoses.                             |  
| • A communication bridge   | • A long-term Electronic Health Record (EHR)           |  
|   for low-signal areas.|   database.                         |  
| • An automated dispatcher  | • A logistics fleet owner purchasing vehicles          |  
|   for existing fleets.|  .                                    |  
\+-------------------------------------------------------------------------------------+

### **Why Existing Solutions Have Not Solved This Problem**

While several digital health tools operate in Ghana, they are not designed to coordinate real-time emergency triage and transport in low-connectivity settings15:

* **LHIMS (Lightwave Health Information Management System)**: LHIMS is a comprehensive electronic health record system implemented at patient-level facilities in Ghana49. However, it is an online-only, web-based platform designed for in-facility clinical documentation29. It lacks offline capabilities, mobile-edge triage tools, and active transport coordination or mobile money dispatch features18.  
* **DHIS2 (e-Tracker)**: The District Health Information Software 2 (DHIS2) e-Tracker is a robust, national-level aggregate and case-based surveillance platform15. While it supports offline form caching, its primary function is long-term epidemiological tracking rather than real-time emergency dispatching15.  
* **CommCare (Dimagi)**: A widely used mobile data collection platform designed for community health workers29. While CommCare supports custom forms, it relies on rule-based logic and lacks automated, multi-channel voice/USSD dispatching and real-time escrow payment integrations26.

Yoma Triage bridges these gaps by providing an offline-first clinical decision support system that converts clinical vitals into low-bandwidth coordination metrics, linking frontline workers with emergency logistics20.

## **Part VI — Product Principles**

To maintain operational integrity in the field, every design decision within the Yoma Triage ecosystem must align with nine fundamental product principles:

### **1\. Offline-First Architecture**

The primary Android tablet application must perform all core clinical calculations, risk scoring, and data operations locally on-device20. The system must remain fully functional without active internet connectivity, utilizing local SQLite caches to queue data for transmission when a cellular signal is restored24.

### **2\. Clinical Autonomy and Assistive Design**

The system must act as an assistant to human clinicians, never as a replacement14. All final clinical decisions, triage overrides, and treatment plans must be validated by a certified clinician (CHO, Midwife, or Doctor)14.

### **3\. Human-in-the-Loop Protocol Execution**

Critical transitions within the referral chain—including transport dispatches, hospital notifications, and clinical alerts—must require explicit human verification to prevent automated feedback loops and false alarms.

### **4\. Low-Literacy Interface Design**

The transport provider interface (delivered via USSD, IVR, or lightweight SMS) must use low-literacy design patterns25. It must avoid complex terminology, relying on simple numeric choices and automated voice interactions in local languages25.

### **5\. Multi-Channel Communication Fallback**

The platform must assume that standard network connections will fail29. Telemetry must automatically scale down from data networks to binary SMS, USSD channels, or automated telephone calls to guarantee transmission under any network status24.

### **6\. Minimal and Ephemeral Data Footprint**

To comply with data protection regulations and protect patient privacy, Yoma Triage collects only the minimum data required to execute the emergency referral64. All personally identifiable information is encrypted on-device and removed from active transit caches once the referral is resolved29.

### **7\. Explicit and Explainable Decisions**

Every risk score or prioritization recommended by the edge AI must be accompanied by clear, traceable reasons4. The interface must clearly display the clinical inputs and guidelines used to generate its recommendations44.

### **8\. Fail-Safe Operations**

The platform must default to simple, manual workflows if any system component fails. If the software crashes, the physical device is damaged, or networks fail entirely, the system must provide clear guidance for standard manual referral and phone-based coordination23.

### **9\. Operational and Cultural Alignment**

The platform must align with existing administrative and cultural structures within the Ghana Health Service, including standard clinical guidelines, district referral workflows, and community leadership models14.

## **Part VII — Functional Specification**

### **1\. Referral Initiation and Edge Triage Module**

* **Functional Description**: Coordinates the initial clinical capture of an emergency case at the CHPS level, providing structured, step-by-step guidance23.  
* **On-Device Data Capture**: The CHO is guided through a minimal clinical form containing fields mapped to standard GHS referral templates44:  
  * Patient demographic token (Hashed Unique Identifier)24.  
  * Gestational status, parity, and gravidity.  
  * Essential physiological vitals: systolic and diastolic blood pressure, heart rate, respiratory rate, temperature, peripheral oxygen saturation, and level of consciousness (AVPU scale)4.  
  * Dominant clinical presentation (e.g., severe vaginal bleeding, convulsions, prolonged obstructed labor, neonatal breathing distress)2.  
  * Pre-referral interventions administered (e.g., active management of third stage of labor, parenteral oxytocin, magnesium sulfate loading dose)5.  
* **Edge-AI Triage Execution**: The quantized on-device SLM runs local inference against the entered variables, flags critical anomalies, and generates a standardized risk score20. This score is mapped to a color-coded triage category: Green (Local Management/Consultation), Yellow (Urgent Referral), or Red (Critical Emergency Referral)4.  
* **Zero-Data Transmission Engine**: Upon confirmation by the CHO, the module compiles the clinical data, pre-referral actions, and triage score into a compressed, standardized text string24. This payload is prepared for transmission using a high-density Base64 or hexadecimal format designed to fit within a single, 140-octet SMS payload24.

### **2\. Decentralized Transport Brokerage and Dispatch**

* **Asset Matching Protocol**: Once a referral is confirmed, the server prioritizes and dispatches local transport27. It queries a localized registry database to identify active emergency transport assets within the patient's zone, prioritizing as follows28:  
  * **Priority 1**: Formal National Ambulance Service (NAS) units, if available and nearby42.  
  * **Priority 2**: KOICA or community-owned Motor-King tricycle ambulances based at nearby facilities9.  
  * **Priority 3**: Certified local commercial transport operators registered with the community network28.  
* **Multi-Channel Dispatching**: The dispatch request is pushed to the targeted driver's phone using a priority queue. To ensure compatibility with basic feature phones, Yoma Triage uses a three-tier communication protocol26:  
  * **Tier 1 (USSD Push)**: Triggers an interactive USSD alert directly on the driver's handset, displaying the pickup location and a numeric menu to accept or decline: CON Emergency pickup at CHPS Compound X. Press 1 to Accept, 2 to Decline26.  
  * **Tier 2 (IVR Call)**: If the USSD push is unacknowledged within 180 seconds, the Viamo API initiates an automated phone call in the driver's preferred language, reading the dispatch request and parsing DTMF keyboard tones to confirm acceptance25.  
  * **Tier 3 (Binary SMS Fallback)**: If the voice call fails, a standard SMS is dispatched with a simple, direct reply instruction24.

### **3\. Emergency Digital Wallet and Micro-Incentive Module**

* **The Out-of-Pocket Transport Barrier**: In Ghana, while the Free Maternal Care Policy covers medical services, it explicitly excludes emergency transport11. This leaves rural families facing high out-of-pocket transport costs, which is a major driver of delays11.  
* **Escrow Contract Engine**: To remove this barrier, Yoma Triage integrates an automated, multi-party escrow framework using local mobile money APIs17. Each registered facility has access to an Emergency Transport Wallet funded by development partners (such as UNICEF) or GHS regional budgets72.  
* **Verifiable Transaction Flow**:  
  * **Activation**: When a driver accepts an emergency referral via USSD or IVR, the system locks a pre-calculated transit fee (based on distance and road quality) in the platform's escrow wallet27.  
  * **Fuel Payout**: A small, automated mobile money payout (30% of the total fare) is immediately disbursed to the driver's registered MTN MoMo or Telecel Cash wallet to cover immediate fuel costs17.  
  * **Completion Handshake**: Once the driver delivers the patient to the referral hospital, the receiving triage nurse inputs a unique receipt code on the hospital terminal, or the driver dials a confirmation code. This triggers the instant release of the remaining 70% of the fare directly to the driver's mobile money account18.

### **4\. Receiving Hospital Triage and Preparation Dashboard**

* **Intake Interface**: A web-based dashboard designed for emergency wards and maternity desks at district hospitals, operating in sync with the national Lightwave Health Information Management System (LHIMS)49.  
* **Key Features**:  
  * **Dynamic Visual Queue**: Displays incoming emergency referrals sorted by triage priority (Red, Yellow, Green) and estimated arrival times4.  
  * **Edge-Telemetry Viewer**: Parses and displays the compressed clinical telemetry transmitted from the initiating CHPS tablet, showing the patient's current vitals, trends, and pre-referral medications administered24.  
  * **Capacity and Resource Matching**: Allows the receiving hospital to update its current status (e.g., active ICU beds, available blood units by type, operating room status). If a critical mismatch occurs (e.g., a patient requires blood, but the bank is dry), the system flags the issue to the initiating CHO and suggests alternative nearby hubs23.

### **5\. District Administration and Performance Analytics Portal**

* **Performance Dashboard**: A reporting terminal designed for District Health Directorates to monitor referral metrics, systemic bottlenecks, and operational costs9.  
* **Key Indicators Tracked**:  
  * **Systemic Transit Latency**: Measures the time elapsed between referral initiation, transport pickup, and hospital arrival23.  
  * **Transport Responsiveness**: Tracks average response times and acceptance rates for both Motor-King drivers and formal ambulances28.  
  * **Referral Diagnostic Concordance**: Compares edge-generated clinical risk levels with final hospital diagnoses to monitor the accuracy of the triage model44.  
  * **Budget Consumption Rate**: Displays real-time spending across facility transport wallets, helping administrators manage funds and prevent stockouts11.

## **Part VIII — AI Strategy**

The table below outlines the scope of artificial intelligence components within the Yoma Triage architecture, detailing what is included or excluded and the operational justification for each decision5:

| Core AI Capability | Included status | Technical Implementation Approach | Strategic and Operational Justification |
| :---- | :---- | :---- | :---- |
| **Referral Prioritization** \[cite: 48\] | **INCLUDED** | Edge execution of rule-aligned classification models combined with physiological logic4. | Accelerates emergency detection at the primary care level, converting vitals into actionable routing priorities23. |
| **Natural Language Summarization** | **INCLUDED** | On-device inference via highly quantized (Q4\_K\_M) open-source Small Language Models20. | Synthesizes unstructured clinical notes into standardized, brief electronic messages24. |
| **Speech-to-Text Transcription** | **INCLUDED** | Quantized whisper-tiny runtimes executing on Android mobile hardware20. | Accommodates multi-tasking, allowing hands-free clinical capture during acute obstetric crises22. |
| **Acoustic Breathing Screening** | **EXCLUDED** | Delayed to future phases; currently restricted to research modules. | Excluded due to a lack of robust clinical validation and high edge computation constraints77. |
| **Predictive Follow-Up Risk** | **EXCLUDED** | Delayed to future phases; executed solely on regional backend databases. | Excluded from the edge to prioritize core triage speed and limit the on-device processing footprint21. |
| **Disease Diagnosis** \[cite: 14, 38\] | **EXCLUDED** | Strictly prohibited in software logic; clinical categorization is locked38. | Protects safety, avoids regulatory delays, and ensures final accountability remains with the human clinician38. |
| **Drug Prescribing** \[cite: 5, 47\] | **EXCLUDED** | Strictly prohibited; software defaults to official guidelines5. | Prevents medication errors and ensures compliance with standard GHS treatment protocols47. |
| **Autonomous Clinical Actions** | **EXCLUDED** | All protocol transitions require explicit physical validation by the CHO23. | Ensures clinical and administrative accountability remains securely with certified human operators23. |

## **Part IX — Clinical Safety and Guardrails**

### **Defining AI Operational Boundaries**

The AI components of Yoma Triage operate strictly as assistive administrative tools38. Under no circumstances can the edge model generate primary clinical diagnoses, modify established clinical pathways, or prescribe drug regimens5.  
The software serves to structure, summarize, and compress clinical notes entered by human operators, helping them apply official GHS treatment protocols more consistently44. All clinical authority and accountability remain with the licensed healthcare professional operating the system23.

### **The Standardized MOEWS Triage Protocol**

To ensure objective clinical triage, Yoma Triage implements a Modified Obstetric Early Warning Score (MOEWS) framework tailored for low-resource primary care settings48. This system converts physiological vitals into a standardized, color-coded risk assessment4.  
The on-device triage engine processes physiological observations based on the criteria in the table below:

| Physiological Parameter | Red Alert Score (3 pts) | Yellow Alert Score (2 pts) | Normal Range (0 pts) | Yellow Alert Score (2 pts) | Red Alert Score (3 pts) |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Systolic BP (mmHg)** \[cite: 48\] | ![][image1] | N/A | ![][image2] | ![][image3] | ![][image4] |
| **Diastolic BP (mmHg)** \[cite: 48\] | N/A | N/A | ![][image1] | ![][image5] | ![][image6] |
| **Heart Rate (BPM)** \[cite: 48\] | ![][image7] | ![][image8] | ![][image9] | ![][image10] | ![][image11] |
| **Respiratory Rate (tpm)** \[cite: 48\] | ![][image12] | N/A | ![][image13] | ![][image14] | ![][image15] |
| **Temperature (°C)** \[cite: 48\] | ![][image16] | N/A | ![][image17] | ![][image18] | ![][image19] |
| **Oxygen Saturation (%)** \[cite: 48\] | ![][image20] | ![][image21] | ![][image22] | N/A | N/A |
| **Consciousness** \[cite: 48\] | Voice/Pain/Unresponsive | N/A | Alert | N/A | N/A |

The system calculates a cumulative triage risk score using the following formula:  
![][image23]  
where ![][image24] is the parameter score derived from vital value ![][image25]. Triage prioritization is then assigned according to objective thresholds:

* **Green (Score: 0 to 2\)**: Standard care. The patient is stable and can be managed locally or scheduled for a routine consultation48.  
* **Yellow (Score: 3 to 4, or any single parameter scoring 2\)**: Elevated risk. The CHO must inform the district referral coordinator, increase vital monitoring frequency to every 30 minutes, and initiate a soft transport reservation23.  
* **Red (Score: ![][image26], or any single parameter scoring 3\)**: Critical emergency. The system triggers immediate transport brokerage, dispatches clinical telemetry, and alerts the receiving district hospital to prepare emergency resources4.

### **Handover Verification and Accountability Protocols**

To ensure clinical accountability, a referral remains "active" until a verifiable clinical handshake is completed23. When the transport vehicle arrives at the hospital, the receiving nurse scans a unique encrypted QR code displayed on the accompanying transfer card, or inputs a temporary confirmation token23. This updates the status to "Arrived" and closes the operational loop23.  
Every transition, manual override, clinical data point, and telemetry message is logged in a secure, tamper-proof local audit file44. In the event of a negative outcome or patient death, these logs provide regional review committees with a clear, verifiable timeline of the referral2. This system replaces unreliable verbal accounts with precise, objective data to identify and resolve systemic bottlenecks46.

## **Part X — Technical Architecture**

\+-------------------------------------------------------------------------------+  
|                            TECHNICAL ARCHITECTURE                             |  
\+-------------------------------------------------------------------------------+  
|                            Yoma Care (CHO app)                                 |  
|  \- Flutter UI (Android/iOS/Web)       \- On-device TFLite (YAMNet advisory)    |  
|  \- Room/SQLite Local DB              \- llama.cpp / Llamatik (Offline SLM)     |  
\+--------------------------------------+----------------------------------------+  
                                       │  
                    Data Transit Rails │ (HTTPS, USSD API, or Binary SMS)  
                                       v  
\+--------------------------------------+----------------------------------------+  
|                            Yoma Dispatch Gateway                              |  
|  \- Node.js API Gateway               \- Viamo Voice/IVR Engine Integration     |  
|  \- Redis Session Cache               \- Mobile Money Aggregator Rail           |  
\+--------------------------------------+----------------------------------------+  
                                       │  
                                       v  
\+--------------------------------------+----------------------------------------+  
|                            Platform Core Database                             |  
|  \- PostgreSQL Database Layer         \- AES-256 Symmetric Field Encryption      |  
\+-------------------------------------------------------------------------------+

### **Edge Processing and Mobile Inference Engine**

The Yoma Care CHO application is implemented in Flutter (Dart), targeting Android phones, iOS phones, and responsive web for hackathon demo coverage. Historical design research considered native Kotlin/Compose; the shipping stack is Flutter. The local system is designed to run entirely offline for core CHO actions:

* **Model Loading and Storage**: Quantized model binaries are stored in the application's local sandbox storage directory21. To reduce memory overhead, the app dynamically loads model weights into RAM using memory-mapped I/O (mmap), bypassing Java Native Interface (JNI) latency bottlenecks21.  
* **Processing Execution**: Inference is managed via localized C/C++ native bindings using a Kotlin-first wrapper (such as Llamatik or the ONNX Runtime Mobile engine)21. This setup isolates background processing threads from the main UI thread, ensuring the interface remains smooth and responsive during active background processing22.

### **Synchronization and Fallback Architecture**

The mobile application uses a hybrid synchronization engine that monitors network signal quality and automatically selects the most efficient transmission path:

\[New Emergency Triage Submission\]  
                 │  
                 ▼  
       \[Check Connectivity\]  
        ├── Active 3G/4G/Wi-Fi Network  
        │     └── Transmit standard encrypted JSON payload via secure HTTPS APIs  
        │  
        └── Data Offline (No internet)  
              │  
              ▼  
  \[Serialize to Local SQLite / Room DB\] (Saves clinical record locally)  
              │  
              ▼  
  \[Compile Data into Compressed Base64 String\]  
              │  
              ▼  
  \[Dispatch over GSM SMS Telemetry Gateway\]  
        ├── Success (Remote server receives and decodes Base64 SMS packet)  
        └── Network Drop (No cellular signal)  
              │  
              ▼  
  \[Queue in Local Outbox\] (App retries automatically when GSM signal is restored)

### **Low-Bandwidth Data Compression Protocol**

To transmit detailed clinical vitals over standard 2G GSM cellular SMS channels, Yoma Triage implements a highly efficient binary compression format similar to the DHIS2 Android SMS protocol24. This system packs variables into ultra-dense, Base64-encoded strings24.  
An standard 140-octet SMS payload (1,120 bits) is allocated as follows69:

* **Header Core (112 bits)**:  
  * Application Identifier (8 bits): Identifies the Yoma Triage packet format.  
  * Schema Version (8 bits): Ensures compatibility with server-side parsers.  
  * MD5 Payload Checksum (32 bits): Validates data integrity24.  
  * Hashed Facility Identifier (32 bits): Identifies the initiating CHPS compound24.  
  * Hashed User Token (32 bits): Identifies the clinical officer initiating the transfer24.  
* **Clinical Registry Vector (192 bits)**:  
  * Patient Age Category (8 bits): Encodes age range and demographic token.  
  * Parity & Gravidity (16 bits): Essential obstetric history.  
  * Systolic & Diastolic BP (16 bits): Direct millibar representation48.  
  * Heart Rate & Respiratory Rate (16 bits): Physical clinical vital counts48.  
  * Temperature (16 bits): Quantized with a scale multiplier of ![][image27]48.  
  * Saturation and AVPU status (16 bits): High-precision vital metrics48.  
  * Primary Presentation Code (32 bits): High-density diagnostic categorical array.  
  * Pre-referral Treatment Array (72 bits): Bitfield mapping administered medications68.  
* **Transit Core Registry (64 bits)**:  
  * Requested Transport Type (8 bits): Matches triage risk level with vehicle types28.  
  * Target Referral Facility Code (32 bits): Identifies the destination hospital44.  
  * Security Token (24 bits): Validates authorization and integrity.

The resulting binary payload is serialized, hashed, and converted to base64, generating a secure 52-character alphanumeric text string24:  
bG9jYWxfYWlfZGF0YV9zeW5jX3BhY2tldF9zdHJpbmdfZXhhbXBsZQ==  
This compressed string is easily transmitted across standard, low-signal 2G cellular connections, bypassing network congestion and avoiding high mobile data costs24.

### **USSD State Machine Sequence and Integration Architecture**

The transport dispatch and matching system operates as a stateless, real-time interactive USSD menu system, designed to work reliably on basic feature phones without cellular data26.

       \[Driver dials \*848\# shortcode\]  
                     │  
                     ▼  
       \[GSM Network routes to Carrier USSD Gateway\]  
                     │  
                     ▼  
  \[Stateless HTTP POST to Yoma Triage Gateway (Session ID & PhoneNumber)\]  
                     │  
                     ▼  
     \[Gateway queries DB & maps Session State\] \[cite: 27, 82\]  
                     │  
         ┌───────────┴───────────┐  
         ▼                       ▼  
  \[Active Dispatch Pending\]    \[No Active Dispatch\]  
         │                       │  
         ▼                       ▼  
  \[Return Accept/Decline Menu\]  \[Return Default Main Menu\]  
  "Pickup: CHPS Compound A"     1\. View Active Balance  
  "Fee: 85 GHS" \[cite: 33\]      2\. Update Status  
  1\. Accept         3\. Claim History  
  2\. Decline         

Each menu selection translates to a round-trip latency of less than 2 seconds, staying well within the standard 10-second carrier timeout budget26. The gateway parses the delimited response strings, executes the corresponding business logic, and returns the next menu screen, ensuring a responsive and reliable user experience27.

### **Platform Security, Authentication, and Encryption Standard**

To protect patient privacy, Yoma Triage applies end-to-end security measures across the entire data pipeline29:

* **On-Device Database Encryption**: The local Room/SQLite database is secured using SQLCipher, applying AES-256 symmetric encryption to protect all stored records63. The decryption keys are managed via the Android Keystore system and are bound to biometric or clinical PIN credentials.  
* **Network Security Protocols**: Active cellular data transfers use secure HTTPS channels with TLS 1.3 encryption and strict certificate pinning65. SMS telemetry strings are encrypted locally using AES-256-GCM prior to Base64 encoding, ensuring data remains secure during transit over carrier networks24.  
* **Access Control and Authentication**: Access to the web interface and mobile applications is managed via OAuth 2.0 with JSON Web Tokens (JWT)27. Healthcare workers must log in using two-factor authentication, combining standard clinical password credentials with temporary SMS tokens or biometric verification27.

## **Part XI — Data Architecture**

### **Database Entity Relationship Model**

The Yoma Triage backend database is structured around eight core relational entities to coordinate clinical triage, transport dispatches, and financial transactions:

\+------------------+             \+------------------+             \+------------------+  
|    FACILITY      |             |     REFERRAL     |             |      PATIENT     |  
\+------------------+             \+------------------+             \+------------------+  
| PK facility\_id   |1       1..\* | PK referral\_id   |1..\*        1| PK patient\_hash  |  
|    name          |------------\>| FK facility\_id   |\<------------|    age\_years     |  
|    latitude      |             | FK patient\_hash  |             |    nhis\_number   |  
|    longitude     |             |    triage\_score  |             \+------------------+  
\+------------------+             |    moews\_score   |  
         │                       \+------------------+  
         │1                               │1  
         │                                │  
         │ Has Many                       │ Has One  
         v                                v  
\+------------------+             \+------------------+             \+------------------+  
|     DRIVER       |             |     JOURNEY      |             |   NOTIFICATION   |  
\+------------------+             \+------------------+             \+------------------+  
| PK driver\_id     |1       0..\* | PK journey\_id    |1       0..\* | PK notification\_id|  
| FK facility\_id   |------------\>| FK referral\_id   |------------\>| FK referral\_id   |  
|    phone\_number  |             | FK driver\_id     |             |    channel\_type  |  
|    status        |             |    status        |             |    status        |  
\+------------------+             \+------------------+             \+------------------+  
         │1                               │  
         │                                │ Releases  
         v Has One                        v  
\+------------------+                      │  
|     WALLET       |\<─────────────────────┘  
\+------------------+  
| PK wallet\_id     |  
| FK driver\_id     |  
|    balance\_ghs   |  
\+------------------+

### **Core Schema Definitions**

The tables below define the structure of the database tables within the Yoma Triage system:

SQL  
\-- 1\. Facility Entity Schema  
CREATE TABLE facilities (  
    facility\_id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
    ghs\_registration\_code VARCHAR(100) UNIQUE NOT NULL,  
    facility\_name VARCHAR(255) NOT NULL,  
    facility\_tier VARCHAR(50) CHECK (facility\_tier IN ('CHPS Compound', 'Health Center', 'District Hospital', 'Regional Hospital')) NOT NULL,  
    latitude DECIMAL(9, 6) NOT NULL,  
    longitude DECIMAL(9, 6) NOT NULL,  
    resource\_capacity\_status JSONB NOT NULL DEFAULT '{}'::jsonb,  
    created\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP  
);

\-- 2\. Patient Entity Schema (Stored Locally on the Edge Client)  
CREATE TABLE patients (  
    patient\_hash VARCHAR(64) PRIMARY KEY, \-- Secure SHA-256 hash of patient ID  
    age\_years INT NOT NULL CHECK (age\_years \>= 0),  
    nhis\_membership\_number VARCHAR(255), \-- Encrypted NHIS number  
    gravidity INT CHECK (gravidity \>= 0),  
    parity INT CHECK (parity \>= 0),  
    last\_menstrual\_period TIMESTAMP WITH TIME ZONE,  
    created\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP  
);

\-- 3\. Referral Entity Schema  
CREATE TABLE referrals (  
    referral\_id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
    initiating\_facility\_id UUID REFERENCES facilities(facility\_id) NOT NULL,  
    target\_facility\_id UUID REFERENCES facilities(facility\_id) NOT NULL,  
    patient\_hash VARCHAR(64) REFERENCES patients(patient\_hash) NOT NULL,  
    triage\_risk\_level VARCHAR(20) CHECK (triage\_risk\_level IN ('Green', 'Yellow', 'Red')) NOT NULL,  
    moews\_score INT CHECK (moews\_score BETWEEN 0 AND 15) NOT NULL,  
    clinical\_telemetry\_payload TEXT NOT NULL, \-- Compressed Base64 representation of vitals  
    pre\_referral\_interventions JSONB NOT NULL DEFAULT '\[\]'::jsonb,  
    referral\_status VARCHAR(50) CHECK (referral\_status IN ('Initiated', 'Dispatched', 'In-Transit', 'Handed-Over', 'Cancelled')) NOT NULL DEFAULT 'Initiated',  
    created\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP  
);

\-- 4\. Driver Entity Schema  
CREATE TABLE drivers (  
    driver\_id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
    facility\_id UUID REFERENCES facilities(facility\_id), \-- Assigned hub  
    phone\_number VARCHAR(50) UNIQUE NOT NULL,  
    preferred\_language VARCHAR(50) DEFAULT 'Nankani' NOT NULL,  
    vehicle\_type VARCHAR(50) CHECK (vehicle\_type IN ('Motor-King', 'Ambulance', 'Commercial')) NOT NULL,  
    current\_latitude DECIMAL(9, 6),  
    current\_longitude DECIMAL(9, 6),  
    operational\_status VARCHAR(50) CHECK (operational\_status IN ('Active', 'Dispatched', 'Offline', 'Suspended')) NOT NULL DEFAULT 'Offline',  
    created\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP  
);

\-- 5\. Journey Entity Schema  
CREATE TABLE journeys (  
    journey\_id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
    referral\_id UUID REFERENCES referrals(referral\_id) UNIQUE NOT NULL,  
    driver\_id UUID REFERENCES drivers(driver\_id) NOT NULL,  
    assigned\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP,  
    pickup\_at TIMESTAMP WITH TIME ZONE,  
    completed\_at TIMESTAMP WITH TIME ZONE,  
    route\_gps\_trail JSONB DEFAULT '\[\]'::jsonb  
);

\-- 6\. Notification Entity Schema  
CREATE TABLE notifications (  
    notification\_id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
    referral\_id UUID REFERENCES referrals(referral\_id) NOT NULL,  
    recipient\_phone VARCHAR(50) NOT NULL,  
    channel\_type VARCHAR(20) CHECK (channel\_type IN ('USSD', 'SMS', 'Voice Call', 'Web-Push')) NOT NULL,  
    payload\_message TEXT NOT NULL,  
    delivery\_status VARCHAR(20) CHECK (delivery\_status IN ('Queued', 'Dispatched', 'Delivered', 'Failed')) NOT NULL DEFAULT 'Queued',  
    sent\_at TIMESTAMP WITH TIME ZONE  
);

\-- 7\. Wallet Entity Schema  
CREATE TABLE wallets (  
    wallet\_id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
    driver\_id UUID REFERENCES drivers(driver\_id) NOT NULL,  
    balance\_ghs DECIMAL(10, 2) NOT NULL DEFAULT 0.00,  
    currency\_code VARCHAR(3) DEFAULT 'GHS' NOT NULL,  
    funding\_source\_token VARCHAR(255),  
    updated\_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP  
);

\-- 8\. Audit Trail Entity Schema  
CREATE TABLE audit\_trails (  
    audit\_id UUID PRIMARY KEY DEFAULT gen\_random\_uuid(),  
    event\_type VARCHAR(100) NOT NULL,  
    event\_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT\_TIMESTAMP,  
    user\_session\_token VARCHAR(255),  
    event\_metadata JSONB NOT NULL DEFAULT '{}'::jsonb  
);

### **Data Privacy Schema: Stored vs. Never Stored Data**

To comply with Ghana's Data Protection Act (Act 843\) and protect patient privacy, the platform separates essential operational tracking data from sensitive personal identification markers64:

| Data Fields STORED on the Core Server | Data Fields NEVER STORED on the Core Server |
| :---- | :---- |
| • Hashed unique identification tokens (patient\_token\_hash) to protect anonymity24. | • Patient Names and direct identification markers (e.g., phone numbers, home addresses)29. |
| • Physiological vital signs and calculated MOEWS risk classifications4. | • Raw voice input recordings from clinicians22. |
| • Facility names, registration codes, and coordinates44. | • Driver location history outside of active emergency referral transits27. |
| • Driver phone numbers, vehicle classes, and status markers27. | • Plaintext NHIS registration numbers11. |
| • Transit timestamps and route coordinates during active referrals23. | • Plaintext user PIN codes and authentication passwords. |
| • Escrow transaction logs and wallet balances17. | • Detailed medical history unrelated to the active emergency referral44. |

## **Part XII — User Journeys**

### **1\. Severe Postpartum Hemorrhage Escalation under Critical Offline Conditions**

* **The Incident**: A 24-year-old mother develops severe, active postpartum hemorrhage at a remote CHPS compound in the Savelugu district, 20 kilometers from the district hospital2. The mobile network is completely down, and the facility has no internet connectivity29.  
* **Step-by-Step Resolution**:  
  1. **Edge Triage**: The CHO enters the patient's vitals on the offline Android tablet: Systolic BP 80 mmHg, Diastolic BP 45 mmHg, Heart Rate 135 BPM, and active vaginal bleeding2.  
  2. **Risk Scoring**: The on-device quantized SLM runs local inference and calculates a MOEWS score of 8, automatically triggering a "Red" critical emergency status4.  
  3. **Offline Communication**: The application compiles the vitals, pre-referral interventions (e.g., 10 IU intramuscular oxytocin), and triage score into a compressed 52-character base64 text string24. The device queues the payload for transmission over standard 2G SMS channels, bypasses the offline data network, and schedules auto-retry attempts24.  
  4. **Manual Backup Instructions**: The app displays clear backup instructions on-screen: Data network offline. Handover standard paper transfer card and utilize voice backup to contact referral coordinates at Savelugu District Hospital38.

### **2\. Child with Respiratory Distress and Transport Brokerage Match**

* **The Incident**: A mother arrives at a CHPS compound with a 14-month-old child presenting with severe chest indrawing, rapid breathing, and signs of pneumonia13.  
* **Step-by-Step Resolution**:  
  1. **Triage Ingest**: The midwife enters clinical indicators: respiratory rate of 55 breaths per minute, low blood oxygen saturation (90%), and chest indrawing48.  
  2. **Priority Verification**: The clinical engine assigns a critical risk rating and requests immediate transport48.  
  3. **Smart Matching**: The server searches the local driver database, bypasses a busy regional ambulance, and targets the nearest registered Motor-King tricycle ambulance based 2 kilometers away9.  
  4. **USSD Dispatching**: The system pushes an interactive USSD alert directly to the driver's phone26. The driver presses 1 to accept, immediately triggering a 35 GHS mobile money disbursement to cover fuel costs17.  
  5. **Hospital Ready**: The server transmits the child's respiratory vitals to the receiving hospital's triage portal, alerting the staff to prepare pediatric oxygen therapy before the tricycle arrives7.

### **3\. Complete Driver Booking Rejection and Escalation**

* **The Incident**: An emergency referral is initiated for a patient presenting with postpartum eclampsia and active seizures2.  
* **Step-by-Step Resolution**:  
  1. **Triage & Query**: The CHO initiates a "Red" priority emergency transfer4. The brokerage server queries the driver database and initiates serial USSD dispatches to the three nearest registered drivers26.  
  2. **Declined Requests**:  
     * Driver 1 declines due to engine issues.  
     * Driver 2 declines because they are outside the operational zone.  
     * Driver 3 does not acknowledge the USSD push within 120 seconds.  
  3. **Automated Escalation**:  
     * Recognizing the lack of response, the system escalates the dispatch and triggers a direct API call to the national 112 ambulance network dispatcher28.  
     * Simultaneously, the system activates community backup contacts, initiating automated IVR phone calls in local languages to registered community volunteers and health management committee members9.  
     * The system updates the CHO's tablet screen in real-time, displaying the backup contacts and guiding them to initiate direct manual calls while standby support is mobilized23.

### **4\. Mid-Transit Network Outage**

* **The Incident**: A patient presenting with severe pre-eclampsia is loaded into a Motor-King tricycle ambulance and starts transit toward the district hospital2. Halfway through the journey, the local cellular network tower fails, causing a complete loss of signal29.  
* **Step-by-Step Resolution**:  
  1. **Active Offline Monitoring**: The CHO accompanying the patient continues to record physiological vitals on the offline Android tablet at 15-minute intervals23.  
  2. **Local Caching**: The app serializes these clinical records in its local SQLite database24. The system recognizes the lack of cellular connection, pauses transmission attempts, and caches the update queue24.  
  3. **Verification and Handshake Recovery**:  
     * Upon physical arrival at Savelugu District Hospital, the driver and CHO navigate to the triage desk23.  
     * Because the network is offline, the receiving nurse cannot access the online dashboard30. The nurse uses the camera on their mobile device to scan the secure QR code displayed on the CHO's tablet20.  
     * The QR code encodes the cached clinical history and triage data20. This immediately transfers the patient's record to the hospital's local system, completing the handover verification process23.

### **5\. Receiving Hospital Overcapacity and Rejection**

* **The Incident**: A patient presenting with severe hemorrhaging is in transit toward a nearby district hospital2. However, the hospital's surgical block is currently full due to ongoing emergency surgeries, and the blood bank lacks compatible types2.  
* **Step-by-Step Resolution**:  
  1. **Dashboard Alert**: The receiving nurse marks the hospital's status as "Overcapacity \- No Surgical Resources Available" on the terminal44.  
  2. **Dynamic Routing**:  
     * The matching server intercepts the active journey status and evaluates alternative nearby facilities23.  
     * The system identifies an alternative accredited hospital 12 kilometers away with open surgical blocks and compatible blood inventory40.  
     * The server pushes an urgent redirect notification directly to the driver's phone via USSD and initiates an automated IVR call to the accompanying CHO's device, reading the redirect instructions23.  
     * The transit fee is automatically recalculated to reflect the longer route, and the escrow contract updates to ensure the driver receives the correct payment upon arrival18.

### **6\. Critical Family Transport Refusal**

* **The Incident**: A CHO identifies a critical case of severe neonatal sepsis at a remote CHPS compound and initiates a "Red" emergency referral4. However, the child's family members refuse the transfer due to fears of high hospital costs and cultural concerns7.  
* **Step-by-Step Resolution**:  
  1. **Triage Registration**: The CHO registers the neonatal vital signs: respiratory rate of 70 breaths per minute, heart rate of 190 BPM, and severe hypothermia (34.8°C)35.  
  2. **Refusal Overrides**:  
     * Recognizing the family's refusal, the CHO selects the "Patient / Family Refused Transfer" option in the application interface.  
     * The app pauses the transport dispatch queue, preventing unnecessary vehicle dispatch and preserving resources28.  
     * The app launches an interactive counseling guide, providing localized talking points in the family's preferred language to help the CHO address financial concerns, explain the free care policy, and clarify the severity of the child's condition23.  
     * If the family still refuses, the CHO documents the refusal in the system, requiring a digital signature or verbal confirmation token. This secures the facility's legal safety while compiling a detailed record of the case for district health reviews44.

## **Part XIII — Pilot Design and Implementation Framework**

### **Setting Selection**

The pilot program is designed for implementation in two districts in Northern Ghana: Kassena-Nankana East Municipal and Savelugu Municipal39. These locations are selected for their combination of established CHPS networks and challenging geographic and environmental conditions9.  
The pilot will deploy the platform across 50 functional CHPS compounds, connecting them to 10 sub-district health centers and district hospitals9. The pilot registry will register 150 local Motor-King tricycle operators and active community transport drivers9.

### **Success Metrics and Benchmarks**

The pilot program evaluates performance across five primary operational and clinical metrics:

* **Triage Decision Latency**: Reduces the average time elapsed between a patient's arrival at a CHPS compound and the decision to refer from 45 minutes to under 10 minutes23.  
* **Transport Matching Latency**: Lowers the average time required to locate and dispatch an available transport vehicle from 90 minutes to under 5 minutes7.  
* **Systemic Transit Latency**: Reduces the average journey time from referral confirmation to hospital arrival by 40%, keeping transit times under 60 minutes to reduce complications23.  
* **Referral Form Completeness**: Pushes the completeness of GHS referral forms from under 30% to over 95% via automated digital data aggregation45.  
* **Payment Processing Speed**: Reduces the average time required to disburse transport fees to drivers from 14 days to under 10 minutes, maintaining driver trust and system reliability53.

### **Clinical Training and Onboarding Plan**

To ensure clinical safety and ease of use, the pilot will implement a structured "train-the-trainer" curriculum:

* **Phase 1 (Master Training)**: Midwifery supervisors and district coordinators will complete standardized simulation drills on edge-AI triage, MOEWS parameters, and USSD mechanics28.  
* **Phase 2 (Simulation Drills)**: CHOs and frontline nurses will complete hands-on simulation training on-site28. These sessions will focus on tablet usage, vital inputting, and error recovery under high-stress scenarios63.  
* **Phase 3 (Remote Refresher Courses)**: Continuous remote follow-up training will be delivered via interactive IVR calls using platforms like Viamo and Agoo86. This approach lowers training costs and fits seamlessly into standard clinic workflows88.

## **Part XIV — Business and Sustainability**

### **Operating Costs Analysis**

To support pilot operations and regional scale-up, the platform's cost structure is divided into capital expenditures (CapEx) and recurring operational expenditures (OpEx):

| Cost Classification | Hardware and Software Assets | Unit Rate (USD) | Core Pilot Budget (USD) | Primary Funding Source |
| :---- | :---- | :---- | :---- | :---- |
| **CapEx: Tablet Devices** | Pre-configured ruggedized Android tablets with solar battery chargers20. | $120 per facility | $6,000 | Subsidized by development partners (e.g., KOICA, USAID)9. |
| **CapEx: System Setup** | Backend deployment, dashboard configuration, and LHIMS API integrations49. | Lump sum | $12,000 | Core technical development budget. |
| **OpEx: SMS/USSD Channels** | Monthly usage fees for standard SMS and interactive USSD shortcodes24. | $25 per shortcode / month | $3,000 (annual total) | Funded by GHS District operational budgets. |
| **OpEx: System Maintenance** | On-device model updates, database hosting, security reviews, and technical support20. | $50 per hospital / month | $6,000 (annual total) | Consolidated under GHS national IT maintenance budgets. |
| **OpEx: Fuel Escrow Wallet** | Dynamic micro-incentive disbursements for emergency tricycles17. | $12 per average transfer | $14,400 (assumes 1,200 annual transfers) | Funded by the National Health Insurance Scheme (NHIS)11. |

### **Stakeholder Partnerships and Policy Alignment**

To support deployment and adoption, Yoma Triage maintains close alignment with three key stakeholder groups in Ghana:

* **UNICEF Innovation Office**: Coordinates the initial pilot funding, supports hardware procurement, and leads the integration of IVR training modules72.  
* **Ghana Health Service (Policy, Planning, Monitoring, and Evaluation Directorate)**: Ensures the platform aligns with the National Digital Health Strategy 2023-2027 and the Networks of Practice operational guidelines64.  
* **Ministry of Communications and Digitalisation**: Coordinates with major telecommunications providers (such as MTN Ghana) to secure zero-rated USSD shortcodes and subsidized SMS packages, lowering operational communication costs27.

### **Integration with National Health Finance Frameworks**

The core financial sustainability of Yoma Triage depends on its integration with existing national health financing structures, moving away from a long-term reliance on donor grants11:

\+---------------------------------------------------------------------------------------------------------+  
|                                     SUSTAINABLE HEALTH FINANCING MODEL                                  |  
\+---------------------------------------------------------------------------------------------------------+  
|                                                                                                         |  
|   \+-----------------------------+                                    \+-----------------------------+    |  
|   |    NATIONAL LEVEL (NHIA)    |                                    |   DISTRICT LEVEL (WALLETS)  |    |  
|   |                             |                                    |                             |    |  
|   |  \- National Health Insurance|                                    |  \- Direct Facility Wallets  |    |  
|   |    Scheme (NHIS) Fund       | \=================================\> |  \- Immediate Mobile Money   |    |  
|   |  \- GHS Core Budget \[cite: 11\]|        Claim Reimbursements        |    Disbursals \[cite: 17\]     |    |  
|   \+--------------+--------------+                                    \+--------------+--------------+    |  
|                  |                                                                  |                   |  
|                  | Policy Integration                                               | Fuel Payouts      |  
|                  v                                                                  v                   |  
|   \+-----------------------------+                                    \+-----------------------------+    |  
|   |   LIVELIHOOD SUPPORT (LEAP) |                                    |    EMERGENCY MOTOR-KINGS    |    |  
|   |                             |                                    |                             |    |  
|   |  \- Direct Premium Waivers   |                                    |  \- Local Tricycle Operators |    |  
|   |  \- Integration with Social  |                                    |  \- Guaranteed Reimbursements|    |  
|   |    Services     |                                    |                  |    |  
|   \+-----------------------------+                                    \+-----------------------------+    |  
|                                                                                                         |  
\+---------------------------------------------------------------------------------------------------------+

* **National Health Insurance Scheme (NHIS) Integration**: Under the Free Maternal Care Policy, the National Health Insurance Authority (NHIA) waives registration fees and premiums for pregnant mothers, reimbursing clinics for maternal services11. Yoma Triage proposes integrating emergency transit costs directly into this reimbursement framework, allowing clinics to claim transit fees from the NHIS to replenish their local emergency wallets11.  
* **Livelihood Empowerment Against Poverty (LEAP) Linkages**: The platform aligns with the LEAP program, which provides direct cash transfers and health insurance waivers to vulnerable households91. By integrating these social registries, Yoma Triage ensures that the poorest families receive complete, automated out-of-pocket exemptions during emergency transits11.

## **Part XV — Risks and Mitigations**

Deploying a clinical coordination platform in Northern Ghana's rural primary care network involves several technical, clinical, operational, political, and financial risks. The table below details these risks and their associated mitigation strategies:

| Risk Category | Identified Hazard Vector | Impact Severity | Probability of Occurrence | Mitigation Strategy and Technical Guardrails |
| :---- | :---- | :---- | :---- | :---- |
| **Technical** | Prolonged power grid and solar failures, causing tablet batteries to deplete29. | High | Moderate | Deploy ruggedized devices with low-power e-ink displays, provide high-capacity solar power banks, and maintain a hot-swap inventory of charged tablets at sub-district hubs20. |
| **Technical** | Mobile network outages and SMS gateway downtime, preventing dispatch18. | High | Moderate | Implement local SQLite data queueing, use dual-SIM multi-carrier backup routers, and provide an automated offline voice/IVR backup system24. |
| **Clinical** | Clinicians blindly follow AI recommendations without applying clinical judgment38. | High | Low | Implement clear system guardrails: the AI cannot generate diagnoses or modify dosing, and all key actions require manual clinical sign-off5. |
| **Clinical** | Edge triage models generate false negatives, causing critical cases to be delayed48. | High | Low | Tailor the MOEWS framework to prioritize sensitivity, ensuring suspicious or borderline cases default to high-priority triage48. |
| **Operational** | High clinical staff turnover, leading to trained users leaving the pilot zones3. | Moderate | High | Build simple, automated interactive training tutorials directly into the mobile app, allowing new users to complete onboarding on-device in under an hour63. |
| **Operational** | Commercial tricycle drivers refuse dispatches due to concerns about delayed payouts28. | High | Moderate | Use mobile money APIs to automate instant payouts, immediately releasing 30% of the fare for fuel and the remaining 70% upon verified handover17. |
| **Political** | Changes in district or national leadership cause policy priorities or funding to shift64. | Moderate | Moderate | Maintain strict alignment with GHS national policy documents, and engage regional health directorates early to secure institutional support64. |
| **Financial** | Regional budgets run dry, leading to funding gaps in local emergency wallets11. | High | Moderate | Diversify funding sources by combining NHIS claims, GHS operational budgets, and international development partner grants11. |

## **Part XVI — Project Roadmap**

### **Phase 1: Hackathon MVP and Code Validation (Months 1 \- 3\)**

* **Milestones**: Validate model quantization algorithms to ensure 100% offline edge execution on target ARM tablets20. Establish a functional USSD emulator to test routing state machines and Base64 SMS data compression protocols24. Secure GHS Institutional Review Board (IRB) ethical clearances to prepare for the pilot deployment13.

### **Phase 2: Focused 50-Compound Pilot (Months 4 \- 9\)**

* **Milestones**: Deploy pre-configured tablets and solar charging banks across 50 functional CHPS compounds in Kassena-Nankana and Savelugu9. Register 150 local Motor-King operators in the driver database, and set up receiving ward dashboards at local referral hospitals9. Conduct on-site training workshops and establish baseline-to-endline clinical data tracking28.

### **Phase 3: District Integration and LHIMS Coupling (Months 10 \- 15\)**

* **Milestones**: Expand platform deployment to cover all functional CHPS compounds across the pilot districts9. Integrate the receiving hospital dashboards directly with the GHS Lightwave EHR platform and national DHIS2 instances to streamline patient records15. Transition from pilot funding to local GHS operational budgets64.

### **Phase 5: National Expansion and Global Good Certification (Months 25+)**

* **Milestones**: Deploy Yoma Triage as a standardized, national clinical triage and emergency referral protocol integrated across all 16 regions of Ghana2. Transition the hosting and technical maintenance of the core servers to the GHS Central Health Information Management Unit15. Complete certification as a global digital health good to support replication across other low-resource primary care networks72.

## **Part XVII — Conclusion and Recommendations**

The analysis of rural primary healthcare systems in Northern Ghana indicates that reducing maternal and neonatal mortality depends on systematically resolving the second delay: the fragmentation of communication and transport coordination during emergency transit9. Traditional, uncoordinated voice calls and paper-based referral cards are insufficient under high cognitive loads and poor network conditions, contributing to preventable delays and negative outcomes38.  
Yoma Triage offers a practical, highly resilient alternative by serving as an intelligent coordination layer designed to align with existing community resources and GHS protocols14. To ensure successful deployment and adoption, three key recommendations are proposed for pilot managers and policy stakeholders:

> 1. **Prioritize Edge-First Reliability**: Developers should maintain a strict focus on offline performance. Core clinical calculations, risk triage, and data compression must execute locally on-device, bypassing unstable cellular networks to protect patient safety20.  
> 2. **Automate Transport Payouts**: Implementers should secure direct integrations with mobile money APIs to automate driver reimbursements. Providing instant, guaranteed payouts is essential to build driver trust and maintain active community transport networks17.  
> 3. **Align with National Digital Strategies**: Platform scaling must align with national digital health frameworks, integrating directly with platforms like LHIMS and the Networks of Practice initiative to secure long-term government support and sustainable financing49.

#### **Works cited**

> 1. FACTORS INFLUENCING MATERNAL MORTALITY IN THE NORTHERN REGION OF GHANA, [https://www.bibalex.org/baifa/Attachment/Documents/HJ8ZbaP68J\_2016102414221811.pdf](https://www.bibalex.org/baifa/Attachment/Documents/HJ8ZbaP68J_2016102414221811.pdf)  
> 2. Maternal Mortality in Ghana, [https://www.parliament.gh/floor?dis=167](https://www.parliament.gh/floor?dis=167)  
> 3. An assessment of hospital maternal health services in northern Ghana: a cross-sectional survey \- ResearchGate, [https://www.researchgate.net/journal/BMC-Health-Services-Research-1472-6963/publication/346437488\_An\_assessment\_of\_hospital\_maternal\_health\_services\_in\_northern\_Ghana\_a\_cross-sectional\_survey/links/5fc67a2f92851c00f844e7ed/An-assessment-of-hospital-maternal-health-services-in-northern-Ghana-a-cross-sectional-survey.pdf](https://www.researchgate.net/journal/BMC-Health-Services-Research-1472-6963/publication/346437488_An_assessment_of_hospital_maternal_health_services_in_northern_Ghana_a_cross-sectional_survey/links/5fc67a2f92851c00f844e7ed/An-assessment-of-hospital-maternal-health-services-in-northern-Ghana-a-cross-sectional-survey.pdf)  
> 4. A new modified obstetric early warning score for prognostication of severe maternal morbidity \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC9720996/](https://pmc.ncbi.nlm.nih.gov/articles/PMC9720996/)  
> 5. MAGNESIUM SULFATE, [https://www.ghsupplychain.org/sites/default/files/2019-02/MNCH%20Commodities-MagnesiumSulfate.pdf](https://www.ghsupplychain.org/sites/default/files/2019-02/MNCH%20Commodities-MagnesiumSulfate.pdf)  
> 6. accelerating progress towards MDG5 \- UNFPA Ghana, [https://ghana.unfpa.org/sites/default/files/resource-pdf/Ghana%20accelerating%20progress%20towards%20MDG5\_0.pdf](https://ghana.unfpa.org/sites/default/files/resource-pdf/Ghana%20accelerating%20progress%20towards%20MDG5_0.pdf)  
> 7. Neonatal mortality in rural northern Ghana and the three delays model: are we focusing on the right delays? \- ResearchGate, [https://www.researchgate.net/publication/349061486\_Neonatal\_mortality\_in\_rural\_northern\_Ghana\_and\_the\_three\_delays\_model\_are\_we\_focusing\_on\_the\_right\_delays](https://www.researchgate.net/publication/349061486_Neonatal_mortality_in_rural_northern_Ghana_and_the_three_delays_model_are_we_focusing_on_the_right_delays)  
> 8. Applicability of the Three Delays Model in the context of maternal mortality: integrative review \- SciELO, [https://www.scielo.br/j/sdeb/a/dtqQsfZDXp7BXVLzRkf74Qn/?format=pdf\&lang=en](https://www.scielo.br/j/sdeb/a/dtqQsfZDXp7BXVLzRkf74Qn/?format=pdf&lang=en)  
> 9. Upper East: KOICA Presents Tricycle Ambulances To GHS \- Modern Ghana, [https://www.modernghana.com/news/883018/upper-east-koica-presents-tricycle-ambulances-to-ghs.html](https://www.modernghana.com/news/883018/upper-east-koica-presents-tricycle-ambulances-to-ghs.html)  
> 10. Transportation: A Critical Component Of Emergency Care System \- Modern Ghana, [https://www.modernghana.com/news/883017/transportation-a-critical-component-of-emergency-care-syste.html](https://www.modernghana.com/news/883017/transportation-a-critical-component-of-emergency-care-syste.html)  
> 11. Why “free maternal healthcare” is not entirely free in Ghana: a qualitative exploration of the role of street-level bureaucratic power \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC11462662/](https://pmc.ncbi.nlm.nih.gov/articles/PMC11462662/)  
> 12. Community-based Health Planning and Services programme in Ghana: a systematic review, [https://www.frontiersin.org/journals/public-health/articles/10.3389/fpubh.2024.1337803/full](https://www.frontiersin.org/journals/public-health/articles/10.3389/fpubh.2024.1337803/full)  
> 13. Implementation of the Community-based Health Planning and Services (CHPS) in rural and urban Ghana: a history and systematic review of what works, for whom and why \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC10332345/](https://pmc.ncbi.nlm.nih.gov/articles/PMC10332345/)  
> 14. CHPS Operational Policy \- Ministry Of Health, [https://www.moh.gov.gh/wp-content/uploads/2016/02/CHPS-Operational-Policy-2005.pdf](https://www.moh.gov.gh/wp-content/uploads/2016/02/CHPS-Operational-Policy-2005.pdf)  
> 15. Ghana Digital TB Surveillance System Assessment Report.pdf, [https://tbassessment.stoptb.org/assets/docs/Digital%20TB%20Surveillance%20System%20Assessment%20All%20Country%20Reports/Ghana%20Digital%20TB%20Surveillance%20System%20Assessment%20Report.pdf](https://tbassessment.stoptb.org/assets/docs/Digital%20TB%20Surveillance%20System%20Assessment%20All%20Country%20Reports/Ghana%20Digital%20TB%20Surveillance%20System%20Assessment%20Report.pdf)  
> 16. Ghana \- Stop TB Partnership, [https://tbassessment.stoptb.org/ghana.html](https://tbassessment.stoptb.org/ghana.html)  
> 17. API – momo.mtn.com, [https://momo.mtn.com/api/](https://momo.mtn.com/api/)  
> 18. Mobile Money Integration Patterns for Web Applications: A Technical Reference, [https://pinuno.com.gh/article/mobile-money-integration-patterns-web-applications](https://pinuno.com.gh/article/mobile-money-integration-patterns-web-applications)  
> 19. MTN Mobile Money Open APIs: Driving fintech innovation \- Ericsson, [https://www.ericsson.com/en/cases/2023/mtn-mobile-money-open-apis](https://www.ericsson.com/en/cases/2023/mtn-mobile-money-open-apis)  
> 20. LLM AI Server with llama.cpp \- Apps on Google Play, [https://play.google.com/store/apps/details?id=com.micklab.llama](https://play.google.com/store/apps/details?id=com.micklab.llama)  
> 21. How to Run LLMs Offline on Android Using Kotlin \- DEV Community, [https://dev.to/ferranpons/how-to-run-llms-offline-on-android-using-kotlin-407g](https://dev.to/ferranpons/how-to-run-llms-offline-on-android-using-kotlin-407g)  
> 22. How to Run LLMs Offline on Android Using Kotlin \- Llamatik, [https://www.llamatik.com/blog/how-to-run-llms-on-android/](https://www.llamatik.com/blog/how-to-run-llms-on-android/)  
> 23. Perspectives of health workers on malaria case referral among pregnant women attending antenatal care in Savelugu Municipality, Ghana: A qualitative descriptive study | PLOS One \- Research journals, [https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0319567](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0319567)  
> 24. dhis2-android-docs/content/tech-guides/SMS-compression.md at main \- GitHub, [https://github.com/dhis2/dhis2-android-docs/blob/main/content/tech-guides/SMS-compression.md](https://github.com/dhis2/dhis2-android-docs/blob/main/content/tech-guides/SMS-compression.md)  
> 25. \#Viamo \- Digital Made Easy, [https://viamo.io/](https://viamo.io/)  
> 26. USSD \- Unstructured Supplementary Service Data \- QuecPython, [https://developer.quectel.com/doc/quecpython/API\_reference/en/iotlib/ussd.html](https://developer.quectel.com/doc/quecpython/API_reference/en/iotlib/ussd.html)  
> 27. USSD-Rootstock Architecture & Data Flow, [https://dev.rootstock.io/use-cases/onboarding-ux/ussd-rootstock-defi/architecture/](https://dev.rootstock.io/use-cases/onboarding-ux/ussd-rootstock-defi/architecture/)  
> 28. Boosting Emergency Care: NAS Trains Hundreds Under HOPE-MCH Project to Save Mothers and Children \- National Ambulance Service, [https://nas.gov.gh/news/view.php?slug=boosting-emergency-care-nas-trains](https://nas.gov.gh/news/view.php?slug=boosting-emergency-care-nas-trains)  
> 29. A scoping review of acceptance and utilization of electronic health records among healthcare professionals in Ghana, [https://d-nb.info/1387599828/34](https://d-nb.info/1387599828/34)  
> 30. (PDF) Usability evaluation of electronic health records at the trauma and emergency directorates at the Komfo Anokye teaching hospital in the Ashanti region of Ghana \- ResearchGate, [https://www.researchgate.net/publication/383279519\_Usability\_evaluation\_of\_electronic\_health\_records\_at\_the\_trauma\_and\_emergency\_directorates\_at\_the\_Komfo\_Anokye\_teaching\_hospital\_in\_the\_Ashanti\_region\_of\_Ghana](https://www.researchgate.net/publication/383279519_Usability_evaluation_of_electronic_health_records_at_the_trauma_and_emergency_directorates_at_the_Komfo_Anokye_teaching_hospital_in_the_Ashanti_region_of_Ghana)  
> 31. Viamo \- EWB Canada, [https://www.ewb.ca/en/venture/viamo/](https://www.ewb.ca/en/venture/viamo/)  
> 32. Utility of the three-delays model and its potential for supporting a solution-based approach to accessing intrapartum care in low \- Liverpool School of Tropical Medicine, [https://research.lstmed.ac.uk/ws/portalfiles/portal/22262372/Utility%20of%20the%20three%20delays%20model%20and%20its%20potential%20for%20supporting%20a%20solution%20based%20approach%20to%20accessing%20intrapartum%20care%20in%20low%20and%20middle%20income.pdf](https://research.lstmed.ac.uk/ws/portalfiles/portal/22262372/Utility%20of%20the%20three%20delays%20model%20and%20its%20potential%20for%20supporting%20a%20solution%20based%20approach%20to%20accessing%20intrapartum%20care%20in%20low%20and%20middle%20income.pdf)  
> 33. The operations of the free maternal care policy and out of pocket payments during childbirth in rural Northern Ghana \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC5700011/](https://pmc.ncbi.nlm.nih.gov/articles/PMC5700011/)  
> 34. Influence of Ghana's Free Maternal Healthcare on rural women's Access, [https://www.bibalex.org/baifa/Attachment/Documents/3irCyeODIF\_20251216155204199.pdf](https://www.bibalex.org/baifa/Attachment/Documents/3irCyeODIF_20251216155204199.pdf)  
> 35. The Transport and Outcome of Sick Outborn Neonates Admitted to a Regional and District Hospital in the Upper West Region of Ghana: A Cross-Sectional Study \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC7140801/](https://pmc.ncbi.nlm.nih.gov/articles/PMC7140801/)  
> 36. The Six Delays Model: expanding the three delays model with evidence from Madagascar for maternal referrals in LMICs | BMJ Global Health, [https://gh.bmj.com/content/11/2/e020936](https://gh.bmj.com/content/11/2/e020936)  
> 37. The Six Delays Model: expanding the three delays model with evidence from Madagascar for maternal referrals in LMICs \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC12918671/](https://pmc.ncbi.nlm.nih.gov/articles/PMC12918671/)  
> 38. Obstetric referral processes and the role of inter-facility communication: the district-level experience in the Greater Accra region of Ghana \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC10630038/](https://pmc.ncbi.nlm.nih.gov/articles/PMC10630038/)  
> 39. Full article: Does the national health insurance scheme in Ghana reduce household cost of treating malaria in the Kassena-Nankana districts? \- Taylor & Francis, [https://www.tandfonline.com/doi/full/10.3402/gha.v7.23848](https://www.tandfonline.com/doi/full/10.3402/gha.v7.23848)  
> 40. (PDF) An assessment of hospital maternal health services in northern Ghana: a cross-sectional survey \- ResearchGate, [https://www.researchgate.net/publication/346437488\_An\_assessment\_of\_hospital\_maternal\_health\_services\_in\_northern\_Ghana\_a\_cross-sectional\_survey](https://www.researchgate.net/publication/346437488_An_assessment_of_hospital_maternal_health_services_in_northern_Ghana_a_cross-sectional_survey)  
> 41. National CHPS+ Project launched \- Ministry of Health, Ghana, [https://moh.gov.gh/national-chps-project-launched/](https://moh.gov.gh/national-chps-project-launched/)  
> 42. Chief of Staff receives locally made tricycle ambulance \- Graphic Online, [https://www.graphic.com.gh/news/general-news/chief-of-staff-receives-locally-made-tricycle-ambulance.html](https://www.graphic.com.gh/news/general-news/chief-of-staff-receives-locally-made-tricycle-ambulance.html)  
> 43. An exploratory study of the policy process and early implementation of the free NHIS coverage for pregnant women in Ghana, [https://d-nb.info/1200782151/34](https://d-nb.info/1200782151/34)  
> 44. Referral Policy and Guidelines \- Ministry Of Health, [https://www.moh.gov.gh/wp-content/uploads/2016/03/Referral-Policy-Guidelines.pdf](https://www.moh.gov.gh/wp-content/uploads/2016/03/Referral-Policy-Guidelines.pdf)  
> 45. Completeness of obstetric referral letters/ notes from subdistrict to district level in three rural districts in Greater Accra region of \- BMJ Open, [https://bmjopen.bmj.com/content/bmjopen/9/9/e029785.full.pdf](https://bmjopen.bmj.com/content/bmjopen/9/9/e029785.full.pdf)  
> 46. (PDF) Audit of documentation accompanying referred maternity cases to a referral hospital in northern Ghana: a mixed-methods study \- ResearchGate, [https://www.researchgate.net/publication/359277425\_Audit\_of\_documentation\_accompanying\_referred\_maternity\_cases\_to\_a\_referral\_hospital\_in\_northern\_Ghana\_a\_mixed-methods\_study](https://www.researchgate.net/publication/359277425_Audit_of_documentation_accompanying_referred_maternity_cases_to_a_referral_hospital_in_northern_Ghana_a_mixed-methods_study)  
> 47. MODULE III: TECHNICAL INFORMATION FOR LIFE- SAVING MNCH PRODUCTS \- USAID Global Health Supply Chain Program, [https://www.ghsupplychain.org/sites/default/files/2022-11/MNCH%20Commodities%20Procurement-Module%202-20221028.pdf](https://www.ghsupplychain.org/sites/default/files/2022-11/MNCH%20Commodities%20Procurement-Module%202-20221028.pdf)  
> 48. Obstetric-specific compared to general early warning system for predicting severe postpartum maternal morbidity \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC12097397/](https://pmc.ncbi.nlm.nih.gov/articles/PMC12097397/)  
> 49. university of cape coast electronic health record system for health service delivery in central region, ghana edward agyemang 2024, [https://ir.ucc.edu.gh/xmlui/bitstream/handle/123456789/11984/AGYEMANG%2C%202024.pdf?sequence=1\&isAllowed=y](https://ir.ucc.edu.gh/xmlui/bitstream/handle/123456789/11984/AGYEMANG%2C%202024.pdf?sequence=1&isAllowed=y)  
> 50. Paying the Costs of Connection \- Digital Health & Rights Project, [https://digitalhealthandrights.com/wp-content/uploads/2025/05/2025-DHRP-Paying-the-costs-report.pdf](https://digitalhealthandrights.com/wp-content/uploads/2025/05/2025-DHRP-Paying-the-costs-report.pdf)  
> 51. Examining the potential of mobile money-based health insurance for people living with HIV and hypertension or diabetes in Uganda \- Frontiers, [https://www.frontiersin.org/journals/health-services/articles/10.3389/frhs.2026.1779532/pdf](https://www.frontiersin.org/journals/health-services/articles/10.3389/frhs.2026.1779532/pdf)  
> 52. UNICEF Agoo 5100 Reaches 10 Million Engagements \- Viamo, [https://viamo.io/global-health/unicef-agoo-5100-reaches-10-million-engagements/](https://viamo.io/global-health/unicef-agoo-5100-reaches-10-million-engagements/)  
> 53. (PDF) Impact of community health interventions on maternal and child health indicators in the upper east region of Ghana \- ResearchGate, [https://www.researchgate.net/publication/370370299\_Impact\_of\_community\_health\_interventions\_on\_maternal\_and\_child\_health\_indicators\_in\_the\_upper\_east\_region\_of\_Ghana](https://www.researchgate.net/publication/370370299_Impact_of_community_health_interventions_on_maternal_and_child_health_indicators_in_the_upper_east_region_of_Ghana)  
> 54. The Birth and Growth of the National Ambulance Service in Ghana \- ResearchGate, [https://www.researchgate.net/publication/311613405\_The\_Birth\_and\_Growth\_of\_the\_National\_Ambulance\_Service\_in\_Ghana](https://www.researchgate.net/publication/311613405_The_Birth_and_Growth_of_the_National_Ambulance_Service_in_Ghana)  
> 55. networks of practice in ghana: learning from implementation in two districts \- Documents & Reports, [https://documents1.worldbank.org/curated/en/099121924100565743/pdf/P176209-863e13a7-f38f-4b29-b52e-181f43978f70.pdf](https://documents1.worldbank.org/curated/en/099121924100565743/pdf/P176209-863e13a7-f38f-4b29-b52e-181f43978f70.pdf)  
> 56. Assessment of emergency medical services in the Ashanti region of Ghana \- ResearchGate, [https://www.researchgate.net/publication/284762635\_Assessment\_of\_emergency\_medical\_services\_in\_the\_Ashanti\_region\_of\_Ghana](https://www.researchgate.net/publication/284762635_Assessment_of_emergency_medical_services_in_the_Ashanti_region_of_Ghana)  
> 57. NG-SOS: Comprehensive Emergency Data Platform, [https://www.ng-sos.com/](https://www.ng-sos.com/)  
> 58. (PDF) A scoping review of acceptance and utilization of electronic health records among healthcare professionals in Ghana \- ResearchGate, [https://www.researchgate.net/publication/397846856\_A\_scoping\_review\_of\_acceptance\_and\_utilization\_of\_electronic\_health\_records\_among\_healthcare\_professionals\_in\_Ghana](https://www.researchgate.net/publication/397846856_A_scoping_review_of_acceptance_and_utilization_of_electronic_health_records_among_healthcare_professionals_in_Ghana)  
> 59. Status of patient safety in selected Ghanaian hospitals: a national cross-sectional study, [https://bmjopenquality.bmj.com/content/11/4/e001938](https://bmjopenquality.bmj.com/content/11/4/e001938)  
> 60. SCHOOL OF PUBLIC HEALTH, COLLEGE OF HEALTH SCIENCES UNIVERSITY OF GHANA, LEGON AN EVALUATION OF MATERNAL REFERRALS IN THE SISSAL, [https://ugspace.ug.edu.gh/bitstreams/ff08858a-b4f6-4c8c-a0d1-459759136528/download](https://ugspace.ug.edu.gh/bitstreams/ff08858a-b4f6-4c8c-a0d1-459759136528/download)  
> 61. Use of Maternal Early Warning Trigger tool reduces maternal morbidity. \- Semantic Scholar, [https://www.semanticscholar.org/paper/Use-of-Maternal-Early-Warning-Trigger-tool-reduces-Shields-Wiesner/ed5dc61636aef6b2f99838550865ff45ca5d87e9](https://www.semanticscholar.org/paper/Use-of-Maternal-Early-Warning-Trigger-tool-reduces-Shields-Wiesner/ed5dc61636aef6b2f99838550865ff45ca5d87e9)  
> 62. Digital Health Interventions (DHIs) for Health Systems Strengthening in Sub-Saharan Africa: Insights from Ethiopia, Ghana, and Zimbabwe | medRxiv, [https://www.medrxiv.org/content/10.1101/2025.04.22.25326213v1.full-text](https://www.medrxiv.org/content/10.1101/2025.04.22.25326213v1.full-text)  
> 63. What is the best architecture for integrating local LLM inference and RAG on mobile devices? \- Hugging Face Forums, [https://discuss.huggingface.co/t/what-is-the-best-architecture-for-integrating-local-llm-inference-and-rag-on-mobile-devices/174270](https://discuss.huggingface.co/t/what-is-the-best-architecture-for-integrating-local-llm-inference-and-rag-on-mobile-devices/174270)  
> 64. Addressing Public Governance Challenges in Digital Health: The Experience of Ghana \- Open Knowledge Repository, [https://openknowledge.worldbank.org/bitstreams/1cbe0514-3de5-4ec8-92e5-1dd193e51e39/download](https://openknowledge.worldbank.org/bitstreams/1cbe0514-3de5-4ec8-92e5-1dd193e51e39/download)  
> 65. How Website Development Companies in Ghana Integrate Mobile Money Payment Systems, [https://websysgh.com/how-website-development-companies-in-ghana-integrate-mobile-money-payment-systems/](https://websysgh.com/how-website-development-companies-in-ghana-integrate-mobile-money-payment-systems/)  
> 66. Global Repository on National Digital Health Strategies \- World Health Organization (WHO), [https://www.who.int/teams/digital-health-and-innovation/global-repository-on-national-digital-health-strategies](https://www.who.int/teams/digital-health-and-innovation/global-repository-on-national-digital-health-strategies)  
> 67. International Journal of \- GYNECOLOGY \- & OBSTETRICS \- Healthy Newborn Network, [https://www.healthynewbornnetwork.org/hnn-content/uploads/IntrapartumRelatedDeathsEvidenceforAction.pdf](https://www.healthynewbornnetwork.org/hnn-content/uploads/IntrapartumRelatedDeathsEvidenceforAction.pdf)  
> 68. Implementation research to improve quality of maternal and newborn health care, Malawi \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC5487969/](https://pmc.ncbi.nlm.nih.gov/articles/PMC5487969/)  
> 69. SMS-Based Medical Diagnostic Telemetry Data Transmission Protocol for Medical Sensors, [https://www.mdpi.com/1424-8220/11/4/4231](https://www.mdpi.com/1424-8220/11/4/4231)  
> 70. Binary SMS: sending rich content to devices using SMS \- mobiForge, [https://mobiforge.com/design-development/binary-sms-sending-rich-content-devices-using-sms](https://mobiforge.com/design-development/binary-sms-sending-rich-content-devices-using-sms)  
> 71. Mobile Money Payments on Your Website \- Faciotech Blog, [https://blog.faciotech.com/how-to-accept-mobile-money-payments-on-your-website](https://blog.faciotech.com/how-to-accept-mobile-money-payments-on-your-website)  
> 72. Digital Innovation in Pandemic Control Summary Report, [https://www.bmz-digital.global/wp-content/uploads/2025/03/DIPC-project-summary-report-1.pdf](https://www.bmz-digital.global/wp-content/uploads/2025/03/DIPC-project-summary-report-1.pdf)  
> 73. Evaluation of the Free Maternal Health Care Initiative in Ghana \- UNICEF, [https://evaluationreports.unicef.org/GetDocument?documentID=92\&fileID=25200](https://evaluationreports.unicef.org/GetDocument?documentID=92&fileID=25200)  
> 74. CASE STUDIES OF MULTISECTORAL APPROACHES TO INTEGRATING DIGITAL FINANCIAL SERVICES FOR WOMEN'S FINANCIAL INCLUSION, [https://www.afi-global.org/wp-content/uploads/2024/10/DWFS\_Gender\_CS\_FINAL.pdf](https://www.afi-global.org/wp-content/uploads/2024/10/DWFS_Gender_CS_FINAL.pdf)  
> 75. Mobile Money Integration for Ghana Websites \- Faciotech Blog, [https://blog.faciotech.com/mobile-money-payment-integration-ghana](https://blog.faciotech.com/mobile-money-payment-integration-ghana)  
> 76. KOICA CHPS+ PROJECT BEGINS COMMUNITY HEALTH VOLUNTEER AND SUSTAINABLE EMERGENCY REFERRAL CARE EVALUATION, [https://navrongo-hrc.org/koica-chps-project-begins-community-health-volunteer-and-sustainable-emergency-referral-care-evaluation/](https://navrongo-hrc.org/koica-chps-project-begins-community-health-volunteer-and-sustainable-emergency-referral-care-evaluation/)  
> 77. Feasibility of using an Early Warning Score for preterm or low birthweight infants in a low-resource setting: results of a mixed-methods study at a national referral hospital in Kenya | BMJ Open, [https://bmjopen.bmj.com/content/10/10/e039061](https://bmjopen.bmj.com/content/10/10/e039061)  
> 78. Implementation of a modified obstetric early warning system to improve the quality of obstetric care in Zimbabwe | Request PDF \- ResearchGate, [https://www.researchgate.net/publication/312348742\_Implementation\_of\_a\_modified\_obstetric\_early\_warning\_system\_to\_improve\_the\_quality\_of\_obstetric\_care\_in\_Zimbabwe](https://www.researchgate.net/publication/312348742_Implementation_of_a_modified_obstetric_early_warning_system_to_improve_the_quality_of_obstetric_care_in_Zimbabwe)  
> 79. Effective application of midwifery early warning in predicting adverse obstetric outcomes and reducing obstetric morbidity in hospitals: A systematic literature review, [https://e-jurnal.iphorr.com/index.php/minh/article/view/629](https://e-jurnal.iphorr.com/index.php/minh/article/view/629)  
> 80. Running On-Device AI Models on Android: MediaPipe, Llama.cpp, or ExecuTorch?, [https://meetprajapati.com/blogs/running-on-device-ai-models-android-mediapipe-llamacpp-executorch/](https://meetprajapati.com/blogs/running-on-device-ai-models-android-mediapipe-llamacpp-executorch/)  
> 81. How ussd works — Ussd Airflow 0.0 documentation, [https://django-ussd-airflow.readthedocs.io/en/latest/how\_ussd\_works.html](https://django-ussd-airflow.readthedocs.io/en/latest/how_ussd_works.html)  
> 82. An assessment of hospital maternal health services in northern Ghana: a cross-sectional survey \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC7690070/](https://pmc.ncbi.nlm.nih.gov/articles/PMC7690070/)  
> 83. Review of Health Facility Referrals for Severe Malaria in DHS Program Surveys, [https://dhsprogram.com/pubs/pdf/OP14/OP14.pdf](https://dhsprogram.com/pubs/pdf/OP14/OP14.pdf)  
> 84. Risk Factors for Child Mortality in the Kassena-Nankana District of Northern Ghana: A Cross-Sectional Study Using Population-Based Data \- PMC, [https://pmc.ncbi.nlm.nih.gov/articles/PMC6092989/](https://pmc.ncbi.nlm.nih.gov/articles/PMC6092989/)  
> 85. Empowering Frontline Health Workers through Remote training to Combat Vaccine Hesitancy in Ghana \- UNICEF, [https://www.unicef.org/ghana/stories/empowering-frontline-health-workers-through-remote-training-combat-vaccine-hesitancy-ghana](https://www.unicef.org/ghana/stories/empowering-frontline-health-workers-through-remote-training-combat-vaccine-hesitancy-ghana)  
> 86. NAVOROGO 2024 EDITION 2\_FINAL\_27DEC.cdr \- Navrongo Health Research Centre, [https://navrongo-hrc.org/wp-content/uploads/2025/01/NHRC-Magazine-EDITION-TWO-December-2024-For-Press.pdf](https://navrongo-hrc.org/wp-content/uploads/2025/01/NHRC-Magazine-EDITION-TWO-December-2024-For-Press.pdf)  
> 87. Leveraging Interactive Voice Response to train nurses on vaccine hesitancy in Ghana, [https://viamo.io/case-study/training-nurses-on-vaccine-hesitancy-in-ghana/](https://viamo.io/case-study/training-nurses-on-vaccine-hesitancy-in-ghana/)  
> 88. Implementation Guidelines for Networks of Practice, [https://p4h.world/app/uploads/2024/07/NoP-Implementation-Guidelines-GHS-FINAL-24-Launched.x69485.pdf](https://p4h.world/app/uploads/2024/07/NoP-Implementation-Guidelines-GHS-FINAL-24-Launched.x69485.pdf)  
> 89. Every African Country's National Digital Health Strategy in 2026 \- ICTworks, [https://www.ictworks.org/updated-every-african-countrys-national-digital-health-strategy-in-2026/](https://www.ictworks.org/updated-every-african-countrys-national-digital-health-strategy-in-2026/)  
> 90. Qualitative Assessment of the Livelihood Empowerment Against Poverty (LEAP) and Integrated Social Services (ISS) Midline Report \- UNICEF, [https://www.unicef.org/ghana/media/9416/file/LEAP%20ISS%20Midline%20Assessment%20Report.pdf.pdf](https://www.unicef.org/ghana/media/9416/file/LEAP%20ISS%20Midline%20Assessment%20Report.pdf.pdf)  
> 91. Inspiring future female digital health leaders in Ghana \- PATH, [https://www.path.org/our-impact/articles/inspiring-future-female-digital-health-leaders-in-ghana/](https://www.path.org/our-impact/articles/inspiring-future-female-digital-health-leaders-in-ghana/)

[image1]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACoAAAAZCAYAAABHLbxYAAACLklEQVR4Xu2VTUgVURiGP820sPyJghBcS5EY+BMSEbgpXSltIlok9CMiGIlSaiAYREEUoqCBeCNdSLWNFlKLKOgHpVAijRAsgmjlPup973cmz3xedbxdd/PAw53znrnMNzPfOSMSE5NxsuBt+BkuwklY4p/g2A9H4Qv4Bl4IT289w3AK7oJ5cAA+F72BgL3wI2x141K4APuCE9KlEJ6D20xuOQP/wItexoKZcS7gjmihPi3wF9xu8kjsgzfhO3ge5oanV5EQLarB5N/ghDdeFG0JnzrR/x4z+brsES3wA2wTfYVReCR6sRMm/wI/uWP2Js8ZWZlOUunyXpOnpAD2iz7B0zA7PL0hXBy82EmT85Uuu+Mq0XMGV6aTlLt8zOQhdsIrcFp09eWEpyMT9Gizl1W4jBbB4+7YFnrQ5eMmT8LGvQRfy+Ze8VpwsSXgM5gv+gDuwe+iRbDHa92xLfSAyx+YPEkNXIKdcIeZ+x8uw/eiC4ivlIuJxZIy0YKG3DjgkMvvmvwfvOtuOCd6gUwWHPBbdKER7qEsiP3sU+3y6yZfRTHsgTOwQ/QGNgt7OwFPedlh0QL8bB4+8cakXvQ8u7WtCfu0Hc7Ca6K9FpWgz5562Q3RfdPfyJnxE+t/rdh+PySNDZ8r9Bb8Crvg7vB0SnhTP+FZNz4q2p/89WF7vYKNbsy3x6cc/C8t2FN98K1E2xWOwIfwJXwsuu2kgh+Vq6Ktch82hWZjYmJiYjLCX5zvafwaSxDQAAAAAElFTkSuQmCC>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAE0AAAAZCAYAAAB0FqNRAAAC60lEQVR4Xu2XWahOURTHl1nmIWNJpkSR4UU8uCk8oLx4MiWJJDyQSB4UkpTkwQO6GSJkSpk9mDPPD6IUyvQgQpT4/1trf3d/+zvn3n0f7kHtX/37Wv+zz/n2Wvvs4YgkEon/gCHQdegu9BKaXna1hpnQKegadBDqXX65UBpBfULTaAtVQ8+gk9B2aLDfwIjNuwI+7AM0xeLh0BtofKmFshC6D3W1eA301ouLoic0FToHHQ2uOfaLDrDjIvRVyoscm3cFHK0n0OvA3wA99eJu0Hdomuc1hl5Byz2voVkMPYS2QT8lu2jdod/QY89jH+mttTg270z6iz7sauDPN9+90nMtHlpqoZyHTgdeUfDNySvaO+i2560U7f9Gi2PzzmSYaKNLgT/H/BkWc2QZ9yq1UI5AX6CWgV8EeUUjXaS8T4dE+19lcWzemXCOs9HlwF9q/jKL2TnGHEWfA+b3C/wiqK1oPpNFpzLfIkds3rlwbj8PPO6MvHmzxWctDou2z/xBgV8EdRWNO+Nh6JPoxtC6/HJU3rmMgt5DEy0eLTrXebNbOLltZxVtr/kDAr8I6iqag8ePO6IbSAfPj8m7VgaKzntu46uhBaI385fssbiHxQ6OIP3OgV8ELNqx0MyBRxT2szrw68q7XqwSvZkLJtlicXiYZKfp8/iRRTvojGinYsTRjyWvaE1F+81fR1/Rfv6SymnqE+adyyRoN9TK81h9HmQds0UfNsLzyBWp3LaLgkU7HppSM8CbPI/LBz2qo3kxeefi1qUxFreHfkCLSi30jz5DszyvOfQRWuJ5RcKinQhNsEM0n/Wex3WL3k3Pi8k7lxWi1eW5htNpl+hRgqdmH64L/OZsYvE86J78nTNaC9EvlAtS2c+Rop93blbwzMaD7jdorGsk8Xln0gxaJ7rd3hL9VMlboyaIvvbcGLZCncovNzjjoBuiBXPT7YXoetjGa1cFPRAtyiNop+ii71OfvBOJRCKRSCQS/zh/ALo6zzNS6r1PAAAAAElFTkSuQmCC>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFcAAAAZCAYAAABEmrJwAAADWUlEQVR4Xu2YWahNURzG/2YiJIRIikREISSdeDA+IG/yQuFGIUNRZMgDypAolBxjmTIUKdMDQvGikLFbppJSSkqJ7/Nf6551/vY565wH+8X61dc9+1tr3732d9Z4RBKJRCJKM6ifNSuwGSpaE/SADkG3oAfQgvLi3OkEdbGmYz3UO7juC50Orgkz2Q49hxqhU1CvsEIMVp4JXYPOm7Is+AV8g44Zvyv0GFrsrvtAL6GNvkJOMJABol/sU2hFefEfWkC/jH5CS8JKYD90HeoAtYH2QDdFnxFlqWgge6EfUlu4rMOG2HB3iP6vkAboM9TK+P8S9q47ou1jaFnhthTtIGzvB9EeO7mshsgc0fsXBh5DpseyuuDDYuFOgvZJds9tFH2xkImijRlv/DwYI5XDbQ69sKahKHr/NOO/g04YL0osXA6le1A3+TtczrVsyIHAIyOcv874eVAtXBIL94zo/bZHv4KeGS9KLFwOj5Xusw13pGhDOL2EDHX+YePnQSxcrgecYy9Db6GLUPegnAsz758SeITT3FfjRakWbkfR1d/PnTbcgmSHO9j5x42fB7FwGdB097md6Khk0B4/584LvGHOozoHfpRq4W4T3VF4bLhjJTvcQc4/Yvw8iIU7xFwvkvJpgNNgEboKtRf9AnZD71291q5eTTCwC9YU3f9dMZ4Nd6DoA7nYhfAF6O8yfh74cP1UFoMLV9Y7LIceii5inOa4oDHguqgULrcpHN4hNlzucdkwzlMho5zPDXsluC/mHrsW2ZFRjWrhbhUNqH/gFUTr24OEhdtQLnZ1wcA4qVvo86GVNN/V4+p7zn32TBWtY7czeeDDXWULRA8CLONW0TPDeTyREe6Fi9BsXwEMF60TejXBEC9ZMwPfS+0+d4voMTE8vayGPkq+hwiPD5dtsOyElhlvrWj9grv260U4JfIdG6XO9+HR7jt0Q+JHOx6X+dCTxm8L3ZXSwscFgL15blONfJkg2s5NtgD0FJ1m/O8E7DBvoKNNNXQR+ySl9o8TnW/5tyY4LO6LBuuH+WvRB/OoZzkLfZFS3UdSPuT5I8ka0eF0EJoVlOUFF6AnonOjbycXJP5OEMK9OUcqpwiWbxDdIYSMFh2ht0Xf3a49iUQikUgkEonEf8NvDjjij/s6PyMAAAAASUVORK5CYII=>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADUAAAAZCAYAAACRiGY9AAACcUlEQVR4Xu2WS6hNYRTH/96vRCmiOEkmMkAeGSmSjGQghRTlEQMykHsVNwOPkhKSUsirGJFHUUoGlFd5hOSRR4jyGBgo8f9b3z7n2+uefe6+59xuaP/qN1hrfWfvvfY+e30bKCj47xlBu/lkxCR6ml6hF0Mc051ugdVv0520T2pFJ9GTjqct9BOdmKpWmEff0ykhXkffIH0TTtJjsOZ607OwBmsylW6jJV9ogNf0Ar1Mf6F6U0PpN7ohyl2HrR8e4jkhHlxeAYwJueRGZDKS7qb7YT/qKNYju6kdsNqwKDebbo7iI/RDFAs9sZ+02eUzGQI72Qk63dXqoVZTT+hHn3Tco498knyml3yyLQbALugMnU+7psu5yWpqYMg/oAvoVdhfr4n2iNZ9gTXm0Xv4zCfz0osup+fpEtijbw9ZTY0KeV3cPthxdSNv0kPROq2p1tRb2EBpCJ30FGwA9HO1WmQ1NTbk9W4MivJrQn5ciL+jelNq6IVP5kXNLKYP6TU6K11uk6Qpv/doOCj/3OUXhvzWEL+i9yvlMu9ge1a70D6zEvYyawJp7NdDVlM6vvI3XF7vr/L6S4o79GmlXOYrbLvIhTa9ZfQW3Yj0/lAPSVOTfQF2wXddbhHST+ogbNLF9IWt2e7yrehPV8M+U5bCBkRHkDRVbaPUpNPmG0+7tbD1M0I8M8Sl8go7lnITolwrptFzdC7t4mqNsgnpi4zR95tGegvsvBrzmn57Qpygb71dUXyUHojiTuMwfQlrSP6A7UWrKkv+MJoep49hQ0HTz6M9cgXdC/s76unXu28W/HXondJ4zKO+vPX5X1BQUPDv8htZRI0IaveeeAAAAABJRU5ErkJggg==>

[image5]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAE0AAAAZCAYAAAB0FqNRAAACbElEQVR4Xu2XX2iPYRTHD/InLULNqLXEEkW4kt0pXCy1m13NnyTREi5ISS7UcrFWkmsX/kQUI8U2bvwvhVZcUQolXJEWN3xP5/zePb/zex87v9Ue1POpT+t83+dd5zzv3j8jymQy/wEr4GP4DL6FXVVHR9kKb8FH8DJsqT6clElwkQ0DPL16565hOfwMN2u9Gn6AG4oVQjd8ARu1PgY/BnUqFsIOOASvmWMVPL16566Br9ZL+N7kJ+CroJ4PR2BnkE2G7+ChIJto9sFheBr+pPJN8/TqnbuUJfAXfGjy3Zrz1WB2ar2yWCHcgbdNlorvVL5pnl69c5eyimTRPZPv0HyL1nxluW4uVghX4Tc4w+QpiG2ap1fv3KXwg5QX3Tf5Ac0Pas3Ncd1UrBAuab7Y5CmIbZqnV+/cUfjefm0yftvwyX1aD2ptG7mg+TKTpyC2ad5ePXNHWQs/wU1aryO51/nk45rd1No2cl7zVpOnILZp3l49c/+RpfAKyWv8KNxDcjL/ZM5pvUDrChc1n2fyFPCm9duQ6ut1rLnr4gjJyfzAZE5qbT8muWnO+ZVexiw4QNKUR776XmKbNt5eGTt3lHZ4Fs4MMt59/jissJ3kl60JMuYB1b62U8Gbdt2G5O/VM3eUyr3epvVs+APuLVYQzYFf4bYgmwa/wP1BlhLetBs2JH+vnrmjHCbZXf5+4dvpDMnrmb+aQzpI/o+bovUu+Jz+zjfadJKv/rtU2yfj6dU7dylTYQ/J6/Ypyb8qsft+I+wlediegnOrD0846+ETkg3jvxL2DcnzsCFYx4zVaz1zZzKZTCaTyWT+cX4Dj/7QgRDh8OwAAAAASUVORK5CYII=>

[image6]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADUAAAAZCAYAAACRiGY9AAACDElEQVR4Xu2WTShlYRjHHx+Nz2l2lAXZ2hEmq6mRLLGyU5SPKEsLU5KNUZNSU9OUBRFl4yNMjSjZWGBBkiTy0VAKC5SS+T+ee/Kex7nuuefchM6vfov7POfce/73vfd9XqKAgHdPNkzQRUUczNXFEImwCy7AVfgDptiueCE+wHzYCc9goa37SBashHNwXPUsRuEwSbhkOEUS8FlKYDfM0Q0fHMJZkoe9J+dQrXAd/oS35ByqguT+DKOWF6p9NmqO8NL3wV8kN8WKNgofyuSKnEMNwlNV4xW7g+2qHpZM2ANH4FfV84LfULySW7oIzuFfXYzEJ5IHmoTVMN7edo3fUBckwTQncFcX3ZIEG+AMrCVZ+mjwG4rvdQp1DI90MVo4zBjJBpCmes/hN9Q1OYfiQHu66BYOUwM34RIst7cjYoUq0g0Fh5rQRXAAN3QR/COZWVHBc6YJbpPsQLzte8FvqDW4o4vgkmRcuIInfz1cgd/IPh+8YIUq1g0Fh+JNSdNPstOZpJK853dVf8JH2AL/wDqSDSIWWKEiDUoOxScFTRnJ/TlGjd+LawVG7Qlf4DSsIjmDxZIOkgco1Q0D/gJv4Dw5fz6f9XqN10Pwt/H6xRiA+ySBWD4GLcLmx0sehvsySSDrOp49/F9JN67jGdlIcpzinyOvvte5GfDq4P8UL7kb+eTNx/+AgICAt8t/7Eh7k6QvLc4AAAAASUVORK5CYII=>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACoAAAAZCAYAAABHLbxYAAACGklEQVR4Xu2Vy0tVURSHl+aj8JFGQQ2EZpKog9IkMIJmNVIH4qCBgqaImBRGD/NBSTSIBumgRDRx4kBw4MDIx8iiAt8iKUTQQJTAP6F+6659r3svz72ce73NzgffYP325p51995nH6KAgKRzF1626mz4ClZYGXMeDsMF+BU2ucP/nzn4VzkGM6w5Z+EabDV1AdyBveEJiXIa1sMTKvdiHi7DA/gRtrvDIV6TNGrTAv/AdJX74hx8Cb/DRnJXJRqz8KIOFb/ghMpukqz+dZXH5AxJg6uwDWa6wzH5RLEb5bPJDb1T+RWTd6nck1z4nGQF62CqO+wLbrQBTsEVuASvWeNlJA0NWBlTYvIRlTucgvdJfpTfvjR3OC6m4Qurfkuy1bxLzA3ybrTI5OMqD8EHtxl+pvi3OBqlqr5E0kC/qXl1vRoNz/ug8hBX4W/YCU+qsWSRRdLAuqkLTT0YmSEUm/yNyiPwtj+Bm7CDjtdwDdyDtVaWQtLAvqn5DuWaL3ubcpM/U/kR8uFTkjvwAckfiJc+kof1WFmeyb5Y2TactGrmFsm82yqPCp/Te3ADPibZOr9Uk7wM9qVdSdJAt5Xxy/aDZLXD8PHbpQQufF4J/kb/hA9hjjvsCT94hg6/63y98S2wRe4O8fFahFWm5jFe5TuRGQnAZ6oXfiN/t8IFOETyzef7mL/zfKw0fF09gqPwPcluBAQEBAQkmX+IGmOzGXQM1AAAAABJRU5ErkJggg==>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEIAAAAZCAYAAACFHfjcAAACjklEQVR4Xu2XWegNYRjGH/suW7aSkERZcoNEJwqJUlKSpX+2UuJGbuTKhciSJIVSyBouZE+ylhS5kXIhW0LZkguJ5+n9ZnzznTnOd2Hman7169/3zDvTe77/zHvmABUVFf9gOF1Nu3rZVLrTWycsoZfoPXqKDs4eLpzYXlvRbfQZfUFP0oF+QR7T6O/A93SKX0TW0Me0r1tvpu+8dRnE9rqfXodtWAe6h96AbVBDptNX9C19Qg/QEZkKoB/9QRd4WWvYeRu8rGhiel0E26BVXqYNUaZjDdEuHwzDgOWwC40Jcu365SArkpheD8N6nR3kr+mxIMtQQ/OL74VdfFCQn6XfaMcgL4oamvd6GtbrzCB/Tp8GWYYaPU53wAbhB7oL2efpHOzi/b1MnHD5sCAvihqa93oI1tMsLxMf6dcgyzCJvqRD3Vof6jPdmFYAV5G/EbrVlI8M8qKI6TWZES1eNtZlsoeXZ+iG+q/Bo/QL7ePWF5C/EapTrq+1MojptQ1sTmh2daGd6G76BtZre1cXxVbYSQvd+ohbD0grDN2mynsHeZmEvSaspw9hd+1o2LDUZuSiZ+smvQ/7OkzYBLv4WrfWjmo9JK0wzrvcP9enO71Cr0U60U7LJbbXRvyCDdJcdJuo4Dvt7OUaRrr4HLde5tbj0wrjDr0bZEUR22tb2KMxPykg42A1flbHA9gw8dFE/kR7uXVP2MRdmlZYY5rE67ysaGJ61eDWh76YVgBbYK/a7bysjrl0H/7ust7df9IVaYUxD/YbQ8NIrKSPUN47hIjpVQNSr92L3XoybD7ob1M0aPQufgt2q+tD5zGDbocNT72/J/+FMonpdQKsx9v0DB2VPVxRUVFRUVFR8X/4A8Goqh2ZqsR7AAAAAElFTkSuQmCC>

[image9]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAE0AAAAZCAYAAAB0FqNRAAAC7ElEQVR4Xu2XaahOURSGl3lIxjKVJCRCKBH/CEnKHyljkkhCIkNCCklKhr+UIaJMKbMyK4WEKCRDCb9IosT73rXOufts53zfpu651H7q7d717vV9rda3z97riEQikf+EodBR6DJ0xmKfGaJrN6EjUPfscqk0gHr4pkNIrQOgW9Bd6CU0LbNahcnQO2iYxUuhN1CjNENkAXQf6mjxWtHPJHFZdIUmQReg495aQkit/aAP0ESLB0NvoTFpRgW6QJ+glY7H7v+EulncCfoq2tyEhtBraLnj1TWLoAfQLui75DctpFbu0keiG8NlM/TY83LZItog/oIJ46F1TjxHNGeg45GL0FnPK4svkt+0kFp7iebcqF2uYZ753IUVeSq6TSvBX9bdeQnHoM9Qc88vg6KmhdQ6SDTnaiZDZLb50z0/Q1vRpIfQVOiK6KO5Cmri5LE45nV2PHLY/J6eXwZFTQuplRcI/7+WyRBZYv4yz8/AL2ASD8ndUGOoDXQH2uvknbc8v5CD5vf1/DIoalporTzTntUu18BbljnbPD9Df9GkH1AHx19sPrcxOW2xX8gB83t7fhkUNS201uHQe2icxSNEzzjmbDAvFx7+THrh+ZxX6G+yeL/FvGldDpnvNrws2LQTvil/Vmsf0dmU48saaL7l8G8hTUWTbnv+FPP5yJLtFvvDJIumzys9j9bQOdGiQsRfP5Sipv1trWS1aE7yhBXCafie5/H2cHfaLIuHpBnKdfn92i4LNu2kb0p4rROgfVBLx+Ou41BcFd6UHG7d2zK5RUZb3E40Z2aaobv0o+j5Vx+waad8U8JrTc64kRbzAvwGLUwzKtBCdORYLzopcwzh7bnT4gS+uvA9Lnm1miu6Q+tjRmsmOvVfkmyNCSG1rhDdVfR4jOwRHUvyvi8X3ii8kp9Ar6R494yFtooetjug9tnlOmeU6PnLhnGXUM9Fz8NWTh6pViufrI2iYwY3CV/RKp13kUgkEolEIpF/mF9qp9GvyMhTVgAAAABJRU5ErkJggg==>

[image10]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFcAAAAZCAYAAABEmrJwAAADQ0lEQVR4Xu2YWeiMURjGXztR1oRQLmSJkD0hS1lKkSvLzd+WXEj2C0SRIpHIUjJCsmVJkjWhKDdkX2oKKUlRUiSex3vOOPM2M998Tb4b51dPnOd9/zPf93wzZxmRSCQSSaQe1M2aJegKNbCmowN0ALoB3YPmF5czpyXUxpqOztBF6DP0FNoMNSvq0Ey2QM+hPHQc6hQ2JMHmqdAV6IypeRpDA6D10EdoUFFVaQc9hBa5cRfopejfZAkD6S76YJ9AS4vLf2gBPYPmQW2hVdAv6HzYBPZCV0X7m0A7oeui75HIYtFAdkHfpXy4b0SfMh8AL6JUuNtEXytkoejDaGT8fwk/Xbehw6LXWircddAm4x0T7Z/ixjPdeEGhQ0Omx1oqvkr5cD0rpXy4edEbCxkr2j/S+FkwTMqHewH6JMXXNUu0/5Ab59x4sm9wvIWOGi+RWsLlXEt/n/EHOn+N8bOgUri8T9bmBB6nRnon3PikG08odCivROfoVNQSLsf0Ob2E9HX+QeNnQaVw20MzoPqBxw8A+ze4MRdmjicWOhROc1+Ml0gt4Y52vg23t/OPGD8LKoVr4e7nkWhwHZ3n59w63wT6OY9qFfiJ1BLucOfbcHs5389jWZImXO4afkDjA4+B56BLUHPRbdoO6J3o63IHVTUM96w1DT7cwcbv4fzdxu/j/O3GzwIf7jJbMPQU3etyQSvFEui+6CLGaY4LGgNORS3hco9Ln/NUCPvorzV+CPfF3OJVI/vNqEQ14bYWnQ7m2kIFfooudqlguOesafDhDrEF8AI6bbxJov12O5MFPtzltuDg3vsytCLwGDb3wKSh6LQwvVAV6S/6mqFXFQzXnlAsPtyhtgA2ih4Tw9MLL/y9ZHuI8Phww/BCOH/uMd4oaKv7v18veHjy8B7zkvJ+eLT7Bl2Tykc7PlW+4ThbAE2hO6L7RcIFgJ/m2YWObBkjeq1+axXCa2KN90s9EP0Q8CvvT2RcxD64XjJCdL7lv1XBE9Rd0WD5ZtRr0fmNRz1PTvSJ+R4elW/K398RPPyRZLVo/35oWlE1G7gAPRYNyl8vFyT+TuDhPfuaVfjB4TeUx+hb0CnRrWUkEolEIpFIJPJf8hu9dtzQEqg/BAAAAABJRU5ErkJggg==>

[image11]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADUAAAAZCAYAAACRiGY9AAACcElEQVR4Xu2WW4hNURjH/y65y4sxFIY3eUKGPM1EkifxQqkpyiXyKlGTKJeS0kxNSiIinhCjkHJ5cg1JksgllEKKjMT/P99a56y9zm2fM6cJ7V/96qxvfXtmfXutvdYCMjL+eybTQXHQsZjep9foebqJDkxkAIPpDnqV3qX76PBERj8xhM6k2+lHOjvRa8ygN+kY155Pf9OOXIZxkh6HFTeMnoMVWJZ5dDdtijv6wGvaTS/DBlqsqE5Y3wrXHkC/0m90lIstcTnjXFtMd7G5QawoU+kB2gV7qF5sRumidtJfdJlrq6gfsHxf1FH6wf32aMb03NYoXpJGupeegC2HvlKuKDEp+K3lqNwrQewhfRK0PZ/opThYCa1zDegsXY7CjzctlYry6P/pW7lNG4L4Z1hhMe/p8ziYlqF0Lb1AV8GmvhrSFLWFPoB9S63Jrt5nixX1lr6Jg9WiYk7DNoCRUV850hTlWQnLXR3EVGixolTQiziYFhXTRh/TG3RRsrsivqjmuKMEWn7f6TTXfkUf5btzvIOdWVWhc2Y9fQrbgbTt10K5oibSCVHsMCx/l2vfo8/y3Tm+wI6LVOjkX0Pv0G1Ing+14IuaE8XH05+wWRkbxPUClb/ftQ/BdrqQEbCcPVG8gNF0I70IW9PaIOqBLyo+KKe4uAYcvrjrLq5DVyx07aZchv0txWYFsQJaYPeupbADsJ60wwawIO4gp2Az4XdU7bLKPYPkEaK7np85cYweDNr9xhH6EjZI2QO7tG7Ip/SuBt1idGO4BduIVFh8+VWB62DXKr0EzX6t52bGX4e+KW2PaeyGXf8zMjIy/l3+AIpNiP4h225qAAAAAElFTkSuQmCC>

[image12]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACoAAAAZCAYAAABHLbxYAAABt0lEQVR4Xu2VzSsFURiHX98kn7FDKQsLJflaydfCSlmyU0iJyFehdMtCNtaWNyt/gQUbShYUKVIIsSQWSrHh93pndOaYmTsz192dp55u8/7Obd5zzr3nEBkMKaUKZuhFi3Z4BN+szyFnnHqyYQOMwWfY5EiFRngFO2AF3IJfcFYZE4kiOEjeq6PyCLfhLsnL3RrlrEd5zoF38B2WK/XA8JdW4TEcJlmtoMyTe6PpJNt9TbIANhsk40P9BEpJGjyD4yQzDotXo5nwycpqlPq6VZtQap4UwhWSFewnmX1UvBpl6mGXVtshGd+t1R3kwWl4AkdIZp0sfo3qVMMPeADTtOyHLDgKDyn6FnsRptFN+EByArjSQvIvnYO5WpYsdqPNeqAxAF9gnR7o8LYvwgs4Rf/XcJBG+TzlY8lvzB9K4BI8hTMkE0gGu1HeNTcq4Q1sU2qdsE959oV/p5PwHC7AfGccGLvRVj0g2TW+NnnbVXiherVaQorhGrwleWmBM07IMnkfN3H4SnJD7cFLkuuWx9f+jgpJGcm9zSsQ5FSIw3uSl7KfcB+OWTmf1XbmZpjbz2AwGAwJ+AYs1lpYpVxdMgAAAABJRU5ErkJggg==>

[image13]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEIAAAAZCAYAAACFHfjcAAACsElEQVR4Xu2XS6iNURTHl7cQIc/oJhQRRcpE16MYKZKBAXcgE4Wu7s1AxFghDExE3hl4pbxFIYk8JsqjW0yECCFK7v9/1/7OWd9qf84pnc9k/+rXOXvtfc+3v7WfVySRSNRJNzjOBwN94H74Dr6BR+GYXItyaIb34dfwuTpfXWElvAjvwlOwKV8dZzRcAq/CM64u4wTcC0fApfAz7IADbaMGMxM+h3NFB+Ek/APbTBuyFj6Gw0N5K3xrylHWw6dwH/wl8UTMg7dEZ0wGH8ZO7DCxRsOBWmTKnKUcjO9wWIhxoH7A5Vkj0F10Freb2F/5JvFEbBJNUquJcUSYCHakDPgyXA4v4CAT53JlP7Ilwk+Wp1VaKNfgJRcrpCgRG0V//KCJDQ4x7hll0BO+F33mBBPfGWLrQpkzm+WxlRbKadFE9nXxKEWJ6AVbJL8fNIs+8IaJNZrpcL6LXRHtx4JQZv9ZHllpoWT7yXgXj1KUiBjZlLRrtmx4wv2Et6W6f2WJ8Yk4FuKTXTxKvYmYBH/DLb6iZA7D15I/xi9IPBE87hmf6OJRmIizPujoB59Ifr/4H6yAH+FUFz8i+sKjXJzHP+NDXTxKrURw+h2HB2APVxeDe8pl0WOvHmfrn9WE94kOOMtXgN2iL+wvhnwvxnn61ISJOOeDhm2iP2h/bJf5XgY8DV7COSbGew4vhKRF9IVnVKu74D5yx8UKYSLO+2BgmeiVtr+J9Ra9aJUFjz72gcvCshkuDt95rH+Bq6rVXf38ADeYWCG8pfFGdl3yN0gyRfRK/VB0Cj8Q3aS4Y3NNlsUh+Em0DzfhM9EX5AzgBp7B2cH/MbLluwY+khp3CJ7L90STwB+kr0QfNiC04TU6q/NuD20aDfcb/2wrR92yULTfHKg9cEi+OpFIJBKJROLf6QQGYaQUf4QiygAAAABJRU5ErkJggg==>

[image14]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEIAAAAZCAYAAACFHfjcAAACK0lEQVR4Xu2XTUgVURTHT5pfFGaBiyBFwUVCFH6UBkp+LFwJ6iJoGYGLoFbhJrAEW7hp00Zo8xAXLl2IqKUoBEGBBi4EC5Ra+UEtBEE39T+cGed4Z8a5D3pvXNwf/JB7zn2XM8c7795H5HA4EngAv8AD7++T0+kQ1bDQDOYJm1oHYaMaX4ZjsEXFQjTBTdgBb8Ap+Be+UHOYYtgAX8N92Hwqmx9sa1304toJkmeI5QPsUeMSuAUPYaWK/4KzJPN54TQaYVvrElyDf+A8fK5ykRSQbLHv8IqKj5M8bNS2G6J0GpFNrR9hjRonchHukSxUp+JvvdgzFfNJqxHZ1Mo7p0aNrbgDu4zYAsni3UacSasRjG2t3IjHcBp+g6vwvspbUQuP4Cd4wcgxaTbCJK7WGTiqxu/gNrymYonwt+tPkm/lKM5TI+JqvW2M60lqfmPEY3kEf8NbZkLhN+KumcgzNrX6XCKped1MRMFn9BYlP2A2jSgnOb74nbWxVT6WyFm1DsAd+FDF+LXhmndVLJIq+AO2q1gn7FNjH78R98xEnkiqdYSkvldBmiq82GcVC1FKclXlraZ5CXuNGOM34szrao6wqbUfTsKiIE1tJDUPq1iIDMkNjLfmMtwguULzB2+ezArgxTgXdbTmmgwl18qvwRwF/yi+iPEpwnPLvFgIfod5kTj13TxDcgT5uWO4Ap8GU3JKNrVeh+9JfnN8JTldrqq8w+FwOBwOx3/hH5i6n6OkNcYUAAAAAElFTkSuQmCC>

[image15]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACoAAAAZCAYAAABHLbxYAAACCUlEQVR4Xu2VS0hVURSGl4VWauILnAhKEQmB4lDwcc2BAxWSJuEkkEASGhSIkIo6EARTB4IEaSKKjnzMHAT2QhQxqCYOA4UGOagGDlTE/p99D629vY9zDzo7H3yDvdbmsu7ea+0jEhJy4VyDr+EvuA/nYbG1Q+QO7IDZKlYLx9T60lmEE7AItsK/8AfMUXvuwzNH/rEatedSqYcfYZqKdYopZETFGsSc9k/4Hb6Bd1X+HE3wM6xzEwHphsfwuYrx2lkoT9WDJzql1r6IwPdwFpZamdR5IaaoGRXLi8Z4tR4RCVCoRxvcEnNFBU7OL+nwsdj9yNtioesqFhHTy6NwDR7AcbFbJinV8C18JeenNQh8AVhoo4pVwT14K7q+Df+IaZ2UqYRLcA6WOzm/lMFT2OfEb8ISJ8ZnjC9EoRP3DadxGa7A604uEZnwm9j9mohhMSf/yE34gYPAH+AgDIn/HuK+BTgNr8bIfYCb8IqK94op9JmKJeUG7IJfxfRNvp1OygBcFbsQDgvJENMOh2JO3YODxUKbVSwunNqnYq6MTw0LTpWHcBtmqRiL44fAg/kKtSac/t+S5FD4fX4Cd2CP2M9LKtwTMxBf4Dsxv8fpPhIzlB4tcFL+nyi/8ydiaohLO9yFLyV4gR58g3l9sRxU+wiHhm/rJ7gBH9hpG36b+2GumwgJCQkJScg/ZNdkCnNuGYEAAAAASUVORK5CYII=>

[image16]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADoAAAAZCAYAAABggz2wAAAC3ElEQVR4Xu2WW6hNURSGf3eS+11JSCIkcsmLU4qUBy8i9zqkpIjIpRBF8iKX8kBOIUJ4UISUcsv9WnjwgAeiiFBK/L8x19ljz72cvfbZ8rS++mvPf42117yMOeYEcnJyItpRddQL6iy1jxriAxyjqRPUZepcaGdhLiz+OnWc6lv8+P9wFNaRBA3iK9XPeWI69ZYaG9orqDdUs/qIdJZQD6juob0B9j9Juyo6UAtQvhM9qV/UE+etCt5m5/WiPlNrnHcDFtfHeTE9qO+wSUpoSr2GfafRdKO2UbephVTL4sclaKDvqDvOWwsbwHbn6be83s6bQm107TRqYe8Nj/xL1PnIy0Rn2AAfUkupVsWPG0ST09q1tQfVuRrnPafeu3ZW9iB91U9RX1D83QZpT22BreBMWFpUw1TqB7XYeR1RSO9Z1BVY2mrlW7i4NE7D3lXmeI4Ff0Dkl9AGVgzuUYuo5sWPK2YYdZL6BCtObd0zdUadUgHZC/uWaoAm96CLS+MC0gd6JPiDI78ezaBmW2W60hTNgo6au9Qj2EqKobBO/aS6BE8sC/4I58XouEob6OHgD4z8esagULEy53eFTIN1oi60VYDUfpkEBGYHf2vkew7BYlS1Pcoa+X7iSlDarqOeUstR3YCVhloRn/r9UVhBpbAqt9o3XYyYEXyl89/YCYuJz+Qzwc9UUzpR66n71ErYBFRK0pEdzlM6yZP0DaFaoO945qD8is6HxYyM/KvUtcgri/ap9ouqoiqhLyTl2I/Szk4O3i3n6X91YfBVVtmkuInO0+DHu7YmSu/Nc54y5AOsz41CxUMHu/bSalhhKccoWDVNZlxnqi4P36gJSRAsWzSRm6gmsG+p6u4ObTEONvCPoZ2gPa/imdzSdEooO6rZcn/oCuuQViRLVa6BXTR0H31MHaAG+YCAUlrHwjPqFUpXRNc9rdTFyBeTYNtDxWkX7IKTk5OTk5OT84/5DZf/mKQeuYFOAAAAAElFTkSuQmCC>

[image17]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGIAAAAZCAYAAADKQPsMAAADwklEQVR4Xu2YWchNURTHl3lOxsy+J5mTlBf0ZXgQIjwQmUOJB2VMChkyRURKZCiZMmQoUxkeRGYZkpQIkbEIifVv7fNZZ9n33n0/3cvD/tW/7vmfffY9a+9z1l77EEUikch/TX/WDdZ51jHWdFbFVAuhGms26xzrNGslq1KqhZ/KrMUk111jrWbVSLUoDiFxPmK1Ml4oLVgnWB9Y91nLKY84u7Auseq6496sn6wNZS2EOiQDuZNk8BuT3PRU3SgDe1i7SSakOusoSV/FJCTOms7LpG2/m/5BbdYD1iRWA9YckmsQaxAbSS4Y4Y4rsD6xPpN0noCn/w3JWwEGkly3payFn8Ek7TBxCe2d1115hSYkzg6ujU/fWZ1dOx8LWUuNhwcQ1w4yvpclrB+soe4YN/iVpIPkBuuzvrA2uWNQiyS4jsrzsYP1ynh4M/Cf841fSELiHMBa635rkI7tIFuQ6t6yeipvFEn/GIMgWqrfeIVx8RnljXXeDOWFcpskX1resU5Zs8DkinMIq1QdAwws1sNcuf4QSX8TlIf+4O1TXhDIn8hpV1mNlL+GpMPJrCOsC6wDrG6qTSbek0yG5SXrsTWLRKY4LVjPbrGa2RMekHpHUnrxX0AybouUl5O5JH+KnFmaPkXbSTp8yGrnvDGsj5Q7NeE630Q8Zz2zZhHIFqdlHuVeAzOBguYuybra1JwLIslr+hVLFh2dP5FjX7P2K88HAvZNBCbhiTWLiC9OTVWShyXkrfeB6gkLfF97Ih/wymJxbuuOsUj7bvoe6xulqyvLU9YdazIvSPYU/xIbpwaxYiDtPiME9Ie9BCY7GGxC7KuDehkDv8wdo+LAsS3D8KTDt9drrpPsNyy4USyCmehBcj5E2ERlexhASJya46yb1gygHklKmmhPZKMJyazjqWiofJRbOhUNc8fDy1oIqIbgo5TNxFaSCkmTbJxWGL9QhMaZgPyO9e+k8XNRhaQSnKU8TAz2GFkpIbkRDJTecKEqgo/NGMDAoQ0WugSsEViI9A4ZJd5MVnPl9SPpq7XysJGD11V5haSEwuJMSErbg8ZP8MUJ1rE2G68Xa5XxvOwleWqxyQIoUXEThymdH8eTLK5JLT6OZMHtlDQg2fj4AsC3Jf3U7aLyVyPlJTROkHw1QJHiwxfnaOeddUJlhnUQm0j8V07wyWI9ye73CusiyYW+j3nTSGp/5E7k5pLUWfmohj+2ryICnUKyE8dgIBAbfKHJJ842JGkMT70PX5yXSSbCpz6qXSQSiUQikUgkEon8Nb8AVn4F1yXiA0sAAAAASUVORK5CYII=>

[image18]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGIAAAAZCAYAAADKQPsMAAAC6ElEQVR4Xu2YS8hNURTHl/cjhULefQNJSAaYoL6kEPKYUJRQiiJJYiIRoiivgZIYSAZK8kikPAYe5VFGGJgoJIoiJP7/1t7uvuuce797Yu8M9q9+dc/a++y717nn7L3OFclkMpn/mjnwMbwFL8H1sHNdD5EXcKSJtcooeAPeg9fgXtivrkcaYuY5RjS/nrahVSbCu7CvO54Bf8Ejf3qI9HaxRp6sdS3Ac5/B0e54AHwvekE6+U4JiJ3nbCn2D11Z61rOUdGOS90xL85n+AX2cbFxrk+ZP+AE16+MJaL9jgWxiy42M4jFJnaea6V4jvel6I/clF3wJ1zsjjnBb6ID+AnOhQfd55AtcLcNGninMInw/Cui43PcVMTOcx9caGJd4AU4y8QbMiL4zEeYk+Oa7uEXtAfHZDq8DnuZeBnh+JzcG/gODgziKYiZ53Yp7nvbRPfDynD95LLxUJpfJG5IT+FQ29AB3eAO+BZOqW9KSuw8yVjRPYk3XiW2in4p18z2+qYC/KWP22AHLII34Xe4WYrVSipi5+nh8rvcBquwTPSRXWUbHN3hazjJNrTIePgBnpG0VZMlZp5c9rj0drUNVeEj+1W0NrZw4tx8/+aO5obY7CKkIlaep0T3lUoMh0NMjPUyL9QeEyeX4RMbbAIrEpaFIaypOf4dEw+ZJppMK3IZ8JVPI2Ln6eFTwLL4sG1oxmDRX513BV+0PKdFJ2hLOW48n+BVE2/GI9Gx5gex1S7GOzIFKfL0sAjhmNxfWqZN9KSPcFAQv+3iC4IY8SXfeRP3sMTbBIcFseei5/B9wsOanLEDQSwmbRI/T88G0XM32oaOOAdPSG1jWSM6EF9E7Po4z7WdNXEPX3xsAuvgfamViZNFN2u+bYZ3Z2xi5+nZL9rGvCvRAx4Sre0fiK7bnGRZ/cv/i/h4824og3+q8e2VLzchnNQr0R+ES9VO2D/skIAUeZIVoudOtQ2ZTCaTyWQymUwm86/4DTNZ7WG3XJEAAAAAAElFTkSuQmCC>

[image19]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADoAAAAZCAYAAABggz2wAAACXklEQVR4Xu2WTYhOURjH/76/IkMiaXwUyhj5WkjktVJY2NiIjURWajIjpmZKEZEsLCg0UixmsDFZTI0FRaJ8laJYKaRIoUj8n55ze8997r3vnHslm/OrX2/v/znvnXPvnPOcC0QiEcNE2kNf0pv0LF3kDyC76RmThfKKNtvwf3CV7vC+D9KvdK6XHaW/GzivPjTFeGTH+l6sD/23zID+wede1u6yw152xWV5yoMqogXZ8Yk/6ZL60DSb6B26zhYqIjf6nj70soPQiRz3srt0qvddkN8+cJ9FyHxP2ZB00CM2tNTobXqJzklVqjGNjvW+90JvtOZleZO9RTfa0LAF6esIa+kAHWfyQrbR+/QEsk+7KpvpD7rHFgw7kX/zQyEP9AmdaQshrIFu6pN0lqmF0kr76GfonpuQLqeYBF3us20hANkW52xYlmX0Gr2MBpt8COSoeUSf0smmlrCP3rBhAKPpW7rSFqqykF6HTsbfe6HIvpI92mNyYTh9TbtsIQBZ7tJp5Rp/TRM9Rj9Au9qwdDnDSLrUfSbImSg3+gvZJbza1baaPIR++tiGZZEOJuefXOgAnZIuF3IaOnFpaAnzXSbKg/PZ73LpC2UYQb9AO3UlRtG90E7WhhIt23EeOnF580nY4DI5Iy3J0bPcFhzbof91i6wa+Z30kFKMobugB30ntBNWYQV9h/rE5UyVa35D/kvJPeiEF9sCWQWtfbIF6LEltUZvURlkU7+gh1D9Bn1q0BUhy/4ZvQBtaHnICniD7JIWptOP0JcBywL6HbrqglhPu1Hc+iORSCQSiWT5A5e8gcL3Eat/AAAAAElFTkSuQmCC>

[image20]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAZCAYAAACPQVaOAAADK0lEQVR4Xu2XaahNURiGX/M8D0WGhEKEZMo8FCncIlN+kDFzpkxFUYYfkiFDyYmISPkjISlDGSJFMt8MfxBFKT/E+/atde86++5znXPcrk7tp57uWd/eZ5+1vr3Wt9YFEhL+J63oQbqPdotcC9lEu0SDlUEVuos+o8X0DG0d3uAYRu/S7+7vnPTLqE+f09G0I31P17i4qEZH0nP0vItVOofoVVinatG99BosCZ4+sIEMp23oafqbrg7umUsfBu3NdAc9Qk/SO7DvKQl6RoXRiM6CZbM8ZsA6PT+IadCK6ZrnCh0TtJWUN/QHbeFih2H3eSbA3mzIYrooEssb/fB2eg+W6Zrpl8uQgg1sXCSu7OttiKqwqfsClkSPZoS+66fzftgM8UykK4N2Z3oT6TMmL5rCBvmILoFlPhvOwjocvjXxkj51n6vTT7D7OpXcAex2saWurdnxoPQyttCx7rMGqKXRo+RqHjSkW2FvchrsLeTCUViHfac8n+m3oN0TVlxCLsO+O8q1G8OSNJi2pLdQuow0y9TPvKgDmyLK5DxY9vPBr9nZQUwDU0xqAHF0oD9Rdlr2hiVBhai9izWDDby2vylbatAF9DZym66ZUOZT9BKtB0viHvoBNthMa/44fYvsquoBWBX3LKQX6OQgFks/+g5W5XLOVDmsoPdhRUnrSgVKA45jOv1Cu0cvxKD+auvxbIMVNtWYY3REcC0WZX8DfQLrZEUO2vMLVryiaL/VltM3eiEGzULNmCaurUquqj7QtdvRU+7zX9FDNsI28lWwJOSK1nqKTgpivWBTOIyJtrACNCSI6c0UBe2QdXRq0B4Ke27XIKY1nxNat8vpY7oetvayRT+sDlwMYppqxbA349Hs0RFRUzhEyR4fiQkVsOiRcADst8Izs7ajvFDl3Elf07W0QfrlWJSYj3Smaw+CrVf9DUnRr7AT0nXYHqztSZ2PO9BroJoJIXVhy8M/W9VaVfufaA7b0PUmsqnW/ekJegN2SI/+t6K93G9FcUYr9hS6LBLz6CCi39J2pT0+uncXFJop2lYyncm1NHSsfIX0s3fBEp6fExISEhIKlj/4p5srcxldIAAAAABJRU5ErkJggg==>

[image21]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGUAAAAZCAYAAAAonOB1AAAEUklEQVR4Xu2YacitUxTH/+Z5nsscmWXKLAkhKVNS1xDKTEhkvMZkypghuTJPZYjMw0XmmfCB3JvhAz5IkpD4/1rPPmedfc+5Lt7nvF73/OpfZ6+9Ts9ez7P3XmtvacSIEePHZtZ91pnW0lVfYWHrOmuuumOC0WqsG1ivWu9Y061JPb3BfNYN1rfWl9Yd1oo9HtKm1sfWytaeCr+91R0QA9xX8ZwTGtuwWcJ60PpAEcvF1rw9HtLh1iapzbjx2yLZWo11Xes7a4+mvbH1tbVzxyO427rGWs7ay/rBmmYtmnxus65K7Weso63brQes16x7rVf0D2bOGLCQ9bp1iTWntbw11To/+cCz1h+ViC1/vNZincP6yPqqsl+kmAWFHawXFP4FBsBgL022T6yzUvsy9c4uuMvasLINi+sVY1472XazflfM+MJz1rvW99aT1vGpr9BarGsoBvlyZT+isbOK4FTrV+vEjkdsXfiwWgpsCZNT+3LFvls4TPHBx4vPFWNmxRTWaWxHJhuzftXU7kdrsW6kGNCLlf2Qxn5A0z6pad/S8Yi9GRv7coGle2VqP2Ut1vxmq3jTWqDbPXTYphnz/Mm2emO7Mdme1l9/lNZiXU0xoJcqO4kJ+8lNex7rYPXmj+0VPiz1Ast3mrWUtaN1U+ojiJ1Sezz4VDHm/LJI6NgeTjY+ChPzIes9RbLeKvVDq7GSUz6rbJR5DJQlOQgqMXx2qez7K5LnterOSD7grcVhHCk5hdVROK6xvZFsj1oXpDYFznRryWSD1mLdUrEFlZe7tSLHMNDzilMFiZLkmBPdIOZWrKZSxy+iKA7uUVR6w2QZxbZyoaL6Wsm6UxHr88mvTs4l7/C/mTGmsa5l3a9YthyESHoMIie/woLW++rNLzODfHRg85vqbap1qKK0ZtskNw0TXtQVilKVlcOkJFY+ziAoDPD5sO6oaDXW0xWDoBDI8CDKvJs1a7U3OYuavcA++6NilgIBHNXtnoFtFRNlVvSY4sD2d9lOEWspezkAfmPt1/GIuPHJRU3Nv421h90VByFWQIFVQ4KrOUeR/MqDgFk3iEesVVL7DPWeidZX7NfDYk3FIZgbjAIf4zdr2aZ9ruIDTO54SIs3Nm49BjGmsXJdwgO3adqUdb9Yx3Y8gn0UyTDX+JxwOVT2Y5JiOWdOUdwWFBgoSXJYlPPXacnGcYCTd4HbCt4JFWeBFcv/zk62zJjHysGQVUH1QMk7RZGY8ul9PcW1ytuKreIt6wvFx6P8q2FmPa4Zt7hdrZ+S/SDrmG5361DW/qw4NPPSuZXgEEgBUCDuJ9Q9nbMrUI1xgu937mglVgZHVUEZTGXCcs7bE1BBMFP6ieVewzLlwq6GZ5FgmbFslyS/usxsGw7ErAQm1tXq//wVFOcO7sB4J2zvg5L0fznWDpsrblQHwR0T+y93S/2CmUhMmFjZBrnmnx2YnWIdMWLEiBEjRoz4H/InUCISIABsS5cAAAAASUVORK5CYII=>

[image22]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADsAAAAZCAYAAACPQVaOAAADOklEQVR4Xu2XaajNQRjGH/uerYgsSQoRPtgie1k+kGyFFCFRSBFRbpHtg6xZSq5EtpSyhZQQIr6QJXSzlPCJz+J5vDPue+aeezqO6yLnV7/uf96Zc87M/GfemQsUKfInaUP30J20e1LnWUO7psHqoAbdQp/SMnqctvUNHH3pSXqVXgjlSGP6jI6inekbujzERS06gp6ip0Os2tlLr8A6VY/ugA1Gk+CZQt/R/qG8DDYgDULMpQ/Cs1hLN9H99Ai9Q4/BPtPOtauUgXQj7ZhWFMh0+pXOdzENWjHVRbQ8P9GVLnYL1q59KO+jl8urMR72Zj2L6MIklpNOdDtsb+TaF/lQCuvwuCSu2dfbiGyGtfPLeyzs7UV2wVZIZALs7Ue60BuouGLyojWsE0dhe6EQtP80iNFJ/Dl97Mrazx9cORtaHfdduYSOCc8aoLZGzx+1BdKUrqBn6DRaM7M6Jwdgg42dinyELVvRDNbmIWxpX4Mt4VW0TmgT22mSBtNW9CYy9/O68FwlKLlods/R2bR2ZnVW4p5V+0ivEJMagDKrnpWcdsO+VxN8lx4Mn4n0oZdgiSjmlZawgdePjaoSdeYEfU0bJXUpmvlSehHWtgHdRt/CBliX9gjPX2AdjywJ8d4ulg1N0DBXXgBbhZNd7KfRIGfRR/Q6Ku7DXCyl92BJSftKCUoDFkpKGtTLUI7MCPENSdzTD3b0RNbDjroWsFUx3NXlhWZfs6Ukcgh2PP0qeotKXkLfr0HdLq/+jvKD4npz2dB+1oppHspa+p9R3r8OsOSaF1qC82BvZDUsKfwsWg2ldJKLaVlqED6mLOsvDGImcr9ZncmakMgQWPtuLqajKCdNYIezrmtzYImpUPTD6sB5F9NSK0NmplXmVXb2MS19fXaki0V0F0ivhANg7f3dQMdRpQylZ+lEFHg4JygpvYe9JTEItl/116PEpaOnBPa7ytLKxrrwZ+uHBhpvVpGGsO0Rv1vZWlm7WtFd9zAsqemSXtmtTDcgJbAn9BUsG2djKl2cBgNbYb+lCdIZX+hl6K9AK0XHSrxMpGgb6Fr5Apl3738WZd0qQXtW/1nko5LOb7m1FClSpMh/yzfpIKObxOB5VgAAAABJRU5ErkJggg==>

[image23]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAmwAAABKCAYAAAAG/wgnAAAElElEQVR4Xu3dWajtUxwH8GXITGa6IZkyZChSxjI8yFCGF5lnUjxxy5UpyjxTyDyWJJEUCUUZMySUSCjkgfskPLB+rf+/s/Zy7j575+xzbud8PvXtrv9vndPt7Kdfa639XykBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAgvFkzsM5S3PeaOYAAFgJLMn5oxvfWU8AALByuDVnWc6mOctzNhqcBgBgvv2as3rOUalsia4yOA0AAAAAAAAAAAAAACx0Z+f8k/NbO9HYIufMnNtS+fkIAABzpG/A4luhozgl56dUXvkBAMAcODRNNW0HN3PDvN4WxrB9zhptcQaXtwUAgMXkulQatm/aiSF2agtj+KgtjOCrnP3bIgBAiEZmm258dfe8EP2eyt92bjsxAWe0hRHEqtxC/ewBgP9hz5zLqueL0sJuGh5I5e9bp52YRae1hTE81hYAAC7J2aMbr5/zc85rU9MrlY/T1Fm06TKKDVP52fvaiTG8nMpndEw70YlvmtZOzXklZ5Oco3O+HZwe4BwbADBg3Zw/q+ebcjarnlvR6ETDsyK7toXKdCtacV5rWPMyKQ+l8rfEfaLjujRny258bFU/rhq/UI1DXCwfrwzZp3t+upq7vRqHaO5WbWoAwCJ2ZBpcmToilRW3FZmpYTuhLVSme0VGvPtsWVucA7GSOM6qXO3wVH7vyzR4Yfzm1fjZatx7qxo/WI33rcbh5KRhAwAq7+f8Uj2/mnN+9bxXzs05u3XPf+fckPNM97wklW9fPprKCtJTOVd0cxfmXJNK8xG163MuyHk8Z2nOezlX5nzS/XzUH0nlFRxz4YucjdviCD6rxrEaFm6saiE+o1rdGJ+TymcVTeO16b+NbH2eEABY5N5NpYn4MeeQrrZjzuc5L6XSZHzd1Zensn35V5raDjwvlW3AF3Mu7mr9Cls0MB+m0qjt19XqxqTedo3/f7Wcg6rapM1068EwcX4tmthotnrtubPtcnZpalel8ln1K5Rbp+nfCVc3hAAAQ8X5rO+7caysHZYGG7ZYLYtXgURT9mlXi4Ztq5y7Ulltq0XDdmA3rrdVf8hZM+eAqjZJO6fBs2ezIZqsaMBqw7aWe3enwd/bIJXPGgBgZMfn3J/K1meIb0bG3Zx9M3ZLKg1bvyUYh/n781mxXRjn0/rzWPekssoUW6hPpNI4xdZofOkhrox6rqvH6tSkxBbwON8OHXYmr/Z2znpNbaYvU8T5tw9ydq9q0fjtUD0DACwq0SDFVm9sv47qzbYwhtgKHvXu0t5ZbQEAYLE4Kee7tjjE6am8j66//QEAgAmKLdb+FR7jBgCAOXBHKmfvxk284gQAAAAAAAAAAABmyzttYRqTfA8cAACzoL8LFQCAORT3oO6dyqXrM9GwAQDMg7ivc600eOn8imjYAADmyfOp3Hm6djvR0LABAMyTe3NObIuNaNbiIvf4d9vBKQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgVv0LkeC2oFFtJ1cAAAAASUVORK5CYII=>

[image24]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAZCAYAAAA4/K6pAAAAwElEQVR4XmNgGAWjgAbABIi3AvFuID4MxL6o0viBBhA/B2JRKL8KiK8ipAmDUiD+CsQSUH4hEAcgpOFi/WhicOACxP+h+DoQdwIxI4oKiBfN0MTAYAUQX0ITewfEsVA2LxA3A/E+IBaBq0ACb4C4D4lvB8RHgJgPys8AYg4gfgDESlAxFODDAAn9zUDczQCxjR9JXpYBYugZJDGSwWQgLmaAGEYyYAbil0AsDsQT0OSIAqDYOM0A0ayLJjcKBhwAAGwbHNJsZH+LAAAAAElFTkSuQmCC>

[image25]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAaCAYAAAC+aNwHAAAA3klEQVR4XmNgGAWjgIrAHIgXAfEJIDaFiskC8W0gzocpwgVkgHg3EHMD8SkgXgwVFwXiZ0B8AMrHCaqA2AWIlYH4PxAXIcllAvEsJL4NEB9F4qOAFgaIAdJIYvFAnIHEFwPiECQ+CrgMxPvRxLYxQLxIEID8D7K9HklMHYjnI/FLgHgjEDshiaGAF0A8FcoWBOJVUBoErIDYmAESwIlQMQzgD8SvGSBROR2IDZDkQFHKAcRvGCCxQxYIA+INQCwOxGxockSBdQyQGOgEYk40OaIAKHzmAHEEusQoGGgAAGw8IHD8p3P2AAAAAElFTkSuQmCC>

[image26]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAZCAYAAABQDyyRAAABZElEQVR4Xu2VvStGURzHf94JeRnIhJHBYJFSymJmYFMUKWW0KFIkowwGE8lgorzmZTEYCCXJpkws/gQ+v47LOcfz9Nx7n57l6X7qM5zv79xzTvecc69IQh4zgZ1WuwpXsMvKcsoFfnluYandKaAbl7HZL2TBJd7jJ57itFv+Tyuu4jq2e7U4nGOLH4ahUcxe7WCfV4vCmcRcQEANzuA+DmOhW86ILmAU9/AB78RsdWTKxJzoQzEDFrvltBzgotVew1est7JI6MS7+IaVXi0VHV67TcxNWPLyjOjEI/iEV9jvlkOji9YFPPqFdOh9ncQX3JRo+zeI7zhkZQViFvBhZSkpwnG8xVlscMuhWBAz2byV1f5k11bmUI1TeIxjYg5fXAZwG0usrEfMAuas7JdeMadWH9RXlS06xon8fff1Cuv4z1gRdMo1Tbgh5p9wI+Y/UOf0SLDQM6CfzjAeYbl5LCEhD/gGV9c/i5zbU34AAAAASUVORK5CYII=>

[image27]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAZCAYAAABD2GxlAAABfUlEQVR4Xu2VvStGYRyGfygMFpSvkiSDxeAvOBnMFiOKLBIWIxlsFsl/gEj5TJGPDdnI7iMWg4lQFu5fz6Med+dxzpEjw3PVNZzrnLful97ziAS+pRz2cfwvTMFVeMU3kiiAjRwduuEOPIErsOHr7UxEkmFgHeyE+3Cd7n0yCM9hlb2egPfOdVYiSTlwGF7AOfgm8QOr4SvsclohvINjTstCJCkHujxL/MB++A5bqR/AXedav+y4x1HnOSWC19QS8Q3Uv64OrKe+Bp9gKfU0RPCGWiK+gdp0YA31ZdubqKchgrcck/AN3JP4gYu2t1BPYkjMZ1/gpJixqfAN3Jb4gQu2N1PPDR24wRHMixlSS33J9krqueEbOCNmCL/E9Vnt+sr5E3TgJkfQK2ZIG/UjeEwtV3TgFkcxB/sj7HFaMXyAI07LlRIxp8WhmDOZ0aNQz+Aiez0Az+Rn78BMtMNTMeP036heijmXy5znlA44LeZHMwsrvt4OBAKBwG/yATZyVdVvLtv8AAAAAElFTkSuQmCC>