import 'package:flutter/material.dart';

import '../features/accounts/presentation/accounts_screen.dart';
import '../features/reports/presentation/reports_tab.dart';
import '../features/settings/presentation/settings_drawer.dart';
import '../features/transactions/presentation/add_edit_transaction_sheet.dart';
import '../features/transactions/presentation/transactions_tab.dart';

/// The app's root navigation shell: a bottom nav bar with three tabs —
/// Transactions, Reports, Accounts — added 2026-11-13 per user request,
/// replacing the old single-screen Dashboard. Settings (previously opened
/// from the Dashboard's own gear icon/edge-swipe) now lives on this root
/// `Scaffold` instead, so its drawer opens the same way from any tab.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  static const _tabs = [
    TransactionsTab(),
    ReportsTab(),
    AccountsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SettingsDrawer(),
      // Wider than the Scaffold default (20px) so the edge-swipe-to-open
      // gesture (see docs/features/settings-drawer.md) is easier to hit
      // reliably — carried over from the old Dashboard, now app-wide since
      // the drawer lives on this root Scaffold.
      drawerEdgeDragWidth: 48,
      body: IndexedStack(index: _index, children: _tabs),
      // Hidden on the Accounts tab, which has its own "Add account" action
      // — this FAB is for adding a transaction, not relevant there.
      floatingActionButton: _index == 2
          ? null
          : FloatingActionButton(
              onPressed: () => showAddEditTransactionSheet(context),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Accounts',
          ),
        ],
      ),
    );
  }
}
