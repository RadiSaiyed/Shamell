class V2EventCatalog {
  static const String activationStarted = 'v2_activation_started';
  static const String activationCompleted = 'v2_activation_completed';
  static const String authSignInSucceeded = 'v2_auth_sign_in_succeeded';
  static const String chatMessageSent = 'v2_chat_message_sent';
  static const String paymentsTransferSucceeded =
      'v2_payments_transfer_succeeded';
  static const String errorShown = 'v2_error_shown';

  static const Map<String, Set<String>> _requiredProperties =
      <String, Set<String>>{
    activationStarted: <String>{'source', 'user_role'},
    activationCompleted: <String>{'elapsed_ms', 'first_flow'},
    authSignInSucceeded: <String>{'method', 'elapsed_ms'},
    chatMessageSent: <String>{'chat_type', 'elapsed_ms'},
    paymentsTransferSucceeded: <String>{'amount_cents', 'elapsed_ms'},
    errorShown: <String>{'code', 'surface'},
  };

  static void validate({
    required String name,
    required Map<String, Object?> properties,
  }) {
    final required = _requiredProperties[name];
    if (required == null) {
      throw StateError('Unknown v2 telemetry event: $name');
    }
    final missing = required
        .where((key) => !properties.containsKey(key) || properties[key] == null)
        .toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required properties for $name: ${missing.join(', ')}',
      );
    }
  }
}
