import '../menu.dart';

/// Default menu seed — faithful port of React data/defaultMenu.js.
/// Used as the offline-first fallback when the cloud menu is empty
/// (mirrors React menuStorage: ship DEFAULT_MENU, override from cloud).
const List<MenuCategory> kDefaultCategories = [
  MenuCategory('milk-tea', 'Milk Tea', '🧋'),
  MenuCategory('fruit-tea', 'Fruit Tea', '🍑'),
  MenuCategory('coffee', 'Coffee', '☕'),
  MenuCategory('smoothie', 'Smoothies', '🥤'),
  MenuCategory('snack', 'Snacks', '🥐'),
  MenuCategory('topping', 'Toppings', '🟤'),
];

MenuItem _i(String id, String cat, String name, double price, String emoji, {bool popular = false}) =>
    MenuItem(id: id, name: name, icon: emoji, category: cat, price: price,
        available: true, is86d: false, popular: popular, modifierGroupIds: const []);

final List<MenuItem> kDefaultMenu = [
  // milk tea
  _i('classic', 'milk-tea', 'Classic Milk Tea', 5.50, '🧋'),
  _i('brown-sugar', 'milk-tea', 'Brown Sugar Boba', 6.75, '🧋', popular: true),
  _i('oolong', 'milk-tea', 'Oolong Milk Tea', 5.75, '🧋'),
  _i('matcha', 'milk-tea', 'Matcha Latte', 6.25, '🍵'),
  _i('thai', 'milk-tea', 'Thai Milk Tea', 5.75, '🧋', popular: true),
  _i('taro', 'milk-tea', 'Taro Milk Tea', 6.25, '🧋'),
  _i('jasmine', 'milk-tea', 'Jasmine Milk Tea', 5.75, '🌼'),
  _i('honeydew', 'milk-tea', 'Honeydew Milk Tea', 6.00, '🍈'),
  // fruit tea
  _i('mango', 'fruit-tea', 'Mango Green Tea', 5.75, '🥭'),
  _i('strawberry', 'fruit-tea', 'Strawberry Tea', 6.25, '🍓'),
  _i('passion', 'fruit-tea', 'Passion Fruit', 5.95, '🍊'),
  _i('lychee', 'fruit-tea', 'Lychee Tea', 5.95, '🌸'),
  // coffee
  _i('latte', 'coffee', 'Latte', 5.50, '☕'),
  _i('iced-coffee', 'coffee', 'Iced Coffee', 4.95, '☕'),
  _i('viet-coffee', 'coffee', 'Vietnamese Coffee', 5.25, '☕', popular: true),
  // smoothie
  _i('mango-sm', 'smoothie', 'Mango Smoothie', 6.50, '🥤'),
  _i('straw-sm', 'smoothie', 'Strawberry Smoothie', 6.50, '🥤'),
  // snack
  _i('waffle', 'snack', 'Bubble Waffle', 5.50, '🧇'),
  _i('mochi', 'snack', 'Mochi (3 pcs)', 4.25, '🍡'),
  // toppings (add-ons, shown in the customize sheet)
  _i('tapioca', 'topping', 'Tapioca Pearls', 0.75, '⚫'),
  _i('cheese-foam', 'topping', 'Cheese Foam', 1.25, '🧀'),
  _i('aloe', 'topping', 'Aloe Vera', 0.75, '🟢'),
  _i('jelly', 'topping', 'Lychee Jelly', 0.75, '🟣'),
  _i('pudding', 'topping', 'Egg Pudding', 0.95, '🟡'),
];
