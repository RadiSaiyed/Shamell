import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_shell_widgets.dart' show AppBG;
import 'glass.dart';

class DoctorsAdminPage extends StatefulWidget {
  final String baseUrl;
  const DoctorsAdminPage({super.key, required this.baseUrl});

  @override
  State<DoctorsAdminPage> createState() => _DoctorsAdminPageState();
}

class _DoctorsAdminPageState extends State<DoctorsAdminPage> {
  bool _loading = false;
  String _error = '';
  List<_Appt> _appts = const [];
  final _doctorFilter = TextEditingController();
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, String>> _hdr({bool json = false}) async {
    final h = <String, String>{};
    if (json) h['content-type'] = 'application/json';
    try {
      final sp = await SharedPreferences.getInstance();
      final cookie = sp.getString('sa_cookie');
      if (cookie != null && cookie.isNotEmpty) h['sa_cookie'] = cookie;
    } catch (_) {}
    return h;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final fromIso = DateTime.now().toIso8601String();
      final toIso =
          DateTime.now().add(const Duration(days: 7)).toIso8601String();
      final qp = {
        'from_iso': fromIso,
        'to_iso': toIso,
      };
      if (_doctorFilter.text.trim().isNotEmpty) {
        qp['doctor_id'] = _doctorFilter.text.trim();
      }
      if (_statusFilter.isNotEmpty) {
        qp['status'] = _statusFilter;
      }
      final uri = Uri.parse('${widget.baseUrl}/admin/calendar')
          .replace(queryParameters: qp);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) {
        setState(() {
          _error = 'Failed to load (${r.statusCode})';
          _loading = false;
        });
        return;
      }
      final j = jsonDecode(r.body) as List;
      final list = j
          .map((e) => _Appt(
                id: e['id'] ?? '',
                doctorId: e['doctor_id'] ?? 0,
                patient: e['patient_name'] ?? '',
                reason: e['reason'] ?? '',
                status: e['status'] ?? '',
                tsIso: e['ts_iso'] ?? '',
              ))
          .toList();
      setState(() {
        _appts = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(String apptId, String status) async {
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/admin/appointments/$apptId/status');
      final r = await http.post(uri,
          headers: await _hdr(json: true),
          body: jsonEncode({'status': status}));
      if (r.statusCode == 200) {
        await _load();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Update failed: ${r.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Doctors Admin'),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GlassPanel(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error.isNotEmpty
                          ? Text(_error)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: 180,
                                      child: TextField(
                                        controller: _doctorFilter,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                            labelText: 'Doctor ID filter'),
                                      ),
                                    ),
                                    DropdownButton<String>(
                                      value: _statusFilter.isEmpty
                                          ? null
                                          : _statusFilter,
                                      hint: const Text('Status'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'booked',
                                            child: Text('Booked')),
                                        DropdownMenuItem(
                                            value: 'completed',
                                            child: Text('Completed')),
                                        DropdownMenuItem(
                                            value: 'canceled',
                                            child: Text('Canceled')),
                                        DropdownMenuItem(
                                            value: 'no-show',
                                            child: Text('No-show')),
                                      ],
                                      onChanged: (v) {
                                        setState(() {
                                          _statusFilter = v ?? '';
                                        });
                                        _load();
                                      },
                                    ),
                                    ElevatedButton.icon(
                                        onPressed: _load,
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Reload')),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: ListView(
                                    children: _appts
                                        .map((a) => ListTile(
                                              title: Text(
                                                  '${a.patient} • ${_fmt(a.tsIso)}'),
                                              subtitle: Text(
                                                  '${a.reason.isEmpty ? '—' : a.reason} • ${a.status}'),
                                              trailing: PopupMenuButton<String>(
                                                onSelected: (val) =>
                                                    _updateStatus(a.id, val),
                                                itemBuilder: (ctx) => const [
                                                  PopupMenuItem(
                                                      value: 'booked',
                                                      child: Text('Booked')),
                                                  PopupMenuItem(
                                                      value: 'completed',
                                                      child: Text('Completed')),
                                                  PopupMenuItem(
                                                      value: 'canceled',
                                                      child: Text('Canceled')),
                                                  PopupMenuItem(
                                                      value: 'no-show',
                                                      child: Text('No-show')),
                                                ],
                                                child:
                                                    const Icon(Icons.more_vert),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ],
                            ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Appt {
  final String id;
  final int doctorId;
  final String patient;
  final String reason;
  final String status;
  final String tsIso;
  const _Appt({
    required this.id,
    required this.doctorId,
    required this.patient,
    required this.reason,
    required this.status,
    required this.tsIso,
  });
}

String _fmt(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return iso;
  }
}
