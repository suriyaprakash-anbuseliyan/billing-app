import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/settings/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _addr1Ctrl;
  late TextEditingController _addr2Ctrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _gstCtrl;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(shopSettingsProvider);
    _nameCtrl = TextEditingController(text: settings.shopName);
    _addr1Ctrl = TextEditingController(text: settings.addressLine1);
    _addr2Ctrl = TextEditingController(text: settings.addressLine2);
    _phoneCtrl = TextEditingController(text: settings.phoneNumbers);
    _gstCtrl = TextEditingController(text: settings.gstIn);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addr1Ctrl.dispose();
    _addr2Ctrl.dispose();
    _phoneCtrl.dispose();
    _gstCtrl.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(shopSettingsProvider.notifier).saveSettings(
      shopName: _nameCtrl.text.trim(),
      addressLine1: _addr1Ctrl.text.trim(),
      addressLine2: _addr2Ctrl.text.trim(),
      phoneNumbers: _phoneCtrl.text.trim(),
      gstIn: _gstCtrl.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop settings saved successfully!')));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Settings'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Receipt Details', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Shop Name (e.g. ராகா பேக்கரி)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addr1Ctrl,
                    decoration: const InputDecoration(labelText: 'Address Line 1', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addr2Ctrl,
                    decoration: const InputDecoration(labelText: 'Address Line 2 (City, Pincode)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone Number(s)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _gstCtrl,
                    decoration: const InputDecoration(labelText: 'GSTIN (Optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Settings', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
