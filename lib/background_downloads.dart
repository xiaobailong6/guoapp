import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'core_bridge.dart';
import 'local_store.dart';
import 'media_library.dart';
import 'app_build.dart';

@pragma('vm:entry-point')
void downloadServiceEntry() {
  FlutterForegroundTask.setTaskHandler(DownloadTaskHandler());
}

class BackgroundDownloads {
  static bool _prepared = false;
  static bool _notificationRequested = false;
  static Future<void>? _starting;

  static Future<void> prepare() async {
    if (!Platform.isAndroid || _prepared) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'zhenguojian_downloads',
        channelName: '$appName下载',
        channelDescription: '后台下载和媒体处理进度',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(2000),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        stopWithTask: false,
      ),
    );
    _prepared = true;
  }

  static Future<void> ensureStarted() async {
    if (!Platform.isAndroid) return;
    final pending = _starting;
    if (pending != null) return pending;
    final starting = _start();
    _starting = starting;
    try {
      await starting;
    } finally {
      if (identical(_starting, starting)) _starting = null;
    }
  }

  static Future<void> _start() async {
    await prepare();
    if (await FlutterForegroundTask.isRunningService) return;
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission == NotificationPermission.denied &&
        !_notificationRequested) {
      _notificationRequested = true;
      try {
        await FlutterForegroundTask.requestNotificationPermission();
      } on PlatformException catch (error) {
        final message = (error.message ?? '').toLowerCase();
        if (!message.contains('permission request') ||
            !message.contains('cancelled') && !message.contains('closed')) {
          throw AppFailure('通知权限请求未完成，请返回应用后重试。');
        }
      }
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: 2406,
      serviceTypes: [ForegroundServiceTypes.dataSync],
      notificationTitle: appName,
      notificationText: '正在准备后台任务',
      notificationButtons: [
        const NotificationButton(id: 'pause', text: '暂停下载'),
      ],
      callback: downloadServiceEntry,
    );
    if (result is ServiceRequestFailure) {
      throw AppFailure('后台下载服务启动失败，请保持应用在前台后重试。');
    }
  }
}

class DownloadTaskHandler extends TaskHandler {
  final repository = NativeRepository(background: true);
  MediaLibrary? library;
  bool _polling = false;
  int _idle = 0;
  String? _notificationText;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await repository.initialize();
    library = MediaLibrary(
      repository,
      LocalStore(await SharedPreferences.getInstance()),
      automaticWorker: true,
    );
    await _update();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_update());
  }

  Future<void> _notify(String text) async {
    if (_notificationText == text) return;
    final result = await FlutterForegroundTask.updateService(
      notificationTitle: appName,
      notificationText: text,
    );
    if (result is ServiceRequestFailure) return;
    _notificationText = text;
  }

  Future<void> _update() async {
    if (_polling) return;
    _polling = true;
    try {
      if (library != null) unawaited(library!.maybeExport());
      final jobs = await repository.downloads();
      final active = jobs.where((job) => job.active).toList();
      final work = await repository.workLease('', '');
      if (active.isEmpty && work == 0) {
        _idle++;
        if (_idle >= 5) {
          await FlutterForegroundTask.stopService();
          return;
        }
      } else {
        _idle = 0;
      }
      final bytes = active.fold<int>(0, (total, job) => total + job.bytes);
      await _notify(
        work > 0
            ? '正在更新站源或处理本地媒体'
            : active.isEmpty
            ? '下载已完成或暂停'
            : '${active.length} 集下载中 · ${(bytes / 1048576).toStringAsFixed(1)} MB',
      );
    } catch (_) {
      await _notify('正在等待下载任务');
    } finally {
      _polling = false;
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'pause') unawaited(repository.controlDownloads('pauseAll'));
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await library?.cancel();
    library?.dispose();
    if (isTimeout) {
      await repository.controlDownloads('pauseAll');
      await FFmpegKit.cancel();
    }
  }
}
