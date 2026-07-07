import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:translator/translator.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/database/database.dart';
import 'package:excel/excel.dart' hide Border, TextSpan;

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Set<String> _selectedProductIds = {};
  final _uuid = const Uuid();
  final _translator = GoogleTranslator();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = ref.read(databaseProvider);
    final products = await (db.select(db.products)..where((t) => t.isActive.equals(true))).get();
    setState(() {
      _allProducts = products;
      _filterProducts(_searchController.text, updateState: false);
    });
  }

  void _filterProducts(String query, {bool updateState = true}) {
    if (query.isEmpty) {
      if (updateState) setState(() => _filteredProducts = _allProducts);
      else _filteredProducts = _allProducts;
      return;
    }
    final q = query.toLowerCase();
    
    final filtered = _allProducts.where((p) {
      return p.name.toLowerCase().contains(q) ||
             (p.searchAliases?.toLowerCase().contains(q) ?? false) ||
             (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList();
    
    if (updateState) {
      setState(() {
        _filteredProducts = filtered;
      });
    } else {
      _filteredProducts = filtered;
    }
  }

  Future<void> _bulkDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${_selectedProductIds.length} Products?'),
        content: const Text('Are you sure you want to delete these products? They will be hidden from inventory but kept in past sales.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Delete')
          ),
        ],
      )
    );
    if (confirm == true) {
      final db = ref.read(databaseProvider);
      for (var id in _selectedProductIds) {
        await (db.update(db.products)..where((t) => t.id.equals(id)))
            .write(ProductsCompanion(isActive: const drift.Value(false), syncStatus: const drift.Value(1)));
      }
      setState(() {
        _selectedProductIds.clear();
      });
      _loadProducts();
    }
  }

  void _showStockAdjustDialog(Product p) {
    final qtyCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String adjustType = 'IN'; // IN or OUT

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('Stock Adjustment: ${p.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Stock IN (+)'),
                      selected: adjustType == 'IN',
                      selectedColor: Colors.teal.shade100,
                      onSelected: (val) => setStateDialog(() => adjustType = 'IN'),
                    ),
                    const SizedBox(width: 16),
                    ChoiceChip(
                      label: const Text('Stock OUT (-)'),
                      selected: adjustType == 'OUT',
                      selectedColor: Colors.red.shade100,
                      onSelected: (val) => setStateDialog(() => adjustType = 'OUT'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantity (${p.unit})',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: 'Reason (e.g. Restock, Damaged)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: adjustType == 'IN' ? Colors.teal : Colors.red, foregroundColor: Colors.white),
                onPressed: () async {
                  final qty = double.tryParse(qtyCtrl.text);
                  if (qty == null || qty <= 0) return;
                  
                  final db = ref.read(databaseProvider);
                  
                  await db.into(db.stockLedger).insert(
                    StockLedgerCompanion.insert(
                      id: _uuid.v4(),
                      productId: p.id,
                      type: adjustType,
                      quantity: qty,
                      reason: drift.Value(reasonCtrl.text.trim()),
                    )
                  );
                  
                  final newStock = adjustType == 'IN' ? p.stockQty + qty : p.stockQty - qty;
                  
                  await (db.update(db.products)..where((t) => t.id.equals(p.id))).write(
                    ProductsCompanion(stockQty: drift.Value(newStock), syncStatus: const drift.Value(1))
                  );
                  
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Stock Adjusted!')));
                  }
                  _loadProducts();
                },
                child: Text('Confirm ${adjustType == 'IN' ? 'IN' : 'OUT'}'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _exportTemplate() async {
    final rows = [
      ['name', 'searchAliases', 'product_code', 'unit', 'price', 'costPrice', 'stockQty'],
      ['Sample Product', 'Alias1, Alias2', '123456789', 'kg', '100.0', '80.0', '50.0'],
    ];
    String csv = const CsvEncoder().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/product_import_template.csv';
    final file = File(path);
    await file.writeAsString(csv);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Template saved to: $path'),
        duration: const Duration(seconds: 5),
      ));
    }
  }

  void _showBulkImportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bulk Import Products', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('To import multiple products, upload a CSV or Excel (.xlsx) file with the following exact columns:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.grey.shade100,
                child: const Text(
                  'name, searchAliases, product_code, unit, price, costPrice, stockQty',
                  style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _exportTemplate();
                    },
                    icon: const Icon(Icons.download),
                    label: const Text('Download Sample'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processBulkImport();
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Select File & Import'),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processBulkImport() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
    );

    if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        List<List<dynamic>> rows = [];
        
        if (file.path.toLowerCase().endsWith('.xlsx')) {
          final bytes = await file.readAsBytes();
          final excel = Excel.decodeBytes(bytes);
          final table = excel.tables[excel.tables.keys.first]!;
          for (final row in table.rows) {
            rows.add(row.map((e) => e?.value?.toString() ?? '').toList());
          }
        } else {
          final csvString = await file.readAsString();
          rows = const CsvDecoder().convert(csvString);
        }

        if (rows.isEmpty || rows.length == 1) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File is empty or only has headers.')));
          return;
        }

        final header = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
        final nameIdx = header.indexOf('name');
        final aliasesIdx = header.indexOf('searchaliases');
        final barcodeIdx = header.indexOf('product_code') != -1 ? header.indexOf('product_code') : header.indexOf('barcode');
        final unitIdx = header.indexOf('unit');
        final priceIdx = header.indexOf('price');
        final costIdx = header.indexOf('costprice');
        final stockIdx = header.indexOf('stockqty');

        if (nameIdx == -1 || priceIdx == -1) {
           if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File must contain at least "name" and "price" columns.')));
           return;
        }

        final db = ref.read(databaseProvider);
        final companions = <ProductsCompanion>[];

        for (int i = 1; i < rows.length; i++) {
          final row = rows[i];
          if (row.isEmpty || row[nameIdx].toString().trim().isEmpty) continue;
          
          companions.add(ProductsCompanion.insert(
            id: _uuid.v4(),
            name: row[nameIdx].toString().trim(),
            searchAliases: aliasesIdx != -1 ? drift.Value(row[aliasesIdx]?.toString().trim()) : const drift.Value(null),
            barcode: barcodeIdx != -1 ? drift.Value(row[barcodeIdx]?.toString().trim()) : const drift.Value(null),
            unit: unitIdx != -1 ? row[unitIdx].toString().trim() : 'nos',
            price: double.tryParse(row[priceIdx].toString()) ?? 0.0,
            costPrice: drift.Value(costIdx != -1 ? (double.tryParse(row[costIdx].toString()) ?? 0.0) : 0.0),
            stockQty: drift.Value(stockIdx != -1 ? (double.tryParse(row[stockIdx].toString()) ?? 0.0) : 0.0),
          ));
        }

        await db.batch((batch) {
          batch.insertAll(db.products, companions);
        });

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully imported ${companions.length} products!')));
        _loadProducts();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error importing file: $e')));
      }
    }
  }

  void _showAddOrEditDialog({Product? product}) {
    final isEditing = product != null;
    final nameCtrl = TextEditingController(text: isEditing ? product.name : '');
    final aliasCtrl = TextEditingController(text: isEditing ? product.searchAliases : '');
    
    // Auto-generate a product code if it's a new product
    final defaultCode = 'PRD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    final barcodeCtrl = TextEditingController(text: isEditing ? product.barcode : defaultCode);
    final costPriceCtrl = TextEditingController(text: isEditing ? product.costPrice.toString() : '');
    final priceCtrl = TextEditingController(text: isEditing ? product.price.toString() : '');
    final stockCtrl = TextEditingController(text: isEditing ? product.stockQty.toString() : '');
    
    String selectedUnit = isEditing ? product.unit : 'pcs';
    Timer? debounce;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 500,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Edit Product' : 'Add New Product',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: nameCtrl, 
                      decoration: InputDecoration(
                        labelText: 'Product Name (English)',
                        prefixIcon: const Icon(Icons.shopping_bag_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onChanged: (text) {
                        if (debounce?.isActive ?? false) debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 800), () async {
                          if (text.trim().isNotEmpty && !isEditing) {
                            try {
                              final translation = await _translator.translate(text, from: 'en', to: 'ta');
                              setStateDialog(() => aliasCtrl.text = translation.text);
                            } catch (_) {}
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: aliasCtrl, 
                      decoration: InputDecoration(
                        labelText: 'Tamil Name / Aliases',
                        prefixIcon: const Icon(Icons.language),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      )
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: ['pcs', 'kgs', 'ltr', 'saram'].contains(selectedUnit) ? selectedUnit : 'pcs',
                            decoration: InputDecoration(
                              labelText: 'Unit Type',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'pcs', child: Text('Numbers')),
                              DropdownMenuItem(value: 'kgs', child: Text('Kilograms')),
                              DropdownMenuItem(value: 'ltr', child: Text('Liters')),
                              DropdownMenuItem(value: 'saram', child: Text('Saram')),
                            ],
                            onChanged: (val) {
                              if (val != null) setStateDialog(() => selectedUnit = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Product Code', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: barcodeCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Enter Product Code (Optional)',
                                  prefixIcon: const Icon(Icons.qr_code),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                )
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: costPriceCtrl, 
                            keyboardType: TextInputType.number, 
                            decoration: InputDecoration(
                              labelText: 'Purchase Price (₹)',
                              prefixIcon: const Icon(Icons.currency_rupee),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            )
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl, 
                            keyboardType: TextInputType.number, 
                            decoration: InputDecoration(
                              labelText: 'Sales Price (₹)',
                              prefixIcon: const Icon(Icons.currency_rupee),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            )
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: stockCtrl, 
                            keyboardType: TextInputType.number, 
                            decoration: InputDecoration(
                              labelText: isEditing ? 'Update Stock' : 'Initial Stock',
                              prefixIcon: const Icon(Icons.inventory_2_outlined),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            )
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(child: SizedBox()), // spacer for alignment
                      ],
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isEditing)
                          TextButton(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: ctx,
                                builder: (c) => AlertDialog(
                                  title: const Text('Delete Product?'),
                                  content: const Text('Are you sure you want to delete this product? It will be hidden from inventory but kept in past sales.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(c, true), 
                                      child: const Text('Delete')
                                    ),
                                  ],
                                )
                              );
                              if (confirm == true) {
                                final db = ref.read(databaseProvider);
                                await (db.update(db.products)..where((t) => t.id.equals(product.id)))
                                    .write(ProductsCompanion(isActive: const drift.Value(false), syncStatus: const drift.Value(1)));
                                if (ctx.mounted) Navigator.pop(ctx);
                                _loadProducts();
                              }
                            },
                            child: const Text('Delete Product', style: TextStyle(fontSize: 16, color: Colors.red)),
                          ),
                        if (isEditing) const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx), 
                          child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            final db = ref.read(databaseProvider);
                            final name = nameCtrl.text.trim();
                            final barcode = barcodeCtrl.text.trim();
                            final costPrice = double.tryParse(costPriceCtrl.text) ?? (isEditing ? product.costPrice : 0.0);
                            final price = double.tryParse(priceCtrl.text) ?? (isEditing ? product.price : 0.0);
                            final stock = double.tryParse(stockCtrl.text) ?? (isEditing ? product.stockQty : 0.0);

                            if (!isEditing) {
                              // Duplicate Check for new
                              final existing = await (db.select(db.products)
                                ..where((t) => (t.name.equals(name) | (barcode.isNotEmpty ? t.barcode.equals(barcode) : const drift.Constant(false))) & t.isActive.equals(true))
                              ).get();
                              
                              if (existing.isNotEmpty) {
                                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Product already exists!')));
                                return;
                              }

                              await db.into(db.products).insert(
                                ProductsCompanion.insert(
                                  id: _uuid.v4(),
                                  name: name,
                                  searchAliases: drift.Value(aliasCtrl.text),
                                  barcode: drift.Value(barcode),
                                  unit: selectedUnit,
                                  price: price,
                                  costPrice: drift.Value(costPrice),
                                  stockQty: drift.Value(stock),
                                  syncStatus: const drift.Value(1),
                                )
                              );
                            } else {
                              // Update existing
                              await (db.update(db.products)..where((t) => t.id.equals(product.id))).write(
                                ProductsCompanion(
                                  name: drift.Value(name),
                                  searchAliases: drift.Value(aliasCtrl.text),
                                  barcode: drift.Value(barcode),
                                  unit: drift.Value(selectedUnit),
                                  price: drift.Value(price),
                                  costPrice: drift.Value(costPrice),
                                  stockQty: drift.Value(stock),
                                  syncStatus: const drift.Value(1),
                                )
                              );
                            }
                            
                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadProducts();
                          },
                          child: Text(isEditing ? 'Save Changes' : 'Create Product', style: const TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int lowStockCount = _allProducts.where((p) => p.stockQty < 5).length;
    double totalValue = _allProducts.fold(0, (sum, p) => sum + (p.price * p.stockQty));

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar Area
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => context.pop(),
                            tooltip: 'Back to Billing',
                          ),
                          const SizedBox(width: 8),
                          const Text('Inventory Dashboard', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                        ],
                      ),
                      Row(
                        children: [
                          if (_selectedProductIds.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.delete),
                                label: Text('Delete (${_selectedProductIds.length})'),
                                onPressed: _bulkDelete,
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.sync, color: Colors.white),
                            tooltip: 'Sync MongoDB',
                            onPressed: () async {
                              await ref.read(syncManagerProvider).syncData();
                              _loadProducts();
                            },
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: Colors.white),
                            tooltip: 'More Actions',
                            onSelected: (value) {
                              if (value == 'export') _exportTemplate();
                              if (value == 'import') _showBulkImportDialog();
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(value: 'export', child: Text('Export CSV Template')),
                              const PopupMenuItem(value: 'import', child: Text('Bulk Import CSV')),
                            ],
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.teal,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.analytics),
                            label: const Text('Report'),
                            onPressed: () => context.push('/inventory-report'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.teal,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Item'),
                            onPressed: () => _showAddOrEditDialog(),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Dashboard Stats
                  Row(
                    children: [
                      _buildStatCard('Total Items', _allProducts.length.toString(), Icons.inventory_2),
                      const SizedBox(width: 16),
                      _buildStatCard('Low Stock', lowStockCount.toString(), Icons.warning_amber_rounded, color: Colors.orange),
                      const SizedBox(width: 16),
                      _buildStatCard('Est. Value', '₹${totalValue.toStringAsFixed(0)}', Icons.account_balance_wallet),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Search Bar
                  TextField(
                    controller: _searchController,
                    onChanged: _filterProducts,
                    decoration: InputDecoration(
                      hintText: 'Search inventory by name, Tamil alias, or barcode...',
                      prefixIcon: const Icon(Icons.search, color: Colors.teal),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
            
            // Product List DataGrid Header
            Container(
              decoration: BoxDecoration(color: Colors.grey.shade200, border: Border(top: BorderSide(color: Colors.grey.shade300), bottom: BorderSide(color: Colors.grey.shade300))),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(
                      width: 50, 
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), 
                      alignment: Alignment.center,
                      child: Checkbox(
                        value: _selectedProductIds.length == _filteredProducts.length && _filteredProducts.isNotEmpty,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedProductIds = _filteredProducts.map((p) => p.id).toSet();
                            } else {
                              _selectedProductIds.clear();
                            }
                          });
                        },
                      )
                    ),
                    VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                    Container(width: 50, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('S.No', style: TextStyle(fontWeight: FontWeight.bold))),
                    VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                    Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Product Code', style: TextStyle(fontWeight: FontWeight.bold)))),
                    VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                    Expanded(flex: 3, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold)))),
                    VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                    Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Stock', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)))),
                    VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                    Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Pur. Price', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)))),
                    VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                    Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Sale Price', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold)))),
                    VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                    Container(width: 100, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Actions', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              ),
            ),
            
            // Product List DataGrid Body
            Expanded(
              child: _filteredProducts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No products found', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final p = _filteredProducts[index];
                      final isLow = p.stockQty < 5;
                      final bgColor = index % 2 == 0 ? Colors.white : Colors.grey.shade50;
                      final tamilAlias = (p.searchAliases != null && p.searchAliases!.isNotEmpty) ? '  •  ${p.searchAliases}' : '';
                      
                      return Container(
                        decoration: BoxDecoration(
                          color: isLow ? Colors.red.shade50 : bgColor,
                          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showAddOrEditDialog(product: p),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  Container(
                                    width: 50, 
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                                    alignment: Alignment.center,
                                    child: Checkbox(
                                      value: _selectedProductIds.contains(p.id),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) _selectedProductIds.add(p.id);
                                          else _selectedProductIds.remove(p.id);
                                        });
                                      }
                                    )
                                  ),
                                  VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                                  Container(width: 50, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), alignment: Alignment.centerLeft, child: Text('${index + 1}')),
                                  VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                                  Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(p.barcode ?? '-', style: TextStyle(color: Colors.grey.shade700)))),
                                  VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                                  Expanded(
                                    flex: 3, 
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: RichText(
                                        text: TextSpan(
                                          style: const TextStyle(color: Colors.black87, fontSize: 14),
                                          children: [
                                            TextSpan(text: p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            TextSpan(text: tamilAlias, style: TextStyle(color: Colors.teal.shade700, fontSize: 12)),
                                          ]
                                        )
                                      ),
                                    )
                                  ),
                                  VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                                  Expanded(
                                    flex: 1, 
                                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), alignment: Alignment.centerRight, child: Text('${p.stockQty} ${p.unit}', style: TextStyle(fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.black87)))
                                  ),
                                  VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                                  Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), alignment: Alignment.centerRight, child: Text('₹${p.costPrice.toStringAsFixed(2)} / ${p.unit}', style: TextStyle(color: Colors.grey.shade600)))),
                                  VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                                  Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), alignment: Alignment.centerRight, child: Text('₹${p.price.toStringAsFixed(2)} / ${p.unit}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)))),
                                  VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade200),
                                  Container(
                                    width: 100, 
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.add_shopping_cart, size: 20, color: Colors.teal),
                                          tooltip: 'Stock Adjustment',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showStockAdjustDialog(p),
                                        ),
                                        const SizedBox(width: 12),
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
                                          tooltip: 'Edit Product',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showAddOrEditDialog(product: p),
                                        ),
                                      ],
                                    )
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, {Color? color}) {
    final c = color ?? Colors.white;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: c, size: 28),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c)),
            Text(title, style: TextStyle(fontSize: 14, color: c.withOpacity(0.8))),
          ],
        ),
      ),
    );
  }
}
