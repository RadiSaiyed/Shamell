import 'package:shamell_flutter/core/app_surface.dart';
import 'package:shamell_flutter/main.dart' as app;

Future<void> main() async {
  await app.runShamellApp(surface: ShamellAppSurface.taxiOperator);
}
