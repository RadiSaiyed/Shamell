class RuntimeCompromiseState {
  final bool compromised;
  final List<String> signals;

  const RuntimeCompromiseState({
    required this.compromised,
    this.signals = const <String>[],
  });

  static const RuntimeCompromiseState safe = RuntimeCompromiseState(
    compromised: false,
  );
}
