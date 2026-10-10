import '../models.dart';

List<String> recommendationsFor(
    MonthlyReport report, Map<String, int> budgets) {
  if (report.transactionCount == 0) {
    return ['Import a statement or add a transaction to start your monthly review.'];
  }
  final result = <String>[];
  if (report.incomeCents > 0) {
    final savingsRate = report.netCents / report.incomeCents;
    if (report.netCents < 0) {
      result.add('Spending exceeds recorded income this month. Review your largest expense categories.');
    } else if (savingsRate < 0.10) {
      result.add('Your net surplus is below 10% of recorded income. Consider a savings target.');
    } else {
      result.add('Your current net surplus is ${(savingsRate * 100).round()}% of recorded income. Consider setting aside part of it.');
    }
  } else {
    result.add('No credits are recorded for this month. Add or import income for a complete picture.');
  }
  if (budgets.values.any((v) => v > 0)) {
    for (final entry in report.byCategory.entries) {
      final cap = budgets[entry.key] ?? 0;
      if (cap > 0 && entry.value > cap) {
        final over = ((entry.value - cap) / 100).toStringAsFixed(2);
        result.add('${entry.key} is over its planned limit by TT\$$over.');
      }
    }
  } else {
    result.add('Set category budgets to compare planned and actual spending.');
  }
  if ((report.byCategory['Other'] ?? 0) > report.expensesCents * .20) {
    result.add('Over 20% of expenses are in Other. Reclassify these for clearer insight.');
  }
  if (report.expensesCents > 0) {
    final biggest = report.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (biggest.isNotEmpty) {
      result.add('${biggest.first.key} is your largest expense category. Review recurring charges here first.');
    }
  }
  return result.take(5).toList();
}
