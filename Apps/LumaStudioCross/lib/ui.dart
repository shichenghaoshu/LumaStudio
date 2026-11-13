import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:archive/archive_io.dart';

import 'studio.dart';
import 'recipe.dart';
import 'worker.dart';

const accent = Color(0xffe7c671),
    surface = Color(0xff191a1c),
    background = Color(0xff101113);

class LumaApp extends StatelessWidget {
  const LumaApp({super.key, this.studio});
  final Studio? studio;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LumaStudio',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: background,
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: "LumaUI"),
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ).copyWith(primary: accent, surface: surface),
      sliderTheme: const SliderThemeData(
        trackHeight: 2,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        scrolledUnderElevation: 0,
      ),
    ),
    home: StudioPage(studio: studio),
  );
}

class StudioPage extends StatefulWidget {
  const StudioPage({super.key, this.studio});
  final Studio? studio;
  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  late final Studio s = widget.studio ?? Studio();
  String section = '影调';
  bool comparing = false, exporting = false;
  final instruction = TextEditingController();
  @override
  void initState() {
    super.initState();
    if (widget.studio == null) s.initialize();
  }

  @override
  void dispose() {
    instruction.dispose();
    if (widget.studio == null) s.dispose();
    super.dispose();
  }

  Future<void> attempt(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 7)),
        );
      }
    }
  }

  bool get locked => s.busy || s.batchBusy || s.agentBusy || exporting;
  Future<void> import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [...rasterExtensions, ...rawExtensions],
    );
    if (result.isNotEmpty) {
      await s.importPaths(
        result.map((f) => f.path).whereType<String>().toList(),
      );
    }
  }

  Future<void> demo() async {
    final bytes = await rootBundle.load('assets/demo.jpg');
    final f = File(p.join(s.directory!.path, 'demo.jpg'));
    await f.writeAsBytes(bytes.buffer.asUint8List());
    await s.importPaths([f.path]);
  }

  Future<void> exportOne() async {
    final photo = s.current;
    if (photo == null) return;
    setState(() => exporting = true);
    try {
      final file = await s.exportPhoto(
        photo,
        s.recipe,
        Directory(p.join(s.directory!.path, 'Exports')),
      );
      String? location;
      if (Platform.isAndroid) {
        final uri = await FilePicker.saveFile(
          dialogTitle: '导出精修照片',
          fileName: p.basename(file.path),
          bytes: await file.readAsBytes(),
          mimeType: s.exportFormat == 'png' ? 'image/png' : 'image/jpeg',
        );
        if (uri == null) return;
        location = uri.toString();
      } else {
        final selected = await getSaveLocation(
          suggestedName: p.basename(file.path),
        );
        if (selected == null) return;
        location = selected.path;
        final dest = File(location);
        if (await dest.exists()) {
          throw const FileSystemException('为保护已有文件，请使用新的文件名');
        }
        await file.copy(dest.path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Platform.isAndroid ? '照片已交给系统保存' : '已导出到 $location'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) => LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                _UndoIntent(),
            SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ): _RedoIntent(),
          },
          child: Actions(
            actions: {
              _UndoIntent: CallbackAction<_UndoIntent>(
                onInvoke: (_) {
                  s.undo();
                  return null;
                },
              ),
              _RedoIntent: CallbackAction<_RedoIntent>(
                onInvoke: (_) {
                  s.redo();
                  return null;
                },
              ),
            },
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: wide ? 24 : 12,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (wide) const Icon(Icons.camera, size: 23, color: accent),
                    if (wide) const SizedBox(width: 8),
                    Text(
                      wide ? 'LumaStudio' : 'LUMA',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: wide ? 19 : 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: wide ? -.4 : .2,
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: '导入照片',
                    onPressed: locked ? null : () => attempt(import),
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 21,
                    ),
                  ),
                  IconButton(
                    tooltip: '批量处理',
                    onPressed: locked ? null : batchDialog,
                    icon: const Icon(Icons.grid_view_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: 'AI 助手',
                    onPressed: s.current == null ? null : agentDialog,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: '接入与导出设置',
                    onPressed: locked ? null : settingsDialog,
                    icon: const Icon(Icons.tune, size: 20),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 10, left: 2),
                    child: FilledButton(
                      onPressed: locked || s.current == null
                          ? null
                          : () => attempt(exportOne),
                      child: exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(wide ? '导出照片' : '导出'),
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (s.error.isNotEmpty)
                    Material(
                      color: const Color(0xff4a2924),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 5, 4, 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.error,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            IconButton(
                              tooltip: '关闭提示',
                              onPressed: () {
                                s.error = '';
                                s.refresh();
                              },
                              icon: const Icon(Icons.close, size: 17),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (s.busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: wide
                        ? Row(
                            children: [
                              SizedBox(
                                width: 185,
                                child: photoLibrary(vertical: true),
                              ),
                              const VerticalDivider(
                                width: 1,
                                color: Colors.white10,
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    tools(),
                                    Expanded(child: stage()),
                                    status(),
                                  ],
                                ),
                              ),
                              const VerticalDivider(
                                width: 1,
                                color: Colors.white10,
                              ),
                              SizedBox(width: 330, child: inspector()),
                            ],
                          )
                        : Column(
                            children: [
                              tools(),
                              Expanded(flex: 5, child: stage()),
                              status(),
                              SizedBox(
                                height: 96,
                                child: photoLibrary(vertical: false),
                              ),
                              Expanded(flex: 4, child: inspector()),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  Widget tools() => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.white10)),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: '撤销编辑',
          onPressed: locked || s.undoStack.isEmpty ? null : s.undo,
          icon: const Icon(Icons.undo, size: 19),
        ),
        IconButton(
          tooltip: '重做编辑',
          onPressed: locked || s.redoStack.isEmpty ? null : s.redo,
          icon: const Icon(Icons.redo, size: 19),
        ),
        IconButton(
          tooltip: '旋转 90 度',
          onPressed: locked || s.current == null
              ? null
              : () => s.change(s.recipe.copy(turns: (s.recipe.turns + 1) % 4)),
          icon: const Icon(Icons.rotate_90_degrees_cw, size: 19),
        ),
        IconButton(
          tooltip: '重置全部参数',
          onPressed: locked || s.current == null
              ? null
              : () => s.change(Recipe()),
          icon: const Icon(Icons.restart_alt, size: 19),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: s.current == null
              ? null
              : () => setState(() => comparing = !comparing),
          icon: Icon(
            comparing ? Icons.photo_outlined : Icons.compare,
            size: 18,
          ),
          label: Text(
            comparing ? '返回效果' : '查看原图',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
  Widget stage() => ColoredBox(
    color: const Color(0xff090a0b),
    child: Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<Frame?>(
          valueListenable: s.preview,
          builder: (context, frame, _) {
            if (frame == null) {
              return Center(
                child: s.current != null
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_outlined,
                              size: 43,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 15),
                            const Text(
                              '让每张照片，更接近你的想象',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'JPEG · PNG · TIFF · WebP · 多品牌 RAW',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: locked ? null : () => attempt(import),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('导入照片'),
                            ),
                            TextButton(
                              onPressed: s.directory == null || locked
                                  ? null
                                  : () => attempt(demo),
                              child: const Text(
                                '用示例照片体验',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
              );
            }
            return RepaintBoundary(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.memory(
                    comparing ? (frame.original ?? frame.bytes) : frame.bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          left: 16,
          top: 14,
          child: Text(
            comparing ? '原图对照' : '编辑预览',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ),
        Positioned(
          right: 14,
          top: 14,
          child: ValueListenableBuilder<bool>(
            valueListenable: s.rendering,
            builder: (_, running, _) => running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  );
  Widget status() => Container(
    height: 29,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            s.current?.name ?? s.status,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
        ValueListenableBuilder<Frame?>(
          valueListenable: s.preview,
          builder: (_, frame, _) => Text(
            frame == null
                ? ''
                : '${frame.width} × ${frame.height} · ${frame.milliseconds} ms',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      ],
    ),
  );
  Widget photoLibrary({required bool vertical}) {
    Widget item(Photo photo) => RepaintBoundary(
      child: Container(
        width: vertical ? null : 108,
        margin: EdgeInsets.all(vertical ? 9 : 5),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: s.current?.id == photo.id ? accent : Colors.white10,
          ),
        ),
        child: InkWell(
          onTap: locked ? null : () => s.select(photo),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: vertical ? 102 : 53,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(photo.thumbnail),
                      fit: BoxFit.contain,
                      cacheWidth: 320,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: Checkbox(
                          value: s.selected.contains(photo.id),
                          onChanged: locked ? null : (_) => s.toggle(photo.id),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  photo.name,
                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (s.photos.isEmpty) return const SizedBox.shrink();
    if (!vertical) {
      return ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: s.photos.length,
        itemBuilder: (_, i) => item(s.photos[i]),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 5),
          child: Row(
            children: [
              Text(
                '照片库  ${s.photos.length}',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
              const Spacer(),
              IconButton(
                tooltip: '全选批量目标',
                onPressed: locked
                    ? null
                    : () {
                        s.selected.length == s.photos.length
                            ? s.selected.clear()
                            : s.selected.addAll(s.photos.map((e) => e.id));
                        s.refresh();
                      },
                icon: const Icon(Icons.select_all, size: 17),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: s.photos.length,
            itemBuilder: (_, i) => item(s.photos[i]),
          ),
        ),
      ],
    );
  }

  Widget inspector() => Column(
    children: [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          children: [
            for (final name in ['影调', '色彩', 'HSL', '滤镜', '细节', '肤色', '裁切'])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                child: ChoiceChip(
                  label: Text(name, style: const TextStyle(fontSize: 11)),
                  selected: section == name,
                  onSelected: (_) => setState(() => section = name),
                  showCheckmark: false,
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: IgnorePointer(
          ignoring: locked || s.current == null,
          child: Opacity(
            opacity: s.current == null ? .4 : 1,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(17, 8, 17, 24),
              children: [
                if (section == '影调')
                  ValueListenableBuilder<Frame?>(
                    valueListenable: s.preview,
                    builder: (_, frame, _) => SizedBox(
                      height: 64,
                      child: CustomPaint(
                        painter: _Histogram(frame?.histogram ?? []),
                      ),
                    ),
                  ),
                if (section == '肤色')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text(
                      '基于颜色范围的柔化与提亮，可能影响相近颜色。此版本不含人脸专用分割、瘦脸或祛痘模型。',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                        height: 1.6,
                      ),
                    ),
                  ),
                if (section == '肤色')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final style in beautyStyles)
                          OutlinedButton(
                            onPressed: () =>
                                s.change(beautyStyle(s.recipe, style)),
                            child: Text(style),
                          ),
                      ],
                    ),
                  ),
                for (final e in controls.indexed.where(
                  (e) => e.$2.section == section,
                ))
                  control(e.$1, e.$2),
                if (section == 'HSL') ...hslControls(),
                if (section == '滤镜') ...[
                  TextButton(
                    onPressed: () => s.change(s.recipe.copy(clearFilter: true)),
                    child: const Text('移除滤镜'),
                  ),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    childAspectRatio: 1.8,
                    crossAxisSpacing: 7,
                    mainAxisSpacing: 7,
                    children: [
                      for (final f in filterTitles.entries)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(4),
                            foregroundColor: s.recipe.filter == f.key
                                ? Colors.black
                                : Colors.white70,
                            backgroundColor: s.recipe.filter == f.key
                                ? accent
                                : Colors.transparent,
                            side: BorderSide(
                              color: s.recipe.filter == f.key
                                  ? accent
                                  : Colors.white12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          onPressed: () =>
                              s.change(s.recipe.copy(filter: f.key)),
                          child: Text(
                            f.value,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ],
                if (section == '裁切') ...[
                  const Text('中心裁切比例', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in {
                        '原始': 0.0,
                        '1:1': 1.0,
                        '4:3': 4 / 3,
                        '3:2': 1.5,
                        '16:9': 16 / 9,
                        '4:5': .8,
                        '2:3': 2 / 3,
                      }.entries)
                        ChoiceChip(
                          label: Text(e.key),
                          selected: s.recipe.aspect == e.value,
                          onSelected: (_) =>
                              s.change(s.recipe.copy(aspect: e.value)),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('水平翻转', style: TextStyle(fontSize: 12)),
                    value: s.recipe.flip,
                    onChanged: (v) => s.change(s.recipe.copy(flip: v)),
                  ),
                  TextButton.icon(
                    onPressed: () => s.change(
                      s.recipe.copy(turns: (s.recipe.turns + 1) % 4),
                    ),
                    icon: const Icon(Icons.rotate_90_degrees_cw),
                    label: const Text('顺时针旋转 90°'),
                  ),
                  const Text(
                    '原图保留。导出时重新处理完整像素。',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
  Widget control(int i, Control c) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Column(
      children: [
        Row(
          children: [
            Text(
              c.title,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const Spacer(),
            Text(
              '${s.recipe.values[i].toStringAsFixed(c.unit == 'K' ? 0 : 2)} ${c.unit}',
              style: const TextStyle(fontSize: 11, color: accent),
            ),
            SizedBox(
              width: 30,
              height: 25,
              child: IconButton(
                padding: EdgeInsets.zero,
                tooltip: '重置${c.title}',
                onPressed: () => s.change(s.recipe.set(i, c.initial)),
                icon: const Icon(
                  Icons.refresh,
                  size: 13,
                  color: Colors.white38,
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 27,
          child: Slider(
            value: s.recipe.values[i],
            min: c.min,
            max: c.max,
            onChangeStart: (_) => s.beginGesture(),
            onChanged: (v) => s.change(s.recipe.set(i, v), gesture: true),
            onChangeEnd: (_) => s.endGesture(),
          ),
        ),
      ],
    ),
  );
  List<Widget> hslControls() => [
    for (var band = 0; band < 8; band++)
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(
          '${bandTitles[band]}色',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          for (var axis = 0; axis < 3; axis++)
            Column(
              children: [
                Row(
                  children: [
                    Text(
                      ['色相', '饱和度', '明度'][axis],
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      s.recipe.hsl[band * 3 + axis].toStringAsFixed(2),
                      style: const TextStyle(fontSize: 11, color: accent),
                    ),
                  ],
                ),
                Slider(
                  value: s.recipe.hsl[band * 3 + axis],
                  min: axis == 0 ? -.5 : -1,
                  max: axis == 0 ? .5 : 1,
                  onChangeStart: (_) => s.beginGesture(),
                  onChanged: (v) => s.change(
                    s.recipe.setHSL(band * 3 + axis, v),
                    gesture: true,
                  ),
                  onChangeEnd: (_) => s.endGesture(),
                ),
              ],
            ),
        ],
      ),
  ];
  void settingsDialog() {
    final endpoint = TextEditingController(text: s.endpoint),
        model = TextEditingController(text: s.model),
        key = TextEditingController(text: s.apiKey);
    showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('接入与导出设置'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('在线模型', style: TextStyle(color: accent)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: endpoint,
                    decoration: const InputDecoration(
                      labelText: 'Chat Completions HTTPS 地址',
                    ),
                  ),
                  TextField(
                    controller: model,
                    decoration: const InputDecoration(labelText: '模型名称'),
                  ),
                  TextField(
                    controller: key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'API 密钥 · 仅本次会话',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '只向你指定的服务发送指令与参数，不上传照片。密钥不保存到磁盘，关闭应用后清除。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                      height: 1.5,
                    ),
                  ),
                  const Divider(height: 30),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: s.exportFormat,
                    decoration: const InputDecoration(labelText: '导出格式'),
                    items: const [
                      DropdownMenuItem(
                        value: 'jpeg',
                        child: Text('JPEG · 8 位 sRGB'),
                      ),
                      DropdownMenuItem(
                        value: 'png',
                        child: Text('PNG · 8 位 sRGB'),
                      ),
                    ],
                    onChanged: (v) => refresh(() => s.exportFormat = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: s.longEdge,
                    decoration: const InputDecoration(labelText: '导出长边'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('原始尺寸')),
                      DropdownMenuItem(value: 2048, child: Text('2048 px')),
                      DropdownMenuItem(value: 4096, child: Text('4096 px')),
                    ],
                    onChanged: (v) => refresh(() => s.longEdge = v!),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'JPEG 质量 ${s.quality}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Slider(
                    value: s.quality.toDouble(),
                    min: 70,
                    max: 100,
                    divisions: 30,
                    onChanged: (v) => refresh(() => s.quality = v.round()),
                  ),
                  const Text(
                    '导出移除 EXIF 与 GPS 信息。Windows / Android 不含 Mac 的 16 位输出、局部蒙版、联机拍摄和本地大模型。HEIC 请使用 Mac 版。',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                      height: 1.5,
                    ),
                  ),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'LumaStudio',
                      applicationVersion: '0.5.0',
                      applicationLegalese: 'LibRaw 0.22.3 · CDDL-1.0\n30 original LumaStudio LUTs',
                    ),
                    child: const Text('开源许可'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                s.endpoint = endpoint.text.trim();
                s.model = model.text.trim();
                s.apiKey = key.text.trim();
                Navigator.pop(dialog);
              },
              child: const Text('应用设置'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      endpoint.dispose();
      model.dispose();
      key.dispose();
    });
  }

  void agentDialog() => showDialog<void>(
    context: context,
    builder: (dialog) => ListenableBuilder(
      listenable: s,
      builder: (context, _) => AlertDialog(
        title: const Text('AI 助手'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: instruction,
                  minLines: 2,
                  maxLines: 4,
                  enabled: !s.agentBusy,
                  decoration: const InputDecoration(
                    hintText: '例如：提亮半档，恢复高光，略微暖一点，不要美颜。',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '在线生成参数 → 检查范围 → 本地渲染 → 可撤销应用',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(height: 14),
                for (final e in s.events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '•  $e',
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                if (s.agentBusy) const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: s.agentBusy
                ? s.cancelAgent
                : () => Navigator.pop(dialog),
            child: Text(s.agentBusy ? '停止' : '关闭'),
          ),
          FilledButton(
            onPressed: s.agentBusy
                ? null
                : () => attempt(() => s.runAgent(instruction.text.trim())),
            child: const Text('开始处理'),
          ),
        ],
      ),
    ),
  );
  Future<void> batchDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => ListenableBuilder(
        listenable: s,
        builder: (context, _) => AlertDialog(
          title: const Text('批量处理'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已勾选 ${s.selected.length} / ${s.photos.length} 张',
                  style: const TextStyle(color: accent),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: s.batchBusy
                      ? null
                      : () {
                          s.selected.addAll(s.photos.map((p) => p.id));
                          s.refresh();
                        },
                  child: const Text('选择图库全部照片'),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: s.batchMode,
                  decoration: const InputDecoration(labelText: '参数来源'),
                  items: const [
                    DropdownMenuItem(value: 'uniform', child: Text('使用当前照片配方')),
                    DropdownMenuItem(value: 'saved', child: Text('每张照片已存配方')),
                    DropdownMenuItem(value: 'auto', child: Text('逐张自动影调校正')),
                  ],
                  onChanged: s.batchBusy
                      ? null
                      : (v) {
                          s.batchMode = v!;
                          s.refresh();
                        },
                ),
                const SizedBox(height: 14),
                const Text(
                  '逐张自动校正使用本地亮度统计。队列逐张执行以控制内存，保留原片与手动配方。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(s.batchStatus, style: const TextStyle(fontSize: 12)),
                if (s.batchBusy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: s.batchBusy
                  ? () {
                      s.cancelBatch = true;
                    }
                  : () => Navigator.pop(dialog),
              child: Text(s.batchBusy ? '停止队列' : '关闭'),
            ),
            FilledButton(
              onPressed: s.batchBusy || s.selected.isEmpty
                  ? null
                  : () => attempt(() async {
                      String? folder;
                      if (!Platform.isAndroid) {
                        folder = await FilePicker.getDirectoryPath(
                          dialogTitle: '选择批量导出目录',
                        );
                      }
                      if (!Platform.isAndroid && folder == null) return;
                      final output = Directory(
                        folder ??
                            p.join(
                              s.directory!.path,
                              'Exports',
                              'Batch-${DateTime.now().millisecondsSinceEpoch}',
                            ),
                      );
                      final files = await s.batchExport(output);
                      if (Platform.isAndroid && files.isNotEmpty) {
                        final zip = p.join(
                              s.directory!.path,
                              'Exports',
                              'LumaStudio-${DateTime.now().millisecondsSinceEpoch}.zip',
                            ),
                            path = output.path;
                        await Isolate.run(() async {
                          final encoder = ZipFileEncoder();
                          await encoder.zipDirectory(
                            Directory(path),
                            filename: zip,
                          );
                        });
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [XFile(zip)],
                            text: 'LumaStudio 批量精修照片',
                          ),
                        );
                      }
                    }),
              child: Text(Platform.isAndroid ? '处理并分享文件包' : '开始导出'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Histogram extends CustomPainter {
  _Histogram(this.bins);
  final List<int> bins;
  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;
    final max = bins.reduce(math.max).clamp(1, 1 << 30),
        path = Path()..moveTo(0, size.height);
    for (var i = 0; i < bins.length; i++) {
      path.lineTo(
        i / (bins.length - 1) * size.width,
        size.height * (1 - math.sqrt(bins[i] / max)),
      );
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = accent.withValues(alpha: .2));
    canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: .6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_Histogram oldDelegate) => oldDelegate.bins != bins;
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}
