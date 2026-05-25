import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';
import 'session_cookie_store.dart';
import 'shamell_empty_state.dart';

class NearbyCategory {
  final String id;
  final IconData icon;
  const NearbyCategory(this.id, this.icon);
}

// "bar" and "cinema" were intentionally removed from this list — they
// surfaced too sparsely in operator regions and made the quick-pick
// chips noisier than helpful. The Nearby Overpass query is built from
// this list, so dropping the entries here retires them app-wide.
const List<NearbyCategory> kNearbyCategories = <NearbyCategory>[
  NearbyCategory('restaurant', Icons.restaurant),
  NearbyCategory('cafe', Icons.local_cafe),
  NearbyCategory('fast_food', Icons.fastfood),
  NearbyCategory('bakery', Icons.bakery_dining),
  NearbyCategory('supermarket', Icons.local_grocery_store),
  NearbyCategory('convenience', Icons.storefront),
  NearbyCategory('fuel', Icons.local_gas_station),
  NearbyCategory('charging_station', Icons.ev_station),
  NearbyCategory('parking', Icons.local_parking),
  NearbyCategory('pharmacy', Icons.local_pharmacy),
  NearbyCategory('hospital', Icons.local_hospital),
  NearbyCategory('doctors', Icons.medical_services),
  NearbyCategory('dentist', Icons.medical_information),
  NearbyCategory('atm', Icons.atm),
  NearbyCategory('bank', Icons.account_balance),
  NearbyCategory('hotel', Icons.hotel),
  NearbyCategory('park', Icons.park),
  NearbyCategory('museum', Icons.museum),
  NearbyCategory('fitness', Icons.fitness_center),
  NearbyCategory('library', Icons.local_library),
  NearbyCategory('post_office', Icons.local_post_office),
  NearbyCategory('police', Icons.local_police),
  NearbyCategory('toilets', Icons.wc),
];

const List<int> _kRadiusOptionsM = <int>[500, 1500, 3000, 5000, 10000];

class NearbyPage extends StatefulWidget {
  final String baseUrl;

  const NearbyPage({super.key, required this.baseUrl});

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> {
  bool _loading = false;
  String _error = '';
  bool _locationDenied = false;
  bool _serviceDisabled = false;
  Position? _position;
  int _radiusM = 1500;
  final Set<String> _selectedCats = <String>{};
  List<Map<String, dynamic>> _places = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _selectedCats.addAll(kNearbyCategories.map((c) => c.id));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<Map<String, String>> _headers() {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
      _locationDenied = false;
      _serviceDisabled = false;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _serviceDisabled = true;
          _loading = false;
          _places = const [];
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
          _places = const [];
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      _position = pos;
      await _fetchPlaces();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'location_failed';
        _loading = false;
      });
    }
  }

  Future<void> _fetchPlaces() async {
    final pos = _position;
    if (pos == null) return;
    final cats = _selectedCats.isEmpty
        ? kNearbyCategories.map((c) => c.id).join(',')
        : _selectedCats.join(',');
    final uri = Uri.parse('${widget.baseUrl}/me/places').replace(
      queryParameters: <String, String>{
        'lat': pos.latitude.toString(),
        'lon': pos.longitude.toString(),
        'radius_m': _radiusM.toString(),
        'cats': cats,
        'limit': '60',
      },
    );
    try {
      final r = await http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      if (r.statusCode == 200) {
        final decoded = r.body.isEmpty ? null : jsonDecode(r.body);
        final raw = (decoded is Map && decoded['places'] is List)
            ? (decoded['places'] as List)
            : const <dynamic>[];
        final mapped = raw
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(growable: false);
        setState(() {
          _places = mapped;
          _loading = false;
        });
      } else if (r.statusCode == 502 || r.statusCode == 503) {
        setState(() {
          _error = 'provider_unavailable';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'http_${r.statusCode}';
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'network';
        _loading = false;
      });
    }
  }

  void _toggleCategory(String id) {
    setState(() {
      if (_selectedCats.contains(id)) {
        _selectedCats.remove(id);
      } else {
        _selectedCats.add(id);
      }
    });
    if (_position != null) {
      setState(() {
        _loading = true;
        _error = '';
      });
      _fetchPlaces();
    }
  }

  void _toggleAll(bool selectAll) {
    setState(() {
      _selectedCats.clear();
      if (selectAll) {
        _selectedCats.addAll(kNearbyCategories.map((c) => c.id));
      }
    });
    if (_position != null) {
      setState(() {
        _loading = true;
        _error = '';
      });
      _fetchPlaces();
    }
  }

  Future<void> _pickRadius() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in _kRadiusOptionsM)
                ListTile(
                  leading: r == _radiusM
                      ? const Icon(Icons.radio_button_checked)
                      : const Icon(Icons.radio_button_unchecked),
                  title: Text(_formatRadius(r)),
                  onTap: () => Navigator.of(ctx).pop(r),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null && picked != _radiusM) {
      setState(() {
        _radiusM = picked;
        _loading = true;
        _error = '';
      });
      _fetchPlaces();
    }
  }

  String _formatRadius(int m) {
    final l = L10n.of(context);
    if (m >= 1000) return l.nearbyDistanceKm(m / 1000);
    return l.nearbyDistanceMeters(m);
  }

  String _formatDistance(num m) {
    final l = L10n.of(context);
    final meters = m.toDouble();
    if (meters >= 1000) return l.nearbyDistanceKm(meters / 1000);
    return l.nearbyDistanceMeters(meters.round());
  }

  Future<void> _openInMaps(Map<String, dynamic> p) async {
    final lat = (p['lat'] as num?)?.toDouble();
    final lng = (p['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final label = Uri.encodeComponent((p['name'] as String?) ?? '');
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng($label)');
    if (await canLaunchUrl(geo)) {
      await launchUrl(geo, mode: LaunchMode.externalApplication);
      return;
    }
    final web =
        Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=18/$lat/$lng');
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWebsite(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyAddress(BuildContext ctx, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(L10n.of(ctx).nearbyCopyAddress)),
    );
  }

  void _showPlaceActions(Map<String, dynamic> p) {
    final l = L10n.of(context);
    final address = (p['address'] as String?)?.trim();
    final phone = (p['phone'] as String?)?.trim();
    final website = (p['website'] as String?)?.trim();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.map_outlined),
                title: Text(l.nearbyOpenInMaps),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openInMaps(p);
                },
              ),
              if (address != null && address.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(l.nearbyCopyAddress),
                  subtitle: Text(address),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _copyAddress(context, address);
                  },
                ),
              if (phone != null && phone.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.call),
                  title: Text(l.nearbyCallPhone),
                  subtitle: Text(phone),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _callPhone(phone);
                  },
                ),
              if (website != null && website.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.open_in_browser),
                  title: Text(l.nearbyOpenWebsite),
                  subtitle: Text(website,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openWebsite(website);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconForCategory(String id) {
    for (final c in kNearbyCategories) {
      if (c.id == id) return c.icon;
    }
    return Icons.place;
  }

  Widget _buildCategoryChips() {
    final l = L10n.of(context);
    final allSelected = _selectedCats.length == kNearbyCategories.length;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              avatar: const Icon(Icons.apps, size: 18),
              label: Text(l.nearbyAllCategories),
              selected: allSelected,
              onSelected: (sel) => _toggleAll(sel),
            ),
          ),
          for (final c in kNearbyCategories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                avatar: Icon(c.icon, size: 18),
                label: Text(l.nearbyCategoryLabel(c.id)),
                selected: _selectedCats.contains(c.id),
                onSelected: (_) => _toggleCategory(c.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final l = L10n.of(context);
    if (_locationDenied) {
      return ShamellEmptyState.error(
        icon: Icons.location_off,
        title: l.nearbyLocationDenied,
        actionLabel: l.nearbyTitle,
        onAction: _refresh,
      );
    }
    if (_serviceDisabled) {
      return ShamellEmptyState.error(
        icon: Icons.location_disabled,
        title: l.nearbyLocationFailed,
        actionLabel: l.nearbyTitle,
        onAction: _refresh,
      );
    }
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(l.nearbyLoading),
          ],
        ),
      );
    }
    if (_error == 'provider_unavailable') {
      return ShamellEmptyState.error(
        icon: Icons.cloud_off,
        title: l.nearbyProviderUnavailable,
        actionLabel: l.nearbyTitle,
        onAction: _refresh,
      );
    }
    if (_error.isNotEmpty) {
      return ShamellEmptyState.error(
        title: l.nearbyLocationFailed,
        actionLabel: l.nearbyTitle,
        onAction: _refresh,
      );
    }
    if (_places.isEmpty) {
      return ShamellEmptyState.noResults(
        title: l.nearbyEmpty,
      );
    }
    return ListView.separated(
      itemCount: _places.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = _places[i];
        final name = (p['name'] as String?) ?? '';
        final category = (p['category'] as String?) ?? '';
        final address = (p['address'] as String?) ?? '';
        final distance = p['distance_m'];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(ctx).colorScheme.primaryContainer,
            foregroundColor: Theme.of(ctx).colorScheme.onPrimaryContainer,
            child: Icon(_iconForCategory(category)),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            address.isEmpty
                ? L10n.of(ctx).nearbyCategoryLabel(category)
                : '${L10n.of(ctx).nearbyCategoryLabel(category)} • $address',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: distance is num
              ? Text(_formatDistance(distance))
              : const SizedBox.shrink(),
          onTap: () => _showPlaceActions(p),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.nearbyTitle),
        actions: [
          TextButton.icon(
            onPressed: _pickRadius,
            icon: const Icon(Icons.tune),
            label: Text(_formatRadius(_radiusM)),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 4),
          _buildCategoryChips(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}

