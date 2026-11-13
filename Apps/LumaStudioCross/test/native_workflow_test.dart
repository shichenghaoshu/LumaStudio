import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumastudio/self_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('native image, batch and library workflow', () async {
    final temp = await Directory.systemTemp.createTemp('luma-portable-test-'),
        report = File(
          '${Directory.current.path}/../../Artifacts/Performance/portable-local-self-test.json',
        );
    try {
      final ok = await runReleaseSelfTest(temp, report);
      expect(ok, isTrue, reason: await report.readAsString());
      final data = jsonDecode(await report.readAsString());
      expect((data['checks'] as List).length, greaterThanOrEqualTo(15));
    } finally {
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
