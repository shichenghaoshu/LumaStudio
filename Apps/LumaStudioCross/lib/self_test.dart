import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'recipe.dart';
import 'studio.dart';
import 'worker.dart';

/// Runs in the compiled application as well as test runners. Every fixture is
/// generated or explicitly supplied. It never opens the user's normal library.
Future<bool> runReleaseSelfTest(Directory root, File report) async {
  final evidence = <String, Object?>{
    'platform': Platform.operatingSystem,
    'version': '0.5.0',
    'scope': 'compiled native engine and persistent photo workflow; not physical-device aesthetic acceptance',
    'checks': <String>[],
    'measurements': <Object>[],
  };
  final checks = evidence['checks'] as List<String>,
      measurements = evidence['measurements'] as List<Object>;
  final worker = PhotoWorker();
  Studio? studio;
  void check(bool value, String name) {
    if (!value) throw StateError(name);
    checks.add(name);
  }

  try {
    await root.create(recursive: true);
    final fixtures = Directory(p.join(root.path, 'fixtures'));
    await fixtures.create();
    final sources = <String>[];
    for (var photo = 0; photo < 3; photo++) {
      final image = img.Image(width: 960, height: 640, numChannels: 4);
      for (final pixel in image) {
        pixel
          ..r = (pixel.x / 960 * 180 + photo * 22).clamp(0, 255)
          ..g = (pixel.y / 640 * 180 + 20).clamp(0, 255)
          ..b = (pixel.x + pixel.y) % 200
          ..a = 255;
      }
      final ext = ['jpg', 'png', 'tiff'][photo],
          file = File(p.join(fixtures.path, 'photo-$photo.$ext'));
      await file.writeAsBytes(
        photo == 0
            ? img.encodeJpg(image, quality: 95)
            : photo == 1
            ? img.encodePng(image)
            : img.encodeTiff(image),
      );
      sources.add(file.path);
    }
    final hashes = {
      for (final f in sources)
        f: (await sha256.bind(File(f).openRead()).first).toString(),
    };
    var r = Recipe();
    final original = await worker.request({
      'command': 'preview',
      'path': sources.first,
      'edge': 640,
      'recipe': r.toJson(),
    });
    final baseline = img.decodeJpg(original['bytes'])!;
    r = r.set(0, .7).copy(filter: 'warm');
    final cube = await rootBundle.loadString('assets/filters/warm.cube');
    final edited = await worker.request({
      'command': 'preview',
      'path': sources.first,
      'edge': 640,
      'recipe': r.toJson(),
      'cube': cube,
    });
    final changed = img.decodeJpg(edited['bytes'])!;
    check(
      changed.getPixel(320, 200).r > baseline.getPixel(320, 200).r,
      'exposure/LUT change actual decoded pixels',
    );
    for (var i = 0; i < 12; i++) {
      final sample = await worker.request({
        'command': 'preview',
        'path': sources.first,
        'edge': 1280,
        'recipe': r.set(0, i * .03).toJson(),
        'cube': cube,
      });
      measurements.add({
        'preview_ms': sample['milliseconds'],
        'native_render_ms': sample['renderMS'],
      });
    }
    final full = File(p.join(root.path, 'full-resolution.jpg'));
    if (await full.exists()) await full.delete();
    final exported = await worker.request({
      'command': 'export',
      'path': sources.first,
      'edge': 0,
      'recipe': r.toJson(),
      'cube': cube,
      'output': full.path,
      'quality': 95,
    });
    final decoded = img.decodeJpg(await full.readAsBytes())!;
    check(
      decoded.width == 960 && decoded.height == 640 && exported['width'] == 960,
      'full-resolution JPEG is not a preview upscale',
    );
    var refused = false;
    try {
      await worker.request({
        'command': 'export',
        'path': sources.first,
        'edge': 0,
        'recipe': r.toJson(),
        'cube': cube,
        'output': full.path,
      });
    } catch (_) {
      refused = true;
    }
    check(refused, 'existing output overwrite refused');
    final cropped = File(p.join(root.path, 'cropped.png'));
    if (await cropped.exists()) await cropped.delete();
    await worker.request({
      'command': 'export',
      'path': sources[1],
      'edge': 0,
      'recipe': Recipe().copy(turns: 1, aspect: 1).toJson(),
      'output': cropped.path,
      'format': 'png',
    });
    final square = img.decodePng(await cropped.readAsBytes())!;
    check(
      square.width == 640 && square.height == 640,
      'rotated square PNG has expected dimensions',
    );
    for (final path in sources) {
      await worker.request({
        'command': 'preview',
        'path': path,
        'edge': 640,
        'recipe': Recipe().toJson(),
      });
    }
    check(true, 'JPEG PNG TIFF imports decode');
    // Optional independent public RAW fixtures supplied by CI/local validation.
    final rawDir = Directory(p.join(root.path, 'raw'));
    if (await rawDir.exists()) {
      await for (final item in rawDir.list()) {
        if (item is! File) continue;
        final response = await worker.request({
          'command': 'preview',
          'path': item.path,
          'edge': 960,
          'recipe': Recipe().toJson(),
        });
        check(
          (response['width'] as int) > 0,
          'RAW ${p.extension(item.path)} preview',
        );
      }
    }
    studio = Studio();
    await studio.initialize(root: Directory(p.join(root.path, 'test-library')));
    final added = await studio.importPaths(sources);
    check(added == 3, 'three independent photos imported');
    check(
      await studio.importPaths(sources) == 0,
      'SHA256 duplicate imports suppressed',
    );
    studio.select(studio.photos.first);
    studio.change(Recipe().set(0, .5));
    studio.undo();
    check(studio.recipe.values[0] == 0, 'undo restores recipe');
    studio.redo();
    check(studio.recipe.values[0] == .5, 'redo restores edit');
    await studio.flush();
    studio.selected.addAll(studio.photos.map((e) => e.id));
    studio.batchMode = 'saved';
    final files = await studio.batchExport(
      Directory(p.join(root.path, 'saved-batch')),
    );
    check(files.length == 3, 'saved recipe batch exports 3 of 3');
    studio.batchMode = 'auto';
    final auto = await studio.batchExport(
      Directory(p.join(root.path, 'automatic-batch')),
    );
    check(auto.length == 3, 'per-photo automatic batch exports 3 of 3');
    for (final entry in hashes.entries) {
      check(
        (await sha256.bind(File(entry.key).openRead()).first).toString() ==
            entry.value,
        'input unchanged ${p.basename(entry.key)}',
      );
    }
    final reopened = Studio();
    try {
      await reopened.initialize(root: studio.directory);
      check(
        reopened.photos.length == 3 &&
            reopened.photos.first.recipe.values[0] == .5,
        'library restart preserves photo recipes',
      );
    } finally {
      await reopened.flush();
      reopened.dispose();
    }
    evidence['success'] = true;
  } catch (e, stack) {
    evidence['success'] = false;
    evidence['error'] = '$e';
    evidence['stack'] = '$stack';
  } finally {
    await studio?.flush();
    studio?.dispose();
    worker.dispose();
    await report.parent.create(recursive: true);
    await report.writeAsString(
      const JsonEncoder.withIndent('  ').convert(evidence),
      flush: true,
    );
  }
  return evidence['success'] == true;
}
