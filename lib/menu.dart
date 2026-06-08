import 'api.dart';

class MenuCategory {
  final String id;
  final String name;
  const MenuCategory(this.id, this.name);
}

class ModOption {
  final String id, name;
  final double priceDelta;
  ModOption(this.id, this.name, this.priceDelta);
}

class ModGroup {
  final String id, name;
  final List<ModOption> options;
  ModGroup(this.id, this.name, this.options);
}

class MenuItem {
  final String id, name, icon, category;
  final double price;
  final bool available, is86d, popular;
  final List<String> modifierGroupIds;
  MenuItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    required this.price,
    required this.available,
    required this.is86d,
    required this.popular,
    required this.modifierGroupIds,
  });
  bool get sellable => available && !is86d;
}

/// Loads the live menu + tax rate from the shared backend.
class MenuRepo {
  List<MenuCategory> categories = [];
  List<MenuItem> items = [];
  Map<String, ModGroup> groups = {};
  Map<String, dynamic> raw = {}; // full menu JSON, for lossless round-trip (86 toggle)
  double taxRate = 0;
  bool loaded = false;

  static double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  Future<void> load() async {
    final m = await Api.instance.getMenu();
    if (m['ok'] == true && m['menu'] != null) {
      final menu = Map<String, dynamic>.from(m['menu']);
      raw = menu;
      categories = ((menu['categories'] ?? []) as List)
          .map((c) => MenuCategory((c['id'] ?? '').toString(), (c['name'] ?? '').toString()))
          .toList();
      items = ((menu['items'] ?? []) as List).map((e) {
        final i = Map<String, dynamic>.from(e);
        return MenuItem(
          id: (i['id'] ?? '').toString(),
          name: (i['name'] ?? '').toString(),
          icon: (i['icon'] ?? '🍵').toString(),
          category: (i['category'] ?? '').toString(),
          price: _d(i['price']),
          available: i['available'] != false,
          is86d: i['is86d'] == true,
          popular: i['popular'] == true,
          modifierGroupIds: ((i['modifierGroupIds'] ?? []) as List).map((x) => x.toString()).toList(),
        );
      }).toList();
      groups = {
        for (final g in ((menu['modifierGroups'] ?? []) as List).map((e) => Map<String, dynamic>.from(e)))
          (g['id'] ?? '').toString(): ModGroup(
            (g['id'] ?? '').toString(),
            (g['name'] ?? '').toString(),
            ((g['options'] ?? []) as List)
                .map((o) => ModOption((o['id'] ?? '').toString(), (o['name'] ?? '').toString(), _d(o['priceDelta'])))
                .toList(),
          ),
      };
    }
    final s = await Api.instance.getSettings();
    if (s['ok'] == true) {
      taxRate = _d(Map<String, dynamic>.from(s['settings'] ?? {})['shop']?['taxRate']);
    }
    loaded = true;
  }

  /// Toggle "86 / sold out" for an item and persist the full menu (lossless).
  Future<bool> set86(String itemId, bool is86d) async {
    final rawItems = (raw['items'] ?? []) as List;
    for (final it in rawItems) {
      if ((it['id'] ?? '').toString() == itemId) it['is86d'] = is86d;
    }
    final idx = items.indexWhere((i) => i.id == itemId);
    if (idx >= 0) {
      final old = items[idx];
      items[idx] = MenuItem(id: old.id, name: old.name, icon: old.icon, category: old.category,
          price: old.price, available: old.available, is86d: is86d, popular: old.popular, modifierGroupIds: old.modifierGroupIds);
    }
    final r = await Api.instance.saveMenu({
      'categories': raw['categories'] ?? [],
      'items': rawItems,
      'modifierGroups': raw['modifierGroups'] ?? [],
    });
    return r['ok'] == true;
  }
}

/// One line in the counter cart.
class CartLine {
  final MenuItem item;
  int qty;
  final List<ModOption> mods; // chosen options across groups
  String note;
  CartLine(this.item, {this.qty = 1, List<ModOption>? mods, this.note = ''}) : mods = mods ?? [];
  double get unit => item.price + mods.fold(0.0, (s, m) => s + m.priceDelta);
  double get lineTotal => unit * qty;
  String get modText => mods.map((m) => m.name).join(', ');
}
