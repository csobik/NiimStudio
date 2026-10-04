import 'package:flutter/material.dart';

import 'adapters/d11_capability_loader.dart';
import 'printing/d11_print_controller.dart';
import 'rendering/label_text_renderer.dart';
import 'ui/label_composer_screen.dart';

final class NiimStudioApp extends StatelessWidget {
  const NiimStudioApp({
    super.key,
    required this.capability,
    this.composer,
    this.printController,
  });

  final D11PreviewCapability capability;
  final LabelComposer? composer;
  final D11PrintController? printController;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xff17342f);
    const paper = Color(0xfff3f0e8);
    const accent = Color(0xff963d1d);
    return MaterialApp(
      title: 'NiimStudio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: paper,
        colorScheme: const ColorScheme.light(
          primary: ink,
          onPrimary: Colors.white,
          secondary: accent,
          onSecondary: Colors.white,
          surface: Color(0xfffffdf7),
          onSurface: Color(0xff17211f),
          outline: Color(0xff87918d),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xfffffdf7),
          border: OutlineInputBorder(),
        ),
      ),
      home: LabelComposerScreen(
        capability: capability,
        composer: composer,
        printController: printController,
      ),
    );
  }
}
