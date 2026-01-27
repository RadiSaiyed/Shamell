import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'status_banner.dart';
import 'app_shell_widgets.dart' show AppBG, WaterButton;

class DriverPodPage extends StatefulWidget {
  final String baseUrl;
  final String bookingId;
  const DriverPodPage(
      {super.key, required this.baseUrl, required this.bookingId});

  @override
  State<DriverPodPage> createState() => _DriverPodPageState();
}

class _DriverPodPageState extends State<DriverPodPage> {
  File? _photo;
  final TextEditingController noteCtrl = TextEditingController();
  final TextEditingController sigCtrl = TextEditingController();
  String _out = '';

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img =
        await picker.pickImage(source: ImageSource.camera, maxWidth: 1200);
    if (img != null) setState(() => _photo = File(img.path));
  }

  Future<void> _upload() async {
    setState(() => _out = 'uploading...');
    try {
      String? b64;
      String? fname;
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        b64 = base64Encode(bytes);
        fname = 'pod-${widget.bookingId}.png';
      }
      final body = {
        'kind': 'delivery',
        'status': 'completed',
        'proof_photo_b64': b64,
        'proof_filename': fname,
        'proof_note':
            noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        'signature_name':
            sigCtrl.text.trim().isEmpty ? null : sigCtrl.text.trim(),
        'pod_signed': true,
      };
      final r = await http.post(
        Uri.parse(
            '${widget.baseUrl}/equipment/bookings/${widget.bookingId}/logistics'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode([body]),
      );
      _out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      _out = 'error: $e';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proof of Delivery')),
      body: AppBG(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_photo != null)
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                        image: FileImage(_photo!), fit: BoxFit.cover),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  WaterButton(label: 'Foto aufnehmen', onTap: _pickPhoto),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Notiz')),
              TextField(
                  controller: sigCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Unterschrift Name')),
              const SizedBox(height: 12),
              WaterButton(label: 'Abschließen', onTap: _upload),
              if (_out.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: StatusBanner.info(_out)),
            ],
          ),
        ),
      ),
    );
  }
}
