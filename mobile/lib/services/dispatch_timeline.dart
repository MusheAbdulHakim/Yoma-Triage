/// What the dispatch status screen shows, worked out from the dispatch the app already
/// has (the polled status, driver and destination) without touching how it is fetched.
///
/// Pure: no widgets, no I/O, so every status can be tested on its own.
library;

enum TimelineState { done, current, future }

/// One row of the vertical timeline.
class TimelineStep {
  const TimelineStep({
    required this.id,
    required this.label,
    required this.state,
    this.detail,
    this.note,
  });

  final String id;

  /// Present tense / in progress while current, past tense only once it has happened.
  final String label;
  final TimelineState state;

  /// A line under the label, e.g. the driver's name.
  final String? detail;

  /// A light teal note under the step (the diversion's new destination).
  final String? note;

  /// What a screen reader says for the whole row.
  String get spoken {
    final parts = [
      label,
      if (detail != null) detail!,
      if (note != null) note!,
    ];
    final prefix = switch (state) {
      TimelineState.done => 'Done',
      TimelineState.current => 'Now',
      TimelineState.future => 'Not yet',
    };
    return '$prefix: ${parts.join(', ')}';
  }
}

/// Which help card the screen shows under the timeline.
enum DispatchHelp { none, noDriver, notSentYet }

class DispatchTimeline {
  const DispatchTimeline({required this.steps, required this.help});

  final List<TimelineStep> steps;
  final DispatchHelp help;

  TimelineStep? get current {
    for (final step in steps) {
      if (step.state == TimelineState.current) return step;
    }
    return null;
  }

  /// Drivers are being offered the trip: the CHO may call one instead.
  bool get waitingForDriver => current?.id == 'driver' && help == DispatchHelp.none;
}

const _waitingForDriver = {'PENDING', 'TIER1_NOTIFIED', 'TIER2_NOTIFIED'};
const _driverAssigned = {
  'ACCEPTED',
  'HOSPITAL_NOTIFIED',
  'HOSPITAL_CONFIRMED',
  'DIVERTED',
  'COMPLETED',
};

/// The timeline for a referral still on this phone (no dispatch yet).
DispatchTimeline queuedTimeline() => const DispatchTimeline(
      help: DispatchHelp.notSentYet,
      steps: [
        TimelineStep(
          id: 'saved',
          label: 'Saved on this phone – will send when signal returns',
          state: TimelineState.current,
        ),
        TimelineStep(id: 'drivers', label: 'Drivers notified', state: TimelineState.future),
        TimelineStep(id: 'driver', label: 'Driver accepts', state: TimelineState.future),
        TimelineStep(id: 'hospital', label: 'Hospital confirms', state: TimelineState.future),
        TimelineStep(id: 'trip', label: 'Arrives at hospital', state: TimelineState.future),
      ],
    );

/// The timeline for a dispatch the server knows about.
///
/// [sawConfirmed]: this screen saw HOSPITAL_CONFIRMED earlier, so a COMPLETED trip can
/// say the hospital confirmed (a trip can complete without it). [acceptedLate]: this
/// screen saw FAILED before a driver accepted.
DispatchTimeline dispatchTimeline({
  required String status,
  String? driverName,
  String? facilityName,
  String? divertedFrom,
  bool sawConfirmed = false,
  bool acceptedLate = false,
}) {
  final s = status.toUpperCase();
  final destination = facilityName ?? 'the hospital';

  if (s == 'CANCELLED') {
    return const DispatchTimeline(
      help: DispatchHelp.none,
      steps: [
        TimelineStep(id: 'sent', label: 'Referral sent', state: TimelineState.done),
        TimelineStep(
          id: 'cancelled',
          label: 'Referral cancelled',
          detail: 'Drivers will not be alerted any more.',
          state: TimelineState.done,
        ),
      ],
    );
  }

  final assigned = _driverAssigned.contains(s);

  final drivers = switch (s) {
    'PENDING' => const TimelineStep(
        id: 'drivers', label: 'Notifying drivers', state: TimelineState.current),
    _ when _waitingForDriver.contains(s) || s == 'FAILED' || assigned => const TimelineStep(
        id: 'drivers', label: 'Drivers notified', state: TimelineState.done),
    _ => const TimelineStep(id: 'drivers', label: 'Checking status…', state: TimelineState.current),
  };

  final driver = switch (s) {
    'TIER1_NOTIFIED' || 'TIER2_NOTIFIED' => const TimelineStep(
        id: 'driver', label: 'Waiting for a driver to accept', state: TimelineState.current),
    'FAILED' => const TimelineStep(
        id: 'driver', label: 'No driver has accepted', state: TimelineState.current),
    _ when assigned => TimelineStep(
        id: 'driver',
        label: 'Driver accepted',
        detail: [
          if (driverName != null && driverName.isNotEmpty) driverName,
          if (acceptedLate) 'Accepted after the alerts had stopped',
        ].join(' · ').ifEmpty(),
        state: TimelineState.done,
      ),
    _ => const TimelineStep(id: 'driver', label: 'Driver accepts', state: TimelineState.future),
  };

  final hospital = switch (s) {
    'ACCEPTED' || 'HOSPITAL_NOTIFIED' || 'DIVERTED' => const TimelineStep(
        id: 'hospital', label: 'Waiting for hospital to confirm', state: TimelineState.current),
    'HOSPITAL_CONFIRMED' => const TimelineStep(
        id: 'hospital', label: 'Hospital confirmed', state: TimelineState.done),
    'COMPLETED' => TimelineStep(
        id: 'hospital',
        label: sawConfirmed ? 'Hospital confirmed' : 'Hospital notified',
        state: TimelineState.done,
      ),
    _ => const TimelineStep(id: 'hospital', label: 'Hospital confirms', state: TimelineState.future),
  };

  final trip = switch (s) {
    'HOSPITAL_CONFIRMED' => TimelineStep(
        id: 'trip', label: 'On the way to $destination', state: TimelineState.current),
    'COMPLETED' => const TimelineStep(id: 'trip', label: 'Arrived', state: TimelineState.done),
    _ => const TimelineStep(id: 'trip', label: 'Arrives at hospital', state: TimelineState.future),
  };

  final diverted = divertedFrom == null
      ? null
      : TimelineStep(
          id: 'diverted',
          label: 'Diverted',
          detail: 'From $divertedFrom, by the hospital',
          note: 'Now going to $destination',
          state: TimelineState.done,
        );

  return DispatchTimeline(
    help: s == 'FAILED' ? DispatchHelp.noDriver : DispatchHelp.none,
    steps: [
      const TimelineStep(id: 'sent', label: 'Referral sent', state: TimelineState.done),
      drivers,
      driver,
      // A diversion re-notifies a new hospital, so the hospital step after it is about
      // the new destination.
      if (diverted != null) diverted,
      hospital,
      trip,
    ],
  );
}

extension on String {
  String? ifEmpty() => isEmpty ? null : this;
}
