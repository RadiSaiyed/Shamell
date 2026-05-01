import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chat/threema_chat_page.dart';
import 'l10n.dart';
import 'official_accounts_page.dart'
    show OfficialAccountFeedPage, OfficialAccountHandle;
import 'wechat_ui.dart';

Future<Map<String, String>> _hdrNearby({bool json = false}) async {
  final headers = <String, String>{};
  if (json) {
    headers['content-type'] = 'application/json';
  }
  try {
    final sp = await SharedPreferences.getInstance();
    final cookie = sp.getString('sa_cookie') ?? '';
    if (cookie.isNotEmpty) {
      headers['sa_cookie'] = cookie;
    }
  } catch (_) {}
  return headers;
}

class PeopleNearbyPage extends StatefulWidget {
  final String baseUrl;
  final List<OfficialAccountHandle>? recommendedOfficials;
  final String? recommendedCityLabel;

  const PeopleNearbyPage({
    super.key,
    required this.baseUrl,
    this.recommendedOfficials,
    this.recommendedCityLabel,
  });

  @override
  State<PeopleNearbyPage> createState() => _PeopleNearbyPageState();
}

class _PeopleNearbyPageState extends State<PeopleNearbyPage> {
  bool _loading = true;
  bool _locationDenied = false;
  String _error = '';
  List<Map<String, dynamic>> _items = const [];

  double _maxDistanceKm = 0;
  String _genderFilter = 'all'; // all, male, female
  String _ageFilter = 'all'; // all, 18_25, 26_35, 36_plus
  bool _statusOnly = false;

  final TextEditingController _statusCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();
  bool _profileLoading = false;
  bool _profileSaving = false;
  String _myGender = ''; // '', male, female
  int? _myAgeYears;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _load();
  }

  @override
  void dispose() {
    _statusCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _profileLoading = true;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/nearby/profile');
      final r = await http.get(uri, headers: await _hdrNearby());
      if (r.statusCode == 200) {
        final body = r.body;
        if (body.isNotEmpty) {
          final decoded = jsonDecode(body);
          if (!mounted) return;
          if (decoded is Map) {
            final map = decoded.cast<String, dynamic>();
            final status = (map['status'] ?? '').toString();
            final gender = (map['gender'] ?? '').toString();
            final ageRaw = map['age_years'];
            int? age;
            if (ageRaw is num) {
              age = ageRaw.toInt();
            } else if (ageRaw is String && ageRaw.isNotEmpty) {
              age = int.tryParse(ageRaw);
            }
            setState(() {
              _statusCtrl.text = status;
              _myGender = gender;
              _myAgeYears = age;
              _ageCtrl.text = age != null && age > 0 ? age.toString() : '';
            });
          }
        }
      }
    } catch (_) {
      // Ignore profile load errors; nearby list can still work.
    } finally {
      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_profileSaving) return;
    final l = L10n.of(context);
    setState(() {
      _profileSaving = true;
    });
    try {
      int? age;
      final ageText = _ageCtrl.text.trim();
      if (ageText.isNotEmpty) {
        age = int.tryParse(ageText);
      }
      setState(() {
        _myAgeYears = age;
      });
      final uri = Uri.parse('${widget.baseUrl}/me/nearby/profile');
      final body = <String, dynamic>{
        'status': _statusCtrl.text.trim(),
        'gender': _myGender.isEmpty ? null : _myGender,
        'age_years': _myAgeYears,
      };
      final resp = await http.post(
        uri,
        headers: await _hdrNearby(json: true),
        body: jsonEncode(body),
      );
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تم تحديث ملفك في \"الأشخاص القريبون\".'
                  : 'Your People nearby profile was updated.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر حفظ الملف القريب.'
                  : 'Could not save profile.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'حدث خطأ أثناء حفظ الملف القريب.'
                : 'Error while saving profile.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _profileSaving = false;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
      _locationDenied = false;
      _items = const [];
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _error = 'location_service_disabled';
          _loading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _locationDenied = true;
          _loading = false;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final uri = Uri.parse('${widget.baseUrl}/me/nearby').replace(
        queryParameters: <String, String>{
          'lat': pos.latitude.toString(),
          'lon': pos.longitude.toString(),
          'limit': '40',
        },
      );
      final r = await http.get(uri, headers: await _hdrNearby());
      if (r.statusCode == 200) {
        final body = r.body;
        final decoded = body.isEmpty ? null : jsonDecode(body);
        List list;
        if (decoded is List) {
          list = decoded;
        } else if (decoded is Map && decoded['results'] is List) {
          list = decoded['results'] as List;
        } else {
          list = const [];
        }
        final mapped = list
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (!mounted) return;
        setState(() {
          _items = mapped;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = '${r.statusCode}: ${r.body}';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'error: $e';
        _loading = false;
      });
    }
  }

  double _distanceMeters(Map<String, dynamic> item) {
    final raw = item['distance_m'] ?? item['distance'] ?? '';
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0.0;
    return 0.0;
  }

  String _distanceLabel(double meters) {
    if (meters <= 0) return '';
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  bool _passesFilters(Map<String, dynamic> item) {
    final meters = _distanceMeters(item);
    if (_maxDistanceKm > 0 && meters > 0 && meters > _maxDistanceKm * 1000.0) {
      return false;
    }
    final statusText =
        ((item['status'] ?? item['bio'] ?? '')).toString().trim();
    if (_statusOnly && statusText.isEmpty) return false;

    final genderRaw = (item['gender'] ?? '').toString().toLowerCase();
    if (_genderFilter == 'male' && genderRaw != 'male') return false;
    if (_genderFilter == 'female' && genderRaw != 'female') return false;

    final ageRaw = (item['age'] ?? item['age_years'] ?? '').toString().trim();
    final age = int.tryParse(ageRaw) ?? 0;
    if (_ageFilter == '18_25' && !(age >= 18 && age <= 25)) return false;
    if (_ageFilter == '26_35' && !(age >= 26 && age <= 35)) return false;
    if (_ageFilter == '36_plus' && age > 0 && age < 36) return false;
    return true;
  }

  List<Map<String, dynamic>> _filteredItems() {
    return _items.where(_passesFilters).toList();
  }

  Future<void> _openFriendRequest(Map<String, dynamic> item) async {
    final id =
        (item['shamell_id'] ?? item['user_id'] ?? item['id'] ?? '').toString();
    final name = (item['name'] ?? item['nickname'] ?? '').toString();
    final display = name.isNotEmpty ? name : id;
    if (id.isEmpty && display.isEmpty) return;

    final l = L10n.of(context);
    if (id.isEmpty) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 10,
                bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.isArabic ? 'إضافة صديق' : 'Add friend',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l.isArabic ? 'إغلاق' : 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    display,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.isArabic
                        ? 'افتح شاشة الأصدقاء وابحث عن هذا المعرف لإرسال طلب صداقة.'
                        : 'Open the Friends screen and search for this ID to send a friend request.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: WeChatPalette.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l.isArabic ? 'تم' : 'OK'),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    try {
      final uri = Uri.parse('${widget.baseUrl}/friends/request');
      final resp = await http.post(
        uri,
        headers: await _hdrNearby(json: true),
        body: jsonEncode({'target_id': id}),
      );
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        String msg;
        try {
          final decoded = jsonDecode(resp.body);
          final status =
              (decoded is Map ? (decoded['status'] ?? '').toString() : '')
                  .toLowerCase();
          if (status == 'already_friends') {
            msg = l.mirsaalFriendQrAlreadyFriends;
          } else if (status == 'pending') {
            msg = l.mirsaalFriendQrPending;
          } else {
            msg = l.mirsaalFriendQrSent;
          }
        } catch (_) {
          msg = l.mirsaalFriendQrSent;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.mirsaalFriendQrSendFailed),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.mirsaalFriendQrSendError),
        ),
      );
    }
  }

  void _openChat(Map<String, dynamic> item) {
    final id =
        (item['shamell_id'] ?? item['user_id'] ?? item['id'] ?? '').toString();
    if (id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ThreemaChatPage(baseUrl: widget.baseUrl, initialPeerId: id),
      ),
    );
  }

  Future<void> _showProfileSheet() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final fieldFill = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : WeChatPalette.searchFill;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.isArabic
                            ? 'ملفك في \"الأشخاص القريبون\"'
                            : 'People nearby profile',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l.isArabic ? 'إغلاق' : 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                if (_profileLoading) ...[
                  const SizedBox(height: 6),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _statusCtrl,
                  enabled: !_profileSaving,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: l.isArabic ? 'حالتك القريبة' : 'Nearby status',
                    hintText: l.isArabic
                        ? 'مثال: أبحث عن أصدقاء جدد بالقرب مني'
                        : 'E.g. Looking for new friends nearby',
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.isArabic ? 'جنسك (اختياري)' : 'Your gender (optional)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(l.isArabic ? 'غير محدد' : 'Not set'),
                      selected: _myGender.isEmpty,
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _myGender = '');
                      },
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? 'ذكر' : 'Male'),
                      selected: _myGender == 'male',
                      onSelected: (sel) =>
                          setState(() => _myGender = sel ? 'male' : ''),
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? 'أنثى' : 'Female'),
                      selected: _myGender == 'female',
                      onSelected: (sel) =>
                          setState(() => _myGender = sel ? 'female' : ''),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ageCtrl,
                  enabled: !_profileSaving,
                  keyboardType: TextInputType.number,
                  maxLength: 3,
                  decoration: InputDecoration(
                    counterText: '',
                    labelText:
                        l.isArabic ? 'عمرك (اختياري)' : 'Your age (optional)',
                    hintText: l.isArabic ? 'مثال: ٢٥' : 'e.g. 25',
                    filled: true,
                    fillColor: fieldFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: WeChatPalette.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _profileSaving
                      ? null
                      : () async {
                          await _saveProfile();
                          if (!mounted) return;
                          Navigator.of(ctx).pop();
                        },
                  child: Text(l.isArabic ? 'حفظ الملف' : 'Save profile'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showFiltersSheet() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.isArabic ? 'التصفية' : 'Filters',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _maxDistanceKm = 0;
                          _genderFilter = 'all';
                          _ageFilter = 'all';
                          _statusOnly = false;
                        });
                        Navigator.of(ctx).pop();
                      },
                      child: Text(l.isArabic ? 'إعادة ضبط' : 'Reset'),
                    ),
                    IconButton(
                      tooltip: l.isArabic ? 'إغلاق' : 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l.isArabic ? 'المسافة' : 'Distance',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(l.isArabic ? 'الكل' : 'All'),
                      selected: _maxDistanceKm == 0,
                      onSelected: (sel) => setState(() => _maxDistanceKm = 0),
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? '< 1 كم' : '< 1 km'),
                      selected: _maxDistanceKm == 1,
                      onSelected: (sel) =>
                          setState(() => _maxDistanceKm = sel ? 1 : 0),
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? '< 5 كم' : '< 5 km'),
                      selected: _maxDistanceKm == 5,
                      onSelected: (sel) =>
                          setState(() => _maxDistanceKm = sel ? 5 : 0),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l.isArabic ? 'الجنس' : 'Gender',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(l.isArabic ? 'أيّ جنس' : 'Any'),
                      selected: _genderFilter == 'all',
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _genderFilter = 'all');
                      },
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? 'ذكور فقط' : 'Only male'),
                      selected: _genderFilter == 'male',
                      onSelected: (sel) =>
                          setState(() => _genderFilter = sel ? 'male' : 'all'),
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? 'إناث فقط' : 'Only female'),
                      selected: _genderFilter == 'female',
                      onSelected: (sel) => setState(
                          () => _genderFilter = sel ? 'female' : 'all'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l.isArabic ? 'العمر' : 'Age',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(l.isArabic ? 'الكل' : 'All'),
                      selected: _ageFilter == 'all',
                      onSelected: (sel) {
                        if (!sel) return;
                        setState(() => _ageFilter = 'all');
                      },
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? '١٨-٢٥' : '18-25'),
                      selected: _ageFilter == '18_25',
                      onSelected: (sel) =>
                          setState(() => _ageFilter = sel ? '18_25' : 'all'),
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? '٢٦-٣٥' : '26-35'),
                      selected: _ageFilter == '26_35',
                      onSelected: (sel) =>
                          setState(() => _ageFilter = sel ? '26_35' : 'all'),
                    ),
                    ChoiceChip(
                      label: Text(l.isArabic ? '٣٦+' : '36+'),
                      selected: _ageFilter == '36_plus',
                      onSelected: (sel) =>
                          setState(() => _ageFilter = sel ? '36_plus' : 'all'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.isArabic ? 'الحالة فقط' : 'Status only'),
                  subtitle: Text(
                    l.isArabic
                        ? 'اعرض الأشخاص الذين لديهم حالة فقط.'
                        : 'Only show users with a status.',
                  ),
                  value: _statusOnly,
                  onChanged: (v) => setState(() => _statusOnly = v),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: WeChatPalette.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.isArabic ? 'تم' : 'Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _recommendedOfficialsSection(
    ThemeData theme,
    L10n l,
    List<OfficialAccountHandle> officials,
    String? cityLabel,
  ) {
    if (officials.isEmpty) return const SizedBox.shrink();
    final title = cityLabel != null && cityLabel.isNotEmpty
        ? (l.isArabic
            ? 'الخدمات الرسمية في $cityLabel'
            : 'Official services in $cityLabel')
        : (l.isArabic ? 'الخدمات الرسمية القريبة' : 'Nearby official services');
    final subtitle = l.isArabic
        ? 'حسابات خدمات Shamell التي قد تهمّك في منطقتك.'
        : 'Shamell service accounts that might be relevant around you.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .65),
            ),
          ),
        ),
        WeChatSection(
          margin: const EdgeInsets.only(top: 8),
          dividerIndent: 0,
          children: [
            SizedBox(
              height: 82,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: officials.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final acc = officials[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OfficialAccountFeedPage(
                            baseUrl: widget.baseUrl,
                            account: acc,
                            onOpenChat: (peerId) {
                              if (peerId.isEmpty) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ThreemaChatPage(
                                    baseUrl: widget.baseUrl,
                                    initialPeerId: peerId,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 200,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: .40),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundImage: acc.avatarUrl != null &&
                                    acc.avatarUrl!.isNotEmpty
                                ? NetworkImage(acc.avatarUrl!)
                                : null,
                            child: acc.avatarUrl == null
                                ? Text(
                                    acc.name.isNotEmpty
                                        ? acc.name.characters.first
                                            .toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  acc.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  acc.category?.isNotEmpty == true
                                      ? acc.category!
                                      : (acc.city?.isNotEmpty == true
                                          ? acc.city!
                                          : (l.isArabic
                                              ? 'حساب خدمة رسمي'
                                              : 'Official service account')),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .70),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : WeChatPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    String profileSummary() {
      final parts = <String>[];
      final status = _statusCtrl.text.trim();
      if (status.isNotEmpty) parts.add(status);
      if (_myGender == 'male') {
        parts.add(l.isArabic ? 'ذكر' : 'Male');
      } else if (_myGender == 'female') {
        parts.add(l.isArabic ? 'أنثى' : 'Female');
      }
      final age = _myAgeYears;
      if (age != null && age > 0) {
        parts.add(l.isArabic ? '$age سنة' : '$age yrs');
      }
      if (parts.isNotEmpty) return parts.join(' · ');
      return l.isArabic ? 'اضغط لضبط ملفك' : 'Tap to set up your profile';
    }

    String filtersSummary() {
      final parts = <String>[];
      if (_maxDistanceKm == 1) {
        parts.add(l.isArabic ? '< 1 كم' : '< 1 km');
      } else if (_maxDistanceKm == 5) {
        parts.add(l.isArabic ? '< 5 كم' : '< 5 km');
      } else {
        parts.add(l.isArabic ? 'الكل' : 'All distances');
      }
      if (_genderFilter == 'male') {
        parts.add(l.isArabic ? 'ذكور فقط' : 'Only male');
      } else if (_genderFilter == 'female') {
        parts.add(l.isArabic ? 'إناث فقط' : 'Only female');
      } else {
        parts.add(l.isArabic ? 'أيّ جنس' : 'Any gender');
      }
      switch (_ageFilter) {
        case '18_25':
          parts.add(l.isArabic ? '١٨-٢٥' : '18-25');
          break;
        case '26_35':
          parts.add(l.isArabic ? '٢٦-٣٥' : '26-35');
          break;
        case '36_plus':
          parts.add(l.isArabic ? '٣٦+' : '36+');
          break;
        default:
          parts.add(l.isArabic ? 'أيّ عمر' : 'Any age');
      }
      if (_statusOnly) parts.add(l.isArabic ? 'الحالة فقط' : 'Status only');
      return parts.join(' · ');
    }

    final officials =
        widget.recommendedOfficials ?? const <OfficialAccountHandle>[];
    final filteredItems = _filteredItems();

    Widget topSection() {
      return WeChatSection(
        children: [
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.person_outline,
              background: Color(0xFF3B82F6),
            ),
            title: Text(l.isArabic ? 'ملفي' : 'My profile'),
            subtitle: Text(profileSummary()),
            trailing: chevron(),
            onTap: _showProfileSheet,
          ),
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.radar_outlined,
              background: WeChatPalette.green,
            ),
            title: Text(l.isArabic ? 'اكتشف الآن' : 'Discover now'),
            subtitle: Text(
              l.isArabic
                  ? 'هزّ (أو اضغط) لاكتشاف أشخاص قريبين.'
                  : 'Shake (or tap) to discover nearby people.',
            ),
            trailing: chevron(),
            onTap: _load,
          ),
          ListTile(
            dense: true,
            leading: const WeChatLeadingIcon(
              icon: Icons.tune_outlined,
              background: Color(0xFFF59E0B),
            ),
            title: Text(l.isArabic ? 'التصفية' : 'Filters'),
            subtitle: Text(filtersSummary()),
            trailing: chevron(),
            onTap: _showFiltersSheet,
          ),
        ],
      );
    }

    Widget peopleListSection() {
      if (filteredItems.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l.isArabic
                ? 'لا يوجد أشخاص ضمن هذا النطاق حتى الآن.'
                : 'No people within this distance yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
        );
      }

      return WeChatSection(
        margin: const EdgeInsets.only(top: 12, bottom: 12),
        children: [
          for (final item in filteredItems)
            Builder(
              builder: (ctx) {
                final name =
                    (item['name'] ?? item['nickname'] ?? item['title'] ?? '')
                        .toString();
                final id =
                    (item['shamell_id'] ?? item['user_id'] ?? item['id'] ?? '')
                        .toString();
                final meters = _distanceMeters(item);
                final distance = _distanceLabel(meters);
                final statusText =
                    ((item['status'] ?? item['bio'] ?? '')).toString().trim();
                final genderRaw =
                    (item['gender'] ?? '').toString().toLowerCase();
                final ageRaw =
                    (item['age'] ?? item['age_years'] ?? '').toString().trim();
                final age = int.tryParse(ageRaw) ?? 0;

                final metaParts = <String>[];
                if (distance.isNotEmpty) metaParts.add(distance);
                if (genderRaw == 'male') {
                  metaParts.add(l.isArabic ? 'ذكر' : 'Male');
                } else if (genderRaw == 'female') {
                  metaParts.add(l.isArabic ? 'أنثى' : 'Female');
                }
                if (age > 0)
                  metaParts.add(l.isArabic ? '$age سنة' : '$age yrs');
                if (id.isNotEmpty) {
                  metaParts.add(
                      l.isArabic ? 'معرّف Shamell: $id' : 'Shamell ID: $id');
                }

                final initials = name.isNotEmpty
                    ? name.characters.first.toUpperCase()
                    : (id.isNotEmpty ? id.characters.first.toUpperCase() : '?');

                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: .10),
                    child: Text(
                      initials,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(
                    name.isNotEmpty
                        ? name
                        : (id.isNotEmpty ? id : l.unknownLabel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (metaParts.isNotEmpty)
                        Text(
                          metaParts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .65),
                          ),
                        ),
                      if (statusText.isNotEmpty)
                        Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                    ],
                  ),
                  trailing: SizedBox(
                    width: 88,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline, size: 20),
                          onPressed: id.isEmpty ? null : () => _openChat(item),
                          tooltip: l.isArabic ? 'دردشة' : 'Chat',
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_1_outlined,
                              size: 20),
                          onPressed: () => _openFriendRequest(item),
                          tooltip: l.isArabic ? 'إضافة' : 'Add',
                        ),
                      ],
                    ),
                  ),
                  onTap: () => _openChat(item),
                );
              },
            ),
        ],
      );
    }

    Widget content;
    if (_locationDenied) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 8),
          topSection(),
          WeChatSection(
            children: [
              ListTile(
                dense: true,
                leading: const WeChatLeadingIcon(
                  icon: Icons.location_on_outlined,
                  background: Color(0xFFEF4444),
                ),
                title: Text(l.isArabic
                    ? 'صلاحيات الموقع مطلوبة'
                    : 'Location permission required'),
                subtitle: Text(l.isArabic
                    ? 'اسمح للتطبيق بالوصول إلى موقعك من إعدادات النظام.'
                    : 'Allow location access in system settings.'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: WeChatPalette.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _load,
              child: Text(l.isArabic ? 'إعادة المحاولة' : 'Retry'),
            ),
          ),
        ],
      );
    } else if (_error.isNotEmpty) {
      final label = _error == 'location_service_disabled'
          ? (l.isArabic
              ? 'خدمة الموقع غير مفعلة'
              : 'Location services are disabled')
          : (l.isArabic
              ? 'تعذّر تحميل القائمة'
              : 'Could not load nearby people');
      final detail = _error == 'location_service_disabled'
          ? (l.isArabic
              ? 'فعّل خدمة الموقع ثم حاول مرة أخرى.'
              : 'Enable location services and try again.')
          : _error;

      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 8),
          topSection(),
          WeChatSection(
            children: [
              ListTile(
                dense: true,
                leading: const WeChatLeadingIcon(
                  icon: Icons.error_outline,
                  background: Color(0xFFEF4444),
                ),
                title: Text(label),
                subtitle: Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: WeChatPalette.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _load,
              child: Text(l.isArabic ? 'إعادة المحاولة' : 'Retry'),
            ),
          ),
        ],
      );
    } else {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 8),
          topSection(),
          if (officials.isNotEmpty)
            _recommendedOfficialsSection(
              theme,
              l,
              officials,
              widget.recommendedCityLabel,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              l.isArabic ? 'الأشخاص القريبون' : 'People nearby',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
          ),
          peopleListSection(),
        ],
      );
    }

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: content,
          );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الأشخاص القريبون' : 'People nearby'),
        backgroundColor: bgColor,
        elevation: 0.5,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'profile') {
                _showProfileSheet();
              } else if (v == 'filters') {
                _showFiltersSheet();
              } else if (v == 'refresh') {
                _load();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'profile',
                child: Text(l.isArabic ? 'ملفي' : 'My profile'),
              ),
              PopupMenuItem(
                value: 'filters',
                child: Text(l.isArabic ? 'التصفية' : 'Filters'),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Text(l.isArabic ? 'تحديث' : 'Refresh'),
              ),
            ],
          ),
        ],
      ),
      body: body,
    );
  }
}
