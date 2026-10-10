import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core_bridge.dart';
import 'app_theme.dart';
import 'app_layout.dart';
import 'local_store.dart';
import 'glass_panel.dart';
import 'playback_preferences.dart';
import 'playback_settings_screen.dart';
import 'profiles_screen.dart';
import 'remote_widgets.dart';
import 'sources_screen.dart';
import 'storage_access.dart';
import 'widgets.dart';
import 'resource_settings_screen.dart';
import 'lan_screen.dart';
import 'library_transfer_actions.dart';
import 'watch_stats.dart';
import 'follow_state.dart';

String storageSize(int bytes) {
  if (bytes < 0) return '暂不可用';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.repository,
    required this.store,
    this.onLibraryChanged,
  });
  final AppRepository repository;
  final LocalStore store;
  final ValueChanged<Iterable<String>>? onLibraryChanged;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _listKey = GlobalKey<RemoteListState>();
  bool _busy = false;
  final _themeAnchor = GlobalKey();
  final _styleAnchor = GlobalKey();
  String? _message;

  /// 列表底部避让系统手势条 / 导航栏，避免最后一项被遮挡。
  static double _systemInset(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final padding = MediaQuery.paddingOf(context).bottom;
    return viewPadding > padding ? viewPadding : padding;
  }

  Future<void> _showWatchStats() => WatchStatsPanel.show(
    context,
    stats: widget.store.watchStats,
    watchingCount: widget.store.favorites
        .where(
          (drama) =>
              widget.store.following(drama.id)?.status == FollowStatus.watching,
        )
        .length,
  );

  Future<String?> _chooseOption(
    GlobalKey key,
    String value,
    List<(String, String, IconData)> options,
  ) {
    final anchorContext = key.currentContext;
    final size = MediaQuery.sizeOf(context);
    final anchor = anchorContext == null
        ? Rect.fromLTWH(size.width / 2, size.height / 3, 0, 0)
        : glassMenuAnchor(anchorContext);
    if (anchor == null) return Future.value();
    return showGlassMenu<String>(
      context: context,
      anchor: anchor,
      alignRight: true,
      autofocusSelected: true,
      width: 320,
      entries: [
        for (final (option, label, icon) in options)
          GlassMenuEntry(
            value: option,
            label: Text(label),
            leading: Icon(icon),
            selected: option == value,
          ),
      ],
    );
  }

  Future<void> _chooseTheme() async {
    final epoch = widget.store.profileEpoch;
    final selected = await _chooseOption(_themeAnchor, widget.store.themeMode, [
      ('light', '浅色', Icons.light_mode_outlined),
      ('dark', '深色', Icons.dark_mode_outlined),
      ('system', '跟随系统', Icons.brightness_auto_outlined),
    ]);
    if (selected == null || !mounted || epoch != widget.store.profileEpoch)
      return;
    await saveUserChange(context, () => widget.store.setThemeMode(selected));
  }

  Future<void> _chooseInterfaceStyle() async {
    final epoch = widget.store.profileEpoch;
    final selected =
        await _chooseOption(_styleAnchor, widget.store.interfaceStyle, [
          ('standard', '标准 · 经典底部导航', Icons.view_agenda_outlined),
          ('glass', '玻璃 · 悬浮底栏与菜单', Icons.blur_on_outlined),
        ]);
    if (selected == null || !mounted || epoch != widget.store.profileEpoch)
      return;
    await saveUserChange(
      context,
      () => widget.store.setInterfaceStyle(selected),
    );
  }

  Future<void> _backup(bool restore) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!restore) {
        final content = await widget.store.exportBackup();
        final saved = await FilePicker.saveFile(
          fileName:
              '$appSlug-backup-${DateTime.now().toIso8601String().substring(0, 10)}.json',
          bytes: Uint8List.fromList(utf8.encode(content)),
          mimeType: 'application/json',
        );
        if (saved != null && mounted) setState(() => _message = '备份已保存');
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (file == null || !mounted) return;
        final size = await file.length();
        if (size == null || size > 8 * 1024 * 1024) {
          throw const FormatException('备份文件过大或无法读取');
        }
        final content = utf8.decode(await file.readAsBytes());
        final data = widget.store.validateBackup(content);
        if (!mounted) return;
        final summary =
            '包含 ${(data['profiles'] as List).length} 个用户。将替换本机的用户、追剧、观看记录和偏好设置；已下载视频保留。恢复后使用备份内的管理员密码登录。';
        final bool accepted;
        if (AppLayout.isTelevision(context)) {
          accepted =
              await showDialog<String>(
                context: context,
                builder: (_) => TelevisionActionDialog(
                  title: '恢复备份？',
                  options: [
                    TelevisionAction(
                      value: 'restore',
                      label: '恢复这套备份',
                      description: summary,
                      icon: Icons.restore_rounded,
                    ),
                  ],
                ),
              ) ==
              'restore';
        } else {
          accepted =
              await showDialog<bool>(
                context: context,
                builder: (context) => _SettingsGlassConfirmation(
                  title: const Text('恢复备份？'),
                  content: Text(summary),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('恢复'),
                    ),
                  ],
                ),
              ) ??
              false;
        }
        if (!accepted || !mounted) return;
        await widget.store.importBackup(content);
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _libraryTransfer(bool restore) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final transfer = LibraryTransfer(widget.repository);
      final outcome = restore
          ? await transfer.importLibrary()
          : await transfer.exportLibrary();
      if (!mounted) return;
      final sources = outcome.importedSources;
      if (sources != null) {
        widget.onLibraryChanged?.call(
          sources.isEmpty
              ? widget.store.sources.map((item) => item.id)
              : sources,
        );
      }
      setState(() => _message = outcome.message);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleGreenMode() async {
    if (widget.store.greenMode) {
      const summary = '关闭后会展示成人点播与成人直播内容，站源管理与直播分类中将出现成人入口。';
      final bool accepted;
      if (AppLayout.isTelevision(context)) {
        accepted =
            await showDialog<String>(
              context: context,
              builder: (_) => TelevisionActionDialog(
                title: '关闭绿色模式？',
                options: [
                  TelevisionAction(
                    value: 'disable',
                    label: '关闭绿色模式',
                    description: summary,
                    icon: Icons.visibility_off_outlined,
                  ),
                ],
              ),
            ) ==
            'disable';
      } else {
        accepted =
            await showDialog<bool>(
              context: context,
              builder: (context) => _SettingsGlassConfirmation(
                title: const Text('关闭绿色模式？'),
                content: const Text(summary),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (!accepted || !mounted) return;
    }
    await saveUserChange(
      context,
      () => widget.store.setGreenMode(!widget.store.greenMode),
    );
  }

  List<
    ({
      String id,
      IconData icon,
      String title,
      String subtitle,
      VoidCallback? onPressed,
    })
  >
  _televisionEntries() => [
    (
      id: 'watch-stats',
      icon: Icons.bar_chart_rounded,
      title: '观看统计',
      subtitle: '实际观看时长、看完集数与最近 7 天',
      onPressed: _showWatchStats,
    ),
    (
      id: 'lan',
      icon: Icons.devices_rounded,
      title: '设备互联',
      subtitle: '局域网自动同步追剧与推送播放',
      onPressed: () => openLanSync(context),
    ),
    if (widget.repository.supportsSourceManagement)
      (
        id: 'sources',
        icon: Icons.dns_outlined,
        title: '站源管理',
        subtitle: '独立更新、连接与播放检测',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SourcesScreen(
              repository: widget.repository,
              store: widget.store,
            ),
          ),
        ),
      ),
    (
      id: 'theme',
      icon: Icons.palette_outlined,
      title: '外观主题',
      subtitle: AppTheme.label(widget.store.themeMode),
      onPressed: _chooseTheme,
    ),
    (
      id: 'profiles',
      icon: Icons.people_outline,
      title: '用户管理',
      subtitle: '当前：${widget.store.profile.name}',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProfilesScreen(store: widget.store),
        ),
      ),
    ),
    if (widget.store.canDownload)
      (
        id: 'playback-preferences',
        icon: Icons.play_circle_outline,
        title: '播放设置',
        subtitle: '长按倍速、默认倍速、连播、弹幕与清晰度',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => PlaybackSettingsScreen(store: widget.store),
          ),
        ),
      ),
    if (widget.store.canDownload)
      (
        id: 'download-preferences',
        icon: Icons.download_outlined,
        title: '下载偏好',
        subtitle: widget.store.downloadPreferences.qualityLabel,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DownloadPreferencesScreen(store: widget.store),
          ),
        ),
      ),
    if (widget.store.canDownload)
      (
        id: 'storage',
        icon: Icons.folder_outlined,
        title: '下载目录与空间',
        subtitle: '查看存储用量、迁移已下载文件',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => StorageScreen(
              repository: widget.repository,
              store: widget.store,
            ),
          ),
        ),
      ),
    if (widget.store.profile.admin) ...[
      (
        id: 'resources',
        icon: Icons.settings_ethernet_rounded,
        title: '网络与资源',
        subtitle: '代理、目录请求间隔、下载并发与站源目录',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ResourceSettingsScreen(
              repository: widget.repository,
              store: widget.store,
            ),
          ),
        ),
      ),
      if (widget.store.fullMode)
        (
          id: 'green-mode',
          icon: Icons.verified_user_outlined,
          title: '分级限制',
          subtitle: widget.store.greenMode
              ? '已开启 · 不显示成人点播与成人直播'
              : '已关闭 · 显示成人点播与成人直播',
          onPressed: _busy ? null : _toggleGreenMode,
        ),
      (
        id: 'backup',
        icon: Icons.backup_outlined,
        title: '导出配置备份',
        subtitle: '包含本地用户、追剧、历史和设置，不含视频文件',
        onPressed: _busy ? null : () => _backup(false),
      ),
      (
        id: 'restore',
        icon: Icons.restore,
        title: '恢复配置备份',
        subtitle: '从备份文件恢复用户与设置',
        onPressed: _busy ? null : () => _backup(true),
      ),
      (
        id: 'library-export',
        icon: Icons.menu_book_outlined,
        title: '导出剧库',
        subtitle: '与「果果剧库」互相导入，只含剧库条目',
        onPressed: _busy ? null : () => _libraryTransfer(false),
      ),
      (
        id: 'library-import',
        icon: Icons.library_add_outlined,
        title: '导入剧库',
        subtitle: '按剧集 ID 合并补全，不删除本地条目',
        onPressed: _busy ? null : () => _libraryTransfer(true),
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('设置与备份')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: AppLayout.isTelevision(context)
              ? Builder(
                  builder: (_) {
                    final entries = _televisionEntries();
                    return RemoteList(
                      key: _listKey,
                      itemKeys: [for (final entry in entries) entry.id],
                      itemExtent: RemoteListTile.extent,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      autofocus: true,
                      itemBuilder: (_, index, node, onFocus) => RemoteListTile(
                        title: entries[index].title,
                        subtitle: entries[index].subtitle,
                        leading: Icon(entries[index].icon, size: 26),
                        focusNode: node,
                        onFocus: onFocus,
                        onPressed: entries[index].onPressed,
                      ),
                    );
                  },
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + _systemInset(context),
                  ),
                  children: [
                    ListTile(
                      key: const ValueKey('lan-settings'),
                      leading: const Icon(Icons.devices_rounded),
                      title: const Text('设备互联'),
                      subtitle: const Text('局域网自动同步追剧与推送播放'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openLanSync(context),
                    ),
                    if (widget.repository.supportsSourceManagement)
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('站源管理'),
                        subtitle: const Text('独立更新、连接与播放检测'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => SourcesScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        ),
                      ),
                    ListTile(
                      key: const ValueKey('watch-stats-setting'),
                      leading: const Icon(Icons.bar_chart_rounded),
                      title: const Text('观看统计'),
                      subtitle: const Text('实际观看时长、看完集数与最近 7 天'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _showWatchStats,
                    ),
                    ListTile(
                      key: const ValueKey('theme-setting'),
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('外观主题'),
                      subtitle: Text(AppTheme.label(widget.store.themeMode)),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        key: _themeAnchor,
                      ),
                      onTap: _chooseTheme,
                    ),
                    ListTile(
                      key: const ValueKey('interface-style-setting'),
                      leading: const Icon(Icons.blur_on_outlined),
                      title: const Text('界面风格'),
                      subtitle: Text(
                        widget.store.interfaceStyle == 'glass'
                            ? '玻璃 · 悬浮玻璃底栏、菜单与回到顶部按钮'
                            : '标准 · 经典底部导航',
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        key: _styleAnchor,
                      ),
                      onTap: _chooseInterfaceStyle,
                    ),
                    if (widget.store.fullMode)
                      ListTile(
                        key: const ValueKey('green-mode-setting'),
                        leading: const Icon(Icons.verified_user_outlined),
                        title: const Text('分级限制'),
                        subtitle: Text(
                          widget.store.greenMode
                              ? '已开启 · 不显示成人点播与成人直播'
                              : '已关闭 · 显示成人点播与成人直播',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _busy ? null : _toggleGreenMode,
                      ),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('用户管理'),
                      subtitle: Text('当前：${widget.store.profile.name}'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ProfilesScreen(store: widget.store),
                        ),
                      ),
                    ),
                    if (widget.store.canDownload)
                      ListTile(
                        key: const ValueKey('playback-settings-entry'),
                        leading: const Icon(Icons.play_circle_outline),
                        title: const Text('播放设置'),
                        subtitle: Text(
                          '长按倍速 ${speedLabel(widget.store.playbackPreferences.holdSpeed)}x · '
                          '滑动快进 ${widget.store.playbackPreferences.swipeSeekSeconds} 秒',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PlaybackSettingsScreen(store: widget.store),
                          ),
                        ),
                      ),
                    if (widget.store.canDownload)
                      ListTile(
                        leading: const Icon(Icons.download_outlined),
                        title: const Text('下载偏好'),
                        subtitle: Text(
                          widget.store.downloadPreferences.qualityLabel,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                DownloadPreferencesScreen(store: widget.store),
                          ),
                        ),
                      ),
                    if (widget.store.canDownload)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('下载目录与空间'),
                        subtitle: const Text('查看存储用量、迁移已下载文件'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => StorageScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        ),
                      ),
                    if (widget.store.profile.admin) ...[
                      ListTile(
                        leading: const Icon(Icons.settings_ethernet_rounded),
                        title: const Text('网络与资源'),
                        subtitle: const Text('代理、目录请求间隔、下载并发与站源目录'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ResourceSettingsScreen(
                              repository: widget.repository,
                              store: widget.store,
                            ),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: const Text('导出配置备份'),
                        subtitle: const Text('包含本地用户、追剧、历史和设置，不含视频文件'),
                        onTap: _busy ? null : () => _backup(false),
                      ),
                      ListTile(
                        leading: const Icon(Icons.restore),
                        title: const Text('恢复配置备份'),
                        onTap: _busy ? null : () => _backup(true),
                      ),
                      ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: const Text('导出剧库'),
                        subtitle: const Text('与「果果剧库」互相导入，只含剧库条目'),
                        onTap: _busy ? null : () => _libraryTransfer(false),
                      ),
                      ListTile(
                        leading: const Icon(Icons.library_add_outlined),
                        title: const Text('导入剧库'),
                        subtitle: const Text('按剧集 ID 合并补全，不删除本地条目'),
                        onTap: _busy ? null : () => _libraryTransfer(true),
                      ),
                    ],
                    if (Platform.isIOS)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('iOS 下载和媒体处理需要保持应用在前台；切到后台会暂停，回到前台后可继续。'),
                      ),
                    if (_busy) const LinearProgressIndicator(),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(_message!),
                      ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _info;
  String? _error;
  bool _busy = false;
  bool _access = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _loadAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAccess();
  }

  Future<void> _loadAccess() async {
    final access = await hasAllFilesAccess();
    if (mounted && access != _access) setState(() => _access = access);
  }

  Future<void> _refresh() async {
    try {
      final info = await widget.repository.storage();
      if (mounted) {
        setState(() {
          _info = info;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _move() async {
    String? parent;
    if (Platform.isAndroid || Platform.isIOS) {
      final support = await getApplicationSupportDirectory();
      final directories = <String, String>{support.path: '应用内部存储'};
      if (Platform.isAndroid) {
        final external = await getExternalStorageDirectories() ?? [];
        for (var i = 0; i < external.length; i++) {
          directories[external[i].path] = i == 0
              ? '设备共享存储（应用目录）'
              : 'SD 卡 ${i + 1}（应用目录）';
        }
      } else {
        final documents = await getApplicationDocumentsDirectory();
        directories[documents.path] = '文件 App 可见目录';
      }
      if (!mounted) return;
      parent = await showDialog<String>(
        context: context,
        builder: (context) => GlassDialog(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('选择下载位置', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                for (final entry in directories.entries)
                  ListTile(
                    title: Text(entry.value),
                    leading: const Icon(Icons.folder_outlined),
                    onTap: () => Navigator.pop(context, entry.key),
                  ),
              ],
            ),
          ),
        ),
      );
    } else {
      parent = await FilePicker.getDirectoryPath(dialogTitle: '选择下载保存位置');
    }
    if (parent == null || !mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => _SettingsGlassConfirmation(
        title: const Text('迁移已下载内容？'),
        content: Text(
          '将视频、合并成品及导出内容迁移到：\n$parent\n\n下载会先暂停，复制成功后清理旧目录。请保证目标有足够空间，并在完成后继续下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.moveDownloads(parent);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickExportDirectory() async {
    if (_busy) return;
    final directory = await FilePicker.getDirectoryPath(dialogTitle: '选择导出目录');
    if (directory == null || !mounted) return;
    try {
      await widget.store.setExportDirectory(directory);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return;
    }
    if (mounted) setState(() {});
    if (!await hasAllFilesAccess()) await ensureStorageAccess(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('下载目录与空间')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_info != null) ...[
                Text(
                  '已使用 ${storageSize((_info!['bytes'] as num?)?.toInt() ?? 0)}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '剩余 ${storageSize((_info!['free'] as num?)?.toInt() ?? -1)} · ${_info!['files'] ?? 0} 个文件',
                ),
                const SizedBox(height: 24),
                const Text('当前下载目录'),
                const SizedBox(height: 8),
                SelectableText(_info!['directory'] as String? ?? ''),
                TextButton.icon(
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: _info!['directory'] as String? ?? ''),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制路径'),
                ),
                const SizedBox(height: 20),
                const Text('在下载页删除不需要的分集，在本地媒体页删除合并成品或 Emby 导出，可释放空间。'),
              ],
              if (_busy || (_info == null && _error == null))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: LinearProgressIndicator(),
                ),
              if (_busy) const Text('正在迁移，请保持应用运行…'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_error!),
                ),
              const Divider(height: 40),
              ListTile(
                title: const Text('导出目录'),
                subtitle: Text(
                  widget.store.exportDirectory.isEmpty
                      ? '未设置 · 导出时选择并记住'
                      : widget.store.exportDirectory,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : _pickExportDirectory,
              ),
              if (Platform.isAndroid) ...[
                const Divider(),
                ListTile(
                  title: const Text('所有文件访问权限'),
                  subtitle: Text(
                    _access ? '已授权 · 可导出到应用目录外的文件夹' : '未授权 · 导出到应用目录外需要授权',
                  ),
                  trailing: _access
                      ? const Icon(Icons.verified_outlined)
                      : const Text('去授权'),
                  onTap: _access
                      ? null
                      : () async {
                          await ensureStorageAccess(context);
                          await _loadAccess();
                        },
                ),
              ],
              if (widget.store.profile.admin)
                FilledButton.icon(
                  onPressed: _busy ? null : _move,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('更改并迁移目录'),
                ),
              TextButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('刷新用量'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SettingsGlassConfirmation extends StatelessWidget {
  const _SettingsGlassConfirmation({
    required this.title,
    required this.content,
    required this.actions,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => GlassDialog(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefaultTextStyle.merge(
            style: Theme.of(context).textTheme.titleLarge,
            child: title,
          ),
          const SizedBox(height: 16),
          content,
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ],
      ),
    ),
  );
}
