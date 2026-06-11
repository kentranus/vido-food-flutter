import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Order entry models — faithful port of React OrderView helpers
/// (emptyOrder / calcLineTotal / calcOrderTotals / ORDER_TYPES).

class OrderType {
  final String id, label, icon;
  const OrderType(this.id, this.label, this.icon);
}

const List<OrderType> kOrderTypes = [
  OrderType('dinein', 'Dine In', '🏠'),
  OrderType('togo', 'To Go', '📦'),
  OrderType('delivery', 'Delivery', '🚚'),
];

OrderType orderTypeOf(String id) => kOrderTypes.firstWhere((t) => t.id == id, orElse: () => kOrderTypes[1]);

/// Shop pricing config (tax + large-size upcharge), loaded from settings.
class ShopConfig {
  static double tax = 0.0875; // 8.75% default
  static double sizeLargeBonus = 0.75;
  static String currencySymbol = '\$';
}

String money(num n) => '${ShopConfig.currencySymbol}${(n).toStringAsFixed(2)}';

class Topping {
  final String id, name;
  final double price;
  const Topping(this.id, this.name, this.price);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'price': price};
  factory Topping.fromJson(Map<String, dynamic> j) => Topping((j['id'] ?? '').toString(), (j['name'] ?? '').toString(), (j['price'] ?? 0).toDouble());
}

class CartLine {
  final String id, productId, name, emoji, category;
  String size; // 'R' | 'L'
  int sugar, ice, qty;
  List<Topping> toppings;
  final double basePrice;
  CartLine({
    required this.id, required this.productId, required this.name, required this.emoji, required this.category,
    this.size = 'R', this.sugar = 100, this.ice = 100, this.qty = 1, List<Topping>? toppings, required this.basePrice,
  }) : toppings = toppings ?? [];

  double get lineTotal {
    var p = basePrice;
    if (size == 'L') p += ShopConfig.sizeLargeBonus;
    p += toppings.fold(0.0, (s, t) => s + t.price);
    return p * qty;
  }

  bool get isSimple => category == 'snack' || category == 'topping';
}

class Order {
  final String id;
  final int number;
  String type;
  List<CartLine> items;
  double discount;
  String discountType; // 'amount' | 'percent'
  String note;
  final String createdAt;
  String status;
  Order({required this.id, required this.number, this.type = 'togo', List<CartLine>? items,
    this.discount = 0, this.discountType = 'amount', this.note = '', required this.createdAt, this.status = 'open'})
      : items = items ?? [];

  // ---- Gift card tender áp vào đơn (POS D4) ----
  // giftCode FULL chỉ giữ trong RAM để refund khi remove/fail — không in/log.
  String? giftCode;
  String? giftCodeMasked;
  double giftApplied = 0;
  double giftRemaining = 0; // balance thẻ còn lại sau redeem
  String? giftRef;          // idempotency key (redeem + refund cùng ref)
  double get due => (totals.total - giftApplied).clamp(0, double.infinity).toDouble();
  void clearGift() { giftCode = null; giftCodeMasked = null; giftApplied = 0; giftRemaining = 0; giftRef = null; }

  ({double sub, double discount, double taxable, double tax, double total}) get totals {
    final sub = items.fold(0.0, (s, l) => s + l.lineTotal);
    var disc = 0.0;
    if (discount > 0) {
      disc = discountType == 'percent' ? sub * (discount / 100) : discount;
      if (disc > sub) disc = sub;
    }
    final taxable = sub - disc;
    final tax = taxable * ShopConfig.tax;
    return (sub: sub, discount: disc, taxable: taxable, tax: tax, total: taxable + tax);
  }
}

/// Local order-number counter (mirrors orderStorage nextOrderNumber).
class OrderCounter {
  static const _key = 'vido_order_counter';
  static int _next = 0;
  static Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _next = sp.getInt(_key) ?? 1001;
  }
  static int next() {
    final n = _next;
    _next += 1;
    SharedPreferences.getInstance().then((sp) => sp.setInt(_key, _next));
    return n;
  }
}

Order emptyOrder() => Order(
      id: 'O${DateTime.now().microsecondsSinceEpoch}',
      number: OrderCounter.next(),
      createdAt: DateTime.now().toIso8601String(),
    );

/// Deterministic colourful gradient per product (React products carry a
/// per-item gradient; we derive one from the name so cards look the same kind).
LinearGradient gradientFor(String seed) {
  const palettes = [
    [Color(0xFFFF9A3C), Color(0xFFFF6A00)],
    [Color(0xFF60A5FA), Color(0xFF2563EB)],
    [Color(0xFF34D399), Color(0xFF059669)],
    [Color(0xFFF472B6), Color(0xFFDB2777)],
    [Color(0xFFA78BFA), Color(0xFF7C3AED)],
    [Color(0xFF22D3EE), Color(0xFF0891B2)],
    [Color(0xFFFBBF24), Color(0xFFF59E0B)],
    [Color(0xFFFB7185), Color(0xFFE11D48)],
  ];
  var h = 0;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final p = palettes[h % palettes.length];
  return LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p);
}

// Lightweight JSON for persisting a completed order to /api/orders later.
// giftCode (MASKED) + giftApplied: chỉ để history/reports — không gửi full code.
Map<String, dynamic> orderToApi(Order o, {String? paymentMethod, double tip = 0, String? giftCode, double? giftApplied}) => {
      if (giftCode != null && giftCode.isNotEmpty) 'giftCode': giftCode,
      if (giftApplied != null && giftApplied > 0) 'giftApplied': giftApplied,
      'number': o.number,
      'type': o.type,
      'orderType': o.type.toUpperCase(),
      'note': o.note,
      'discount': o.discount,
      'subtotal': o.totals.sub,
      'tax': o.totals.tax,
      'total': o.totals.total + tip,
      'tip': tip,
      'paymentMethod': paymentMethod,
      'items': o.items.map((l) => {
            'nameSnapshot': l.name, 'name': l.name, 'quantity': l.qty, 'qty': l.qty,
            'priceSnapshot': l.basePrice, 'lineTotal': l.lineTotal, 'category': l.category,
            'size': l.size, 'sugar': l.sugar, 'ice': l.ice,
            'modifiers': l.toppings.map((t) => {'optionName': t.name, 'name': t.name, 'priceDelta': t.price}).toList(),
          }).toList(),
    };

String encodeOrders(List<Order> _) => jsonEncode([]); // reserved
