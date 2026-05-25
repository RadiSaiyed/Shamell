import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/main.dart' as app;

/// Hotel-Operator flavor entrypoint.
///
/// Opens the Shamell super-app with [ShamellAppSurface.hotelOperator]; the
/// surface acts as a marker for routing/branding so consumers of
/// [shamellActiveAppSurface] (e.g. analytics tags, default landing route,
/// recent-modules ordering) can react without changing the runtime shape.
///
/// The actual Hotels Admin console is the `hotels_admin` mini-program
/// registered in [MiniAppRegistry]; on this surface the home tab routes
/// straight into it, but the rest of the runtime stays available so an
/// operator can still scan QRs, look up wallets, etc.
Future<void> main() async {
  await app.runShamellApp(surface: ShamellAppSurface.hotelOperator);
}
