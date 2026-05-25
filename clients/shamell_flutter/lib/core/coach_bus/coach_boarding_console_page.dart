import 'dart:async';

import 'package:flutter/material.dart';

import '../account_privilege_store.dart';
import '../dashboard_policy_scope.dart';
import '../payments/payments_idempotency.dart';
import '../safe_set_state.dart';
import '../scan_page.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_boarding_offline_queue.dart';
import 'coach_crew_cockpit_page.dart';
import 'coach_mobility_api.dart';
import 'coach_ops_feature_widgets.dart';
import 'coach_platform_contracts.dart';

String _coachCrewIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

String _coachCrewBoardingStateLabel(CoachManifestBoardingState state) {
  switch (state) {
    case CoachManifestBoardingState.notBoarded:
      return 'Not boarded';
    case CoachManifestBoardingState.boarded:
      return 'Boarded';
    case CoachManifestBoardingState.denied:
      return 'Denied';
    case CoachManifestBoardingState.duplicateAttempt:
      return 'Duplicate attempt';
    case CoachManifestBoardingState.revoked:
      return 'Revoked';
    case CoachManifestBoardingState.noShow:
      return 'No-show';
  }
}

String _coachCrewScanStatusLabel(CoachBoardingScanStatus status) {
  switch (status) {
    case CoachBoardingScanStatus.scanned:
      return 'Scanned';
    case CoachBoardingScanStatus.denied:
      return 'Denied';
    case CoachBoardingScanStatus.duplicate:
      return 'Duplicate';
    case CoachBoardingScanStatus.revoked:
      return 'Revoked';
    case CoachBoardingScanStatus.noShow:
      return 'No-show';
  }
}

String _coachCrewEpochLabel(int epochMs) {
  if (epochMs <= 0) return '-';
  return _coachCrewIsoLabel(
    DateTime.fromMillisecondsSinceEpoch(epochMs).toUtc().toIso8601String(),
  );
}

String _coachBoardingManifestQueueLabel(String queue) {
  switch (queue) {
    case 'pending':
      return 'Pending';
    case 'boarded':
      return 'Boarded';
    case 'attention':
      return 'Attention';
    default:
      return 'All';
  }
}

class CoachBoardingConsolePage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final Future<int> Function(String baseUrl)? pendingScanFlusher;
  final ShamellDashboardPolicy? dashboardPolicyOverride;
  final AccountPrivilegeSnapshot? privilegeSnapshotOverride;
  final Future<String?> Function(BuildContext context)? scanLauncher;
  final CoachCrewDepartureBoardResponse? initialDepartureBoard;
  final CoachCrewManifestResponse? initialManifest;

  const CoachBoardingConsolePage({
    super.key,
    required this.baseUrl,
    this.api,
    this.pendingScanFlusher,
    this.dashboardPolicyOverride,
    this.privilegeSnapshotOverride,
    this.scanLauncher,
    this.initialDepartureBoard,
    this.initialManifest,
  });

  @override
  State<CoachBoardingConsolePage> createState() =>
      _CoachBoardingConsolePageState();
}

class _CoachBoardingConsolePageState extends State<CoachBoardingConsolePage>
    with SafeSetStateMixin<CoachBoardingConsolePage>, WidgetsBindingObserver {
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _departuresSectionKey = GlobalKey(
    debugLabel: 'coachBoardingDeparturesSection',
  );
  final GlobalKey _manifestFiltersSectionKey = GlobalKey(
    debugLabel: 'coachBoardingManifestFiltersSection',
  );
  final GlobalKey _manifestSectionKey = GlobalKey(
    debugLabel: 'coachBoardingManifestSection',
  );
  final GlobalKey _recentEventsSectionKey = GlobalKey(
    debugLabel: 'coachBoardingRecentEventsSection',
  );
  final GlobalKey _offlineQueueSectionKey = GlobalKey(
    debugLabel: 'coachBoardingOfflineQueueSection',
  );

  bool _loadingPrivileges = true;
  bool _accessAllowed = false;
  bool _loadingBoard = false;
  bool _loadingManifest = false;
  bool _scanning = false;
  bool _syncingPendingScans = false;
  bool _trainingMode = false;
  String? _errorMessage;
  String? _generatedAtIso;
  String? _selectedTripId;
  List<CoachCrewTripSummary> _departures = const <CoachCrewTripSummary>[];
  List<CoachOfflineBoardingScan> _pendingBoardingScans =
      const <CoachOfflineBoardingScan>[];
  CoachCrewManifestResponse? _manifest;
  final Set<String> _recordingTicketIds = <String>{};
  final TextEditingController _manifestSearchController =
      TextEditingController();
  String _selectedManifestQueue = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadPrivilegesAndBoard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manifestSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !mounted || !_accessAllowed) {
      return;
    }
    unawaited(_maybeAutoSyncPendingBoardingScans());
  }

  Future<void> _loadPrivilegesAndBoard() async {
    final policy = await shamellResolveDashboardPolicy(
      context,
      baseUrl: widget.baseUrl,
      policyOverride: widget.dashboardPolicyOverride,
      privilegeSnapshotOverride: widget.privilegeSnapshotOverride,
    );
    final snapshot = policy.privilegeSnapshot;
    if (!mounted) return;
    setState(() {
      _accessAllowed = shamellDashboardAllowsCoachBoardingSnapshot(snapshot);
      _loadingPrivileges = false;
    });
    if (_accessAllowed &&
        widget.initialDepartureBoard != null &&
        widget.initialManifest != null) {
      await _refreshPendingBoardingScans();
      setState(() {
        _generatedAtIso = widget.initialDepartureBoard!.generatedAtIso;
        _departures = widget.initialDepartureBoard!.departures;
        _selectedTripId = widget.initialManifest!.trip.tripId;
        _manifest = widget.initialManifest;
      });
      return;
    }
    if (_accessAllowed) {
      await _maybeAutoSyncPendingBoardingScans(reloadManifest: false);
      await _loadDepartureBoard(selectFirstTrip: true);
    }
  }

  Future<void> _scrollToSection(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) {
      return;
    }
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.06,
    );
  }

  Future<void> _refreshPendingBoardingScans() async {
    final scans = await loadPendingCoachBoardingScans(baseUrl: widget.baseUrl);
    if (!mounted) return;
    setState(() {
      _pendingBoardingScans = scans;
    });
  }

  Iterable<CoachOfflineBoardingScan> get _selectedTripPendingScans {
    final tripId = _selectedTripId;
    if (tripId == null || tripId.isEmpty) {
      return const <CoachOfflineBoardingScan>[];
    }
    return _pendingBoardingScans.where((scan) => scan.tripId == tripId);
  }

  CoachOfflineBoardingScan? _pendingScanForTicket(String ticketId) {
    for (final scan in _selectedTripPendingScans) {
      if (scan.ticketId == ticketId) {
        return scan;
      }
    }
    return null;
  }

  bool _entryNeedsAttention(CoachCrewManifestEntry entry) {
    return entry.needsAttention ||
        entry.boardingState == CoachManifestBoardingState.denied ||
        entry.boardingState == CoachManifestBoardingState.duplicateAttempt ||
        entry.boardingState == CoachManifestBoardingState.revoked ||
        entry.boardingState == CoachManifestBoardingState.noShow;
  }

  bool _matchesManifestQueue(CoachCrewManifestEntry entry, String queue) {
    switch (queue) {
      case 'pending':
        return entry.boardingState == CoachManifestBoardingState.notBoarded;
      case 'boarded':
        return entry.boardingState == CoachManifestBoardingState.boarded;
      case 'attention':
        return _entryNeedsAttention(entry);
      default:
        return true;
    }
  }

  bool _matchesManifestSearch(CoachCrewManifestEntry entry, String query) {
    if (query.isEmpty) return true;
    final normalizedQuery = query.toLowerCase();
    final displayName = entry.passenger.displayName.toLowerCase();
    final ticketId = entry.ticket.ticketId.toLowerCase();
    final seatNumber = entry.seatNumber.toLowerCase();
    final operatorRef =
        (entry.ticket.operatorTicketReference ?? '').toLowerCase();
    final boardingState =
        _coachCrewBoardingStateLabel(entry.boardingState).toLowerCase();
    return displayName.contains(normalizedQuery) ||
        ticketId.contains(normalizedQuery) ||
        seatNumber.contains(normalizedQuery) ||
        operatorRef.contains(normalizedQuery) ||
        boardingState.contains(normalizedQuery);
  }

  int _manifestQueueCount(
    List<CoachCrewManifestEntry> entries,
    String queue,
  ) {
    return entries.where((entry) => _matchesManifestQueue(entry, queue)).length;
  }

  Future<void> _maybeAutoSyncPendingBoardingScans({
    bool reloadManifest = true,
  }) async {
    await _refreshPendingBoardingScans();
    if (_pendingBoardingScans.isEmpty || _syncingPendingScans) {
      return;
    }
    await _syncPendingBoardingScans(
      silent: true,
      reloadManifest: reloadManifest,
    );
  }

  Future<void> _syncPendingBoardingScans({
    bool silent = false,
    bool reloadManifest = true,
  }) async {
    if (_syncingPendingScans) return;
    setState(() {
      _syncingPendingScans = true;
      if (!silent) {
        _errorMessage = null;
      }
    });
    try {
      final delivered =
          await (widget.pendingScanFlusher?.call(widget.baseUrl) ??
              flushPendingCoachBoardingScans(baseUrl: widget.baseUrl));
      await _refreshPendingBoardingScans();
      final selectedTripId = _selectedTripId;
      if (reloadManifest &&
          selectedTripId != null &&
          selectedTripId.isNotEmpty) {
        await _loadManifest(selectedTripId);
      }
      if (!mounted) return;
      if (delivered > 0) {
        setState(() {
          _errorMessage = null;
        });
      }
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              delivered > 0
                  ? 'Synced $delivered queued boarding scans.'
                  : 'No queued boarding scans were delivered yet.',
            ),
          ),
        );
      }
    } on CoachApiException catch (error) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _errorMessage = error.detail;
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        setState(() {
          _errorMessage = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncingPendingScans = false;
        });
      }
    }
  }

  Future<void> _refreshConsole() async {
    await _maybeAutoSyncPendingBoardingScans(reloadManifest: false);
    await _loadDepartureBoard();
  }

  Future<void> _loadDepartureBoard({bool selectFirstTrip = false}) async {
    setState(() {
      _loadingBoard = true;
      _errorMessage = null;
    });
    try {
      final board = await _api.crewDepartures(limit: 12);
      if (!mounted) return;
      final selectedTripId = _selectedTripId ??
          (selectFirstTrip && board.departures.isNotEmpty
              ? board.departures.first.tripId
              : null);
      setState(() {
        _generatedAtIso = board.generatedAtIso;
        _departures = board.departures;
        _selectedTripId = selectedTripId;
        _loadingBoard = false;
      });
      if (selectedTripId != null) {
        await _loadManifest(selectedTripId);
      }
    } on CoachApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.detail;
        _loadingBoard = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loadingBoard = false;
      });
    }
  }

  Future<void> _loadManifest(String tripId) async {
    setState(() {
      _loadingManifest = true;
      _selectedTripId = tripId;
      _errorMessage = null;
    });
    try {
      final manifest = await _api.getCrewManifest(tripId);
      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _loadingManifest = false;
      });
    } on CoachApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.detail;
        _loadingManifest = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loadingManifest = false;
      });
    }
  }

  Future<void> _recordBoarding(
    CoachCrewManifestEntry entry,
    CoachBoardingScanStatus scanStatus, {
    bool offlineCaptured = false,
    String? note,
  }) async {
    final tripId = _selectedTripId;
    if (tripId == null || tripId.isEmpty) return;
    if (_trainingMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Training mode: ${entry.ticket.ticketId} would be marked ${_coachCrewScanStatusLabel(scanStatus).toLowerCase()}.',
          ),
        ),
      );
      return;
    }
    final idempotencyKey = newPaymentsIdempotencyKey('coach-crew-boarding');
    setState(() {
      _recordingTicketIds.add(entry.ticket.ticketId);
    });
    try {
      final result = await _api.recordBoarding(
        tripId: tripId,
        ticketId: entry.ticket.ticketId,
        scanStatus: scanStatus,
        offlineCaptured: offlineCaptured,
        deviceId: 'coach_crew_console',
        note: note,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return;
      setState(() {
        _departures = _departures
            .map((trip) =>
                trip.tripId == result.trip.tripId ? result.trip : trip)
            .toList(growable: false);
        if (_manifest != null) {
          _manifest = CoachCrewManifestResponse(
            trip: result.trip,
            manifest: _manifest!.manifest
                .map(
                  (value) => value.ticket.ticketId ==
                          result.manifestEntry.ticket.ticketId
                      ? result.manifestEntry
                      : value,
                )
                .toList(growable: false),
            recentEvents: result.recentEvents,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ticket ${entry.ticket.ticketId} marked ${_coachCrewScanStatusLabel(result.boardingEvent.scanStatus).toLowerCase()}.',
          ),
        ),
      );
    } on CoachApiException catch (error) {
      if (error.statusCode != null && error.statusCode! < 500) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.detail)),
        );
      } else {
        await _queueOfflineBoardingScan(
          tripId: tripId,
          entry: entry,
          scanStatus: scanStatus,
          note: note,
          idempotencyKey: idempotencyKey,
          fallbackMessage: error.detail,
        );
      }
    } catch (error) {
      await _queueOfflineBoardingScan(
        tripId: tripId,
        entry: entry,
        scanStatus: scanStatus,
        note: note,
        idempotencyKey: idempotencyKey,
        fallbackMessage: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _recordingTicketIds.remove(entry.ticket.ticketId);
        });
      }
    }
  }

  Future<void> _queueOfflineBoardingScan({
    required String tripId,
    required CoachCrewManifestEntry entry,
    required CoachBoardingScanStatus scanStatus,
    required String idempotencyKey,
    required String fallbackMessage,
    String? note,
  }) async {
    final alreadyQueued = _selectedTripPendingScans.any(
      (scan) =>
          scan.ticketId == entry.ticket.ticketId &&
          scan.scanStatus == scanStatus,
    );
    if (!alreadyQueued) {
      await enqueuePendingCoachBoardingScan(
        baseUrl: widget.baseUrl,
        tripId: tripId,
        ticketId: entry.ticket.ticketId,
        scanStatus: scanStatus,
        offlineCaptured: true,
        deviceId: 'coach_crew_console',
        note: note,
        idempotencyKey: idempotencyKey,
      );
      await _refreshPendingBoardingScans();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          alreadyQueued
              ? 'Ticket ${entry.ticket.ticketId} is already queued for sync.'
              : 'Boarding saved offline for ${entry.ticket.ticketId}. Sync when the network is back.',
        ),
      ),
    );
    if (fallbackMessage.trim().isNotEmpty) {
      setState(() {
        _errorMessage = fallbackMessage;
      });
    }
  }

  String? _normalizeScannedTicketId(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;
    if (normalized.contains('/tickets/')) {
      final ticketSegment = normalized.split('/tickets/').last;
      final ticketId = ticketSegment.split('/').first.trim();
      if (ticketId.isNotEmpty) return ticketId;
    }
    if (normalized.startsWith('ticket:')) {
      final ticketId = normalized.substring('ticket:'.length).trim();
      if (ticketId.isNotEmpty) return ticketId;
    }
    if (normalized.contains('ticket_id=')) {
      for (final part in normalized.split('|')) {
        final segments = part.split('=');
        if (segments.length == 2 && segments.first.trim() == 'ticket_id') {
          final ticketId = segments.last.trim();
          if (ticketId.isNotEmpty) return ticketId;
        }
      }
    }
    return normalized;
  }

  Future<void> _scanTicket() async {
    if (_selectedTripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a departure first.')),
      );
      return;
    }
    setState(() {
      _scanning = true;
    });
    try {
      final raw = await (widget.scanLauncher?.call(context) ??
          Navigator.push<String?>(
            context,
            MaterialPageRoute(
              builder: (_) => const ScanPage(allowManualEntry: true),
            ),
          ));
      if (!mounted || raw == null) return;
      final ticketId = _normalizeScannedTicketId(raw);
      if (ticketId == null) return;
      final entry = _manifest?.manifest
          .where((value) => value.ticket.ticketId == ticketId)
          .cast<CoachCrewManifestEntry?>()
          .firstWhere((value) => value != null, orElse: () => null);
      if (entry == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket $ticketId is not on this manifest.')),
        );
        return;
      }
      await _recordBoarding(entry, CoachBoardingScanStatus.scanned);
    } finally {
      if (mounted) {
        setState(() {
          _scanning = false;
        });
      }
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(label)),
      ],
    );
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: child,
    );
  }

  Widget _buildStatusPill({
    required BuildContext context,
    required IconData icon,
    required String label,
    Color color = const Color(0xFF165B45),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatCard({
    required BuildContext context,
    required String label,
    required String value,
    required String detail,
    required IconData icon,
    Color accent = const Color(0xFF0F766E),
  }) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF17362B),
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleBoardingSection(
    BuildContext context, {
    required CoachCrewManifestResponse? manifest,
    required int manifestAttentionCount,
    required int recentExceptionCount,
  }) {
    final theme = Theme.of(context);
    final selectedTrip = manifest?.trip ??
        _departures.cast<CoachCrewTripSummary?>().firstWhere(
              (trip) => trip?.tripId == _selectedTripId,
              orElse: () => null,
            );
    final pendingCount = manifest == null
        ? (selectedTrip?.pendingCount ?? 0)
        : _manifestQueueCount(manifest.manifest, 'pending');
    final boardedCount = manifest == null
        ? (selectedTrip?.boardedCount ?? 0)
        : _manifestQueueCount(manifest.manifest, 'boarded');
    final attentionCount = manifestAttentionCount + recentExceptionCount;
    final routeLabel = selectedTrip == null
        ? 'No departure selected'
        : '${selectedTrip.from} -> ${selectedTrip.to}';
    final tripDetail = selectedTrip == null
        ? '${_departures.length} departures available today'
        : '${selectedTrip.gateLabel} · ${selectedTrip.vehicleLabel} · ${_coachCrewIsoLabel(selectedTrip.departureAtIso)}';

    return Container(
      key: const ValueKey('coachBoardingSimpleHome'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Boarding checklist',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$routeLabel · $tripDetail',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .72),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                key: const ValueKey('coachBoardingSimpleScanButton'),
                onPressed: (_scanning || _loadingBoard || _loadingManifest)
                    ? null
                    : _scanTicket,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(_scanning ? 'Scanning...' : 'Scan ticket'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_scrollToSection(
                  selectedTrip == null
                      ? _departuresSectionKey
                      : _manifestSectionKey,
                )),
                icon: Icon(
                  selectedTrip == null
                      ? Icons.departure_board_outlined
                      : Icons.list_alt_outlined,
                ),
                label: Text(
                  selectedTrip == null ? 'Choose departure' : 'Open manifest',
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    (_syncingPendingScans || _pendingBoardingScans.isEmpty)
                        ? null
                        : _syncPendingBoardingScans,
                icon: const Icon(Icons.sync),
                label: Text(
                  _pendingBoardingScans.isEmpty
                      ? 'Queue clear'
                      : 'Sync ${_pendingBoardingScans.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            key: const ValueKey('coachBoardingTrainingModeSwitch'),
            contentPadding: EdgeInsets.zero,
            value: _trainingMode,
            onChanged: (value) => setState(() => _trainingMode = value),
            title: const Text('Training mode'),
            subtitle: const Text(
                'Scans and manual boarding actions do not update live data.'),
            secondary: const Icon(Icons.school_outlined),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _CoachBoardingSimpleMetric(
                icon: Icons.people_outline,
                label: 'Pending',
                value: '$pendingCount',
                color: const Color(0xFF2563EB),
              ),
              _CoachBoardingSimpleMetric(
                icon: Icons.verified_outlined,
                label: 'Boarded',
                value: '$boardedCount',
                color: const Color(0xFF0F766E),
              ),
              _CoachBoardingSimpleMetric(
                icon: Icons.warning_amber_outlined,
                label: 'Attention',
                value: '$attentionCount',
                color: const Color(0xFFB45309),
              ),
              _CoachBoardingSimpleMetric(
                icon: Icons.cloud_upload_outlined,
                label: 'Offline',
                value: '${_selectedTripPendingScans.length}',
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _runBoardingIncidentPlaybook(CoachIncidentTemplate template) {
    switch (template.id) {
      case 'passenger_missing':
        setState(() {
          _selectedManifestQueue = 'pending';
        });
        unawaited(_scrollToSection(_manifestSectionKey));
        return;
      case 'invalid_qr':
        unawaited(_scanTicket());
        return;
      case 'duplicate_boarding':
        unawaited(_scrollToSection(_recentEventsSectionKey));
        return;
      default:
        unawaited(_scrollToSection(_departuresSectionKey));
    }
  }

  Widget _buildSmartBoardingRiskSection(
    BuildContext context, {
    required CoachCrewManifestResponse? manifest,
    required int manifestAttentionCount,
    required int recentExceptionCount,
  }) {
    final theme = Theme.of(context);
    final selectedTrip = manifest?.trip;
    final risks = <String>[
      if (selectedTrip == null) 'Select a departure before opening the gate.',
      if ((selectedTrip?.pendingCount ?? 0) > 0)
        '${selectedTrip!.pendingCount} passenger(s) still pending.',
      if (manifestAttentionCount > 0)
        '$manifestAttentionCount passenger(s) need boarding attention.',
      if (recentExceptionCount > 0)
        '$recentExceptionCount recent scan exception(s).',
      if (_selectedTripPendingScans.isNotEmpty)
        '${_selectedTripPendingScans.length} offline scan(s) still queued.',
    ];
    final clear = risks.isEmpty;
    return Container(
      key: const ValueKey('coachBoardingSmartRiskPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: clear ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: clear ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                clear ? Icons.verified_outlined : Icons.warning_amber_outlined,
                color:
                    clear ? const Color(0xFF0F766E) : const Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Smart boarding risk',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (clear)
            const Text('Selected departure is clear for boarding.')
          else
            for (final risk in risks) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.priority_high_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(risk)),
                ],
              ),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }

  CoachTimelinePanel _buildBoardingTimelinePanel(
    CoachCrewManifestResponse? manifest,
  ) {
    final selectedTrip = manifest?.trip ??
        _departures.cast<CoachCrewTripSummary?>().firstWhere(
              (trip) => trip?.tripId == _selectedTripId,
              orElse: () => null,
            );
    return CoachTimelinePanel(
      title: 'Trip timeline',
      events: <CoachTimelineEvent>[
        CoachTimelineEvent(
          icon: Icons.departure_board_outlined,
          title: 'Departure selected',
          detail: selectedTrip == null
              ? 'No departure selected yet.'
              : '${selectedTrip.from} -> ${selectedTrip.to}',
          timeLabel: selectedTrip == null
              ? '-'
              : _coachCrewIsoLabel(selectedTrip.departureAtIso),
          done: selectedTrip != null,
        ),
        CoachTimelineEvent(
          icon: Icons.door_front_door_outlined,
          title: 'Boarding window',
          detail: selectedTrip == null
              ? 'Window appears after departure selection.'
              : '${_coachCrewIsoLabel(selectedTrip.boardingOpensAtIso)} to ${_coachCrewIsoLabel(selectedTrip.boardingClosesAtIso)}',
          timeLabel: selectedTrip == null
              ? '-'
              : _coachCrewIsoLabel(selectedTrip.boardingOpensAtIso),
          done: selectedTrip != null,
        ),
        CoachTimelineEvent(
          icon: Icons.people_outline,
          title: 'Manifest loaded',
          detail: manifest == null
              ? 'Select a departure to load passengers.'
              : '${manifest.manifest.length} passenger(s) loaded.',
          timeLabel: _generatedAtIso == null
              ? '-'
              : _coachCrewIsoLabel(_generatedAtIso!),
          done: manifest != null,
        ),
        CoachTimelineEvent(
          icon: Icons.qr_code_scanner,
          title: 'Boarding progress',
          detail: selectedTrip == null
              ? 'Scan starts after manifest load.'
              : '${selectedTrip.boardedCount}/${selectedTrip.manifestCount} boarded.',
          timeLabel:
              selectedTrip == null ? '-' : '${selectedTrip.boardedCount}',
          done: (selectedTrip?.boardedCount ?? 0) > 0,
        ),
      ],
    );
  }

  Color _seatStateColor(CoachCrewManifestEntry entry) {
    if (entry.needsAttention ||
        entry.boardingState == CoachManifestBoardingState.denied ||
        entry.boardingState == CoachManifestBoardingState.duplicateAttempt ||
        entry.boardingState == CoachManifestBoardingState.revoked ||
        entry.boardingState == CoachManifestBoardingState.noShow) {
      return const Color(0xFFB45309);
    }
    if (entry.boardingState == CoachManifestBoardingState.boarded) {
      return const Color(0xFF0F766E);
    }
    return const Color(0xFF2563EB);
  }

  IconData _seatStateIcon(CoachCrewManifestEntry entry) {
    if (entry.needsAttention ||
        entry.boardingState == CoachManifestBoardingState.denied ||
        entry.boardingState == CoachManifestBoardingState.duplicateAttempt ||
        entry.boardingState == CoachManifestBoardingState.revoked ||
        entry.boardingState == CoachManifestBoardingState.noShow) {
      return Icons.warning_amber_outlined;
    }
    if (entry.boardingState == CoachManifestBoardingState.boarded) {
      return Icons.verified_outlined;
    }
    return Icons.event_seat_outlined;
  }

  String _seatStateLabel(CoachCrewManifestEntry entry) {
    if (entry.needsAttention ||
        entry.boardingState == CoachManifestBoardingState.denied ||
        entry.boardingState == CoachManifestBoardingState.duplicateAttempt ||
        entry.boardingState == CoachManifestBoardingState.revoked ||
        entry.boardingState == CoachManifestBoardingState.noShow) {
      return 'Attention';
    }
    if (entry.boardingState == CoachManifestBoardingState.boarded) {
      return 'Boarded';
    }
    return 'Pending';
  }

  List<CoachSeatStatus> _buildSeatStatuses(
    CoachCrewManifestResponse? manifest,
  ) {
    if (manifest == null) {
      return const <CoachSeatStatus>[];
    }
    return manifest.manifest
        .map(
          (entry) => CoachSeatStatus(
            seatLabel: entry.seatNumber,
            passengerLabel: entry.passenger.displayName,
            statusLabel: _seatStateLabel(entry),
            color: _seatStateColor(entry),
            icon: _seatStateIcon(entry),
          ),
        )
        .toList(growable: false);
  }

  int _buildTripHealthScore({
    required CoachCrewManifestResponse? manifest,
    required int manifestAttentionCount,
    required int recentExceptionCount,
  }) {
    final selectedTrip = manifest?.trip;
    final pending = selectedTrip?.pendingCount ?? 0;
    final queued = _selectedTripPendingScans.length;
    final noShows = selectedTrip?.noShowCount ?? 0;
    final score = 100 -
        (pending * 4) -
        (manifestAttentionCount * 10) -
        (recentExceptionCount * 8) -
        (queued * 6) -
        (noShows * 5);
    return score.clamp(0, 100).toInt();
  }

  List<CoachTripHealthFactor> _buildTripHealthFactors({
    required CoachCrewManifestResponse? manifest,
    required int manifestAttentionCount,
    required int recentExceptionCount,
  }) {
    final selectedTrip = manifest?.trip;
    return <CoachTripHealthFactor>[
      CoachTripHealthFactor(
        icon: Icons.people_outline,
        label: 'Pending',
        value: '${selectedTrip?.pendingCount ?? 0}',
        healthy: (selectedTrip?.pendingCount ?? 0) == 0,
      ),
      CoachTripHealthFactor(
        icon: Icons.warning_amber_outlined,
        label: 'Exceptions',
        value: '$manifestAttentionCount',
        healthy: manifestAttentionCount == 0,
      ),
      CoachTripHealthFactor(
        icon: Icons.history_outlined,
        label: 'Recent scans',
        value: '$recentExceptionCount',
        healthy: recentExceptionCount == 0,
      ),
      CoachTripHealthFactor(
        icon: Icons.cloud_upload_outlined,
        label: 'Queued',
        value: '${_selectedTripPendingScans.length}',
        healthy: _selectedTripPendingScans.isEmpty,
      ),
    ];
  }

  List<CoachCloseoutMetric> _buildCloseoutMetrics(
    CoachCrewManifestResponse? manifest,
  ) {
    final selectedTrip = manifest?.trip;
    return <CoachCloseoutMetric>[
      CoachCloseoutMetric(
        label: 'Boarded',
        value: '${selectedTrip?.boardedCount ?? 0}',
      ),
      CoachCloseoutMetric(
        label: 'Pending',
        value: '${selectedTrip?.pendingCount ?? 0}',
      ),
      CoachCloseoutMetric(
        label: 'No-shows',
        value: '${selectedTrip?.noShowCount ?? 0}',
      ),
      CoachCloseoutMetric(
        label: 'Denied',
        value: '${selectedTrip?.deniedCount ?? 0}',
      ),
    ];
  }

  Widget _buildHeroPanel(CoachCrewManifestResponse? manifest) {
    final selectedTrip = manifest?.trip;
    final tripPendingCount = _selectedTripPendingScans.length;
    final boardedCount = selectedTrip?.boardedCount ?? 0;
    final deniedCount = selectedTrip?.deniedCount ?? 0;
    final noShowCount = selectedTrip?.noShowCount ?? 0;
    final pendingCount = selectedTrip?.pendingCount ?? 0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFF8FBF9),
            Color(0xFFEAF4EF),
            Color(0xFFD9EBE2),
          ],
        ),
        border: Border.all(color: const Color(0xFFD5E7DE)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12081F17),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFD8E8E0)),
            ),
            child: Text(
              'Crew boarding',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF165B45),
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Board the next departure fast',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF17362B),
                  fontWeight: FontWeight.w900,
                  height: .96,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            selectedTrip == null
                ? 'Select a departure, scan tickets, and resolve exceptions without leaving this console.'
                : 'Selected trip ${selectedTrip.from} -> ${selectedTrip.to}. Keep scanning moving and watch the exception counts before departure closes.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF50675E),
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildStatusPill(
                context: context,
                icon: Icons.departure_board_outlined,
                label: selectedTrip == null
                    ? 'No trip selected'
                    : 'Gate ${selectedTrip.gateLabel} · ${selectedTrip.vehicleLabel}',
              ),
              _buildStatusPill(
                context: context,
                icon: Icons.schedule_outlined,
                label: selectedTrip == null
                    ? 'Manifest loads per trip'
                    : 'Boarding closes ${_coachCrewIsoLabel(selectedTrip.boardingClosesAtIso)}',
                color: const Color(0xFF2563EB),
              ),
              _buildStatusPill(
                context: context,
                icon: _pendingBoardingScans.isEmpty
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
                label: _pendingBoardingScans.isEmpty
                    ? 'Queue clear'
                    : 'Offline queue: ${_pendingBoardingScans.length}',
                color: _pendingBoardingScans.isEmpty
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFC2410C),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildActionButton(
                icon: Icons.qr_code_scanner,
                label: _scanning ? 'Scanning…' : 'Scan ticket',
                onPressed: (_scanning || _loadingBoard || _loadingManifest)
                    ? null
                    : _scanTicket,
                primary: true,
              ),
              _buildActionButton(
                icon: Icons.sync,
                label: _syncingPendingScans
                    ? 'Syncing queue…'
                    : 'Sync queued scans',
                onPressed:
                    (_syncingPendingScans || _pendingBoardingScans.isEmpty)
                        ? null
                        : _syncPendingBoardingScans,
              ),
              _buildActionButton(
                icon: Icons.refresh,
                label: 'Refresh board',
                onPressed: _loadingBoard || _syncingPendingScans
                    ? null
                    : _refreshConsole,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Ready now',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF214739),
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildHeroStatCard(
                context: context,
                label: 'Pending',
                value: '$pendingCount',
                detail: 'Passengers still waiting to board',
                icon: Icons.people_outline,
                accent: const Color(0xFF2563EB),
              ),
              _buildHeroStatCard(
                context: context,
                label: 'Boarded',
                value: '$boardedCount',
                detail: 'Tickets already scanned successfully',
                icon: Icons.verified_outlined,
                accent: const Color(0xFF0F766E),
              ),
              _buildHeroStatCard(
                context: context,
                label: 'Exceptions',
                value: '${deniedCount + noShowCount}',
                detail: 'Denied plus no-show cases to resolve',
                icon: Icons.warning_amber_outlined,
                accent: const Color(0xFFC2410C),
              ),
              _buildHeroStatCard(
                context: context,
                label: 'Offline queue',
                value: '$tripPendingCount',
                detail: 'Queued scans for this selected trip',
                icon: Icons.cloud_upload_outlined,
                accent: const Color(0xFF7C3AED),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommandDeskSection(
    BuildContext context, {
    required CoachCrewManifestResponse? manifest,
    required int manifestAttentionCount,
    required int recentExceptionCount,
    required int tripPendingCount,
  }) {
    final theme = Theme.of(context);
    final selectedTrip = manifest?.trip;
    final pendingCount = selectedTrip?.pendingCount ?? 0;
    final departuresLoaded = _departures.length;
    final passengersLoaded = manifest?.manifest.length ?? 0;
    final attentionItems = <_CoachBoardingAttentionItemData>[
      if (selectedTrip != null && pendingCount > 0)
        _CoachBoardingAttentionItemData(
          icon: Icons.airline_seat_recline_normal_outlined,
          title: 'Passengers waiting to board',
          detail:
              '$pendingCount passengers are still pending on ${selectedTrip.from} -> ${selectedTrip.to} before boarding closes ${_coachCrewIsoLabel(selectedTrip.boardingClosesAtIso)}.',
        ),
      if (manifest != null && manifestAttentionCount > 0)
        _CoachBoardingAttentionItemData(
          icon: Icons.warning_amber_outlined,
          title: 'Boarding exceptions on manifest',
          detail:
              '$manifestAttentionCount passengers are flagged for denied, duplicate, revoked, no-show, or manual review handling.',
        ),
      if (recentExceptionCount > 0)
        _CoachBoardingAttentionItemData(
          icon: Icons.fact_check_outlined,
          title: 'Recent scan exceptions',
          detail:
              '$recentExceptionCount recent scan events ended in denied, duplicate, revoked, or no-show outcomes.',
        ),
      if (tripPendingCount > 0)
        _CoachBoardingAttentionItemData(
          icon: Icons.cloud_off_outlined,
          title: 'Queued offline scans',
          detail:
              '$tripPendingCount scans for the selected trip are still waiting for sync before the manifest fully catches up.',
        ),
    ];
    if (attentionItems.isEmpty) {
      attentionItems.add(
        const _CoachBoardingAttentionItemData(
          icon: Icons.task_alt_outlined,
          title: 'No immediate boarding escalations',
          detail:
              'The selected trip is clear right now. Keep the scanner moving and monitor the manifest for late exceptions.',
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Command desk',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              selectedTrip == null
                  ? 'Start by loading a departure, then work from boarding risk, recent scans, and the offline queue.'
                  : 'Start from boarding risk on the selected departure, then move through recent scans and any offline backlog.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CoachBoardingCommandMetricCard(
                  icon: Icons.departure_board_outlined,
                  label: 'Departures loaded',
                  value: '$departuresLoaded',
                ),
                _CoachBoardingCommandMetricCard(
                  icon: Icons.badge_outlined,
                  label: 'Passengers loaded',
                  value: '$passengersLoaded',
                ),
                _CoachBoardingCommandMetricCard(
                  icon: Icons.warning_amber_outlined,
                  label: 'Needs attention',
                  value: '$manifestAttentionCount',
                ),
                _CoachBoardingCommandMetricCard(
                  icon: Icons.fact_check_outlined,
                  label: 'Recent exceptions',
                  value: '$recentExceptionCount',
                ),
                _CoachBoardingCommandMetricCard(
                  icon: Icons.cloud_off_outlined,
                  label: 'Queued offline',
                  value: '$tripPendingCount',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Needs attention',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final item in attentionItems) ...[
              _CoachBoardingAttentionItem(item: item),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            Text(
              'Jump to workspace',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildActionButton(
                  icon: Icons.departure_board_outlined,
                  label: 'Review departures',
                  onPressed: () =>
                      unawaited(_scrollToSection(_departuresSectionKey)),
                ),
                if (manifest != null)
                  _buildActionButton(
                    icon: Icons.filter_alt_outlined,
                    label: 'Open manifest filters',
                    onPressed: () => unawaited(
                      _scrollToSection(_manifestFiltersSectionKey),
                    ),
                  ),
                if (manifest != null)
                  _buildActionButton(
                    icon: Icons.groups_outlined,
                    label: 'Open passenger manifest',
                    onPressed: () =>
                        unawaited(_scrollToSection(_manifestSectionKey)),
                    primary: true,
                  ),
                if (manifest != null)
                  _buildActionButton(
                    icon: Icons.history_outlined,
                    label: 'Review recent scans',
                    onPressed: () =>
                        unawaited(_scrollToSection(_recentEventsSectionKey)),
                  ),
                if (_selectedTripPendingScans.isNotEmpty)
                  _buildActionButton(
                    icon: Icons.cloud_off_outlined,
                    label: 'Open offline queue',
                    onPressed: () =>
                        unawaited(_scrollToSection(_offlineQueueSectionKey)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrivileges) {
      return Scaffold(
        appBar: AppBar(title: const Text('Coach boarding')),
        body: const ShamellSkeletonList(itemCount: 5),
      );
    }
    if (!_accessAllowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Coach boarding')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This account is not allowed to manage coach boarding.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final manifest = _manifest;
    final manifestSearchQuery =
        _manifestSearchController.text.trim().toLowerCase();
    final visibleManifest = manifest == null
        ? const <CoachCrewManifestEntry>[]
        : manifest.manifest
            .where(
                (entry) => _matchesManifestQueue(entry, _selectedManifestQueue))
            .where(
                (entry) => _matchesManifestSearch(entry, manifestSearchQuery))
            .toList(growable: false);
    final manifestAttentionCount = manifest == null
        ? 0
        : manifest.manifest.where(_entryNeedsAttention).length;
    final recentExceptionCount = manifest == null
        ? 0
        : manifest.recentEvents
            .where(
              (event) => event.scanStatus != CoachBoardingScanStatus.scanned,
            )
            .length;
    final selectedTrip = manifest?.trip ??
        _departures.cast<CoachCrewTripSummary?>().firstWhere(
              (trip) => trip?.tripId == _selectedTripId,
              orElse: () => null,
            );
    final selectedRouteLabel = selectedTrip == null
        ? 'No departure selected'
        : '${selectedTrip.from} -> ${selectedTrip.to}';
    final selectedSeatCapacity = () {
      final seats = _buildSeatStatuses(manifest);
      final manifestCapacity = selectedTrip?.manifestCount ?? seats.length;
      return manifestCapacity < seats.length ? seats.length : manifestCapacity;
    }();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach boarding'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _loadingBoard || _syncingPendingScans ? null : _refreshConsole,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sync queued scans',
            onPressed: (_syncingPendingScans || _pendingBoardingScans.isEmpty)
                ? null
                : _syncPendingBoardingScans,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Scan ticket',
            onPressed: (_scanning || _loadingBoard || _loadingManifest)
                ? null
                : _scanTicket,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          // Cycle 258 — quick switch to the streamlined Crew Cockpit
          // view. Same data but driver-first layout: "what's my next
          // trip" with a big scan button. Ops who like the dense
          // boarding console can stay here; drivers tap this.
          IconButton(
            tooltip: 'Crew cockpit',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      CoachCrewCockpitPage(baseUrl: widget.baseUrl),
                ),
              );
            },
            icon: const Icon(Icons.badge_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            if (_errorMessage != null) ...[
              StatusBanner.error(_errorMessage!),
              const SizedBox(height: 12),
            ],
            _buildSimpleBoardingSection(
              context,
              manifest: manifest,
              manifestAttentionCount: manifestAttentionCount,
              recentExceptionCount: recentExceptionCount,
            ),
            const SizedBox(height: 12),
            CoachShiftPanel(
              roleLabel: 'Boarding crew',
              assignedTrips: _departures.length,
              openTasks: (manifest?.trip.pendingCount ?? 0) +
                  manifestAttentionCount +
                  recentExceptionCount +
                  _selectedTripPendingScans.length,
              handoverHint: 'Gate, vehicle, exception, or offline queue note',
            ),
            const SizedBox(height: 12),
            _buildSmartBoardingRiskSection(
              context,
              manifest: manifest,
              manifestAttentionCount: manifestAttentionCount,
              recentExceptionCount: recentExceptionCount,
            ),
            const SizedBox(height: 12),
            CoachOfflineBoardingPanel(
              queuedScans: _selectedTripPendingScans.length,
              conflictCount: manifestAttentionCount + recentExceptionCount,
              liveSyncAvailable: !_syncingPendingScans,
              onSyncNow: (_syncingPendingScans || _pendingBoardingScans.isEmpty)
                  ? null
                  : _syncPendingBoardingScans,
            ),
            const SizedBox(height: 12),
            CoachTripHealthScorePanel(
              score: _buildTripHealthScore(
                manifest: manifest,
                manifestAttentionCount: manifestAttentionCount,
                recentExceptionCount: recentExceptionCount,
              ),
              tripLabel: selectedRouteLabel,
              factors: _buildTripHealthFactors(
                manifest: manifest,
                manifestAttentionCount: manifestAttentionCount,
                recentExceptionCount: recentExceptionCount,
              ),
            ),
            const SizedBox(height: 12),
            CoachSeatMapPanel(
              seats: _buildSeatStatuses(manifest),
              capacity: selectedSeatCapacity,
            ),
            const SizedBox(height: 12),
            CoachDriverAssignmentPanel(
              initialDriver: 'Assigned crew driver',
              initialVehicle: selectedTrip?.vehicleLabel ?? 'Unassigned bus',
              initialGate: selectedTrip?.gateLabel ?? 'Unassigned bay',
            ),
            const SizedBox(height: 12),
            CoachRecoveryFlowPanel(
              routeLabel: selectedRouteLabel,
              impactedPassengers: manifestAttentionCount +
                  recentExceptionCount +
                  (selectedTrip?.pendingCount ?? 0),
              rebookingOptions: <String>[
                if (selectedTrip != null)
                  '${selectedTrip.from} -> ${selectedTrip.to} next coach',
                'Same operator standby seat',
                'Any partner express service',
              ],
              compensationLabel: 'Delay voucher or refund credit',
            ),
            const SizedBox(height: 12),
            CoachPostTripCloseoutPanel(
              tripLabel: selectedRouteLabel,
              metrics: _buildCloseoutMetrics(manifest),
            ),
            const SizedBox(height: 12),
            CoachIncidentFlowPanel(
              onRunPlaybook: _runBoardingIncidentPlaybook,
            ),
            const SizedBox(height: 12),
            CoachPassengerNotificationPanel(
              impactedPassengers: manifest?.trip.manifestCount ??
                  _departures.fold<int>(
                    0,
                    (sum, trip) => sum + trip.manifestCount,
                  ),
              contextLabel: 'Boarding passengers',
            ),
            const SizedBox(height: 12),
            _buildBoardingTimelinePanel(manifest),
            const SizedBox(height: 12),
            _buildHeroPanel(manifest),
            const SizedBox(height: 12),
            _buildCommandDeskSection(
              context,
              manifest: manifest,
              manifestAttentionCount: manifestAttentionCount,
              recentExceptionCount: recentExceptionCount,
              tripPendingCount: _selectedTripPendingScans.length,
            ),
            const SizedBox(height: 12),
            StatusBanner.info(
              _generatedAtIso == null
                  ? 'Crew manifest data loads per trip and keeps boarding separate from ticketing.'
                  : 'Departure board synced at ${_coachCrewIsoLabel(_generatedAtIso!)}.',
            ),
            if (_pendingBoardingScans.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline scan queue',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_pendingBoardingScans.length} queued boarding scans are waiting for sync.',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Queued scans retry when this console is reopened, refreshed, or brought back to foreground.',
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _syncingPendingScans
                            ? null
                            : _syncPendingBoardingScans,
                        icon: const Icon(Icons.sync),
                        label: Text(
                          _syncingPendingScans
                              ? 'Syncing...'
                              : 'Sync queued scans',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (manifest != null) ...[
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _manifestFiltersSectionKey,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manifest filters',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _manifestSearchController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Search passengers',
                            hintText: 'Passenger, ticket, seat, or state',
                            prefixIcon: const Icon(Icons.search),
                            border: const OutlineInputBorder(),
                            suffixIcon:
                                _manifestSearchController.text.trim().isEmpty
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () {
                                          _manifestSearchController.clear();
                                          setState(() {});
                                        },
                                      ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text('Loaded ${manifest.manifest.length}'),
                            ),
                            Chip(
                              label: Text(
                                'Pending ${_manifestQueueCount(manifest.manifest, 'pending')}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Boarded ${_manifestQueueCount(manifest.manifest, 'boarded')}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Attention ${_manifestQueueCount(manifest.manifest, 'attention')}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Queue',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final queue in const <String>[
                              'all',
                              'pending',
                              'boarded',
                              'attention',
                            ])
                              ChoiceChip(
                                label: Text(
                                  '${_coachBoardingManifestQueueLabel(queue)} (${queue == 'all' ? manifest.manifest.length : _manifestQueueCount(manifest.manifest, queue)})',
                                ),
                                selected: _selectedManifestQueue == queue,
                                onSelected: (selected) {
                                  if (!selected) return;
                                  setState(() {
                                    _selectedManifestQueue = queue;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Showing ${visibleManifest.length} of ${manifest.manifest.length} passengers',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: .70),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            KeyedSubtree(
              key: _departuresSectionKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today\'s departures',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_loadingBoard)
                    const LinearProgressIndicator()
                  else if (_departures.isEmpty)
                    const Text('No departures available for this crew account.')
                  else
                    ..._departures.map(_buildTripCard),
                ],
              ),
            ),
            const SizedBox(height: 16),
            KeyedSubtree(
              key: _manifestSectionKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manifest == null
                        ? 'Passenger manifest'
                        : 'Passenger manifest · ${manifest.trip.operatorName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_loadingManifest)
                    const LinearProgressIndicator()
                  else if (manifest == null)
                    const Text('Select a departure to load the manifest.')
                  else ...[
                    _buildSelectedTripCard(manifest.trip),
                    const SizedBox(height: 12),
                    if (visibleManifest.isEmpty)
                      Text(
                        'No passengers match the current search or queue.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .70),
                            ),
                      )
                    else
                      ...visibleManifest.map(_buildManifestEntryCard),
                  ],
                ],
              ),
            ),
            if (manifest != null) ...[
              const SizedBox(height: 16),
              KeyedSubtree(
                key: _recentEventsSectionKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent scan events',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (manifest.recentEvents.isEmpty)
                      const Text('No scans recorded yet.')
                    else
                      ...manifest.recentEvents.map(_buildRecentEventTile),
                  ],
                ),
              ),
              if (_selectedTripPendingScans.isNotEmpty) ...[
                const SizedBox(height: 16),
                KeyedSubtree(
                  key: _offlineQueueSectionKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Queued offline scans',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ..._selectedTripPendingScans
                          .map(_buildPendingOfflineScanTile),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(CoachCrewTripSummary trip) {
    final isSelected = trip.tripId == _selectedTripId;
    return Card(
      color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: _loadingManifest ? null : () => _loadManifest(trip.tripId),
        leading: const Icon(Icons.directions_bus_outlined),
        title: Text('${trip.from} -> ${trip.to}'),
        subtitle: Text(
          '${trip.gateLabel} • ${trip.vehicleLabel}\n'
          'Boarded ${trip.boardedCount}/${trip.manifestCount} · '
          'Denied ${trip.deniedCount} · No-show ${trip.noShowCount}',
        ),
        trailing: Text(_coachCrewIsoLabel(trip.departureAtIso)),
      ),
    );
  }

  Widget _buildSelectedTripCard(CoachCrewTripSummary trip) {
    final tripPendingCount = _selectedTripPendingScans
        .where((scan) => scan.tripId == trip.tripId)
        .length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${trip.from} -> ${trip.to}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Boarding window: ${_coachCrewIsoLabel(trip.boardingOpensAtIso)} to ${_coachCrewIsoLabel(trip.boardingClosesAtIso)}',
            ),
            Text('Gate ${trip.gateLabel} · ${trip.vehicleLabel}'),
            Text(
              'Pending ${trip.pendingCount} · Boarded ${trip.boardedCount} · Denied ${trip.deniedCount} · No-show ${trip.noShowCount}',
            ),
            if (tripPendingCount > 0)
              Text('Offline queue for this trip: $tripPendingCount scan(s)'),
          ],
        ),
      ),
    );
  }

  Widget _buildManifestEntryCard(CoachCrewManifestEntry entry) {
    final isRecording = _recordingTicketIds.contains(entry.ticket.ticketId);
    final pendingScan = _pendingScanForTicket(entry.ticket.ticketId);
    return Card(
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
                        entry.passenger.displayName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.ticket.ticketId} · Seat ${entry.seatNumber}',
                      ),
                      Text(
                        _coachCrewBoardingStateLabel(entry.boardingState),
                      ),
                    ],
                  ),
                ),
                if (entry.needsAttention)
                  const Icon(Icons.warning_amber_outlined,
                      color: Colors.orange),
              ],
            ),
            if (entry.lastEvent != null) ...[
              const SizedBox(height: 8),
              StatusBanner.info(
                '${_coachCrewScanStatusLabel(entry.lastEvent!.scanStatus)} at ${_coachCrewIsoLabel(entry.lastEvent!.capturedAtIso)}'
                '${entry.lastEvent!.note == null ? '' : ' · ${entry.lastEvent!.note}'}',
                dense: true,
              ),
            ],
            if (pendingScan != null) ...[
              const SizedBox(height: 8),
              StatusBanner.warning(
                'Offline ${_coachCrewScanStatusLabel(pendingScan.scanStatus).toLowerCase()} queued at ${_coachCrewEpochLabel(pendingScan.createdAtEpochMs)}'
                '${pendingScan.retries > 0 ? ' · retry ${pendingScan.retries}' : ''}'
                '${pendingScan.nextAttemptAtEpochMs > 0 ? ' · next ${_coachCrewEpochLabel(pendingScan.nextAttemptAtEpochMs)}' : ''}',
                dense: true,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: isRecording
                      ? null
                      : () => _recordBoarding(
                            entry,
                            CoachBoardingScanStatus.scanned,
                          ),
                  child: const Text('Boarded'),
                ),
                OutlinedButton(
                  onPressed: isRecording
                      ? null
                      : () => _recordBoarding(
                            entry,
                            CoachBoardingScanStatus.denied,
                            note: 'boarding denied by crew',
                          ),
                  child: const Text('Denied'),
                ),
                OutlinedButton(
                  onPressed: isRecording
                      ? null
                      : () => _recordBoarding(
                            entry,
                            CoachBoardingScanStatus.noShow,
                            note: 'passenger did not board before departure',
                          ),
                  child: const Text('No-show'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentEventTile(CoachBoardingEvent event) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.fact_check_outlined),
        title: Text(
            '${event.ticketId} · ${_coachCrewScanStatusLabel(event.scanStatus)}'),
        subtitle: Text(
          '${_coachCrewIsoLabel(event.capturedAtIso)}'
          '${event.note == null ? '' : ' · ${event.note}'}',
        ),
      ),
    );
  }

  Widget _buildPendingOfflineScanTile(CoachOfflineBoardingScan scan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(
          '${scan.ticketId} · ${_coachCrewScanStatusLabel(scan.scanStatus)}',
        ),
        subtitle: Text(
          '${_coachCrewEpochLabel(scan.createdAtEpochMs)}'
          '${scan.nextAttemptAtEpochMs > 0 ? ' · next ${_coachCrewEpochLabel(scan.nextAttemptAtEpochMs)}' : ''}'
          '${scan.note == null ? '' : ' · ${scan.note}'}',
        ),
        trailing: scan.retries > 0 ? Text('retry ${scan.retries}') : null,
      ),
    );
  }
}

class _CoachBoardingAttentionItemData {
  final IconData icon;
  final String title;
  final String detail;

  const _CoachBoardingAttentionItemData({
    required this.icon,
    required this.title,
    required this.detail,
  });
}

class _CoachBoardingCommandMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CoachBoardingCommandMetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .45,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: .50),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: theme.colorScheme.primary.withValues(alpha: .90),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .72),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachBoardingSimpleMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _CoachBoardingSimpleMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .46),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachBoardingAttentionItem extends StatelessWidget {
  final _CoachBoardingAttentionItemData item;

  const _CoachBoardingAttentionItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 18,
            color: theme.colorScheme.primary.withValues(alpha: .95),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
