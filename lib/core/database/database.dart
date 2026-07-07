import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'dart:io';

part 'database.g.dart';

// Sync Status: 0 = Synced, 1 = Pending Push
class Products extends Table {
  TextColumn get id => text()(); // MongoDB ObjectId string or UUID
  TextColumn get name => text()();
  TextColumn get searchAliases => text().nullable()(); // Comma separated for Tamil/Tanglish
  TextColumn get barcode => text().nullable()();
  TextColumn get unit => text()(); // kg, pcs, liter
  RealColumn get price => real()();
  RealColumn get costPrice => real().withDefault(const Constant(0.0))();
  RealColumn get stockQty => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class StockLedger extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get type => text()(); // IN, OUT
  RealColumn get quantity => real()();
  TextColumn get reason => text().nullable()(); // 'Restock', 'Damaged', 'Correction', etc.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  RealColumn get creditBalance => real().withDefault(const Constant(0.0))();
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get billNumber => text()();
  TextColumn get customerId => text().nullable()();
  RealColumn get total => real()();
  TextColumn get paymentMode => text()(); // cash, upi, card, credit
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class BillItems extends Table {
  TextColumn get id => text()();
  TextColumn get billId => text()();
  TextColumn get productId => text()();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()(); // Overridden or default price
  
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Products, Customers, Bills, BillItems, StockLedger])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(products, products.costPrice);
        }
        if (from < 3) {
          await m.addColumn(products, products.isActive);
          await m.createTable(stockLedger);
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'billing_app_v1.sqlite'));
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;
    return NativeDatabase.createInBackground(file);
  });
}
