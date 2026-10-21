import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'der.dart';

/// Client identity (self-signed RSA certificate) used for TLS with the TV.
///
/// The TV remembers this certificate after pairing, so it is generated once
/// and persisted.
class ClientIdentity {
  final String certPem;
  final String keyPem;
  ClientIdentity(this.certPem, this.keyPem);

  Uint8List get certDer => pemToDer(certPem);

  SecurityContext toSecurityContext() {
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(certPem.codeUnits);
    ctx.usePrivateKeyBytes(keyPem.codeUnits);
    return ctx;
  }

  static const _certKey = 'identity.cert';
  static const _keyKey = 'identity.key';

  static Future<ClientIdentity> loadOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final cert = prefs.getString(_certKey);
    final key = prefs.getString(_keyKey);
    if (cert != null && key != null) return ClientIdentity(cert, key);

    // RSA key generation in pure Dart takes a few seconds: run off the UI.
    final generated = await Isolate.run(_generate);
    await prefs.setString(_certKey, generated.$1);
    await prefs.setString(_keyKey, generated.$2);
    return ClientIdentity(generated.$1, generated.$2);
  }
}

(String, String) _generate() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final priv = pair.privateKey as RSAPrivateKey;
  final pub = pair.publicKey as RSAPublicKey;
  final dn = {'CN': 'atvremote', 'O': 'Chyri', 'OU': 'TV Remote', 'C': 'BR'};
  final csr = X509Utils.generateRsaCsrPem(dn, priv, pub);
  final cert = X509Utils.generateSelfSignedCertificate(
    priv,
    csr,
    365 * 10,
    issuer: dn,
    serialNumber: DateTime.now().millisecondsSinceEpoch.toString(),
  );
  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(priv);
  return (cert, keyPem);
}
