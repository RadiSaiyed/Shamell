import 'package:flutter/material.dart';

class CoachShiftPanel extends StatefulWidget {
  final String roleLabel;
  final int assignedTrips;
  final int openTasks;
  final int crewMembers;
  final String handoverHint;

  const CoachShiftPanel({
    super.key,
    required this.roleLabel,
    required this.assignedTrips,
    required this.openTasks,
    this.crewMembers = 1,
    this.handoverHint = 'Add handover note for the next shift',
  });

  @override
  State<CoachShiftPanel> createState() => _CoachShiftPanelState();
}

class _CoachShiftPanelState extends State<CoachShiftPanel> {
  final TextEditingController _handoverController = TextEditingController();
  bool _shiftActive = false;
  DateTime? _startedAt;
  DateTime? _endedAt;

  @override
  void dispose() {
    _handoverController.dispose();
    super.dispose();
  }

  void _toggleShift() {
    setState(() {
      if (_shiftActive) {
        _shiftActive = false;
        _endedAt = DateTime.now().toUtc();
      } else {
        _shiftActive = true;
        _startedAt = DateTime.now().toUtc();
        _endedAt = null;
      }
    });
  }

  String _timeLabel(DateTime? value) {
    if (value == null) return '-';
    return value.toIso8601String().replaceFirst('T', ' ').replaceFirst('Z', '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachShiftPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _shiftActive
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline,
                color: _shiftActive
                    ? const Color(0xFF0F766E)
                    : theme.colorScheme.onSurface.withValues(alpha: .58),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shift mode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _toggleShift,
                icon: Icon(_shiftActive ? Icons.stop : Icons.play_arrow),
                label: Text(_shiftActive ? 'End shift' : 'Start shift'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(widget.roleLabel)),
              Chip(label: Text('Trips ${widget.assignedTrips}')),
              Chip(label: Text('Open tasks ${widget.openTasks}')),
              Chip(label: Text('Crew ${widget.crewMembers}')),
              Chip(
                label: Text(
                  _shiftActive
                      ? 'Started ${_timeLabel(_startedAt)}'
                      : _endedAt == null
                          ? 'Not started'
                          : 'Ended ${_timeLabel(_endedAt)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _handoverController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Handover note',
              hintText: widget.handoverHint,
              prefixIcon: const Icon(Icons.edit_note_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class CoachIncidentTemplate {
  final String id;
  final IconData icon;
  final String title;
  final String detail;
  final List<String> actions;

  const CoachIncidentTemplate({
    required this.id,
    required this.icon,
    required this.title,
    required this.detail,
    required this.actions,
  });
}

const List<CoachIncidentTemplate> coachDefaultIncidentTemplates =
    <CoachIncidentTemplate>[
  CoachIncidentTemplate(
    id: 'bus_delay',
    icon: Icons.schedule_outlined,
    title: 'Bus delayed',
    detail: 'Notify passengers, update trip status, and watch rebooking risk.',
    actions: <String>[
      'Send passenger update',
      'Open disruption desk',
      'Add shift handover note',
    ],
  ),
  CoachIncidentTemplate(
    id: 'bus_cancelled',
    icon: Icons.cancel_outlined,
    title: 'Bus cancelled',
    detail:
        'Queue reaccommodation, refunds, support cases, and cancellation notices.',
    actions: <String>[
      'Send cancellation notice',
      'Queue rebooking or refund',
      'Open support follow-up',
    ],
  ),
  CoachIncidentTemplate(
    id: 'passenger_missing',
    icon: Icons.person_off_outlined,
    title: 'Passenger missing',
    detail: 'Mark no-show, notify support, and keep the manifest consistent.',
    actions: <String>[
      'Mark no-show',
      'Notify support',
      'Update manifest timeline',
    ],
  ),
  CoachIncidentTemplate(
    id: 'invalid_qr',
    icon: Icons.qr_code_2_outlined,
    title: 'Invalid QR',
    detail:
        'Check ticket status, prevent duplicate entry, and route the case to support.',
    actions: <String>[
      'Deny scan',
      'Open support case',
      'Add boarding note',
    ],
  ),
  CoachIncidentTemplate(
    id: 'duplicate_boarding',
    icon: Icons.copy_all_outlined,
    title: 'Duplicate boarding',
    detail: 'Flag risk, stop the second scan, and keep an audit trail.',
    actions: <String>[
      'Block duplicate',
      'Open risk follow-up',
      'Record audit event',
    ],
  ),
];

class CoachIncidentFlowPanel extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<CoachIncidentTemplate> templates;
  final ValueChanged<CoachIncidentTemplate>? onRunPlaybook;

  const CoachIncidentFlowPanel({
    super.key,
    this.title = 'Incident flow',
    this.subtitle = 'Pick the problem, then run the matching recovery steps.',
    this.templates = coachDefaultIncidentTemplates,
    this.onRunPlaybook,
  });

  @override
  State<CoachIncidentFlowPanel> createState() => _CoachIncidentFlowPanelState();
}

class _CoachIncidentFlowPanelState extends State<CoachIncidentFlowPanel> {
  late CoachIncidentTemplate _selected = widget.templates.first;
  String? _lastRun;

  @override
  void didUpdateWidget(covariant CoachIncidentFlowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.templates.any((template) => template.id == _selected.id)) {
      _selected = widget.templates.first;
    }
  }

  void _runPlaybook() {
    widget.onRunPlaybook?.call(_selected);
    setState(() {
      _lastRun = _selected.title;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text('${_selected.title} playbook ready.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachIncidentFlowPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final template in widget.templates)
                ChoiceChip(
                  avatar: Icon(template.icon, size: 18),
                  label: Text(template.title),
                  selected: template.id == _selected.id,
                  onSelected: (_) => setState(() => _selected = template),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _selected.detail,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in _selected.actions)
                Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(action),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey('coachIncidentRunPlaybookButton'),
                onPressed: _runPlaybook,
                icon: const Icon(Icons.playlist_add_check_outlined),
                label: const Text('Run playbook'),
              ),
              if (_lastRun != null)
                Text(
                  'Last run: $_lastRun',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .66),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CoachPassengerNotificationPanel extends StatefulWidget {
  final int impactedPassengers;
  final String contextLabel;

  const CoachPassengerNotificationPanel({
    super.key,
    required this.impactedPassengers,
    this.contextLabel = 'Coach passengers',
  });

  @override
  State<CoachPassengerNotificationPanel> createState() =>
      _CoachPassengerNotificationPanelState();
}

class _CoachPassengerNotificationPanelState
    extends State<CoachPassengerNotificationPanel> {
  bool _pushEnabled = true;
  bool _smsEnabled = true;
  bool _inAppEnabled = true;

  int get _channelCount =>
      (_pushEnabled ? 1 : 0) + (_smsEnabled ? 1 : 0) + (_inAppEnabled ? 1 : 0);

  void _sendPreview() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Passenger update queued for ${widget.impactedPassengers} passenger(s).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachPassengerNotificationPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Passenger notifications',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.contextLabel} -> ${widget.impactedPassengers} impacted passenger(s), $_channelCount channel(s).',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                avatar:
                    const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Push'),
                selected: _pushEnabled,
                onSelected: (value) => setState(() => _pushEnabled = value),
              ),
              FilterChip(
                avatar: const Icon(Icons.sms_outlined, size: 18),
                label: const Text('SMS'),
                selected: _smsEnabled,
                onSelected: (value) => setState(() => _smsEnabled = value),
              ),
              FilterChip(
                avatar: const Icon(Icons.inbox_outlined, size: 18),
                label: const Text('In-app'),
                selected: _inAppEnabled,
                onSelected: (value) => setState(() => _inAppEnabled = value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              Chip(label: Text('Delay')),
              Chip(label: Text('Gate change')),
              Chip(label: Text('Ticket issued')),
              Chip(label: Text('Refund approved')),
              Chip(label: Text('Trip cancelled')),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _channelCount == 0 ? null : _sendPreview,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Send preview update'),
          ),
        ],
      ),
    );
  }
}

class CoachTimelineEvent {
  final IconData icon;
  final String title;
  final String detail;
  final String timeLabel;
  final bool done;

  const CoachTimelineEvent({
    required this.icon,
    required this.title,
    required this.detail,
    required this.timeLabel,
    this.done = true,
  });
}

class CoachTimelinePanel extends StatelessWidget {
  final String title;
  final List<CoachTimelineEvent> events;

  const CoachTimelinePanel({
    super.key,
    required this.title,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachTimelinePanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text(
              'No timeline events yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            )
          else
            for (var index = 0; index < events.length; index++) ...[
              _CoachTimelineRow(event: events[index]),
              if (index < events.length - 1)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 15),
                  child: Container(
                    width: 1,
                    height: 14,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

class _CoachTimelineRow extends StatelessWidget {
  final CoachTimelineEvent event;

  const _CoachTimelineRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.done
        ? const Color(0xFF0F766E)
        : theme.colorScheme.onSurface.withValues(alpha: .46);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: color.withValues(alpha: .12),
          child: Icon(event.icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(event.detail, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          event.timeLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .62),
          ),
        ),
      ],
    );
  }
}

class CoachSeatStatus {
  final String seatLabel;
  final String passengerLabel;
  final String statusLabel;
  final Color color;
  final IconData icon;

  const CoachSeatStatus({
    required this.seatLabel,
    required this.passengerLabel,
    required this.statusLabel,
    required this.color,
    required this.icon,
  });
}

class CoachSeatMapPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<CoachSeatStatus> seats;
  final int capacity;

  const CoachSeatMapPanel({
    super.key,
    this.title = 'Seat map',
    this.subtitle = 'Track boarded, pending, blocked, and exception seats.',
    required this.seats,
    required this.capacity,
  });

  int _countWhere(String label) {
    final normalized = label.trim().toLowerCase();
    return seats
        .where((seat) => seat.statusLabel.trim().toLowerCase() == normalized)
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final occupiedSeats = seats.length;
    final openSeats = capacity > occupiedSeats ? capacity - occupiedSeats : 0;
    return Container(
      key: const ValueKey('coachSeatMapPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_seat_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Capacity $capacity')),
              Chip(label: Text('Open $openSeats')),
              Chip(label: Text('Boarded ${_countWhere('Boarded')}')),
              Chip(label: Text('Attention ${_countWhere('Attention')}')),
            ],
          ),
          const SizedBox(height: 12),
          if (seats.isEmpty)
            Text(
              'Load a manifest to see seats.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final seat in seats.take(48))
                  Tooltip(
                    message:
                        '${seat.seatLabel}: ${seat.passengerLabel} (${seat.statusLabel})',
                    child: Container(
                      width: 74,
                      height: 64,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: seat.color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: seat.color.withValues(alpha: .36),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(seat.icon, size: 15, color: seat.color),
                              const Spacer(),
                              Text(
                                seat.seatLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: seat.color,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            seat.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class CoachOfflineBoardingPanel extends StatefulWidget {
  final int queuedScans;
  final int conflictCount;
  final bool liveSyncAvailable;
  final VoidCallback? onSyncNow;

  const CoachOfflineBoardingPanel({
    super.key,
    required this.queuedScans,
    required this.conflictCount,
    required this.liveSyncAvailable,
    this.onSyncNow,
  });

  @override
  State<CoachOfflineBoardingPanel> createState() =>
      _CoachOfflineBoardingPanelState();
}

class _CoachOfflineBoardingPanelState extends State<CoachOfflineBoardingPanel> {
  bool _captureOffline = false;
  String _conflictPolicy = 'Manual review';

  void _savePolicy(String value) {
    setState(() {
      _conflictPolicy = value;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Offline conflict policy set to $value.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachOfflineBoardingPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.liveSyncAvailable
            ? theme.colorScheme.surface
            : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.liveSyncAvailable
              ? theme.colorScheme.outlineVariant
              : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('coachOfflineBoardingCaptureSwitch'),
            contentPadding: EdgeInsets.zero,
            value: _captureOffline,
            onChanged: (value) => setState(() => _captureOffline = value),
            title: const Text('Offline boarding mode'),
            subtitle: Text(
              widget.liveSyncAvailable
                  ? 'Live sync is available; offline capture is a fallback.'
                  : 'Live sync unavailable; scans stay queued until reconnect.',
            ),
            secondary: Icon(
              widget.liveSyncAvailable
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Queued ${widget.queuedScans}')),
              Chip(label: Text('Conflicts ${widget.conflictCount}')),
              Chip(label: Text('Policy $_conflictPolicy')),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final policy in const <String>[
                'Manual review',
                'Latest scan wins',
                'Deny duplicates',
              ])
                ChoiceChip(
                  label: Text(policy),
                  selected: _conflictPolicy == policy,
                  onSelected: (_) => _savePolicy(policy),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.queuedScans == 0 ? null : widget.onSyncNow,
            icon: const Icon(Icons.sync),
            label: const Text('Sync queued scans'),
          ),
        ],
      ),
    );
  }
}

class CoachTripHealthFactor {
  final IconData icon;
  final String label;
  final String value;
  final bool healthy;

  const CoachTripHealthFactor({
    required this.icon,
    required this.label,
    required this.value,
    required this.healthy,
  });
}

class CoachTripHealthScorePanel extends StatelessWidget {
  final int score;
  final String tripLabel;
  final List<CoachTripHealthFactor> factors;

  const CoachTripHealthScorePanel({
    super.key,
    required this.score,
    required this.tripLabel,
    required this.factors,
  });

  Color _scoreColor() {
    if (score >= 85) return const Color(0xFF0F766E);
    if (score >= 65) return const Color(0xFFB45309);
    return const Color(0xFFB91C1C);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _scoreColor();
    return Container(
      key: const ValueKey('coachTripHealthScorePanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: color.withValues(alpha: .15),
                child: Text(
                  '$score',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live trip health score',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tripLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final factor in factors)
                Chip(
                  avatar: Icon(
                    factor.icon,
                    size: 18,
                    color: factor.healthy
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFB45309),
                  ),
                  label: Text('${factor.label}: ${factor.value}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CoachRecoveryFlowPanel extends StatefulWidget {
  final String title;
  final String routeLabel;
  final int impactedPassengers;
  final List<String> rebookingOptions;
  final String compensationLabel;

  const CoachRecoveryFlowPanel({
    super.key,
    this.title = 'Passenger recovery desk',
    required this.routeLabel,
    required this.impactedPassengers,
    required this.rebookingOptions,
    required this.compensationLabel,
  });

  @override
  State<CoachRecoveryFlowPanel> createState() => _CoachRecoveryFlowPanelState();
}

class _CoachRecoveryFlowPanelState extends State<CoachRecoveryFlowPanel> {
  String _caseType = 'Missed bus';
  String? _selectedOption;
  bool _voucherReady = false;
  bool _requestQueued = false;

  @override
  void initState() {
    super.initState();
    _selectedOption =
        widget.rebookingOptions.isEmpty ? null : widget.rebookingOptions.first;
  }

  @override
  void didUpdateWidget(covariant CoachRecoveryFlowPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.rebookingOptions.contains(_selectedOption)) {
      _selectedOption = widget.rebookingOptions.isEmpty
          ? null
          : widget.rebookingOptions.first;
    }
  }

  void _queue(String message) {
    setState(() {
      _requestQueued = true;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachRecoveryFlowPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.routeLabel} -> ${widget.impactedPassengers} passenger(s)',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in const <String>[
                'Missed bus',
                'Invalid QR',
                'Delay',
                'Cancellation',
                'Name mismatch',
              ])
                ChoiceChip(
                  label: Text(type),
                  selected: _caseType == type,
                  onSelected: (_) => setState(() => _caseType = type),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.rebookingOptions.isNotEmpty) ...[
            Text(
              'Auto-rebooking option',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in widget.rebookingOptions)
                  ChoiceChip(
                    avatar: const Icon(Icons.alt_route_outlined, size: 18),
                    label: Text(option),
                    selected: _selectedOption == option,
                    onSelected: (_) => setState(() => _selectedOption = option),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _voucherReady,
            onChanged: (value) =>
                setState(() => _voucherReady = value ?? false),
            title: Text('Prepare ${widget.compensationLabel}'),
            subtitle: const Text('Attach voucher or refund offer to the case.'),
            secondary: const Icon(Icons.card_giftcard_outlined),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _selectedOption == null
                    ? null
                    : () => _queue(
                          'Rebooking queued: $_selectedOption for $_caseType.',
                        ),
                icon: const Icon(Icons.route_outlined),
                label: const Text('Queue rebooking'),
              ),
              OutlinedButton.icon(
                onPressed: _voucherReady
                    ? () => _queue(
                          '${widget.compensationLabel} queued for review.',
                        )
                    : null,
                icon: const Icon(Icons.redeem_outlined),
                label: const Text('Issue voucher'),
              ),
              OutlinedButton.icon(
                onPressed: () => _queue('Recovery case opened for $_caseType.'),
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Open case'),
              ),
              if (_requestQueued)
                Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text('Queued $_caseType'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CoachDriverAssignmentPanel extends StatefulWidget {
  final String initialDriver;
  final String initialVehicle;
  final String initialGate;

  const CoachDriverAssignmentPanel({
    super.key,
    required this.initialDriver,
    required this.initialVehicle,
    required this.initialGate,
  });

  @override
  State<CoachDriverAssignmentPanel> createState() =>
      _CoachDriverAssignmentPanelState();
}

class _CoachDriverAssignmentPanelState
    extends State<CoachDriverAssignmentPanel> {
  late final TextEditingController _driverController;
  late final TextEditingController _vehicleController;
  late final TextEditingController _gateController;
  String _status = 'Ready';
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _driverController = TextEditingController(text: widget.initialDriver);
    _vehicleController = TextEditingController(text: widget.initialVehicle);
    _gateController = TextEditingController(text: widget.initialGate);
  }

  @override
  void dispose() {
    _driverController.dispose();
    _vehicleController.dispose();
    _gateController.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _saved = true;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Driver and bus assignment saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachDriverAssignmentPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Driver and bus assignment',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth =
                  constraints.maxWidth < 720 ? constraints.maxWidth : 210.0;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _driverController,
                      decoration: const InputDecoration(
                        labelText: 'Driver',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _vehicleController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle',
                        prefixIcon: Icon(Icons.directions_bus_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: _gateController,
                      decoration: const InputDecoration(
                        labelText: 'Gate / bay',
                        prefixIcon: Icon(Icons.door_front_door_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Assignment status',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in const <String>[
                'Ready',
                'Delayed',
                'Replacement',
              ])
                ChoiceChip(
                  avatar: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(status),
                  selected: _status == status,
                  onSelected: (_) => setState(() => _status = status),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save assignment'),
              ),
              if (_saved)
                Chip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text('Saved as $_status'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CoachPerformanceMetric {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  const CoachPerformanceMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });
}

class CoachPartnerPerformancePanel extends StatelessWidget {
  final String partnerLabel;
  final List<CoachPerformanceMetric> metrics;

  const CoachPartnerPerformancePanel({
    super.key,
    this.partnerLabel = 'All coach partners',
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachPartnerPerformancePanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Partner performance dashboard',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            partnerLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: 190,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: metric.color.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: metric.color.withValues(alpha: .24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(metric.icon, color: metric.color),
                        const SizedBox(height: 8),
                        Text(
                          metric.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          metric.value,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: metric.color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(metric.detail, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class CoachNotificationInboxItem {
  final String title;
  final String audience;
  final String status;
  final String timeLabel;
  final IconData icon;

  const CoachNotificationInboxItem({
    required this.title,
    required this.audience,
    required this.status,
    required this.timeLabel,
    required this.icon,
  });
}

class CoachNotificationsInboxPanel extends StatelessWidget {
  final List<CoachNotificationInboxItem> items;

  const CoachNotificationsInboxPanel({
    super.key,
    required this.items,
  });

  Color _statusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'delivered':
      case 'opened':
        return const Color(0xFF0F766E);
      case 'failed':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFFB45309);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('coachNotificationsInboxPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coach notifications inbox',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              'No coach notifications yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
              ),
            )
          else
            for (final item in items) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _statusColor(item.status).withValues(
                    alpha: .12,
                  ),
                  child: Icon(item.icon, color: _statusColor(item.status)),
                ),
                title: Text(item.title),
                subtitle: Text('${item.audience} -> ${item.timeLabel}'),
                trailing: Chip(
                  label: Text(item.status),
                  side: BorderSide(
                    color: _statusColor(item.status).withValues(alpha: .24),
                  ),
                ),
              ),
              if (item != items.last) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class CoachApprovalQueueItem {
  final String title;
  final String detail;
  final String riskLabel;
  final IconData icon;

  const CoachApprovalQueueItem({
    required this.title,
    required this.detail,
    required this.riskLabel,
    required this.icon,
  });
}

class CoachApprovalQueuePanel extends StatefulWidget {
  final List<CoachApprovalQueueItem> items;

  const CoachApprovalQueuePanel({
    super.key,
    required this.items,
  });

  @override
  State<CoachApprovalQueuePanel> createState() =>
      _CoachApprovalQueuePanelState();
}

class _CoachApprovalQueuePanelState extends State<CoachApprovalQueuePanel> {
  final Set<int> _resolved = <int>{};

  void _resolve(int index, String action) {
    setState(() {
      _resolved.add(index);
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('$action: ${widget.items[index].title}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = widget.items.length - _resolved.length;
    return Container(
      key: const ValueKey('coachApprovalQueuePanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Approval flow',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Chip(label: Text('$pending pending')),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.items.isEmpty)
            const Text('No approvals waiting.')
          else
            for (var index = 0; index < widget.items.length; index++) ...[
              _CoachApprovalTile(
                item: widget.items[index],
                resolved: _resolved.contains(index),
                onApprove: () => _resolve(index, 'Approved'),
                onHold: () => _resolve(index, 'Put on hold'),
              ),
              if (index < widget.items.length - 1) const Divider(height: 16),
            ],
        ],
      ),
    );
  }
}

class _CoachApprovalTile extends StatelessWidget {
  final CoachApprovalQueueItem item;
  final bool resolved;
  final VoidCallback onApprove;
  final VoidCallback onHold;

  const _CoachApprovalTile({
    required this.item,
    required this.resolved,
    required this.onApprove,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: resolved ? .58 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(item.detail),
                const SizedBox(height: 6),
                Chip(label: Text(item.riskLabel)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            children: [
              IconButton(
                tooltip: 'Approve',
                onPressed: resolved ? null : onApprove,
                icon: const Icon(Icons.check_circle_outline),
              ),
              IconButton(
                tooltip: 'Hold',
                onPressed: resolved ? null : onHold,
                icon: const Icon(Icons.pause_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CoachCloseoutMetric {
  final String label;
  final String value;

  const CoachCloseoutMetric({
    required this.label,
    required this.value,
  });
}

class CoachPostTripCloseoutPanel extends StatefulWidget {
  final String tripLabel;
  final List<CoachCloseoutMetric> metrics;

  const CoachPostTripCloseoutPanel({
    super.key,
    required this.tripLabel,
    required this.metrics,
  });

  @override
  State<CoachPostTripCloseoutPanel> createState() =>
      _CoachPostTripCloseoutPanelState();
}

class _CoachPostTripCloseoutPanelState
    extends State<CoachPostTripCloseoutPanel> {
  final Set<String> _checked = <String>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const checklist = <String>[
      'Manifest reconciled',
      'No-shows confirmed',
      'Incidents attached',
      'Payout ready',
    ];
    final complete = _checked.length == checklist.length;
    return Container(
      key: const ValueKey('coachPostTripCloseoutPanel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: complete ? const Color(0xFFF0FDF4) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: complete
              ? const Color(0xFFBBF7D0)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Post-trip closeout',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Chip(label: Text(complete ? 'Ready' : '${_checked.length}/4')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.tripLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in widget.metrics)
                Chip(label: Text('${metric.label}: ${metric.value}')),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in checklist)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _checked.contains(item),
              onChanged: (value) {
                setState(() {
                  if (value ?? false) {
                    _checked.add(item);
                  } else {
                    _checked.remove(item);
                  }
                });
              },
              title: Text(item),
              dense: true,
            ),
        ],
      ),
    );
  }
}
