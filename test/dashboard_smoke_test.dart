import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pocket_budget/models.dart';
import 'package:pocket_budget/services/locale_setup.dart';
import 'package:pocket_budget/services/secure_budget_store.dart';
import 'package:pocket_budget/ui/home_screen.dart';

// No device files, biometric prompt, or platform plugins needed in this test.
class _MemoryStore extends SecureBudgetStore {
  @override
  Future<BudgetVault> load() async => BudgetVault();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initializing the supported date locale enables TT-style monthly labels', () async {
    await initializePocketBudgetLocale();
    expect(Intl.defaultLocale, 'en_GB');
    expect(DateFormat('MMMM yyyy').format(DateTime(2026, 10)), 'October 2026');
    expect(DateFormat('d MMM yyyy').format(DateTime(2026, 10, 10)), '10 Oct 2026');
  });

  testWidgets('empty monthly dashboard renders without exceptions', (tester) async {
    await initializePocketBudgetLocale();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(store: _MemoryStore(), onLock: () {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pocket Budget'), findsOneWidget);
    expect(find.text('Monthly budget'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
