import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:lumastudio/worker.dart';
import 'package:lumastudio/recipe.dart';

void main() {
  final directory = Platform.environment['LUMA_RAW_DIRECTORY'];
  test(
    'independent RAW fixtures decode and export through native core',
    () async {
      final root = await Directory.systemTemp.createTemp('luma-raw-'),
          worker = PhotoWorker(),
          rows = <Object>[];
      try {
        final manifest = jsonDecode(
          await File(p.join(directory!, 'manifest.json')).readAsString(),
        ) as List;
        for (final item in manifest) {
          final path = p.join(directory, item['filename']),
              r = Recipe().set(0, .15);
          final frame = await worker.request({
            'command': 'preview',
            'path': path,
            'edge': 960,
            'recipe': r.toJson(),
          });
          final exported = await worker.request({
            'command': 'export',
            'path': path,
            'edge': 0,
            'recipe': r.toJson(),
            'output': p.join(root.path, '${item['id']}.jpg'),
            'longEdge': 1600,
            'quality': 90,
          });
          expect(exported['width'], greaterThan(0));
          expect(await File(exported['path']).length(), greaterThan(1000));
          rows.add({
            'input': item['filename'],
            'previewMS': frame['milliseconds'],
            'exportMS': exported['milliseconds'],
            'width': exported['width'],
            'height': exported['height'],
            'success': true,
          });
        }
        final report = File(
          '../../Artifacts/Performance/portable-raw-formats.json',
        );
        await report.parent.create(recursive: true);
        await report.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'scope': 'eight independent licensed RAWs; resized exports from full-resolution processing',
            'rows': rows,
          }),
        );
      } finally {
        worker.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: directory == null
        ? 'Set LUMA_RAW_DIRECTORY to licensed RAW fixtures'
        : false,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
