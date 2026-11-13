import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ui.dart';
import 'self_test.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final name in ['COPYRIGHT', 'LICENSE.CDDL']) {
      yield LicenseEntryWithLineBreaks([
        'LibRaw 0.22.3',
      ], await rootBundle.loadString('assets/licenses/$name'));
    }
    yield LicenseEntryWithLineBreaks([
      'Luma UI derived from Noto Sans SC',
    ], await rootBundle.loadString('assets/licenses/OFL-NotoSansSC.txt'));
  });
  if (args.length >= 3 && args[0] == '--self-test') {
    final ok = await runReleaseSelfTest(Directory(args[1]), File(args[2]));
    exit(ok ? 0 : 1);
  }
  runApp(const LumaApp());
}
