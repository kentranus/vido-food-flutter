import 'package:flutter/material.dart';
import 'pos_theme.dart';

/// Shared primitives — faithful ports of React components/Shared.jsx
/// (BrandMark, Button, Input, Field). Re-read PT.c each build so theme toggles.

/// The Vido Food brand icon (src/assets/brand-icon.png).
class BrandMark extends StatelessWidget {
  final double size;
  final double? radius;
  const BrandMark({super.key, this.size = 64, this.radius});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.28),
      child: Image.asset('assets/images/brand-icon.png', width: size, height: size, fit: BoxFit.contain),
    );
  }
}

enum PBtnVariant { primary, secondary, danger, ghost }
enum PBtnSize { sm, md, lg }

/// Button — matches React Button(variant,size). primary has the 3px bottom shadow.
class PButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final PBtnVariant variant;
  final PBtnSize size;
  final bool expand;
  const PButton(this.child, {super.key, this.onPressed, this.variant = PBtnVariant.primary, this.size = PBtnSize.md, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    final pad = switch (size) {
      PBtnSize.sm => const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      PBtnSize.md => const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      PBtnSize.lg => const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    };
    final fontSize = switch (size) { PBtnSize.sm => 12.0, PBtnSize.md => 13.0, PBtnSize.lg => 15.0 };
    Color bg; Color fg; Border? border; List<BoxShadow>? shadow;
    switch (variant) {
      case PBtnVariant.primary:
        bg = c.primary; fg = c.bg;
        shadow = [BoxShadow(color: c.primaryD, offset: const Offset(0, 3), blurRadius: 0)];
      case PBtnVariant.secondary:
        bg = c.card; fg = c.text;
      case PBtnVariant.danger:
        bg = c.red; fg = Colors.white;
      case PBtnVariant.ghost:
        bg = Colors.transparent; fg = c.text; border = Border.all(color: c.border);
    }
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: expand ? double.infinity : null,
            padding: pad,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: border, boxShadow: shadow),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: fontSize),
              child: IconTheme.merge(
                data: IconThemeData(color: fg, size: fontSize + 3),
                child: Center(
                  widthFactor: expand ? null : 1,
                  child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [child]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Input — matches React Input.
class PInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  const PInput({super.key, this.controller, this.hintText, this.obscure = false, this.keyboardType,
    this.capitalization = TextCapitalization.none, this.onSubmitted, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: TextStyle(color: c.text, fontSize: 14, fontWeight: FontWeight.w700),
      cursorColor: c.primary,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: c.textDim, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: c.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.primary)),
      ),
    );
  }
}

/// Field — label (uppercase) + child + optional hint. Matches React Field.
class PField extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  const PField({super.key, required this.label, required this.child, this.hint});
  @override
  Widget build(BuildContext context) {
    final c = PT.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textMute, letterSpacing: 0.5)),
        ),
        child,
        if (hint != null) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(hint!, style: TextStyle(fontSize: 11, color: c.textMute, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
