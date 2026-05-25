import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'http_error.dart';
import 'l10n.dart';
import 'session_cookie_store.dart';
import 'shamell_empty_state.dart';

class CardsOffersPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? httpClient;
  final String? officialAccountId;
  final String? miniProgramId;
  final String? kind;
  final bool mineOnly;
  final String? title;

  const CardsOffersPage({
    super.key,
    required this.baseUrl,
    this.httpClient,
    this.officialAccountId,
    this.miniProgramId,
    this.kind,
    this.mineOnly = false,
    this.title,
  });

  @override
  State<CardsOffersPage> createState() => _CardsOffersPageState();
}

class _CardsOffersPageState extends State<CardsOffersPage> {
  late final http.Client _http;
  late final bool _ownsHttp;
  bool _loading = true;
  String _error = '';
  String _filter = 'available';
  String? _busyOfferId;
  List<_CardOffer> _offers = const <_CardOffer>[];

  @override
  void initState() {
    super.initState();
    _filter = widget.mineOnly ? 'saved' : 'available';
    _ownsHttp = widget.httpClient == null;
    _http = widget.httpClient ?? http.Client();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    if (_ownsHttp) {
      _http.close();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CardsOffersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseUrl != widget.baseUrl ||
        oldWidget.officialAccountId != widget.officialAccountId ||
        oldWidget.miniProgramId != widget.miniProgramId ||
        oldWidget.kind != widget.kind ||
        oldWidget.mineOnly != widget.mineOnly) {
      if (widget.mineOnly && _filter == 'available') {
        _filter = 'saved';
      }
      unawaited(_load());
    }
  }

  Uri _offersUri() {
    final uri = Uri.parse('${widget.baseUrl}/cards/offers');
    final query = <String, String>{};
    void setParam(String key, String? value) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) {
        query[key] = normalized;
      }
    }

    setParam('official_account_id', widget.officialAccountId);
    setParam('mini_program_id', widget.miniProgramId);
    setParam('kind', widget.kind);
    if (widget.mineOnly) {
      query['mine'] = 'true';
    }
    return query.isEmpty ? uri : uri.replace(queryParameters: query);
  }

  Future<void> _load() async {
    final l = L10n.of(context);
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = _offersUri();
      final response = await _http.get(
        uri,
        headers: await shamellSessionHeadersForBaseUrl(widget.baseUrl),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _error = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(response.body);
      final raw = decoded is Map && decoded['offers'] is List
          ? decoded['offers'] as List
          : const <dynamic>[];
      final offers = raw
          .whereType<Map>()
          .map((item) => _CardOffer.fromJson(item.cast<String, dynamic>()))
          .where((offer) => offer.id.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _loading = false;
        _error = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = l.isArabic
            ? 'تعذر تحميل البطاقات والعروض.'
            : 'Could not load cards and offers.';
        _loading = false;
      });
    }
  }

  Future<void> _mutate(_CardOffer offer, String action) async {
    final l = L10n.of(context);
    setState(() => _busyOfferId = offer.id);
    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/cards/offers/${Uri.encodeComponent(offer.id)}/$action',
      );
      final response = await _http.post(
        uri,
        headers: await shamellSessionHeadersForBaseUrl(
          widget.baseUrl,
          json: true,
        ),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sanitizeHttpError(
                statusCode: response.statusCode,
                rawBody: response.body,
                isArabic: l.isArabic,
              ),
            ),
          ),
        );
        return;
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'redeem'
                ? (l.isArabic ? 'تم استخدام العرض.' : 'Offer redeemed.')
                : (l.isArabic ? 'تم حفظ العرض.' : 'Offer saved to cards.'),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تعذر تحديث العرض.' : 'Could not update this offer.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyOfferId = null);
      }
    }
  }

  List<_CardOffer> get _filteredOffers {
    switch (_filter) {
      case 'saved':
        return _offers.where((offer) => offer.owned).toList(growable: false);
      case 'redeemed':
        return _offers
            .where((offer) => offer.status == 'redeemed')
            .toList(growable: false);
      case 'available':
        return _offers
            .where((offer) => offer.status != 'redeemed')
            .toList(growable: false);
      default:
        return _offers;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final offers = _filteredOffers;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          widget.title?.trim().isNotEmpty == true
              ? widget.title!.trim()
              : (l.isArabic ? 'البطاقات والعروض' : 'Cards & Offers'),
        ),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _summaryBand(l),
            const SizedBox(height: 12),
            _filterBar(l),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error.isNotEmpty)
              _errorPanel(l)
            else if (offers.isEmpty)
              _emptyPanel(l)
            else
              for (final offer in offers) ...[
                _offerTile(offer, l),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _summaryBand(L10n l) {
    final theme = Theme.of(context);
    final saved = _offers.where((offer) => offer.owned).length;
    final redeemed =
        _offers.where((offer) => offer.status == 'redeemed').length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07C160).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF07C160).withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF07C160),
            foregroundColor: Colors.white,
            child: Icon(Icons.local_offer_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic ? 'محفظة عروضك' : 'Your offer wallet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.isArabic
                      ? '$saved محفوظة · $redeemed مستخدمة'
                      : '$saved saved · $redeemed redeemed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(L10n l) {
    final filters = <String, String>{
      'available': l.isArabic ? 'متاحة' : 'Available',
      'saved': l.isArabic ? 'محفوظة' : 'Saved',
      'redeemed': l.isArabic ? 'مستخدمة' : 'Redeemed',
      'all': l.isArabic ? 'الكل' : 'All',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in filters.entries) ...[
            ChoiceChip(
              label: Text(entry.value),
              selected: _filter == entry.key,
              onSelected: (_) => setState(() => _filter = entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _errorPanel(L10n l) {
    return ShamellEmptyState.error(
      title: _error,
      actionLabel: l.isArabic ? 'إعادة المحاولة' : 'Retry',
      onAction: () => unawaited(_load()),
    );
  }

  Widget _emptyPanel(L10n l) {
    return ShamellEmptyState.empty(
      icon: Icons.local_offer_outlined,
      title: l.isArabic
          ? 'لا توجد عروض في هذا القسم.'
          : 'No offers in this section.',
      actionLabel: l.isArabic ? 'تحديث' : 'Refresh',
      onAction: () => unawaited(_load()),
    );
  }

  Widget _offerTile(_CardOffer offer, L10n l) {
    final theme = Theme.of(context);
    final busy = _busyOfferId == offer.id;
    final status = offer.status;
    final canRedeem = offer.owned && status != 'redeemed';
    final actionLabel = status == 'redeemed'
        ? (l.isArabic ? 'مستخدمة' : 'Redeemed')
        : canRedeem
            ? (l.isArabic ? 'استخدم' : 'Redeem')
            : (l.isArabic ? 'احفظ' : 'Claim');
    final subtitle = [
      if (offer.officialName.isNotEmpty) offer.officialName,
      offer.kindLabel,
      if (offer.discountText.isNotEmpty) offer.discountText,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _kindColor(offer.kind).withValues(alpha: 0.12),
            foregroundColor: _kindColor(offer.kind),
            child: Icon(_kindIcon(offer.kind)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.isArabic ? offer.titleArOrEn : offer.titleEn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (offer.featured)
                      Icon(
                        Icons.star,
                        size: 16,
                        color: const Color(0xFFB45309),
                      ),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.64),
                    ),
                  ),
                ],
                if (offer.description(l).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    offer.description(l),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _metricChip(
                      icon: Icons.wallet_membership_outlined,
                      label: l.isArabic
                          ? '${offer.claimedCount} حفظ'
                          : '${offer.claimedCount} saved',
                    ),
                    _metricChip(
                      icon: Icons.task_alt_outlined,
                      label: l.isArabic
                          ? '${offer.redeemedCount} استخدام'
                          : '${offer.redeemedCount} redeemed',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: FilledButton(
              onPressed: busy || status == 'redeemed'
                  ? null
                  : () =>
                      unawaited(_mutate(offer, canRedeem ? 'redeem' : 'claim')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      actionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip({required IconData icon, required String label}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  Color _kindColor(String kind) {
    switch (kind) {
      case 'member_card':
        return const Color(0xFF2563EB);
      case 'event_pass':
        return const Color(0xFF7C3AED);
      case 'service_pass':
        return const Color(0xFF0F766E);
      case 'gift':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF07C160);
    }
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'member_card':
        return Icons.badge_outlined;
      case 'event_pass':
        return Icons.event_available_outlined;
      case 'service_pass':
        return Icons.confirmation_number_outlined;
      case 'gift':
        return Icons.card_giftcard_outlined;
      default:
        return Icons.local_offer_outlined;
    }
  }
}

class _CardOffer {
  final String id;
  final String titleEn;
  final String titleAr;
  final String descriptionEn;
  final String descriptionAr;
  final String kind;
  final String discountText;
  final String officialName;
  final bool featured;
  final bool owned;
  final String status;
  final int claimedCount;
  final int redeemedCount;

  const _CardOffer({
    required this.id,
    required this.titleEn,
    required this.titleAr,
    required this.descriptionEn,
    required this.descriptionAr,
    required this.kind,
    required this.discountText,
    required this.officialName,
    required this.featured,
    required this.owned,
    required this.status,
    required this.claimedCount,
    required this.redeemedCount,
  });

  factory _CardOffer.fromJson(Map<String, dynamic> json) {
    return _CardOffer(
      id: (json['id'] ?? json['offer_id'] ?? '').toString().trim(),
      titleEn: (json['title_en'] ?? '').toString().trim(),
      titleAr: (json['title_ar'] ?? '').toString().trim(),
      descriptionEn: (json['description_en'] ?? '').toString().trim(),
      descriptionAr: (json['description_ar'] ?? '').toString().trim(),
      kind: (json['kind'] ?? 'coupon').toString().trim(),
      discountText: (json['discount_text'] ?? '').toString().trim(),
      officialName: (json['official_name'] ?? '').toString().trim(),
      featured: json['featured'] == true,
      owned: json['owned'] == true || json['status'] != null,
      status: (json['status'] ?? '').toString().trim(),
      claimedCount: _intValue(json['claimed_count']),
      redeemedCount: _intValue(json['redeemed_count']),
    );
  }

  String get titleArOrEn => titleAr.isNotEmpty ? titleAr : titleEn;

  String description(L10n l) {
    if (l.isArabic && descriptionAr.isNotEmpty) return descriptionAr;
    return descriptionEn;
  }

  String get kindLabel => kind.replaceAll('_', ' ');

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }
}
