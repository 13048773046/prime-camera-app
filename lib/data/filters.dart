import 'package:flutter/material.dart';

/// Doka 1.3.20 的滤镜枚举：F 系列、K 系列、Agfa、清新人像、黑白。
/// 原片是单独入口，不占 24 个 LUT。
enum FilterCategory { base, fSeries, kSeries, agfa, dokaPortrait, bw }

extension FilterCategoryLabel on FilterCategory {
  String get label => switch (this) {
    FilterCategory.base => '原片',
    FilterCategory.fSeries => 'F 系列',
    FilterCategory.kSeries => 'K 系列',
    FilterCategory.agfa => 'Agfa',
    FilterCategory.dokaPortrait => '清新人像',
    FilterCategory.bw => '黑白',
  };

  String get completeLabel => switch (this) {
    FilterCategory.fSeries => '富士',
    FilterCategory.kSeries => '柯达',
    _ => label,
  };
}

class FilterPreset {
  const FilterPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.matrix,
    required this.description,
    required this.positives,
    required this.negatives,
    this.pro = false,
    this.unlockShots = 20,
  });

  final String id;
  final String name;
  final FilterCategory category;
  final List<double> matrix;
  final String description;
  final List<String> positives;
  final List<String> negatives;
  final bool pro;
  final int unlockShots;

  ColorFilter get colorFilter => ColorFilter.matrix(matrix);
}

const List<double> _identity = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

List<double> _tone({
  double r = 1,
  double g = 1,
  double b = 1,
  double bias = 0,
  double contrast = 1,
  double lift = 0,
}) {
  final c = contrast;
  final k = (1 - c) * 128 + lift;
  return <double>[
    r * c, 0, 0, 0, bias + k,
    0, g * c, 0, 0, bias + k,
    0, 0, b * c, 0, bias + k,
    0, 0, 0, 1, 0,
  ];
}

List<double> _mono({double contrast = 1.05, double lift = 6}) {
  final c = contrast;
  final k = (1 - c) * 128 + lift;
  return <double>[
    0.299 * c, 0.587 * c, 0.114 * c, 0, k,
    0.299 * c, 0.587 * c, 0.114 * c, 0, k,
    0.299 * c, 0.587 * c, 0.114 * c, 0, k,
    0, 0, 0, 1, 0,
  ];
}

/// 24 个具名 LUT + 原片。矩阵是按 Doka 胶片方向做的可移植近似；
/// 原生成片侧用 CoreImage 对同一 id 再渲染，预览和成片保持同一组 id。
final List<FilterPreset> dokaFilters = <FilterPreset>[
  const FilterPreset(
    id: 'none',
    name: '原片',
    category: FilterCategory.base,
    matrix: _identity,
    description: '不改变颜色，保留现场光线与肤色。',
    positives: ['真实', '适合后期'],
    negatives: ['没有胶片味'],
  ),

  // F 系列（富士）12 款。
  FilterPreset(
    id: 'f_classic_chrome',
    name: 'Classic Chrome',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.00, g: 0.99, b: 1.06, contrast: 1.12, lift: 2),
    description: '低饱和、硬朗阴影的纪实色彩，适合街头和建筑。',
    positives: ['街头', '建筑', '阴天'],
    negatives: ['肤色偏冷', '不适合高饱和场景'],
  ),
  FilterPreset(
    id: 'f_provia',
    name: 'PROVIA',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.04, g: 1.04, b: 1.06, contrast: 1.06, lift: 3),
    description: '标准透明感，颜色准确、反差适中。',
    positives: ['日常', '旅行', '通用'],
    negatives: ['个性较弱'],
  ),
  FilterPreset(
    id: 'f_velvia',
    name: 'Velvia',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.18, g: 1.10, b: 1.06, contrast: 1.18, lift: 0),
    description: '高饱和风光胶片，红绿蓝更浓，适合日出日落和森林。',
    positives: ['风光', '花木', '夕阳'],
    negatives: ['肤色偏红', '室内易过艳'],
    pro: true,
  ),
  FilterPreset(
    id: 'f_cc',
    name: 'CC',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.06, g: 1.07, b: 1.04, contrast: 1.08, lift: 5),
    description: '清透彩色，轻微抬黑位，适合日常人像。',
    positives: ['人像', '日常', '咖啡店'],
    negatives: ['弱光下偏灰'],
  ),
  FilterPreset(
    id: 'f_classic_neg',
    name: 'Classic Neg',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.04, g: 0.98, b: 1.10, contrast: 1.08, lift: 8),
    description: '霓虹感和复古负片色，阴影偏青紫。',
    positives: ['夜景', '街拍', '霓虹'],
    negatives: ['白天肤色偏冷'],
  ),
  FilterPreset(
    id: 'f_cn',
    name: 'CN',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.08, g: 1.02, b: 1.02, contrast: 1.00, lift: 10),
    description: '暖调负片，肤色柔和，适合室内和黄昏。',
    positives: ['人像', '室内', '黄昏'],
    negatives: ['蓝色场景偏暖'],
  ),
  FilterPreset(
    id: 'f_c200',
    name: 'C200',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.10, g: 1.05, b: 0.98, contrast: 1.05, lift: 7),
    description: '便宜日常胶片的暖黄感，轻微颗粒和暖高光。',
    positives: ['日常', '街边', '记录'],
    negatives: ['不适合冷调场景'],
    pro: true,
  ),
  FilterPreset(
    id: 'f_160c',
    name: '160C',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.04, g: 1.09, b: 1.12, contrast: 1.02, lift: 10),
    description: '冷青中间调，适合阴天、海边和绿植。',
    positives: ['阴天', '海边', '绿植'],
    negatives: ['肤色偏青'],
  ),
  FilterPreset(
    id: 'f_pro_neg',
    name: 'Pro Neg',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.06, g: 1.03, b: 0.98, contrast: 0.96, lift: 12),
    description: '低反差、柔和肤色，适合室内人像。',
    positives: ['人像', '婚礼', '室内'],
    negatives: ['风景反差不足'],
  ),
  FilterPreset(
    id: 'f_400h',
    name: '400H',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.02, g: 1.04, b: 1.14, contrast: 0.94, lift: 15),
    description: '高感冷调，暗部偏青，适合夜景和雨天。',
    positives: ['夜景', '雨天', '城市'],
    negatives: ['强光下偏灰'],
    pro: true,
  ),
  FilterPreset(
    id: 'f_s100',
    name: 'S100',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.08, g: 1.06, b: 1.00, contrast: 0.98, lift: 11),
    description: '柔和暖调，适合肤色和浅色衣服。',
    positives: ['人像', '白衣服', '自然光'],
    negatives: ['高对比场景'],
  ),
  FilterPreset(
    id: 'f_s400',
    name: 'S400',
    category: FilterCategory.fSeries,
    matrix: _tone(r: 1.10, g: 1.00, b: 0.96, contrast: 1.10, lift: 8),
    description: '更浓郁的暖褐，适合黄昏、街头和木质场景。',
    positives: ['黄昏', '街头', '木质'],
    negatives: ['冷色场景', '阴天'],
    pro: true,
  ),

  // K 系列（柯达）3 款。
  FilterPreset(
    id: 'k_portra160',
    name: 'Portra 160',
    category: FilterCategory.kSeries,
    matrix: _tone(r: 1.05, g: 1.02, b: 1.00, contrast: 0.96, lift: 12),
    description: '低反差、细腻肤色，最经典的人像负片。',
    positives: ['人像', '婚礼', '自然光'],
    negatives: ['风光反差不足'],
    pro: true,
  ),
  FilterPreset(
    id: 'k_gold200',
    name: 'Gold 200',
    category: FilterCategory.kSeries,
    matrix: _tone(r: 1.16, g: 1.04, b: 0.88, bias: 5, contrast: 1.02, lift: 7),
    description: '金色暖阳、偏黄高光，适合日常和怀旧街头。',
    positives: ['夕阳', '街头', '日常'],
    negatives: ['冷色场景偏黄'],
    pro: true,
  ),
  FilterPreset(
    id: 'k_portra400',
    name: 'Portra 400',
    category: FilterCategory.kSeries,
    matrix: _tone(r: 1.10, g: 1.02, b: 0.96, contrast: 1.00, lift: 8),
    description: '暖肤色、宽容度高，适合室内外混合光。',
    positives: ['人像', '室内', '旅行'],
    negatives: ['高饱和场景'],
  ),

  // Agfa 2 款。
  FilterPreset(
    id: 'agfa_vista800',
    name: 'Vista 800',
    category: FilterCategory.agfa,
    matrix: _tone(r: 1.08, g: 1.04, b: 1.10, contrast: 1.06, lift: 13),
    description: '暖紫阴影、轻微颗粒，适合夜市和霓虹。',
    positives: ['夜市', '霓虹', '复古'],
    negatives: ['干净人像偏紫'],
  ),
  FilterPreset(
    id: 'agfa_ap100',
    name: 'AP 100',
    category: FilterCategory.agfa,
    matrix: _mono(contrast: 1.18, lift: 0),
    description: '硬朗黑白、深黑位，适合建筑和纪实。',
    positives: ['建筑', '纪实', '线条'],
    negatives: ['肤色反差大'],
  ),

  // Doka 清新人像 5 款。
  FilterPreset(
    id: 'doka_s50',
    name: 'S50',
    category: FilterCategory.dokaPortrait,
    matrix: _tone(r: 1.12, g: 1.10, b: 1.04, lift: 18, contrast: 0.92),
    description: '高曝光、冷白肤色，适合日系室内。',
    positives: ['日系', '室内', '白衣服'],
    negatives: ['强光下容易过曝'],
    pro: true,
  ),
  FilterPreset(
    id: 'doka_s100',
    name: 'S100',
    category: FilterCategory.dokaPortrait,
    matrix: _tone(r: 1.08, g: 1.07, b: 1.00, lift: 12, contrast: 0.96),
    description: '日常街拍，轻微暖调和柔和高光。',
    positives: ['日常', '街拍', '人像'],
    negatives: ['夜景偏灰'],
  ),
  FilterPreset(
    id: 'doka_s160',
    name: 'S160',
    category: FilterCategory.dokaPortrait,
    matrix: _tone(r: 1.04, g: 1.08, b: 1.06, lift: 8, contrast: 1.02),
    description: '青绿中间调，适合绿植、咖啡店和清新穿搭。',
    positives: ['绿植', '咖啡店', '清新'],
    negatives: ['肤色偏青'],
    pro: true,
  ),
  FilterPreset(
    id: 'doka_s200',
    name: 'S200',
    category: FilterCategory.dokaPortrait,
    matrix: _tone(r: 0.98, g: 1.02, b: 1.04, lift: 5, contrast: 1.10),
    description: '更深的阴影和冷静高光，适合阴天和城市。',
    positives: ['阴天', '城市', '情绪'],
    negatives: ['弱光下偏暗'],
    pro: true,
  ),
  FilterPreset(
    id: 'doka_s400',
    name: 'S400',
    category: FilterCategory.dokaPortrait,
    matrix: _tone(r: 1.02, g: 0.96, b: 0.93, lift: 2, contrast: 1.16),
    description: '浓郁暖褐、低亮高反差，适合黄昏和胶片人像。',
    positives: ['黄昏', '胶片', '人像'],
    negatives: ['强光下反差过硬'],
    pro: true,
  ),

  // Doka 黑白 2 款。
  FilterPreset(
    id: 'doka_x100',
    name: 'X100',
    category: FilterCategory.bw,
    matrix: _mono(contrast: 1.05, lift: 7),
    description: '中性黑白、灰阶柔和，适合日常纪实。',
    positives: ['纪实', '日常', '人像'],
    negatives: ['需要色彩的场景'],
  ),
  FilterPreset(
    id: 'doka_x400',
    name: 'X400',
    category: FilterCategory.bw,
    matrix: _mono(contrast: 1.25, lift: -3),
    description: '高反差黑白、深黑位，适合街头和建筑。',
    positives: ['街头', '建筑', '光影'],
    negatives: ['暗部细节少'],
    pro: true,
  ),
];

FilterPreset filterById(String id) => dokaFilters.firstWhere(
  (f) => f.id == id,
  orElse: () => dokaFilters.first,
);

List<FilterPreset> filtersByCategory(FilterCategory? category) {
  if (category == null) return dokaFilters;
  return dokaFilters.where((f) => f.category == category).toList();
}

/// 调色盘：用一层 soft-light 色片近似二维调色盘的色彩轴，
/// 再用亮度/对比参数近似色调轴。预览和保存共用同一组参数。
ColorFilter paletteColorFilter({
  required Color color,
  required double tone,
  required double strength,
}) {
  final s = strength.clamp(0.0, 1.0);
  final tint = color.withValues(alpha: 0.10 + s * 0.35);
  return ColorFilter.mode(tint, BlendMode.softLight);
}

/// 调色盘色调轴的亮度/对比矩阵。
List<double> paletteToneMatrix(double tone) {
  final t = tone.clamp(0.0, 1.0);
  final lift = (t - 0.5) * 28;
  return _tone(
    r: 1.0 + (t - 0.5) * 0.05,
    g: 1.0 + (t - 0.5) * 0.05,
    b: 1.0 + (t - 0.5) * 0.05,
    bias: lift,
    contrast: 1.0 + (t - 0.5) * 0.10,
    lift: (1 - t) * 8,
  );
}
