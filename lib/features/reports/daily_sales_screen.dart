import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/database.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/printer/printer_service.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class DailySalesScreen extends ConsumerStatefulWidget {
  const DailySalesScreen({super.key});

  @override
  ConsumerState<DailySalesScreen> createState() => _DailySalesScreenState();
}

class _DailySalesScreenState extends ConsumerState<DailySalesScreen> {
  double _totalSales = 0.0;
  int _totalBills = 0;
  List<Bill> _bills = [];
  List<BarChartGroupData> _chartData = [];
  double _maxChartY = 1000.0;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    final db = ref.read(databaseProvider);
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    
    final sevenDaysAgo = startOfDay.subtract(const Duration(days: 6));
    
    final allBills = await db.select(db.bills).get();
    
    final todayBills = allBills.where((b) => b.createdAt.isAfter(startOfDay) || b.createdAt.isAtSameMomentAs(startOfDay)).toList();
    todayBills.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Prepare chart data for last 7 days
    List<BarChartGroupData> barGroups = [];
    double maxY = 0.0;
    
    for (int i = 0; i < 7; i++) {
      final targetDate = sevenDaysAgo.add(Duration(days: i));
      final nextDate = targetDate.add(const Duration(days: 1));
      
      final dayBills = allBills.where((b) => 
        (b.createdAt.isAfter(targetDate) || b.createdAt.isAtSameMomentAs(targetDate)) && 
        b.createdAt.isBefore(nextDate)
      ).toList();
      
      final dayTotal = dayBills.fold(0.0, (sum, b) => sum + b.total);
      if (dayTotal > maxY) maxY = dayTotal;
      
      barGroups.add(BarChartGroupData(
        x: i,
        barRods: [BarChartRodData(toY: dayTotal, color: Colors.teal, width: 22, borderRadius: BorderRadius.circular(6))],
      ));
    }

    setState(() {
      _bills = todayBills;
      _totalBills = todayBills.length;
      _totalSales = todayBills.fold(0.0, (sum, bill) => sum + bill.total);
      _chartData = barGroups;
      _maxChartY = (maxY * 1.2) + 100; // Add 20% padding
    });
  }

  Future<void> _exportToCSV() async {
    final rows = <List<dynamic>>[];
    rows.add(['Bill Number', 'Date', 'Time', 'Total Amount', 'Payment Mode']);
    for (var b in _bills) {
      rows.add([b.billNumber, DateFormat('yyyy-MM-dd').format(b.createdAt), DateFormat('hh:mm a').format(b.createdAt), b.total, b.paymentMode]);
    }
    String csv = const CsvEncoder().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/sales_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    final file = File(path);
    await file.writeAsString(csv);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Report exported to: $path'),
        duration: const Duration(seconds: 5),
      ));
    }
  }

  void _showBillDetails(Bill bill) async {
    final db = ref.read(databaseProvider);
    final itemsWithProducts = await (db.select(db.billItems).join([
      drift.innerJoin(db.products, db.products.id.equalsExp(db.billItems.productId))
    ])..where(db.billItems.billId.equals(bill.id))).get();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bill Details: ${bill.billNumber}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: itemsWithProducts.length,
            itemBuilder: (context, index) {
              final row = itemsWithProducts[index];
              final item = row.readTable(db.billItems);
              final product = row.readTable(db.products);
              return ListTile(
                title: Text(product.name),
                subtitle: Text('${item.quantity} x ₹${item.unitPrice}'),
                trailing: Text('₹${(item.quantity * item.unitPrice).toStringAsFixed(2)}'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final printer = PrinterService();
              await printer.printReceipt(
                billNumber: bill.billNumber,
                total: bill.total,
                items: itemsWithProducts.map((row) {
                  return {
                    'name': row.readTable(db.products).name,
                    'qty': row.readTable(db.billItems).quantity,
                    'price': row.readTable(db.billItems).unitPrice,
                  };
                }).toList(),
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Receipt sent to printer!')));
                Navigator.pop(ctx);
              }
            },
            icon: const Icon(Icons.print),
            label: const Text('Reprint'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Sales Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            onPressed: _exportToCSV,
          )
        ],
      ),
      body: Row(
        children: [
          // Left side: Chart and Stats
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Card(
                  margin: const EdgeInsets.all(16),
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text("Today's Bills", style: TextStyle(fontSize: 18, color: Colors.teal)),
                            Text('$_totalBills', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text("Today's Revenue", style: TextStyle(fontSize: 18, color: Colors.teal)),
                            Text('₹${_totalSales.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Last 7 Days Revenue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _maxChartY,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                final date = DateTime.now().subtract(Duration(days: 6 - value.toInt()));
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(DateFormat('E').format(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                return Text('₹${value.toInt()}', style: const TextStyle(fontSize: 12));
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: _chartData,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const VerticalDivider(width: 1),
          
          // Right side: Bills List
          Expanded(
            flex: 1,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Today's Bills", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: _bills.isEmpty 
                    ? const Center(child: Text('No bills generated today.'))
                    : ListView.builder(
                        itemCount: _bills.length,
                        itemBuilder: (ctx, i) {
                          final bill = _bills[i];
                          return ListTile(
                            onTap: () => _showBillDetails(bill),
                            leading: const Icon(Icons.receipt_long, color: Colors.teal),
                            title: Text(bill.billNumber),
                            subtitle: Text(DateFormat('hh:mm a').format(bill.createdAt)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('₹${bill.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right, color: Colors.grey),
                              ],
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
