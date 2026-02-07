import 'dart:developer' as dev;
import 'dart:convert';
import 'package:http/http.dart' as http;

class Perf {
  static DateTime? _start;
  static int _tapCount = 0;
  static bool _remote = false;
  static String _base = '';
  static String _device = '';

  static void init() {
    _start = DateTime.now();
    dev.postEvent('shamell_metric', {'phase': 'init'});
  }

  static void configure(
      {required String baseUrl,
      required String deviceId,
      required bool remote}) {
    _base = baseUrl;
    _device = deviceId;
    _remote = remote;
  }

  static void tap(String label) {
    _tapCount++;
    dev.postEvent('shamell_tap', {'label': label, 'count': _tapCount});
    _post('tap', {'label': label});
  }

  static void action(String label) {
    final ms = _start == null
        ? null
        : DateTime.now().difference(_start!).inMilliseconds;
    dev.postEvent('shamell_action', {
      'label': label,
      if (ms != null) 'ms_since_start': ms,
      'tap_count': _tapCount
    });
    _post('action', {'label': label, if (ms != null) 'ms': ms});
  }

  static void sample(String metric, int valueMs) {
    dev.postEvent('shamell_sample', {'metric': metric, 'value_ms': valueMs});
    _post('sample', {'metric': metric, 'value_ms': valueMs});
  }

  static Future<void> _post(String type, Map<String, dynamic> data) async {
    if (!_remote) return;
    if (_base.isEmpty) return;
    try {
      final u = Uri.parse(_base + '/metrics');
      final body = jsonEncode({
        'type': type,
        'data': data,
        'device': _device,
        'ts': DateTime.now().toUtc().toIso8601String()
      });
      await http
          .post(u,
              headers: {
                'content-type': 'application/json',
                'X-Device-ID': _device
              },
              body: body)
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {/* best-effort, ignore */}
  }
}
