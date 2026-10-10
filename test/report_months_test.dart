import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_budget/models.dart';

void main() {
  test('Different years have distinct reports and same month is updated', () {
    final store = BudgetVault();
    final december = BudgetTransaction(
      id: 'dec-a', date: DateTime(2025, 12, 31), description: 'Salary',
      amountCents: 200000, category: 'Income', account: 'Checking', source: 'manual',
    );
    final january = BudgetTransaction(
      id: 'jan-a', date: DateTime(2026, 1, 1), description: 'Rent',
      amountCents: -100000, category: 'Housing', account: 'Checking', source: 'manual',
    );
    expect(store.mergeTransactions([december, january]), 2);
    store.setBudgets('2026-01', {'Housing': 120000});
    expect(store.reports.keys.toSet(), {'2025-12', '2026-01'});
    store.updateCategory('jan-a', 'Other');
    expect(store.reports['2026-01']!.byCategory['Housing'], isNull);
    expect(store.reports['2026-01']!.byCategory['Other'], 100000);
    store.removeTransaction('jan-a');
    expect(store.reports['2026-01']!.transactionCount, 0);
    expect(store.reports.keys.toSet(), {'2025-12', '2026-01'});
  });
}
