import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    AppSettingsTable,
    Accounts,
    Categories,
    NotificationRules,
    RecurringTransactions,
    Transactions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await into(appSettingsTable).insert(
            const AppSettingsTableCompanion(),
            mode: InsertMode.insertOrIgnore,
          );
          await into(accounts).insert(
            AccountsCompanion.insert(name: 'Cash'),
          );
          await _seedDefaultCategories();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(notificationRules, notificationRules.matchAnyApp);
            await m.addColumn(notificationRules, notificationRules.priority);
            await m.addColumn(notificationRules, notificationRules.dateGroup);
            await m.addColumn(notificationRules, notificationRules.dateFormat);
            await m.addColumn(notificationRules, notificationRules.noteGroup);
            await m.addColumn(notificationRules, notificationRules.nameGroup);
          }
          if (from < 3) {
            await m.addColumn(
              appSettingsTable,
              appSettingsTable.allTimeBalanceAdjustmentMinorUnits,
            );
          }
          if (from < 4) {
            await m.addColumn(
              appSettingsTable,
              appSettingsTable.includeArchivedInAllTimeBalance,
            );
          }
          if (from < 5) {
            await m.addColumn(accounts, accounts.isDefault);
            await m.addColumn(transactions, transactions.duplicateOfTransactionId);
          }
          if (from < 6) {
            await m.addColumn(transactions, transactions.description);
          }
        },
      );

  Future<void> _seedDefaultCategories() async {
    const defaults = <(String, String)>[
      ('Food', 'expense'),
      ('Home', 'expense'),
      ('Transport', 'expense'),
      ('Shopping', 'expense'),
      ('Health', 'expense'),
      ('Bills', 'expense'),
      ('Other', 'expense'),
      ('Salary', 'income'),
      ('Freelance', 'income'),
      ('Gift', 'income'),
      ('Other', 'income'),
    ];
    for (final (name, type) in defaults) {
      await into(categories).insert(
        CategoriesCompanion.insert(name: name, type: type),
      );
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'money_manager.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
