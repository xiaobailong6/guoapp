import 'package:flutter/material.dart';

import 'app_notice.dart';
import 'background_downloads.dart';
import 'core_bridge.dart';
import 'download_preferences.dart';
import 'glass_panel.dart';
import 'local_store.dart';
import 'resource_settings.dart';
import 'remote_widgets.dart';
import 'widgets.dart';

class DownloadPreferencesScreen extends StatefulWidget {
  const DownloadPreferencesScreen({super.key, required this.store});
  final LocalStore store;

  @override
  State<DownloadPreferencesScreen> createState() =>
      _DownloadPreferencesScreenState();
}

class _DownloadPreferencesScreenState extends State<DownloadPreferencesScreen> {
  bool _savingExport = false;

  Future<void> _setAutoExport(bool value) async {
    if (_savingExport || !widget.store.canDownload) return;
    final epoch = widget.store.profileEpoch;
    setState(() => _savingExport = true);
    try {
      await saveUserChange(context, () async {
        if (value) await BackgroundDownloads.ensureStarted();
        if (!mounted || widget.store.profileEpoch != epoch) {
          throw StateError('当前用户已变更，请重试');
        }
        await widget.store.setAutoExport(value);
      });
    } finally {
      if (mounted) setState(() => _savingExport = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final preferences = store.downloadPreferences;
      return Scaffold(
        appBar: AppBar(title: const Text('下载偏好')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ListTile(
                  title: const Text('默认画质'),
                  subtitle: const Text('指定画质不可用时，使用源站提供的可用版本。'),
                ),
                GlassChoiceField<int>(
                  value: preferences.quality,
                  label: '下载画质',
                  enabled: store.canDownload,
                  entries: [
                    for (final value in DownloadPreferences.qualities)
                      (value, value == 0 ? '自动 · 优先高清' : '${value}P'),
                  ],
                  onChanged: (value) => saveUserChange(
                    context,
                    () => store.setDownloadPreferences(
                      preferences.copyWith(quality: value),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: preferences.includeVip,
                  title: const Text('默认包含 VIP 集'),
                  subtitle: const Text('VIP 集可能仅提供试看内容；下载前仍可调整选择。'),
                  onChanged: !store.canDownload
                      ? null
                      : (value) => saveUserChange(
                          context,
                          () => store.setDownloadPreferences(
                            preferences.copyWith(includeVip: value),
                          ),
                        ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('画质与 VIP 偏好保存在当前用户中，应用于下载选集、批量下载和更新本剧。'),
                ),
                if (store.profile.admin) ...[
                  const Divider(),
                  SwitchListTile(
                    value: store.autoExport,
                    title: const Text('下载完成后自动导出 Emby'),
                    subtitle: const Text(
                      '在下载目录的 exports 中生成视频和海报 URL 元数据，可将该目录加入 Emby 媒体库。',
                    ),
                    onChanged: _savingExport || !store.canDownload
                        ? null
                        : _setAutoExport,
                  ),
                  SwitchListTile(
                    value: store.exportPosters,
                    title: const Text('同时导出海报文件'),
                    subtitle: const Text('默认只写海报 URL。源站海报需要解密或外部读取失败时可开启。'),
                    onChanged: _savingExport || !store.canDownload
                        ? null
                        : (value) => saveUserChange(
                            context,
                            () => store.setExportPosters(value),
                          ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('导出设置由管理员统一管理，应用于设备上的下载任务。'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ResourceSettingsScreen extends StatefulWidget {
  const ResourceSettingsScreen({
    super.key,
    required this.repository,
    required this.store,
  });
  final AppRepository repository;
  final LocalStore store;
  @override
  State<ResourceSettingsScreen> createState() => _ResourceSettingsScreenState();
}

class _ResourceSettingsScreenState extends State<ResourceSettingsScreen> {
  final _proxy = TextEditingController();
  late final int _epoch = widget.store.profileEpoch;
  ResourceSettings? _settings;
  String _mode = 'auto';
  int _catalog = 3, _interval = 250, _downloads = 2;
  bool _folders = false, _busy = false, _showProxy = false;
  String? _error;
  bool get _allowed =>
      widget.store.profileEpoch == _epoch &&
      !widget.store.locked &&
      widget.store.profile.admin;

  @override
  void initState() {
    super.initState();
    ensureTelevisionFocus(context);
    _load();
  }

  @override
  void dispose() {
    _proxy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.repository.resourceSettings();
      if (!mounted || !_allowed) return;
      setState(() {
        _settings = settings;
        _mode = settings.proxyMode;
        _proxy.text = settings.proxyUrl;
        _catalog = settings.catalogConcurrency;
        _interval = settings.catalogIntervalMs;
        _downloads = settings.downloadConcurrency;
        _folders = settings.downloadBySource;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    if (_busy || !_allowed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await widget.repository.saveResourceSettings(
        ResourceSettings(
          proxyMode: _mode,
          proxyUrl: _proxy.text.trim(),
          catalogConcurrency: _catalog,
          catalogIntervalMs: _interval,
          downloadConcurrency: _downloads,
          downloadBySource: _folders,
        ),
      );
      if (!mounted || !_allowed) return;
      setState(() => _settings = settings);
      AppNotice.show(context, '设置已保存，将用于后续请求和下载任务');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _count(String title, int value, ValueChanged<int> change) =>
      GlassChoiceField<int>(
        value: value,
        label: title,
        enabled: !_busy && _allowed,
        entries: [for (var i = 1; i <= 6; i++) (i, '$i')],
        onChanged: (value) {
          if (!mounted || _busy || !_allowed) return;
          setState(() => change(value));
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('网络与资源'),
      actions: [
        TextButton(
          onPressed: _busy || _settings == null || !_allowed ? null : _save,
          child: const Text('保存'),
        ),
      ],
    ),
    body: !_allowed
        ? const StatusPanel(title: '需要管理员权限', message: '请返回后切换管理员。')
        : _settings == null
        ? _error == null
              ? const Center(child: CircularProgressIndicator())
              : StatusPanel(title: '无法读取设置', message: _error!, onRetry: _load)
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_settings!.warning.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(_settings!.warning),
                    ),
                  GlassChoiceField<String>(
                    value: _mode,
                    label: '连接方式',
                    enabled: !_busy && _allowed,
                    entries: const [
                      ('auto', '自动'),
                      ('direct', '直连'),
                      ('manual', '手动代理'),
                    ],
                    onChanged: (value) {
                      if (!mounted || _busy || !_allowed) return;
                      setState(() => _mode = value);
                    },
                  ),
                  if (_mode == 'auto')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _settings!.systemProxyStatus.isEmpty
                            ? '使用系统静态代理；未配置时使用环境变量或直连。'
                            : _settings!.systemProxyStatus,
                      ),
                    ),
                  if (_mode == 'manual')
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        controller: _proxy,
                        obscureText: !_showProxy,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: '代理地址',
                          hintText: 'http://127.0.0.1:7890',
                          helperText: '支持 HTTP、HTTPS、SOCKS5；仅保存在本机，不进入配置备份。',
                          helperMaxLines: 3,
                          suffixIcon: IconButton(
                            tooltip: _showProxy ? '隐藏代理地址' : '显示代理地址',
                            onPressed: () =>
                                setState(() => _showProxy = !_showProxy),
                            icon: Icon(
                              _showProxy
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  _count('目录请求并发', _catalog, (value) => _catalog = value),
                  const SizedBox(height: 16),
                  Text('目录请求间隔 · $_interval 毫秒'),
                  Slider(
                    value: _interval.toDouble(),
                    min: 0,
                    max: 5000,
                    divisions: 100,
                    label: '$_interval 毫秒',
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _interval = value.round()),
                  ),
                  const SizedBox(height: 16),
                  _count('同时下载数量', _downloads, (value) => _downloads = value),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _folders,
                    title: const Text('按站源分类保存'),
                    subtitle: const Text('新任务放入各站源的子目录，已有下载继续使用原位置。'),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _folders = value),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
  );
}
