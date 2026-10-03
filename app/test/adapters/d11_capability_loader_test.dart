import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niimstudio/src/adapters/d11_capability_loader.dart';
import 'package:niimstudio/src/domain/label_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the versioned D11 preview capability contract', () async {
    final capability = await D11CapabilityLoader(rootBundle).load();

    expect(capability.schemaVersion, 1);
    expect(capability.modelId, 'd11');
    expect(capability.modelName, 'NIIMBOT D11');
    expect(capability.labelId, 'd-12x40');
    expect(capability.labelName, '12 x 40 mm');
    expect(capability.dpiX, 203);
    expect(capability.dpiY, 203);
    expect(capability.mediaWidthMm, 12);
    expect(capability.mediaLengthMm, 40);
    expect(
      capability.geometry.canvasFor(LabelContentOrientation.portrait),
      const LabelCanvas(
        logicalSizePx: PixelSize(width: 96, height: 320),
        displayWidthMm: 12,
        displayHeightMm: 40,
        nativeSizePx: PixelSize(width: 96, height: 320),
      ),
    );
  });
}
