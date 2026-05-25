import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'design_tokens.dart';
import 'format.dart';
import 'session_cookie_store.dart';
import 'wechat_ui.dart';

class CoachMiniProgramPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;

  const CoachMiniProgramPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
  });

  @override
  State<CoachMiniProgramPage> createState() => _CoachMiniProgramPageState();
}

class _CoachMiniProgramPageState extends State<CoachMiniProgramPage> {
  final TextEditingController _fromCtrl =
      TextEditingController(text: 'Damascus');
  final TextEditingController _toCtrl = TextEditingController(text: 'Aleppo');
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  int _passengers = 1;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _journeys = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_search());
    });
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl);
  }

  Uri _apiUri(String path, Map<String, String> query) {
    final base = Uri.parse(widget.baseUrl.trim());
    return base.resolve(path).replace(queryParameters: query);
  }

  String _dateParam(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
    });
    unawaited(_search());
  }

  Future<void> _search() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) {
      setState(() {
        _error = 'Enter origin and destination.';
      });
      return;
    }
    if (from.toLowerCase() == to.toLowerCase()) {
      setState(() {
        _error = 'Origin and destination must be different.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = _apiUri('/me/coach/search', <String, String>{
        'from': from,
        'to': to,
        'departure_date': _dateParam(_date),
        'passengers': _passengers.toString(),
      });
      final resp = await http.get(uri, headers: await _headers());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Search failed (${resp.statusCode})');
      }
      final decoded = jsonDecode(resp.body);
      final journeys = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['journeys'] is List) {
        for (final item in decoded['journeys'] as List) {
          if (item is Map) {
            journeys.add(item.cast<String, dynamic>());
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _journeys = journeys;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Coach search is not available right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _swapRoute() {
    final from = _fromCtrl.text;
    _fromCtrl.text = _toCtrl.text;
    _toCtrl.text = from;
    unawaited(_search());
  }

  String _timeLabel(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _durationLabel(int minutes) {
    if (minutes <= 0) return '-';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h <= 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _priceLabel(Map<String, dynamic> journey) {
    final amount = journey['price_from_minor_units'];
    final currency = (journey['currency'] ?? '').toString().trim();
    if (amount == null) return '-';
    final value = fmtCents(amount);
    return currency.isEmpty ? value : '$value $currency';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : WeChatPalette.background,
      appBar: AppBar(
        title: const Text('Coach'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: .4,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => unawaited(_search()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _search,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SearchPanel(
              fromCtrl: _fromCtrl,
              toCtrl: _toCtrl,
              dateLabel: _dateParam(_date),
              passengers: _passengers,
              loading: _loading,
              onSwap: _swapRoute,
              onPickDate: _pickDate,
              onPassengersChanged: (value) {
                setState(() {
                  _passengers = value.clamp(1, 8);
                });
                unawaited(_search());
              },
              onSearch: () => unawaited(_search()),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 16),
            _SectionHeader(
              title: 'Available journeys',
              trailing: _journeys.isEmpty ? null : '${_journeys.length}',
            ),
            const SizedBox(height: 8),
            if (_journeys.isEmpty && !_loading)
              const _EmptyState(
                title: 'No journeys found',
                body: 'Try another city pair, travel date, or passenger count.',
              )
            else
              for (final journey in _journeys) ...[
                _JourneyCard(
                  journey: journey,
                  departureLabel:
                      _timeLabel((journey['departure_at'] ?? '').toString()),
                  arrivalLabel:
                      _timeLabel((journey['arrival_at'] ?? '').toString()),
                  durationLabel: _durationLabel(
                    (journey['duration_minutes'] is num)
                        ? (journey['duration_minutes'] as num).toInt()
                        : 0,
                  ),
                  priceLabel: _priceLabel(journey),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _SearchPanel extends StatelessWidget {
  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final String dateLabel;
  final int passengers;
  final bool loading;
  final VoidCallback onSwap;
  final VoidCallback onPickDate;
  final ValueChanged<int> onPassengersChanged;
  final VoidCallback onSearch;

  const _SearchPanel({
    required this.fromCtrl,
    required this.toCtrl,
    required this.dateLabel,
    required this.passengers,
    required this.loading,
    required this.onSwap,
    required this.onPickDate,
    required this.onPassengersChanged,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .38 : .82),
          width: .7,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .14 : .04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 390;
              final fromField = _RouteField(
                controller: fromCtrl,
                label: 'From',
                icon: Icons.trip_origin,
              );
              final toField = _RouteField(
                controller: toCtrl,
                label: 'To',
                icon: Icons.location_on_outlined,
              );
              final swapButton = IconButton.filledTonal(
                tooltip: 'Swap',
                onPressed: onSwap,
                icon: const Icon(Icons.swap_horiz),
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    fromField,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.center, child: swapButton),
                    const SizedBox(height: 8),
                    toField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: fromField),
                  const SizedBox(width: 8),
                  swapButton,
                  const SizedBox(width: 8),
                  Expanded(child: toField),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final dateButton = OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
              final stepper = _PassengerStepper(
                value: passengers,
                onChanged: onPassengersChanged,
              );
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dateButton,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: stepper),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: dateButton),
                  const SizedBox(width: 10),
                  stepper,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: loading ? null : onSearch,
            icon: const Icon(Icons.search),
            label: const Text('Search coaches'),
            style: FilledButton.styleFrom(
              backgroundColor: WeChatPalette.green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;

  const _RouteField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18),
        labelText: label,
        isDense: true,
      ),
    );
  }
}

class _PassengerStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PassengerStepper({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .24)
            : WeChatPalette.searchFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .34 : .82),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Fewer passengers',
            onPressed: value <= 1 ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove, size: 18),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 34),
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge,
            ),
          ),
          IconButton(
            tooltip: 'More passengers',
            onPressed: value >= 8 ? null : () => onChanged(value + 1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final Map<String, dynamic> journey;
  final String departureLabel;
  final String arrivalLabel;
  final String durationLabel;
  final String priceLabel;

  const _JourneyCard({
    required this.journey,
    required this.departureLabel,
    required this.arrivalLabel,
    required this.durationLabel,
    required this.priceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final operator = (journey['operator_name'] ?? 'Coach service').toString();
    final from = (journey['from'] ?? '').toString();
    final to = (journey['to'] ?? '').toString();
    final seats = (journey['seats_available'] is num)
        ? (journey['seats_available'] as num).toInt()
        : null;
    final transfers = (journey['transfer_count'] is num)
        ? (journey['transfer_count'] as num).toInt()
        : 0;
    final lowAvailability = journey['low_availability'] == true;
    final amenities = <String>[];
    final rawAmenities = journey['amenities'];
    if (rawAmenities is List) {
      for (final item in rawAmenities) {
        final label = (item ?? '').toString().trim();
        if (label.isNotEmpty) amenities.add(label);
      }
    }

    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: .82),
          width: .7,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Tokens.colorBus.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.directions_bus_filled_outlined,
                    color: Tokens.colorBus,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        operator,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        from.isEmpty && to.isEmpty
                            ? 'Intercity coach'
                            : '$from -> $to',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .68),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  priceLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Tokens.colorPayments,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _TimeBlock(label: 'Depart', value: departureLabel),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      children: [
                        Container(
                          height: 1,
                          color: theme.dividerColor,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          transfers == 0 ? 'Direct' : '$transfers transfer',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .62),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _TimeBlock(label: 'Arrive', value: arrivalLabel),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _InfoChip(icon: Icons.schedule, label: durationLabel),
                if (seats != null)
                  _InfoChip(
                    icon: lowAvailability
                        ? Icons.event_seat
                        : Icons.event_seat_outlined,
                    label: lowAvailability
                        ? '$seats seats left'
                        : '$seats seats available',
                    warning: lowAvailability,
                  ),
                for (final amenity in amenities.take(3))
                  _InfoChip(
                    icon: _amenityIcon(amenity),
                    label: _amenityLabel(amenity),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _amenityIcon(String value) {
    final key = value.toLowerCase();
    if (key.contains('wifi')) return Icons.wifi;
    if (key.contains('power')) return Icons.power;
    if (key.contains('seat')) return Icons.airline_seat_recline_normal;
    if (key.contains('toilet')) return Icons.wc_outlined;
    return Icons.check_circle_outline;
  }

  String _amenityLabel(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.substring(0, 1).toUpperCase() + part.substring(1))
        .join(' ');
  }
}

class _TimeBlock extends StatelessWidget {
  final String label;
  final String value;

  const _TimeBlock({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .58),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool warning;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warning ? Tokens.warning : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: .82)),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color.withValues(alpha: .84),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .72),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .56),
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: theme.colorScheme.error.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyState({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .82)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.route_outlined,
            size: 28,
            color: theme.colorScheme.onSurface.withValues(alpha: .44),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .64),
            ),
          ),
        ],
      ),
    );
  }
}
