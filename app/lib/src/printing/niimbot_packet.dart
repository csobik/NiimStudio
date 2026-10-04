import 'dart:typed_data';

const niimbotPacketOverhead = 7;
const niimbotMaximumPayloadLength = 255;

final class NiimbotProtocolException implements Exception {
  const NiimbotProtocolException(this.message);

  final String message;

  @override
  String toString() => 'NiimbotProtocolException: $message';
}

final class NiimbotPacket {
  NiimbotPacket(this.type, Uint8List data) : data = Uint8List.fromList(data) {
    if (type < 0 || type > 0xff) {
      throw ArgumentError.value(type, 'type', 'Must fit in one byte');
    }
    if (data.length > niimbotMaximumPayloadLength) {
      throw ArgumentError.value(
        data.length,
        'data',
        'Payload must not exceed 255 bytes',
      );
    }
  }

  factory NiimbotPacket.fromBytes(Uint8List bytes) {
    if (bytes.length < niimbotPacketOverhead) {
      throw const NiimbotProtocolException('Packet is too short');
    }
    if (bytes[0] != 0x55 || bytes[1] != 0x55) {
      throw const NiimbotProtocolException('Packet header is invalid');
    }
    if (bytes[bytes.length - 2] != 0xaa || bytes.last != 0xaa) {
      throw const NiimbotProtocolException('Packet footer is invalid');
    }

    final payloadLength = bytes[3];
    final expectedLength = payloadLength + niimbotPacketOverhead;
    if (bytes.length != expectedLength) {
      throw NiimbotProtocolException(
        'Packet length is ${bytes.length} bytes; expected $expectedLength',
      );
    }

    final data = Uint8List.fromList(bytes.sublist(4, 4 + payloadLength));
    var checksum = bytes[2] ^ payloadLength;
    for (final value in data) {
      checksum ^= value;
    }
    if (checksum != bytes[bytes.length - 3]) {
      throw const NiimbotProtocolException('Packet checksum is invalid');
    }
    return NiimbotPacket(bytes[2], data);
  }

  final int type;
  final Uint8List data;

  Uint8List toBytes() {
    var checksum = type ^ data.length;
    for (final value in data) {
      checksum ^= value;
    }
    return Uint8List.fromList([
      0x55,
      0x55,
      type,
      data.length,
      ...data,
      checksum,
      0xaa,
      0xaa,
    ]);
  }
}

final class NiimbotPacketDecoder {
  final List<int> _buffer = [];

  List<NiimbotPacket> add(Uint8List bytes) {
    _buffer.addAll(bytes);
    final packets = <NiimbotPacket>[];
    while (true) {
      final packetStart = _headerIndex();
      if (packetStart < 0) {
        final preserveHeaderByte = _buffer.isNotEmpty && _buffer.last == 0x55;
        _buffer
          ..clear()
          ..addAll(preserveHeaderByte ? const [0x55] : const []);
        return packets;
      }
      if (packetStart > 0) {
        _buffer.removeRange(0, packetStart);
      }
      if (_buffer.length < 4) {
        return packets;
      }

      final packetLength = _buffer[3] + niimbotPacketOverhead;
      if (_buffer.length < packetLength) {
        return packets;
      }
      final packetBytes = Uint8List.fromList(_buffer.sublist(0, packetLength));
      _buffer.removeRange(0, packetLength);
      packets.add(NiimbotPacket.fromBytes(packetBytes));
    }
  }

  void reset() => _buffer.clear();

  int _headerIndex() {
    for (var index = 0; index + 1 < _buffer.length; index++) {
      if (_buffer[index] == 0x55 && _buffer[index + 1] == 0x55) {
        return index;
      }
    }
    return -1;
  }
}
