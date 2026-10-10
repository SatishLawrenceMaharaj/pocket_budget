import 'dart:convert';

const expenseCategories = <String>[
  'Housing', 'Food', 'Transport', 'Bills', 'Shopping',
  'Health', 'Entertainment', 'Education', 'Transfers', 'Other',
];

String monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

DateTime monthFromKey(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
}

class BudgetTransaction {
  final String id;
  final DateTime date;
  final String description;
  final int amountCents; // positive credit, negative debit
  final String category;
  final String account;
  final String source;

  const BudgetTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amountCents,
    required this.category,
    required this.account,
    required this.source,
  });

  String get month => monthKey(date);
  bool get isCredit => amountCents > 0;

  BudgetTransaction copyWith({String? category}) => BudgetTransaction(
        id: id,
        date: date,
        description: description,
        amountCents: amountCents,
        category: category ?? this.category,
        account: account,
        source: source,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'description': description,
        'amountCents': amountCents,
        'category': category,
        'account': account,
        'source': source,
      };

  factory BudgetTransaction.fromJson(Map<String, dynamic> data) =>
      BudgetTransaction(
        id: data['id'] as String,
        date: DateTime.parse(data['date'] as String),
        description: data['description'] as String,
        amountCents: (data['amountCents'] as num).toInt(),
        category: data['category'] as String,
        account: data['account'] as String? ?? '',
        source: data['source'] as String? ?? 'manual',
      );
}

class MonthlyReport {
  final String month;
  final DateTime updatedAt;
  final int incomeCents;
  final int expensesCents;
  final int plannedCents;
  final int transactionCount;
  final Map<String, int> byCategory;

  const MonthlyReport({
    required this.month,
    required this.updatedAt,
    required this.incomeCents,
    required this.expensesCents,
    required this.plannedCents,
    required this.transactionCount,
    required this.byCategory,
  });

  int get netCents => incomeCents - expensesCents;
  int get budgetRemainingCents => plannedCents - expensesCents;

  Map<String, dynamic> toJson() => {
        'month': month,
        'updatedAt': updatedAt.toIso8601String(),
        'incomeCents': incomeCents,
        'expensesCents': expensesCents,
        'plannedCents': plannedCents,
        'transactionCount': transactionCount,
        'byCategory': byCategory,
      };

  factory MonthlyReport.fromJson(Map<String, dynamic> data) => MonthlyReport(
        month: data['month'] as String,
        updatedAt: DateTime.parse(data['updatedAt'] as String),
        incomeCents: (data['incomeCents'] as num).toInt(),
        expensesCents: (data['expensesCents'] as num).toInt(),
        plannedCents: (data['plannedCents'] as num).toInt(),
        transactionCount: (data['transactionCount'] as num).toInt(),
        byCategory: (data['byCategory'] as Map<String, dynamic>)
            .map((key, value) => MapEntry(key, (value as num).toInt())),
      );
}

class BudgetVault {
  final List<BudgetTransaction> transactions;
  final Map<String, Map<String, int>> budgets;
  final Map<String, MonthlyReport> reports;

  BudgetVault({
    List<BudgetTransaction>? transactions,
    Map<String, Map<String, int>>? budgets,
    Map<String, MonthlyReport>? reports,
  })  : transactions = transactions ?? [],
        budgets = budgets ?? {},
        reports = reports ?? {};

  Map<String, int> budgetFor(String month) =>
      Map<String, int>.from(budgets[month] ?? {});

  MonthlyReport reportFor(String month) => reports[month] ?? buildReport(month);

  MonthlyReport buildReport(String month) {
    int income = 0;
    int expenses = 0;
    int count = 0;
    final categories = <String, int>{};
    for (final txn in transactions) {
      if (txn.month != month) continue;
      count++;
      if (txn.isCredit) {
        income += txn.amountCents;
      } else if (txn.amountCents < 0) {
        final amount = -txn.amountCents;
        expenses += amount;
        categories[txn.category] = (categories[txn.category] ?? 0) + amount;
      }
    }
    final budget = budgetFor(month);
    return MonthlyReport(
      month: month,
      updatedAt: DateTime.now(),
      incomeCents: income,
      expensesCents: expenses,
      plannedCents: budget.values.fold<int>(0, (a, b) => a + b),
      transactionCount: count,
      byCategory: categories,
    );
  }

  // Reports are saved in a map keyed by yyyy-MM: re-importing cannot add a
  // second report for a month. Reports are recomputed for affected months.
  void refreshMonth(String month) => reports[month] = buildReport(month);

  int mergeTransactions(List<BudgetTransaction> incoming) {
    final ids = transactions.map((t) => t.id).toSet();
    final affected = <String>{};
    int added = 0;
    for (final t in incoming) {
      if (t.amountCents == 0 || !ids.add(t.id)) continue;
      transactions.add(t);
      affected.add(t.month);
      added++;
    }
    for (final month in affected) {
      refreshMonth(month);
    }
    return added;
  }

  void updateCategory(String id, String category) {
    final idx = transactions.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final old = transactions[idx];
    transactions[idx] = old.copyWith(category: category);
    refreshMonth(old.month);
  }

  void removeTransaction(String id) {
    final idx = transactions.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final month = transactions[idx].month;
    transactions.removeAt(idx);
    refreshMonth(month);
  }

  void setBudgets(String month, Map<String, int> values) {
    budgets[month] = Map<String, int>.from(values);
    refreshMonth(month);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'transactions': transactions.map((e) => e.toJson()).toList(),
        'budgets': budgets,
        'reports': reports.map((key, value) => MapEntry(key, value.toJson())),
      };

  factory BudgetVault.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1) {
      throw const FormatException('Unsupported private data version');
    }
    return BudgetVault(
      transactions: ((data['transactions'] as List?) ?? [])
          .map((e) => BudgetTransaction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      budgets: ((data['budgets'] as Map?) ?? {}).map((key, value) => MapEntry(
            key.toString(),
            (value as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
          )),
      reports: ((data['reports'] as Map?) ?? {}).map((key, value) => MapEntry(
            key.toString(),
            MonthlyReport.fromJson(Map<String, dynamic>.from(value as Map)),
          )),
    );
  }

  String toEncodedJson() => jsonEncode(toJson());
  factory BudgetVault.fromEncodedJson(String json) =>
      BudgetVault.fromJson(Map<String, dynamic>.from(jsonDecode(json) as Map));
}
