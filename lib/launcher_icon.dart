import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_build.dart';

/// 真果鉴安装后先以绿果鉴的名称与图标出现，只有激活分级限制开关才换成
/// 真果鉴的入口；绿果鉴不提供切换，桌面入口始终是绿果鉴。
class LauncherIcon {
  static const _channel = MethodChannel('duanju/device');

  static bool get supported =>
      allSourcesEnabled && !kIsWeb && Platform.isAndroid;

  static Future<void> apply(bool full) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('setLauncherEdition', {'full': full});
    } catch (_) {
      // 切换失败时保留当前入口：桌面图标属于系统状态，不影响应用内功能。
    }
  }
}
