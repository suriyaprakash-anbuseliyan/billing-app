import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:drift/drift.dart' as drift;
import '../database/database.dart';

// TODO: Replace with your actual MongoDB connection string
const String _mongoDbUri = 'YOUR_MONGODB_CONNECTION_STRING';

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final syncManagerProvider = Provider<SyncManager>((ref) {
  return SyncManager(ref.watch(databaseProvider));
});

class SyncManager {
  final AppDatabase _localDb;
  Db? _mongoDb;

  SyncManager(this._localDb);

  Future<void> connect() async {
    if (_mongoDbUri == 'YOUR_MONGODB_CONNECTION_STRING') {
      print('WARNING: Please configure your MongoDB URI in sync_manager.dart');
      return;
    }
    
    try {
      _mongoDb = await Db.create(_mongoDbUri);
      await _mongoDb!.open();
      print('Successfully connected to MongoDB');
    } catch (e) {
      print('Failed to connect to MongoDB: $e');
    }
  }

  Future<void> syncData() async {
    if (_mongoDb == null || !_mongoDb!.isConnected) return;
    
    print('Starting sync...');
    try {
      await _pullProducts();
      await _pushBills();
      print('Sync complete.');
    } catch (e) {
      print('Sync failed: $e');
    }
  }

  Future<void> _pullProducts() async {
    final coll = _mongoDb!.collection('products');
    final remoteProducts = await coll.find().toList();
    
    for (var doc in remoteProducts) {
      await _localDb.into(_localDb.products).insert(
        ProductsCompanion.insert(
          id: doc['_id'].toString(),
          name: doc['name'] as String? ?? 'Unknown',
          searchAliases: drift.Value(doc['search_aliases'] as String?),
          barcode: drift.Value(doc['barcode'] as String?),
          unit: doc['unit'] as String? ?? 'pcs',
          price: (doc['price'] as num?)?.toDouble() ?? 0.0,
          stockQty: drift.Value((doc['stock_qty'] as num?)?.toDouble() ?? 0.0),
          syncStatus: const drift.Value(0), // Pulled from remote, so it's synced
        ),
        mode: drift.InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _pushBills() async {
    // Find bills that haven't been synced yet
    final pendingBills = await (_localDb.select(_localDb.bills)
      ..where((b) => b.syncStatus.equals(1))).get();
      
    if (pendingBills.isEmpty) return;

    final billsColl = _mongoDb!.collection('bills');
    
    for (var bill in pendingBills) {
      // Get items for this bill
      final items = await (_localDb.select(_localDb.billItems)
        ..where((i) => i.billId.equals(bill.id))).get();
        
      final itemsList = items.map((i) => {
        'product_id': i.productId,
        'quantity': i.quantity,
        'unit_price': i.unitPrice,
      }).toList();

      final doc = {
        '_id': bill.id,
        'bill_number': bill.billNumber,
        'customer_id': bill.customerId,
        'total': bill.total,
        'payment_mode': bill.paymentMode,
        'items': itemsList,
        'created_at': bill.createdAt,
      };

      await billsColl.save(doc);
      
      // Mark as synced locally
      await (_localDb.update(_localDb.bills)
        ..where((b) => b.id.equals(bill.id)))
        .write(const BillsCompanion(syncStatus: drift.Value(0)));
    }
  }
}
