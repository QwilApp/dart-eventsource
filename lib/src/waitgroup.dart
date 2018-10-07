import 'dart:async';

class WaitGroup {
  int _counter = 0;
  Completer _completer;

  WaitGroup();

  /// Adds delta, which may be negative, to the WaitGroup counter.
  /// If a wait Future is open and the counter becomes zero, the future is
  /// released.
  /// If the counter goes negative, it throws.
  void add([int amount = 1]) {
    if (_counter + amount < 0) {
      throw new StateError("WaitGroup counter cannot go negative.");
    }
    _counter += amount;
    if (_counter == 0 && _completer != null) {
      _completer.complete();
    }
  }

  /// Decrements the WaitGroup counter.
  void done() => add(-1);

  /// Returns a future that will complete when the WaitGroup counter is zero.
  Future wait() {
    if (_counter == 0) {
      return new Future.value();
    }
    if (_completer == null) {
      _completer = new Completer();
    }
    return _completer.future;
  }
}
