import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/coach_bus/coach_admin_partner_onboarding_page.dart';
import 'package:shamell_flutter/core/coach_bus/coach_mobility_api.dart';

Future<void> _dragUntilVisible(
  WidgetTester tester,
  Finder finder,
) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
}

void configureLargeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1400, 3200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

CoachAdminPartnerOnboardingRecord _buildPartner({
  required String operatorId,
  required String operatorName,
  required String workflowStatus,
  required int missingDocuments,
  required int expiringDocuments,
  required String nextAction,
  String integrationMode = 'feed_only',
  String? ownerAccountId = 'acct_partner_ops_demo',
  String dueAtIso = '2026-04-18T10:00:00Z',
  int degradedFeeds = 1,
  int staleFeeds = 1,
  int pendingCapabilities = 1,
  List<String> blockers = const <String>[
    'vehicle positions not exposed by feed-only operator',
  ],
}) {
  final capabilities = <CoachAdminPartnerOnboardingCapability>[
    const CoachAdminPartnerOnboardingCapability(
      capability: 'catalog_ingest',
      label: 'Catalog ingest',
      status: 'enabled',
    ),
    for (var index = 0; index < pendingCapabilities; index++)
      CoachAdminPartnerOnboardingCapability(
        capability: 'pending_$index',
        label: 'Pending capability $index',
        status: 'pending',
      ),
    if (pendingCapabilities == 0)
      const CoachAdminPartnerOnboardingCapability(
        capability: 'ticketing',
        label: 'Ticketing finalize',
        status: 'enabled',
      ),
  ];

  return CoachAdminPartnerOnboardingRecord(
    operatorId: operatorId,
    operatorName: operatorName,
    integrationMode: integrationMode,
    workflowStatus: workflowStatus,
    lastAction: workflowStatus == 'approved' ? 'approve' : 'request_documents',
    ownerAccountId: ownerAccountId,
    dueAtIso: dueAtIso,
    updatedAtIso: '2026-04-14T10:00:00Z',
    updatedByAccountId: 'acct_partner_ops_demo',
    note: workflowStatus == 'approved'
        ? 'Approved after receiving corrected onboarding packet.'
        : 'Waiting for corrected insurance certificate.',
    missingDocuments: missingDocuments,
    expiringDocuments: expiringDocuments,
    feedSummary: CoachAdminPartnerOnboardingFeedSummary(
      feedsTotal: 3,
      degradedFeeds: degradedFeeds,
      staleFeeds: staleFeeds,
      lastSucceededAtIso: degradedFeeds == 0 && staleFeeds == 0
          ? '2026-04-14T09:10:00Z'
          : '2026-04-14T08:30:00Z',
    ),
    documents: <CoachAdminPartnerOnboardingDocument>[
      const CoachAdminPartnerOnboardingDocument(
        documentId: 'doc_contract',
        documentKey: 'commercial_contract',
        label: 'Commercial contract',
        status: 'approved',
        required: true,
        expiresAtIso: '2026-10-31T00:00:00Z',
      ),
      CoachAdminPartnerOnboardingDocument(
        documentId: 'doc_kyb_$operatorId',
        documentKey: 'kyb_packet',
        label: 'KYB packet',
        status: missingDocuments == 0 ? 'approved' : 'in_review',
        required: true,
        expiresAtIso: null,
      ),
      CoachAdminPartnerOnboardingDocument(
        documentId: 'doc_insurance_$operatorId',
        documentKey: 'insurance_certificate',
        label: 'Insurance certificate',
        status: expiringDocuments > 0 ? 'expiring' : 'approved',
        required: true,
        expiresAtIso: expiringDocuments > 0 ? '2026-04-30T00:00:00Z' : null,
      ),
      CoachAdminPartnerOnboardingDocument(
        documentId: 'doc_bank_$operatorId',
        documentKey: 'settlement_bank_proof',
        label: 'Settlement bank proof',
        status: missingDocuments > 0 ? 'missing' : 'approved',
        required: true,
        expiresAtIso: null,
      ),
    ],
    capabilities: capabilities,
    checklist: <CoachAdminPartnerOnboardingChecklistItem>[
      const CoachAdminPartnerOnboardingChecklistItem(
        itemKey: 'owner',
        label: 'Owner assigned',
        status: 'done',
      ),
      CoachAdminPartnerOnboardingChecklistItem(
        itemKey: 'sandbox',
        label: 'Partner certification',
        status: workflowStatus == 'approved' || blockers.isEmpty
            ? 'done'
            : 'blocked',
      ),
    ],
    blockers: blockers,
    nextAction: nextAction,
  );
}

class _FakeCoachPartnerOnboardingApi extends CoachMobilityApi {
  _FakeCoachPartnerOnboardingApi({
    List<CoachAdminPartnerOnboardingRecord>? partners,
  })  : _partners = List<CoachAdminPartnerOnboardingRecord>.from(
          partners ??
              <CoachAdminPartnerOnboardingRecord>[
                _buildPartner(
                  operatorId: 'op_northern_connector',
                  operatorName: 'Northern Connector',
                  workflowStatus: 'action_required',
                  missingDocuments: 2,
                  expiringDocuments: 0,
                  nextAction:
                      'Request corrected documents and rerun certification',
                ),
              ],
        ),
        super(baseUrl: 'https://api.shamell.online');

  int onboardingCalls = 0;
  int actionCalls = 0;
  final List<CoachAdminPartnerOnboardingRecord> _partners;

  CoachAdminPartnerOnboardingSummary _summaryFor(
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

  CoachAdminPartnerOnboardingResponse _responseFor(
    List<CoachAdminPartnerOnboardingRecord> partners,
  ) {
    return CoachAdminPartnerOnboardingResponse(
      generatedAtIso: '2026-04-14T10:00:00Z',
      summary: _summaryFor(partners),
      partners: partners,
    );
  }

  @override
  Future<CoachAdminPartnerOnboardingResponse> adminPartnerOnboarding({
    String? query,
    String? workflowStatus,
    int limit = 20,
  }) async {
    onboardingCalls++;
    final normalizedQuery = query?.trim().toLowerCase() ?? '';
    final filtered = _partners
        .where((partner) {
          if (workflowStatus != null &&
              workflowStatus.trim().isNotEmpty &&
              partner.workflowStatus != workflowStatus) {
            return false;
          }
          if (normalizedQuery.isEmpty) {
            return true;
          }
          return partner.operatorName.toLowerCase().contains(normalizedQuery) ||
              partner.operatorId.toLowerCase().contains(normalizedQuery) ||
              partner.nextAction.toLowerCase().contains(normalizedQuery);
        })
        .take(limit)
        .toList(growable: false);
    return _responseFor(filtered);
  }

  @override
  Future<CoachAdminPartnerOnboardingMutationResult>
      adminPartnerOnboardingAction({
    required String operatorId,
    required String action,
    String? ownerAccountId,
    String? dueAtIso,
    String? note,
    String? idempotencyKey,
  }) async {
    actionCalls++;
    final index = _partners.indexWhere(
      (partner) => partner.operatorId == operatorId,
    );
    final current = _partners[index];
    final updated = switch (action) {
      'approve' => _buildPartner(
          operatorId: current.operatorId,
          operatorName: current.operatorName,
          workflowStatus: 'approved',
          missingDocuments: 0,
          expiringDocuments: 1,
          nextAction: 'Monitor feed health and renewal dates',
          integrationMode: current.integrationMode,
          ownerAccountId: current.ownerAccountId,
          dueAtIso: current.dueAtIso ?? '2026-04-18T10:00:00Z',
          degradedFeeds: current.feedSummary.degradedFeeds,
          staleFeeds: current.feedSummary.staleFeeds,
          pendingCapabilities: 0,
          blockers: const <String>[],
        ),
      'start_review' => _buildPartner(
          operatorId: current.operatorId,
          operatorName: current.operatorName,
          workflowStatus: 'in_review',
          missingDocuments: current.missingDocuments,
          expiringDocuments: current.expiringDocuments,
          nextAction: current.nextAction,
          integrationMode: current.integrationMode,
          ownerAccountId: ownerAccountId ?? current.ownerAccountId,
          dueAtIso: dueAtIso ?? current.dueAtIso ?? '2026-04-18T10:00:00Z',
          degradedFeeds: current.feedSummary.degradedFeeds,
          staleFeeds: current.feedSummary.staleFeeds,
          pendingCapabilities: current.pendingCapabilities,
          blockers: current.blockers,
        ),
      'claim' => _buildPartner(
          operatorId: current.operatorId,
          operatorName: current.operatorName,
          workflowStatus: current.workflowStatus,
          missingDocuments: current.missingDocuments,
          expiringDocuments: current.expiringDocuments,
          nextAction: current.nextAction,
          integrationMode: current.integrationMode,
          ownerAccountId: ownerAccountId ?? 'acct_partner_ops_demo',
          dueAtIso: dueAtIso ?? current.dueAtIso ?? '2026-04-18T10:00:00Z',
          degradedFeeds: current.feedSummary.degradedFeeds,
          staleFeeds: current.feedSummary.staleFeeds,
          pendingCapabilities: current.pendingCapabilities,
          blockers: current.blockers,
        ),
      'suspend' => _buildPartner(
          operatorId: current.operatorId,
          operatorName: current.operatorName,
          workflowStatus: 'suspended',
          missingDocuments: current.missingDocuments,
          expiringDocuments: current.expiringDocuments,
          nextAction: current.nextAction,
          integrationMode: current.integrationMode,
          ownerAccountId: current.ownerAccountId,
          dueAtIso: current.dueAtIso ?? '2026-04-18T10:00:00Z',
          degradedFeeds: current.feedSummary.degradedFeeds,
          staleFeeds: current.feedSummary.staleFeeds,
          pendingCapabilities: current.pendingCapabilities,
          blockers: current.blockers,
        ),
      _ => _buildPartner(
          operatorId: current.operatorId,
          operatorName: current.operatorName,
          workflowStatus: 'action_required',
          missingDocuments: current.missingDocuments,
          expiringDocuments: current.expiringDocuments,
          nextAction: 'Request corrected documents and rerun certification',
          integrationMode: current.integrationMode,
          ownerAccountId: current.ownerAccountId,
          dueAtIso: current.dueAtIso ?? '2026-04-18T10:00:00Z',
          degradedFeeds: current.feedSummary.degradedFeeds,
          staleFeeds: current.feedSummary.staleFeeds,
          pendingCapabilities: current.pendingCapabilities,
          blockers: current.blockers,
        ),
    };
    _partners[index] = updated;
    return CoachAdminPartnerOnboardingMutationResult(
      operatorId: operatorId,
      action: action,
      updatedAtIso: '2026-04-14T10:05:00Z',
      partner: updated,
    );
  }
}

void main() {
  testWidgets(
    'coach admin partner onboarding page renders and applies approval action',
    (tester) async {
      configureLargeViewport(tester);
      final api = _FakeCoachPartnerOnboardingApi();

      await tester.pumpWidget(
        MaterialApp(
          home: CoachAdminPartnerOnboardingPage(
            baseUrl: 'https://api.shamell.online',
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.onboardingCalls, 1);
      expect(find.text('Partner onboarding'), findsOneWidget);
      expect(find.text('Partner readiness desk'), findsOneWidget);
      expect(find.text('Northern Connector'), findsOneWidget);
      expect(find.textContaining('Action required 1'), findsWidgets);
      expect(find.textContaining('Missing docs 2'), findsWidgets);

      final approveButton = find.widgetWithText(FilledButton, 'Approve');
      await _dragUntilVisible(tester, approveButton);
      await tester.tap(approveButton);
      await tester.pumpAndSettle();

      expect(api.actionCalls, 1);
      expect(find.text('Approved'), findsWidgets);
      expect(find.textContaining('missing 0'), findsOneWidget);
      expect(
        find.text('Monitor feed health and renewal dates'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'coach admin partner onboarding page filters local queues and sorts by due date',
    (tester) async {
      configureLargeViewport(tester);
      final api = _FakeCoachPartnerOnboardingApi(
        partners: <CoachAdminPartnerOnboardingRecord>[
          _buildPartner(
            operatorId: 'op_northern_connector',
            operatorName: 'Northern Connector',
            workflowStatus: 'action_required',
            missingDocuments: 2,
            expiringDocuments: 0,
            nextAction: 'Request corrected documents and rerun certification',
            dueAtIso: '2026-04-18T10:00:00Z',
            degradedFeeds: 1,
            staleFeeds: 1,
            pendingCapabilities: 1,
          ),
          _buildPartner(
            operatorId: 'op_desert_lines',
            operatorName: 'Desert Lines',
            workflowStatus: 'in_review',
            missingDocuments: 0,
            expiringDocuments: 1,
            nextAction: 'Review expiring insurance certificate',
            dueAtIso: '2026-04-19T10:00:00Z',
            degradedFeeds: 0,
            staleFeeds: 0,
            pendingCapabilities: 0,
            blockers: const <String>[],
          ),
          _buildPartner(
            operatorId: 'op_city_link',
            operatorName: 'City Link',
            workflowStatus: 'in_review',
            missingDocuments: 0,
            expiringDocuments: 0,
            nextAction: 'Approve launch checklist and open production routing',
            dueAtIso: '2026-04-17T09:00:00Z',
            degradedFeeds: 0,
            staleFeeds: 0,
            pendingCapabilities: 0,
            blockers: const <String>[],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CoachAdminPartnerOnboardingPage(
            baseUrl: 'https://api.shamell.online',
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Partner readiness desk'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('coachPartnerFocus_ready')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Showing 1 of 3 operators'), findsOneWidget);
      expect(find.text('City Link'), findsOneWidget);
      expect(find.text('Northern Connector'), findsNothing);
      expect(find.text('Desert Lines'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All (3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Due first'));
      await tester.pumpAndSettle();

      final cityLinkCard = find.byKey(
        const ValueKey('coachPartnerCard_op_city_link'),
      );
      final northernCard = find.byKey(
        const ValueKey('coachPartnerCard_op_northern_connector'),
      );

      expect(
        tester.getTopLeft(cityLinkCard).dy,
        lessThan(tester.getTopLeft(northernCard).dy),
      );
      expect(find.textContaining('Showing 3 of 3 operators'), findsOneWidget);
    },
  );
}
