import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Use a locale that intl includes for date formatting. `en_TT` is not one
/// of intl's bundled date locales (even though TTD is our app currency).
/// English (United Kingdom) uses familiar day/month conventions for Trinidad
/// and Tobago. Call before the first DateFormat is constructed.
Future<void> initializePocketBudgetLocale() async {
  await initializeDateFormatting('en_GB');
  Intl.defaultLocale = 'en_GB';
}
