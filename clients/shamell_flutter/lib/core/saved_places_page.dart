// Cycle 189 — Saved places management page.
//
// Lets the rider create/edit/delete Home + Work + arbitrary other
// places. The list is rendered with kind-specific icons and an
// inline "Set as Home / Work" affordance when those slots are
// empty. Tapping an entry returns it via Navigator.pop so the
// caller (the pickup/destination autocomplete in
// ride_hailing_page.dart) can prefill its field.

import 'dart:async';

import 'package:flutter/material.dart';

import 'account_places_api.dart';
import 'l10n.dart';

class SavedPlacesPage extends StatefulWidget {
  final String baseUrl;
  /// When non-null, the page acts as a "picker" — tapping a row
  /// pops back with that place. When null, taps just open the
  /// edit sheet.
  final bool pickerMode;

  const SavedPlacesPage({
    required this.baseUrl,
    this.pickerMode = false,
    super.key,
  });

  @override
  State<SavedPlacesPage> createState() => _SavedPlacesPageState();
}

class _SavedPlacesPageState extends State<SavedPlacesPage> {
  late final AccountPlacesApi _api;
  List<SavedPlace> _items = const <SavedPlace>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = AccountPlacesApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final items = await _api.listMine();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _showEditSheet({SavedPlace? existing, String? presetKind}) async {
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    final labelCtrl =
        TextEditingController(text: existing?.label ?? '');
    final addressCtrl =
        TextEditingController(text: existing?.address ?? '');
    String kind = existing?.kind ?? presetKind ?? 'other';
    final saved = await showModalBottomSheet<SavedPlace?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
            ),
            child: StatefulBuilder(builder: (innerCtx, setSheetState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    existing == null
                        ? (isArabic ? 'مكان جديد' : 'New place')
                        : (isArabic ? 'تعديل المكان' : 'Edit place'),
                    style: Theme.of(innerCtx)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      _kindChip(
                        innerCtx,
                        label: isArabic ? 'منزل' : 'Home',
                        icon: Icons.home_rounded,
                        selected: kind == 'home',
                        onTap: () => setSheetState(() => kind = 'home'),
                      ),
                      _kindChip(
                        innerCtx,
                        label: isArabic ? 'عمل' : 'Work',
                        icon: Icons.work_outline_rounded,
                        selected: kind == 'work',
                        onTap: () => setSheetState(() => kind = 'work'),
                      ),
                      _kindChip(
                        innerCtx,
                        label: isArabic ? 'آخر' : 'Other',
                        icon: Icons.bookmark_outline_rounded,
                        selected: kind == 'other',
                        onTap: () => setSheetState(() => kind = 'other'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: labelCtrl,
                    decoration: InputDecoration(
                      labelText: isArabic ? 'الاسم' : 'Label',
                      hintText: isArabic ? 'مثال: ماما' : 'e.g. Mom',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: isArabic ? 'العنوان' : 'Address',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      final label = labelCtrl.text.trim();
                      final addr = addressCtrl.text.trim();
                      if (label.isEmpty || addr.isEmpty) {
                        ScaffoldMessenger.of(innerCtx).showSnackBar(SnackBar(
                          content: Text(isArabic
                              ? 'يرجى تعبئة الحقول'
                              : 'Please fill both fields'),
                        ));
                        return;
                      }
                      try {
                        final p = await _api.save(
                          label: label,
                          address: addr,
                          kind: kind,
                          lat: existing?.lat,
                          lon: existing?.lon,
                        );
                        if (innerCtx.mounted) {
                          Navigator.of(innerCtx).pop(p);
                        }
                      } on AccountPlacesApiException catch (err) {
                        if (innerCtx.mounted) {
                          ScaffoldMessenger.of(innerCtx).showSnackBar(SnackBar(
                            content: Text(err.detail.isNotEmpty
                                ? err.detail
                                : (isArabic
                                    ? 'فشل الحفظ'
                                    : 'Save failed')),
                          ));
                        }
                      }
                    },
                    icon: const Icon(Icons.save_rounded),
                    label:
                        Text(isArabic ? 'حفظ المكان' : 'Save place'),
                  ),
                ],
              );
            }),
          ),
        );
      },
    );
    if (saved != null) {
      await _refresh();
    }
  }

  Widget _kindChip(
    BuildContext ctx, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(ctx).colorScheme;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: scheme.primary.withValues(alpha: .18),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        color: selected ? scheme.primary : null,
      ),
    );
  }

  Future<void> _delete(SavedPlace place) async {
    final isArabic = L10n.of(context).isArabic;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'حذف المكان؟' : 'Delete place?'),
        content: Text(isArabic
            ? 'سيتم حذف هذا المكان نهائياً.'
            : 'This will permanently remove the saved place.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isArabic ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await _api.delete(id: place.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? (isArabic ? 'تم الحذف' : 'Deleted')
          : (isArabic ? 'فشل الحذف' : 'Delete failed')),
    ));
    if (ok) await _refresh();
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'home':
        return Icons.home_rounded;
      case 'work':
        return Icons.work_outline_rounded;
      default:
        return Icons.bookmark_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final hasHome = _items.any((p) => p.isHome);
    final hasWork = _items.any((p) => p.isWork);
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'الأماكن المحفوظة' : 'Saved places'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                children: <Widget>[
                  if (!hasHome || !hasWork)
                    Row(
                      children: <Widget>[
                        if (!hasHome)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _showEditSheet(presetKind: 'home'),
                              icon: const Icon(Icons.home_rounded),
                              label: Text(
                                  isArabic ? 'إضافة منزل' : 'Add Home'),
                            ),
                          ),
                        if (!hasHome && !hasWork) const SizedBox(width: 8),
                        if (!hasWork)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _showEditSheet(presetKind: 'work'),
                              icon: const Icon(Icons.work_outline_rounded),
                              label: Text(
                                  isArabic ? 'إضافة عمل' : 'Add Work'),
                            ),
                          ),
                      ],
                    ),
                  if (!hasHome || !hasWork) const SizedBox(height: 12),
                  ..._items.map((p) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .14),
                            child: Icon(_kindIcon(p.kind),
                                color: Theme.of(context).colorScheme.primary),
                          ),
                          title: Text(p.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(p.address),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') _showEditSheet(existing: p);
                              if (v == 'delete') _delete(p);
                            },
                            itemBuilder: (_) => <PopupMenuItem<String>>[
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Text(isArabic ? 'تعديل' : 'Edit'),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Text(isArabic ? 'حذف' : 'Delete'),
                              ),
                            ],
                          ),
                          onTap: () {
                            if (widget.pickerMode) {
                              Navigator.of(context).pop(p);
                            } else {
                              _showEditSheet(existing: p);
                            }
                          },
                        ),
                      )),
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          isArabic
                              ? 'لا توجد أماكن محفوظة بعد.'
                              : 'No saved places yet.',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditSheet(),
        icon: const Icon(Icons.add),
        label: Text(isArabic ? 'مكان جديد' : 'New place'),
      ),
    );
  }
}
