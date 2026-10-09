import 'dart:async';

import 'package:flutter/material.dart';
import 'app_layout.dart';
import 'app_theme.dart';
import 'remote_widgets.dart';

enum SleepTimerChoice {
  off,
  minutes15,
  minutes30,
  minutes60,
  minutes90,
  finishEpisode;

  String get label => switch (this) {
    SleepTimerChoice.off => '关闭睡眠定时',
    SleepTimerChoice.minutes15 => '15 分钟',
    SleepTimerChoice.minutes30 => '30 分钟',
    SleepTimerChoice.minutes60 => '60 分钟',
    SleepTimerChoice.minutes90 => '90 分钟',
    SleepTimerChoice.finishEpisode => '播完本集',
  };

  int? get minutes => switch (this) {
    SleepTimerChoice.minutes15 => 15,
    SleepTimerChoice.minutes30 => 30,
    SleepTimerChoice.minutes60 => 60,
    SleepTimerChoice.minutes90 => 90,
    _ => null,
  };
}

class SleepTimerController extends ChangeNotifier {
  SleepTimerController({this.onExpire});

  final VoidCallback? onExpire;

  DateTime? _deadline;
  bool _finishEpisode = false;
  Timer? _ticker;
  Timer? _expiry;

  bool get active => _deadline != null || _finishEpisode;
  bool get finishEpisode => _finishEpisode;

  Duration? get remaining {
    final deadline = _deadline;
    if (deadline == null) return null;
    final value = deadline.difference(DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  String get label {
    if (_finishEpisode) return '播完本集';
    final value = remaining;
    if (value == null) return '';
    final minutes = (value.inSeconds / 60).ceil();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      return rest == 0 ? '$hours 时' : '$hours 时 $rest 分';
    }
    return '$minutes 分';
  }

  void select(SleepTimerChoice choice) {
    if (choice == SleepTimerChoice.off) {
      cancel();
    } else if (choice == SleepTimerChoice.finishEpisode) {
      startFinishEpisode();
    } else {
      startMinutes(choice.minutes!);
    }
  }

  void startMinutes(int minutes) {
    cancel();
    _deadline = DateTime.now().add(Duration(minutes: minutes));
    _expiry = Timer(Duration(minutes: minutes), () {
      cancel();
      onExpire?.call();
    });
    _startTicker();
    notifyListeners();
  }

  void startFinishEpisode() {
    cancel();
    _finishEpisode = true;
    notifyListeners();
  }

  void cancel() {
    _expiry?.cancel();
    _expiry = null;
    _ticker?.cancel();
    _ticker = null;
    final wasActive = _deadline != null || _finishEpisode;
    _deadline = null;
    _finishEpisode = false;
    if (wasActive) notifyListeners();
  }

  bool consumeFinishEpisode() {
    if (!_finishEpisode) return false;
    _finishEpisode = false;
    notifyListeners();
    return true;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}

Future<void> showSleepTimerSheet(
  BuildContext context, {
  required SleepTimerController controller,
  required ValueChanged<SleepTimerChoice> onSelect,
  bool showFinishEpisode = true,
  Color? backgroundColor,
}) async {
  final options = [
    SleepTimerChoice.off,
    SleepTimerChoice.minutes15,
    SleepTimerChoice.minutes30,
    SleepTimerChoice.minutes60,
    SleepTimerChoice.minutes90,
    if (showFinishEpisode) SleepTimerChoice.finishEpisode,
  ];
  final choice = await showDialog<Object>(
    context: context,
    builder: (dialogContext) => Theme(
      data: AppTheme.dark,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, _) => AppLayout.isTelevision(context)
            ? TelevisionActionDialog(
                title: controller.active
                    ? '睡眠定时 · ${controller.label}'
                    : '睡眠定时',
                options: [
                  for (final option in options)
                    TelevisionAction(
                      value: option.name,
                      label: option.label,
                      icon: Icons.bedtime_outlined,
                    ),
                ],
              )
            : AlertDialog(
                backgroundColor: backgroundColor,
                title: Text(
                  controller.active ? '睡眠定时 · ${controller.label}' : '睡眠定时',
                ),
                scrollable: true,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options)
                      ListTile(
                        key: ValueKey('sleep-timer-${option.name}'),
                        title: Text(option.label),
                        onTap: () => Navigator.pop(dialogContext, option),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('返回播放'),
                  ),
                ],
              ),
      ),
    ),
  );
  if (choice is SleepTimerChoice) onSelect(choice);
  if (choice is String) {
    onSelect(
      SleepTimerChoice.values.firstWhere((option) => option.name == choice),
    );
  }
}
