import 'dart:convert';
import 'dart:typed_data';

/// Minimal Protocol Buffers encoder/decoder.
///
/// The Android TV Remote v2 protocol only uses varints and length-delimited
/// fields, so a tiny hand-written implementation avoids a `protoc` build step
/// and keeps the core portable (Windows today, Android later).
class ProtoWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  static List<int> varint(int value) {
    final out = <int>[];
    var v = value;
    if (v < 0) {
      // int32 negatives are encoded as 10-byte two's complement varints.
      v = v.toUnsigned(64);
    }
    while (v >= 0x80) {
      out.add((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.add(v);
    return out;
  }

  void _tag(int field, int wireType) => _b.add(varint((field << 3) | wireType));

  ProtoWriter int32(int field, int value) {
    _tag(field, 0);
    _b.add(varint(value));
    return this;
  }

  ProtoWriter boolean(int field, bool value) => int32(field, value ? 1 : 0);

  ProtoWriter bytes(int field, List<int> value) {
    _tag(field, 2);
    _b.add(varint(value.length));
    _b.add(value);
    return this;
  }

  ProtoWriter string(int field, String value) => bytes(field, utf8.encode(value));

  ProtoWriter message(int field, ProtoWriter value) => bytes(field, value.toBytes());

  Uint8List toBytes() => _b.toBytes();
}

/// Decoded message: field number -> list of raw values
/// (`int` for varints, `Uint8List` for length-delimited fields).
class ProtoMessage {
  final Map<int, List<Object>> fields;
  ProtoMessage(this.fields);

  factory ProtoMessage.parse(Uint8List data) {
    final fields = <int, List<Object>>{};
    var i = 0;
    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (i >= data.length) throw const FormatException('Truncated varint');
        final byte = data[i++];
        result |= (byte & 0x7F) << shift;
        if (byte & 0x80 == 0) break;
        shift += 7;
      }
      return result;
    }

    while (i < data.length) {
      final key = readVarint();
      final field = key >> 3;
      final wire = key & 0x07;
      Object value;
      switch (wire) {
        case 0:
          value = readVarint();
        case 1:
          value = Uint8List.sublistView(data, i, i + 8);
          i += 8;
        case 2:
          final len = readVarint();
          value = Uint8List.sublistView(data, i, i + len);
          i += len;
        case 5:
          value = Uint8List.sublistView(data, i, i + 4);
          i += 4;
        default:
          throw FormatException('Unsupported wire type $wire');
      }
      (fields[field] ??= []).add(value);
    }
    return ProtoMessage(fields);
  }

  bool has(int field) => fields.containsKey(field);

  int? int32(int field) {
    final v = fields[field]?.first;
    return v is int ? v : null;
  }

  bool? boolean(int field) {
    final v = int32(field);
    return v == null ? null : v != 0;
  }

  Uint8List? bytes(int field) {
    final v = fields[field]?.first;
    return v is Uint8List ? v : null;
  }

  String? string(int field) {
    final b = bytes(field);
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  ProtoMessage? message(int field) {
    final b = bytes(field);
    return b == null ? null : ProtoMessage.parse(b);
  }
}
