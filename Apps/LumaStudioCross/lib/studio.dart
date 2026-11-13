import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'recipe.dart';
import 'worker.dart';

class Photo {
  Photo({
    required this.id,
    required this.name,
    required this.path,
    required this.thumbnail,
    Recipe? recipe,
    this.stars = 0,
  }) : recipe = recipe ?? Recipe();
  final String id, name, path, thumbnail;
  Recipe recipe;
  int stars;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'thumbnail': thumbnail,
    'recipe': recipe.toJson(),
    'stars': stars,
  };
  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
    id: j['id'],
    name: j['name'],
    path: j['path'],
    thumbnail: j['thumbnail'],
    recipe: Recipe.fromJson(Map<String, dynamic>.from(j['recipe'])),
    stars: j['stars'] ?? 0,
  );
}

class Frame {
  Frame(Map<String, dynamic> m)
    : bytes = m['bytes'],
      original = m['original'],
      width = m['width'],
      height = m['height'],
      milliseconds = m['milliseconds'],
      renderMS = m['renderMS'],
      histogram = List<int>.from(m['histogram']);
  final Uint8List bytes;
  final Uint8List? original;
  final int width, height, milliseconds, renderMS;
  final List<int> histogram;
}

class Studio extends ChangeNotifier {
  void refresh() {
    if (!disposed) notifyListeners();
  }

  final photos = <Photo>[],
      selected = <String>{},
      undoStack = <Recipe>[],
      redoStack = <Recipe>[];
  final preview = ValueNotifier<Frame?>(null), rendering = ValueNotifier(false);
  final _worker = PhotoWorker(), _exportWorker = PhotoWorker();
  final events = <String>[];
  final _cubes = <String, String>{};
  Directory? directory;
  Photo? current;
  Recipe recipe = Recipe();
  Recipe? _gesture;
  bool busy = false,
      batchBusy = false,
      cancelBatch = false,
      agentBusy = false,
      disposed = false;
  String status = '正在打开本地图库…',
      batchStatus = '',
      error = '',
      apiKey = '',
      endpoint = 'https://api.deepseek.com/chat/completions',
      model = 'deepseek-chat';
  String exportFormat = 'jpeg', batchMode = 'uniform';
  int quality = 95, longEdge = 0;
  int _generation = 0;
  bool _running = false;
  Timer? _timer;
  Future<void> _writes = Future.value();
  Future<void> initialize({Directory? root}) async {
    try {
      directory =
          root ??
          Directory(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'LumaStudioPortable',
            ),
          );
      await Directory(p.join(directory!.path, 'Originals'))
          .create(recursive: true);
      await Directory(p.join(directory!.path, 'Thumbnails')).create();
      await Directory(p.join(directory!.path, 'Exports')).create();
      final index = File(p.join(directory!.path, 'library.json')),
          backup = File('${p.join(directory!.path, 'library.json')}.bak');
      if (await index.exists() || await backup.exists()) {
        Map<String, dynamic>? data;
        for (final f in [index, backup]) {
          try {
            if (await f.exists()) data = jsonDecode(await f.readAsString());
          } catch (_) {
            continue;
          }
          if (data != null) break;
        }
        if (data == null) {
          throw const FormatException('图库索引无法读取；照片仍保存在 Originals 目录。');
        }
        for (final j in data['photos'] as List) {
          photos.add(Photo.fromJson(Map<String, dynamic>.from(j)));
        }
      }
      status = photos.isEmpty
          ? '导入照片，开始本地精修'
          : '${photos.length} 张照片 · 全部保存在本机';
      if (photos.isNotEmpty) select(photos.first);
    } catch (e) {
      error = '$e';
      status = '图库打开失败';
    }
    if (!disposed) notifyListeners();
  }

  void select(Photo photo) {
    if (busy || batchBusy || agentBusy) return;
    current = photo;
    recipe = photo.recipe;
    undoStack.clear();
    redoStack.clear();
    _gesture = null;
    preview.value = null;
    notifyListeners();
    schedule();
  }

  void beginGesture() {
    _gesture ??= recipe;
  }

  void endGesture() {
    final old = _gesture;
    _gesture = null;
    if (old != null && old != recipe) {
      undoStack.add(old);
      if (undoStack.length > 100) undoStack.removeAt(0);
      redoStack.clear();
    }
    save();
    notifyListeners();
    schedule();
  }

  void change(Recipe value, {bool gesture = false}) {
    if (current == null || batchBusy || busy || agentBusy) return;
    if (value == recipe) return;
    if (!gesture && _gesture == null) {
      undoStack.add(recipe);
      if (undoStack.length > 100) undoStack.removeAt(0);
      redoStack.clear();
    }
    recipe = value;
    current!.recipe = value;
    notifyListeners();
    schedule();
    if (!gesture && _gesture == null) save();
  }

  void undo() {
    if (undoStack.isEmpty || agentBusy || batchBusy) return;
    redoStack.add(recipe);
    recipe = undoStack.removeLast();
    current?.recipe = recipe;
    save();
    notifyListeners();
    schedule();
  }

  void redo() {
    if (redoStack.isEmpty || agentBusy || batchBusy) return;
    undoStack.add(recipe);
    recipe = redoStack.removeLast();
    current?.recipe = recipe;
    save();
    notifyListeners();
    schedule();
  }

  void toggle(String id) {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
    notifyListeners();
  }

  Future<String?> cube(Recipe r) async {
    if (r.filter == null) return null;
    return _cubes[r.filter!] ??= await rootBundle.loadString(
      'assets/filters/${r.filter}.cube',
    );
  }

  void schedule() {
    _generation++;
    _timer?.cancel();
    rendering.value = true;
    _timer = Timer(const Duration(milliseconds: 45), _renderLatest);
  }

  Future<void> _renderLatest() async {
    if (_running || current == null || disposed) return;
    _running = true;
    try {
      // One request in flight and one replaceable latest state: rapid sliders
      // cannot build an unbounded queue of obsolete decodes/renders.
      while (!disposed) {
        final generation = _generation, photo = current!, r = recipe;
        try {
          final frame = await _worker.request({
            'command': 'preview',
            'path': photo.path,
            'edge': Platform.isAndroid ? 960 : 1280,
            'recipe': r.toJson(),
            'cube': await cube(r),
          });
          if (disposed) return;
          if (generation == _generation) {
            preview.value = Frame(frame);
            error = '';
            status =
                '${frame['width']} × ${frame['height']} · ${frame['milliseconds']} ms · 本地处理';
            break;
          }
        } catch (e) {
          if (generation == _generation) {
            error = '$e';
            status = '预览失败';
            break;
          }
        }
      }
    } finally {
      _running = false;
      if (!disposed) {
        rendering.value = false;
        notifyListeners();
      }
    }
  }

  void save() {
    if (directory == null || disposed) return;
    final data = jsonEncode({
      'version': 1,
      'photos': photos.map((e) => e.toJson()).toList(),
    });
    _writes = _writes
        .then((_) async {
          final index = File(p.join(directory!.path, 'library.json')),
              temp = File(p.join(directory!.path, 'library.new')),
              backup = File('${p.join(directory!.path, 'library.json')}.bak');
          await temp.writeAsString(data, flush: true);
          if (await backup.exists()) await backup.delete();
          if (await index.exists()) await index.rename(backup.path);
          try {
            await temp.rename(index.path);
          } catch (_) {
            if (await backup.exists() && !await index.exists()) {
              await backup.rename(index.path);
            }
            rethrow;
          }
        })
        .catchError((Object e) {
          if (!disposed) {
            error = '保存配方失败：$e';
            notifyListeners();
          }
        });
  }

  Future<void> flush() => _writes;
  Future<int> importPaths(List<String> paths) async {
    if (busy || batchBusy || directory == null) return 0;
    busy = true;
    error = '';
    notifyListeners();
    var added = 0;
    final failures = <String>[];
    try {
      for (final path in paths) {
        final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
        if (!rawExtensions.contains(ext) && !rasterExtensions.contains(ext)) {
          failures.add('${p.basename(path)}：格式暂不支持');
          continue;
        }
        try {
          final file = File(path);
          if (await file.length() > 512 * 1024 * 1024) {
            throw const FormatException('文件超过 512 MB');
          }
          status = '正在导入 ${added + 1}/${paths.length} · ${p.basename(path)}';
          notifyListeners();
          final id = await Isolate.run(
            () async =>
                (await sha256.bind(File(path).openRead()).first).toString(),
          );
          if (photos.any((e) => e.id == id)) continue;
          final target = File(p.join(directory!.path, 'Originals', '$id.$ext')),
              thumb = File(p.join(directory!.path, 'Thumbnails', '$id.jpg'));
          if (!await target.exists()) {
            final stage = await file.copy('${target.path}.partial');
            await stage.rename(target.path);
          }
          final result = await _worker.request({
            'command': 'thumbnail',
            'path': target.path,
            'edge': 960,
          });
          await thumb.writeAsBytes(result['bytes'], flush: true);
          final photo = Photo(
            id: id,
            name: p.basename(path),
            path: target.path,
            thumbnail: thumb.path,
          );
          photos.add(photo);
          added++;
          save();
        } catch (e) {
          failures.add('${p.basename(path)}：$e');
        }
      }
    } finally {
      busy = false;
      status = '已导入 $added 张 · 图库 ${photos.length} 张';
      if (failures.isNotEmpty) error = failures.join('\n');
      notifyListeners();
      if (added > 0) select(photos.last);
      await flush();
    }
    return added;
  }

  Future<File> exportPhoto(
    Photo photo,
    Recipe r,
    Directory output, {
    String? name,
  }) async {
    await output.create(recursive: true);
    final ext = exportFormat == 'png' ? 'png' : 'jpg',
        safe = p
            .basenameWithoutExtension(name ?? photo.name)
            .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    var target = File(
      p.join(
        output.path,
        '${safe}_Luma_${DateTime.now().microsecondsSinceEpoch}.$ext',
      ),
    );
    if (await target.exists()) throw const FileSystemException('输出文件已存在');
    await _exportWorker.request({
      'command': 'export',
      'path': photo.path,
      'edge': 0,
      'recipe': r.toJson(),
      'cube': await cube(r),
      'output': target.path,
      'format': exportFormat,
      'quality': quality,
      'longEdge': longEdge,
    });
    return target;
  }

  Future<Recipe> automatic(Photo photo) async {
    final r = photo.recipe;
    final result = await _exportWorker.request({
      'command': 'preview',
      'path': photo.path,
      'edge': 640,
      'recipe': Recipe().toJson(),
    });
    final bins = List<int>.from(result['histogram']);
    final sum = bins.fold<int>(0, (a, b) => a + b);
    final mean = sum == 0
        ? 0.5
        : bins.indexed.fold<double>(0, (a, e) => a + e.$1 * e.$2) / (sum * 63);
    final ev = (math.log(0.46 / math.max(0.05, mean)) / math.ln2).clamp(
      -0.7,
      0.7,
    );
    return r
        .set(0, ev)
        .set(3, mean > 0.55 ? -0.2 : 0)
        .set(4, mean < 0.35 ? 0.2 : 0);
  }

  Future<List<File>> batchExport(Directory output) async {
    if (batchBusy || busy || agentBusy) throw StateError('另一个任务正在运行');
    final chosen = photos.where((e) => selected.contains(e.id)).toList();
    if (chosen.isEmpty) throw StateError('请先勾选要导出的照片');
    batchBusy = true;
    cancelBatch = false;
    notifyListeners();
    final outputs = <File>[], failures = <String>[];
    final snapshot = recipe;
    try {
      for (final photo in chosen) {
        if (cancelBatch) break;
        batchStatus =
            '正在处理 ${outputs.length + failures.length + 1}/${chosen.length} · ${photo.name}';
        notifyListeners();
        try {
          final r = batchMode == 'saved'
              ? photo.recipe
              : batchMode == 'auto'
              ? await automatic(photo)
              : snapshot;
          outputs.add(await exportPhoto(photo, r, output));
        } catch (e) {
          failures.add('${photo.name}：$e');
        }
      }
      final report = {
        'requested': chosen.length,
        'completed': outputs.length,
        'cancelled': cancelBatch,
        'failures': failures,
        'mode': batchMode,
        'files': outputs.map((e) => p.basename(e.path)).toList(),
      };
      await File(
        p.join(
          output.path,
          'batch-${DateTime.now().microsecondsSinceEpoch}.json',
        ),
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      batchStatus =
          '成功 ${outputs.length}/${chosen.length} · 失败 ${failures.length}${cancelBatch ? ' · 已停止' : ''}';
      if (failures.isNotEmpty) error = failures.join('\n');
      return outputs;
    } finally {
      batchBusy = false;
      notifyListeners();
    }
  }

  Future<void> runAgent(String instruction) async {
    if (current == null || agentBusy || busy || batchBusy) return;
    if (apiKey.trim().isEmpty) {
      throw StateError('请先在接入设置中填写 API 密钥。密钥只保存在本次会话内。');
    }
    final uri = Uri.parse(endpoint);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const FormatException('API 地址必须为不含凭据、查询参数的 HTTPS 地址');
    }
    agentBusy = true;
    events.clear();
    events.add('读取当前配方 · 照片保留在本机');
    notifyListeners();
    final old = recipe, photo = current!;
    final client = http.Client();
    try {
      events.add('请求在线模型 · $model');
      notifyListeners();
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${apiKey.trim()}',
        })
        ..body = jsonEncode({
          'model': model,
          'temperature': 0.15,
          'max_tokens': 1024,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content':
                  'You edit supported numerical controls only. Return JSON {"changes": {controlID:number}, "filter": optional registered filterID, "explanation": string}. Include only controls requested. No commands, paths, tool calls. Controls: ${controls.map((c) => '${c.id} [${c.min},${c.max}] default ${c.initial}').join('; ')}. Filters: ${filterTitles.keys.join(',')}. Never change skinSmooth or skinBright unless explicitly requested. Current recipe: ${old.encode()}',
            },
            {'role': 'user', 'content': instruction},
          ],
        });
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 40));
      if (response.statusCode != 200) {
        throw StateError('在线服务返回 HTTP ${response.statusCode}；当前配方保留');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 128 * 1024) throw const FormatException('模型响应过大');
      }
      final outer = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
          content = outer['choices'][0]['message']['content'] as String;
      final proposal = jsonDecode(content) as Map<String, dynamic>;
      var next = old;
      final changes = Map<String, dynamic>.from(
        proposal['changes'] as Map? ?? {},
      );
      final forbidSkin = RegExp(
        r'不要.*(美颜|磨皮|肤色)|不.*美颜|no\s+(beauty|retouch|skin)',
        caseSensitive: false,
      ).hasMatch(instruction);
      for (final entry in changes.entries) {
        final i = controls.indexWhere((c) => c.id == entry.key);
        if (i < 0) throw FormatException('模型返回不支持的参数：${entry.key}');
        final v = (entry.value as num).toDouble();
        if (!v.isFinite || v < controls[i].min || v > controls[i].max) {
          throw FormatException('模型参数超出范围：${entry.key}');
        }
        if (i >= 16 &&
            (forbidSkin ||
                !RegExp(
                  r'美颜|磨皮|肤色|skin|beauty',
                  caseSensitive: false,
                ).hasMatch(instruction))) {
          continue;
        }
        next = next.set(i, v);
      }
      final f = proposal['filter'];
      if (f != null) {
        if (!filterTitles.containsKey(f)) {
          throw const FormatException('模型返回未知滤镜');
        }
        next = next.copy(filter: f);
      }
      events.add('参数范围检查通过 · ${changes.length} 项建议');
      notifyListeners();
      // Render first, then commit. Network/decoding/render failures preserve history.
      final result = await _worker.request({
        'command': 'preview',
        'path': photo.path,
        'edge': Platform.isAndroid ? 960 : 1280,
        'recipe': next.toJson(),
        'cube': await cube(next),
      });
      if (disposed || current != photo) return;
      undoStack.add(old);
      redoStack.clear();
      recipe = next;
      photo.recipe = next;
      preview.value = Frame(result);
      save();
      events.add('本地渲染完成 · ${result['milliseconds']} ms');
      events.add('已应用，可撤销 · ${proposal['explanation'] ?? '参数已更新'}');
    } catch (e) {
      events.add('执行失败，当前编辑保留');
      rethrow;
    } finally {
      client.close();
      agentBusy = false;
      if (!disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    _timer?.cancel();
    _worker.dispose();
    _exportWorker.dispose();
    preview.dispose();
    rendering.dispose();
    super.dispose();
  }
}
