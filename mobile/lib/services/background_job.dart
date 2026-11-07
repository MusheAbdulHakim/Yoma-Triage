import 'dart:async';
import 'dart:isolate';

/// The job was cancelled before it finished.
class JobCancelled implements Exception {
  const JobCancelled();

  @override
  String toString() => 'JobCancelled';
}

/// Runs work in its own isolate, so the main thread stays free to draw frames and answer
/// taps. Model inference takes several seconds, longer than Android allows the main thread
/// to stall before it reports the app as not responding.
///
/// [cancel] kills the isolate at once, wherever the work has got to.
///
/// The work function is copied to the new isolate with everything it captures, so it must
/// capture plain data only: no interpreter, no `this` that holds one.
class BackgroundJob<T> {
  BackgroundJob._();

  final _completer = Completer<T>();
  final _port = ReceivePort();
  Isolate? _isolate;
  bool _cancelled = false;

  Future<T> get result => _completer.future;

  static BackgroundJob<T> start<T>(
    FutureOr<T> Function() work, {
    String name = 'yoma-background',
  }) {
    final job = BackgroundJob<T>._();
    unawaited(job._spawn(work, name));
    return job;
  }

  Future<void> _spawn(FutureOr<T> Function() work, String name) async {
    _port.listen(_onMessage);
    try {
      final isolate = await Isolate.spawn(
        _entry,
        _Start(work, _port.sendPort),
        debugName: name,
        onExit: _port.sendPort,
        onError: _port.sendPort,
      );
      _isolate = isolate;
      // Cancelled while the isolate was starting.
      if (_cancelled) isolate.kill(priority: Isolate.immediate);
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _onMessage(Object? message) {
    if (_completer.isCompleted) {
      _port.close();
      return;
    }
    switch (message) {
      case _Done(:final value):
        _completer.complete(value as T);
        _port.close();
      case _Failed(:final error, :final stack):
        _fail(StateError(error), StackTrace.fromString(stack));
      case [final error, final stack]:
        // An uncaught error from the isolate, as Isolate.spawn's onError reports it.
        _fail(StateError('$error'), StackTrace.fromString('$stack'));
      case null:
        // The isolate exited with no result.
        _fail(_cancelled ? const JobCancelled() : StateError('The background job stopped'));
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (!_completer.isCompleted) _completer.completeError(error, stack);
    _port.close();
  }

  /// Stops the work now. [result] fails with [JobCancelled], unless it already finished.
  void cancel() {
    if (_completer.isCompleted) return;
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _fail(const JobCancelled());
  }
}

class _Start {
  _Start(this.work, this.reply);

  final FutureOr<Object?> Function() work;
  final SendPort reply;
}

class _Done {
  _Done(this.value);

  final Object? value;
}

class _Failed {
  _Failed(this.error, this.stack);

  final String error;
  final String stack;
}

Future<void> _entry(_Start start) async {
  try {
    start.reply.send(_Done(await start.work()));
  } catch (error, stack) {
    start.reply.send(_Failed('$error', '$stack'));
  }
}
