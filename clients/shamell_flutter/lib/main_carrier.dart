import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/main.dart' as app;

/// Carrier (Spediteur-Disponent) flavor entrypoint — SyrTrans freight
/// marketplace, supply side.
///
/// Phase 2 boots into a minimal [CarrierConsolePage] that proves the
/// mobile ↔ BFF ↔ freight_service chain (health probe). Real fleet
/// management UI (organizations, vehicles, trailers, cooling units,
/// drivers, certificates) lands in Phase 3 alongside the BFF carrier
/// endpoints; this scaffold is here so the build pipeline, signing,
/// and Discover-tile entry are in place ahead of feature work.
///
/// Mirror of `main_hotel_operator.dart` — same flavor pattern, same
/// surface routing in `shamellBuildSignedInHome`.
Future<void> main() async {
  await app.runShamellApp(surface: ShamellAppSurface.carrier);
}
