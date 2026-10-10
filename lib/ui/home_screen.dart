import 'dart:convert';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/recommendations.dart';
import '../services/secure_budget_store.dart';
import '../services/transaction_importer.dart';

final currency = NumberFormat.currency(locale: 'en_TT', symbol: 'TT\$', decimalDigits: 2);
String money(int cents) => currency.format(cents / 100);

class HomeScreen extends StatefulWidget {
  final SecureBudgetStore store;
  final VoidCallback onLock;
  const HomeScreen({super.key, required this.store, required this.onLock});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BudgetVault? _vault;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _tab = 0;
  int _filter = 0; // all, credits, debits
  bool _saving = false;
  Future<void> _saveQueue = Future<void>.value();
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.store.load();
      if (mounted) setState(() => _vault = loaded);
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    }
  }

  Future<void> _persist() async {
    if (_vault == null) return;
    // Snapshot now, then serialize writes. Two fast edits must not allow an
    // older asynchronous write to replace a newer encrypted report.
    final snapshot = BudgetVault.fromEncodedJson(_vault!.toEncodedJson());
    setState(() => _saving = true);
    final current = _saveQueue.then((_) => widget.store.save(snapshot));
    _saveQueue = current.catchError((Object _) {});
    try {
      await current;
    } catch (e) {
      if (mounted) _message('Unable to save encrypted budget: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String get _selectedMonth => monthKey(_month);
  MonthlyReport get _report => _vault!.reportFor(_selectedMonth);

  void _shiftMonth(int by) => setState(() {
        _month = DateTime(_month.year, _month.month + by);
      });

  Future<void> _chooseMonth() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (date != null) setState(() => _month = DateTime(date.year, date.month));
  }

  Future<void> _importCsv() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
      );
      if (file == null) return;
      final length = await file.length();
      if (length != null && length > 10 * 1024 * 1024) {
        throw const FormatException('Maximum CSV file size is 10 MB.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Maximum CSV file size is 10 MB.');
      }
      if (!mounted) return;
      final controller = TextEditingController(text: 'Republic Bank');
      final account = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import bank transactions'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Use a unique account label for each account. This helps prevent duplicate transactions.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 50,
              decoration: const InputDecoration(labelText: 'Account label'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('Import'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (account == null || !mounted) return;
      final parsed = TransactionImporter.parse(utf8.decode(bytes), account: account);
      if (parsed.transactions.isEmpty) {
        _message('No valid transactions found. ${parsed.skippedRows} rows skipped.');
        return;
      }
      final months = parsed.transactions.map((t) => t.month).toSet();
      final count = _vault!.mergeTransactions(parsed.transactions);
      setState(() {
        if (months.isNotEmpty) {
          final sorted = months.toList()..sort();
          _month = monthFromKey(sorted.last);
        }
      });
      await _persist();
      if (mounted) _message('$count new transactions imported; ${parsed.skippedRows} skipped. Existing transactions were preserved.');
    } catch (e) {
      if (mounted) _message('Import failed: $e');
    }
  }

  Future<void> _newTransaction() async {
    final description = TextEditingController();
    final amount = TextEditingController();
    bool isCredit = false;
    String category = 'Other';
    DateTime date = DateTime(_month.year, _month.month, min(DateTime.now().day,
        DateTime(_month.year, _month.month + 1, 0).day));
    final entered = await showDialog<BudgetTransaction>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, rebuild) => AlertDialog(
          title: const Text('Add transaction'),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Debit')),
                ButtonSegment(value: true, label: Text('Credit')),
              ],
              selected: {isCredit},
              onSelectionChanged: (selection) => rebuild(() {
                isCredit = selection.first;
                category = isCredit ? 'Income' : 'Other';
              }),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: description,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (TTD)', prefixText: 'TT\$ '),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: ['Income', ...expenseCategories].map((c) =>
                  DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) { if (v != null) rebuild(() => category = v); },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text(DateFormat('d MMM yyyy').format(date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: dialogContext,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) rebuild(() => date = picked);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final parsed = double.tryParse(amount.text.replaceAll(',', '').trim());
                if (description.text.trim().isEmpty || parsed == null || !parsed.isFinite || parsed <= 0) {
                  _message('Enter a description and a positive amount.');
                  return;
                }
                final cents = (parsed * 100).round();
                if (cents <= 0) return;
                Navigator.pop(dialogContext, BudgetTransaction(
                  id: 'manual-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
                  date: date,
                  description: description.text.trim(),
                  amountCents: isCredit ? cents : -cents,
                  category: category,
                  account: 'Manual',
                  source: 'manual',
                ));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    description.dispose();
    amount.dispose();
    if (entered == null) return;
    _vault!.mergeTransactions([entered]);
    setState(() => _month = DateTime(entered.date.year, entered.date.month));
    await _persist();
  }

  Future<void> _editBudgets() async {
    final current = _vault!.budgetFor(_selectedMonth);
    final controllers = {
      for (final name in expenseCategories)
        name: TextEditingController(text: current.containsKey(name) && current[name]! > 0
            ? (current[name]! / 100).toStringAsFixed(2) : ''),
    };
    final values = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 24),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: min(MediaQuery.sizeOf(sheetContext).height * .75, 730),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Plan for ${DateFormat('MMMM yyyy').format(_month)}',
                  style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Set category spending limits in TTD. Empty means no limit.'),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(children: [
                  for (final name in expenseCategories)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controllers[name],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: name, prefixText: 'TT\$ '),
                      ),
                    ),
                ]),
              ),
              FilledButton(
                onPressed: () {
                  final data = <String, int>{};
                  for (final entry in controllers.entries) {
                    final value = entry.value.text.trim().replaceAll(',', '');
                    if (value.isEmpty) continue;
                    final amount = double.tryParse(value);
                    if (amount == null || !amount.isFinite || amount < 0) {
                      _message('Budgets must be positive numbers.');
                      return;
                    }
                    data[entry.key] = (amount * 100).round();
                  }
                  Navigator.pop(sheetContext, data);
                },
                child: const Text('Save monthly budget'),
              ),
            ]),
          ),
        ),
      ),
    );
    for (final controller in controllers.values) { controller.dispose(); }
    if (values == null) return;
    _vault!.setBudgets(_selectedMonth, values);
    setState(() {});
    await _persist();
  }

  Future<void> _changeCategory(BudgetTransaction t) async {
    final category = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Choose a category', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          ),
          for (final c in ['Income', ...expenseCategories])
            ListTile(
              title: Text(c),
              trailing: c == t.category ? const Icon(Icons.check_circle) : null,
              onTap: () => Navigator.pop(context, c),
            ),
        ]),
      ),
    );
    if (category == null || category == t.category) return;
    _vault!.updateCategory(t.id, category);
    setState(() {});
    await _persist();
  }

  Future<void> _deleteTransaction(BudgetTransaction t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text(t.description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    _vault!.removeTransaction(t.id);
    setState(() {});
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pocket Budget')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 60, color: Colors.deepOrange),
            const SizedBox(height: 12),
            const Text('Unable to open private budget', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SelectableText(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text('Your data has not been reset. Check your device key store and consult README before changing anything.'),
          ],
        ))),
      );
    }
    if (_vault == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF126B66)),
          SizedBox(width: 8),
          Text('Pocket Budget', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          if (_saving) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(tooltip: 'Lock', onPressed: widget.onLock, icon: const Icon(Icons.lock_outline_rounded)),
        ],
      ),
      body: Column(children: [
        _monthBar(),
        Expanded(child: switch (_tab) {
          0 => _overview(),
          1 => _activity(),
          2 => _insights(),
          _ => _history(),
        }),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.lightbulb_outline_rounded), selectedIcon: Icon(Icons.lightbulb_rounded), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'History'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTransaction,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
    );
  }

  Widget _monthBar() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Row(children: [
          IconButton(onPressed: () => _shiftMonth(-1), tooltip: 'Previous month', icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(child: InkWell(
            onTap: _chooseMonth,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(DateFormat('MMMM yyyy').format(_month), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded),
            ]),
          )),
          IconButton(onPressed: () => _shiftMonth(1), tooltip: 'Next month', icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      );

  Widget _overview() {
    final report = _report;
    final budgets = _vault!.budgetFor(_selectedMonth);
    final monthlyTransactions = _transactionsForMonth();
    final hasLimit = report.plannedCents > 0;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 106), children: [
      Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF0A3D4A), Color(0xFF137A71)]),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('NET CASH FLOW', style: TextStyle(color: Color(0xFFCAE6E0), fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(money(report.netCents), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 35)),
          const SizedBox(height: 6),
          Text('${report.transactionCount} transactions • stored on this device',
              style: const TextStyle(color: Color(0xFFDCF7F2), fontSize: 12)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _heroAmount('Credits', report.incomeCents, Icons.south_west_rounded)),
            const SizedBox(width: 16),
            Expanded(child: _heroAmount('Debits', report.expensesCents, Icons.north_east_rounded)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      Card(child: Padding(
        padding: const EdgeInsets.all(19),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Monthly budget', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            TextButton.icon(onPressed: _editBudgets, icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit')),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Spent: ${money(report.expensesCents)}'),
            Text(hasLimit ? 'Limit: ${money(report.plannedCents)}' : 'No limits set'),
          ]),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            minHeight: 10,
            borderRadius: BorderRadius.circular(10),
            value: hasLimit ? (report.expensesCents / report.plannedCents).clamp(0.0, 1.0) : 0,
            backgroundColor: const Color(0xFFE8EEF0),
            color: hasLimit && report.expensesCents > report.plannedCents ? Colors.deepOrange : const Color(0xFF12A48F),
          ),
          const SizedBox(height: 8),
          Text(hasLimit ? '${money(report.budgetRemainingCents)} left against planned spending' :
              'Set limits to track your spending against a plan.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
      )),
      const SizedBox(height: 16),
      _sectionHeading('Expenses by category', action: 'Edit limits', onPressed: _editBudgets),
      const SizedBox(height: 10),
      if (report.byCategory.isEmpty)
        _emptyCard('No spending in this month yet.')
      else
        Card(child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(children: [
            for (final entry in (report.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
              _categoryBar(entry.key, entry.value, budgets[entry.key] ?? 0, report.expensesCents),
          ]),
        )),
      const SizedBox(height: 16),
      _sectionHeading('Recent activity', action: 'See all', onPressed: () => setState(() => _tab = 1)),
      const SizedBox(height: 8),
      if (monthlyTransactions.isEmpty) _emptyCard('Import a CSV or use Add to record your first transaction.')
      else Card(child: Column(children: [
        for (final t in monthlyTransactions.take(4)) _transactionTile(t),
      ])),
      const SizedBox(height: 18),
      OutlinedButton.icon(onPressed: _importCsv, icon: const Icon(Icons.file_upload_outlined), label: const Text('Import bank CSV statement')),
    ]);
  }

  Widget _heroAmount(String label, int value, IconData icon) => Row(children: [
        Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white, size: 18)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFFCAE6E0), fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child:
              Text(money(value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18))),
        ])),
      ]);

  Widget _sectionHeading(String title, {String? action, VoidCallback? onPressed}) =>
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        if (action != null) TextButton(onPressed: onPressed, child: Text(action)),
      ]);

  Widget _categoryBar(String name, int amount, int limit, int total) {
    final progress = total == 0 ? 0.0 : amount / total;
    final exceeded = limit > 0 && amount > limit;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(money(amount), style: TextStyle(color: exceeded ? Colors.deepOrange : null, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 7,
          backgroundColor: const Color(0xFFF0F1F4),
          borderRadius: BorderRadius.circular(8),
          color: exceeded ? Colors.deepOrange : const Color(0xFF12A48F),
        ),
        if (limit > 0) Padding(padding: const EdgeInsets.only(top: 3), child: Align(
          alignment: Alignment.centerRight,
          child: Text('Limit ${money(limit)}${exceeded ? ' • Over limit' : ''}', style: const TextStyle(fontSize: 11)),
        )),
      ]),
    );
  }

  List<BudgetTransaction> _transactionsForMonth() => _vault!.transactions
      .where((t) => t.month == _selectedMonth)
      .toList()
    ..sort((a, b) {
      final dates = b.date.compareTo(a.date);
      return dates != 0 ? dates : b.id.compareTo(a.id);
    });

  Widget _activity() {
    final data = _transactionsForMonth().where((t) => _filter == 0 ||
        (_filter == 1 && t.isCredit) || (_filter == 2 && !t.isCredit)).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 100), children: [
      Row(children: [
        Expanded(child: _sectionHeading('Transactions')),
        IconButton(tooltip: 'Import CSV', onPressed: _importCsv, icon: const Icon(Icons.file_upload_outlined)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 8, children: [
        for (final option in [(0, 'All'), (1, 'Credits'), (2, 'Debits')])
          ChoiceChip(label: Text(option.$2), selected: _filter == option.$1,
              onSelected: (_) => setState(() => _filter = option.$1)),
      ]),
      const SizedBox(height: 10),
      if (data.isEmpty)
        _emptyCard('No matching transactions. Import a CSV or add one manually.')
      else
        Card(child: Column(children: [for (final txn in data) _transactionTile(txn, canDelete: true)])),
    ]);
  }

  Widget _transactionTile(BudgetTransaction txn, {bool canDelete = false}) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
        leading: CircleAvatar(
          backgroundColor: txn.isCredit ? const Color(0xFFE2F4ED) : const Color(0xFFFFEBE5),
          child: Icon(txn.isCredit ? Icons.south_west : Icons.north_east,
              color: txn.isCredit ? const Color(0xFF11836B) : const Color(0xFFC66547), size: 19),
        ),
        title: Text(txn.description, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${DateFormat('d MMM').format(txn.date)} · ${txn.category} · ${txn.account}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${txn.isCredit ? '+' : '−'}${money(txn.amountCents.abs())}',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
                  color: txn.isCredit ? const Color(0xFF11836B) : const Color(0xFF243443))),
          if (canDelete) PopupMenuButton<String>(
            tooltip: 'Transaction options',
            onSelected: (action) {
              if (action == 'category') _changeCategory(txn);
              if (action == 'delete') _deleteTransaction(txn);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'category', child: Text('Change category')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        onTap: () => _changeCategory(txn),
      );

  Widget _insights() {
    final report = _report;
    final items = recommendationsFor(report, _vault!.budgetFor(_selectedMonth));
    return ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 100), children: [
      _sectionHeading('Your monthly insights'),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('AT A GLANCE', style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _metric('Recorded credits', money(report.incomeCents), Icons.arrow_downward_rounded),
          _metric('Recorded debits', money(report.expensesCents), Icons.arrow_upward_rounded),
          _metric('Net difference', money(report.netCents), Icons.savings_outlined),
          _metric('Planned spending', money(report.plannedCents), Icons.track_changes_rounded),
        ],
      ))),
      const SizedBox(height: 18),
      _sectionHeading('Suggestions'),
      const SizedBox(height: 8),
      for (final suggestion in items)
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tips_and_updates_outlined, color: Color(0xFF126B66)),
            const SizedBox(width: 12),
            Expanded(child: Text(suggestion)),
          ],
        ))),
      const SizedBox(height: 12),
      const Text('Insights are rule-based and based on available transactions, not professional financial advice.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 22),
      _sectionHeading('Bring in bank activity'),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Export your transactions as CSV from your own bank account, then import the file here. The app never requests your banking password.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _importCsv, icon: const Icon(Icons.file_upload_outlined), label: const Text('Import statement')),
          const SizedBox(height: 8),
          const Text('Date format: DD/MM/YYYY or ISO. Headers: Date, Description, and either Amount or Debit/Credit. Review the preview data and categories after import.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ))),
    ]);
  }

  Widget _metric(String label, String value, IconData icon) =>
      Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
        Icon(icon, color: const Color(0xFF126B66), size: 20),
        const SizedBox(width: 9),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]));

  Widget _history() {
    final keys = _vault!.reports.keys.toList()..sort((a, b) => b.compareTo(a));
    return ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 100), children: [
      _sectionHeading('Saved monthly reports'),
      const SizedBox(height: 6),
      const Text('One report per month. New imports update that report instead of creating copies.',
          style: TextStyle(color: Colors.black54, fontSize: 12)),
      const SizedBox(height: 16),
      if (keys.isEmpty)
        _emptyCard('No saved months yet. Your reports appear automatically when you record activity or set a budget.'),
      for (final key in keys)
        Card(child: ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 18),
          title: Text(DateFormat('MMMM yyyy').format(monthFromKey(key)),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${_vault!.reports[key]!.transactionCount} transactions · Spent ${money(_vault!.reports[key]!.expensesCents)}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            Text(money(_vault!.reports[key]!.netCents), style: const TextStyle(fontWeight: FontWeight.bold)),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ]),
          onTap: () => setState(() {
            _month = monthFromKey(key);
            _tab = 0;
          }),
        )),
    ]);
  }

  Widget _emptyCard(String text) => Card(
        child: Padding(padding: const EdgeInsets.all(24), child: Center(
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)))),
      );
}
