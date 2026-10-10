import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

import '../models.dart';

class ImportResult {
  final List<BudgetTransaction> transactions;
  final int skippedRows;
  const ImportResult(this.transactions, this.skippedRows);
}

/// Supports generic bank-export CSV, with aliases for common headers. It does
/// not assume or claim a particular RepublicOnline CSV schema.
class TransactionImporter {
  static String _normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static int _index(List<String> columns, List<String> names) {
    final candidates = names.map(_normalize).toSet();
    return columns.indexWhere((column) => candidates.contains(_normalize(column)));
  }

  static DateTime? _date(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    // Caribbean-first: 03/04/2026 means 3 April 2026, not March 4.
    for (final pattern in <String>[
      'yyyy-MM-dd', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-ddTHH:mm:ss',
      'dd/MM/yyyy', 'd/M/yyyy', 'dd-MM-yyyy', 'd-M-yyyy',
      'dd/MM/yy', 'MM/dd/yyyy',
    ]) {
      try {
        return DateFormat(pattern).parseStrict(value);
      } on FormatException {
        // Try next format.
      }
    }
    try {
      return DateTime.parse(value);
    } on FormatException {
      return null;
    }
  }

  static int? _money(String text) {
    var value = text.trim();
    if (value.isEmpty || value == '-') return null;
    final parenthesized = value.startsWith('(') && value.endsWith(')');
    value = value.replaceAll(RegExp(r'[,$\s()]'), '').replaceAll('TTD', '')
        .replaceAll('TT\$', '').replaceAll(r'$', '');
    final suffixDebit = value.toUpperCase().endsWith('DR');
    value = value.replaceAll(RegExp(r'(CR|DR)$', caseSensitive: false), '');
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) return null;
    final negative = parenthesized || suffixDebit || parsed < 0;
    final cents = (parsed.abs() * 100).round();
    if (cents == 0) return 0;
    return negative ? -cents : cents;
  }

  static String classify(String description, int cents) {
    if (cents > 0) return 'Income';
    final d = description.toUpperCase();
    if (RegExp(r'RENT|MORTGAGE|LANDLORD|PROPERTY').hasMatch(d)) return 'Housing';
    if (RegExp(r'GROCERY|SUPERMARKET|MARKET|FOOD|RESTAURANT|CAFE|KFC|PIZZA|DINER').hasMatch(d)) return 'Food';
    if (RegExp(r'FUEL|GAS STATION|UBER|TAXI|PARKING|TRANSPORT').hasMatch(d)) return 'Transport';
    if (RegExp(r'DIGICEL|B[M]?OBILE|TSTT|WASA|T&TEC|ELECTRIC|INTERNET|BILL|UTILITY').hasMatch(d)) return 'Bills';
    if (RegExp(r'PHARMACY|DOCTOR|HOSPITAL|MEDICAL|CLINIC').hasMatch(d)) return 'Health';
    if (RegExp(r'NETFLIX|SPOTIFY|CINEMA|GAME|DISNEY').hasMatch(d)) return 'Entertainment';
    if (RegExp(r'UNIVERSITY|SCHOOL|COURSE|TUITION').hasMatch(d)) return 'Education';
    if (RegExp(r'AMAZON|STORE|MALL|SHOP').hasMatch(d)) return 'Shopping';
    return 'Other';
  }

  static ImportResult parse(String text, {String account = 'Republic Bank'}) {
    final content = text.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n').convert(content);
    if (rows.isEmpty) throw const FormatException('CSV is empty');
    // Allow metadata lines before the header; find first matching schema.
    int headerIndex = -1;
    List<String> headers = [];
    for (int i = 0; i < rows.length && i < 15; i++) {
      final row = rows[i].map((e) => e.toString().trim()).toList();
      if (_index(row, ['Date', 'Transaction Date', 'Posting Date', 'Value Date', 'Txn Date']) >= 0 &&
          _index(row, ['Description', 'Details', 'Narrative', 'Transaction Details', 'Merchant', 'Memo']) >= 0) {
        headerIndex = i;
        headers = row;
        break;
      }
    }
    if (headerIndex < 0) {
      throw const FormatException('Could not find Date and Description column headers. See samples/transactions.csv.');
    }
    final dateIndex = _index(headers, ['Date', 'Transaction Date', 'Posting Date', 'Value Date', 'Txn Date']);
    final descIndex = _index(headers, ['Description', 'Details', 'Narrative', 'Transaction Details', 'Merchant', 'Memo']);
    final amountIndex = _index(headers, ['Amount', 'Transaction Amount', 'Net Amount', 'Signed Amount']);
    final debitIndex = _index(headers, ['Debit', 'Debits', 'Withdrawal', 'Withdrawals', 'Money Out', 'DR']);
    final creditIndex = _index(headers, ['Credit', 'Credits', 'Deposit', 'Deposits', 'Money In', 'CR']);
    final referenceIndex = _index(headers, ['Reference', 'Transaction ID', 'Transaction Reference', 'Ref', 'ID']);
    if (amountIndex < 0 && debitIndex < 0 && creditIndex < 0) {
      throw const FormatException('CSV needs an Amount or Debit/Credit column.');
    }
    final transactions = <BudgetTransaction>[];
    final duplicateOccurrences = <String, int>{};
    int skipped = 0;
    for (final row in rows.skip(headerIndex + 1)) {
      if (row.every((cell) => cell.toString().trim().isEmpty)) continue;
      String field(int index) => (index >= 0 && index < row.length) ? row[index].toString().trim() : '';
      final date = _date(field(dateIndex));
      final description = field(descIndex);
      int? amount;
      if (amountIndex >= 0) {
        amount = _money(field(amountIndex));
      } else {
        final debit = _money(field(debitIndex));
        final credit = _money(field(creditIndex));
        // Debit and credit columns must not both contain values on the same row.
        if ((debit ?? 0) != 0 && (credit ?? 0) != 0) {
          skipped++;
          continue;
        }
        amount = credit != null && credit != 0 ? credit.abs() :
            debit != null ? -debit.abs() : null;
      }
      if (date == null || description.isEmpty || amount == null || amount == 0) {
        skipped++;
        continue;
      }
      final reference = field(referenceIndex);
      final base = '$account|${date.toIso8601String()}|${description.toLowerCase()}|$amount|$reference';
      // Same input + same account => deterministic IDs; repeated imports are safe.
      // Identical rows without transaction IDs may be ambiguous across partial exports.
      final instance = duplicateOccurrences.update(base, (v) => v + 1, ifAbsent: () => 1);
      final id = sha256.convert(utf8.encode('$base|$instance')).toString();
      transactions.add(BudgetTransaction(
        id: id,
        date: date,
        description: description,
        amountCents: amount,
        category: classify(description, amount),
        account: account,
        source: 'csv',
      ));
    }
    return ImportResult(transactions, skipped);
  }
}
