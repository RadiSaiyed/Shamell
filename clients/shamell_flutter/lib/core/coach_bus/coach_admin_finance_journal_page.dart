import 'package:flutter/material.dart';

import '../format.dart';
import '../safe_set_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_mobility_api.dart';

String _coachFinanceIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

String _coachFinanceMoneyLabel(String currency, int minorUnits) {
  return '${fmtCents(minorUnits)} $currency';
}

String _coachFinanceSignedMoneyLabel(String currency, int minorUnits) {
  if (minorUnits == 0) {
    return _coachFinanceMoneyLabel(currency, minorUnits);
  }
  final sign = minorUnits > 0 ? '+' : '-';
  return '$sign${fmtCents(minorUnits.abs())} $currency';
}

String _coachFinanceQueueLabel(String queue) {
  switch (queue) {
    case 'attention':
      return 'Attention';
    case 'refunds':
      return 'Refunds';
    case 'risk':
      return 'Risk';
    case 'accruals':
      return 'Accruals';
    case 'ready_for_payout':
      return 'Ready for payout';
    default:
      return 'All';
  }
}

String _coachFinanceSortLabel(String sort) {
  switch (sort) {
    case 'latest':
      return 'Latest activity';
    case 'amount':
      return 'Largest amount';
    default:
      return 'Priority';
  }
}

bool _coachFinanceMatchesQueue(
  CoachAdminFinanceJournalEntry entry,
  String queue,
) {
  switch (queue) {
    case 'attention':
      return entry.needsAttention;
    case 'refunds':
      return entry.eventType.contains('refund');
    case 'risk':
      return entry.eventType == 'risk_follow_up_auto_case';
    case 'accruals':
      return entry.eventType.contains('accrual') ||
          entry.eventType.contains('accrued');
    case 'ready_for_payout':
      return entry.status == 'ready_for_payout';
    default:
      return true;
  }
}

int _coachFinanceQueueCount(
  List<CoachAdminFinanceJournalEntry> entries,
  String queue,
) {
  return entries
      .where((entry) => _coachFinanceMatchesQueue(entry, queue))
      .length;
}

int _coachFinanceEventRank(String eventType) {
  if (eventType == 'risk_follow_up_auto_case') {
    return 0;
  }
  if (eventType.startsWith('travel_credit_refund') ||
      eventType.contains('refund')) {
    return 1;
  }
  if (eventType.contains('accrual') || eventType.contains('accrued')) {
    return 2;
  }
  if (eventType.startsWith('payout_')) {
    return 3;
  }
  if (eventType.contains('change')) {
    return 4;
  }
  return 5;
}

int _coachFinanceStatusRank(String status) {
  switch (status) {
    case 'open':
      return 0;
    case 'ready_for_payout':
      return 1;
    case 'approved':
      return 2;
    default:
      return 3;
  }
}

DateTime _coachFinanceTimestamp(String iso) {
  return DateTime.tryParse(iso)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _coachFinanceAmountMagnitude(CoachAdminFinanceJournalEntry entry) {
  return entry.primaryAmountMinorUnits.abs();
}

List<CoachAdminFinanceJournalEntry> _coachFinanceSortedEntries(
  List<CoachAdminFinanceJournalEntry> entries,
  String sort,
) {
  final out = List<CoachAdminFinanceJournalEntry>.of(entries);
  out.sort((left, right) {
    if (sort == 'latest') {
      final latestCompare = _coachFinanceTimestamp(
        right.occurredAtIso,
      ).compareTo(_coachFinanceTimestamp(left.occurredAtIso));
      if (latestCompare != 0) {
        return latestCompare;
      }
    }
    if (sort == 'amount') {
      final amountCompare = _coachFinanceAmountMagnitude(
        right,
      ).compareTo(_coachFinanceAmountMagnitude(left));
      if (amountCompare != 0) {
        return amountCompare;
      }
    }
    final attentionCompare = (right.needsAttention ? 1 : 0).compareTo(
      left.needsAttention ? 1 : 0,
    );
    if (attentionCompare != 0) {
      return attentionCompare;
    }
    final eventCompare = _coachFinanceEventRank(left.eventType).compareTo(
      _coachFinanceEventRank(right.eventType),
    );
    if (eventCompare != 0) {
      return eventCompare;
    }
    final statusCompare = _coachFinanceStatusRank(left.status).compareTo(
      _coachFinanceStatusRank(right.status),
    );
    if (statusCompare != 0) {
      return statusCompare;
    }
    final amountCompare = _coachFinanceAmountMagnitude(
      right,
    ).compareTo(_coachFinanceAmountMagnitude(left));
    if (amountCompare != 0) {
      return amountCompare;
    }
    final occurredCompare = _coachFinanceTimestamp(
      right.occurredAtIso,
    ).compareTo(_coachFinanceTimestamp(left.occurredAtIso));
    if (occurredCompare != 0) {
      return occurredCompare;
    }
    return left.entryId.compareTo(right.entryId);
  });
  return out;
}

IconData _coachFinanceEntryIcon(String eventType) {
  if (eventType == 'risk_follow_up_auto_case') {
    return Icons.warning_amber_outlined;
  }
  if (eventType.startsWith('payout_')) {
    return Icons.account_balance_wallet_outlined;
  }
  if (eventType.contains('refund')) {
    return Icons.undo_outlined;
  }
  if (eventType.contains('change')) {
    return Icons.swap_horiz_outlined;
  }
  return Icons.receipt_long_outlined;
}

class CoachAdminFinanceJournalPage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final CoachAdminFinanceJournalResponse? initialResponse;

  const CoachAdminFinanceJournalPage({
    super.key,
    required this.baseUrl,
    this.api,
    this.initialResponse,
  });

  @override
  State<CoachAdminFinanceJournalPage> createState() =>
      _CoachAdminFinanceJournalPageState();
}

class _CoachAdminFinanceJournalPageState
    extends State<CoachAdminFinanceJournalPage>
    with SafeSetStateMixin<CoachAdminFinanceJournalPage> {
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final TextEditingController _queryController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;
  CoachAdminFinanceJournalResponse? _response;
  String _selectedQueue = 'all';
  String _selectedSort = 'priority';

  @override
  void initState() {
    super.initState();
    _response = widget.initialResponse;
    if (_response == null) {
      _loadJournal();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadJournal() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final response = await _api.adminFinanceJournal(
        query: _queryController.text,
      );
      setState(() {
        _response = response;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _openEntryDetail(CoachAdminFinanceJournalEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: _CoachAdminFinanceJournalEntrySheet(entry: entry),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach finance'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadJournal,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _response == null) {
      return const ShamellSkeletonList(itemCount: 6);
    }
    final response = _response;
    final filteredEntries = response == null
        ? const <CoachAdminFinanceJournalEntry>[]
        : response.entries
            .where((entry) => _coachFinanceMatchesQueue(entry, _selectedQueue))
            .toList(growable: false);
    final visibleEntries = _coachFinanceSortedEntries(
      filteredEntries,
      _selectedSort,
    );
    return RefreshIndicator(
      onRefresh: _loadJournal,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search journal',
                    hintText: 'Booking, statement, payout, operator',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadJournal(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _loadJournal,
                child: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_errorMessage != null) ...[
            StatusBanner.error(_errorMessage!),
            const SizedBox(height: 12),
          ],
          if (_response == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No finance journal loaded yet.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _loadJournal,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Load journal'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFF8FBFF),
                    Color(0xFFEEF4FB),
                    Color(0xFFE6EDF7),
                  ],
                ),
                border: Border.all(color: const Color(0xFFD8E1ED)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x12081F17),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .82),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFD8E1ED)),
                    ),
                    child: Text(
                      'Coach admin queue',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF1D4ED8),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Finance command desk',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xFF1E293B),
                          fontWeight: FontWeight.w900,
                          height: .96,
                        ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Text(
                      'Triage money movement, accruals, payout readiness, and risk-linked finance fallout from one ledger-first queue. Start with attention-heavy entries, then drill into account movement detail.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF526176),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _CoachFinanceHeaderBadge(
                        icon: Icons.public_outlined,
                        label: 'Scope: Coach admin',
                      ),
                      _CoachFinanceHeaderBadge(
                        icon: Icons.priority_high_outlined,
                        label:
                            'Attention ${response!.summary.attentionEntries}',
                        color: const Color(0xFFB91C1C),
                      ),
                      _CoachFinanceHeaderBadge(
                        icon: Icons.receipt_long_outlined,
                        label: 'Accruals ${response.summary.accrualEntries}',
                        color: const Color(0xFFB45309),
                      ),
                      _CoachFinanceHeaderBadge(
                        icon: Icons.account_balance_wallet_outlined,
                        label:
                            'Payout-ready ${_coachFinanceQueueCount(response.entries, 'ready_for_payout')}',
                        color: const Color(0xFF0F766E),
                      ),
                      _CoachFinanceHeaderBadge(
                        icon: Icons.update_outlined,
                        label:
                            'Updated ${_coachFinanceIsoLabel(response.generatedAtIso)}',
                        color: const Color(0xFF475569),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Focus queues',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF1E293B),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final queue in const <String>[
                        'attention',
                        'risk',
                        'refunds',
                        'accruals',
                        'ready_for_payout',
                      ])
                        _CoachFinanceFocusCard(
                          key: ValueKey('coachFinanceFocus_$queue'),
                          icon: switch (queue) {
                            'attention' => Icons.priority_high_outlined,
                            'risk' => Icons.warning_amber_outlined,
                            'refunds' => Icons.undo_outlined,
                            'accruals' => Icons.receipt_long_outlined,
                            'ready_for_payout' =>
                              Icons.account_balance_wallet_outlined,
                            _ => Icons.list_alt_outlined,
                          },
                          label: _coachFinanceQueueLabel(queue),
                          value:
                              '${_coachFinanceQueueCount(response.entries, queue)}',
                          detail: switch (queue) {
                            'attention' =>
                              'Entries that still need explicit finance follow-up',
                            'risk' =>
                              'Risk-linked auto-cases and payout anomalies',
                            'refunds' =>
                              'Refund-side ledger changes and liability updates',
                            'accruals' =>
                              'Accrued operator payable and clearing movements',
                            'ready_for_payout' =>
                              'Ledger lines ready for payout execution or review',
                            _ => '',
                          },
                          selected: _selectedQueue == queue,
                          onTap: () {
                            setState(() {
                              _selectedQueue = queue;
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Updated ${_coachFinanceIsoLabel(response!.generatedAtIso)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('Entries ${response.summary.totalEntries}'),
                ),
                Chip(
                  label: Text('Attention ${response.summary.attentionEntries}'),
                ),
                Chip(
                  label: Text('Accruals ${response.summary.accrualEntries}'),
                ),
                Chip(
                  label:
                      Text('Adjustments ${response.summary.adjustmentEntries}'),
                ),
                Chip(label: Text('Payouts ${response.summary.payoutEntries}')),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Balances',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Operator payable ${_coachFinanceSignedMoneyLabel(response.summary.currency, response.summary.operatorPayableMinorUnits)}',
                    ),
                    Text(
                      'Settlement in transit ${_coachFinanceSignedMoneyLabel(response.summary.currency, response.summary.settlementInTransitMinorUnits)}',
                    ),
                    Text(
                      'SyrChat app fee revenue ${_coachFinanceSignedMoneyLabel(response.summary.currency, response.summary.platformRevenueMinorUnits)}',
                    ),
                    Text(
                      'Travel credit ${_coachFinanceSignedMoneyLabel(response.summary.currency, response.summary.travelCreditLiabilityMinorUnits)}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Queue',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final queue in const <String>[
                  'all',
                  'attention',
                  'refunds',
                  'risk',
                  'accruals',
                  'ready_for_payout',
                ])
                  ChoiceChip(
                    label: Text(
                      '${_coachFinanceQueueLabel(queue)} (${_coachFinanceQueueCount(response.entries, queue)})',
                    ),
                    selected: _selectedQueue == queue,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() {
                        _selectedQueue = queue;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Showing ${visibleEntries.length} of ${response.entries.length} entries',
            ),
            const SizedBox(height: 8),
            Text(
              'Sort',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sort in const <String>[
                  'priority',
                  'latest',
                  'amount',
                ])
                  ChoiceChip(
                    label: Text(_coachFinanceSortLabel(sort)),
                    selected: _selectedSort == sort,
                    onSelected: (selected) {
                      if (!selected) return;
                      setState(() {
                        _selectedSort = sort;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (visibleEntries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No finance journal entries match the current search and queue.',
                  ),
                ),
              )
            else
              for (final entry in visibleEntries) ...[
                Card(
                  key: ValueKey('coachFinanceEntryCard_${entry.entryId}'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openEntryDetail(entry),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _coachFinanceEntryIcon(entry.eventType),
                                color: entry.needsAttention
                                    ? Colors.redAccent
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.referenceLabel ??
                                          entry.operatorName ??
                                          entry.eventType,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${entry.operatorName ?? '-'} • ${_coachFinanceIsoLabel(entry.occurredAtIso)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _coachFinanceMoneyLabel(
                                      entry.currency,
                                      entry.primaryAmountMinorUnits,
                                    ),
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.status.toUpperCase(),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                    textAlign: TextAlign.end,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _CoachFinanceEntryBadge(
                                label: entry.status.toUpperCase(),
                                color: entry.needsAttention
                                    ? Colors.redAccent
                                    : const Color(0xFF526176),
                              ),
                              if (entry.needsAttention)
                                const _CoachFinanceEntryBadge(
                                  label: 'Needs attention',
                                  color: Colors.redAccent,
                                ),
                              if (entry.bookingId != null)
                                const _CoachFinanceEntryBadge(
                                  label: 'Booking linked',
                                  color: Color(0xFF1D4ED8),
                                ),
                              if (entry.statementId != null)
                                const _CoachFinanceEntryBadge(
                                  label: 'Statement linked',
                                  color: Color(0xFF0F766E),
                                ),
                              if (entry.payoutRunId != null)
                                const _CoachFinanceEntryBadge(
                                  label: 'Payout linked',
                                  color: Color(0xFFB45309),
                                ),
                              _CoachFinanceEntryBadge(
                                label:
                                    '${entry.accountMovements.length} movement${entry.accountMovements.length == 1 ? '' : 's'}',
                                color: const Color(0xFF526176),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ],
      ),
    );
  }
}

class _CoachFinanceHeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoachFinanceHeaderBadge({
    required this.icon,
    required this.label,
    this.color = const Color(0xFF526176),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8E1ED)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _CoachFinanceFocusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  const _CoachFinanceFocusCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFE8F0FF)
                  : Colors.white.withValues(alpha: .76),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? const Color(0xFF5B8FF7)
                    : const Color(0xFFD8E1ED),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? const Color(0xFF1D4ED8)
                      : const Color(0xFF526176),
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF1E293B),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF526176),
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoachFinanceEntryBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CoachFinanceEntryBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _CoachAdminFinanceJournalEntrySheet extends StatelessWidget {
  final CoachAdminFinanceJournalEntry entry;

  const _CoachAdminFinanceJournalEntrySheet({
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          entry.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '${_coachFinanceIsoLabel(entry.occurredAtIso)} • ${entry.status.toUpperCase()}',
        ),
        const SizedBox(height: 8),
        Text(
          _coachFinanceMoneyLabel(
              entry.currency, entry.primaryAmountMinorUnits),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'References',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (entry.referenceLabel != null) Text(entry.referenceLabel!),
                if (entry.bookingId != null)
                  Text('Booking ${entry.bookingId!}'),
                if (entry.statementId != null)
                  Text('Statement ${entry.statementId!}'),
                if (entry.payoutRunId != null)
                  Text('Payout ${entry.payoutRunId!}'),
                if (entry.requestId != null)
                  Text('Request ${entry.requestId!}'),
                if (entry.importId != null) Text('Import ${entry.importId!}'),
                if (entry.operatorName != null)
                  Text('Operator ${entry.operatorName!}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account movements',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (entry.accountMovements.isEmpty)
                  const Text('No account movements attached.')
                else
                  for (final movement in entry.accountMovements) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${movement.accountLabel} • ${movement.direction}',
                          ),
                        ),
                        Text(
                          _coachFinanceSignedMoneyLabel(
                            entry.currency,
                            movement.signedMinorUnits,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (entry.nextAction != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next action',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(entry.nextAction!),
                ],
              ),
            ),
          ),
        if (entry.nextAction != null) const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (entry.detailLines.isEmpty)
                  const Text('No additional finance details.')
                else
                  for (final line in entry.detailLines) ...[
                    Text(line),
                    const SizedBox(height: 6),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
