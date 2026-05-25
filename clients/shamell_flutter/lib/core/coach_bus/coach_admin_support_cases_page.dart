import 'package:flutter/material.dart';

import '../format.dart';
import '../safe_set_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_mobility_api.dart';

String _coachSupportIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

String _coachSupportMoneyLabel(String currency, int minorUnits) {
  return '${fmtCents(minorUnits)} $currency';
}

bool _coachReissueCompleted(CoachSelfServiceReissueResult result) =>
    result.changeRequest.status == 'reissued' &&
    result.nextAction == 'completed';

bool _coachReissuePaymentFailed(CoachSelfServiceReissueResult result) =>
    result.changeRequest.status == 'payment_failed' ||
    result.payment?.status == 'failed';

String _coachSupportWireLabel(String raw) {
  final normalized = raw.trim();
  if (normalized.isEmpty) return '-';
  return normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _coachSupportCaseStatusLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'attention_required':
      return 'Attention required';
    case 'refund_requested':
      return 'Refund requested';
    case 'refund_approved':
      return 'Refund approved';
    case 'refund_rejected':
      return 'Refund rejected';
    case 'change_requested':
      return 'Change requested';
    case 'change_reissued':
      return 'Change reissued';
    case 'change_payment_failed':
      return 'Change payment failed';
    case 'risk_follow_up':
      return 'Risk follow-up';
    case 'boarded':
      return 'Boarded';
    default:
      return _coachSupportWireLabel(raw);
  }
}

String _coachSupportOpenRequestKindLabel(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'refund_request':
      return 'Refund';
    case 'change_request':
      return 'Change';
    case 'risk_follow_up':
      return 'Risk';
    default:
      return _coachSupportWireLabel(raw);
  }
}

String _coachSupportQueueLabel(String queue) {
  switch (queue) {
    case 'attention':
      return 'Attention';
    case 'urgent':
      return 'Urgent';
    case 'refunds':
      return 'Refunds';
    case 'changes':
      return 'Changes';
    case 'payment_failures':
      return 'Payment failures';
    case 'risk':
      return 'Risk';
    default:
      return 'All';
  }
}

String _coachSupportSortLabel(String sort) {
  switch (sort) {
    case 'latest':
      return 'Latest activity';
    case 'departure':
      return 'Departure first';
    default:
      return 'Priority';
  }
}

bool _coachSupportMatchesQueue(
  CoachAdminSupportCaseSummaryRecord supportCase,
  String queue,
) {
  switch (queue) {
    case 'attention':
      return supportCase.needsAttention;
    case 'urgent':
      return supportCase.priority.trim().toLowerCase() == 'high';
    case 'refunds':
      return supportCase.caseStatus.contains('refund') ||
          supportCase.openRequestKinds.contains('refund_request');
    case 'changes':
      return supportCase.caseStatus.contains('change') ||
          supportCase.openRequestKinds.contains('change_request');
    case 'payment_failures':
      return supportCase.caseStatus == 'change_payment_failed';
    case 'risk':
      return supportCase.caseStatus == 'risk_follow_up' ||
          supportCase.openRequestKinds.contains('risk_follow_up');
    default:
      return true;
  }
}

int _coachSupportQueueCount(
  List<CoachAdminSupportCaseSummaryRecord> supportCases,
  String queue,
) {
  return supportCases
      .where((supportCase) => _coachSupportMatchesQueue(supportCase, queue))
      .length;
}

int _coachSupportPriorityRank(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'high':
      return 0;
    case 'medium':
      return 1;
    default:
      return 2;
  }
}

int _coachSupportCaseRank(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'change_payment_failed':
      return 0;
    case 'risk_follow_up':
      return 1;
    case 'attention_required':
      return 2;
    case 'refund_requested':
      return 3;
    case 'change_requested':
      return 4;
    case 'refund_approved':
      return 5;
    case 'change_reissued':
      return 6;
    case 'boarded':
      return 7;
    default:
      return 8;
  }
}

DateTime _coachSupportTimestamp(String iso) {
  return DateTime.tryParse(iso)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _coachSupportImpactScore(CoachAdminSupportCaseSummaryRecord supportCase) {
  return (supportCase.needsAttention ? 100 : 0) +
      (supportCase.priority.trim().toLowerCase() == 'high' ? 50 : 0) +
      supportCase.openRequestKinds.length * 10 +
      supportCase.passengerCount;
}

List<CoachAdminSupportCaseSummaryRecord> _coachSupportSortedCases(
  List<CoachAdminSupportCaseSummaryRecord> supportCases,
  String sort,
) {
  final out = List<CoachAdminSupportCaseSummaryRecord>.of(supportCases);
  out.sort((left, right) {
    if (sort == 'latest') {
      final latestCompare = _coachSupportTimestamp(
        right.latestActivityAtIso,
      ).compareTo(_coachSupportTimestamp(left.latestActivityAtIso));
      if (latestCompare != 0) {
        return latestCompare;
      }
    }
    if (sort == 'departure') {
      final departureCompare = _coachSupportTimestamp(
        left.departureAtIso,
      ).compareTo(_coachSupportTimestamp(right.departureAtIso));
      if (departureCompare != 0) {
        return departureCompare;
      }
    }
    final priorityCompare = _coachSupportPriorityRank(left.priority).compareTo(
      _coachSupportPriorityRank(right.priority),
    );
    if (priorityCompare != 0) {
      return priorityCompare;
    }
    final attentionCompare = (right.needsAttention ? 1 : 0).compareTo(
      left.needsAttention ? 1 : 0,
    );
    if (attentionCompare != 0) {
      return attentionCompare;
    }
    final caseCompare = _coachSupportCaseRank(left.caseStatus).compareTo(
      _coachSupportCaseRank(right.caseStatus),
    );
    if (caseCompare != 0) {
      return caseCompare;
    }
    final impactCompare = _coachSupportImpactScore(
      right,
    ).compareTo(_coachSupportImpactScore(left));
    if (impactCompare != 0) {
      return impactCompare;
    }
    final latestCompare = _coachSupportTimestamp(
      right.latestActivityAtIso,
    ).compareTo(_coachSupportTimestamp(left.latestActivityAtIso));
    if (latestCompare != 0) {
      return latestCompare;
    }
    return left.caseId.compareTo(right.caseId);
  });
  return out;
}

Color _coachSupportPriorityColor(BuildContext context, String raw) {
  final scheme = Theme.of(context).colorScheme;
  switch (raw.trim().toLowerCase()) {
    case 'high':
      return scheme.error;
    case 'medium':
      return Colors.orange.shade700;
    default:
      return scheme.primary;
  }
}

Color _coachSupportCaseStatusColor(BuildContext context, String raw) {
  final scheme = Theme.of(context).colorScheme;
  switch (raw.trim().toLowerCase()) {
    case 'attention_required':
    case 'change_payment_failed':
      return scheme.error;
    case 'risk_follow_up':
    case 'refund_requested':
    case 'change_requested':
      return Colors.orange.shade700;
    case 'refund_approved':
    case 'change_reissued':
    case 'boarded':
      return Colors.green.shade700;
    default:
      return scheme.primary;
  }
}

IconData _coachSupportCaseIcon(CoachAdminSupportCaseSummaryRecord supportCase) {
  switch (supportCase.caseStatus.trim().toLowerCase()) {
    case 'change_payment_failed':
      return Icons.payments_outlined;
    case 'risk_follow_up':
      return Icons.shield_outlined;
    case 'refund_requested':
      return Icons.undo_outlined;
    default:
      return supportCase.needsAttention
          ? Icons.priority_high
          : Icons.support_agent_outlined;
  }
}

Widget _coachSupportBadge(
  BuildContext context, {
  required String label,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class CoachAdminSupportCasesPage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final CoachAdminSupportCasesResponse? initialResponse;

  const CoachAdminSupportCasesPage({
    super.key,
    required this.baseUrl,
    this.api,
    this.initialResponse,
  });

  @override
  State<CoachAdminSupportCasesPage> createState() =>
      _CoachAdminSupportCasesPageState();
}

class _CoachAdminSupportCasesPageState extends State<CoachAdminSupportCasesPage>
    with SafeSetStateMixin<CoachAdminSupportCasesPage> {
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final TextEditingController _queryController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;
  CoachAdminSupportCasesResponse? _response;
  String _selectedQueue = 'all';
  String _selectedSort = 'priority';

  @override
  void initState() {
    super.initState();
    _response = widget.initialResponse;
    if (_response == null) {
      _loadCases();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final response = await _api.adminSupportCases(
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

  Future<void> _openCaseDetail(
    CoachAdminSupportCaseSummaryRecord supportCase,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: _CoachAdminSupportCaseDetailSheet(
            api: _api,
            supportCase: supportCase,
            onMutated: _loadCases,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach support'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadCases,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _response == null) {
      return const ShamellSkeletonList(itemCount: 6);
    }
    final response = _response;
    final paymentFailureCases = _response?.cases
            .where(
              (supportCase) =>
                  supportCase.caseStatus == 'change_payment_failed',
            )
            .length ??
        0;
    final filteredCases = response == null
        ? const <CoachAdminSupportCaseSummaryRecord>[]
        : response.cases
            .where(
              (supportCase) =>
                  _coachSupportMatchesQueue(supportCase, _selectedQueue),
            )
            .toList(growable: false);
    final visibleCases = _coachSupportSortedCases(
      filteredCases,
      _selectedSort,
    );
    return RefreshIndicator(
      onRefresh: _loadCases,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search cases',
                    hintText: 'Booking, ticket, operator ref, passenger',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadCases(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _loadCases,
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
                    const Text('No support data loaded yet.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _loadCases,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Load cases'),
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
                    Color(0xFFF9FBFF),
                    Color(0xFFEEF3FB),
                    Color(0xFFE6EDF8),
                  ],
                ),
                border: Border.all(color: const Color(0xFFD6E0F0)),
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
                      border: Border.all(color: const Color(0xFFD6E0F0)),
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
                    'Support command desk',
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
                      'Triage support fallout from one queue: refunds, change failures, risk follow-up, and urgent passenger cases. Start with attention-heavy work, then drill into individual recovery flows.',
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
                      _CoachSupportHeaderBadge(
                        icon: Icons.public_outlined,
                        label: 'Scope: Coach admin',
                      ),
                      _CoachSupportHeaderBadge(
                        icon: Icons.priority_high_outlined,
                        label:
                            'Needs attention ${response!.summary.attentionCases}',
                        color: const Color(0xFFB91C1C),
                      ),
                      _CoachSupportHeaderBadge(
                        icon: Icons.warning_amber_outlined,
                        label: 'Urgent queue ${response!.summary.urgentCases}',
                        color: const Color(0xFFB45309),
                      ),
                      _CoachSupportHeaderBadge(
                        icon: Icons.payments_outlined,
                        label: 'Payment recovery $paymentFailureCases',
                        color: const Color(0xFF0F766E),
                      ),
                      _CoachSupportHeaderBadge(
                        icon: Icons.update_outlined,
                        label:
                            'Updated ${_coachSupportIsoLabel(response!.generatedAtIso)}',
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
                        'urgent',
                        'payment_failures',
                        'refunds',
                        'changes',
                        'risk',
                      ])
                        _CoachSupportFocusCard(
                          key: ValueKey('coachSupportFocus_$queue'),
                          icon: switch (queue) {
                            'attention' => Icons.priority_high_outlined,
                            'urgent' => Icons.warning_amber_outlined,
                            'payment_failures' => Icons.payments_outlined,
                            'refunds' => Icons.undo_outlined,
                            'changes' => Icons.swap_horiz_outlined,
                            'risk' => Icons.shield_outlined,
                            _ => Icons.list_alt_outlined,
                          },
                          label: _coachSupportQueueLabel(queue),
                          value:
                              '${_coachSupportQueueCount(response!.cases, queue)}',
                          detail: switch (queue) {
                            'attention' =>
                              'Cases that still require explicit admin handling',
                            'urgent' =>
                              'High-priority passenger work waiting in queue',
                            'payment_failures' =>
                              'Change collection failures needing recovery',
                            'refunds' => 'Refund review and approval work',
                            'changes' =>
                              'Reissue and itinerary-change follow-up',
                            'risk' =>
                              'Risk-driven support fallout and boarding review',
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
            Text(
              'Updated ${_coachSupportIsoLabel(response!.generatedAtIso)}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Cases ${response.summary.totalCases}')),
                Chip(label: Text('Urgent ${response.summary.urgentCases}')),
                Chip(label: Text('Refunds ${response.summary.refundCases}')),
                Chip(label: Text('Changes ${response.summary.changeCases}')),
                Chip(
                  label: Text('Attention ${response.summary.attentionCases}'),
                ),
                if (paymentFailureCases > 0)
                  Chip(label: Text('Payment failures $paymentFailureCases')),
              ],
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
                  'urgent',
                  'refunds',
                  'changes',
                  'payment_failures',
                  'risk',
                ])
                  ChoiceChip(
                    label: Text(
                      '${_coachSupportQueueLabel(queue)} (${_coachSupportQueueCount(response.cases, queue)})',
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
              'Showing ${visibleCases.length} of ${response.cases.length} cases',
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
                  'departure',
                ])
                  ChoiceChip(
                    label: Text(_coachSupportSortLabel(sort)),
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
            if (visibleCases.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No support cases match the current search and queue.',
                  ),
                ),
              )
            else
              for (final supportCase in visibleCases) ...[
                Card(
                  key: ValueKey('coachSupportCaseCard_${supportCase.caseId}'),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _openCaseDetail(supportCase),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _coachSupportCaseIcon(supportCase),
                                color: _coachSupportCaseStatusColor(
                                  context,
                                  supportCase.caseStatus,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${supportCase.passengerDisplayName} • ${supportCase.from} → ${supportCase.to}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_coachSupportCaseStatusLabel(supportCase.caseStatus)} • ${supportCase.operatorName}',
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_coachSupportIsoLabel(supportCase.departureAtIso)} • ${supportCase.bookingId}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _coachSupportBadge(
                                    context,
                                    label: supportCase.priority.toUpperCase(),
                                    color: _coachSupportPriorityColor(
                                      context,
                                      supportCase.priority,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _coachSupportIsoLabel(
                                      supportCase.latestActivityAtIso,
                                    ),
                                    textAlign: TextAlign.end,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
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
                              _coachSupportBadge(
                                context,
                                label: _coachSupportCaseStatusLabel(
                                  supportCase.caseStatus,
                                ),
                                color: _coachSupportCaseStatusColor(
                                  context,
                                  supportCase.caseStatus,
                                ),
                              ),
                              if (supportCase.needsAttention)
                                _coachSupportBadge(
                                  context,
                                  label: 'Needs attention',
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              _coachSupportBadge(
                                context,
                                label:
                                    'Passengers ${supportCase.passengerCount}',
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              _coachSupportBadge(
                                context,
                                label:
                                    'Tickets ${supportCase.ticketIds.length}',
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              if (supportCase.paymentAuthorizationReference !=
                                  null)
                                _coachSupportBadge(
                                  context,
                                  label: 'Payment ref',
                                  color: const Color(0xFF0F766E),
                                ),
                              for (final kind in supportCase.openRequestKinds)
                                _coachSupportBadge(
                                  context,
                                  label:
                                      _coachSupportOpenRequestKindLabel(kind),
                                  color: _coachSupportCaseStatusColor(
                                    context,
                                    supportCase.caseStatus,
                                  ),
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

class _CoachSupportHeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoachSupportHeaderBadge({
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
        border: Border.all(color: const Color(0xFFD6E0F0)),
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

class _CoachSupportFocusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  const _CoachSupportFocusCard({
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
                    : const Color(0xFFD6E0F0),
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

class _CoachAdminSupportCaseDetailSheet extends StatefulWidget {
  final CoachMobilityApi api;
  final CoachAdminSupportCaseSummaryRecord supportCase;
  final Future<void> Function()? onMutated;

  const _CoachAdminSupportCaseDetailSheet({
    required this.api,
    required this.supportCase,
    this.onMutated,
  });

  @override
  State<_CoachAdminSupportCaseDetailSheet> createState() =>
      _CoachAdminSupportCaseDetailSheetState();
}

class _CoachAdminSupportCaseDetailSheetState
    extends State<_CoachAdminSupportCaseDetailSheet>
    with SafeSetStateMixin<_CoachAdminSupportCaseDetailSheet> {
  late Future<CoachAdminSupportCaseDetailResponse> _detailFuture;

  String _paymentMethod = 'card';
  bool _submitting = false;
  String? _actionError;
  CoachSelfServiceReissueResult? _resolveResult;

  @override
  void initState() {
    super.initState();
    _detailFuture =
        widget.api.adminSupportCaseDetail(widget.supportCase.caseId);
  }

  Future<void> _refreshDetail() async {
    setState(() {
      _detailFuture =
          widget.api.adminSupportCaseDetail(widget.supportCase.caseId);
    });
  }

  Future<void> _resolvePaymentFailure() async {
    setState(() {
      _submitting = true;
      _actionError = null;
    });
    try {
      final result = await widget.api.adminResolveSupportCasePaymentFailure(
        caseId: widget.supportCase.caseId,
        paymentMethod: _paymentMethod,
      );
      setState(() {
        _resolveResult = result;
      });
      await _refreshDetail();
      if (widget.onMutated != null) {
        await widget.onMutated!();
      }
    } catch (error) {
      setState(() {
        _actionError = error.toString();
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CoachAdminSupportCaseDetailResponse>(
      future: _detailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: StatusBanner.error(snapshot.error.toString()),
          );
        }
        final detail = snapshot.data;
        if (detail == null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: StatusBanner.error('Support case detail unavailable'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${detail.supportCase.passengerDisplayName} • ${_coachSupportCaseStatusLabel(detail.supportCase.caseStatus)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${detail.supportCase.from} → ${detail.supportCase.to}\n'
              '${_coachSupportIsoLabel(detail.supportCase.departureAtIso)}',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _coachSupportBadge(
                  context,
                  label: _coachSupportCaseStatusLabel(
                      detail.supportCase.caseStatus),
                  color: _coachSupportCaseStatusColor(
                    context,
                    detail.supportCase.caseStatus,
                  ),
                ),
                _coachSupportBadge(
                  context,
                  label: detail.supportCase.priority.toUpperCase(),
                  color: _coachSupportPriorityColor(
                    context,
                    detail.supportCase.priority,
                  ),
                ),
                for (final kind in detail.supportCase.openRequestKinds)
                  _coachSupportBadge(
                    context,
                    label: _coachSupportOpenRequestKindLabel(kind),
                    color: _coachSupportCaseStatusColor(
                      context,
                      detail.supportCase.caseStatus,
                    ),
                  ),
              ],
            ),
            if (detail.supportCase.caseStatus == 'change_payment_failed') ...[
              const SizedBox(height: 12),
              StatusBanner.error(
                'Collection failed for this change. Retry payment or move it into manual follow-up.',
              ),
            ],
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
                    Text('Booking ${detail.supportCase.bookingId}'),
                    Text(
                      'Latest activity ${_coachSupportIsoLabel(detail.supportCase.latestActivityAtIso)}',
                    ),
                    if (detail.supportCase.operatorBookingReference != null)
                      Text(
                        'Operator ${detail.supportCase.operatorBookingReference!}',
                      ),
                    if (detail.supportCase.paymentAuthorizationReference !=
                        null)
                      Text(
                        'Payment ${detail.supportCase.paymentAuthorizationReference!}',
                      ),
                    if (detail.supportCase.contactEmail != null)
                      Text('Contact ${detail.supportCase.contactEmail!}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (detail.payment != null || detail.compensation != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Commerce',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (detail.payment != null)
                        Text(
                          'Payment ${detail.payment!.status} • ${detail.payment!.authorizationReference} • '
                          '${detail.payment!.method} • '
                          '${_coachSupportMoneyLabel(detail.payment!.currency, detail.payment!.chargedMinorUnits)}',
                        ),
                      if (detail.compensation != null)
                        Text(
                          'Compensation ${detail.compensation!.state} • ${detail.compensation!.action}',
                        ),
                      if (detail.compensation?.reason != null)
                        Text('Reason ${detail.compensation!.reason!}'),
                      if (detail.compensation?.recoveryReference != null)
                        Text(
                          'Recovery ${detail.compensation!.recoveryReference!}',
                        ),
                    ],
                  ),
                ),
              ),
            if (detail.supportCase.caseStatus == 'change_payment_failed' ||
                _resolveResult != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recovery',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'Retry payment method',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'card',
                            child: Text('Card'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'wallet_credit',
                            child: Text('Wallet credit'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'split_tender',
                            child: Text('Split tender'),
                          ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) {
                                if (value == null || value.isEmpty) {
                                  return;
                                }
                                setState(() {
                                  _paymentMethod = value;
                                });
                              },
                      ),
                      if (detail.supportCase.caseStatus ==
                          'change_payment_failed') ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed:
                              _submitting ? null : _resolvePaymentFailure,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_outlined),
                          label: const Text('Retry collection and reissue'),
                        ),
                      ],
                      if (_actionError != null) ...[
                        const SizedBox(height: 12),
                        StatusBanner.error(_actionError!),
                      ],
                      if (_resolveResult != null) ...[
                        const SizedBox(height: 12),
                        if (_coachReissueCompleted(_resolveResult!))
                          const StatusBanner.success(
                            'Payment recovered and tickets reissued.',
                          )
                        else if (_coachReissuePaymentFailed(_resolveResult!))
                          const StatusBanner.error(
                            'Recovery attempt failed again.',
                          )
                        else
                          const StatusBanner.warning(
                            'Recovery was recorded but still needs follow-up.',
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Result ${_resolveResult!.changeRequest.status} • ${_resolveResult!.nextAction}',
                        ),
                        if (_resolveResult!.payment != null)
                          Text(
                            'Payment ${_resolveResult!.payment!.status} • ${_resolveResult!.payment!.method} • ${_coachSupportMoneyLabel(_resolveResult!.payment!.currency, _resolveResult!.payment!.chargedMinorUnits)}',
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (detail.payment != null || detail.compensation != null)
              const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tickets',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final ticket in detail.tickets) ...[
                      Text(
                        '${ticket.ticketId} • ${ticket.boardingState?.name ?? ticket.status.name}',
                      ),
                      if (ticket.operatorTicketReference != null)
                        Text(
                          'Operator ref ${ticket.operatorTicketReference!}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (detail.ticketArtifacts.isNotEmpty) ...[
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Artifacts',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      for (final artifact in detail.ticketArtifacts)
                        Text('${artifact.artifactKind} • ${artifact.fileName}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (detail.refundRequest != null || detail.changeRequest != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Requests',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (detail.refundRequest != null)
                        Text(
                          'Refund ${detail.refundRequest!.status} • ${detail.refundRequest!.selectedKind.name} • '
                          '${_coachSupportMoneyLabel(detail.refundRequest!.currency, detail.refundRequest!.requestedMinorUnits)}',
                        ),
                      if (detail.changeRequest != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Change ${_coachSupportWireLabel(detail.changeRequest!.status)} • target ${detail.changeRequest!.targetOfferId} • '
                              '${_coachSupportMoneyLabel(detail.changeRequest!.currency, detail.changeRequest!.totalDueMinorUnits)}',
                            ),
                            if ((detail.changeRequest!.reason ?? '').isNotEmpty)
                              Text('Reason ${detail.changeRequest!.reason!}'),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (detail.refundRequest != null || detail.changeRequest != null)
              const SizedBox(height: 12),
            Text(
              'Timeline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final event in detail.timeline) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_coachSupportWireLabel(event.statusLabel)} • ${_coachSupportIsoLabel(event.occurredAtIso)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (event.detailLines.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final line in event.detailLines) Text(line),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
