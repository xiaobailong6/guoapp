import 'package:duanju_app/app_orientation.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('直播锁横屏，旋转到竖屏后锁竖屏', () {
    expect(
      AppOrientationController.orientations(
        television: false,
        fullscreen: true,
        aspectRatio: 16 / 9,
      ),
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
      reason: '直播流为 16:9，进入播放页即锁横屏',
    );
    expect(
      AppOrientationController.orientations(
        television: false,
        fullscreen: true,
        aspectRatio: 9 / 16,
      ),
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
      reason: '旋转按钮切到竖屏后必须真正锁竖屏，否则一松手就被系统转回横屏',
    );
  });

  test('电视模式始终锁横屏，不参与旋转', () {
    expect(
      AppOrientationController.orientations(television: true),
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  });

  test('已下线的熊果不再出现在直播源里', () {
    expect(LiveSource.byId('xiongguo'), isNull);
    expect(
      LiveSource.values.map((source) => source.id),
      isNot(contains('xiongguo')),
    );
    final xiuguo = LiveSource.byId('xiuguo');
    expect(xiuguo, isNotNull, reason: '保留下来的直播源仍可正常取用');
    expect(xiuguo!.endpoints, isNotEmpty);
  });
}
