// lib/FrontEnd/ChatPage/services/key_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage();

  static const _privKey  = 'e2e_private_key';
  static const _pubKey   = 'e2e_public_key';

  static Future<void> saveKeyPair(String publicKey, String privateKey) async {
    await _storage.write(key: _pubKey,  value: publicKey);
    await _storage.write(key: _privKey, value: privateKey);
  }

  static Future<String?> getPublicKey()  => _storage.read(key: _pubKey);
  static Future<String?> getPrivateKey() => _storage.read(key: _privKey);

  static Future<bool> hasKeys() async {
    final k = await _storage.read(key: _pubKey);
    return k != null;
  }

  static Future<void> clearKeys() async {
    await _storage.deleteAll();
  }
}