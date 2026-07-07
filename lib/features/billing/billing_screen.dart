import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../core/database/database.dart';
import '../../core/sync/sync_manager.dart';
import '../../core/printer/printer_service.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:typed_data';
import '../../core/printer/receipt_image_generator.dart';
import '../../core/settings/settings_provider.dart';

class CartItem {
  final Product product;
  double quantity;
  double unitPrice;
  final FocusNode qtyFocusNode = FocusNode();
  final FocusNode rateFocusNode = FocusNode();
  final TextEditingController qtyCtrl = TextEditingController();
  final TextEditingController rateCtrl = TextEditingController();

  CartItem({required this.product, required this.quantity, required this.unitPrice}) {
    qtyCtrl.text = quantity == quantity.toInt() ? quantity.toInt().toString() : quantity.toStringAsFixed(2);
    rateCtrl.text = unitPrice.toStringAsFixed(2);
  }
  
  double get total => quantity * unitPrice;

  void dispose() {
    qtyFocusNode.dispose();
    rateFocusNode.dispose();
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final _uuid = const Uuid();
  
  TextEditingController? _autoCompleteCtrl;
  FocusNode? _autoCompleteFocus;
  
  List<CartItem> _cart = [];
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    for (var item in _cart) {
      item.dispose();
    }
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // F2
      if (event.logicalKey == LogicalKeyboardKey.f2) {
        if (_cart.isNotEmpty) _processBill(shouldPrint: false);
        return true;
      }
      // F3
      if (event.logicalKey == LogicalKeyboardKey.f3) {
        if (_cart.isNotEmpty) _processBill(shouldPrint: true);
        return true;
      }
      // Cmd+S / Ctrl+S
      if (event.logicalKey == LogicalKeyboardKey.keyS && (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
         if (_cart.isNotEmpty) _processBill(shouldPrint: false);
         return true;
      }
      // Cmd+P / Ctrl+P
      if (event.logicalKey == LogicalKeyboardKey.keyP && (HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed)) {
         if (_cart.isNotEmpty) _processBill(shouldPrint: true);
         return true;
      }
    }
    return false;
  }

  Future<void> _loadProducts() async {
    final db = ref.read(databaseProvider);
    final products = await (db.select(db.products)..where((t) => t.isActive.equals(true))).get();
    if (mounted) {
      setState(() {
        _allProducts = products;
        _filteredProducts = products;
        _isLoading = false;
      });
    }
  }

  void _filterProducts(String query) {
    if (query.isEmpty) {
      setState(() => _filteredProducts = _allProducts);
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        return p.name.toLowerCase().contains(lowerQuery) || 
               (p.searchAliases?.toLowerCase().contains(lowerQuery) ?? false) ||
               (p.barcode?.toLowerCase().contains(lowerQuery) ?? false);
      }).toList();
    });
  }

  void _addToCart(Product p) {
    final existingIndex = _cart.indexWhere((item) => item.product.id == p.id);
    if (existingIndex != -1) {
      _cart[existingIndex].qtyFocusNode.requestFocus();
      _cart[existingIndex].qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: _cart[existingIndex].qtyCtrl.text.length);
    } else {
      final newItem = CartItem(product: p, quantity: 1, unitPrice: p.price);
      setState(() {
        _cart.add(newItem);
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          newItem.qtyFocusNode.requestFocus();
          newItem.qtyCtrl.selection = TextSelection(baseOffset: 0, extentOffset: newItem.qtyCtrl.text.length);
        }
      });
    }
    // Clear search for next scan
    _autoCompleteCtrl?.clear();
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart[index].dispose();
      _cart.removeAt(index);
    });
  }

  void _updateCartItemQty(CartItem item, String val) {
    final parsed = double.tryParse(val);
    if (parsed != null && parsed > 0) {
      if (parsed > item.product.stockQty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Only ${item.product.stockQty} ${item.product.unit} available in stock.'), backgroundColor: Colors.red));
        return;
      }
      setState(() {
        item.quantity = parsed;
      });
    }
  }

  void _updateCartItemRate(CartItem item, String val) {
    final parsed = double.tryParse(val);
    if (parsed != null && parsed >= 0) {
      setState(() {
        item.unitPrice = parsed;
      });
    }
  }

  Future<void> _processBill({required bool shouldPrint}) async {
    if (_cart.isEmpty) return;

    final db = ref.read(databaseProvider);
    final total = _cart.fold(0.0, (sum, item) => sum + item.total);
    final billId = _uuid.v4();
    final billNum = 'B-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    // Generate image first for preview and printing
    final itemsList = _cart.map((i) {
      String displayName = i.product.name;
      if (i.product.searchAliases != null && i.product.searchAliases!.isNotEmpty) {
        // Assume searchAliases is formatted as "Tamil Name, English Name"
        displayName = i.product.searchAliases!.split(',').first.trim();
      }
      return {
        'name': displayName,
        'qty': i.quantity,
        'unit': i.product.unit,
        'price': i.unitPrice,
      };
    }).toList();

    final shopSettings = ref.read(shopSettingsProvider);

    Uint8List? pngBytes;
    if (shouldPrint) {
      pngBytes = await ReceiptImageGenerator.generateReceiptImage(
        shopSettings: shopSettings,
        billNumber: billNum,
        total: total,
        items: itemsList,
      );

      // Show Print Preview Dialog
      final userConfirmedPrint = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _PrintPreviewDialog(imageBytes: pngBytes!),
      );

      if (userConfirmedPrint != true) return; // Abort entirely if they cancel the print dialog
    }

    // Save to database
    for (var item in _cart) {
      await db.into(db.billItems).insert(
        BillItemsCompanion.insert(
          id: _uuid.v4(),
          billId: billId,
          productId: item.product.id,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
        )
      );

      final newStock = item.product.stockQty - item.quantity;
      await (db.update(db.products)..where((t) => t.id.equals(item.product.id)))
        .write(ProductsCompanion(stockQty: drift.Value(newStock), syncStatus: const drift.Value(1)));
    }

    await db.into(db.bills).insert(
      BillsCompanion.insert(
        id: billId,
        billNumber: billNum,
        customerId: const drift.Value(null),
        total: total,
        paymentMode: 'Cash',
        syncStatus: const drift.Value(1),
      )
    );

    if (shouldPrint && pngBytes != null) {
      final printer = PrinterService();
      await printer.printImageBytes(pngBytes);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bill saved successfully!'), backgroundColor: Colors.green));
      }
    }

    if (mounted) {
      setState(() {
        for (var item in _cart) { item.dispose(); }
        _cart.clear();
      });
      _autoCompleteFocus?.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _cart.fold(0.0, (sum, item) => sum + item.total);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('POS / Billing', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.history), onPressed: () => context.push('/past-bills'), tooltip: 'Past Bills'),
          IconButton(icon: const Icon(Icons.bar_chart), onPressed: () => context.push('/reports'), tooltip: 'Reports'),
          IconButton(icon: const Icon(Icons.inventory), onPressed: () => context.push('/products'), tooltip: 'Inventory'),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => context.push('/settings'), tooltip: 'Settings'),
        ],
      ),
          body: Row(
            children: [
              // LEFT PANEL: Search & Products
              Container(
                width: MediaQuery.of(context).size.width * 0.35,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(right: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Column(
                  children: [
                    // Search Bar with Autocomplete
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.teal.shade50,
                      child: Autocomplete<Product>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Product>.empty();
                          }
                          final query = textEditingValue.text.toLowerCase();
                          return _allProducts.where((p) {
                            return p.name.toLowerCase().contains(query) || 
                                   (p.searchAliases?.toLowerCase().contains(query) ?? false) ||
                                   (p.barcode?.toLowerCase().contains(query) ?? false);
                          });
                        },
                        displayStringForOption: (Product option) => option.name,
                        onSelected: (Product selection) {
                          _addToCart(selection);
                        },
                        fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                          _autoCompleteCtrl = fieldTextEditingController;
                          _autoCompleteFocus = fieldFocusNode;
                          
                          return TextField(
                            controller: fieldTextEditingController,
                            focusNode: fieldFocusNode,
                            autofocus: true,
                            style: const TextStyle(fontSize: 18),
                            decoration: InputDecoration(
                              hintText: 'Search Product or Scan Code...',
                              prefixIcon: const Icon(Icons.search, color: Colors.teal),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => fieldTextEditingController.clear(),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                            onSubmitted: (String value) {
                              onFieldSubmitted();
                            },
                          );
                        },
                        optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Product> onSelected, Iterable<Product> options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 8.0,
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: 350, maxWidth: MediaQuery.of(context).size.width * 0.35 - 32),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
                                  itemBuilder: (BuildContext context, int index) {
                                    final Product option = options.elementAt(index);
                                    final tamilName = option.searchAliases ?? '';
                                    final bool isHighlighted = AutocompleteHighlightedOption.of(context) == index;
                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Container(
                                        color: isHighlighted ? Colors.teal.shade50 : Colors.transparent,
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(option.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                                  if (tamilName.isNotEmpty) 
                                                    Text(tamilName, style: TextStyle(fontSize: 14, color: Colors.teal.shade700)),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text('₹${option.price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                                                Text('Stock: ${option.stockQty} ${option.unit}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Shop Logo/Details
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront_outlined, size: 100, color: Colors.teal.shade100),
                            const SizedBox(height: 16),
                            Text('Ready for next item', style: TextStyle(fontSize: 20, color: Colors.teal.shade300, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
              
              // RIGHT PANEL: Cart / Bill
              Expanded(
                child: Column(
                  children: [
                    // Table Header
                    Container(
                      color: Colors.teal.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Container(width: 40, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), child: const Text('S.No', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                            VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                            Expanded(flex: 3, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                            VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                            Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                            VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                            Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: const Text('Rate', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                            VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                            Expanded(flex: 1, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), alignment: Alignment.centerRight, child: const Text('Price', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)))),
                            VerticalDivider(width: 1, thickness: 1, color: Colors.teal.shade800),
                            Container(width: 60, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), alignment: Alignment.center, child: const Text('Action', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                          ],
                        ),
                      ),
                    ),
                    
                    // Cart Items
                    Expanded(
                      child: _cart.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text('Cart is empty. Search or select a product.', style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _cart.length,
                              itemBuilder: (context, index) {
                                final item = _cart[index];
                                final tamilAlias = item.product.searchAliases ?? '';
                                final displayTitle = tamilAlias.isNotEmpty ? '$tamilAlias  •  ${item.product.name}' : item.product.name;
                                
                                // Unit formatting logic
                                String displayUnit = item.product.unit;
                                final unitLower = displayUnit.toLowerCase();
                                if (unitLower == '1kg' || unitLower == '1 kg') displayUnit = 'kg';
                                if (unitLower == '1ltr' || unitLower == '1 ltr' || unitLower == '1l') displayUnit = 'ltr';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 1),
                                  decoration: BoxDecoration(
                                    color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
                                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                  ),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Container(width: 40, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), alignment: Alignment.centerLeft, child: Text('${index + 1}', style: const TextStyle(color: Colors.black54))),
                                        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                                        Expanded(
                                          flex: 3, 
                                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(displayTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)))
                                        ),
                                        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                                        // QTY Input
                                        Expanded(
                                          flex: 1, 
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            child: TextField(
                                              controller: item.qtyCtrl,
                                              focusNode: item.qtyFocusNode,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              textAlign: TextAlign.center,
                                              decoration: InputDecoration(
                                                suffixText: displayUnit,
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                isDense: true,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onChanged: (val) => _updateCartItemQty(item, val),
                                              onSubmitted: (_) {
                                                item.rateFocusNode.requestFocus();
                                                item.rateCtrl.selection = TextSelection(baseOffset: 0, extentOffset: item.rateCtrl.text.length);
                                              },
                                            ),
                                          ),
                                        ),
                                        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                                        // RATE Input
                                        Expanded(
                                          flex: 1, 
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            child: TextField(
                                              controller: item.rateCtrl,
                                              focusNode: item.rateFocusNode,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              textAlign: TextAlign.center,
                                              decoration: InputDecoration(
                                                prefixText: '₹ ',
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                isDense: true,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onChanged: (val) => _updateCartItemRate(item, val),
                                              onSubmitted: (_) {
                                                _autoCompleteFocus?.requestFocus();
                                              },
                                            ),
                                          ),
                                        ),
                                        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                                        // PRICE Display
                                        Expanded(
                                          flex: 1, 
                                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), alignment: Alignment.centerRight, child: Text('₹${item.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))
                                        ),
                                        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
                                        // ACTION
                                        Container(
                                          width: 60,
                                          alignment: Alignment.center,
                                          child: IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _removeFromCart(index),
                                            tooltip: 'Remove',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    
                    // Footer (Totals & Checkout)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Total Items: ${_cart.length}', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                                  const SizedBox(height: 4),
                                  const Text('Grand Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text('₹${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.teal)),
                                ],
                              ),
                              OutlinedButton.icon(
                                onPressed: _cart.isEmpty ? null : () {
                                  setState(() {
                                    for(var item in _cart) { item.dispose(); }
                                    _cart.clear();
                                  });
                                },
                                icon: const Icon(Icons.delete_sweep),
                                label: const Text('Clear Cart'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey.shade200,
                                    foregroundColor: Colors.teal.shade800,
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  icon: const Icon(Icons.save, size: 24),
                                  label: const Text('Save Bill [F2]', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  onPressed: _cart.isEmpty ? null : () => _processBill(shouldPrint: false),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  icon: const Icon(Icons.print, size: 24),
                                  label: const Text('Save & Print [F3]', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  onPressed: _cart.isEmpty ? null : () => _processBill(shouldPrint: true),
                                ),
                              ),
                            ],
                          ),
                        ],
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

class _PrintPreviewDialog extends StatelessWidget {
  final Uint8List imageBytes;
  const _PrintPreviewDialog({required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('Receipt Preview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), color: Colors.grey.shade100),
                child: SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Image.memory(imageBytes),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.print),
                  label: const Text('Print Now'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
