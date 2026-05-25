import 'package:flutter/material.dart';

import '../safe_set_state.dart';
import '../shamell_empty_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_mobility_api.dart';

String _coachPartnerIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

Color _coachPartnerWorkflowColor(String workflowStatus) {
  switch (workflowStatus) {
    case 'approved':
      return Colors.green;
    case 'in_review':
      return Colors.blue;
    case 'action_required':
      return Colors.orange;
    case 'suspended':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

String _coachPartnerWorkflowLabel(String workflowStatus) {
  switch (workflowStatus) {
    case 'approved':
      return 'Approved';
    case 'in_review':
      return 'In review';
    case 'action_required':
      return 'Action required';
    case 'suspended':
      return 'Suspended';
    default:
      return 'Draft';
  }
}

String _coachPartnerQueueLabel(String queue) {
  switch (queue) {
    case 'action_required':
      return 'Action required';
    case 'in_review':
      return 'In review';
    case 'missing_docs':
      return 'Missing docs';
    case 'feed_alerts':
      return 'Feed alerts';
    case 'expiring_docs':
      return 'Expiring docs';
    case 'ready':
      return 'Ready to approve';
    default:
      return 'All';
  }
}

int _coachPartnerFeedAlertCount(CoachAdminPartnerOnboardingRecord partner) {
  return partner.feedSummary.degradedFeeds + partner.feedSummary.staleFeeds;
}

bool _coachPartnerReadyToApprove(CoachAdminPartnerOnboardingRecord partner) {
  return partner.workflowStatus != 'approved' &&
      partner.workflowStatus != 'suspended' &&
      partner.missingDocuments == 0 &&
      partner.expiringDocuments == 0 &&
      partner.pendingCapabilities == 0 &&
      partner.blockers.isEmpty &&
      _coachPartnerFeedAlertCount(partner) == 0;
}

bool _coachPartnerMatchesQueue(
  CoachAdminPartnerOnboardingRecord partner,
  String queue,
) {
  switch (queue) {
    case 'action_required':
      return partner.workflowStatus == 'action_required';
    case 'in_review':
      return partner.workflowStatus == 'in_review';
    case 'missing_docs':
      return partner.missingDocuments > 0;
    case 'feed_alerts':
      return _coachPartnerFeedAlertCount(partner) > 0;
    case 'expiring_docs':
      return partner.expiringDocuments > 0;
    case 'ready':
      return _coachPartnerReadyToApprove(partner);
    default:
      return true;
  }
}

int _coachPartnerQueueCount(
  List<CoachAdminPartnerOnboardingRecord> partners,
  String queue,
) {
  return partners
      .where((partner) => _coachPartnerMatchesQueue(partner, queue))
      .length;
}

String _coachPartnerSortLabel(String sort) {
  switch (sort) {
    case 'due':
      return 'Due first';
    case 'readiness':
      return 'Ready first';
    default:
      return 'Priority';
  }
}

int _coachPartnerPriorityRank(String workflowStatus) {
  switch (workflowStatus) {
    case 'action_required':
      return 0;
    case 'suspended':
      return 1;
    case 'in_review':
      return 2;
    case 'draft':
      return 3;
    case 'approved':
      return 4;
    default:
      return 5;
  }
}

DateTime _coachPartnerDueTimestamp(String? iso) {
  return DateTime.tryParse(iso ?? '')?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(
        253402300799000,
        isUtc: true,
      );
}

DateTime _coachPartnerUpdatedTimestamp(String iso) {
  return DateTime.tryParse(iso)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _coachPartnerIssueCount(CoachAdminPartnerOnboardingRecord partner) {
  return partner.missingDocuments +
      partner.expiringDocuments +
      partner.pendingCapabilities +
      partner.blockers.length +
      _coachPartnerFeedAlertCount(partner);
}

int _coachPartnerChecklistDone(CoachAdminPartnerOnboardingRecord partner) {
  return partner.checklist.where((item) => item.status == 'done').length;
}

List<CoachAdminPartnerOnboardingRecord> _coachPartnerSortedItems(
  List<CoachAdminPartnerOnboardingRecord> partners,
  String sort,
) {
  final out = List<CoachAdminPartnerOnboardingRecord>.of(partners);
  out.sort((left, right) {
    if (sort == 'due') {
      final dueCompare = _coachPartnerDueTimestamp(
        left.dueAtIso,
      ).compareTo(_coachPartnerDueTimestamp(right.dueAtIso));
      if (dueCompare != 0) {
        return dueCompare;
      }
    }
    if (sort == 'readiness') {
      final readyCompare = (_coachPartnerReadyToApprove(right) ? 1 : 0)
          .compareTo(_coachPartnerReadyToApprove(left) ? 1 : 0);
      if (readyCompare != 0) {
        return readyCompare;
      }
      final issueCompare = _coachPartnerIssueCount(
        left,
      ).compareTo(_coachPartnerIssueCount(right));
      if (issueCompare != 0) {
        return issueCompare;
      }
    }
    final priorityCompare = _coachPartnerPriorityRank(
      left.workflowStatus,
    ).compareTo(_coachPartnerPriorityRank(right.workflowStatus));
    if (priorityCompare != 0) {
      return priorityCompare;
    }
    final issueCompare = _coachPartnerIssueCount(
      right,
    ).compareTo(_coachPartnerIssueCount(left));
    if (issueCompare != 0) {
      return issueCompare;
    }
    final dueCompare = _coachPartnerDueTimestamp(
      left.dueAtIso,
    ).compareTo(_coachPartnerDueTimestamp(right.dueAtIso));
    if (dueCompare != 0) {
      return dueCompare;
    }
    final updatedCompare = _coachPartnerUpdatedTimestamp(
      right.updatedAtIso,
    ).compareTo(_coachPartnerUpdatedTimestamp(left.updatedAtIso));
    if (updatedCompare != 0) {
      return updatedCompare;
    }
    return left.operatorId.compareTo(right.operatorId);
  });
  return out;
}

class CoachAdminPartnerOnboardingPage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final CoachAdminPartnerOnboardingResponse? initialResponse;

  const CoachAdminPartnerOnboardingPage({
    super.key,
    required this.baseUrl,
    this.api,
    this.initialResponse,
  });

  @override
  State<CoachAdminPartnerOnboardingPage> createState() =>
      _CoachAdminPartnerOnboardingPageState();
}

class _CoachAdminPartnerOnboardingPageState
    extends State<CoachAdminPartnerOnboardingPage>
    with SafeSetStateMixin<CoachAdminPartnerOnboardingPage> {
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final TextEditingController _queryController = TextEditingController();

  CoachAdminPartnerOnboardingResponse? _response;
  bool _loading = false;
  String? _errorMessage;
  String _workflowStatusFilter = 'all';
  String _selectedQueue = 'all';
  String _selectedSort = 'priority';
  final Set<String> _busyOperatorIds = <String>{};

  @override
  void initState() {
    super.initState();
    _response = widget.initialResponse;
    _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final response = await _api.adminPartnerOnboarding(
        query: _queryController.text,
        workflowStatus:
            _workflowStatusFilter == 'all' ? null : _workflowStatusFilter,
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

  CoachAdminPartnerOnboardingSummary _summaryFromRecords(
    List<CoachAdminPartnerOnboardingRecord> partners,
  ) {
    return CoachAdminPartnerOnboardingSummary(
      operatorsTotal: partners.length,
      draftOperators:
          partners.where((partner) => partner.workflowStatus == 'draft').length,
      inReviewOperators: partners
          .where((partner) => partner.workflowStatus == 'in_review')
          .length,
      actionRequiredOperators: partners
          .where((partner) => partner.workflowStatus == 'action_required')
          .length,
      approvedOperators: partners
          .where((partner) => partner.workflowStatus == 'approved')
          .length,
      suspendedOperators: partners
          .where((partner) => partner.workflowStatus == 'suspended')
          .length,
      missingDocuments:
          partners.fold(0, (sum, partner) => sum + partner.missingDocuments),
      expiringDocuments:
          partners.fold(0, (sum, partner) => sum + partner.expiringDocuments),
    );
  }

  void _mergePartner(CoachAdminPartnerOnboardingRecord partner) {
    final current = _response;
    if (current == null) return;
    final partners = current.partners
        .map((candidate) =>
            candidate.operatorId == partner.operatorId ? partner : candidate)
        .toList(growable: false);
    setState(() {
      _response = CoachAdminPartnerOnboardingResponse(
        generatedAtIso: DateTime.now().toUtc().toIso8601String(),
        summary: _summaryFromRecords(partners),
        partners: partners,
      );
    });
  }

  Future<void> _runAction(
    CoachAdminPartnerOnboardingRecord partner,
    String action,
  ) async {
    setState(() {
      _busyOperatorIds.add(partner.operatorId);
    });
    try {
      final result = await _api.adminPartnerOnboardingAction(
        operatorId: partner.operatorId,
        action: action,
      );
      _mergePartner(result.partner);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${partner.operatorName}: ${_coachPartnerWorkflowLabel(result.partner.workflowStatus)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      setState(() {
        _busyOperatorIds.remove(partner.operatorId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final response = _response;
    final filteredPartners = response == null
        ? const <CoachAdminPartnerOnboardingRecord>[]
        : response.partners
            .where(
                (partner) => _coachPartnerMatchesQueue(partner, _selectedQueue))
            .toList(growable: false);
    final visiblePartners = _coachPartnerSortedItems(
      filteredPartners,
      _selectedSort,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner onboarding'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null) ...[
              StatusBanner.error(_errorMessage!),
              const SizedBox(height: 12),
            ],
            StatusBanner.info(
              response == null
                  ? 'Review operator onboarding, certification, and readiness before go-live.'
                  : 'Updated ${_coachPartnerIsoLabel(response.generatedAtIso)}.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: const InputDecoration(
                      labelText: 'Search operators',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _workflowStatusFilter,
                  onChanged: _loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _workflowStatusFilter = value;
                          });
                          _load();
                        },
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(
                      value: 'in_review',
                      child: Text('In review'),
                    ),
                    DropdownMenuItem(
                      value: 'action_required',
                      child: Text('Action required'),
                    ),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('Suspended'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading && response == null)
              const ShamellSkeletonList(itemCount: 5)
            else if (response == null)
              const ShamellEmptyState.empty(
                icon: Icons.handshake_outlined,
                title: 'No partner onboarding data loaded yet.',
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
                      Color(0xFFF9FCF8),
                      Color(0xFFEDF6EF),
                      Color(0xFFE3F0E7),
                    ],
                  ),
                  border: Border.all(color: const Color(0xFFD5E4D7)),
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
                        border: Border.all(color: const Color(0xFFD5E4D7)),
                      ),
                      child: Text(
                        'Coach admin queue',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF166534),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Partner readiness desk',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: const Color(0xFF16362B),
                                fontWeight: FontWeight.w900,
                                height: .96,
                              ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        'Work blocked, expiring, and near-ready operators from one queue. Use this board to push documentation, certification, and feed readiness to launch.',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: const Color(0xFF51675D),
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
                        _CoachPartnerHeaderBadge(
                          icon: Icons.public_outlined,
                          label: 'Scope: Coach admin',
                        ),
                        _CoachPartnerHeaderBadge(
                          icon: Icons.warning_amber_outlined,
                          label:
                              'Action required ${response.summary.actionRequiredOperators}',
                          color: const Color(0xFFB45309),
                        ),
                        _CoachPartnerHeaderBadge(
                          icon: Icons.description_outlined,
                          label:
                              'Missing docs ${response.summary.missingDocuments}',
                          color: const Color(0xFFB91C1C),
                        ),
                        _CoachPartnerHeaderBadge(
                          icon: Icons.hub_outlined,
                          label:
                              'Feed alerts ${response.partners.fold<int>(0, (sum, partner) => sum + _coachPartnerFeedAlertCount(partner))}',
                          color: const Color(0xFF0F766E),
                        ),
                        _CoachPartnerHeaderBadge(
                          icon: Icons.update_outlined,
                          label:
                              'Updated ${_coachPartnerIsoLabel(response.generatedAtIso)}',
                          color: const Color(0xFF475569),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Focus queues',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: const Color(0xFF214739),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final queue in const <String>[
                          'action_required',
                          'in_review',
                          'missing_docs',
                          'feed_alerts',
                          'expiring_docs',
                          'ready',
                        ])
                          _CoachPartnerFocusCard(
                            key: ValueKey('coachPartnerFocus_$queue'),
                            icon: switch (queue) {
                              'action_required' => Icons.crisis_alert_outlined,
                              'in_review' => Icons.fact_check_outlined,
                              'missing_docs' => Icons.description_outlined,
                              'feed_alerts' => Icons.hub_outlined,
                              'expiring_docs' => Icons.event_busy_outlined,
                              'ready' => Icons.task_alt_outlined,
                              _ => Icons.list_alt_outlined,
                            },
                            label: _coachPartnerQueueLabel(queue),
                            value:
                                '${_coachPartnerQueueCount(response.partners, queue)}',
                            detail: switch (queue) {
                              'action_required' =>
                                'Blocked operators that need an explicit next move',
                              'in_review' =>
                                'Partners in certification or approval review',
                              'missing_docs' =>
                                'Required paperwork still missing or rejected',
                              'feed_alerts' =>
                                'Degraded or stale feeds that block readiness',
                              'expiring_docs' =>
                                'Documents approaching renewal windows',
                              'ready' => 'Operators that are clear to approve',
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                      label:
                          Text('Operators ${response.summary.operatorsTotal}')),
                  Chip(
                      label: Text(
                          'Approved ${response.summary.approvedOperators}')),
                  Chip(
                    label: Text('Review ${response.summary.inReviewOperators}'),
                  ),
                  Chip(
                    label: Text(
                      'Action required ${response.summary.actionRequiredOperators}',
                    ),
                  ),
                  Chip(
                    label: Text(
                      'Missing docs ${response.summary.missingDocuments}',
                    ),
                  ),
                  Chip(
                    label: Text(
                      'Expiring docs ${response.summary.expiringDocuments}',
                    ),
                  ),
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
                    'action_required',
                    'in_review',
                    'missing_docs',
                    'feed_alerts',
                    'expiring_docs',
                    'ready',
                  ])
                    ChoiceChip(
                      label: Text(
                        '${_coachPartnerQueueLabel(queue)} (${_coachPartnerQueueCount(response.partners, queue)})',
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
                    'due',
                    'readiness',
                  ])
                    ChoiceChip(
                      label: Text(_coachPartnerSortLabel(sort)),
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
              Text(
                'Showing ${visiblePartners.length} of ${response.partners.length} operators • Sorted by ${_coachPartnerSortLabel(_selectedSort).toLowerCase()}',
              ),
              const SizedBox(height: 12),
              if (visiblePartners.isEmpty)
                const Text('No operators match the current filters.')
              else
                ...visiblePartners.map(_buildPartnerCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerCard(CoachAdminPartnerOnboardingRecord partner) {
    final busy = _busyOperatorIds.contains(partner.operatorId);
    final statusColor = _coachPartnerWorkflowColor(partner.workflowStatus);
    final feedAlerts = _coachPartnerFeedAlertCount(partner);
    final checklistDone = _coachPartnerChecklistDone(partner);
    return Card(
      key: ValueKey('coachPartnerCard_${partner.operatorId}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        partner.operatorName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${partner.operatorId} • ${partner.integrationMode}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(
                  backgroundColor: statusColor.withValues(alpha: .14),
                  label: Text(
                    _coachPartnerWorkflowLabel(partner.workflowStatus),
                    style: TextStyle(color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(partner.integrationMode)),
                Chip(
                  label: Text(
                    'Docs ${partner.documents.length} • missing ${partner.missingDocuments}',
                  ),
                ),
                Chip(
                  label: Text('Expiring ${partner.expiringDocuments}'),
                ),
                Chip(
                  label: Text('Feed alerts $feedAlerts'),
                ),
                Chip(
                  label: Text(
                    'Capabilities ${partner.enabledCapabilities} enabled • ${partner.pendingCapabilities} pending',
                  ),
                ),
                Chip(
                  label: Text(
                    'Checklist $checklistDone/${partner.checklist.length}',
                  ),
                ),
                if (partner.ownerAccountId != null)
                  Chip(label: Text('Owner ${partner.ownerAccountId}'))
                else
                  const Chip(label: Text('Unowned')),
                if (partner.dueAtIso != null)
                  Chip(
                    label: Text(
                      'Due ${_coachPartnerIsoLabel(partner.dueAtIso!)}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8F5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD9E7DD)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next action',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    partner.nextAction,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (partner.note != null && partner.note!.isNotEmpty) ...[
              Text(
                partner.note!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
            ],
            if (partner.feedSummary.lastSucceededAtIso != null) ...[
              Text(
                'Last healthy feed ${_coachPartnerIsoLabel(partner.feedSummary.lastSucceededAtIso!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
            ],
            if (partner.blockers.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Blockers',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              ...partner.blockers.map(
                (blocker) => Text(
                  '• $blocker',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final document in partner.documents)
                  Chip(
                    label: Text('${document.label}: ${document.status}'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : () => _runAction(partner, 'claim'),
                  child: Text(busy ? 'Working...' : 'Claim'),
                ),
                OutlinedButton(
                  onPressed:
                      busy ? null : () => _runAction(partner, 'start_review'),
                  child: const Text('Start review'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _runAction(partner, 'request_documents'),
                  child: const Text('Request docs'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => _runAction(partner, 'approve'),
                  child: const Text('Approve'),
                ),
                TextButton(
                  onPressed: busy ? null : () => _runAction(partner, 'suspend'),
                  child: const Text('Suspend'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachPartnerHeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoachPartnerHeaderBadge({
    required this.icon,
    required this.label,
    this.color = const Color(0xFF51675D),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD5E4D7)),
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

class _CoachPartnerFocusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  const _CoachPartnerFocusCard({
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
                  ? const Color(0xFFEAF6EC)
                  : Colors.white.withValues(alpha: .76),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? const Color(0xFF5A9C6B)
                    : const Color(0xFFD5E4D7),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? const Color(0xFF166534)
                      : const Color(0xFF567261),
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF16362B),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF16362B),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF51675D),
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
