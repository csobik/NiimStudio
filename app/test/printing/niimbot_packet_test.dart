import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/printing/niimbot_packet.dart';

void main() {
  group('NiimbotPacket', () {
    test('matches the Python golden framing vector', () {
      final packet = NiimbotPacket(0x40, Uint8List.fromList([0x0b]));

      expect(
        packet.toBytes(),
        Uint8List.fromList([0x55, 0x55, 0x40, 0x01, 0x0b, 0x4a, 0xaa, 0xaa]),
      );
      expect(NiimbotPacket.fromBytes(packet.toBytes()).type, 0x40);
      expect(NiimbotPacket.fromBytes(packet.toBytes()).data, [0x0b]);
    });

    test('rejects malformed packets', () {
      expect(
        () => NiimbotPacket.fromBytes(Uint8List.fromList([0x55])),
        throwsA(isA<NiimbotProtocolException>()),
      );
      expect(
        () => NiimbotPacket.fromBytes(
          Uint8List.fromList([0x55, 0x55, 0x01, 0x00, 0x00, 0xaa, 0xaa]),
        ),
        throwsA(
          isA<NiimbotProtocolException>().having(
            (error) => error.message,
            'message',
            contains('checksum'),
          ),
        ),
      );
    });

    test('rejects invalid type and oversized payload', () {
      expect(() => NiimbotPacket(256, Uint8List(0)), throwsArgumentError);
      expect(() => NiimbotPacket(1, Uint8List(256)), throwsArgumentError);
    });
  });

  group('NiimbotPacketDecoder', () {
    test('buffers fragmented notifications and leading noise', () {
      final decoder = NiimbotPacketDecoder();
      final bytes = NiimbotPacket(0x31, Uint8List.fromList([1])).toBytes();

      expect(decoder.add(Uint8List.fromList([0x99, 0x55])), isEmpty);
      expect(decoder.add(Uint8List.fromList(bytes.sublist(1, 5))), isEmpty);
      final packets = decoder.add(Uint8List.fromList(bytes.sublist(5)));

      expect(packets, hasLength(1));
      expect(packets.single.type, 0x31);
      expect(packets.single.data, [1]);
    });

    test('returns multiple packets from one notification', () {
      final decoder = NiimbotPacketDecoder();
      final first = NiimbotPacket(0x02, Uint8List.fromList([1])).toBytes();
      final second = NiimbotPacket(0x04, Uint8List.fromList([1])).toBytes();

      final packets = decoder.add(Uint8List.fromList([...first, ...second]));

      expect(packets.map((packet) => packet.type), [0x02, 0x04]);
    });

    test('reports a malformed complete notification', () {
      final decoder = NiimbotPacketDecoder();

      expect(
        () => decoder.add(
          Uint8List.fromList([0x55, 0x55, 0x01, 0x00, 0x00, 0xaa, 0xaa]),
        ),
        throwsA(isA<NiimbotProtocolException>()),
      );
    });
  });
}
