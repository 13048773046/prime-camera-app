import 'package:flutter_test/flutter_test.dart';
import 'package:prime_camera/services/guidance.dart';

GuidanceFrame frame({
  List<double>? box,
  List<double>? face,
  List<double>? saliency,
  double roll = 0,
}) => GuidanceFrame(
  box: box,
  face: face,
  saliency: saliency,
  roll: roll,
  pitch: 0,
  frameW: 1080,
  frameH: 1920,
  hfov: 60,
  ts: 1,
);

void main() {
  const composer = LiveComposer();

  test('没有人时不乱给口令', () {
    final guide = composer.compose(frame(), zoom: 1);
    expect(guide.hint, '把人物放进取景框');
    expect(guide.actionLabel, '找主体');
    expect(guide.subjectBox, isEmpty);
  });

  test('人物太小喊靠近', () {
    final guide = composer.compose(
      frame(
        box: const [0.3, 0.2, 0.3, 0.45],
        face: const [0.46, 0.2, 0.06, 0.12],
      ),
      zoom: 1,
    );
    expect(guide.hint, contains('再靠近'));
    expect(guide.actionLabel, contains('再近'));
  });

  test('距离高度角度都对时提示可以拍', () {
    final guide = composer.compose(
      frame(
        box: const [0.3, 0.08, 0.4, 0.62],
        face: const [0.46, 0.12, 0.09, 0.20],
      ),
      zoom: 1,
    );
    expect(guide.hint, '可以拍了，稳住呼吸');
    expect(guide.actionLabel, '已对齐');
  });

  test('头顶留白太多时先降机位', () {
    final guide = composer.compose(
      frame(
        box: const [0.3, 0.28, 0.4, 0.6],
        face: const [0.46, 0.30, 0.09, 0.20],
      ),
      zoom: 1,
    );
    expect(guide.hint, '镜头降到胸口');
  });

  test('人物偏左时提示把手机往左带', () {
    final guide = composer.compose(
      frame(
        box: const [0.08, 0.10, 0.30, 0.60],
        face: const [0.18, 0.12, 0.09, 0.16],
      ),
      zoom: 1,
    );
    expect(guide.hint, contains('往左带'));
    expect(guide.actionLabel, '左移');
  });

  test('水平歪了提示回正', () {
    final guide = composer.compose(
      frame(
        box: const [0.3, 0.08, 0.4, 0.62],
        face: const [0.46, 0.12, 0.09, 0.20],
        roll: 4,
      ),
      zoom: 1,
    );
    expect(guide.hint, contains('回正'));
    expect(guide.actionLabel, contains('°'));
  });

  test('通用场景不依赖人脸，优先使用显著区域', () {
    final guide = composer.compose(
      frame(saliency: const [0.36, 0.24, 0.28, 0.34]),
      zoom: 1,
      mode: SceneMode.general,
    );
    expect(guide.subjectBox, isNotEmpty);
    expect(guide.hint, isNot(contains('人物')));
  });

  test('街景把显著区域引导到右三分', () {
    final left = composer.compose(
      frame(saliency: const [0.10, 0.28, 0.22, 0.30], roll: 0.4),
      zoom: 1,
      mode: SceneMode.street,
    );
    expect(left.hint, contains('往右带'));

    final aligned = composer.compose(
      frame(saliency: const [0.58, 0.24, 0.22, 0.28], roll: 0.4),
      zoom: 1,
      mode: SceneMode.street,
    );
    expect(aligned.actionLabel, '已对齐');
    expect(aligned.hint, contains('可以拍了'));
  });
}
