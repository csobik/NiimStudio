import 'd11_transport.dart';

final class D11PrinterDevice {
  const D11PrinterDevice({required this.id, required this.name, this.rssi});

  final String id;
  final String name;
  final int? rssi;
}

abstract interface class D11PrinterGateway {
  Future<List<D11PrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> cancelScan();

  D11PrinterTransport createTransport(D11PrinterDevice device);
}
