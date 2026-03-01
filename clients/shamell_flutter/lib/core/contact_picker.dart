import 'package:flutter/material.dart';

class ContactPickerPage extends StatefulWidget {
  final void Function(String phone) onPicked;
  const ContactPickerPage({super.key, required this.onPicked});
  @override
  State<ContactPickerPage> createState() => _ContactPickerPageState();
}

class _ContactPickerPageState extends State<ContactPickerPage> {
  final TextEditingController _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phoneCtrl.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Select contact')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the recipient phone number manually.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                final v = _phoneCtrl.text.trim();
                if (v.isEmpty) return;
                widget.onPicked(v);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: phone.isEmpty
                  ? null
                  : () {
                      widget.onPicked(phone);
                      Navigator.pop(context);
                    },
              child: const Text('Use this number'),
            ),
          ],
        ),
      ),
    );
  }
}
