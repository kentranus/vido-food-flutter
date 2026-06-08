import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Receipt / kitchen-ticket printing (80mm thermal). Mirrors the React
/// printKitchenTicket / printReceipt. Opens the native print sheet; works with
/// any AirPrint / system / Bluetooth / USB printer the device exposes.

const _w = 80.0 * PdfPageFormat.mm;
PdfPageFormat get _fmt => PdfPageFormat(_w, double.infinity, marginAll: 6);

pw.Widget _line([double h = 1]) => pw.Container(height: h, color: PdfColors.black, margin: const pw.EdgeInsets.symmetric(vertical: 4));

String _sourceLabel(String source) {
  final s = source.toLowerCase();
  if (s.contains('online') || s.contains('web')) return 'ONLINE ORDER';
  if (s.contains('kiosk')) return 'KIOSK ORDER';
  return 'COUNTER';
}

/// items: [{qty,name,mods:[..],notes}]
Future<void> printKitchenTicket({
  required String source,
  required String number,
  required String type,
  String customer = '',
  String phone = '',
  String? table,
  required List<Map<String, dynamic>> items,
}) async {
  final doc = pw.Document();
  doc.addPage(pw.Page(pageFormat: _fmt, build: (_) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Center(child: pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 2)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: pw.Text(_sourceLabel(source), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      )),
      pw.SizedBox(height: 4),
      pw.Center(child: pw.Text('#$number', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text('${type.toUpperCase()}${table != null && table.isNotEmpty ? '  TABLE $table' : ''}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text(DateTime.now().toString().substring(0, 16), style: const pw.TextStyle(fontSize: 9))),
      if (customer.isNotEmpty) pw.Text('Customer: $customer', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      if (phone.isNotEmpty) pw.Text('Tel: $phone', style: const pw.TextStyle(fontSize: 11)),
      _line(),
      for (final it in items) ...[
        pw.Text('${it['qty']} x ${it['name']}', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        if ((it['mods'] as List?)?.isNotEmpty ?? false)
          pw.Padding(padding: const pw.EdgeInsets.only(left: 10), child: pw.Text('+ ${(it['mods'] as List).join(', ')}', style: const pw.TextStyle(fontSize: 11))),
        if ((it['notes'] ?? '').toString().isNotEmpty)
          pw.Padding(padding: const pw.EdgeInsets.only(left: 10), child: pw.Text('>> ${it['notes']}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
      ],
      _line(),
      pw.SizedBox(height: 24),
    ],
  )));
  await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'kitchen-$number');
}

/// items: [{qty,name,lineTotal}]
Future<void> printReceipt({
  required String storeName,
  required String number,
  required String type,
  required List<Map<String, dynamic>> items,
  required double subtotal,
  required double tax,
  double tip = 0,
  required double total,
  String paymentMethod = '',
  double cashReceived = 0,
  double change = 0,
}) async {
  String m(num v) => '\$${v.toStringAsFixed(2)}';
  final doc = pw.Document();
  doc.addPage(pw.Page(pageFormat: _fmt, build: (_) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Center(child: pw.Text(storeName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.Center(child: pw.Text('Order #$number · ${type.toUpperCase()}', style: const pw.TextStyle(fontSize: 10))),
      pw.Center(child: pw.Text(DateTime.now().toString().substring(0, 16), style: const pw.TextStyle(fontSize: 9))),
      _line(),
      for (final it in items)
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Expanded(child: pw.Text('${it['qty']} x ${it['name']}', style: const pw.TextStyle(fontSize: 11))),
          pw.Text(m((it['lineTotal'] ?? 0) as num), style: const pw.TextStyle(fontSize: 11)),
        ]),
      _line(),
      _kv('Subtotal', m(subtotal)),
      _kv('Tax', m(tax)),
      if (tip > 0) _kv('Tip', m(tip)),
      pw.SizedBox(height: 2),
      _kv('TOTAL', m(total), bold: true),
      if (paymentMethod.isNotEmpty) _kv('Paid', paymentMethod.toUpperCase()),
      if (cashReceived > 0) ...[_kv('Cash', m(cashReceived)), _kv('Change', m(change))],
      _line(),
      pw.Center(child: pw.Text('Thank you!', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 20),
    ],
  )));
  await Printing.layoutPdf(onLayout: (_) => doc.save(), name: 'receipt-$number');
}

pw.Widget _kv(String k, String v, {bool bold = false}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(k, style: pw.TextStyle(fontSize: bold ? 14 : 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        pw.Text(v, style: pw.TextStyle(fontSize: bold ? 14 : 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      ],
    );
