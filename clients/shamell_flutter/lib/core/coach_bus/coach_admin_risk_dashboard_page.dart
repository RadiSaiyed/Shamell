import 'package:flutter/material.dart';

import '../format.dart';
import '../safe_set_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_mobility_api.dart';

String _coachRiskIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

String _coachRiskMoneyLabel(String currency, int minorUnits) {
  if (currency.trim().isEmpty) {
    return fmtCents(minorUnits);
  }
  return '${fmtCents(minorUnits)} $currency';
}

String _coachRiskWorkflowLabel(String workflowStatus) {
  switch (workflowStatus) {
    case 'resolved':
      return 'Resolved';
    case 'acknowledged':
      return 'Acknowledged';
    case 'snoozed':
      return 'Snoozed';
    default:
      return 'Active';
  }
}

String _coachRiskTeamLabel(String team) {
  switch (team) {
    case 'finance_ops':
      return 'Finance ops';
    case 'partner_ops':
      return 'Partner ops';
    case 'support_ops':
      return 'Support ops';
    case 'live_ops':
      return 'Live ops';
    case 'trust_ops':
      return 'Trust ops';
    default:
      return team;
  }
}

String _coachRiskRoutingSourceLabel(String routingSource) {
  switch (routingSource) {
    case 'shamell_pay_reconciliation':
      return 'SyrChat Pay reconciliation';
    case 'settlement_journal':
      return 'Settlement journal';
    case 'partner_feed_health':
      return 'Partner feed health';
    case 'support_queue':
      return 'Support queue';
    case 'boarding_console':
      return 'Boarding console';
    default:
      return routingSource;
  }
}

String _coachRiskSlaLabel(String slaStatus) {
  switch (slaStatus) {
    case 'overdue':
      return 'Overdue';
    case 'due_soon':
      return 'Due soon';
    default:
      return 'On track';
  }
}

String _coachRiskQueueLabel(String queue) {
  switch (queue) {
    case 'overdue':
      return 'Overdue';
    case 'critical':
      return 'Critical';
    case 'unowned':
      return 'Unowned';
    case 'owned':
      return 'Owned';
    case 'finance':
      return 'Finance';
    case 'partner_feed':
      return 'Partner feed';
    case 'boarding':
      return 'Boarding';
    default:
      return 'All';
  }
}

bool _coachRiskMatchesQueue(CoachAdminRiskItem risk, String queue) {
  switch (queue) {
    case 'overdue':
      return risk.slaStatus == 'overdue';
    case 'critical':
      return risk.severity == 'critical';
    case 'unowned':
      return risk.ownerAccountId == null;
    case 'owned':
      return risk.ownerAccountId != null;
    case 'finance':
      return risk.category == 'finance';
    case 'partner_feed':
      return risk.category == 'partner_feed';
    case 'boarding':
      return risk.category == 'boarding';
    default:
      return true;
  }
}

int _coachRiskQueueCount(List<CoachAdminRiskItem> risks, String queue) {
  return risks.where((risk) => _coachRiskMatchesQueue(risk, queue)).length;
}

String _coachRiskSortLabel(String sort) {
  switch (sort) {
    case 'newest':
      return 'Newest';
    case 'amount':
      return 'Largest amount';
    default:
      return 'Priority';
  }
}

class _CoachRiskSnoozeRequest {
  final String snoozedUntilIso;
  final String reason;
  final String? note;

  const _CoachRiskSnoozeRequest({
    required this.snoozedUntilIso,
    required this.reason,
    this.note,
  });
}

String _coachRiskSnoozeDurationLabel(String duration) {
  switch (duration) {
    case '1h':
      return '1 hour';
    case '4h':
      return '4 hours';
    case '24h':
      return '24 hours';
    case '3d':
      return '3 days';
    case 'custom':
      return 'Custom';
    default:
      return duration;
  }
}

DateTime _coachRiskSnoozeUntilFromDuration(
  String duration,
  DateTime now,
  DateTime? customUntil,
) {
  switch (duration) {
    case '1h':
      return now.add(const Duration(hours: 1));
    case '4h':
      return now.add(const Duration(hours: 4));
    case '24h':
      return now.add(const Duration(hours: 24));
    case '3d':
      return now.add(const Duration(days: 3));
    case 'custom':
      return customUntil ?? now.add(const Duration(hours: 24));
    default:
      return now.add(const Duration(hours: 24));
  }
}

String _coachRiskBulkActionPastLabel(String action) {
  switch (action) {
    case 'claim':
      return 'claimed';
    case 'acknowledge':
      return 'acknowledged';
    case 'snooze':
      return 'snoozed';
    case 'resolve':
      return 'resolved';
    case 'reopen':
      return 'reopened';
    default:
      return action;
  }
}

int _coachRiskSlaRank(String slaStatus) {
  switch (slaStatus) {
    case 'overdue':
      return 0;
    case 'due_soon':
      return 1;
    default:
      return 2;
  }
}

int _coachRiskSeverityRank(String severity) {
  switch (severity) {
    case 'critical':
      return 0;
    case 'high':
      return 1;
    case 'medium':
      return 2;
    default:
      return 3;
  }
}

int _coachRiskWorkflowRank(String workflowStatus) {
  switch (workflowStatus) {
    case 'active':
      return 0;
    case 'acknowledged':
      return 1;
    case 'snoozed':
      return 2;
    case 'resolved':
      return 3;
    default:
      return 4;
  }
}

DateTime _coachRiskTimestamp(String iso) {
  return DateTime.tryParse(iso)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _coachRiskAmountMagnitude(CoachAdminRiskItem risk) {
  return risk.amountMinorUnits?.abs() ?? -1;
}

List<CoachAdminRiskItem> _coachRiskSortedItems(
  List<CoachAdminRiskItem> risks,
  String sort,
) {
  final out = List<CoachAdminRiskItem>.of(risks);
  out.sort((left, right) {
    if (sort == 'newest') {
      final newestCompare = _coachRiskTimestamp(
        right.detectedAtIso,
      ).compareTo(_coachRiskTimestamp(left.detectedAtIso));
      if (newestCompare != 0) {
        return newestCompare;
      }
    }
    if (sort == 'amount') {
      final amountCompare = _coachRiskAmountMagnitude(
        right,
      ).compareTo(_coachRiskAmountMagnitude(left));
      if (amountCompare != 0) {
        return amountCompare;
      }
    }
    final slaCompare = _coachRiskSlaRank(left.slaStatus).compareTo(
      _coachRiskSlaRank(right.slaStatus),
    );
    if (slaCompare != 0) {
      return slaCompare;
    }
    final severityCompare = _coachRiskSeverityRank(left.severity).compareTo(
      _coachRiskSeverityRank(right.severity),
    );
    if (severityCompare != 0) {
      return severityCompare;
    }
    final ownershipCompare = (left.ownerAccountId == null ? 0 : 1).compareTo(
      right.ownerAccountId == null ? 0 : 1,
    );
    if (ownershipCompare != 0) {
      return ownershipCompare;
    }
    final workflowCompare = _coachRiskWorkflowRank(
      left.workflowStatus,
    ).compareTo(_coachRiskWorkflowRank(right.workflowStatus));
    if (workflowCompare != 0) {
      return workflowCompare;
    }
    final detectedCompare = _coachRiskTimestamp(
      right.detectedAtIso,
    ).compareTo(_coachRiskTimestamp(left.detectedAtIso));
    if (detectedCompare != 0) {
      return detectedCompare;
    }
    return left.riskId.compareTo(right.riskId);
  });
  return out;
}

Color? _coachRiskSlaColor(String slaStatus) {
  switch (slaStatus) {
    case 'overdue':
      return Colors.redAccent;
    case 'due_soon':
      return Colors.orange;
    default:
      return null;
  }
}

IconData _coachRiskIcon(CoachAdminRiskItem risk) {
  switch (risk.category) {
    case 'finance':
      return Icons.account_balance_outlined;
    case 'partner_feed':
      return Icons.hub_outlined;
    case 'boarding':
      return Icons.qr_code_scanner_outlined;
    default:
      return Icons.support_agent_outlined;
  }
}

Color? _coachRiskAccent(CoachAdminRiskItem risk) {
  switch (risk.severity) {
    case 'critical':
      return Colors.redAccent;
    case 'high':
      return Colors.orange;
    case 'medium':
      return Colors.amber.shade700;
    default:
      return null;
  }
}

class CoachAdminRiskDashboardPage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final CoachAdminRiskDashboardResponse? initialResponse;

  const CoachAdminRiskDashboardPage({
    super.key,
    required this.baseUrl,
    this.api,
    this.initialResponse,
  });

  @override
  State<CoachAdminRiskDashboardPage> createState() =>
      _CoachAdminRiskDashboardPageState();
}

class _CoachAdminRiskDashboardPageState
    extends State<CoachAdminRiskDashboardPage>
    with SafeSetStateMixin<CoachAdminRiskDashboardPage> {
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final TextEditingController _queryController = TextEditingController();

  bool _loading = false;
  String? _errorMessage;
  CoachAdminRiskDashboardResponse? _response;
  String _selectedQueue = 'all';
  String _selectedSort = 'priority';
  final Set<String> _actioningRiskIds = <String>{};
  final Set<String> _selectedRiskIds = <String>{};
  bool _bulkActionRunning = false;

  @override
  void initState() {
    super.initState();
    _response = widget.initialResponse;
    if (_response == null) {
      _loadDashboard();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final response = await _api.adminRiskDashboard(
        query: _queryController.text,
      );
      setState(() {
        _response = response;
        final responseIds = response.risks.map((risk) => risk.riskId).toSet();
        _selectedRiskIds.retainWhere(responseIds.contains);
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

  Future<void> _openRiskDetail(CoachAdminRiskItem risk) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: _CoachAdminRiskDetailSheet(risk: risk),
        );
      },
    );
  }

  Future<void> _performRiskAction(
    CoachAdminRiskItem risk,
    String action, {
    String? ownerAccountId,
    String? ownerTeam,
    String? snoozedUntilIso,
    String? snoozeReason,
    String? note,
  }) async {
    setState(() {
      _actioningRiskIds.add(risk.riskId);
      _errorMessage = null;
    });
    try {
      final result = await _api.adminRiskAction(
        riskId: risk.riskId,
        action: action,
        ownerAccountId: ownerAccountId,
        ownerTeam: ownerTeam,
        snoozedUntilIso: snoozedUntilIso,
        snoozeReason: snoozeReason,
        note: note,
      );
      await _loadDashboard();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.risk.title}: ${_coachRiskWorkflowLabel(result.risk.workflowStatus)}',
            ),
          ),
        );
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _actioningRiskIds.remove(risk.riskId);
      });
    }
  }

  Future<void> _performBulkAction(
    String action,
    List<CoachAdminRiskItem> selectedRisks, {
    _CoachRiskSnoozeRequest? snoozeRequest,
  }) async {
    if (selectedRisks.isEmpty) return;
    final ids = selectedRisks
        .map((risk) => risk.riskId)
        .toList(growable: false);
    setState(() {
      _bulkActionRunning = true;
      _actioningRiskIds.addAll(ids);
      _errorMessage = null;
    });
    var success = 0;
    try {
      for (final risk in selectedRisks) {
        await _api.adminRiskAction(
          riskId: risk.riskId,
          action: action,
          ownerTeam: risk.ownerTeam ?? risk.suggestedTeam,
          snoozedUntilIso: action == 'snooze'
              ? (snoozeRequest?.snoozedUntilIso ?? _defaultSnoozeUntilIso())
              : null,
          snoozeReason: action == 'snooze'
              ? (snoozeRequest?.reason ?? _defaultSnoozeReason(risk))
              : null,
          note: snoozeRequest?.note,
        );
        success++;
      }
      setState(() {
        _selectedRiskIds.clear();
      });
      await _loadDashboard();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$success ${success == 1 ? 'risk' : 'risks'} '
              '${_coachRiskBulkActionPastLabel(action)}',
            ),
          ),
        );
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _bulkActionRunning = false;
        _actioningRiskIds.removeAll(ids);
      });
    }
  }

  void _toggleRiskSelection(String riskId, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedRiskIds.add(riskId);
      } else {
        _selectedRiskIds.remove(riskId);
      }
    });
  }

  void _toggleSelectVisible(List<CoachAdminRiskItem> visibleRisks) {
    if (visibleRisks.isEmpty) return;
    final allSelected = visibleRisks
        .every((risk) => _selectedRiskIds.contains(risk.riskId));
    setState(() {
      if (allSelected) {
        for (final risk in visibleRisks) {
          _selectedRiskIds.remove(risk.riskId);
        }
      } else {
        for (final risk in visibleRisks) {
          _selectedRiskIds.add(risk.riskId);
        }
      }
    });
  }

  String _defaultSnoozeUntilIso() {
    return DateTime.now()
        .toUtc()
        .add(const Duration(hours: 24))
        .toIso8601String();
  }

  String _defaultSnoozeReason(CoachAdminRiskItem risk) {
    return 'Waiting for ${risk.suggestedTeam == 'finance_ops' ? 'finance reconciliation window' : 'operator follow-up window'}.';
  }

  Future<_CoachRiskSnoozeRequest?> _promptSnoozeRequest({
    required String title,
    required String defaultReason,
  }) async {
    return await showModalBottomSheet<_CoachRiskSnoozeRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: _CoachRiskSnoozeSheet(
            title: title,
            defaultReason: defaultReason,
          ),
        );
      },
    );
  }

  Future<void> _confirmAndSnoozeRisk(CoachAdminRiskItem risk) async {
    final request = await _promptSnoozeRequest(
      title: 'Snooze risk',
      defaultReason: _defaultSnoozeReason(risk),
    );
    if (request == null) return;
    await _performRiskAction(
      risk,
      'snooze',
      ownerTeam: risk.ownerTeam ?? risk.suggestedTeam,
      snoozedUntilIso: request.snoozedUntilIso,
      snoozeReason: request.reason,
      note: request.note,
    );
  }

  Future<void> _confirmAndBulkSnooze(
    List<CoachAdminRiskItem> selectedRisks,
  ) async {
    if (selectedRisks.isEmpty) return;
    final request = await _promptSnoozeRequest(
      title: 'Snooze ${selectedRisks.length} '
          '${selectedRisks.length == 1 ? 'risk' : 'risks'}',
      defaultReason: 'Waiting for follow-up window.',
    );
    if (request == null) return;
    await _performBulkAction(
      'snooze',
      selectedRisks,
      snoozeRequest: request,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach risk'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadDashboard,
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
    final filteredRisks = response == null
        ? const <CoachAdminRiskItem>[]
        : response.risks
            .where((risk) => _coachRiskMatchesQueue(risk, _selectedQueue))
            .toList(growable: false);
    final visibleRisks = _coachRiskSortedItems(filteredRisks, _selectedSort);
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search risk queue',
                    hintText: 'Booking, operator, payout, feed',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadDashboard(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _loadDashboard,
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
                    const Text('No risk dashboard loaded yet.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _loadDashboard,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Load dashboard'),
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
                    Color(0xFFFFFBF7),
                    Color(0xFFF9F0E6),
                    Color(0xFFF3E4D7),
                  ],
                ),
                border: Border.all(color: const Color(0xFFE8D7C5)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x14081F17),
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
                      border: Border.all(color: const Color(0xFFE8D7C5)),
                    ),
                    child: Text(
                      'Coach admin queue',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF9A3412),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Risk command desk',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xFF3B2214),
                          fontWeight: FontWeight.w900,
                          height: .96,
                        ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Text(
                      'Work overdue, critical, and unowned coach risks first. Search the queue, claim ownership, and route issues before they become downstream failures.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF6B4B3A),
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
                      _CoachRiskHeaderBadge(
                        icon: Icons.public_outlined,
                        label: 'Scope: Coach admin',
                      ),
                      _CoachRiskHeaderBadge(
                        icon: Icons.warning_amber_outlined,
                        label: 'Overdue ${response!.summary.overdueRisks}',
                        color: const Color(0xFFB45309),
                      ),
                      _CoachRiskHeaderBadge(
                        icon: Icons.shield_outlined,
                        label: 'Critical ${response!.summary.criticalRisks}',
                        color: const Color(0xFFB91C1C),
                      ),
                      _CoachRiskHeaderBadge(
                        icon: Icons.person_search_outlined,
                        label:
                            'Unowned ${_coachRiskQueueCount(response!.risks, 'unowned')}',
                        color: const Color(0xFF0F766E),
                      ),
                      _CoachRiskHeaderBadge(
                        icon: Icons.update_outlined,
                        label:
                            'Updated ${_coachRiskIsoLabel(response!.generatedAtIso)}',
                        color: const Color(0xFF475569),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Focus queues',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF3B2214),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final focusQueue in const <String>[
                        'overdue',
                        'critical',
                        'unowned',
                        'finance',
                        'partner_feed',
                        'boarding',
                      ])
                        _CoachRiskFocusCard(
                          key: ValueKey('coachRiskFocus_$focusQueue'),
                          icon: switch (focusQueue) {
                            'overdue' => Icons.schedule_outlined,
                            'critical' => Icons.crisis_alert_outlined,
                            'unowned' => Icons.person_off_outlined,
                            'finance' => Icons.account_balance_outlined,
                            'partner_feed' => Icons.hub_outlined,
                            'boarding' => Icons.qr_code_scanner_outlined,
                            _ => Icons.list_alt_outlined,
                          },
                          label: _coachRiskQueueLabel(focusQueue),
                          value:
                              '${_coachRiskQueueCount(response!.risks, focusQueue)}',
                          detail: switch (focusQueue) {
                            'overdue' => 'Past SLA and needs action now',
                            'critical' => 'Highest severity across coach flows',
                            'unowned' => 'Needs assignment before follow-up',
                            'finance' => 'Payouts, statements, and money risk',
                            'partner_feed' =>
                              'Realtime or schedule feed health',
                            'boarding' => 'Manifest and departure exceptions',
                            _ => '',
                          },
                          selected: _selectedQueue == focusQueue,
                          onTap: () {
                            setState(() {
                              _selectedQueue = focusQueue;
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text('Updated ${_coachRiskIsoLabel(response!.generatedAtIso)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Open ${response.summary.openRisks}')),
                Chip(label: Text('Active ${response.summary.activeRisks}')),
                Chip(label: Text('Ack ${response.summary.acknowledgedRisks}')),
                Chip(label: Text('Snoozed ${response.summary.snoozedRisks}')),
                Chip(label: Text('Owned ${response.summary.ownedRisks}')),
                Chip(label: Text('Critical ${response.summary.criticalRisks}')),
                Chip(label: Text('Overdue ${response.summary.overdueRisks}')),
                Chip(label: Text('Due soon ${response.summary.dueSoonRisks}')),
                Chip(label: Text('Finance ${response.summary.financeAlerts}')),
                Chip(label: Text('Support ${response.summary.supportAlerts}')),
                Chip(label: Text('Partners ${response.summary.partnerAlerts}')),
                Chip(
                    label: Text('Boarding ${response.summary.boardingAlerts}')),
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
                  'overdue',
                  'critical',
                  'unowned',
                  'owned',
                  'finance',
                  'partner_feed',
                  'boarding',
                ])
                  ChoiceChip(
                    label: Text(
                      '${_coachRiskQueueLabel(queue)} (${_coachRiskQueueCount(response.risks, queue)})',
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
                  'newest',
                  'amount',
                ])
                  ChoiceChip(
                    label: Text(_coachRiskSortLabel(sort)),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${visibleRisks.length} of ${response.risks.length} risks • Sorted by ${_coachRiskSortLabel(_selectedSort).toLowerCase()}',
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('coachRiskSelectVisibleToggle'),
                  onPressed: visibleRisks.isEmpty
                      ? null
                      : () => _toggleSelectVisible(visibleRisks),
                  icon: Icon(
                    visibleRisks.isNotEmpty &&
                            visibleRisks.every(
                              (risk) =>
                                  _selectedRiskIds.contains(risk.riskId),
                            )
                        ? Icons.deselect_outlined
                        : Icons.select_all_outlined,
                  ),
                  label: Text(
                    visibleRisks.isNotEmpty &&
                            visibleRisks.every(
                              (risk) =>
                                  _selectedRiskIds.contains(risk.riskId),
                            )
                        ? 'Clear visible'
                        : 'Select visible',
                  ),
                ),
              ],
            ),
            if (_selectedRiskIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CoachRiskBulkActionBar(
                selectedCount: _selectedRiskIds.length,
                isBusy: _loading || _bulkActionRunning,
                onClaim: () => _performBulkAction(
                  'claim',
                  response.risks
                      .where(
                        (risk) => _selectedRiskIds.contains(risk.riskId),
                      )
                      .toList(growable: false),
                ),
                onAcknowledge: () => _performBulkAction(
                  'acknowledge',
                  response.risks
                      .where(
                        (risk) => _selectedRiskIds.contains(risk.riskId),
                      )
                      .toList(growable: false),
                ),
                onSnooze: () => _confirmAndBulkSnooze(
                  response.risks
                      .where(
                        (risk) => _selectedRiskIds.contains(risk.riskId),
                      )
                      .toList(growable: false),
                ),
                onResolve: () => _performBulkAction(
                  'resolve',
                  response.risks
                      .where(
                        (risk) => _selectedRiskIds.contains(risk.riskId),
                      )
                      .toList(growable: false),
                ),
                onClear: () => setState(() {
                  _selectedRiskIds.clear();
                }),
              ),
            ],
            const SizedBox(height: 12),
            if (visibleRisks.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No risks match the current search and queue.'),
                ),
              )
            else
              for (final risk in visibleRisks) ...[
                Card(
                  key: ValueKey('coachRiskCard_${risk.riskId}'),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Column(
                      children: [
                        ListTile(
                          onTap: () => _openRiskDetail(risk),
                          leading: SizedBox(
                            width: 72,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  key: ValueKey(
                                    'coachRiskSelect_${risk.riskId}',
                                  ),
                                  value: _selectedRiskIds.contains(
                                    risk.riskId,
                                  ),
                                  onChanged: _bulkActionRunning
                                      ? null
                                      : (selected) => _toggleRiskSelection(
                                            risk.riskId,
                                            selected,
                                          ),
                                ),
                                Icon(
                                  _coachRiskIcon(risk),
                                  color: _coachRiskAccent(risk),
                                ),
                              ],
                            ),
                          ),
                          title: Text(risk.title),
                          subtitle: Text(
                            '${risk.operatorName ?? risk.referenceLabel ?? risk.category} • ${risk.severity.toUpperCase()} • ${_coachRiskWorkflowLabel(risk.workflowStatus)}\n${_coachRiskIsoLabel(risk.detectedAtIso)} • ${risk.status}${risk.ownerAccountId == null ? '' : ' • ${risk.ownerAccountId}'}\n${risk.slaDueAtIso == null ? _coachRiskSlaLabel(risk.slaStatus) : 'Due ${_coachRiskIsoLabel(risk.slaDueAtIso!)} • ${_coachRiskSlaLabel(risk.slaStatus)}'}',
                          ),
                          isThreeLine: true,
                          trailing: risk.amountMinorUnits == null
                              ? null
                              : Text(
                                  _coachRiskMoneyLabel(
                                    risk.currency ?? '',
                                    risk.amountMinorUnits!,
                                  ),
                                  textAlign: TextAlign.end,
                                ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (risk.ownerAccountId != null)
                                Chip(
                                  label: Text('Owner ${risk.ownerAccountId}'),
                                ),
                              if (risk.ownerTeam != null)
                                Chip(
                                  label: Text(
                                    _coachRiskTeamLabel(risk.ownerTeam!),
                                  ),
                                )
                              else if (risk.suggestedTeam != null)
                                Chip(
                                  label: Text(
                                    'Route ${_coachRiskTeamLabel(risk.suggestedTeam!)}',
                                  ),
                                ),
                              Chip(
                                label: Text(_coachRiskWorkflowLabel(
                                    risk.workflowStatus)),
                              ),
                              Chip(
                                backgroundColor:
                                    _coachRiskSlaColor(risk.slaStatus)
                                        ?.withValues(alpha: 0.16),
                                label: Text(_coachRiskSlaLabel(risk.slaStatus)),
                              ),
                              if (risk.followUpTaskLabel != null)
                                Chip(
                                  label: Text(risk.followUpTaskLabel!),
                                ),
                              if (risk.autoCaseLabel != null)
                                Chip(
                                  label: Text(risk.autoCaseLabel!),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: _loading ||
                                        _actioningRiskIds.contains(risk.riskId)
                                    ? null
                                    : () => _performRiskAction(
                                          risk,
                                          'claim',
                                          ownerTeam: risk.suggestedTeam,
                                        ),
                                icon: const Icon(Icons.person_pin_outlined),
                                label: const Text('Claim'),
                              ),
                              PopupMenuButton<String>(
                                enabled: !_loading &&
                                    !_actioningRiskIds.contains(risk.riskId),
                                onSelected: (team) => _performRiskAction(
                                  risk,
                                  'claim',
                                  ownerTeam: team,
                                ),
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'finance_ops',
                                    child: Text('Finance ops'),
                                  ),
                                  PopupMenuItem(
                                    value: 'partner_ops',
                                    child: Text('Partner ops'),
                                  ),
                                  PopupMenuItem(
                                    value: 'support_ops',
                                    child: Text('Support ops'),
                                  ),
                                  PopupMenuItem(
                                    value: 'live_ops',
                                    child: Text('Live ops'),
                                  ),
                                  PopupMenuItem(
                                    value: 'trust_ops',
                                    child: Text('Trust ops'),
                                  ),
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.groups_outlined, size: 18),
                                      SizedBox(width: 6),
                                      Text('Route team'),
                                    ],
                                  ),
                                ),
                              ),
                              if (risk.workflowStatus != 'acknowledged')
                                TextButton.icon(
                                  onPressed: _loading ||
                                          _actioningRiskIds
                                              .contains(risk.riskId)
                                      ? null
                                      : () => _performRiskAction(
                                            risk,
                                            'acknowledge',
                                            ownerTeam: risk.ownerTeam ??
                                                risk.suggestedTeam,
                                          ),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Acknowledge'),
                                ),
                              if (risk.workflowStatus != 'snoozed')
                                TextButton.icon(
                                  key: ValueKey(
                                    'coachRiskSnooze_${risk.riskId}',
                                  ),
                                  onPressed: _loading ||
                                          _actioningRiskIds
                                              .contains(risk.riskId)
                                      ? null
                                      : () => _confirmAndSnoozeRisk(risk),
                                  icon: const Icon(Icons.snooze_outlined),
                                  label: const Text('Snooze'),
                                ),
                              if (risk.workflowStatus != 'resolved')
                                TextButton.icon(
                                  onPressed: _loading ||
                                          _actioningRiskIds
                                              .contains(risk.riskId)
                                      ? null
                                      : () => _performRiskAction(
                                            risk,
                                            'resolve',
                                            ownerTeam: risk.ownerTeam ??
                                                risk.suggestedTeam,
                                          ),
                                  icon: const Icon(Icons.task_alt_outlined),
                                  label: const Text('Resolve'),
                                ),
                              if (risk.workflowStatus == 'acknowledged' ||
                                  risk.workflowStatus == 'snoozed')
                                TextButton.icon(
                                  onPressed: _loading ||
                                          _actioningRiskIds
                                              .contains(risk.riskId)
                                      ? null
                                      : () => _performRiskAction(
                                            risk,
                                            'reopen',
                                          ),
                                  icon: const Icon(Icons.refresh_outlined),
                                  label: const Text('Reopen'),
                                ),
                            ],
                          ),
                        ),
                      ],
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

class _CoachRiskHeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoachRiskHeaderBadge({
    required this.icon,
    required this.label,
    this.color = const Color(0xFF6B4B3A),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE8D7C5)),
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

class _CoachRiskFocusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  const _CoachRiskFocusCard({
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
                  ? const Color(0xFFFDEAD7)
                  : Colors.white.withValues(alpha: .76),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? const Color(0xFFF08D49)
                    : const Color(0xFFE8D7C5),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? const Color(0xFF9A3412)
                      : const Color(0xFF8A5A44),
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF3B2214),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF3B2214),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B4B3A),
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

class _CoachRiskBulkActionBar extends StatelessWidget {
  final int selectedCount;
  final bool isBusy;
  final VoidCallback onClaim;
  final VoidCallback onAcknowledge;
  final VoidCallback onSnooze;
  final VoidCallback onResolve;
  final VoidCallback onClear;

  const _CoachRiskBulkActionBar({
    required this.selectedCount,
    required this.isBusy,
    required this.onClaim,
    required this.onAcknowledge,
    required this.onSnooze,
    required this.onResolve,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFDEAD7),
            Color(0xFFF6D3B3),
          ],
        ),
        border: Border.all(color: const Color(0xFFF08D49), width: 1.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14081F17),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.checklist_outlined,
                color: Color(0xFF9A3412),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$selectedCount '
                  '${selectedCount == 1 ? 'risk' : 'risks'} selected',
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF3B2214),
                            fontWeight: FontWeight.w800,
                          ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('coachRiskBulkClear'),
                onPressed: isBusy ? null : onClear,
                icon: const Icon(Icons.close, color: Color(0xFF6B4B3A)),
                label: const Text(
                  'Clear',
                  style: TextStyle(color: Color(0xFF6B4B3A)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Apply the same workflow action to every selected risk. '
            'Routing defaults to the suggested team.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF6B4B3A),
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('coachRiskBulkClaim'),
                onPressed: isBusy ? null : onClaim,
                icon: const Icon(Icons.person_pin_outlined),
                label: const Text('Claim all'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9A3412),
                  foregroundColor: Colors.white,
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('coachRiskBulkAcknowledge'),
                onPressed: isBusy ? null : onAcknowledge,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Acknowledge all'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('coachRiskBulkSnooze'),
                onPressed: isBusy ? null : onSnooze,
                icon: const Icon(Icons.snooze_outlined),
                label: const Text('Snooze...'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6B4B3A),
                  side: const BorderSide(color: Color(0xFFE8D7C5)),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('coachRiskBulkResolve'),
                onPressed: isBusy ? null : onResolve,
                icon: const Icon(Icons.task_alt_outlined),
                label: const Text('Resolve all'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9A3412),
                  side: const BorderSide(color: Color(0xFFF08D49)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoachAdminRiskDetailSheet extends StatelessWidget {
  final CoachAdminRiskItem risk;

  const _CoachAdminRiskDetailSheet({
    required this.risk,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(risk.title),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _coachRiskIcon(risk),
              color: _coachRiskAccent(risk),
            ),
            title: Text('${risk.severity.toUpperCase()} • ${risk.category}'),
            subtitle: Text(
              '${risk.status} • ${_coachRiskIsoLabel(risk.detectedAtIso)}',
            ),
            trailing: risk.amountMinorUnits == null
                ? null
                : Text(
                    _coachRiskMoneyLabel(
                      risk.currency ?? '',
                      risk.amountMinorUnits!,
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
          ),
          const SizedBox(height: 12),
          if (risk.operatorName != null || risk.bookingId != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Context', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (risk.operatorName != null)
                      Text('Operator ${risk.operatorName}'),
                    if (risk.bookingId != null)
                      Text('Booking ${risk.bookingId}'),
                    if (risk.statementId != null)
                      Text('Statement ${risk.statementId}'),
                    if (risk.payoutRunId != null)
                      Text('Payout ${risk.payoutRunId}'),
                    if (risk.tripId != null) Text('Trip ${risk.tripId}'),
                    if (risk.referenceLabel != null) Text(risk.referenceLabel!),
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
                  Text('Workflow', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_coachRiskWorkflowLabel(risk.workflowStatus)),
                  if (risk.ownerAccountId != null)
                    Text('Owner ${risk.ownerAccountId}'),
                  if (risk.ownerTeam != null)
                    Text('Team ${_coachRiskTeamLabel(risk.ownerTeam!)}'),
                  if (risk.suggestedTeam != null)
                    Text(
                        'Suggested team ${_coachRiskTeamLabel(risk.suggestedTeam!)}'),
                  if (risk.snoozedUntilIso != null)
                    Text(
                      'Snoozed until ${_coachRiskIsoLabel(risk.snoozedUntilIso!)}',
                    ),
                  if (risk.snoozeReason != null)
                    Text('Snooze reason ${risk.snoozeReason}'),
                  if (risk.workflowUpdatedByAccountId != null)
                    Text('Updated by ${risk.workflowUpdatedByAccountId}'),
                  if (risk.workflowUpdatedAtIso != null)
                    Text(
                      'Updated ${_coachRiskIsoLabel(risk.workflowUpdatedAtIso!)}',
                    ),
                  if (risk.workflowNote != null)
                    Text('Note ${risk.workflowNote}'),
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
                  Text('SLA', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_coachRiskSlaLabel(risk.slaStatus)),
                  if (risk.slaDueAtIso != null)
                    Text('Due ${_coachRiskIsoLabel(risk.slaDueAtIso!)}'),
                  if (risk.followUpTaskLabel != null)
                    Text('Task ${risk.followUpTaskLabel}'),
                  if (risk.followUpTaskDetail != null)
                    Text(risk.followUpTaskDetail!),
                  if (risk.autoCaseId != null)
                    Text('Auto case ${risk.autoCaseId}'),
                  if (risk.autoCaseStatus != null)
                    Text('Auto case status ${risk.autoCaseStatus}'),
                ],
              ),
            ),
          ),
          if (risk.routingReason != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Routing', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (risk.suggestedTeam != null)
                      Text(
                          'Suggested team ${_coachRiskTeamLabel(risk.suggestedTeam!)}'),
                    if (risk.routingSource != null)
                      Text(
                        'Source ${_coachRiskRoutingSourceLabel(risk.routingSource!)}',
                      ),
                    Text(risk.routingReason!),
                  ],
                ),
              ),
            ),
          ],
          if (risk.nextAction != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next action', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(risk.nextAction!),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Details', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (risk.detailLines.isEmpty)
                    const Text('No extra detail available.')
                  else
                    for (final line in risk.detailLines) ...[
                      Text(line),
                      const SizedBox(height: 6),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachRiskSnoozeSheet extends StatefulWidget {
  final String title;
  final String defaultReason;

  const _CoachRiskSnoozeSheet({
    required this.title,
    required this.defaultReason,
  });

  @override
  State<_CoachRiskSnoozeSheet> createState() => _CoachRiskSnoozeSheetState();
}

class _CoachRiskSnoozeSheetState extends State<_CoachRiskSnoozeSheet> {
  String _duration = '24h';
  DateTime? _customUntil;
  late final TextEditingController _reasonController =
      TextEditingController(text: widget.defaultReason);
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _customUntil?.toLocal() ??
          now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _customUntil?.toLocal() ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _customUntil = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc();
      _duration = 'custom';
    });
  }

  DateTime _resolveSnoozeUntil() {
    return _coachRiskSnoozeUntilFromDuration(
      _duration,
      DateTime.now().toUtc(),
      _customUntil,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reasonText = _reasonController.text.trim();
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        title: Text(
          widget.title,
          style: theme.textTheme.titleLarge?.copyWith(
            color: const Color(0xFF3B2214),
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('coachRiskSnoozeClose'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            color: const Color(0xFF6B4B3A),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Snooze duration',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF3B2214),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final duration in const <String>[
                    '1h',
                    '4h',
                    '24h',
                    '3d',
                    'custom',
                  ])
                    ChoiceChip(
                      key: ValueKey('coachRiskSnoozeDuration_$duration'),
                      label: Text(_coachRiskSnoozeDurationLabel(duration)),
                      selected: _duration == duration,
                      selectedColor: const Color(0xFFFDEAD7),
                      side: BorderSide(
                        color: _duration == duration
                            ? const Color(0xFFF08D49)
                            : const Color(0xFFE8D7C5),
                      ),
                      onSelected: (selected) {
                        if (!selected) return;
                        if (duration == 'custom') {
                          _pickCustomDateTime();
                          return;
                        }
                        setState(() {
                          _duration = duration;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8D7C5)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_outlined,
                      size: 18,
                      color: Color(0xFF9A3412),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Until ${_coachRiskIsoLabel(
                          _resolveSnoozeUntil().toIso8601String(),
                        )}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF3B2214),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Reason',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF3B2214),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('coachRiskSnoozeReasonField'),
                controller: _reasonController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Why is this being snoozed?',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text(
                'Internal note (optional)',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF3B2214),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('coachRiskSnoozeNoteField'),
                controller: _noteController,
                decoration: const InputDecoration(
                  hintText: 'Context for the audit trail',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                    key: const ValueKey('coachRiskSnoozeCancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF6B4B3A),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('coachRiskSnoozeSubmit'),
                      onPressed: reasonText.isEmpty
                          ? null
                          : () {
                              Navigator.of(context).pop(
                                _CoachRiskSnoozeRequest(
                                  snoozedUntilIso: _resolveSnoozeUntil()
                                      .toIso8601String(),
                                  reason: reasonText,
                                  note: _noteController.text.trim().isEmpty
                                      ? null
                                      : _noteController.text.trim(),
                                ),
                              );
                            },
                      icon: const Icon(Icons.snooze_outlined),
                      label: const Text('Snooze'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF9A3412),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
