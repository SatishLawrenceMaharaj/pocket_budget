import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';

import 'services/secure_budget_store.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'en_TT';
  runApp(const PocketBudgetApp());
}

class PocketBudgetApp extends StatelessWidget {
  const PocketBudgetApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pocket Budget',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F7FB),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF126B66),
            primary: const Color(0xFF126B66),
            surface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF5F7FB),
            scrolledUnderElevation: 0,
          ),
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        home: const AppGuard(),
      );
}

class AppGuard extends StatefulWidget {
  const AppGuard({super.key});
  @override
  State<AppGuard> createState() => _AppGuardState();
}

class _AppGuardState extends State<AppGuard> with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  final _store = SecureBudgetStore();
  bool _unlocked = false;
  bool _busy = false;
  String? _error;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && _pausedAt != null &&
        DateTime.now().difference(_pausedAt!) > const Duration(seconds: 30)) {
      _pausedAt = null;
      if (_unlocked) {
        setState(() => _unlocked = false);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (!await _auth.isDeviceSupported()) {
        throw StateError('Set up a device PIN, passcode, or biometrics to protect this budget.');
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock your private budget',
        persistAcrossBackgrounding: true,
      );
      if (!mounted) return;
      if (ok) setState(() => _unlocked = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) {
      return HomeScreen(store: _store, onLock: () => setState(() => _unlocked = false));
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.account_balance_wallet_rounded, size: 74, color: Color(0xFF126B66)),
              const SizedBox(height: 18),
              Text('Pocket Budget', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Private • Encrypted • On your device', textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 18),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(_busy ? 'Authenticating…' : 'Unlock with device security'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
