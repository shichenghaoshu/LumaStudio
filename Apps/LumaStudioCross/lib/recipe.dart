import 'dart:convert';

class Control {
  const Control(
    this.id,
    this.title,
    this.min,
    this.max,
    this.initial, {
    this.unit = '',
    this.section = '影调',
  });
  final String id, title, unit, section;
  final double min, max, initial;
}

const controls = <Control>[
  Control('exposure', '曝光', -5, 5, 0, unit: 'EV'),
  Control('contrast', '对比度', 0.2, 2, 1),
  Control('brightness', '亮度', -0.5, 0.5, 0),
  Control('highlights', '高光', -1, 1, 0),
  Control('shadows', '阴影', -1, 1, 0),
  Control('whites', '白色色阶', -1, 1, 0),
  Control('blacks', '黑色色阶', -1, 1, 0),
  Control('temperature', '色温', 2000, 12000, 6500, unit: 'K', section: '色彩'),
  Control('tint', '色调', -150, 150, 0, section: '色彩'),
  Control('saturation', '饱和度', 0, 2, 1, section: '色彩'),
  Control('vibrance', '自然饱和度', -1, 1, 0, section: '色彩'),
  Control('sharpen', '锐化', 0, 2, 0, section: '细节'),
  Control('denoise', '亮度降噪', 0, 1, 0, section: '细节'),
  Control('vignette', '暗角', 0, 1, 0, section: '细节'),
  Control('grain', '胶片颗粒', 0, 0.3, 0, section: '细节'),
  Control('intensity', '滤镜强度', 0, 1, 0.8, section: '滤镜'),
  Control('skinSmooth', '肤色柔化', 0, 1, 0, section: '肤色'),
  Control('skinBright', '肤色提亮', 0, 1, 0, section: '肤色'),
  Control('skinTexture', '纹理保留', 0, 1, 1, section: '肤色'),
  Control('skinRadius', '磨皮范围', 0.5, 8, 1, section: '肤色'),
  Control('skinEven', '肤色均匀', 0, 1, 0, section: '肤色'),
  Control('skinWarmth', '肤色冷暖', -1, 1, 0, section: '肤色'),
  Control('skinWhiten', '瓷白美白', 0, 1, 0, section: '肤色'),
  Control('skinRosy', '红润肤色', 0, 1, 0, section: '肤色'),
];
const beautyStyles = ['自然', '精修', '瓷白', '高强度'];
Recipe beautyStyle(Recipe current, String title) {
  final values = switch (title) {
    '自然' => [0.3, 0.08, 0.9, 1.0, 0.12, 0.0, 0.0, 0.0],
    '精修' => [0.65, 0.2, 0.55, 2.2, 0.4, 0.05, 0.15, 0.1],
    '瓷白' => [0.9, 0.4, 0.15, 4.0, 0.8, 0.0, 0.8, 0.1],
    '高强度' => [1.0, 0.45, 0.0, 6.0, 0.95, 0.1, 0.65, 0.35],
    _ => throw const FormatException('未知美颜预设'),
  };
  var next = current;
  for (var i = 0; i < values.length; i++) {
    next = next.set(16 + i, values[i]);
  }
  return next;
}

const bands = [
  'red',
  'orange',
  'yellow',
  'green',
  'aqua',
  'blue',
  'purple',
  'magenta',
];
const bandTitles = ['红', '橙', '黄', '绿', '青', '蓝', '紫', '洋红'];
const filterTitles = <String, String>{
  'natural': '自然',
  'portrait': '自然人像',
  'film': '经典胶片',
  'warm': '暖调',
  'cool': '冷调',
  'clean': '清透',
  'ivory': '象牙白',
  'rose': '玫瑰',
  'peach': '蜜桃',
  'softPortrait': '柔光人像',
  'amber': '琥珀',
  'golden': '金色时刻',
  'copper': '铜色',
  'sunset': '落日',
  'silver': '银盐',
  'mono': '经典黑白',
  'matteMono': '哑光黑白',
  'noir': '黑色电影',
  'forest': '森林',
  'jade': '青玉',
  'ocean': '海岸',
  'alpine': '山野',
  'faded': '褪色胶片',
  'vintage': '复古',
  'instant': '即影',
  'cinema': '电影',
  'tealOrange': '青橙',
  'night': '夜色',
  'pastel': '粉彩',
  'airy': '空气感',
};

Recipe applyOnlineProposal(
  Recipe current,
  Map<String, dynamic> proposal,
  String instruction,
) {
  if (proposal.keys.any(
    (k) => !{'changes', 'filter', 'explanation'}.contains(k),
  )) {
    throw const FormatException('模型返回不支持的字段');
  }
  final changes = Map<String, dynamic>.from(proposal['changes'] as Map? ?? {});
  var next = current;
  final forbidden = RegExp(
    r'不.{0,6}(美颜|磨皮|肤色)|(?:no|without|do not|don.t)\s+(?:beauty|retouch|smooth|skin)',
    caseSensitive: false,
  ).hasMatch(instruction);
  final requested = RegExp(
    r'美颜|磨皮|美白|瓷白|红润|(?:提亮|柔化|统一).{0,4}肤色|肤色.{0,3}(?:提亮|柔化|统一)|smooth.{0,12}skin|brighten.{0,12}skin|beauty',
    caseSensitive: false,
  ).hasMatch(instruction);
  for (final entry in changes.entries) {
    final i = controls.indexWhere((c) => c.id == entry.key);
    if (i < 0) throw FormatException('模型返回不支持的参数：${entry.key}');
    if (entry.value is! num) throw const FormatException('模型参数必须是数字');
    final v = (entry.value as num).toDouble();
    if (!v.isFinite || v < controls[i].min || v > controls[i].max) {
      throw FormatException('模型参数超出范围：${entry.key}');
    }
    if (i >= 16 && (forbidden || !requested)) continue;
    if (entry.key == 'skinWhiten' &&
        RegExp(r'不.{0,3}美白|不.{0,3}瓷白').hasMatch(instruction)) {
      continue;
    }
    if (entry.key == 'skinRosy' && RegExp(r'不.{0,3}红润').hasMatch(instruction)) {
      continue;
    }
    next = next.set(i, v);
  }
  if (proposal.containsKey('filter')) {
    final f = proposal['filter'];
    if (f == null) {
      next = next.copy(clearFilter: true);
    } else {
      if (f is! String || !filterTitles.containsKey(f)) {
        throw const FormatException('模型返回未知滤镜');
      }
      next = next.copy(filter: f);
    }
  }
  return next;
}

class Recipe {
  Recipe({
    List<double>? values,
    List<double>? hsl,
    this.filter,
    this.turns = 0,
    this.aspect = 0,
    this.flip = false,
  }) : values = List.unmodifiable(values ?? controls.map((c) => c.initial)),
       hsl = List<double>.unmodifiable(hsl ?? List<double>.filled(24, 0.0));
  final List<double> values, hsl;
  final String? filter;
  final int turns;
  final double aspect;
  final bool flip;
  Recipe set(int i, double v) {
    final n = values.toList();
    n[i] = v.clamp(controls[i].min, controls[i].max);
    return copy(values: n);
  }

  Recipe setHSL(int i, double v) {
    final n = hsl.toList();
    n[i] = v.clamp(i % 3 == 0 ? -0.5 : -1, i % 3 == 0 ? 0.5 : 1);
    return copy(hsl: n);
  }

  Recipe copy({
    List<double>? values,
    List<double>? hsl,
    String? filter,
    bool clearFilter = false,
    int? turns,
    double? aspect,
    bool? flip,
  }) => Recipe(
    values: values ?? this.values,
    hsl: hsl ?? this.hsl,
    filter: clearFilter ? null : filter ?? this.filter,
    turns: turns ?? this.turns,
    aspect: aspect ?? this.aspect,
    flip: flip ?? this.flip,
  );
  Map<String, Object?> toJson() => {
    'schema': 'luma.portable/v1',
    'values': {
      for (var i = 0; i < controls.length; i++) controls[i].id: values[i],
    },
    'hsl': hsl,
    'filter': filter,
    'turns': turns,
    'aspect': aspect,
    'flip': flip,
  };
  factory Recipe.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 'luma.portable/v1') {
      throw const FormatException(
        '此客户端只接受 LumaStudio Portable v1 配方；Mac 专业配方尚不互通。',
      );
    }
    final map = Map<String, dynamic>.from(j['values'] as Map? ?? {});
    if (map.keys.any((k) => !controls.any((c) => c.id == k))) {
      throw const FormatException('配方包含不支持的参数');
    }
    final values = <double>[];
    for (final c in controls) {
      final n = (map[c.id] as num?)?.toDouble() ?? c.initial;
      if (!n.isFinite || n < c.min || n > c.max) {
        throw FormatException('${c.title}超出范围');
      }
      values.add(n);
    }
    final hs = (j['hsl'] as List? ?? List.filled(24, 0))
        .map((e) => (e as num).toDouble())
        .toList();
    if (hs.length != 24 ||
        hs.indexed.any(
          (e) => !e.$2.isFinite || e.$2.abs() > (e.$1 % 3 == 0 ? 0.5 : 1),
        )) {
      throw const FormatException('HSL 配方无效');
    }
    final f = j['filter'] as String?;
    if (f != null && !filterTitles.containsKey(f)) {
      throw const FormatException('未注册的滤镜');
    }
    final turns = (j['turns'] as num?)?.toInt() ?? 0,
        aspect = (j['aspect'] as num?)?.toDouble() ?? 0;
    if (turns < 0 ||
        turns > 3 ||
        !aspect.isFinite ||
        aspect < 0 ||
        aspect > 3) {
      throw const FormatException('裁切参数无效');
    }
    return Recipe(
      values: values,
      hsl: hs,
      filter: f,
      turns: turns,
      aspect: aspect,
      flip: j['flip'] as bool? ?? false,
    );
  }
  String encode() => jsonEncode(toJson());
  @override
  bool operator ==(Object other) =>
      other is Recipe && encode() == other.encode();
  @override
  int get hashCode => encode().hashCode;
}
