import 'package:flutter/material.dart';

import '../services/camera_prefs.dart';
import '../theme.dart';

/// Doka `DokaPalettePanelController` 的 Flutter 版：
/// 二维调色板（横轴颜色、纵轴色调）+ 强度滑杆 + 重置。
class PaletteSheet extends StatefulWidget {
  const PaletteSheet({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<PaletteSheet> createState() => _PaletteSheetState();
}

class _PaletteSheetState extends State<PaletteSheet> {
  final CameraPrefs _prefs = CameraPrefs.instance;
  late double _hue;
  late double _tone = _prefs.paletteTone;
  late double _strength = _prefs.paletteStrength;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(_prefs.paletteColor);
    _hue = hsv.hue / 360;
  }

  Color get _color => HSVColor.fromAHSV(
    1,
    _hue * 360,
    0.48,
    1,
  ).toColor();

  void _updatePad(Offset local, Size size) {
    setState(() {
      _hue = (local.dx / size.width).clamp(0.0, 1.0);
      _tone = (1 - local.dy / size.height).clamp(0.0, 1.0);
    });
    _persist();
  }

  void _persist() {
    _prefs.paletteEnabled = true;
    _prefs.paletteColorValue = _color.toARGB32();
    _prefs.paletteTone = _tone;
    _prefs.paletteStrength = _strength;
    _prefs.touch();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: const BoxDecoration(
          color: Color(0xFF0B0B0B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: PrimeColor.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Text(
                  '调色盘',
                  style: TextStyle(
                    fontSize: 17,
                    color: PrimeColor.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(_strength * 100).round()}%',
                  style: const TextStyle(fontSize: 10, color: PrimeColor.white38),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _hue = 0.52;
                      _tone = 0.5;
                      _strength = 0.5;
                    });
                    _persist();
                  },
                  child: const Text(
                    '重置',
                    style: TextStyle(fontSize: 11, color: PrimeColor.white38),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, 138);
                return GestureDetector(
                  onPanDown: (details) => _updatePad(details.localPosition, size),
                  onPanUpdate: (details) =>
                      _updatePad(details.localPosition, size),
                  child: Container(
                    width: size.width,
                    height: size.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(_color, Colors.white, 0.28)!,
                          _color,
                          Color.lerp(_color, Colors.black, 0.45)!,
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: (_hue * size.width).clamp(8, size.width - 8),
                          top: ((1 - _tone) * size.height).clamp(
                            8,
                            size.height - 8,
                          ),
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: Colors.black54,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 9,
                          bottom: 8,
                          child: Text(
                            '颜色',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  '强度',
                  style: TextStyle(fontSize: 11, color: PrimeColor.white54),
                ),
                Expanded(
                  child: Slider(
                    value: _strength,
                    min: 0,
                    max: 1,
                    activeColor: const Color(0xFF80EEFF),
                    inactiveColor: PrimeColor.white12,
                    onChanged: (value) {
                      setState(() => _strength = value);
                      _persist();
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text(
                  '色调',
                  style: TextStyle(fontSize: 11, color: PrimeColor.white54),
                ),
                Expanded(
                  child: Slider(
                    value: _tone,
                    min: 0,
                    max: 1,
                    activeColor: const Color(0xFF80EEFF),
                    inactiveColor: PrimeColor.white12,
                    onChanged: (value) {
                      setState(() => _tone = value);
                      _persist();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () {
                _persist();
                Navigator.of(context).maybePop();
              },
              child: Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PrimeColor.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '应用到取景',
                  style: TextStyle(
                    fontSize: 13,
                    color: PrimeColor.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
