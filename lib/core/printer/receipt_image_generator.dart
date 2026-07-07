import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../settings/settings_provider.dart';

class ReceiptImageGenerator {
  static Future<Uint8List> generateReceiptImage({
    required ShopSettings shopSettings,
    required String billNumber,
    required double total,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
    String paymentMode = 'Cash',
  }) async {
    const double width = 576.0; // 80mm thermal printer standard width
    
    // Estimate height dynamically based on items
    double height = 400.0 + (items.length * 60.0);
    if (customerName != null) height += 40.0;
    if (customerPhone != null) height += 40.0;
    if (shopSettings.addressLine1.isNotEmpty) height += 30.0;
    if (shopSettings.addressLine2.isNotEmpty) height += 30.0;
    if (shopSettings.phoneNumbers.isNotEmpty) height += 30.0;
    if (shopSettings.gstIn.isNotEmpty) height += 30.0;
    
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    
    // Fill white background
    final Paint bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    double currentY = 20.0;

    // Helper function to draw text and return its rendered height
    double drawText(String text, double x, double y, double fontSize, {bool isBold = false, TextAlign align = TextAlign.left, double maxWidth = width}) {
      final textSpan = TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black,
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'Mukta Malar',
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: ui.TextDirection.ltr,
        textAlign: align,
      );
      
      textPainter.layout(minWidth: 0, maxWidth: maxWidth);
      
      double drawX = x;
      if (align == TextAlign.center) {
        drawX = (maxWidth - textPainter.width) / 2;
      } else if (align == TextAlign.right) {
        drawX = maxWidth - textPainter.width - x;
      }
      
      textPainter.paint(canvas, Offset(drawX, y));
      return textPainter.height;
    }

    void drawDashedLine(double y) {
      final paint = Paint()..color = Colors.black..strokeWidth = 2..style = PaintingStyle.stroke;
      double dashWidth = 10, dashSpace = 5, startX = 20;
      while (startX < width - 20) {
        canvas.drawLine(Offset(startX, y), Offset(startX + dashWidth, y), paint);
        startX += dashWidth + dashSpace;
      }
    }

    // --- Header ---
    currentY += drawText(shopSettings.shopName, 0, currentY, 32, isBold: true, align: TextAlign.center) + 10;
    
    if (shopSettings.addressLine1.isNotEmpty) {
      currentY += drawText(shopSettings.addressLine1, 0, currentY, 20, align: TextAlign.center) + 5;
    }
    if (shopSettings.addressLine2.isNotEmpty) {
      currentY += drawText(shopSettings.addressLine2, 0, currentY, 20, align: TextAlign.center) + 5;
    }
    if (shopSettings.phoneNumbers.isNotEmpty) {
      currentY += drawText('Ph: ${shopSettings.phoneNumbers}', 0, currentY, 20, align: TextAlign.center) + 10;
    }
    if (shopSettings.gstIn.isNotEmpty) {
      currentY += drawText('GSTIN: ${shopSettings.gstIn}', 0, currentY, 20, align: TextAlign.center) + 10;
    }
    
    drawDashedLine(currentY);
    currentY += 10;

    currentY += drawText('பில் நம்பர் : $billNumber', 20, currentY, 22, isBold: true) + 5;
    currentY += drawText('தேதி ${DateFormat('dd-MM-yyyy').format(DateTime.now())}', 20, currentY, 22, isBold: true) + 15;
    currentY += drawText('Payment Mode: $paymentMode', 20, currentY, 22) + 20;
    
    drawDashedLine(currentY);
    currentY += 10;

    // --- Table Headers ---
    double itemX = 20;
    double qtyX = 210; // Right margin for Qty
    double rateX = 110; // Right margin for Rate
    double amtX = 20; // Right margin for Amt

    double headerRowY = currentY;
    double headerHeight = drawText('Item', itemX, headerRowY, 24, isBold: true);
    drawText('Qty', qtyX, headerRowY, 24, isBold: true, align: TextAlign.right);
    drawText('Rate', rateX, headerRowY, 24, isBold: true, align: TextAlign.right);
    drawText('Amt', amtX, headerRowY, 24, isBold: true, align: TextAlign.right);
    
    currentY += headerHeight + 10;
    
    drawDashedLine(currentY);
    currentY += 10;

    // --- Items ---
    int sno = 1;
    for (var item in items) {
      final name = item['name'] as String;
      final qty = item['qty'] as double;
      final originalUnit = item['unit'] as String? ?? '';
      final unitLower = originalUnit.toLowerCase();
      final price = item['price'] as double;
      final amt = qty * price;
      
      String qtyStr = '';
      if ((unitLower.contains('kg') || unitLower.contains('kilo')) && qty > 0 && qty < 1) {
        final grams = (qty * 1000).round();
        qtyStr = '$grams கிராம்';
      } else if ((unitLower.contains('ltr') || unitLower.contains('liter') || unitLower == 'l' || unitLower == '1l') && qty > 0 && qty < 1) {
        final ml = (qty * 1000).round();
        qtyStr = '$ml மிலி';
      } else {
        String displayUnit = originalUnit;
        if (unitLower == '1kg' || unitLower == '1 kg') displayUnit = 'kg';
        if (unitLower == '1ltr' || unitLower == '1 ltr' || unitLower == '1l') displayUnit = 'ltr';
        
        final qtyFormatted = qty == qty.toInt() ? qty.toInt().toString() : qty.toStringAsFixed(2);
        
        bool startsWithNumber = RegExp(r'^\d').hasMatch(displayUnit);
        if (startsWithNumber) {
          qtyStr = '$qtyFormatted x $displayUnit'.trim();
        } else {
          qtyStr = '$qtyFormatted $displayUnit'.trim();
        }
      }
      
      String cleanedName = name;
      if (originalUnit.isNotEmpty) {
        final regex = RegExp(r'\s*' + RegExp.escape(originalUnit) + r'$', caseSensitive: false);
        cleanedName = cleanedName.replaceAll(regex, '').trim();
      }
      
      double rowY = currentY;
      
      // maxWidth 250 prevents it from bleeding into Qty (right margin 210 -> right edge 366 -> gap ~50px)
      double nameHeight = drawText('$sno. $cleanedName', itemX, rowY, 22, maxWidth: 250);
      drawText(qtyStr, qtyX, rowY, 22, align: TextAlign.right);
      drawText(price.toStringAsFixed(2), rateX, rowY, 22, align: TextAlign.right);
      drawText(amt.toStringAsFixed(2), amtX, rowY, 22, align: TextAlign.right);
      
      sno++;
      currentY += nameHeight + 10;
    }
    
    drawDashedLine(currentY);
    currentY += 10;

    // --- Totals ---
    drawText('TOTAL', 20, currentY, 32, isBold: true);
    currentY += drawText('Rs.${total.toStringAsFixed(2)}', 20, currentY, 32, isBold: true, align: TextAlign.right) + 20;
    
    drawDashedLine(currentY);
    currentY += 20;
    
    currentY += drawText('E & O.E', 20, currentY, 16, align: TextAlign.right) + 20;
    currentY += drawText('!!! Thank You !!! Visit Us Again :)', 0, currentY, 22, align: TextAlign.center) + 20;
    
    // Generate image
    final ui.Picture picture = recorder.endRecording();
    final ui.Image img = await picture.toImage(width.toInt(), (currentY + 50).toInt());
    final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    
    final bytes = byteData!.buffer.asUint8List();
    
    // DEBUG: Save to disk so the user can see what it looks like without a physical printer!
    try {
      final file = File('test_receipt.png');
      await file.writeAsBytes(bytes);
      print('Saved preview of receipt to: \${file.absolute.path}');
    } catch (_) {}
    
    return bytes;
  }
}
