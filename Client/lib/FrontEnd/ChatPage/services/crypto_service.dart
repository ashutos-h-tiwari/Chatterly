import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class CryptoService {
  CryptoService(this.token, this.myUserId);

  final String token;
  final String myUserId;
  static const _storage = FlutterSecureStorage();

  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Ed25519 _ed25519 = Ed25519();

  // Server base (match ChatApi)
  static const String _base = 'https://chatterly-backend-f9j0.onrender.com';

  // Helper to ensure X25519 keys are exactly 32 bytes
  List<int> _ensureKeyLength32(List<int> key) {
    if (key.length == 32) return key;
    if (key.length == 33) return key.sublist(0, 32); // trim extra byte
    if (key.length > 33) return key.sublist(0, 32);
    throw Exception('Invalid key length: ${key.length}, expected 32');
  }

  Future<void> init() async {
    final existing = await _storage.read(key: 'e2ee_x25519_sk_$myUserId');
    if (existing != null) return;

    // 1) generate identity X25519 key pair
    final idKp = await _x25519.newKeyPair();
    final idPub = await idKp.extractPublicKey();
    final idSkBytes = _ensureKeyLength32(await idKp.extractPrivateKeyBytes());
    await _storage.write(
      key: 'e2ee_x25519_sk_$myUserId',
      value: base64Encode(idSkBytes),
    );
    await _storage.write(
      key: 'e2ee_x25519_pk_$myUserId',
      value: base64Encode(_ensureKeyLength32(idPub.bytes)),
    );

    // 2) generate identity signing key (Ed25519)
    final signKp = await _ed25519.newKeyPair();
    final signPub = await signKp.extractPublicKey();
    final signSkBytes = await signKp.extractPrivateKeyBytes();
    await _storage.write(
      key: 'e2ee_ed25519_sk_$myUserId',
      value: base64Encode(signSkBytes),
    );
    await _storage.write(
      key: 'e2ee_ed25519_pk_$myUserId',
      value: base64Encode(signPub.bytes),
    );

    // 3) generate signed pre-key (X25519)
    final spKp = await _x25519.newKeyPair();
    final spPub = await spKp.extractPublicKey();
    final spSkBytes = _ensureKeyLength32(await spKp.extractPrivateKeyBytes());
    final spId = DateTime.now().millisecondsSinceEpoch & 0xffffffff;
    await _storage.write(
      key: 'e2ee_signedpre_sk_$myUserId',
      value: base64Encode(spSkBytes),
    );
    await _storage.write(
      key: 'e2ee_signedpre_id_$myUserId',
      value: spId.toString(),
    );

    // sign the signedPreKey pub with Ed25519 identity signing key
    final signed = await _ed25519.sign(
      _ensureKeyLength32(spPub.bytes),
      keyPair: signKp,
    );
    final sig = base64Encode(signed.bytes);

    // 4) generate a batch of one-time prekeys
    final List<Map<String, dynamic>> otpkList = [];
    final Map<String, String> otpkPrivMap = {};
    for (var i = 0; i < 10; i++) {
      final id = (DateTime.now().millisecondsSinceEpoch + i) & 0xffffffff;
      final k = await _x25519.newKeyPair();
      final kpPub = await k.extractPublicKey();
      final kpSk = _ensureKeyLength32(await k.extractPrivateKeyBytes());
      otpkList.add({
        'keyId': id,
        'publicKey': base64Encode(_ensureKeyLength32(kpPub.bytes)),
      });
      otpkPrivMap[id.toString()] = base64Encode(kpSk);
    }
    await _storage.write(
      key: 'e2ee_onetime_priv_$myUserId',
      value: jsonEncode(otpkPrivMap),
    );

    // upload bundle to server
    await _uploadIdentityBundle(
      identityX25519Base64: base64Encode(idPub.bytes),
      identitySigningBase64: base64Encode(signPub.bytes),
      signedPreKeyId: spId,
      signedPreKeyPublicBase64: base64Encode(spPub.bytes),
      signedPreKeySignatureBase64: sig,
      oneTimePreKeys: otpkList,
    );
  }

  Future<void> _uploadIdentityBundle({
    required String identityX25519Base64,
    required String identitySigningBase64,
    required int signedPreKeyId,
    required String signedPreKeyPublicBase64,
    required String signedPreKeySignatureBase64,
    required List<Map<String, dynamic>> oneTimePreKeys,
  }) async {
    final uri = Uri.parse('$_base/api/keys/upload');
    final body = {
      'identityKey': identityX25519Base64,
      'identitySigningPublic': identitySigningBase64,
      'signedPreKeyId': signedPreKeyId,
      'signedPreKeyPublic': signedPreKeyPublicBase64,
      'signedPreKeySignature': signedPreKeySignatureBase64,
      'oneTimePreKeys': oneTimePreKeys,
    };
    await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  Future<void> _uploadIdentity(String identityKeyBase64) async {
    final uri = Uri.parse('$_base/api/keys/upload');
    final body = {
      'identityKey': identityKeyBase64,
      // server expects these fields; provide simple placeholders
      'signedPreKeyId': 1,
      'signedPreKeyPublic': identityKeyBase64,
      'signedPreKeySignature': '',
      'oneTimePreKeys': [],
    };
    await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
  }

  Future<String> encryptFor(String recipientId, String plaintext) async {
    // fetch recipient bundle (identityKey + signedPreKey + oneTimePreKey)
    final bundle = await _fetchBundle(recipientId);
    if (bundle == null || bundle['identityKey'] == null) {
      throw Exception('No recipient public key');
    }

    final rpIdentity = _ensureKeyLength32(
      base64Decode(bundle['identityKey']),
    ); // X25519 pub
    final rpSignedPre = _ensureKeyLength32(
      base64Decode(bundle['signedPreKeyPublic']),
    );
    final rpOneTime = bundle['oneTimePreKey'] != null
        ? _ensureKeyLength32(base64Decode(bundle['oneTimePreKey']['publicKey']))
        : null;
    final rpSigningPub = bundle['identitySigningPublic'] != null
        ? base64Decode(bundle['identitySigningPublic'])
        : null;

    // verify signature on signedPreKey if signing pub is available
    if (rpSigningPub != null && bundle['signedPreKeySignature'] != null) {
      try {
        final signerPublicKey = SimplePublicKey(
          rpSigningPub,
          type: KeyPairType.ed25519,
        );
        final signature = Signature(
          base64Decode(bundle['signedPreKeySignature'] as String),
          publicKey: signerPublicKey,
        );
        final ok = await _ed25519.verify(rpSignedPre, signature: signature);
        if (!ok) throw Exception('signedPreKey signature invalid');
      } catch (e) {
        // signature verification failed; abort
        throw Exception('signedPreKey signature verification failed');
      }
    }

    // load my identity and signed prekey private
    final myIdSkB64 = await _storage.read(key: 'e2ee_x25519_sk_$myUserId');
    final myIdPubB64 = await _storage.read(key: 'e2ee_x25519_pk_$myUserId');
    final mySignedSkB64 = await _storage.read(
      key: 'e2ee_signedpre_sk_$myUserId',
    );
    final mySignedId = await _storage.read(key: 'e2ee_signedpre_id_$myUserId');
    if (myIdSkB64 == null || myIdPubB64 == null || mySignedSkB64 == null) {
      throw Exception('Local keys missing');
    }

    final myIdSk = _ensureKeyLength32(base64Decode(myIdSkB64));
    final myIdPub = _ensureKeyLength32(base64Decode(myIdPubB64));
    final mySignedSk = _ensureKeyLength32(base64Decode(mySignedSkB64));

    // ephemeral
    final eph = await _x25519.newKeyPair();
    final ephPub = await eph.extractPublicKey();

    // derive DHs per X3DH-like: DH1 = DH(IKA, SPKB)
    final ika = await _x25519.newKeyPairFromSeed(myIdSk);
    final spkb = SimplePublicKey(rpSignedPre, type: KeyPairType.x25519);
    final dh1 = await _x25519.sharedSecretKey(
      keyPair: ika,
      remotePublicKey: spkb,
    );

    // DH2 = DH(EA, IKB)
    final ea = eph;
    final ikb = SimplePublicKey(rpIdentity, type: KeyPairType.x25519);
    final dh2 = await _x25519.sharedSecretKey(
      keyPair: ea,
      remotePublicKey: ikb,
    );

    // DH3 = DH(EA, SPKB)
    final dh3 = await _x25519.sharedSecretKey(
      keyPair: ea,
      remotePublicKey: spkb,
    );

    // DH4 = DH(EA, OPKB) if provided
    SecretKey? dh4;
    if (rpOneTime != null) {
      final opkb = SimplePublicKey(rpOneTime, type: KeyPairType.x25519);
      dh4 = await _x25519.sharedSecretKey(keyPair: ea, remotePublicKey: opkb);
    }

    // combine secret material
    final bytes = <int>[];
    final dh1Bytes = await dh1.extractBytes();
    final dh2Bytes = await dh2.extractBytes();
    final dh3Bytes = await dh3.extractBytes();

    if (dh1Bytes.isEmpty || dh2Bytes.isEmpty || dh3Bytes.isEmpty) {
      throw Exception('DH computation failed: empty shared secret');
    }

    bytes.addAll(dh1Bytes);
    bytes.addAll(dh2Bytes);
    bytes.addAll(dh3Bytes);
    if (dh4 != null) {
      final dh4Bytes = await dh4.extractBytes();
      if (dh4Bytes.isNotEmpty) {
        bytes.addAll(dh4Bytes);
      }
    }

    if (bytes.isEmpty) {
      throw Exception('Failed to combine DH shares: no secret material');
    }

    // Validate secret material
    if (bytes.length < 32) {
      throw Exception(
        'DH shares produced insufficient bytes: ${bytes.length}, need at least 32',
      );
    }

    try {
      final combinedKey = SecretKey(bytes);
      final derivedKeyBytes = await _hkdf.deriveKey(
        secretKey: combinedKey,
        info: utf8.encode('chatterly-x3dh'),
      );

      // Extract bytes from the derived key
      final secretKeyBytes = await derivedKeyBytes.extractBytes();

      if (secretKeyBytes.isEmpty) {
        throw Exception('HKDF derivation produced empty bytes');
      }

      // Create a new SecretKey with the derived bytes for AesGcm
      final secretKey = SecretKey(secretKeyBytes);

      final nonce = _randomBytes(12);
      final secretBox = await _aesGcm.encrypt(
        utf8.encode(plaintext),
        secretKey: secretKey,
        nonce: nonce,
      );

      final header = {
        'ephemeral': base64Encode(_ensureKeyLength32(ephPub.bytes)),
        'senderIdentity': base64Encode(myIdPub),
        if (bundle['oneTimePreKey'] != null)
          'usedOneTimePreKeyId': bundle['oneTimePreKey']['keyId'],
      };

      final envelope = {
        'header': header,
        'nonce': base64Encode(nonce),
        'cipherText': base64Encode(secretBox.cipherText),
        'tag': base64Encode(secretBox.mac.bytes),
      };

      return jsonEncode(envelope);
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  Future<String> decryptEnvelope(String envelopeJson) async {
    final map = jsonDecode(envelopeJson) as Map<String, dynamic>;
    final header = map['header'] as Map<String, dynamic>?;
    if (header == null) throw Exception('Malformed envelope');

    final ephPub = _ensureKeyLength32(
      base64Decode(header['ephemeral'] as String),
    );
    final senderIdentity = _ensureKeyLength32(
      base64Decode(header['senderIdentity'] as String),
    );
    final usedOneTimeId = header['usedOneTimePreKeyId'] != null
        ? header['usedOneTimePreKeyId'].toString()
        : null;

    final nonce = base64Decode(map['nonce'] as String);
    final cipherText = base64Decode(map['cipherText'] as String);
    final tag = base64Decode(map['tag'] as String);

    // load my keys
    final myIdSkB64 = await _storage.read(key: 'e2ee_x25519_sk_$myUserId');
    final mySignedSkB64 = await _storage.read(
      key: 'e2ee_signedpre_sk_$myUserId',
    );
    final otpkPrivRaw = await _storage.read(key: 'e2ee_onetime_priv_$myUserId');
    if (myIdSkB64 == null || mySignedSkB64 == null)
      throw Exception('Missing local keys');

    final myIdSk = _ensureKeyLength32(base64Decode(myIdSkB64));
    final mySignedSk = _ensureKeyLength32(base64Decode(mySignedSkB64));
    final otpkMap = otpkPrivRaw != null
        ? Map<String, dynamic>.from(jsonDecode(otpkPrivRaw))
        : {};

    // compute DHs as recipient
    // DH1' = DH(senderIdentityPub, mySignedPreKeyPriv)
    final senderIk = SimplePublicKey(senderIdentity, type: KeyPairType.x25519);
    final mySpk = await _x25519.newKeyPairFromSeed(mySignedSk);
    final dh1 = await _x25519.sharedSecretKey(
      keyPair: mySpk,
      remotePublicKey: senderIk,
    );

    // DH2' = DH(ephPub, myIdentityPriv)
    final eph = SimplePublicKey(ephPub, type: KeyPairType.x25519);
    final myIk = await _x25519.newKeyPairFromSeed(myIdSk);
    final dh2 = await _x25519.sharedSecretKey(
      keyPair: myIk,
      remotePublicKey: eph,
    );

    // DH3' = DH(ephPub, mySignedPreKeyPriv)
    final dh3 = await _x25519.sharedSecretKey(
      keyPair: mySpk,
      remotePublicKey: eph,
    );

    // DH4' = DH(ephPub, myOneTimePreKeyPriv) if usedOneTimeId present
    SecretKey? dh4;
    if (usedOneTimeId != null && otpkMap[usedOneTimeId] != null) {
      final otPriv = _ensureKeyLength32(base64Decode(otpkMap[usedOneTimeId]));
      final myOtp = await _x25519.newKeyPairFromSeed(otPriv);
      dh4 = await _x25519.sharedSecretKey(keyPair: myOtp, remotePublicKey: eph);
    }

    final bytes = <int>[];
    final dh1Bytes = await dh1.extractBytes();
    final dh2Bytes = await dh2.extractBytes();
    final dh3Bytes = await dh3.extractBytes();

    if (dh1Bytes.isEmpty || dh2Bytes.isEmpty || dh3Bytes.isEmpty) {
      throw Exception(
        'DH computation failed during decryption: empty shared secret',
      );
    }

    bytes.addAll(dh1Bytes);
    bytes.addAll(dh2Bytes);
    bytes.addAll(dh3Bytes);
    if (dh4 != null) {
      final dh4Bytes = await dh4.extractBytes();
      if (dh4Bytes.isNotEmpty) {
        bytes.addAll(dh4Bytes);
      }
    }

    if (bytes.isEmpty) {
      throw Exception(
        'Failed to combine DH shares during decryption: no secret material',
      );
    }

    // Validate secret material
    if (bytes.length < 32) {
      throw Exception(
        'DH shares produced insufficient bytes during decryption: ${bytes.length}, need at least 32',
      );
    }

    try {
      final combinedKey = SecretKey(bytes);
      final derivedKeyBytes = await _hkdf.deriveKey(
        secretKey: combinedKey,
        info: utf8.encode('chatterly-x3dh'),
      );

      // Extract bytes from the derived key
      final secretKeyBytes = await derivedKeyBytes.extractBytes();

      if (secretKeyBytes.isEmpty) {
        throw Exception(
          'HKDF derivation produced empty bytes during decryption',
        );
      }

      // Create a new SecretKey with the derived bytes for AesGcm
      final secretKey = SecretKey(secretKeyBytes);

      final mac = Mac(tag);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
      final clear = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clear);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchBundle(String recipientId) async {
    final uri = Uri.parse('$_base/api/keys/bundle');
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'recipientId': recipientId}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = jsonDecode(resp.body);
      if (body is Map && body['data'] is Map)
        return body['data'] as Map<String, dynamic>;
      if (body is Map && body['identityKey'] != null)
        return body as Map<String, dynamic>;
    }
    return null;
  }

  List<int> _randomBytes(int len) {
    final rnd = Random.secure();
    return List<int>.generate(len, (_) => rnd.nextInt(256));
  }
}
