import 'dart:io';
import 'package:flutter/material.dart';
import 'lib/core/printer/receipt_image_generator.dart';
import 'lib/features/settings/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final shopSettings = ShopSettings(
    shopName: 'Suriya Stores',
    addressLine1: '',
    addressLine2: '',
    phoneNumbers: '',
    gstIn: '',
  );

  final items = [
    {'name': 'Milagai Thool 250g', 'qty': 0.10, 'unit': '250g', 'price': 87.50},
    {'name': 'Garam Masala 100g', 'qty': 1.0, 'unit': '100g', 'price': 45.00}
  ];

  final bytes = await ReceiptImageGenerator.generateReceiptImage(
    shopSettings: shopSettings,
    billNumber: 'B-05078148',
    total: 53.75,
    items: items,
  );
  
  File('test_preview.png').writeAsBytesSync(bytes);
  print('Saved test_preview.png');
}
