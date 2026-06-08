import 'package:flutter_test/flutter_test.dart';
import 'package:vido_food_app/theme.dart';

void main() {
  test('money formats USD', () {
    expect(money(5.5), '\$5.50');
    expect(money(0), '\$0.00');
  });

  test('columnOf routes orders correctly', () {
    expect(columnOf('pending_accept', 'Online'), 'new');
    expect(columnOf('new', 'Kiosk'), 'preparing'); // kiosk pre-paid skips NEW
    expect(columnOf('accepted', 'Online'), 'preparing');
    expect(columnOf('ready', 'Online'), 'ready');
    expect(columnOf('completed', 'Online'), null);
  });
}
