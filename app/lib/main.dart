import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/adapters/d11_capability_loader.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final capability = await D11CapabilityLoader(rootBundle).load();
  runApp(NiimStudioApp(capability: capability));
}
