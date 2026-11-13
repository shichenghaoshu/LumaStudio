import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lumastudio/ui.dart';
import 'package:lumastudio/studio.dart';
import 'package:lumastudio/recipe.dart';

class TestStudio extends Studio {
  @override
  void schedule() {}
}

void main() {
  for (final size in [
    const Size(360, 640),
    const Size(390, 844),
    const Size(900, 600),
    const Size(1360, 860),
  ]) {
    testWidgets('usable layout at ${size.width} x ${size.height}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = TestStudio();
      await tester.pumpWidget(LumaApp(studio: s));
      await tester.pumpAndSettle();
      expect(find.text('用示例照片体验'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final skinTab = find.text('肤色').first;
      await tester.ensureVisible(skinTab);
      await tester.pumpAndSettle();
      expect(skinTab.hitTestable(), findsOneWidget);
      await tester.tap(skinTab);
      await tester.pumpAndSettle();
      expect(find.text('高强度'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('接入与导出设置'));
      await tester.pumpAndSettle();
      expect(find.text('API 密钥 · 仅本次会话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    });
  }
  test('a drag groups many parameter updates into one undo entry', () {
    final s = TestStudio();
    s.current = Photo(
      id: 'test',
      name: 'test',
      path: 'test',
      thumbnail: 'test',
    );
    s.beginGesture();
    for (var i = 1; i <= 60; i++) {
      s.change(Recipe().set(0, i / 100), gesture: true);
    }
    s.endGesture();
    expect(s.undoStack.length, 1);
    s.undo();
    expect(s.recipe.values[0], 0);
    s.redo();
    expect(s.recipe.values[0], .6);
    s.dispose();
  });
}
