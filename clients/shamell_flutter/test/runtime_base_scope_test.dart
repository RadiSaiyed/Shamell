import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/runtime_base_scope.dart';

void main() {
  test('resolve runtime base url prefers active normalized base', () {
    expect(
      shamellResolveRuntimeBaseUrl(
        storedBaseUrl: 'https://api.shamell.online',
        activeBaseUrl: 'https://api.example.com',
      ),
      'https://api.example.com',
    );
  });

  test('resolve runtime base url falls back when stored base is invalid', () {
    expect(
      shamellResolveRuntimeBaseUrl(
        storedBaseUrl: 'https://api.shamell.online:0',
      ),
      'https://api.shamell.online',
    );
  });
}
