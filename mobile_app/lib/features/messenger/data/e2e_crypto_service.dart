import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-End Encryption service 100% compatible with website `frontend/src/utils/e2e.js`:
/// - Key Agreement: NIST P-256 (`secp256r1`) ECDH via pure-Dart PointyCastle
///   (works identically across Android, iOS, Web, and unit tests; JWK `kty: EC`, `crv: P-256`).
/// - Cipher: AES-GCM-256 with 12-byte random IV and 16-byte MAC appended to ciphertext (Web Crypto standard).
class E2eCryptoService {
  static final pc.ECDomainParameters _p256 = pc.ECCurve_secp256r1();
  static final AesGcm _aesGcm = AesGcm.with256bits();

  static String _storageKey(String conversationId) => 'e2e_$conversationId';

  static String _base64UrlNoPad(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static Uint8List _decodeBase64Url(String input) {
    final normalized = base64Url.normalize(input);
    return Uint8List.fromList(base64Url.decode(normalized));
  }

  static Uint8List _bigIntToFixedBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static pc.FortunaRandom _createSecureRandom() {
    final rng = Random.secure();
    final seed = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    return pc.FortunaRandom()..seed(pc.KeyParameter(seed));
  }

  static Future<bool> hasKeyPair(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKey(conversationId)) != null;
  }

  /// Generate a new ECDH P-256 keypair, store private JWK locally, return public JWK JSON string.
  static Future<String> generateKeyPair(String conversationId) async {
    final keyGen = pc.ECKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.ECKeyGeneratorParameters(_p256),
          _createSecureRandom(),
        ),
      );
    final pair = keyGen.generateKeyPair();
    final priv = pair.privateKey as pc.ECPrivateKey;
    final pub = pair.publicKey as pc.ECPublicKey;

    final xBytes = _bigIntToFixedBytes(pub.Q!.x!.toBigInteger()!, 32);
    final yBytes = _bigIntToFixedBytes(pub.Q!.y!.toBigInteger()!, 32);
    final dBytes = _bigIntToFixedBytes(priv.d!, 32);

    final privateJwk = <String, dynamic>{
      'kty': 'EC',
      'crv': 'P-256',
      'x': _base64UrlNoPad(xBytes),
      'y': _base64UrlNoPad(yBytes),
      'd': _base64UrlNoPad(dBytes),
      'ext': true,
    };

    final publicJwk = <String, dynamic>{
      'kty': 'EC',
      'crv': 'P-256',
      'x': _base64UrlNoPad(xBytes),
      'y': _base64UrlNoPad(yBytes),
      'ext': true,
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(conversationId), jsonEncode(privateJwk));
    return jsonEncode(publicJwk);
  }

  /// Derive the shared AES-GCM-256 key using our stored private JWK and the peer's public JWK JSON string.
  static Future<SecretKey?> deriveSharedKey(String conversationId, String peerPublicJwkJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawPrivate = prefs.getString(_storageKey(conversationId));
      if (rawPrivate == null) return null;

      final privMap = jsonDecode(rawPrivate) as Map<String, dynamic>;
      final peerMap = jsonDecode(peerPublicJwkJson) as Map<String, dynamic>;

      final d = _bytesToBigInt(_decodeBase64Url(privMap['d'].toString()));
      final peerX = _bytesToBigInt(_decodeBase64Url(peerMap['x'].toString()));
      final peerY = _bytesToBigInt(_decodeBase64Url(peerMap['y'].toString()));

      final privKey = pc.ECPrivateKey(d, _p256);
      final peerPoint = _p256.curve.createPoint(peerX, peerY);
      final peerPubKey = pc.ECPublicKey(peerPoint, _p256);

      final agreement = pc.ECDHBasicAgreement()..init(privKey);
      final sharedInt = agreement.calculateAgreement(peerPubKey);
      final sharedBytes = _bigIntToFixedBytes(sharedInt, 32);

      return SecretKey(sharedBytes);
    } catch (_) {
      return null;
    }
  }

  /// Encrypt plaintext into Web Crypto compatible `{ ciphertext: base64, iv: base64 }`.
  static Future<({String ciphertext, String iv})> encryptMessage(
    SecretKey sharedKey,
    String plaintext,
  ) async {
    final rng = Random.secure();
    final nonce = Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));

    final box = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: sharedKey,
      nonce: nonce,
    );

    // Web Crypto AES-GCM concatenates cipherText + 16-byte authentication tag
    final combined = Uint8List(box.cipherText.length + box.mac.bytes.length)
      ..setAll(0, box.cipherText)
      ..setAll(box.cipherText.length, box.mac.bytes);

    return (
      ciphertext: base64Encode(combined),
      iv: base64Encode(nonce),
    );
  }

  /// Decrypt a Web Crypto AES-GCM message (`ciphertextB64` = ciphertext + 16-byte tag).
  static Future<String> decryptMessage(
    SecretKey sharedKey,
    String ciphertextB64,
    String ivB64,
  ) async {
    try {
      final combined = base64Decode(ciphertextB64);
      final nonce = base64Decode(ivB64);
      if (combined.length < 16) return '🔒 Unable to decrypt';

      final cipherBytes = combined.sublist(0, combined.length - 16);
      final macBytes = combined.sublist(combined.length - 16);

      final plainBytes = await _aesGcm.decrypt(
        SecretBox(cipherBytes, nonce: nonce, mac: Mac(macBytes)),
        secretKey: sharedKey,
      );
      return utf8.decode(plainBytes);
    } catch (_) {
      return '🔒 Unable to decrypt';
    }
  }
}
