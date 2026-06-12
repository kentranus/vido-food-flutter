// Business hours dropdown (Google-Business style) — helper tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:vido_food_app/pos/settings_screen.dart';

void main() {
  test('48 mốc 30 phút, đủ 24h, format HH:mm', () {
    final opts = hoursTimeOptions('09:00');
    expect(opts.length, 48);
    expect(opts.first, '00:00');
    expect(opts.last, '23:30');
    expect(opts.contains('09:00'), isTrue);
    expect(opts.contains('21:30'), isTrue);
  });

  test('giá trị lẻ từ picker cũ (09:15) được giữ + đúng vị trí sort', () {
    final opts = hoursTimeOptions('09:15');
    expect(opts.length, 49);
    expect(opts.indexOf('09:15'), opts.indexOf('09:00') + 1);
  });

  test('label 12h kiểu Google: 9:00 AM / 12:00 PM / 12:00 AM / 11:30 PM', () {
    expect(hoursLabel12('09:00'), '9:00 AM');
    expect(hoursLabel12('12:00'), '12:00 PM');
    expect(hoursLabel12('00:00'), '12:00 AM');
    expect(hoursLabel12('23:30'), '11:30 PM');
    expect(hoursLabel12('rác'), 'rác'); // không crash
  });
}

// acceptPrint flag — default ON (giữ hành vi cũ), tắt được.
// (đặt chung file test settings cho gọn)
