import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/devices_page.dart';

void main() {
  test('devices web desktop url derives canonical first-party targets', () {
    expect(
      shamellDevicesWebDesktopUrl('https://api.shamell.online'),
      Uri.parse('https://online.shamell.online/'),
    );
    expect(
      shamellDevicesWebDesktopUrl('https://staging-api.shamell.online'),
      Uri.parse('https://online.shamell.online/'),
    );
    expect(
      shamellDevicesWebDesktopUrl('http://127.0.0.1:8080'),
      Uri.parse('http://127.0.0.1:8080/auth/device_login'),
    );
  });

  test('devices web desktop url rejects credentialed or invalid bases', () {
    expect(
      shamellDevicesWebDesktopUrl('https://evil.test@api.shamell.online'),
      isNull,
    );
    expect(
      shamellDevicesWebDesktopUrl('https://api.shamell.online/path?x=1'),
      isNull,
    );
    expect(
      shamellDevicesWebDesktopUrl('mailto:test@example.com'),
      isNull,
    );
  });
}
