---
name: Clinical Field Resilience
colors:
  surface: '#f9f9ff'
  surface-dim: '#cddbf5'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f0f3ff'
  surface-container: '#e7eeff'
  surface-container-high: '#dee8ff'
  surface-container-highest: '#d6e3fe'
  on-surface: '#0e1c2f'
  on-surface-variant: '#44474d'
  inverse-surface: '#243145'
  inverse-on-surface: '#ebf1ff'
  outline: '#74777e'
  outline-variant: '#c4c6ce'
  surface-tint: '#4a5f7f'
  primary: '#001229'
  on-primary: '#ffffff'
  primary-container: '#0f2744'
  on-primary-container: '#798fb1'
  inverse-primary: '#b2c8ed'
  secondary: '#415e94'
  on-secondary: '#ffffff'
  secondary-container: '#a4c1fe'
  on-secondary-container: '#304e83'
  tertiary: '#001324'
  on-tertiary: '#ffffff'
  tertiary-container: '#002845'
  on-tertiary-container: '#6291c0'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d4e3ff'
  primary-fixed-dim: '#b2c8ed'
  on-primary-fixed: '#021c39'
  on-primary-fixed-variant: '#324866'
  secondary-fixed: '#d8e2ff'
  secondary-fixed-dim: '#acc7ff'
  on-secondary-fixed: '#001a41'
  on-secondary-fixed-variant: '#28467b'
  tertiary-fixed: '#cfe5ff'
  tertiary-fixed-dim: '#9ccbfd'
  on-tertiary-fixed: '#001d34'
  on-tertiary-fixed-variant: '#104a75'
  background: '#f9f9ff'
  on-background: '#0e1c2f'
  surface-variant: '#d6e3fe'
typography:
  headline-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 26px
    fontWeight: '700'
    lineHeight: 34px
  headline-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 22px
    fontWeight: '700'
    lineHeight: 30px
  headline-sm:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 19px
    fontWeight: '600'
    lineHeight: 26px
  body-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
  label-lg:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 16px
    fontWeight: '700'
    lineHeight: 22px
  label-md:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 18px
  label-sm:
    fontFamily: Atkinson Hyperlegible Next
    fontSize: 12px
    fontWeight: '700'
    lineHeight: 16px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.25rem
---

## Brand & Style
This design system is engineered specifically for frontline Community Health Officers (CHOs) working under extreme clinical, environmental, and infrastructural pressure in rural Northern Ghana. The interface embodies high-contrast utilitarian minimalism merged with clinical ergonomics. It projects unflinching reliability, immediate clarity, and clinical authority while actively reducing cognitive load during time-critical maternal and pediatric emergencies.

The visual style strips away ornamental gradients, low-contrast pastels, and cosmetic micro-interactions in favor of crisp, structural, high-visibility surfaces. The interface must remain immediately legible under direct, harsh sub-Saharan sunlight on low-cost Android hardware (e.g., 360dp display widths with TN/IPS panels of varying quality). Visual hierarchy is driven strictly by scale, structural containment, and deliberate semantic color segregation: the brand is deep, steady navy and slate; triage statuses are sacred and reserved exclusively for clinical severity.

## Colors
The color architecture enforces a strict clinical boundary between institutional chrome and vital triage signals:

- **Institutional Brand & Surfaces**:
  - Primary (`#0F2744`): Deep clinical navy used for primary actions, critical navigation anchors, and persistent app headers.
  - Secondary (`#1B3B6F`): Medium clinical indigo used for secondary interactive structures, tab indicators, and active selection containers.
  - Tertiary / Accent (`#2C5E8A`): Deep slate-teal used for supporting UI elements, passive data highlights, and non-urgent system messaging.
  - Neutral Base (`#0B192C`): Ultra-deep slate used for all primary typography to hit WCAG AAA contrast ratios (≥ 12:1 against pure white).
  - Surface Background: Pure clinical white (`#FFFFFF`) as the default canvas, backed by stark neutral gray (`#F1F5F9`) for secondary structural panels.

- **Sacred Triage & Clinical Semantics (Strict Reservation)**:
  Under no circumstances may red, yellow/amber, or green be used in branding, marketing badges, or general layout chrome. They are reserved strictly for clinical acuity:
  - Critical / Immediate Danger (`#C5221F`): Crimson triage alert for severe hemorrhages, shock, eclampsia, or neonate respiratory failure. Paired with white text (`#FFFFFF`) or pure black iconography.
  - Urgent / Moderate Risk (`#B45309`): High-contrast amber-ochre for non-immediate vital deviations, delayed capillary refill, or warning scores.
  - Stable / Routine Care (`#15803D`): Deep clinical forest green for normal parameters and baseline vitals.

- **Connectivity & Offline Signals**:
  Offline state is treated as standard operating reality, not a system failure. The offline indicator uses muted slate-blue (`#475569` on `#E2E8F0`) with a calm synced/cached cloud icon, preventing false panic among health workers.

## Typography
Typography is anchored entirely on **Atkinson Hyperlegible Next**, designed specifically for maximum glyph differentiation and uncompromised legibility across visual impairments and sun glare. Numbers, vital signs, and diagnostic symbols (e.g., distinguishing 1, I, l or 0, O) must be readable at a glance on cracked or dusty screens.

- **Baseline Sizing**: Standard body copy starts strictly at `16px` (`body-md`) and runs with an expanded line-height ratio (`1.5` to `1.55`) to facilitate rapid tracking while walking or in moving transport.
- **Language Accommodation**: Northern Ghanaian contexts involve localization and code-switching into languages like Dagbani, Gonja, and Hausa. Text containers must provide an automatic 30% horizontal expansion allowance and avoid aggressive fixed-width truncations or ellipsis.
- **Numerical Hierarchy**: Blood pressure, fetal heart rates, and triage timestamps must render with dedicated bold weights (`label-lg` or `headline-md`) using tabular figures to prevent shifting digit columns during live monitoring.

## Layout & Spacing
The layout system is tailored for Android devices down to a base viewport of 360dp width (common for devices running entry-level chipsets):

- **Grid Architecture**: Single-column vertical stream on mobile screens (360dp to 599dp) with a fixed outer margin of `16px` (`margin`) and a `16px` (`gutter`). For rural field tablets (600dp+), layouts split into a structured two-column master-detail split (e.g., triage queue on the left 40%, clinical intervention protocol on the right 60%).
- **Ergonomic Reach Zones**: High-priority triage triggers and emergency handoff actions must reside within the thumb-accessible bottom 40% of the screen. Critical emergency buttons must occupy full row width.
- **Touch Target Integrity**: Every tap target must adhere strictly to a 48dp minimum, with high-stress triage buttons expanding to 56dp vertical height. Spacing between discrete actions is maintained at a minimum of `12px` to `16px` (`space-md`) to eliminate accidental triggering during rapid patient intake.

## Elevation & Depth
In harsh outdoor sunlight, subtle drop shadows, soft ambient blurs, and glassmorphic translucent effects wash out completely and introduce visual noise. 

This design system uses a **structural tonal layering and high-contrast outline model**:
- **Planes & Surfaces**: Visual hierarchy is created through flat, solid background layers (`#FFFFFF` resting on `#F1F5F9`).
- **Separation & Borders**: Cards, alert panels, and list rows rely on crisp 1.5px to 2px solid structural borders (`#CBD5E1` for standard cards; `#0F2744` for active/selected states).
- **Elevation Cues**: Floating action buttons (e.g., "Add Emergency") utilize a hard, direct offset shadow (e.g., `0px 3px 0px 0px #0B192C`) rather than a blurred ambient shadow, ensuring the physical affordance cuts through direct ambient glare.
- **Modals & Overlays**: Emergency assessment dialogs employ a pure black high-opacity scrim (`rgba(11, 25, 44, 0.75)`) with stark white structural dialogue containers to retain immediate situational focus.

## Shapes
A "Soft" roundedness standard (`roundedness: 1` — 4px base radius) is maintained across all UI components. 

- **Rationale**: Circular pills and heavy rounded corners eat valuable screen real estate on 360dp screens and soften the imperative nature of emergency tools. Modest 4px corners provide clean, modern boundaries while maximizing readable rectangular text area.
- **Form Cohesion**: Input fields, diagnostic cards, triage alert banners, and primary CTA buttons share uniform 4px corner radii, establishing an uncompromising, utilitarian clinical aesthetic.

## Components

### Buttons & Action Bars
- **Emergency / Primary Action**: Minimum 56dp height, full-width or large-format. Styled with `#0F2744` background, pure white bold text (`label-lg`), and an unmistakable clinical action icon (e.g., ambulance, referral paper, direct call).
- **Secondary Actions**: Minimum 48dp height, white background, `#1B3B6F` border (2px stroke), with matching navy typography.
- **Triage Action Modifiers**: Dedicated emergency overrides (e.g., "RED FLAG DETECTED - REFER NOW") adopt solid `#C5221F` backgrounds with crisp white text, accompanied by an exclamation shield icon.

### Triage Badges & Status Chips
- **Dual-Coded Acuity Indicators**: Every triage badge must combine color, text, and an explicit icon to ensure total accessibility for color-blind practitioners and outdoor washout scenarios:
  - *Emergency*: `#C5221F` background, white bold text "CRITICAL", Octagon Alert icon.
  - *Priority*: `#B45309` background, white bold text "URGENT", Triangle Warning icon.
  - *Routine*: `#15803D` background, white bold text "STABLE", Check Circle icon.
- Badges use 4px border radius and generous padding (`6px 12px`).

### Offline & Sync Indicators
- **Passive Connection Status**: Fixed in the sub-header. Rendered in `#E2E8F0` with `#334155` text and a cloud icon with a clear checkmark ("Saved to Device - 14 Records Pending Sync"). Never uses warning colors for standard offline functionality.

### Inputs & Vital Sign Collectors
- **Field Layout**: Large 52dp height fields with prominent numeric keypads triggered by default for clinical metrics (BP, Pulse, Temperature, Gestational Age).
- **Visual Validation**: High-contrast 2px border `#0B192C` on active focus. Out-of-range thresholds dynamically trigger triage badge borders without hiding user input.

### Patient & Referral Cards
- **Clinical Patient Card**: Crisp white surface framed with a 1.5px border. Left edge features an uninterrupted 8px vertical triage severity stripe. High-contrast typography displays patient name, national ID / local identifier, and time since triage intake in clear tabular notation.
