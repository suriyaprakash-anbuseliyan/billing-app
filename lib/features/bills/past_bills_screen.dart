import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/database.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/printer/printer_service.dart';
import '../../core/printer/receipt_image_generator.dart';
import '../../core/settings/settings_provider.dart';

class PastBillsScreen extends ConsumerStatefulWidget {
  const PastBillsScreen({super.key});

  @override
  ConsumerState<PastBillsScreen> createState() => _PastBillsScreenState();
}

class _PastBillsScreenState extends ConsumerState<PastBillsScreen> {
  List<Bill> _allBills = [];
  List<Bill> _filteredBills = [];
  bool _isLoading = true;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  Future<void> _loadBills() async {
    final db = ref.read(databaseProvider);
    final bills = await (db.select(db.bills)
      ..orderBy([(t) => drift.OrderingTerm(expression: t.createdAt, mode: drift.OrderingMode.desc)])
    ).get();
    
    if (mounted) {
      setState(() {
        _allBills = bills;
        _filterBills(_searchCtrl.text);
        _isLoading = false;
      });
    }
  }

  void _filterBills(String query) {
    if (query.isEmpty) {
      setState(() => _filteredBills = _allBills);
      return;
    }
    
    final q = query.toLowerCase();
    setState(() {
      _filteredBills = _allBills.where((b) {
        return b.billNumber.toLowerCase().contains(q) ||
               b.paymentMode.toLowerCase().contains(q);
      }).toList();
    });
  }

  Future<void> _viewAndPrintBill(Bill bill) async {
    final db = ref.read(databaseProvider);
    // Fetch bill items
    final items = await (db.select(db.billItems)..where((t) => t.billId.equals(bill.id))).get();
    
    // Map with products to get names and units
    final List<Map<String, dynamic>> itemsList = [];
    for (var item in items) {
      final product = await (db.select(db.products)..where((t) => t.id.equals(item.productId))).getSingle();
      String displayName = product.name;
      if (product.searchAliases != null && product.searchAliases!.isNotEmpty) {
        displayName = product.searchAliases!.split(',').first.trim();
      }
      itemsList.add({
        'name': displayName,
        'qty': item.quantity,
        'unit': product.unit,
        'price': item.unitPrice,
      });
    }

    final shopSettings = ref.read(shopSettingsProvider);

    final pngBytes = await ReceiptImageGenerator.generateReceiptImage(
      shopSettings: shopSettings,
      billNumber: bill.billNumber,
      total: bill.total,
      items: itemsList,
    );

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => _BillPreviewDialog(
          bill: bill, 
          itemsList: itemsList, 
          imageBytes: pngBytes
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Past Bills', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search & Filters
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search by Bill Number...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () {
                        _searchCtrl.clear();
                        _filterBills('');
                      }),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    ),
                    onChanged: _filterBills,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadBills,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          
          // Data Table Header
          Container(
            color: Colors.teal.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), child: const Text('Bill Number', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                  VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                  Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                  VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                  Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                  VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                  Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), alignment: Alignment.centerRight, child: const Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                  VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                  Container(width: 100, padding: const EdgeInsets.symmetric(vertical: 12), alignment: Alignment.center, child: const Text('Action', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                ],
              ),
            ),
          ),

          // Data
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _filteredBills.isEmpty
                ? const Center(child: Text('No bills found.', style: TextStyle(fontSize: 18, color: Colors.grey)))
                : ListView.builder(
                    itemCount: _filteredBills.length,
                    itemBuilder: (context, index) {
                      final bill = _filteredBills[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Text(bill.billNumber, style: const TextStyle(fontWeight: FontWeight.w600)))),
                              VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                              Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: Text(DateFormat('dd-MM-yyyy hh:mm a').format(bill.createdAt)))),
                              VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                              Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: Text(bill.paymentMode))),
                              VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                              Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), alignment: Alignment.centerRight, child: Text('₹${bill.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)))),
                              VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                              Container(
                                width: 100,
                                alignment: Alignment.center,
                                child: TextButton(
                                  onPressed: () => _viewAndPrintBill(bill),
                                  child: const Text('View/Print', style: TextStyle(color: Colors.blue)),
                                )
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

class _BillPreviewDialog extends StatelessWidget {
  final Bill bill;
  final List<Map<String, dynamic>> itemsList;
  final Uint8List imageBytes;

  const _BillPreviewDialog({required this.bill, required this.itemsList, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // Left: Bill Data Table
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bill Details: ${bill.billNumber}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('Date: ${DateFormat('dd-MM-yyyy hh:mm a').format(bill.createdAt)}', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: ListView.separated(
                        itemCount: itemsList.length,
                        separatorBuilder: (c, i) => Divider(height: 1, color: Colors.grey.shade300),
                        itemBuilder: (c, i) {
                          final item = itemsList[i];
                          return ListTile(
                            title: Text(item['name']),
                            subtitle: Text('${item['qty']} ${item['unit']} x ₹${item['price']}'),
                            trailing: Text('₹${(item['qty'] * item['price']).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('₹${bill.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
            const SizedBox(width: 24),
            // Right: Receipt Preview
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  const Text('Receipt Preview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]
                      ),
                      child: SingleChildScrollView(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Image.memory(imageBytes, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final printer = PrinterService();
                        await printer.printImageBytes(imageBytes);
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt sent to printer!')));
                        }
                      }, 
                      icon: const Icon(Icons.print),
                      label: const Text('Print Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
