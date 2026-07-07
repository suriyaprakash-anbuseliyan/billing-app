import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShopSettings {
  final String shopName;
  final String addressLine1;
  final String addressLine2;
  final String phoneNumbers;
  final String gstIn;

  ShopSettings({
    required this.shopName,
    required this.addressLine1,
    required this.addressLine2,
    required this.phoneNumbers,
    required this.gstIn,
  });

  factory ShopSettings.defaultSettings() {
    return ShopSettings(
      shopName: 'ராகா பேக்கரி & ரெஸ்டாரண்ட்',
      addressLine1: '',
      addressLine2: '',
      phoneNumbers: '',
      gstIn: '',
    );
  }
}

class ShopSettingsNotifier extends Notifier<ShopSettings> {
  @override
  ShopSettings build() {
    _loadSettings();
    return ShopSettings.defaultSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = ShopSettings(
      shopName: prefs.getString('shopName') ?? 'ராகா பேக்கரி & ரெஸ்டாரண்ட்',
      addressLine1: prefs.getString('addressLine1') ?? '',
      addressLine2: prefs.getString('addressLine2') ?? '',
      phoneNumbers: prefs.getString('phoneNumbers') ?? '',
      gstIn: prefs.getString('gstIn') ?? '',
    );
  }

  Future<void> saveSettings({
    required String shopName,
    required String addressLine1,
    required String addressLine2,
    required String phoneNumbers,
    required String gstIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shopName', shopName);
    await prefs.setString('addressLine1', addressLine1);
    await prefs.setString('addressLine2', addressLine2);
    await prefs.setString('phoneNumbers', phoneNumbers);
    await prefs.setString('gstIn', gstIn);

    state = ShopSettings(
      shopName: shopName,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      phoneNumbers: phoneNumbers,
      gstIn: gstIn,
    );
  }
}

final shopSettingsProvider = NotifierProvider<ShopSettingsNotifier, ShopSettings>(() {
  return ShopSettingsNotifier();
});
