// D5 — receipt payment-line composer: đúng từng dòng cho 4 kịch bản.
// Composer này được dùng cho CẢ bản in (printer.dart) lẫn dialog (order_view).
import 'package:flutter_test/flutter_test.dart';
import 'package:vido_food_app/printer.dart';

void main() {
  test('1. FULL gift-card payment', () {
    final rows = receiptPaymentLines(
        paymentMethod: 'giftcard', total: 20.0,
        giftCodeMasked: 'VG-****-H4B3', giftApplied: 20.0, giftRemaining: 30.0);
    expect(rows, [
      ['Gift Card VG-****-H4B3', '-\$20.00'],
      ['Total Paid', '\$20.00'],
      ['Remaining Gift Card Balance', '\$30.00'],
      ['Paid', 'GIFT CARD'],
    ]);
  });

  test('2. PARTIAL gift + cash (đưa đủ, không thối)', () {
    final rows = receiptPaymentLines(
        paymentMethod: 'cash', total: 40.0, cashReceived: 15.0, change: 0,
        giftCodeMasked: 'VG-****-H4B3', giftApplied: 25.0, giftRemaining: 0.0);
    expect(rows, [
      ['Gift Card VG-****-H4B3', '-\$25.00'],
      ['Cash', '\$15.00'],
      ['Total Paid', '\$40.00'],
      ['Remaining Gift Card Balance', '\$0.00'],
      ['Paid', 'GIFT CARD + CASH'],
    ]);
  });

  test('2b. PARTIAL gift + cash có tiền thối', () {
    final rows = receiptPaymentLines(
        paymentMethod: 'cash', total: 40.0, cashReceived: 20.0, change: 5.0,
        giftCodeMasked: 'VG-****-H4B3', giftApplied: 25.0, giftRemaining: 0.0);
    expect(rows[1], ['Cash', '\$15.00']);     // phần còn thiếu
    expect(rows[2], ['Change', '\$5.00']);    // thối lại
  });

  test('3. PARTIAL gift + card', () {
    final rows = receiptPaymentLines(
        paymentMethod: 'card', total: 40.0,
        giftCodeMasked: 'VG-****-H4B3', giftApplied: 25.0, giftRemaining: 10.0);
    expect(rows, [
      ['Gift Card VG-****-H4B3', '-\$25.00'],
      ['Card', '\$15.00'],
      ['Total Paid', '\$40.00'],
      ['Remaining Gift Card Balance', '\$10.00'],
      ['Paid', 'GIFT CARD + CARD'],
    ]);
  });

  test('4. KHÔNG gift — layout cũ giữ nguyên (cash)', () {
    final rows = receiptPaymentLines(paymentMethod: 'cash', total: 12.0, cashReceived: 20.0, change: 8.0);
    expect(rows, [
      ['Paid', 'CASH'],
      ['Cash', '\$20.00'],
      ['Change', '\$8.00'],
    ]);
  });

  test('4b. KHÔNG gift — card layout cũ', () {
    final rows = receiptPaymentLines(paymentMethod: 'card', total: 12.0);
    expect(rows, [['Paid', 'CARD']]);
  });

  test('an toàn: gift removed/failed (giftApplied=0) → không dòng gift nào', () {
    final rows = receiptPaymentLines(paymentMethod: 'cash', total: 12.0, cashReceived: 12.0, giftCodeMasked: 'VG-****-H4B3', giftApplied: 0);
    expect(rows.any((r) => r[0].contains('Gift')), isFalse);
  });

  test('an toàn: không bao giờ chứa full code (composer chỉ in chuỗi caller đưa, app luôn đưa masked)', () {
    final rows = receiptPaymentLines(paymentMethod: 'giftcard', total: 5, giftCodeMasked: 'VG-****-H4B3', giftApplied: 5, giftRemaining: 0);
    expect(rows.toString().contains('****'), isTrue);
  });
}
