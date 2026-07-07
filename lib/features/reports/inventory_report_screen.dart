import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/database.dart';
import '../../core/sync/sync_manager.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class InventoryReportScreen extends ConsumerStatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  ConsumerState<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends ConsumerState<InventoryReportScreen> {
  double _totalInventoryValue = 0.0;
  int _lowStockCount = 0;
  List<StockLedgerData> _ledgerHistory = [];
  Map<String, String> _productNames = {};

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    final db = ref.read(databaseProvider);
    
    final products = await (db.select(db.products)..where((t) => t.isActive.equals(true))).get();
    
    double value = 0.0;
    int lowCount = 0;
    Map<String, String> names = {};
    
    for (var p in products) {
      value += (p.costPrice * p.stockQty);
      if (p.stockQty < 5) lowCount++;
      names[p.id] = p.name;
    }
    
    final ledger = await (db.select(db.stockLedger)..orderBy([(t) => drift.OrderingTerm(expression: t.createdAt, mode: drift.OrderingMode.desc)])).get();

    setState(() {
      _totalInventoryValue = value;
      _lowStockCount = lowCount;
      _productNames = names;
      _ledgerHistory = ledger;
    });
  }

  Future<void> _exportToCSV() async {
    final rows = <List<dynamic>>[];
    rows.add(['Date', 'Product', 'Type', 'Quantity', 'Reason']);
    for (var row in _ledgerHistory) {
      rows.add([
        DateFormat('yyyy-MM-dd HH:mm').format(row.createdAt),
        _productNames[row.productId] ?? 'Unknown',
        row.type,
        row.quantity,
        row.reason ?? ''
      ]);
    }
    String csv = const CsvEncoder().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/inventory_ledger_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    final file = File(path);
    await file.writeAsString(csv);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ledger exported to: $path'),
        duration: const Duration(seconds: 5),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory & Stock Ledger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportToCSV,
          )
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            color: Colors.blueGrey.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Total Inventory Value (Cost)', style: TextStyle(fontSize: 18, color: Colors.blueGrey)),
                      Text('₹${_totalInventoryValue.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Low Stock Alerts', style: TextStyle(fontSize: 18, color: Colors.blueGrey)),
                      Text('$_lowStockCount', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Stock Movement Ledger', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _ledgerHistory.isEmpty 
              ? const Center(child: Text('No stock movements recorded yet.'))
              : ListView.builder(
                  itemCount: _ledgerHistory.length,
                  itemBuilder: (ctx, i) {
                    final ledger = _ledgerHistory[i];
                    final isOut = ledger.type == 'OUT';
                    return ListTile(
                      leading: Icon(
                        isOut ? Icons.arrow_downward : Icons.arrow_upward, 
                        color: isOut ? Colors.red : Colors.green
                      ),
                      title: Text(_productNames[ledger.productId] ?? 'Unknown Product', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${ledger.reason ?? "Update"} • ${DateFormat('MMM dd, hh:mm a').format(ledger.createdAt)}'),
                      trailing: Text(
                        '${isOut ? "-" : "+"}${ledger.quantity}', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isOut ? Colors.red : Colors.green)
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
