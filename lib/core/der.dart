import 'dart:convert';
import 'dart:typed_data';

/// Tiny DER reader used to pull the RSA modulus/exponent out of X.509
/// certificates (needed to compute the pairing secret).
class _Tlv {
  final int tag;
  final Uint8List content;
  _Tlv(this.tag, this.content);

  List<_Tlv> children() {
    final out = <_Tlv>[];
    var i = 0;
    while (i < content.length) {
      final r = _readTlv(content, i);
      out.add(r.$1);
      i = r.$2;
    }
    return out;
  }
}

(_Tlv, int) _readTlv(Uint8List data, int offset) {
  var i = offset;
  final tag = data[i++];
  var len = data[i++];
  if (len & 0x80 != 0) {
    final n = len & 0x7F;
    len = 0;
    for (var k = 0; k < n; k++) {
      len = (len << 8) | data[i++];
    }
  }
  final content = Uint8List.sublistView(data, i, i + len);
  return (_Tlv(tag, content), i + len);
}

Uint8List _stripLeadingZeros(Uint8List b) {
  var i = 0;
  while (i < b.length - 1 && b[i] == 0) {
    i++;
  }
  return Uint8List.sublistView(b, i);
}

class RsaPublicKeyBytes {
  /// Unsigned big-endian bytes without leading zeros.
  final Uint8List modulus;
  final Uint8List exponent;
  RsaPublicKeyBytes(this.modulus, this.exponent);
}

/// Extracts the RSA public key from a DER-encoded X.509 certificate.
RsaPublicKeyBytes rsaPublicKeyFromCertificateDer(Uint8List der) {
  final cert = _readTlv(der, 0).$1;
  final tbs = cert.children().first;
  final tbsChildren = tbs.children();
  // Optional explicit version tag [0].
  final base = tbsChildren.first.tag == 0xA0 ? 1 : 0;
  // serial, signature, issuer, validity, subject, subjectPublicKeyInfo
  final spki = tbsChildren[base + 5];
  final bitString = spki.children()[1];
  // First byte of a BIT STRING is the number of unused bits.
  final rsaKey = _readTlv(Uint8List.sublistView(bitString.content, 1), 0).$1;
  final ints = rsaKey.children();
  return RsaPublicKeyBytes(
    _stripLeadingZeros(ints[0].content),
    _stripLeadingZeros(ints[1].content),
  );
}

/// Decodes the first PEM block body into DER bytes.
Uint8List pemToDer(String pem) {
  final lines = pem
      .split(RegExp(r'\r?\n'))
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64.decode(lines.trim());
}
