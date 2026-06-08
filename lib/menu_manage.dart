import 'package:flutter/material.dart';
import 'menu.dart';
import 'theme.dart';

/// Menu management — add / edit / delete items + price + category + availability.
/// Edits round-trip the full menu to the backend (POS, kiosk + web see it live).
class MenuManageScreen extends StatefulWidget {
  const MenuManageScreen({super.key});
  @override
  State<MenuManageScreen> createState() => _MenuManageScreenState();
}

class _MenuManageScreenState extends State<MenuManageScreen> {
  final repo = MenuRepo();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    repo.load().then((_) { if (mounted) setState(() => _loading = false); });
  }

  Future<void> _edit([MenuItem? item]) async {
    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _ItemEditor(item: item, categories: repo.categories),
    );
    if (res == null) return;
    setState(() => _saving = true);
    final ok = await repo.upsertItem(res);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Saved' : 'Save failed'), backgroundColor: ok ? C.green : C.red));
  }

  Future<void> _delete(MenuItem it) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text('Delete "${it.name}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: C.red))),
      ]));
    if (ok != true) return;
    setState(() => _saving = true);
    await repo.deleteItem(it.id);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(backgroundColor: C.panel, elevation: 0, foregroundColor: C.ink, title: const Text('Manage menu', style: TextStyle(fontWeight: FontWeight.w900))),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: C.brand, foregroundColor: C.ink, onPressed: _saving ? null : () => _edit(), icon: const Icon(Icons.add), label: const Text('Add item', style: TextStyle(fontWeight: FontWeight.w900))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: C.brand))
          : Stack(children: [
              ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
                for (final c in repo.categories) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(c.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, color: C.textMute, letterSpacing: .5, fontSize: 12))),
                  for (final it in repo.items.where((i) => i.category == c.id))
                    _itemTile(it),
                ],
              ]),
              if (_saving) Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator(color: C.brand))),
            ]),
    );
  }

  Widget _itemTile(MenuItem it) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: C.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: C.border)),
        child: ListTile(
          leading: Text(it.icon, style: const TextStyle(fontSize: 26)),
          title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${money(it.price)}${it.is86d ? '  · 86 (sold out)' : !it.available ? '  · hidden' : ''}',
              style: TextStyle(fontWeight: FontWeight.w700, color: it.is86d ? C.red : C.textMute)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit, color: C.textMute), onPressed: () => _edit(it)),
            IconButton(icon: const Icon(Icons.delete_outline, color: C.red), onPressed: () => _delete(it)),
          ]),
        ),
      );
}

class _ItemEditor extends StatefulWidget {
  final MenuItem? item;
  final List<MenuCategory> categories;
  const _ItemEditor({required this.item, required this.categories});
  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price = TextEditingController(text: widget.item?.price.toStringAsFixed(2) ?? '');
  late final _icon = TextEditingController(text: widget.item?.icon ?? '🍵');
  late String _cat = widget.item?.category ?? (widget.categories.isNotEmpty ? widget.categories.first.id : '');
  late bool _available = widget.item?.available ?? true;
  late bool _is86 = widget.item?.is86d ?? false;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: C.panel, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isNew ? 'Add item' : 'Edit item', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.ink)),
          const SizedBox(height: 14),
          Row(children: [
            SizedBox(width: 64, child: TextField(controller: _icon, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24), decoration: _dec('icon'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _name, decoration: _dec('Name'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _price, keyboardType: TextInputType.number, decoration: _dec('Price').copyWith(prefixText: '\$ '))),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: widget.categories.any((c) => c.id == _cat) ? _cat : null,
              decoration: _dec('Category'),
              items: [for (final c in widget.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _cat = v ?? _cat),
            )),
          ]),
          const SizedBox(height: 6),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _available, activeThumbColor: C.green, onChanged: (v) => setState(() => _available = v), title: const Text('Available (shown on menu)', style: TextStyle(fontWeight: FontWeight.w700))),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: _is86, activeThumbColor: C.red, onChanged: (v) => setState(() => _is86 = v), title: const Text('86 — sold out today', style: TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(height: 10),
          SizedBox(height: 52, child: ElevatedButton(
            onPressed: () {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              final id = widget.item?.id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
              Navigator.pop(context, {
                'id': id, 'name': name, 'icon': _icon.text.trim().isEmpty ? '🍵' : _icon.text.trim(),
                'price': double.tryParse(_price.text) ?? 0, 'category': _cat,
                'available': _available, 'is86d': _is86,
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: C.brand, foregroundColor: C.ink, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: Text(isNew ? 'Add item' : 'Save changes', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          )),
        ]),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(labelText: label, isDense: true, filled: true, fillColor: C.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none));
}
