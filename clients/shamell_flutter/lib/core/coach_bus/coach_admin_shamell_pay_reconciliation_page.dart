import 'package:flutter/material.dart';

import '../format.dart';
import '../safe_set_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_mobility_api.dart';

String _coachShamellPayIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

String _coachShamellPayMoneyLabel(String currency, int minorUnits) {
  return '${fmtCents(minorUnits)} $currency';
}

String _coachShamellPaySignedMoneyLabel(String currency, int minorUnits) {
  if (minorUnits == 0) {
    return _coachShamellPayMoneyLabel(currency, minorUnits);
  }
  final sign = minorUnits > 0 ? '+' : '-';
  return '$sign${fmtCents(minorUnits.abs())} $currency';
}

String _coachShamellPayStatusLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _coachShamellPayImportSourceLabel(String raw) {
  switch (raw.trim()) {
    case 'psp_report':
      return 'SyrChat Pay report';
    case 'manual_upload':
      return 'Manual operator rail action';
    case 'bank_report':
      return 'Operator rail confirmation';
    default:
      return _coachShamellPayStatusLabel(raw);
  }
}

String _coachShamellPayQueueLabel(String queue) {
  switch (queue) {
    case 'attention':
      return 'Attention';
    case 'escalated':
      return 'Escalated';
    case 'awaiting_shamell_pay':
      return 'Awaiting SyrChat Pay';
    case 'operator_rail_pending':
      return 'Operator rail';
    case 'failed':
      return 'Failed';
    case 'status_mismatch':
      return 'Status mismatch';
    default:
      return 'All';
  }
}

String _coachShamellPaySortLabel(String sort) {
  switch (sort) {
    case 'latest':
      return 'Latest activity';
    case 'retries':
      return 'Most retries';
    default:
      return 'Priority';
  }
}

bool _coachShamellPayMatchesQueue(
  CoachAdminShamellPayReconciliationRun run,
  String queue,
) {
  switch (queue) {
    case 'attention':
      return run.needsAttention;
    case 'escalated':
      return run.escalated;
    case 'awaiting_shamell_pay':
      return run.reconciliationStatus == 'awaiting_shamell_pay' ||
          run.shamellPayStatus == 'not_reported';
    case 'operator_rail_pending':
      return run.reconciliationStatus == 'operator_rail_pending';
    case 'failed':
      return run.reconciliationStatus == 'failed' ||
          run.downstreamStatus == 'failed';
    case 'status_mismatch':
      return run.reconciliationStatus == 'status_mismatch';
    default:
      return true;
  }
}

int _coachShamellPayQueueCount(
  List<CoachAdminShamellPayReconciliationRun> runs,
  String queue,
) {
  return runs.where((run) => _coachShamellPayMatchesQueue(run, queue)).length;
}

String? _coachShamellPayAttemptSummaryLabel(
  CoachAdminShamellPayReconciliationRun run,
) {
  final count = run.downstreamAttempts.length;
  if (count <= 0) return null;
  if (count == 1) return '1 rail attempt';
  return '$count rail attempts';
}

String _coachShamellPayEscalationBannerLabel(int escalatedRuns) {
  if (escalatedRuns == 1) {
    return 'Repeated operator rail failures detected on 1 payout run. Escalate before another retry.';
  }
  return 'Repeated operator rail failures detected on $escalatedRuns payout runs. Escalate before another retry.';
}

String _coachShamellPayImportResultLabel(
  CoachOperatorPayoutImportBatchMutationResult result,
) {
  return result.dryRun ? 'Latest preview' : 'Latest import';
}

String _coachShamellPayImportStateLabel(
  CoachOperatorPayoutImportBatchMutationResult result,
) {
  if (result.dryRun) {
    return 'Preview ready';
  }
  if (result.failedRows.isNotEmpty) {
    return 'Imported with failures';
  }
  return 'Import applied';
}

int _coachShamellPayPriorityRank(CoachAdminShamellPayReconciliationRun run) {
  if (run.escalated) {
    return 0;
  }
  switch (run.reconciliationStatus) {
    case 'failed':
      return 1;
    case 'status_mismatch':
      return 2;
    case 'operator_rail_pending':
      return run.downstreamStatus == 'pending' ? 3 : 4;
    case 'awaiting_shamell_pay':
      return 5;
    case 'reconciled':
      return 8;
    default:
      return run.needsAttention ? 6 : 7;
  }
}

DateTime _coachShamellPayTimestamp(String iso) {
  return DateTime.tryParse(iso)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _coachShamellPayAmountMagnitude(
  CoachAdminShamellPayReconciliationRun run,
) {
  return run.expectedNetPayableMinorUnits.abs();
}

List<CoachAdminShamellPayReconciliationRun> _coachShamellPaySortedRuns(
  List<CoachAdminShamellPayReconciliationRun> runs,
  String sort,
) {
  final out = List<CoachAdminShamellPayReconciliationRun>.of(runs);
  out.sort((left, right) {
    if (sort == 'latest') {
      final latestCompare = _coachShamellPayTimestamp(
        right.occurredAtIso,
      ).compareTo(_coachShamellPayTimestamp(left.occurredAtIso));
      if (latestCompare != 0) {
        return latestCompare;
      }
    }
    if (sort == 'retries') {
      final retryCompare = right.downstreamAttemptCount.compareTo(
        left.downstreamAttemptCount,
      );
      if (retryCompare != 0) {
        return retryCompare;
      }
      final failedRetryCompare = right.downstreamFailedAttemptCount.compareTo(
        left.downstreamFailedAttemptCount,
      );
      if (failedRetryCompare != 0) {
        return failedRetryCompare;
      }
    }
    final priorityCompare = _coachShamellPayPriorityRank(left).compareTo(
      _coachShamellPayPriorityRank(right),
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
    final failedAttemptsCompare = right.downstreamFailedAttemptCount.compareTo(
      left.downstreamFailedAttemptCount,
    );
    if (failedAttemptsCompare != 0) {
      return failedAttemptsCompare;
    }
    final amountCompare = _coachShamellPayAmountMagnitude(
      right,
    ).compareTo(_coachShamellPayAmountMagnitude(left));
    if (amountCompare != 0) {
      return amountCompare;
    }
    final occurredCompare = _coachShamellPayTimestamp(
      right.occurredAtIso,
    ).compareTo(_coachShamellPayTimestamp(left.occurredAtIso));
    if (occurredCompare != 0) {
      return occurredCompare;
    }
    return left.payoutRunId.compareTo(right.payoutRunId);
  });
  return out;
}

Color _coachShamellPayBadgeColor(String status) {
  switch (status) {
    case 'reconciled':
    case 'executed':
    case 'booked':
      return const Color(0xFF0F766E);
    case 'failed':
      return const Color(0xFFB91C1C);
    case 'operator_rail_pending':
    case 'pending':
    case 'awaiting_shamell_pay':
    case 'not_reported':
    case 'status_mismatch':
      return const Color(0xFFB45309);
    default:
      return const Color(0xFF526176);
  }
}

IconData _coachShamellPayStatusIcon(CoachAdminShamellPayReconciliationRun run) {
  switch (run.reconciliationStatus) {
    case 'reconciled':
      return Icons.check_circle_outline;
    case 'awaiting_shamell_pay':
      return Icons.pending_outlined;
    case 'operator_rail_pending':
      return Icons.account_balance_outlined;
    case 'failed':
      return Icons.error_outline;
    default:
      return Icons.sync_problem_outlined;
  }
}

class CoachAdminShamellPayReconciliationPage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final CoachAdminShamellPayReconciliationResponse? initialResponse;

  const CoachAdminShamellPayReconciliationPage({
    super.key,
    required this.baseUrl,
    this.api,
    this.initialResponse,
  });

  @override
  State<CoachAdminShamellPayReconciliationPage> createState() =>
      _CoachAdminShamellPayReconciliationPageState();
}

class _CoachAdminShamellPayReconciliationPageState
    extends State<CoachAdminShamellPayReconciliationPage>
    with SafeSetStateMixin<CoachAdminShamellPayReconciliationPage> {
  static const String _reportTemplateHeader =
      'merchant_reference,psp_status,psp_reference,settlement_reference,booked_at,description\n';

  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _reportNameController =
      TextEditingController(text: 'shamell_pay_report.csv');
  final TextEditingController _reportBodyController =
      TextEditingController(text: _reportTemplateHeader);
  final TextEditingController _noteController = TextEditingController();

  bool _loading = false;
  bool _showImportComposer = false;
  bool _importingReport = false;
  final Set<String> _releasingOperatorRailRunIds = <String>{};
  final Set<String> _confirmingOperatorRailRunIds = <String>{};
  final Set<String> _failingOperatorRailRunIds = <String>{};
  String _selectedQueue = 'all';
  String _selectedSort = 'priority';
  String? _errorMessage;
  String? _successMessage;
  String? _activePreviewToken;
  CoachOperatorPayoutImportBatchMutationResult? _latestImportResult;
  CoachAdminShamellPayReconciliationResponse? _response;

  @override
  void initState() {
    super.initState();
    _reportNameController.addListener(_handleImportDraftChanged);
    _reportBodyController.addListener(_handleImportDraftChanged);
    _noteController.addListener(_handleImportDraftChanged);
    _response = widget.initialResponse;
    if (_response == null) {
      _loadReconciliation();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _reportNameController.dispose();
    _reportBodyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _handleImportDraftChanged() {
    if (_activePreviewToken == null &&
        !(_latestImportResult?.dryRun ?? false)) {
      return;
    }
    setState(() {
      _activePreviewToken = null;
      if (_latestImportResult?.dryRun ?? false) {
        _latestImportResult = null;
      }
    });
  }

  Future<void> _loadReconciliation() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final response = await _api.adminShamellPayReconciliation(
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

  Future<void> _submitShamellPayReportImport({required bool dryRun}) async {
    final reportName = _reportNameController.text.trim();
    final reportBody = _reportBodyController.text.trim();
    final note = _noteController.text.trim();
    if (reportName.isEmpty) {
      setState(() {
        _errorMessage = 'Report name required.';
      });
      return;
    }
    if (reportBody.isEmpty || reportBody == _reportTemplateHeader.trim()) {
      setState(() {
        _errorMessage = 'Paste a SyrChat Pay CSV report before continuing.';
      });
      return;
    }
    if (!dryRun && (_activePreviewToken ?? '').trim().isEmpty) {
      setState(() {
        _errorMessage = 'Run preview before applying the SyrChat Pay report.';
      });
      return;
    }
    setState(() {
      _importingReport = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final result = await _api.createAdminShamellPayReportImport(
        reportName: reportName,
        reportBody: reportBody,
        expectedPreviewToken: dryRun ? null : _activePreviewToken,
        dryRun: dryRun,
        note: note.isEmpty ? null : note,
      );
      setState(() {
        _latestImportResult = result;
        _activePreviewToken = dryRun ? result.previewEcho?.previewToken : null;
      });
      if (!dryRun) {
        await _loadReconciliation();
      }
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _importingReport = false;
      });
    }
  }

  Future<void> _openRunDetail(CoachAdminShamellPayReconciliationRun run) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: _CoachAdminShamellPayReconciliationRunSheet(run: run),
        );
      },
    );
  }

  bool _canReleaseOperatorRail(CoachAdminShamellPayReconciliationRun run) {
    if (run.shamellPayStatus != 'executed') {
      return false;
    }
    return run.downstreamStatus == 'not_reported' ||
        run.downstreamStatus == 'failed';
  }

  bool _canConfirmOperatorRail(CoachAdminShamellPayReconciliationRun run) {
    return run.reconciliationStatus == 'operator_rail_pending' &&
        run.downstreamStatus == 'pending';
  }

  bool _canFailOperatorRail(CoachAdminShamellPayReconciliationRun run) {
    return run.reconciliationStatus == 'operator_rail_pending' &&
        run.downstreamStatus == 'pending';
  }

  Future<void> _releaseOperatorRail(
    CoachAdminShamellPayReconciliationRun run,
  ) async {
    setState(() {
      _releasingOperatorRailRunIds.add(run.payoutRunId);
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final result = await _api.releaseAdminShamellPayOperatorRail(
        payoutRunId: run.payoutRunId,
        note: 'Released from SyrChat Pay reconciliation.',
      );
      await _loadReconciliation();
      setState(() {
        _successMessage = result.nextAction;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _releasingOperatorRailRunIds.remove(run.payoutRunId);
      });
    }
  }

  Future<void> _confirmOperatorRail(
    CoachAdminShamellPayReconciliationRun run,
  ) async {
    setState(() {
      _confirmingOperatorRailRunIds.add(run.payoutRunId);
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final result = await _api.confirmAdminShamellPayOperatorRail(
        payoutRunId: run.payoutRunId,
        note: 'Confirmed from SyrChat Pay reconciliation.',
      );
      await _loadReconciliation();
      setState(() {
        _successMessage = result.nextAction;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _confirmingOperatorRailRunIds.remove(run.payoutRunId);
      });
    }
  }

  Future<void> _failOperatorRail(
    CoachAdminShamellPayReconciliationRun run,
  ) async {
    setState(() {
      _failingOperatorRailRunIds.add(run.payoutRunId);
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final result = await _api.failAdminShamellPayOperatorRail(
        payoutRunId: run.payoutRunId,
        note: 'Marked failed from SyrChat Pay reconciliation.',
      );
      await _loadReconciliation();
      setState(() {
        _successMessage = result.nextAction;
      });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _failingOperatorRailRunIds.remove(run.payoutRunId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SyrChat Pay reconciliation'),
        actions: [
          IconButton(
            onPressed: _importingReport
                ? null
                : () {
                    setState(() {
                      _showImportComposer = !_showImportComposer;
                    });
                  },
            icon: Icon(
              _showImportComposer
                  ? Icons.upload_file_outlined
                  : Icons.playlist_add_outlined,
            ),
            tooltip:
                _showImportComposer ? 'Hide report import' : 'Import report',
          ),
          IconButton(
            onPressed: _loading ? null : _loadReconciliation,
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
    final filteredRuns = response == null
        ? const <CoachAdminShamellPayReconciliationRun>[]
        : response.runs
            .where((run) => _coachShamellPayMatchesQueue(run, _selectedQueue))
            .toList(growable: false);
    final visibleRuns = _coachShamellPaySortedRuns(
      filteredRuns,
      _selectedSort,
    );
    return RefreshIndicator(
      onRefresh: _loadReconciliation,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search reconciliation',
                    hintText: 'Run, statement, operator, import',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadReconciliation(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _loading ? null : _loadReconciliation,
                child: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_errorMessage != null) ...[
            StatusBanner.error(_errorMessage!),
            const SizedBox(height: 12),
          ],
          if (_successMessage != null) ...[
            StatusBanner.success(_successMessage!),
            const SizedBox(height: 12),
          ],
          if ((response?.summary.escalatedRuns ?? 0) > 0) ...[
            StatusBanner.warning(
              _coachShamellPayEscalationBannerLabel(
                response!.summary.escalatedRuns,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_showImportComposer) ...[
            _buildImportComposer(context),
            const SizedBox(height: 12),
          ],
          if (_latestImportResult != null) ...[
            _buildLatestImportResultCard(context, _latestImportResult!),
            const SizedBox(height: 12),
          ],
          if (response == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No SyrChat Pay reconciliation loaded yet.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _loadReconciliation,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Load reconciliation'),
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
                    Color(0xFFFFFBF5),
                    Color(0xFFFFF3DF),
                    Color(0xFFFDE5C7),
                  ],
                ),
                border: Border.all(color: const Color(0xFFECD3AE)),
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
                      border: Border.all(color: const Color(0xFFECD3AE)),
                    ),
                    child: Text(
                      'Coach admin payout bridge',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: const Color(0xFFB45309),
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'SyrChat Pay command desk',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xFF431407),
                          fontWeight: FontWeight.w900,
                          height: .96,
                        ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Text(
                      'Resolve bridge gaps between SyrChat Pay settlement, operator rail execution, and payout reconciliation from one desk. Start with escalations and pending rail handoffs before moving back to clean reconciled runs.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF7C5A2A),
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
                      const _CoachShamellPayHeaderBadge(
                        icon: Icons.public_outlined,
                        label: 'Scope: Coach admin',
                      ),
                      _CoachShamellPayHeaderBadge(
                        icon: Icons.priority_high_outlined,
                        label: 'Attention ${response.summary.attentionRuns}',
                        color: const Color(0xFFB91C1C),
                      ),
                      _CoachShamellPayHeaderBadge(
                        icon: Icons.warning_amber_outlined,
                        label: 'Escalated ${response.summary.escalatedRuns}',
                        color: const Color(0xFFB45309),
                      ),
                      _CoachShamellPayHeaderBadge(
                        icon: Icons.account_balance_outlined,
                        label:
                            'Rail pending ${response.summary.operatorRailPendingRuns}',
                        color: const Color(0xFF1D4ED8),
                      ),
                      _CoachShamellPayHeaderBadge(
                        icon: Icons.update_outlined,
                        label:
                            'Updated ${_coachShamellPayIsoLabel(response.generatedAtIso)}',
                        color: const Color(0xFF526176),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Focus queues',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF431407),
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
                        'escalated',
                        'awaiting_shamell_pay',
                        'operator_rail_pending',
                        'failed',
                        'status_mismatch',
                      ])
                        _CoachShamellPayFocusCard(
                          key: ValueKey('coachShamellPayFocus_$queue'),
                          icon: switch (queue) {
                            'attention' => Icons.priority_high_outlined,
                            'escalated' => Icons.warning_amber_outlined,
                            'awaiting_shamell_pay' => Icons.pending_outlined,
                            'operator_rail_pending' =>
                              Icons.account_balance_outlined,
                            'failed' => Icons.error_outline,
                            'status_mismatch' => Icons.sync_problem_outlined,
                            _ => Icons.list_alt_outlined,
                          },
                          label: _coachShamellPayQueueLabel(queue),
                          value:
                              '${_coachShamellPayQueueCount(response.runs, queue)}',
                          detail: switch (queue) {
                            'attention' =>
                              'Runs that still need manual payout bridge follow-up',
                            'escalated' =>
                              'Repeated operator rail failures before the next retry',
                            'awaiting_shamell_pay' =>
                              'Runs still missing the latest SyrChat Pay signal',
                            'operator_rail_pending' =>
                              'SyrChat Pay is ahead of the downstream payout rail',
                            'failed' =>
                              'Operator rail failures that need retry or escalation',
                            'status_mismatch' =>
                              'Status disagreement between settlement and rail state',
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
              'Updated ${_coachShamellPayIsoLabel(response.generatedAtIso)}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('Runs ${response.summary.totalRuns}'),
                ),
                Chip(
                  label: Text('Reconciled ${response.summary.reconciledRuns}'),
                ),
                Chip(
                  label: Text(
                    'Awaiting SyrChat Pay '
                    '${response.summary.awaitingShamellPayRuns}',
                  ),
                ),
                Chip(
                  label: Text(
                    'Operator rail pending '
                    '${response.summary.operatorRailPendingRuns}',
                  ),
                ),
                if (response.summary.escalatedRuns > 0)
                  Chip(
                    label: Text('Escalated ${response.summary.escalatedRuns}'),
                  ),
                if (response.summary.statusMismatchRuns > 0)
                  Chip(
                    label: Text(
                      'Status mismatch ${response.summary.statusMismatchRuns}',
                    ),
                  ),
                Chip(
                  label: Text('Attention ${response.summary.attentionRuns}'),
                ),
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
                      'Bridge balances',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Expected net payable '
                      '${_coachShamellPaySignedMoneyLabel(response.summary.currency, response.summary.expectedNetPayableMinorUnits)}',
                    ),
                    Text(
                      'Reconciled net payable '
                      '${_coachShamellPaySignedMoneyLabel(response.summary.currency, response.summary.reconciledNetPayableMinorUnits)}',
                    ),
                    Text(
                      'Attention net payable '
                      '${_coachShamellPaySignedMoneyLabel(response.summary.currency, response.summary.attentionNetPayableMinorUnits)}',
                    ),
                    Text(
                      'SyrChat Pay clearing '
                      '${_coachShamellPaySignedMoneyLabel(response.summary.currency, response.summary.shamellPayClearingMinorUnits)}',
                    ),
                    Text(
                      'Settlement in transit '
                      '${_coachShamellPaySignedMoneyLabel(response.summary.currency, response.summary.settlementInTransitMinorUnits)}',
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
                  'escalated',
                  'awaiting_shamell_pay',
                  'operator_rail_pending',
                  'failed',
                  'status_mismatch',
                ])
                  ChoiceChip(
                    label: Text(
                      '${_coachShamellPayQueueLabel(queue)} (${_coachShamellPayQueueCount(response.runs, queue)})',
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
              'Showing ${visibleRuns.length} of ${response.runs.length} runs',
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
                  'retries',
                ])
                  ChoiceChip(
                    label: Text(_coachShamellPaySortLabel(sort)),
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
            if (visibleRuns.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No SyrChat Pay runs match the current search and queue.',
                  ),
                ),
              )
            else
              for (final run in visibleRuns) ...[
                Builder(
                  builder: (context) {
                    final isReleasing =
                        _releasingOperatorRailRunIds.contains(run.payoutRunId);
                    final isConfirming =
                        _confirmingOperatorRailRunIds.contains(run.payoutRunId);
                    final isFailing =
                        _failingOperatorRailRunIds.contains(run.payoutRunId);
                    final canRelease = _canReleaseOperatorRail(run);
                    final canConfirm = _canConfirmOperatorRail(run);
                    final canFail = _canFailOperatorRail(run);
                    return Card(
                      key:
                          ValueKey('coachShamellPayRunCard_${run.payoutRunId}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () => _openRunDetail(run),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          _coachShamellPayStatusIcon(run),
                                          color: run.needsAttention
                                              ? Colors.redAccent
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                run.operatorNames.isEmpty
                                                    ? run.payoutRunId
                                                    : run.operatorNames.join(
                                                        ', ',
                                                      ),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                run.payoutRunId,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_coachShamellPayIsoLabel(run.occurredAtIso)}${run.statementIds.isEmpty ? '' : ' • ${run.statementIds.length} statement${run.statementIds.length == 1 ? '' : 's'}'}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _coachShamellPayMoneyLabel(
                                                run.currency,
                                                run.expectedNetPayableMinorUnits,
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              _coachShamellPayStatusLabel(
                                                run.runStatus,
                                              ).toUpperCase(),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
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
                                        _CoachShamellPayRunBadge(
                                          label: _coachShamellPayStatusLabel(
                                            run.reconciliationStatus,
                                          ),
                                          color: _coachShamellPayBadgeColor(
                                            run.reconciliationStatus,
                                          ),
                                        ),
                                        if (run.needsAttention)
                                          const _CoachShamellPayRunBadge(
                                            label: 'Needs attention',
                                            color: Colors.redAccent,
                                          ),
                                        if (run.escalated)
                                          const _CoachShamellPayRunBadge(
                                            label: 'Escalated',
                                            color: Color(0xFFB45309),
                                          ),
                                        _CoachShamellPayRunBadge(
                                          label:
                                              'SyrChat Pay ${_coachShamellPayStatusLabel(run.shamellPayStatus)}',
                                          color: _coachShamellPayBadgeColor(
                                            run.shamellPayStatus,
                                          ),
                                        ),
                                        _CoachShamellPayRunBadge(
                                          label:
                                              'Operator rail ${_coachShamellPayStatusLabel(run.downstreamStatus)}',
                                          color: _coachShamellPayBadgeColor(
                                            run.downstreamStatus,
                                          ),
                                        ),
                                        if (_coachShamellPayAttemptSummaryLabel(
                                              run,
                                            ) !=
                                            null)
                                          _CoachShamellPayRunBadge(
                                            label:
                                                _coachShamellPayAttemptSummaryLabel(
                                              run,
                                            )!,
                                            color: const Color(0xFF526176),
                                          ),
                                        if (run.downstreamFailedAttemptCount >
                                            0)
                                          _CoachShamellPayRunBadge(
                                            label:
                                                '${run.downstreamFailedAttemptCount} failed',
                                            color: const Color(0xFFB91C1C),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: run.needsAttention
                                            ? const Color(0xFFFFF4F2)
                                            : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: run.needsAttention
                                              ? const Color(0xFFF3C7C1)
                                              : const Color(0xFFD8E1ED),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Next action',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(run.nextAction),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (canRelease ||
                                isReleasing ||
                                canConfirm ||
                                isConfirming ||
                                canFail ||
                                isFailing) ...[
                              const Divider(height: 20),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  if (canRelease || isReleasing)
                                    FilledButton.icon(
                                      onPressed: isReleasing
                                          ? null
                                          : () => _releaseOperatorRail(run),
                                      icon: isReleasing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.account_balance_outlined,
                                            ),
                                      label: Text(
                                        isReleasing
                                            ? 'Releasing operator rail...'
                                            : run.downstreamStatus == 'failed'
                                                ? 'Retry operator rail'
                                                : 'Release operator rail',
                                      ),
                                    ),
                                  if (canConfirm || isConfirming)
                                    OutlinedButton.icon(
                                      onPressed: isConfirming
                                          ? null
                                          : () => _confirmOperatorRail(run),
                                      icon: isConfirming
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.verified_outlined,
                                            ),
                                      label: Text(
                                        isConfirming
                                            ? 'Confirming operator rail...'
                                            : 'Confirm operator rail',
                                      ),
                                    ),
                                  if (canFail || isFailing)
                                    OutlinedButton.icon(
                                      onPressed: isFailing
                                          ? null
                                          : () => _failOperatorRail(run),
                                      icon: isFailing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.error_outline,
                                            ),
                                      label: Text(
                                        isFailing
                                            ? 'Marking operator rail failed...'
                                            : 'Mark operator rail failed',
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
          ],
        ],
      ),
    );
  }

  Widget _buildImportComposer(BuildContext context) {
    final activePreviewToken = (_activePreviewToken ?? '').trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import SyrChat Pay report',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Paste the SyrChat App payout export as CSV. Preview is required before apply.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reportNameController,
              decoration: const InputDecoration(
                labelText: 'Report name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Optional finance note',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reportBodyController,
              minLines: 8,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'CSV body',
                hintText:
                    'merchant_reference,psp_status,psp_reference,settlement_reference,booked_at,description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (activePreviewToken.isNotEmpty)
              Text(
                'Preview token active. Apply uses the latest preview snapshot.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (activePreviewToken.isNotEmpty) const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _importingReport
                      ? null
                      : () => _submitShamellPayReportImport(dryRun: true),
                  icon: _importingReport
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.preview_outlined),
                  label: const Text('Preview'),
                ),
                FilledButton.icon(
                  onPressed: _importingReport || activePreviewToken.isEmpty
                      ? null
                      : () => _submitShamellPayReportImport(dryRun: false),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestImportResultCard(
    BuildContext context,
    CoachOperatorPayoutImportBatchMutationResult result,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _coachShamellPayImportResultLabel(result),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(_coachShamellPayImportStateLabel(result))),
                Chip(label: Text('Rows ${result.batch.totalRows}')),
                Chip(label: Text('Applied ${result.batch.appliedRows}')),
                Chip(label: Text('Failed ${result.batch.failedRows}')),
              ],
            ),
            const SizedBox(height: 8),
            Text(result.batch.reportName),
            Text(
              'Generated ${_coachShamellPayIsoLabel(result.batch.createdAtIso)}',
            ),
            if (result.previewEcho != null) ...[
              const SizedBox(height: 8),
              Text(
                'Preview active until '
                '${_coachShamellPayIsoLabel(result.previewEcho!.expiresAtIso)}',
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Next action',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(result.nextAction),
            if (result.failedRows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Failed rows',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final failure in result.failedRows.take(3)) ...[
                Text(
                  'Line ${failure.lineNumber}'
                  '${failure.payoutRunId == null ? '' : ' • ${failure.payoutRunId}'}'
                  ' • ${failure.detail}',
                ),
                const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachShamellPayHeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoachShamellPayHeaderBadge({
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
        border: Border.all(color: const Color(0xFFECD3AE)),
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

class _CoachShamellPayFocusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  const _CoachShamellPayFocusCard({
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
                  ? const Color(0xFFFFE8CC)
                  : Colors.white.withValues(alpha: .76),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? const Color(0xFFEA9A3B)
                    : const Color(0xFFECD3AE),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? const Color(0xFFB45309)
                      : const Color(0xFF7C5A2A),
                ),
                const SizedBox(height: 14),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF431407),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF431407),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF7C5A2A),
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

class _CoachShamellPayRunBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _CoachShamellPayRunBadge({
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

class _CoachAdminShamellPayReconciliationRunSheet extends StatelessWidget {
  final CoachAdminShamellPayReconciliationRun run;

  const _CoachAdminShamellPayReconciliationRunSheet({
    required this.run,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          run.operatorNames.isEmpty
              ? run.payoutRunId
              : run.operatorNames.join(', '),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '${_coachShamellPayIsoLabel(run.occurredAtIso)} • '
          '${_coachShamellPayStatusLabel(run.reconciliationStatus)}',
        ),
        const SizedBox(height: 8),
        Text(
          _coachShamellPayMoneyLabel(
            run.currency,
            run.expectedNetPayableMinorUnits,
          ),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        _CoachAdminShamellPayImportTimelineCard(
          title: 'SyrChat Pay attempts',
          emptyLabel: 'No SyrChat Pay report attempts recorded yet.',
          imports: run.shamellPayAttempts,
        ),
        const SizedBox(height: 12),
        _CoachAdminShamellPayImportTimelineCard(
          title: 'Operator rail attempts',
          emptyLabel: 'No downstream operator rail attempts recorded yet.',
          imports: run.downstreamAttempts,
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
                Text('Payout ${run.payoutRunId}'),
                if (run.statementIds.isNotEmpty)
                  Text('Statements ${run.statementIds.join(', ')}'),
                if (run.operatorNames.isNotEmpty)
                  Text('Operators ${run.operatorNames.join(', ')}'),
                if (run.latestShamellPayImportId != null)
                  Text('SyrChat Pay import ${run.latestShamellPayImportId!}'),
                if (run.latestDownstreamImportId != null)
                  Text('Downstream import ${run.latestDownstreamImportId!}'),
                if (run.paymentReference != null)
                  Text('Payment reference ${run.paymentReference!}'),
                if (run.externalReference != null)
                  Text('External reference ${run.externalReference!}'),
              ],
            ),
          ),
        ),
        if (run.escalated) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Escalation',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_coachShamellPayStatusLabel(run.escalationSeverity ?? 'high')} severity',
                  ),
                  Text(
                    'Failed attempts ${run.downstreamFailedAttemptCount} of ${run.downstreamAttemptCount}',
                  ),
                  if (run.escalationReason != null) ...[
                    const SizedBox(height: 8),
                    Text(run.escalationReason!),
                  ],
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
                Text(
                  'Bridge status',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Run status ${_coachShamellPayStatusLabel(run.runStatus)}',
                ),
                Text(
                  'SyrChat Pay ${_coachShamellPayStatusLabel(run.shamellPayStatus)}',
                ),
                Text(
                  'Operator rail ${_coachShamellPayStatusLabel(run.downstreamStatus)}',
                ),
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
                  'Next action',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(run.nextAction),
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
                  'Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (run.detailLines.isEmpty)
                  const Text('No additional reconciliation details.')
                else
                  for (final line in run.detailLines) ...[
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

class _CoachAdminShamellPayImportTimelineCard extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<CoachOperatorPayoutImport> imports;

  const _CoachAdminShamellPayImportTimelineCard({
    required this.title,
    required this.emptyLabel,
    required this.imports,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (imports.isEmpty)
              Text(emptyLabel)
            else
              for (var index = 0; index < imports.length; index++) ...[
                _CoachAdminShamellPayImportTimelineRow(
                    importEntry: imports[index]),
                if (index < imports.length - 1) const Divider(height: 20),
              ],
          ],
        ),
      ),
    );
  }
}

class _CoachAdminShamellPayImportTimelineRow extends StatelessWidget {
  final CoachOperatorPayoutImport importEntry;

  const _CoachAdminShamellPayImportTimelineRow({
    required this.importEntry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_coachShamellPayIsoLabel(importEntry.importedAtIso)} • '
          '${_coachShamellPayStatusLabel(importEntry.externalStatus)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${_coachShamellPayImportSourceLabel(importEntry.importSource)} • '
          'Import ${importEntry.importId}',
        ),
        if (importEntry.paymentReference != null)
          Text('Payment reference ${importEntry.paymentReference!}'),
        if (importEntry.externalReference != null)
          Text('External reference ${importEntry.externalReference!}'),
        if (importEntry.note != null) Text(importEntry.note!),
      ],
    );
  }
}
