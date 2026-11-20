import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:money_manager/app/app.dart';
import 'package:money_manager/core/database/database.dart';
import 'package:money_manager/core/database/database_provider.dart';

void main() {
  testWidgets('Dashboard renders without crashing', (WidgetTester tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MoneyManagerApp(),
      ),
    );
    // Not pumpAndSettle: the dashboard's Drift streams stay open (by
    // design, for live updates), so there's always a pending timer and
    // pumpAndSettle would never return. A few pumps are enough for the
    // first stream emissions to land.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Your money'), findsOneWidget);

    // Close the database via tester.runAsync (real event loop, not the
    // fake-async zone testWidgets normally runs in — closing the native
    // sqlite3 connection needs real async work). Deliberately NOT calling
    // tester.pumpWidget(const SizedBox()) first: manually unmounting here
    // disposes the Riverpod container mid-test, which starts cancelling
    // every live Drift `.watch()` subscription, and racing db.close()
    // against those in-flight cancellations reliably deadlocks. Leaving
    // the widget tree mounted and closing the db first means its stream
    // controllers finish cleanly, and the framework's own end-of-test
    // teardown unmounts everything afterward with nothing left pending.
    await tester.runAsync(() => db.close());
  });
}
