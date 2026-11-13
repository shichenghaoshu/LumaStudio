import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:luma_native/luma_native.dart';

import 'recipe.dart';

const rawExtensions = {
  'rw2',
  'raw',
  'cr2',
  'cr3',
  'nef',
  'nrw',
  'arw',
  'srf',
  'sr2',
  'raf',
  'orf',
  'dng',
  'pef',
  'srw',
  '3fr',
  'fff',
  'iiq',
  'kdc',
  'mrw',
  'mos',
  'x3f',
  'rwl',
  'erf',
};
const rasterExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'tif',
  'tiff',
  'bmp',
  'gif',
  'psd',
  'tga',
};

class PhotoWorker {
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  Isolate? _isolate;
  ReceivePort? _receive;
  SendPort? _send;
  int _id = 0;
  Future<void>? _startup;
  Future<void> start() => _startup ??= _open();
  Future<void> _open() async {
    if (_send != null) return;
    final ready = Completer<void>();
    _receive = ReceivePort();
    _receive!.listen((dynamic event) {
      if (event is SendPort) {
        _send = event;
        ready.complete();
        return;
      }
      final r = Map<String, dynamic>.from(event as Map);
      final c = _pending.remove(r['id']);
      if (c == null) return;
      if (r['error'] != null) {
        c.completeError(StateError(r['error'] as String));
      } else {
        c.complete(r);
      }
    });
    _isolate = await Isolate.spawn(_workerMain, _receive!.sendPort);
    await ready.future.timeout(const Duration(seconds: 30));
  }

  Future<Map<String, dynamic>> request(Map<String, Object?> request) async {
    await start();
    final id = ++_id, c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _send!.send({...request, 'id': id});
    return c.future;
  }

  void dispose() {
    _isolate?.kill();
    _receive?.close();
    for (final c in _pending.values) {
      c.completeError(StateError('图像工作进程已关闭'));
    }
    _pending.clear();
  }
}

void _workerMain(SendPort send) async {
  final receive = ReceivePort();
  send.send(receive.sendPort);
  LumaNative? native;
  String? cachedKey;
  img.Image? cached;
  Uint8List? cachedOriginal;
  final luts = <String, ({Float32List values, int size})>{};
  await for (final dynamic request in receive) {
    final m = Map<String, dynamic>.from(request as Map);
    try {
      native ??= LumaNative();
      final clock = Stopwatch()..start();
      final path = m['path'] as String,
          edge = m['edge'] as int? ?? 1280,
          file = File(path);
      final stat = await file.stat();
      if (stat.size > 512 * 1024 * 1024) {
        throw const FormatException('输入文件超过 512 MB 安全上限');
      }
      final key =
          '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}|$edge';
      img.Image source;
      if (edge > 0 && cachedKey == key && cached != null) {
        source = cached;
      } else {
        final ext = path.split('.').last.toLowerCase();
        if (rawExtensions.contains(ext)) {
          final raw = native.decodeRaw(path, edge);
          source = img.Image.fromBytes(
            width: raw.width,
            height: raw.height,
            bytes: raw.pixels.buffer,
            numChannels: 4,
          );
        } else {
          final bytes = await file.readAsBytes();
          final decoder = img.findDecoderForData(bytes),
              info = decoder?.startDecode(bytes);
          if (info == null) {
            throw const FormatException(
              '无法解码照片。支持 JPEG、PNG、WebP、TIFF、BMP、PSD 和所列 RAW；HEIC 请在 Mac 版打开。',
            );
          }
          if (info.width * info.height > 80000000) {
            throw const FormatException('照片超过 80 MP 安全上限');
          }
          final decoded = decoder!.decodeFrame(0);
          if (decoded == null) throw const FormatException('照片数据损坏');
          source = img.bakeOrientation(decoded);
        }
        source = source.convert(numChannels: 4, format: img.Format.uint8);
        if (edge > 0 && source.width > edge ||
            edge > 0 && source.height > edge) {
          source = img.copyResize(
            source,
            width: source.width >= source.height ? edge : null,
            height: source.height > source.width ? edge : null,
            interpolation: img.Interpolation.linear,
          );
        }
        if (edge > 0) {
          cached = source;
          cachedKey = key;
          cachedOriginal = Uint8List.fromList(
            img.encodeJpg(source, quality: 86),
          );
        }
      }
      if (m['command'] == 'thumbnail') {
        final small = img.copyResize(
          source,
          width: source.width >= source.height ? 320 : null,
          height: source.height > source.width ? 320 : null,
        );
        send.send({
          'id': m['id'],
          'bytes': Uint8List.fromList(img.encodeJpg(small, quality: 82)),
          'width': source.width,
          'height': source.height,
        });
        continue;
      }
      final recipe = Recipe.fromJson(
        Map<String, dynamic>.from(m['recipe'] as Map),
      );
      ({Float32List values, int size})? lut;
      if (recipe.filter != null) {
        lut = luts[recipe.filter];
        if (lut == null) {
          final text = m['cube'] as String?;
          if (text == null) throw const FormatException('滤镜资源缺失');
          var size = 0;
          final values = <double>[];
          for (final line in text.split('\n')) {
            final s = line.split('#').first.trim();
            if (s.isEmpty || s.startsWith('TITLE') || s.startsWith('DOMAIN_')) {
              continue;
            }
            final tokens = s.split(RegExp(r'\s+'));
            if (s.startsWith('LUT_3D_SIZE')) {
              size = int.parse(tokens.last);
              continue;
            }
            if (tokens.length != 3) throw const FormatException('滤镜格式无效');
            values.addAll(tokens.map(double.parse));
          }
          if (size < 2 ||
              size > 65 ||
              values.length != size * size * size * 3 ||
              values.any((v) => !v.isFinite || v < 0 || v > 1)) {
            throw const FormatException('滤镜数据无效');
          }
          lut = (values: Float32List.fromList(values), size: size);
          luts[recipe.filter!] = lut;
        }
      }
      final before = clock.elapsedMilliseconds;
      final pixels = native.process(
        source.getBytes(order: img.ChannelOrder.rgba),
        source.width,
        source.height,
        recipe.values,
        recipe.hsl,
        lut?.values,
        lut?.size ?? 0,
      );
      var edited = img.Image.fromBytes(
        width: source.width,
        height: source.height,
        bytes: pixels.buffer,
        numChannels: 4,
      );
      img.Image geometry(img.Image image) {
        if (recipe.turns != 0) {
          image = img.copyRotate(image, angle: recipe.turns * 90);
        }
        if (recipe.flip) image = img.flipHorizontal(image);
        if (recipe.aspect > 0) {
          var w = image.width, h = image.height;
          if (w / h > recipe.aspect) {
            w = (h * recipe.aspect).round().clamp(1, w);
          } else {
            h = (w / recipe.aspect).round().clamp(1, h);
          }
          image = img.copyCrop(
            image,
            x: (image.width - w) ~/ 2,
            y: (image.height - h) ~/ 2,
            width: w,
            height: h,
          );
        }
        return image;
      }

      edited = geometry(edited);
      final renderMS = clock.elapsedMilliseconds - before;
      if (m['command'] == 'export') {
        final long = m['longEdge'] as int? ?? 0;
        if (long > 0 && (edited.width > long || edited.height > long)) {
          edited = img.copyResize(
            edited,
            width: edited.width >= edited.height ? long : null,
            height: edited.height > edited.width ? long : null,
            interpolation: img.Interpolation.cubic,
          );
        }
        // Rebuild from pixels to strip GPS/EXIF and stale color profiles. The
        // portable output contract is sRGB 8-bit; Mac retains 16-bit/ICC options.
        final bytes = m['format'] == 'png'
            ? img.encodePng(edited, level: 3)
            : img.encodeJpg(
                edited,
                quality: (m['quality'] as int? ?? 95).clamp(1, 100),
              );
        final output = File(m['output'] as String);
        if (await output.exists()) throw const FileSystemException('拒绝覆盖已有文件');
        final temp = File('${output.path}.partial');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(output.path);
        send.send({
          'id': m['id'],
          'path': output.path,
          'width': edited.width,
          'height': edited.height,
          'milliseconds': clock.elapsedMilliseconds,
          'renderMS': renderMS,
        });
      } else {
        final bytes = Uint8List.fromList(img.encodeJpg(edited, quality: 86));
        final original = recipe.turns == 0 && !recipe.flip && recipe.aspect == 0
            ? cachedOriginal
            : Uint8List.fromList(
                img.encodeJpg(geometry(img.Image.from(source)), quality: 86),
              );
        final histogram = List.filled(64, 0);
        final step = ((edited.width * edited.height) / 20000).ceil().clamp(
          1,
          10000,
        );
        for (var i = 0; i < edited.width * edited.height; i += step) {
          final p = edited.getPixel(i % edited.width, i ~/ edited.width);
          histogram[((p.r * .2126 + p.g * .7152 + p.b * .0722) / 4)
              .floor()
              .clamp(0, 63)]++;
        }
        send.send({
          'id': m['id'],
          'bytes': bytes,
          'original': original,
          'width': edited.width,
          'height': edited.height,
          'histogram': histogram,
          'milliseconds': clock.elapsedMilliseconds,
          'renderMS': renderMS,
        });
      }
    } catch (e) {
      send.send({'id': m['id'], 'error': '$e'});
    }
  }
}
