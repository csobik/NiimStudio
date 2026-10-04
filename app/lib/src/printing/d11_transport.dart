import 'dart:typed_data';

abstract interface class D11PrinterTransport {
  Stream<Uint8List> get notifications;

  Future<void> open();

  Future<void> write(Uint8List bytes);

  Future<void> close();
}
