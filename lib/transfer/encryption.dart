import 'package:cryptography/cryptography.dart';

class EncryptedPayload {
  final List<int> cipherText;
  final List<int> nonce;
  final List<int> mac;

  const EncryptedPayload({required this.cipherText, required this.nonce, required this.mac});
}

class QrEncryptionRequiredException implements Exception {
  final String message;

  const QrEncryptionRequiredException([this.message = 'Passphrase required']);

  @override
  String toString() => message;
}

/// AES-256-GCM encryption with a PBKDF2-derived key. This protects file
/// contents from anyone else who points a camera at the sender's screen.
/// The passphrase must be shared with the receiver out-of-band (in person,
/// chat, etc.) — it is never transmitted in the QR frames.
class QrEncryption {
  static final AesGcm _algorithm = AesGcm.with256bits();

  static Future<SecretKey> _deriveKey({required String passphrase, required List<int> salt}) {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256);
    return pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Future<EncryptedPayload> encrypt({
    required List<int> plainBytes,
    required String passphrase,
    required List<int> salt,
  }) async {
    final key = await _deriveKey(passphrase: passphrase, salt: salt);
    final secretBox = await _algorithm.encrypt(plainBytes, secretKey: key);
    return EncryptedPayload(