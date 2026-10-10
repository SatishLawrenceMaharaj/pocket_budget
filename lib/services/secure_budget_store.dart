import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

/// Entire dataset is an authenticated AES-256-GCM encrypted blob; encryption
/// key is generated randomly once and stored in Android Keystore / iOS Keychain
/// via flutter_secure_storage. No remote requests are made.
class SecureBudgetStore {
  static const _keyName = 'pocket_budget_v1_key';
  static const _fileName = 'private_budget_v1.enc';
  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );
  final _cipher = AesGcm.with256bits();

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<SecretKey> _key({required bool createIfMissing}) async {
    var raw = await _secureStorage.read(key: _keyName);
    if (raw == null) {
      if (!createIfMissing) {
        throw StateError('Encryption key is missing. Data cannot be decrypted.');
      }
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      raw = base64Encode(bytes);
      await _secureStorage.write(key: _keyName, value: raw);
    }
    final key = base64Decode(raw);
    if (key.length != 32) throw const FormatException('Invalid encryption key');
    return SecretKey(key);
  }

  Future<BudgetVault> load() async {
    final file = await _file();
    if (!await file.exists()) return BudgetVault();
    final key = await _key(createIfMissing: false);
    final bytes = await file.readAsBytes();
    if (bytes.length < 1 + 12 + 16 || bytes[0] != 1) {
      throw const FormatException('Invalid encrypted budget file');
    }
    final nonce = bytes.sublist(1, 13);
    final mac = Mac(bytes.sublist(bytes.length - 16));
    final ciphertext = bytes.sublist(13, bytes.length - 16);
    final plaintext = await _cipher.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return BudgetVault.fromEncodedJson(utf8.decode(plaintext));
  }

  Future<void> save(BudgetVault budget) async {
    final file = await _file();
    final key = await _key(createIfMissing: true);
    final random = Random.secure();
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final encrypted = await _cipher.encrypt(
      utf8.encode(budget.toEncodedJson()),
      secretKey: key,
      nonce: nonce,
    );
    final bytes = Uint8List.fromList([
      1, ...encrypted.nonce, ...encrypted.cipherText, ...encrypted.mac.bytes,
    ]);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    // POSIX rename replaces atomically. Windows isn't a target platform here.
    await temp.rename(file.path);
  }
}
