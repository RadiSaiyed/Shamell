import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Guards against calling `setState` during forbidden frame phases and after
/// disposal. This avoids intermittent red-screen failures in async-heavy flows.
mixin SafeSetStateMixin<T extends StatefulWidget> on State<T> {
  @override
  void setState(VoidCallback fn) {
    if (!mounted) return;
    final binding = SchedulerBinding.instance;
    final phase = binding.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      binding.addPostFrameCallback((_) {
        if (!mounted) return;
        super.setState(fn);
      });
      return;
    }
    super.setState(fn);
  }
}
