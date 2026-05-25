import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/shamell_support.dart';

void main() {
  test('support email uri stays canonical and encodes subject', () {
    final uri = shamellSupportEmailUri(subject: 'SyrChat Feedback');

    expect(uri.toString(),
        'mailto:radisaiyed@icloud.com?subject=SyrChat+Feedback');
    expect(uri.path, kShamellSupportEmail);
  });

  test('support phone uri stays canonical', () {
    final uri = shamellSupportPhoneUri();

    expect(uri.toString(), 'tel:+963996428955');
    expect(uri.path, kShamellSupportPhone);
  });
}
