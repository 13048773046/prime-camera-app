import 'dart:ui';

import 'package:flutter/material.dart';

/// Doka 1.3.20 `filter_detail_*` / `filter_category_*` 中出现的胶片体系。
/// 名称保持 Doka 的原始叫法，色彩用可移植的 4x5 矩阵近似；原生侧用
/// CoreImage 的同一组 id 再渲染一次，保证取景预览和成片方向一致。
enum FilterCategory { base, doka, fSeries, kodak, agfa, bw }

extension FilterCategoryLabel on FilterCategory {
  String get label => switch (this) {
        FilterCategory.base => '原片',
        FilterCategory.doka => 'Doka',
        FilterCategory.fSeries => 'F 系列',
        FilterCategory.kodak => 'Kodak',
        FilterCategory.agfa => 'Agfa',
        FilterCategory.bw => '黑白',
      };
}

class FilterPreset {
  const FilterPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.matrix,
    this.pro = false,
    this.note = '',
  });

  final String id;
  final String name;
  final FilterCategory category;
  final List<double> matrix;
  final bool pro;
  final String note;

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
  // 先按通道缩放，再以 contrast/lift 模拟胶片曲线的黑位抬升。
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

final List<FilterPreset> dokaFilters = <FilterPreset>[
  const FilterPreset(id: 'none', name: '原片', category: FilterCategory.base, matrix: _identity, note: '保留真实颜色'),
  FilterPreset(id: 'clear', name: '清透', category: FilterCategory.base, matrix: _tone(r: 1.06, g: 1.07, b: 1.08, contrast: 1.08, lift: 4), note: '低饱和、干净高光'),
  FilterPreset(id: 'warm', name: '暖调', category: FilterCategory.base, matrix: _tone(r: 1.10, g: 1.02, b: 0.92, bias: 3, contrast: 1.04), note: '暖黄肤色与夕阳'),
  FilterPreset(id: 'cool', name: '冷调', category: FilterCategory.base, matrix: _tone(r: 0.94, g: 1.00, b: 1.10, bias: -1, contrast: 1.04), note: '青蓝阴影'),
  FilterPreset(id: 'mono', name: '黑白', category: FilterCategory.bw, matrix: _mono(), note: '中性黑白'),

  FilterPreset(id: 'doka_s50', name: 'S50', category: FilterCategory.doka, matrix: _tone(r: 1.12, g: 1.10, b: 1.04, lift: 18, contrast: 0.92), note: '高曝光、冷白'),
  FilterPreset(id: 'doka_s100', name: 'S100', category: FilterCategory.doka, matrix: _tone(r: 1.08, g: 1.07, b: 1.00, lift: 12, contrast: 0.96), note: '日常街拍'),
  FilterPreset(id: 'doka_s160', name: 'S160', category: FilterCategory.doka, matrix: _tone(r: 1.04, g: 1.08, b: 1.06, lift: 8, contrast: 1.02), note: '青绿中间调'),
  FilterPreset(id: 'doka_s200', name: 'S200', category: FilterCategory.doka, matrix: _tone(r: 0.98, g: 1.02, b: 1.04, lift: 5, contrast: 1.10), note: '更深的阴影'),
  FilterPreset(id: 'doka_s400', name: 'S400', category: FilterCategory.doka, matrix: _tone(r: 1.02, g: 0.96, b: 0.93, lift: 2, contrast: 1.16), note: '浓郁暖褐'),

  FilterPreset(id: 'f160c', name: 'F160C', category: FilterCategory.fSeries, matrix: _tone(r: 1.05, g: 1.10, b: 1.12, contrast: 1.02, lift: 10), note: '冷青胶片'),
  FilterPreset(id: 'f400h', name: 'F400H', category: FilterCategory.fSeries, matrix: _tone(r: 1.02, g: 1.04, b: 1.14, contrast: 0.94, lift: 14), pro: true, note: '高感冷调'),
  FilterPreset(id: 'fc200', name: 'FC200', category: FilterCategory.fSeries, matrix: _tone(r: 1.10, g: 1.06, b: 0.98, contrast: 1.06, lift: 6), pro: true, note: '暖黄日常'),
  FilterPreset(id: 'fcc', name: 'FCC', category: FilterCategory.fSeries, matrix: _tone(r: 1.08, g: 1.09, b: 1.06, contrast: 1.10, lift: 4), pro: true, note: '高对比彩色'),
  FilterPreset(id: 'classic_chrome', name: 'Classic Chrome', category: FilterCategory.fSeries, matrix: _tone(r: 1.02, g: 1.00, b: 1.06, contrast: 1.12, lift: 0), pro: true, note: '褪色纪实'),
  FilterPreset(id: 'classic_neg', name: 'Classic Neg', category: FilterCategory.fSeries, matrix: _tone(r: 1.04, g: 0.98, b: 1.10, contrast: 1.08, lift: 8), pro: true, note: '霓虹夜景'),
  FilterPreset(id: 'pro_neg', name: 'Pro Neg', category: FilterCategory.fSeries, matrix: _tone(r: 1.06, g: 1.04, b: 0.98, contrast: 0.98, lift: 10), pro: true, note: '柔和肤色'),
  FilterPreset(id: 'provia', name: 'Provia', category: FilterCategory.fSeries, matrix: _tone(r: 1.04, g: 1.04, b: 1.06, contrast: 1.06), pro: true, note: '标准透明感'),
  FilterPreset(id: 'velvia', name: 'Velvia', category: FilterCategory.fSeries, matrix: _tone(r: 1.18, g: 1.10, b: 1.06, contrast: 1.18), pro: true, note: '高饱和风光'),
  FilterPreset(id: 'astia', name: 'Astia', category: FilterCategory.fSeries, matrix: _tone(r: 1.08, g: 1.04, b: 1.02, contrast: 1.02, lift: 6), pro: true, note: '柔和高光'),

  FilterPreset(id: 'kodak_gold', name: 'Gold 200', category: FilterCategory.kodak, matrix: _tone(r: 1.16, g: 1.04, b: 0.88, bias: 5, contrast: 1.02, lift: 6), pro: true, note: '金色暖阳'),
  FilterPreset(id: 'portra160', name: 'Portra 160', category: FilterCategory.kodak, matrix: _tone(r: 1.06, g: 1.02, b: 1.00, contrast: 0.96, lift: 10), pro: true, note: '低反差人像'),
  FilterPreset(id: 'portra400', name: 'Portra 400', category: FilterCategory.kodak, matrix: _tone(r: 1.10, g: 1.02, b: 0.96, contrast: 1.00, lift: 8), pro: true, note: '暖肤色'),
  FilterPreset(id: 'ektar', name: 'Ektar 100', category: FilterCategory.kodak, matrix: _tone(r: 1.10, g: 1.00, b: 1.04, contrast: 1.16), pro: true, note: '浓彩红蓝'),

  FilterPreset(id: 'agfa_ap100', name: 'APX 100', category: FilterCategory.agfa, matrix: _mono(contrast: 1.18, lift: 0), pro: true, note: '硬朗黑白'),
  FilterPreset(id: 'agfa_vista', name: 'Vista 800', category: FilterCategory.agfa, matrix: _tone(r: 1.08, g: 1.04, b: 1.10, contrast: 1.06, lift: 12), pro: true, note: '颗粒暖紫'),
  FilterPreset(id: 'bw_high', name: '黑白 400', category: FilterCategory.bw, matrix: _mono(contrast: 1.25, lift: -4), pro: true, note: '高反差纪实'),
];

FilterPreset filterById(String id) => dokaFilters.firstWhere(
      (f) => f.id == id,
      orElse: () => dokaFilters.first,
    );

List<FilterPreset> filtersByCategory(FilterCategory? category) {
  if (category == null) return dokaFilters;
  return dokaFilters.where((f) => f.category == category).toList();
}
