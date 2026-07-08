// lib/FrontEnd/ChatPage/services/e2e/e2e_service.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

class E2EService {
  static const _storage = FlutterSecureStorage();
  static const _serverUrl = 'https://chatterly-backend-f9j0.onrender.com';

// In-memory Signal store
  static final InMemorySignalProtocolStore _store = InMemorySignalProtocolStore(
    generateIdentityKeyPair(),
    generateRegistrationId(false),
  );

// --- public API methods (unchanged flow) --------------------------------

// Guards against re-generating and re-uploading a brand new signed
// prekey / one-time-prekey batch every time a ChatPage is opened within
// the same app run (each call used to rotate keys and overwrite the
// server's bundle, which could invalidate an in-flight handshake from a
// peer). The in-memory Signal store itself is still only created once per
// process (see the static field above), so this flag is scoped to "have we
// already uploaded for the current process", not "across app restarts" —
// full cross-restart persistence needs a durable SignalProtocolStore
// (e.g. backed by SQLite/secure storage) implementing PreKeyStore /
// SignedPreKeyStore / SessionStore, which InMemorySignalProtocolStore does
// not provide.
  static bool _initializedThisSession = false;

  static Future<void> initAndUpload(String token) async {
    if (_initializedThisSession) return;
    final identityKeyPair = await _store.getIdentityKeyPair();
    final registrationId = await _store.getLocalRegistrationId();

    final signedPreKey = generateSignedPreKey(identityKeyPair, 1);
    _store.storeSignedPreKey(signedPreKey.id, signedPreKey);

    final preKeys = generatePreKeys(0, 100);
    for (final pk in preKeys) {
      _store.storePreKey(pk.id, pk);
    }

    await _persistStoreToStorage(identityKeyPair, registrationId, signedPreKey, preKeys);

    final uploadRes = await _uploadKeys(
      token: token,
      registrationId: registrationId,
      identityKeyPair: identityKeyPair,
      signedPreKey: signedPreKey,
      preKeys: preKeys,
    );
    try {
      debugPrint(
          'E2EService.initAndUpload: uploaded keys registrationId=$registrationId signedPreKeyId=${signedPreKey.id} uploadStatus=${uploadRes?.statusCode}');
    } catch (_) {}
    await _storage.write(key: 'signal_initialized', value: 'true');
    _initializedThisSession = true;
  }

  static Future<void> buildSession(String recipientUserId, String token, {bool force = false}) async {
    final address = SignalProtocolAddress(recipientUserId, 1);

    if (force) {
      try {
        final storeDyn = _store as dynamic;
        try {
          await storeDyn.removeSession(address);
        } catch (_) {}
        try {
          await storeDyn.deleteSession(address);
        } catch (_) {}
        try {
          await storeDyn.removeSessions(address);
        } catch (_) {}
        try {
          await storeDyn.deleteSessions(address);
        } catch (_) {}
      } catch (_) {}
    } else {
      if (await _store.containsSession(address)) return;
    }

    final res = await http.post(
      Uri.parse('$_serverUrl/api/keys/bundle'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'recipientId': recipientUserId}),
    );
    if (res.statusCode != 200) throw Exception('Failed to fetch key bundle (status ${res.statusCode})');

    final parsed = jsonDecode(res.body);
    final body = parsed is Map && parsed['data'] is Map ? parsed['data'] as Map : (parsed is Map ? parsed : {});

    try {
      debugPrint('E2EService.buildSession: bundle body -> ${jsonEncode(body)} (force=$force)');
    } catch (_) {}

    int? _parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      final s = v.toString();
      return int.tryParse(s);
    }

    String _normalizeB64Local(String s) {
      var t = s.replaceAll(RegExp(r"\s+"), '');
      t = t.replaceAll('-', '+').replaceAll('_', '/');
      final mod = t.length % 4;
      if (mod != 0) t = t + ('=' * (4 - mod));
      return t;
    }

    Uint8List _b64DecodeLocal(String? s, String name) {
      if (s == null) throw Exception('Invalid key bundle: $name missing');
      try {
        final norm = _normalizeB64Local(s);
        return base64Decode(norm);
      } catch (e) {
        throw Exception('Invalid base64 for $name: ${e.toString()}');
      }
    }

    dynamic _firstPresent(Map m, List<String> keys) {
      for (final k in keys) {
        if (m.containsKey(k) && m[k] != null) return m[k];
      }
      return null;
    }

    final registrationIdRaw = _firstPresent(body, ['registrationId', 'regId', 'registrationIdStr', 'registration']);
    final registrationId = _parseInt(registrationIdRaw) ?? 0;
    final signedPreKeyId = _parseInt(_firstPresent(body, ['signedPreKeyId', 'signedPreKey', 'spkId']));
    final deviceId = _parseInt(_firstPresent(body, ['deviceId', 'device', 'recipientDeviceId', 'device_id'])) ?? 1;

    final oneTimeRaw = _firstPresent(body, ['oneTimePreKey', 'oneTimeKey', 'oneTimePreKeyRecord']);
    final Map<String, dynamic>? oneTimeMap = (oneTimeRaw is Map) ? Map<String, dynamic>.from(oneTimeRaw) : null;
    final oneTimeKeyId = oneTimeMap != null ? _parseInt(_firstPresent(oneTimeMap, ['keyId', 'id'])) : null;

    if (registrationIdRaw == null) {
      try {
        debugPrint('E2EService.buildSession: registrationId missing in bundle — defaulting to 0');
      } catch (_) {}
    }
    if (signedPreKeyId == null) {
      throw Exception('Invalid key bundle: signedPreKeyId missing or not a number');
    }

    final signedPreKeyPublicB64 = _firstPresent(body, [
      'signedPreKeyPublic',
      'signedPreKey',
      'signedPreKey.public',
      'signedPreKeyPublicKey'
    ])?.toString() ??
        (_firstPresent(body, ['signedPreKey']) is Map
            ? (_firstPresent(body, ['signedPreKey']) as Map)['publicKey']?.toString()
            : null);
    final signedPreKeySigB64 = _firstPresent(body, ['signedPreKeySignature', 'signedPreKeySig', 'signedPreKey.signature'])?.toString();
    final identityKeyB64 = _firstPresent(body, ['identityKey', 'identityKeyPublic', 'identity'])?.toString();

    if (signedPreKeyPublicB64 == null || signedPreKeySigB64 == null || identityKeyB64 == null) {
      throw Exception('Invalid key bundle: missing signedPreKeyPublic/signedPreKeySignature/identityKey');
    }

    final String? oneTimePreKeyB64 = oneTimeMap != null ? _firstPresent(oneTimeMap, ['publicKey', 'public', 'key'])?.toString() : null;

// decode and convert to ECPublicKey when needed
    final ECPublicKey? oneTimePreKeyPublic;
    if (oneTimePreKeyB64 != null) {
      oneTimePreKeyPublic = Curve.decodePoint(_decodePointSafe(oneTimePreKeyB64, 'oneTimePreKey.publicKey'),0);
    } else {
      oneTimePreKeyPublic = null;
    }

    try {
      final spkPubLen = signedPreKeyPublicB64.length;
      final spkSigLen = signedPreKeySigB64.length;
      final idkLen = identityKeyB64.length;
      try {
        debugPrint(
            'E2EService.buildSession: parsed signedPreKeyId=$signedPreKeyId oneTimeKeyId=$oneTimeKeyId registrationId=$registrationId signedPreKeyPublic.len=$spkPubLen signedPreKeySig.len=$spkSigLen identityKey.len=$idkLen');
      } catch (_) {}
    } catch (_) {}

    final signedPreKeyPublic = Curve.decodePoint(_decodePointSafe(signedPreKeyPublicB64, 'signedPreKeyPublic'),0);
    final signedPreKeySignature = _b64DecodeLocal(signedPreKeySigB64, 'signedPreKeySignature');
    final identityKeyPub = Curve.decodePoint(_decodePointSafe(identityKeyB64, 'identityKey'),0);

    final bundle = PreKeyBundle(
      registrationId,
      deviceId,
      oneTimeKeyId ?? 0,
      oneTimePreKeyPublic,
      signedPreKeyId,
      signedPreKeyPublic,
      signedPreKeySignature,
      IdentityKey(identityKeyPub),
    );

    final builder = SessionBuilder.fromSignalStore(_store, address);
    try {
      await builder.processPreKeyBundle(bundle);
    } catch (e, st) {
      try {
        debugPrint('E2EService.buildSession: processPreKeyBundle failed for $recipientUserId: ${e.toString()}');
      } catch (_) {}
      try {
        debugPrint(st.toString());
      } catch (_) {}
      try {
        debugPrint(
            'E2EService.buildSession: signedPreKeyPublic.len=${signedPreKeyPublicB64.length} signedPreKeySig.len=${signedPreKeySigB64.length} identityKey.len=${identityKeyB64.length} deviceId=$deviceId signedPreKeyId=$signedPreKeyId oneTimeKeyId=$oneTimeKeyId');
      } catch (_) {}

      if (e.runtimeType.toString().toLowerCase().contains('untrustedidentity')) {
        try {
          try {
            debugPrint('E2EService.buildSession: attempting to persist remote identity and retry');
          } catch (_) {}
          final remoteIdentity = IdentityKey(identityKeyPub);
          final storeDyn = _store as dynamic;
          var persisted = false;
          try {
            await storeDyn.saveIdentity(address, remoteIdentity);
            persisted = true;
          } catch (_) {}
          try {
            if (!persisted) await storeDyn.storeIdentity(address, remoteIdentity);
            persisted = persisted || true;
          } catch (_) {}
          try {
            if (!persisted) await storeDyn.setIdentity(address, remoteIdentity);
            persisted = persisted || true;
          } catch (_) {}
          try {
            if (!persisted) await storeDyn.putIdentity(address, remoteIdentity);
            persisted = persisted || true;
          } catch (_) {}
          try {
            if (!persisted) await storeDyn.setIdentityKey(address, remoteIdentity);
            persisted = persisted || true;
          } catch (_) {}

          if (persisted) {
            try {
              debugPrint('E2EService.buildSession: remote identity persisted, retrying processPreKeyBundle');
            } catch (_) {}
            await builder.processPreKeyBundle(bundle);
            try {
              debugPrint('E2EService.buildSession: retry succeeded for $recipientUserId');
            } catch (_) {}
          } else {
            try {
              debugPrint('E2EService.buildSession: unable to persist remote identity - store has no known setter');
            } catch (_) {}
            throw Exception('Invalid key bundle: Untrusted identity and failed to persist remote identity');
          }
        } catch (e2, st2) {
          try {
            debugPrint('E2EService.buildSession: retry after persisting identity failed: ${e2.toString()}');
          } catch (_) {}
          try {
            debugPrint(st2.toString());
          } catch (_) {}
          rethrow;
        }
      }

      rethrow;
    }

    try {
      final has = await _store.containsSession(address);
      try {
        debugPrint('E2EService.buildSession: session established for $recipientUserId -> $has');
      } catch (_) {}
    } catch (_) {}
  }

// Encrypt
  static Future<Map<String, String>> encrypt(String recipientUserId, String plaintext) async {
    final address = SignalProtocolAddress(recipientUserId, 1);
    final cipher = SessionCipher.fromStore(_store, address);

    final cipherMessage = await cipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));

    final contentType = cipherMessage.getType() == CiphertextMessage.prekeyType ? 'signal:prekey' : 'signal:whisper';

    return {
      'cipherText': base64Encode(cipherMessage.serialize()),
      'contentType': contentType,
    };
  }

// Decrypt
  static Future<String> decrypt(String senderUserId, String cipherTextB64, String contentType, {String? token}) async {
    final address = SignalProtocolAddress(senderUserId, 1);
    final cipher = SessionCipher.fromStore(_store, address);

    String _normalizeB64(String s) {
      var t = s.replaceAll(RegExp(r"\s+"), '');
      t = t.replaceAll('-', '+').replaceAll('_', '/');
      final mod = t.length % 4;
      if (mod != 0) t = t + ('=' * (4 - mod));
      return t;
    }

    try {
      final hasSessionBefore = await _store.containsSession(address);
      try {
        debugPrint(
            'E2EService.decrypt: hasSessionBefore=$hasSessionBefore sender=$senderUserId contentType=$contentType payloadLen=${cipherTextB64.length}');
      } catch (_) {}

      final norm = _normalizeB64(cipherTextB64);
      final bytes = base64Decode(norm);
      try {
        debugPrint('E2EService.decrypt: decoded bytes len=${bytes.length}');
      } catch (_) {}

      Uint8List plainBytes;
      if (contentType == 'signal:prekey') {
        final msg = PreKeySignalMessage(bytes);
        plainBytes = await cipher.decryptWithCallback(msg, (_) {});
      } else {
        final msg = SignalMessage.fromSerialized(bytes);
        plainBytes = await cipher.decryptFromSignal(msg);
      }

      return utf8.decode(plainBytes);
    } catch (e, st) {
      try {
        debugPrint('E2EService.decrypt failed for sender=$senderUserId contentType=$contentType error=${e.toString()}');
      } catch (_) {}
      try {
        debugPrint(st.toString());
      } catch (_) {}

      final errStr = e.toString().toLowerCase();
      if (token != null && errStr.contains('untrustedidentity')) {
        try {
          try {
            debugPrint('E2EService.decrypt: untrusted identity detected, attempting buildSession(force:true) to persist identity and retry');
          } catch (_) {}
          await buildSession(senderUserId, token, force: true);
          final cipher2 = SessionCipher.fromStore(_store, address);
          final norm2 = _normalizeB64(cipherTextB64);
          final bytes2 = base64Decode(norm2);
          Uint8List plainBytes2;
          if (contentType == 'signal:prekey') {
            final msg2 = PreKeySignalMessage(bytes2);
            plainBytes2 = await cipher2.decryptWithCallback(msg2, (_) {});
          } else {
            final msg2 = SignalMessage.fromSerialized(bytes2);
            plainBytes2 = await cipher2.decryptFromSignal(msg2);
          }
          return utf8.decode(plainBytes2);
        } catch (e2, st2) {
          try {
            debugPrint('E2EService.decrypt retry after untrusted identity failed: ${e2.toString()}');
          } catch (_) {}
          try {
            debugPrint(st2.toString());
          } catch (_) {}
        }
      }

      if (token != null &&
          (errStr.contains('bad mac') || errStr.contains('no valid sessions') || errStr.contains('invalidmessageexception'))) {
        try {
          try {
            debugPrint('E2EService.decrypt: attempting session rebuild for $senderUserId and retrying');
          } catch (_) {}
          await buildSession(senderUserId, token, force: true);
          final cipher2 = SessionCipher.fromStore(_store, address);
          final norm2 = _normalizeB64(cipherTextB64);
          final bytes2 = base64Decode(norm2);
          Uint8List plainBytes2;
          if (contentType == 'signal:prekey') {
            final msg2 = PreKeySignalMessage(bytes2);
            plainBytes2 = await cipher2.decryptWithCallback(msg2, (_) {});
          } else {
            final msg2 = SignalMessage.fromSerialized(bytes2);
            plainBytes2 = await cipher2.decryptFromSignal(msg2);
          }
          return utf8.decode(plainBytes2);
        } catch (e2, st2) {
          try {
            debugPrint('E2EService.decrypt retry failed for $senderUserId: ${e2.toString()}');
          } catch (_) {}
          try {
            debugPrint(st2.toString());
          } catch (_) {}
        }
      }

      rethrow;
    }
  }

// --- Private helpers ----------------------------------------------------

  static Uint8List _toUint8List(dynamic v) {
    if (v == null) return Uint8List(0);
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    if (v is String) return base64Decode(v);
    throw FormatException('Cannot convert ASN.1 value to Uint8List (type: ${v.runtimeType})');
  }

  static Uint8List _decodePointSafe(String b64, String name) {
    if (b64.isEmpty) throw Exception('Invalid key bundle: $name empty');

    Uint8List raw;
    try {
      raw = base64Decode(_normalizeB64(b64));
    } catch (e) {
      throw FormatException('Invalid base64 public key for $name: $e');
    }

// Common raw lengths: 32 for X25519/Curve25519; 33 if prefixed with 0x00; 65 uncompressed EC
    if (raw.length == 32) return raw;
    if (raw.length == 33 && raw[0] == 0x00) return raw.sublist(1);
    if (raw.length == 65 && raw[0] == 0x04) {
      throw FormatException(
          'Incompatible EC curve for $name: received uncompressed 65-byte EC point (likely P-256). Server must provide Curve25519 (32 bytes).');
    }

// If looks like DER/ASN.1 (starts with 0x30), parse SPKI and extract BIT STRING
    if (raw.isNotEmpty && raw[0] == 0x30) {
      try {
        final parser = ASN1Parser(raw);
        final seq = parser.nextObject() as ASN1Sequence;

        if (seq.elements.length >= 2 && seq.elements[1] is ASN1BitString) {
          final bitStr = seq.elements[1] as ASN1BitString;

          final dyn = bitStr.valueBytes ?? bitStr.contentBytes;
          var pub = _toUint8List(dyn);

// strip leading unused-bits byte if present
          if (pub.isNotEmpty && pub[0] == 0x00) {
            pub = pub.sublist(1);
          }

          if (pub.length == 32) return pub;
          if (pub.length == 33 && pub[0] == 0x00) return pub.sublist(1);
          if (pub.length == 65 && pub[0] == 0x04) {
            throw FormatException(
                'Incompatible EC curve for $name: received uncompressed 65-byte EC point (likely P-256). Server must provide Curve25519 (32 bytes).');
          }

          if (pub.isNotEmpty) return pub;
        }
      } catch (e) {
        throw FormatException('Failed to parse ASN.1 public key for $name: $e');
      }
    }

    throw FormatException(
        'Unsupported public key format for $name or unexpected length=${raw.length}. Expected raw Curve25519 (32 bytes) or ASN.1-wrapped Curve25519.');
  }

  static String _normalizeB64(String s) {
    var t = s.replaceAll(RegExp(r"\s+"), '');
    t = t.replaceAll('-', '+').replaceAll('_', '/');
    final mod = t.length % 4;
    if (mod != 0) t = t + ('=' * (4 - mod));
    return t;
  }

  static Future<http.Response?> _uploadKeys({
    required String token,
    required int registrationId,
    required IdentityKeyPair identityKeyPair,
    required SignedPreKeyRecord signedPreKey,
    required List<PreKeyRecord> preKeys,
  }) async {
    final body = jsonEncode({
      'registrationId': registrationId,
      'identityKey': base64Encode(identityKeyPair.getPublicKey().serialize()),
      'signedPreKeyId': signedPreKey.id,
      'signedPreKeyPublic': base64Encode(signedPreKey.getKeyPair().publicKey.serialize()),
      'signedPreKeySignature': base64Encode(signedPreKey.signature),
      'oneTimePreKeys': preKeys.map((pk) => {
        'keyId': pk.id,
        'publicKey': base64Encode(pk.getKeyPair().publicKey.serialize()),
      }).toList(),
    });

    try {
      final res = await http.post(
        Uri.parse('$_serverUrl/api/keys/upload'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      try {
        debugPrint('E2EService._uploadKeys: status=${res.statusCode} body=${res.body}');
      } catch (_) {}
      return res;
    } catch (e) {
      try {
        debugPrint('E2EService._uploadKeys: request failed: ${e.toString()}');
      } catch (_) {}
      return null;
    }
  }

  static Future<void> _persistStoreToStorage(
      IdentityKeyPair ikp,
      int regId,
      SignedPreKeyRecord spk,
      List<PreKeyRecord> preKeys,
      ) async {
    await _storage.write(key: 'signal_regId', value: regId.toString());
    await _storage.write(key: 'signal_identity_priv', value: base64Encode(ikp.getPrivateKey().serialize()));
    await _storage.write(key: 'signal_identity_pub', value: base64Encode(ikp.getPublicKey().serialize()));
    await _storage.write(key: 'signal_spk_id', value: spk.id.toString());
    await _storage.write(key: 'signal_spk_priv', value: base64Encode(spk.getKeyPair().privateKey.serialize()));
  }

  static Future<void> _restoreStoreFromStorage() async {
    final regIdStr = await _storage.read(key: 'signal_regId');
    final privKeyB64 = await _storage.read(key: 'signal_identity_priv');
    final pubKeyB64 = await _storage.read(key: 'signal_identity_pub');
    final spkIdStr = await _storage.read(key: 'signal_spk_id');
    try {
      debugPrint('E2EService._restoreStoreFromStorage: spkId=$spkIdStr');
    } catch (_) {}

    if (regIdStr == null || privKeyB64 == null || pubKeyB64 == null) return;

// Note: full session persistence requires a persistent SignalProtocolStore (e.g. SQLite).
  }
}