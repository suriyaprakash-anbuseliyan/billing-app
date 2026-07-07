import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'receipt_image_generator.dart';
import '../settings/settings_provider.dart';

class PrinterService {
  Future<void> printImageBytes(Uint8List pngBytes) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];

      final img.Image? receiptImage = img.decodeImage(pngBytes);
      if (receiptImage == null) {
        throw Exception("Failed to decode receipt image");
      }

      bytes += generator.image(receiptImage);
      bytes += generator.cut();

      print('--- RECEIPT IMAGE GENERATED (${bytes.length} bytes) ---');
      print('Waiting for physical USB Printer connection to send data.');
    } catch (e) {
      print('Error printing image: $e');
    }
  }

  Future<void> printReceipt({
    required String billNumber,
    required double total,
    required List<Map<String, dynamic>> items,
    String? customerName,
    String? customerPhone,
  }) async {
    final pngBytes = await ReceiptImageGenerator.generateReceiptImage(
      shopSettings: ShopSettings.defaultSettings(),
      billNumber: billNumber,
      total: total,
      items: items,
      customerName: customerName,
      customerPhone: customerPhone,
    );
    await printImageBytes(pngBytes);
  }
}
