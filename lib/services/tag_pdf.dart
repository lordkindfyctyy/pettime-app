import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart'
    show Barcode, BarcodeQRCorrectionLevel;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_lang.dart';
import '../models/supply.dart';
import 'vet_report.dart';

/// A sheet to print a pet's tag QR: the same QR in several sizes to cut out
/// and glue on (or take to have it engraved), and a card with the pet's name.
class TagPdf {
  TagPdf._();

  static const _red = PdfColor.fromInt(0xFFE53935);
  static const _grey = PdfColor.fromInt(0xFF616161);

  /// QR sizes in cm, from a big one for the card to a small collar tag.
  static const sizesCm = [4.0, 3.0, 2.5, 2.0];

  static String fileName(String petName) =>
      '${tr('Chapita de {pet}', {'pet': petName})}.pdf';

  static Future<Uint8List> build({
    required String petName,
    required String url,
    required VetReportAssets assets,
  }) async {
    final doc = pw.Document(
      title: tr('Chapita de {pet}', {'pet': petName}),
      author: 'PetTime',
    );
    final qr = Barcode.qrCode(errorCorrectLevel: BarcodeQRCorrectionLevel.medium);

    pw.Widget code(double cm) => pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.BarcodeWidget(
              barcode: qr,
              data: url,
              width: cm * PdfPageFormat.cm,
              height: cm * PdfPageFormat.cm,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${formatAmount(cm)} cm',
              style: const pw.TextStyle(color: _grey, fontSize: 8),
            ),
          ],
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(1.5 * PdfPageFormat.cm),
      theme: pw.ThemeData.withFont(base: assets.regular, bold: assets.bold),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            tr('Chapita de {pet}', {'pet': petName}),
            style: pw.TextStyle(color: _red, fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            tr('Recortá el QR del tamaño que necesites y pegalo en la chapita o el '
                'collar, o llevá esta hoja para grabarlo. Quien la encuentre lo '
                'escanea con la cámara y ve tu WhatsApp.'),
          ),
          pw.SizedBox(height: 24),
          // A card to hang or glue: the QR with a line that says what it is.
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _red, width: 2),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.BarcodeWidget(
                  barcode: qr,
                  data: url,
                  width: 4 * PdfPageFormat.cm,
                  height: 4 * PdfPageFormat.cm,
                ),
                pw.SizedBox(width: 14),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      petName,
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(tr('Si me encontraste,')),
                    pw.Text(tr('escaneame para avisarle')),
                    pw.Text(tr('a mi familia')),
                    if (assets.logo != null) ...[
                      pw.SizedBox(height: 8),
                      pw.Row(children: [
                        pw.Image(assets.logo!, width: 16, height: 16),
                        pw.SizedBox(width: 4),
                        pw.Text('PetTime', style: const pw.TextStyle(color: _grey, fontSize: 9)),
                      ]),
                    ],
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Text(
            tr('Para recortar'),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 28,
            runSpacing: 20,
            crossAxisAlignment: pw.WrapCrossAlignment.end,
            children: [for (final cm in sizesCm) code(cm)],
          ),
          pw.Spacer(),
          pw.Text(
            url,
            style: const pw.TextStyle(color: _grey, fontSize: 9),
          ),
        ],
      ),
    ));
    return doc.save();
  }
}
