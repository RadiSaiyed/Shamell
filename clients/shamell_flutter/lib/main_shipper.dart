import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/main.dart' as app;

/// Cycle 206 — Shipper (Verlader) flavor entrypoint. SyrTrans
/// marketplace, demand side: posts loads, watches bids inbox, sees
/// cold-chain telemetry from carrier vehicles.
///
/// Mirrors `main_carrier.dart` — same flavor pattern, same surface
/// routing in `shamellBuildSignedInHome`. Uses the carrier role under
/// the hood (`freight.carrier_admin`); freight_organizations.org_kind
/// distinguishes shipper vs carrier actions.
Future<void> main() async {
  await app.runShamellApp(surface: ShamellAppSurface.shipper);
}
