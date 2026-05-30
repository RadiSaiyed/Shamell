import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

class ContactPickerPage extends StatefulWidget {
  final void Function(String phone) onPicked;
  const ContactPickerPage({super.key, required this.onPicked});
  @override
  State<ContactPickerPage> createState() => _ContactPickerPageState();
}

class _ContactPickerPageState extends State<ContactPickerPage> {
  List<Contact> all = [];
  List<Contact> filtered = [];
  bool loading = true;
  bool permissionDenied = false;
  final qCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
    qCtrl.addListener(_applyFilter);
  }

  Future<void> _load() async {
    try {
      final ok = await FlutterContacts.requestPermission(readonly: true);
      if (!ok) {
        permissionDenied = true;
        loading = false;
        if (mounted) setState(() {});
        return;
      }
      final withProps = await FlutterContacts.getContacts(
          withProperties: true, withPhoto: false);
      all = withProps.where((c) => (c.phones.isNotEmpty)).toList();
      filtered = all;
      loading = false;
      if (mounted) setState(() {});
    } catch (e) {
      loading = false;
      if (mounted) setState(() {});
    }
  }

  void _applyFilter() {
    final q = qCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      filtered = all;
    } else {
      filtered = all.where((c) {
        final name = c.displayName.toLowerCase();
        final phone = c.phones.isNotEmpty
            ? c.phones.first.number.replaceAll(' ', '')
            : '';
        return name.contains(q) || phone.contains(q);
      }).toList();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Select contact')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : permissionDenied
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Contacts permission is required to pick a recipient from your address book.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
            : Column(children: [
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                        controller: qCtrl,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search…'))),
                Expanded(
                    child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          final name = c.displayName;
                          final phone = c.phones.first.number;
                          return ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.person_outline)),
                            title: Text(name),
                            subtitle: Text(phone),
                            onTap: () {
                              widget.onPicked(phone);
                              Navigator.pop(context);
                            },
                          );
                        }))
              ]));
  }
}
