import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lumastudio/studio.dart';
import 'package:lumastudio/ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real device editor renders, edits, undoes, crops and exports', (
    tester,
  ) async {
    final root = await Directory((await getTemporaryDirectory()).path)
        .createTemp('luma-ui-');
    final s = Studio();
    try {
      await s.initialize(root: Directory('${root.path}/library'));
      final source = File('${root.path}/sample.jpg'),
          data = await rootBundle.load('assets/demo.jpg');
      await source.writeAsBytes(data.buffer.asUint8List());
      expect(await s.importPaths([source.path]), 1);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: LumaApp(studio: s),
        ),
      );
      Future<void> ready() async {
        for (var i = 0; i < 300; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (s.preview.value != null && !s.rendering.value) return;
        }
        fail('Preview did not settle');
      }

      await ready();
      final before = s.recipe.values[0];
      await tester.drag(find.byType(Slider).first, const Offset(60, 0));
      await ready();
      expect(s.recipe.values[0], greaterThan(before));
      await tester.tap(find.byTooltip('撤销编辑'));
      await ready();
      expect(s.recipe.values[0], before);
      await tester.ensureVisible(find.text('滤镜').first);
      await tester.tap(find.text('滤镜').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('暖调'));
      await tester.tap(find.text('暖调'));
      await ready();
      expect(s.recipe.filter, 'warm');
      await tester.ensureVisible(find.text('裁切').first);
      await tester.tap(find.text('裁切').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1:1'));
      await ready();
      expect(s.preview.value!.width, s.preview.value!.height);
      final output = await s.exportPhoto(
        s.current!,
        s.recipe,
        Directory('${root.path}/output'),
      );
      expect(await output.length(), greaterThan(1000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1),
          png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (Platform.isWindows) {
        final f = File('../../Artifacts/windows-editor-ui.png');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(png!.buffer.asUint8List());
      }
      image.dispose();
      await tester.pumpWidget(const SizedBox());
    } finally {
      await s.flush();
      s.dispose();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
