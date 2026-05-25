import 'package:flutter/material.dart';

import '../safe_set_state.dart';
import '../shamell_empty_state.dart';
import '../shamell_loading_shimmer.dart';
import '../status_banner.dart';
import 'coach_mobility_api.dart';

String _coachDisruptionIsoLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '-';
  return value.replaceFirst('T', ' ').replaceFirst('Z', ' UTC');
}

String _coachDisruptionWorkflowLabel(String workflowStatus) {
  switch (workflowStatus) {
    case 'resolved':
      return 'Resolved';
    case 'action_required':
      return 'Action required';
    case 'monitoring':
      return 'Monitoring';
    default:
      return 'Scheduled';
  }
}

Color _coachDisruptionWorkflowColor(String workflowStatus) {
  switch (workflowStatus) {
    case 'resolved':
      return Colors.green;
    case 'action_required':
      return Colors.redAccent;
    case 'monitoring':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}

String _coachDisruptionKindLabel(String? disruptionKind) {
  switch (disruptionKind) {
    case 'cancelled':
      return 'Cancelled';
    case 'delay':
      return 'Delay';
    default:
      return 'No disruption';
  }
}

Color? _coachDisruptionSeverityColor(String severity) {
  switch (severity) {
    case 'critical':
      return Colors.redAccent;
    case 'high':
      return Colors.deepOrange;
    case 'medium':
      return Colors.orange;
    default:
      return Colors.blueGrey;
  }
}

String _coachDisruptionQueueLabel(String queue) {
  switch (queue) {
    case 'action_required':
      return 'Action required';
    case 'critical':
      return 'Critical';
    case 'cancelled':
      return 'Cancelled';
    case 'reaccommodation':
      return 'Reaccommodation';
    case 'feed_alerts':
      return 'Feed alerts';
    case 'boarding':
      return 'Boarding';
    default:
      return 'All';
  }
}

bool _coachDisruptionNeedsReaccommodation(CoachAdminDisruptionTrip trip) {
  return trip.eligibleReaccommodationCount > trip.queuedReaccommodationCount ||
      trip.queuedReaccommodationCount > 0;
}

bool _coachDisruptionNeedsBoardingFollowUp(CoachAdminDisruptionTrip trip) {
  return trip.pendingCount > 0 || trip.deniedCount > 0;
}

bool _coachDisruptionMatchesQueue(
  CoachAdminDisruptionTrip trip,
  String queue,
) {
  switch (queue) {
    case 'action_required':
      return trip.workflowStatus == 'action_required';
    case 'critical':
      return trip.severity == 'critical';
    case 'cancelled':
      return trip.disruptionKind == 'cancelled';
    case 'reaccommodation':
      return _coachDisruptionNeedsReaccommodation(trip);
    case 'feed_alerts':
      return trip.feedIssueCount > 0;
    case 'boarding':
      return _coachDisruptionNeedsBoardingFollowUp(trip);
    default:
      return true;
  }
}

int _coachDisruptionQueueCount(
  List<CoachAdminDisruptionTrip> trips,
  String queue,
) {
  return trips
      .where((trip) => _coachDisruptionMatchesQueue(trip, queue))
      .length;
}

String _coachDisruptionSortLabel(String sort) {
  switch (sort) {
    case 'departure':
      return 'Departure first';
    case 'impact':
      return 'Highest impact';
    default:
      return 'Priority';
  }
}

int _coachDisruptionSeverityRank(String severity) {
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

int _coachDisruptionWorkflowRank(String workflowStatus) {
  switch (workflowStatus) {
    case 'action_required':
      return 0;
    case 'monitoring':
      return 1;
    case 'scheduled':
      return 2;
    case 'resolved':
      return 3;
    default:
      return 4;
  }
}

int _coachDisruptionKindRank(String? disruptionKind) {
  switch (disruptionKind) {
    case 'cancelled':
      return 0;
    case 'delay':
      return 1;
    default:
      return 2;
  }
}

DateTime _coachDisruptionTimestamp(String iso) {
  return DateTime.tryParse(iso)?.toUtc() ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

int _coachDisruptionImpactScore(CoachAdminDisruptionTrip trip) {
  return trip.affectedBookingCount * 100 +
      trip.pendingCount * 10 +
      trip.feedIssueCount +
      trip.queuedReaccommodationCount;
}

List<CoachAdminDisruptionTrip> _coachDisruptionSortedTrips(
  List<CoachAdminDisruptionTrip> trips,
  String sort,
) {
  final out = List<CoachAdminDisruptionTrip>.of(trips);
  out.sort((left, right) {
    if (sort == 'departure') {
      final departureCompare = _coachDisruptionTimestamp(
        left.departureAtIso,
      ).compareTo(_coachDisruptionTimestamp(right.departureAtIso));
      if (departureCompare != 0) {
        return departureCompare;
      }
    }
    if (sort == 'impact') {
      final impactCompare = _coachDisruptionImpactScore(
        right,
      ).compareTo(_coachDisruptionImpactScore(left));
      if (impactCompare != 0) {
        return impactCompare;
      }
    }
    final workflowCompare = _coachDisruptionWorkflowRank(
      left.workflowStatus,
    ).compareTo(_coachDisruptionWorkflowRank(right.workflowStatus));
    if (workflowCompare != 0) {
      return workflowCompare;
    }
    final severityCompare = _coachDisruptionSeverityRank(
      left.severity,
    ).compareTo(_coachDisruptionSeverityRank(right.severity));
    if (severityCompare != 0) {
      return severityCompare;
    }
    final kindCompare = _coachDisruptionKindRank(left.disruptionKind).compareTo(
      _coachDisruptionKindRank(right.disruptionKind),
    );
    if (kindCompare != 0) {
      return kindCompare;
    }
    final reaccommodationCompare =
        (_coachDisruptionNeedsReaccommodation(right) ? 1 : 0).compareTo(
      _coachDisruptionNeedsReaccommodation(left) ? 1 : 0,
    );
    if (reaccommodationCompare != 0) {
      return reaccommodationCompare;
    }
    final impactCompare = _coachDisruptionImpactScore(
      right,
    ).compareTo(_coachDisruptionImpactScore(left));
    if (impactCompare != 0) {
      return impactCompare;
    }
    final departureCompare = _coachDisruptionTimestamp(
      left.departureAtIso,
    ).compareTo(_coachDisruptionTimestamp(right.departureAtIso));
    if (departureCompare != 0) {
      return departureCompare;
    }
    return left.tripId.compareTo(right.tripId);
  });
  return out;
}

class CoachAdminDisruptionsPage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? api;
  final CoachAdminDisruptionsResponse? initialResponse;

  const CoachAdminDisruptionsPage({
    super.key,
    required this.baseUrl,
    this.api,
    this.initialResponse,
  });

  @override
  State<CoachAdminDisruptionsPage> createState() =>
      _CoachAdminDisruptionsPageState();
}

class _CoachAdminDisruptionsPageState extends State<CoachAdminDisruptionsPage>
    with SafeSetStateMixin<CoachAdminDisruptionsPage> {
  late final CoachMobilityApi _api =
      widget.api ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  final TextEditingController _queryController = TextEditingController();

  CoachAdminDisruptionsResponse? _response;
  bool _loading = false;
  String? _errorMessage;
  String _workflowStatusFilter = 'all';
  String _disruptionKindFilter = 'all';
  String _selectedQueue = 'all';
  String _selectedSort = 'priority';
  final Set<String> _busyTripIds = <String>{};

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
      final response = await _api.adminDisruptions(
        query: _queryController.text,
        workflowStatus:
            _workflowStatusFilter == 'all' ? null : _workflowStatusFilter,
        disruptionKind:
            _disruptionKindFilter == 'all' ? null : _disruptionKindFilter,
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

  CoachAdminDisruptionSummary _summaryFromTrips(
    List<CoachAdminDisruptionTrip> trips,
  ) {
    return CoachAdminDisruptionSummary(
      tripCount: trips.length,
      scheduledTrips:
          trips.where((trip) => trip.workflowStatus == 'scheduled').length,
      monitoringTrips:
          trips.where((trip) => trip.workflowStatus == 'monitoring').length,
      actionRequiredTrips: trips
          .where((trip) => trip.workflowStatus == 'action_required')
          .length,
      resolvedTrips:
          trips.where((trip) => trip.workflowStatus == 'resolved').length,
      delayedTrips:
          trips.where((trip) => trip.disruptionKind == 'delay').length,
      cancelledTrips:
          trips.where((trip) => trip.disruptionKind == 'cancelled').length,
      criticalTrips: trips.where((trip) => trip.severity == 'critical').length,
      affectedBookingCount:
          trips.fold(0, (sum, trip) => sum + trip.affectedBookingCount),
      eligibleReaccommodationCount: trips.fold(
        0,
        (sum, trip) => sum + trip.eligibleReaccommodationCount,
      ),
      queuedReaccommodationCount:
          trips.fold(0, (sum, trip) => sum + trip.queuedReaccommodationCount),
    );
  }

  void _mergeTrip(CoachAdminDisruptionTrip trip) {
    final current = _response;
    if (current == null) return;
    final trips = current.trips
        .map((candidate) => candidate.tripId == trip.tripId ? trip : candidate)
        .toList(growable: false);
    setState(() {
      _response = CoachAdminDisruptionsResponse(
        generatedAtIso: DateTime.now().toUtc().toIso8601String(),
        summary: _summaryFromTrips(trips),
        trips: trips,
      );
    });
  }

  Future<void> _runAction(
    CoachAdminDisruptionTrip trip,
    String action, {
    int? delayMinutes,
    String? reason,
  }) async {
    setState(() {
      _busyTripIds.add(trip.tripId);
      _errorMessage = null;
    });
    try {
      final result = await _api.adminDisruptionAction(
        tripId: trip.tripId,
        action: action,
        delayMinutes: delayMinutes,
        reason: reason,
      );
      _mergeTrip(result.trip);
      if (!mounted) return;
      final queued = result.queuedChangeRequestIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued > 0
                ? '${trip.operatorName}: queued $queued reaccommodation request(s)'
                : '${trip.operatorName}: ${_coachDisruptionWorkflowLabel(result.trip.workflowStatus)}',
          ),
        ),
      );
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      setState(() {
        _busyTripIds.remove(trip.tripId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final response = _response;
    final filteredTrips = response == null
        ? const <CoachAdminDisruptionTrip>[]
        : response.trips
            .where((trip) => _coachDisruptionMatchesQueue(trip, _selectedQueue))
            .toList(growable: false);
    final visibleTrips = _coachDisruptionSortedTrips(
      filteredTrips,
      _selectedSort,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coach disruptions'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_errorMessage != null) ...[
                StatusBanner.error(_errorMessage!),
                const SizedBox(height: 12),
              ],
              StatusBanner.info(
                response == null
                    ? 'Track delayed or cancelled trips and queue reaccommodation directly into the change queue.'
                    : 'Updated ${_coachDisruptionIsoLabel(response.generatedAtIso)}.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      decoration: const InputDecoration(
                        labelText: 'Search trips',
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
                      DropdownMenuItem(value: 'all', child: Text('All status')),
                      DropdownMenuItem(
                        value: 'scheduled',
                        child: Text('Scheduled'),
                      ),
                      DropdownMenuItem(
                        value: 'monitoring',
                        child: Text('Monitoring'),
                      ),
                      DropdownMenuItem(
                        value: 'action_required',
                        child: Text('Action required'),
                      ),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Text('Resolved'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: DropdownButton<String>(
                  value: _disruptionKindFilter,
                  onChanged: _loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _disruptionKindFilter = value;
                          });
                          _load();
                        },
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All kinds')),
                    DropdownMenuItem(value: 'delay', child: Text('Delay')),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelled'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (response != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFFFFFAF7),
                        Color(0xFFFBEFE7),
                        Color(0xFFF4E4D8),
                      ],
                    ),
                    border: Border.all(color: const Color(0xFFE7D7CA)),
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
                          border: Border.all(color: const Color(0xFFE7D7CA)),
                        ),
                        child: Text(
                          'Coach admin queue',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: const Color(0xFF9A3412),
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Disruption command desk',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: const Color(0xFF3B2214),
                              fontWeight: FontWeight.w900,
                              height: .96,
                            ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Text(
                          'Run delayed and cancelled trips from one queue. Focus on affected bookings, reaccommodation pressure, and boarding exceptions before departures slip further.',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
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
                          _CoachDisruptionHeaderBadge(
                            icon: Icons.public_outlined,
                            label: 'Scope: Coach admin',
                          ),
                          _CoachDisruptionHeaderBadge(
                            icon: Icons.warning_amber_outlined,
                            label:
                                'Action required ${response.summary.actionRequiredTrips}',
                            color: const Color(0xFFB45309),
                          ),
                          _CoachDisruptionHeaderBadge(
                            icon: Icons.crisis_alert_outlined,
                            label: 'Critical ${response.summary.criticalTrips}',
                            color: const Color(0xFFB91C1C),
                          ),
                          _CoachDisruptionHeaderBadge(
                            icon: Icons.swap_horiz_outlined,
                            label:
                                'Queued reaccommodation ${response.summary.queuedReaccommodationCount}',
                            color: const Color(0xFF0F766E),
                          ),
                          _CoachDisruptionHeaderBadge(
                            icon: Icons.update_outlined,
                            label:
                                'Updated ${_coachDisruptionIsoLabel(response.generatedAtIso)}',
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
                          for (final queue in const <String>[
                            'action_required',
                            'critical',
                            'cancelled',
                            'reaccommodation',
                            'feed_alerts',
                            'boarding',
                          ])
                            _CoachDisruptionFocusCard(
                              key: ValueKey('coachDisruptionFocus_$queue'),
                              icon: switch (queue) {
                                'action_required' =>
                                  Icons.crisis_alert_outlined,
                                'critical' => Icons.priority_high_outlined,
                                'cancelled' => Icons.event_busy_outlined,
                                'reaccommodation' => Icons.swap_horiz_outlined,
                                'feed_alerts' => Icons.hub_outlined,
                                'boarding' =>
                                  Icons.airline_seat_recline_normal_outlined,
                                _ => Icons.list_alt_outlined,
                              },
                              label: _coachDisruptionQueueLabel(queue),
                              value:
                                  '${_coachDisruptionQueueCount(response.trips, queue)}',
                              detail: switch (queue) {
                                'action_required' =>
                                  'Trips already escalated into active handling',
                                'critical' =>
                                  'Highest-severity journeys across today’s network',
                                'cancelled' =>
                                  'Cancelled service that needs clear fallout handling',
                                'reaccommodation' =>
                                  'Trips with reissue pressure or queued rebooking',
                                'feed_alerts' =>
                                  'Partner feed instability during active disruption',
                                'boarding' =>
                                  'Pending or denied passenger handling at departure',
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
                    Chip(label: Text('Trips ${response.summary.tripCount}')),
                    Chip(
                      label: Text(
                        'Action required ${response.summary.actionRequiredTrips}',
                      ),
                    ),
                    Chip(
                      label: Text('Delayed ${response.summary.delayedTrips}'),
                    ),
                    Chip(
                      label:
                          Text('Cancelled ${response.summary.cancelledTrips}'),
                    ),
                    Chip(
                      label: Text(
                        'Queued reaccommodation ${response.summary.queuedReaccommodationCount}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (response != null) ...[
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
                      'critical',
                      'cancelled',
                      'reaccommodation',
                      'feed_alerts',
                      'boarding',
                    ])
                      ChoiceChip(
                        label: Text(
                          '${_coachDisruptionQueueLabel(queue)} (${_coachDisruptionQueueCount(response.trips, queue)})',
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
                      'departure',
                      'impact',
                    ])
                      ChoiceChip(
                        label: Text(_coachDisruptionSortLabel(sort)),
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
                  'Showing ${visibleTrips.length} of ${response.trips.length} trips • Sorted by ${_coachDisruptionSortLabel(_selectedSort).toLowerCase()}',
                ),
                const SizedBox(height: 12),
              ],
              if (_loading && response == null) ...[
                const ShamellSkeletonList(itemCount: 5),
              ] else if (response == null || response.trips.isEmpty) ...[
                const ShamellEmptyState.empty(
                  icon: Icons.event_busy_outlined,
                  title: 'No disruption data loaded yet.',
                ),
              ] else ...[
                if (visibleTrips.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No trips match the current filters.'),
                    ),
                  ),
                for (final trip in visibleTrips) ...[
                  Card(
                    key: ValueKey('coachDisruptionCard_${trip.tripId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
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
                                      '${trip.from} → ${trip.to}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${trip.operatorName} • ${_coachDisruptionIsoLabel(trip.departureAtIso)}',
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${trip.gateLabel} • ${trip.vehicleLabel}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Chip(
                                backgroundColor: _coachDisruptionWorkflowColor(
                                  trip.workflowStatus,
                                ).withValues(alpha: 0.12),
                                label: Text(
                                  _coachDisruptionWorkflowLabel(
                                    trip.workflowStatus,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(
                                label: Text(
                                  _coachDisruptionKindLabel(
                                      trip.disruptionKind),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  'Severity ${trip.severity}',
                                ),
                                backgroundColor: (_coachDisruptionSeverityColor(
                                          trip.severity,
                                        ) ??
                                        Colors.blueGrey)
                                    .withValues(alpha: 0.12),
                              ),
                              if (trip.delayMinutes != null)
                                Chip(
                                  label: Text('Delay ${trip.delayMinutes}m'),
                                ),
                              Chip(
                                label: Text(
                                  'Boarding ${trip.boardedCount}/${trip.manifestCount}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  'Eligible ${trip.eligibleReaccommodationCount}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  'Queued ${trip.queuedReaccommodationCount}',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF6EF),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFF0DFC9),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Next action',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(trip.nextAction),
                              ],
                            ),
                          ),
                          if (trip.reason != null) ...[
                            const SizedBox(height: 8),
                            Text('Reason: ${trip.reason}'),
                          ],
                          if (trip.note != null) ...[
                            const SizedBox(height: 6),
                            Text('Note: ${trip.note}'),
                          ],
                          if (trip.blockers.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Blockers',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            for (final blocker in trip.blockers)
                              Text(
                                '• $blocker',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _busyTripIds.contains(trip.tripId)
                                    ? null
                                    : () => _runAction(
                                          trip,
                                          'mark_delayed',
                                          delayMinutes: 45,
                                          reason:
                                              'operator delay above service threshold',
                                        ),
                                child: const Text('Delay 45m'),
                              ),
                              OutlinedButton(
                                onPressed: _busyTripIds.contains(trip.tripId)
                                    ? null
                                    : () => _runAction(
                                          trip,
                                          'mark_cancelled',
                                          reason:
                                              'service was cancelled by operator',
                                        ),
                                child: const Text('Cancel trip'),
                              ),
                              FilledButton(
                                onPressed: _busyTripIds.contains(trip.tripId) ||
                                        trip.eligibleReaccommodationCount == 0
                                    ? null
                                    : () => _runAction(
                                          trip,
                                          'queue_reaccommodation',
                                        ),
                                child: const Text('Queue reaccommodation'),
                              ),
                              TextButton(
                                onPressed: _busyTripIds.contains(trip.tripId)
                                    ? null
                                    : () => _runAction(trip, 'resolve'),
                                child: const Text('Resolve'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachDisruptionHeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CoachDisruptionHeaderBadge({
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
        border: Border.all(color: const Color(0xFFE7D7CA)),
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

class _CoachDisruptionFocusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  const _CoachDisruptionFocusCard({
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
                  ? const Color(0xFFFDE9D9)
                  : Colors.white.withValues(alpha: .76),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? const Color(0xFFF08D49)
                    : const Color(0xFFE7D7CA),
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
