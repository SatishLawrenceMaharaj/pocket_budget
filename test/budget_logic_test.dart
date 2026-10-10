import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_budget/models.dart';
import 'package:pocket_budget/services/recommendations.dart';
import 'package:pocket_budget/services/transaction_importer.dart';

void main() {
  const csv = '''Date,Description,Debit,Credit,Reference
01/10/2026,Monthly Salary,,10000.00,A1
02/10/2026,Supermarket,250.50,,A2
03/10/2026,Gas Station,100.00,,A3
''';

  test('CSV debit / credit direction and Trinidad dates', () {
    final result = TransactionImporter.parse(csv, account: 'RBL 1');
    expect(result.transactions, hasLength(3));
    expect(result.transactions[0].date.month, 10);
    expect(result.transactions[0].amountCents, 1000000);
    expect(result.transactions[1].amountCents, -25050);
    expect(result.transactions[1].category, 'Food');
  });

  test('Reimport updates existing month report, no duplicates', () {
    final vault = BudgetVault();
    final txns = TransactionImporter.parse(csv, account: 'RBL 1').transactions;
    expect(vault.mergeTransactions(txns), 3);
    expect(vault.mergeTransactions(txns), 0);
    expect(vault.reports.length, 1);
    expect(vault.reports['2026-10']!.transactionCount, 3);
    expect(vault.reports['2026-10']!.incomeCents, 1000000);
    expect(vault.reports['2026-10']!.expensesCents, 35050);
  });

  test('Budget changes refresh same saved month', () {
    final vault = BudgetVault();
    vault.mergeTransactions(TransactionImporter.parse(csv).transactions);
    vault.setBudgets('2026-10', {'Food': 20000, 'Transport': 30000});
    expect(vault.reports.length, 1);
    expect(vault.reports['2026-10']!.plannedCents, 50000);
    final restored = BudgetVault.fromEncodedJson(vault.toEncodedJson());
    expect(restored.reportFor('2026-10').plannedCents, 50000);
    expect(recommendationsFor(restored.reportFor('2026-10'),
        restored.budgetFor('2026-10')).any((s) => s.contains('over its planned limit')), isTrue);
  });

  test('Unparseable rows are skipped rather than generating transactions', () {
    final result = TransactionImporter.parse('''Date,Description,Amount
22/10/2026,Coffee,-15.25
notadate,Invalid,40.00
''');
    expect(result.transactions.length, 1);
    expect(result.skippedRows, 1);
  });
}
