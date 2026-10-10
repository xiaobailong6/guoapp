import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_notice.dart';
import 'core_bridge.dart';
import 'glass_panel.dart';
import 'local_store.dart';
import 'models.dart';
import 'remote_widgets.dart';
import 'source_status.dart';

String sourceTimestamp(DateTime? value) {
  if (value == null) return '尚无记录';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
}

/// 有界、可滚动的诊断文本：上游偶发超长信息时不会把卡片撑到整屏。
class SourceMessage extends StatelessWidget {
  const SourceMessage({
    super.key,
    required this.text,
    required this.color,
    this.maxHeight = 160,
  });

  final String text;
  final Color color;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxHeight),
    child: SingleChildScrollView(
      child: SelectableText(text, style: TextStyle(color: color)),
    ),
  );
}

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({
    super.key,
    required this.repository,
    required this.store,
    this.initialSource,
    this.drama,
  });

  final AppRepository repository;
  final LocalStore store;
  final String? initialSource;
  final Drama? drama;

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  final _statuses = <String, SourceStatus>{};
  final _errors = <String, String>{};
  final _pending = <String>{};
  final _revisions = <String, int>{};
  final _expandedHealth = <String>{};
  Timer? _timer;
  bool _polling = false;
  bool _cooling = false;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    ensureTelevisionFocus(context);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _ticks++;
      final cooling = _statuses.values.any((status) => status.retrySeconds > 0);
      if (cooling || _cooling) setState(() {});
      _cooling = cooling;
      if (_ticks % 2 == 0 &&
          (_statuses.values.any((status) => status.running) ||
              _ticks % 10 == 0)) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_polling) return;
    _polling = true;
    final epoch = widget.store.profileEpoch;
    final sources = widget.store.sources.map((source) => source.id).toList();
    final revisions = {
      for (final source in sources) source: _revisions[source] ?? 0,
    };
    var changed = false;
    try {
      final statuses = await widget.repository.sourceStatuses(sources);
      if (!mounted || epoch != widget.store.profileEpoch) return;
      for (final source in sources) {
        if (revisions[source] != (_revisions[source] ?? 0)) continue;
        final status = statuses[source];
        if (status == null) continue;
        if (!_statuses.containsKey(source) ||
            !status.sameAs(_statuses[source]!) ||
            _errors.containsKey(source)) {
          _statuses[source] = status;
          _errors.remove(source);
          changed = true;
        }
      }
      if (changed) setState(() {});
    } catch (error) {
      if (!mounted || epoch != widget.store.profileEpoch) return;
      final message = error.toString();
      for (final source in sources) {
        if (revisions[source] == (_revisions[source] ?? 0) &&
            _errors[source] != message) {
          _errors[source] = message;
          changed = true;
        }
      }
      if (changed) setState(() {});
    } finally {
      _polling = false;
    }
  }

  Future<void> _run(SourceSite source, String operation) async {
    if (_pending.contains(source.id)) return;
    final epoch = widget.store.profileEpoch;
    setState(() {
      _pending.add(source.id);
      _errors.remove(source.id);
      _revisions[source.id] = (_revisions[source.id] ?? 0) + 1;
      if (operation == 'check' || operation == 'checkCatalog') {
        _expandedHealth.add(source.id);
      }
    });
    try {
      final status = operation == 'cancel'
          ? await widget.repository.cancelSourceJob(source.id)
          : await widget.repository.startSourceJob(
              source.id,
              operation,
              drama: source.id == widget.drama?.source ? widget.drama : null,
            );
      if (mounted && epoch == widget.store.profileEpoch) {
        setState(() => _statuses[source.id] = status);
      }
    } catch (error) {
      if (mounted && epoch == widget.store.profileEpoch) {
        setState(() => _errors[source.id] = error.toString());
      }
    } finally {
      if (mounted) setState(() => _pending.remove(source.id));
    }
  }

  Future<void> _copy(SourceSite source, SourceStatus status) async {
    final text = StringBuffer('${source.name}\n');
    text.writeln(
      '缓存 ${status.count} 部，更新 ${sourceTimestamp(status.updatedAt)}',
    );
    final health = status.health;
    if (health != null) {
      text.writeln('${health.label} · ${sourceTimestamp(health.checkedAt)}');
      if (health.sample.isNotEmpty) text.writeln('检测剧集：${health.sample}');
      for (final step in health.steps) {
        text.writeln('${step.name}：${step.message}');
        text.writeln(
          '${step.host} HTTP ${step.httpStatus} · ${step.elapsedMs} ms',
        );
        if (step.cfRay.isNotEmpty) text.writeln('CF Ray: ${step.cfRay}');
      }
    }
    if (status.error.isNotEmpty) text.writeln(status.error);
    if (status.storageError.isNotEmpty) text.writeln(status.storageError);
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (mounted) {
      AppNotice.show(context, '诊断信息已复制');
    }
  }

  Future<void> _updateAll() async {
    if (!widget.repository.supportsSourceManagement) return;
    final targets = <SourceSite>[];
    for (final source in widget.store.sources) {
      final status = _statuses[source.id];
      final busy = _pending.contains(source.id) || status?.running == true;
      final seconds = status?.retrySeconds ?? 0;
      if (!busy && seconds == 0) targets.add(source);
    }
    if (targets.isEmpty) {
      if (mounted) {
        AppNotice.show(context, '站源都在更新或冷却中，请稍候');
      }
      return;
    }
    for (final source in targets) {
      unawaited(_run(source, 'update'));
    }
    if (mounted) {
      AppNotice.show(context, '已开始更新 ${targets.length} 个站源');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final sources = widget.store.sources.toList()
        ..sort((a, b) {
          final aFirst = a.id == widget.initialSource ? 0 : 1;
          final bFirst = b.id == widget.initialSource ? 0 : 1;
          return aFirst.compareTo(bFirst);
        });
      final orderedSources = [
        for (final group in SourceGroup.fromSources(sources)) ...group.sources,
      ];
      final viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
      final paddingBottom = MediaQuery.paddingOf(context).bottom;
      final bottomInset = viewPaddingBottom > paddingBottom
          ? viewPaddingBottom
          : paddingBottom;
      return Scaffold(
        appBar: AppBar(
          title: const Text('站源管理'),
          actions: [
            if (widget.store.sources.isNotEmpty)
              IconButton(
                key: const ValueKey('update-all-sources'),
                tooltip: '更新全部站源',
                onPressed: widget.repository.supportsSourceManagement
                    ? _updateAll
                    : null,
                icon: const Icon(Icons.sync_rounded),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView.builder(
              key: const PageStorageKey('source-management-list'),
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              itemCount: orderedSources.isEmpty ? 2 : orderedSources.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      '各站源可分别更新和检测。更新会查找新剧、继续加载历史分页，并分批补齐资料；离开此页后任务继续。',
                    ),
                  );
                }
                if (orderedSources.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('当前用户没有可用站源'),
                  );
                }
                final source = orderedSources[index - 1];
                return FocusTraversalGroup(
                  key: ValueKey('source-focus-${source.id}'),
                  child: _sourceCard(source),
                );
              },
            ),
          ),
        ),
      );
    },
  );

  Widget _sourceCard(SourceSite source) {
    final status = _statuses[source.id];
    final pending = _pending.contains(source.id);
    final busy = pending || status?.running == true;
    final seconds = status?.retrySeconds ?? 0;
    final enabled =
        !busy && seconds == 0 && widget.repository.supportsSourceManagement;
    final error = _errors[source.id] ?? status?.error ?? '';
    final health = status?.health;
    final healthExpanded = _expandedHealth.contains(source.id);
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('source-${source.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dns_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    source.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  status == null
                      ? (_errors.containsKey(source.id) ? '读取失败' : '读取中')
                      : '${status.count} 部',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              status == null
                  ? '最近更新：读取中'
                  : '最近更新：${sourceTimestamp(status.updatedAt)}',
            ),
            if (status != null && status.count > 0)
              Text(
                '已加载至第 ${status.page} 页${status.hasMore ? ' · 可继续加载' : ' · 当前分页已加载完'}',
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: ValueKey('update-${source.id}'),
                  onPressed: enabled ? () => _run(source, 'update') : null,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('更新'),
                ),
                OutlinedButton.icon(
                  key: ValueKey('check-${source.id}'),
                  onPressed: enabled ? () => _run(source, 'check') : null,
                  icon: const Icon(Icons.network_check),
                  label: const Text('检测连接与播放'),
                ),
                if (status?.running == true)
                  TextButton(
                    onPressed: pending ? null : () => _run(source, 'cancel'),
                    child: const Text('停止'),
                  ),
                Builder(
                  builder: (anchorContext) => IconButton(
                    tooltip: '${source.name}更多操作',
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: !enabled
                        ? null
                        : () async {
                            final anchor = glassMenuAnchor(anchorContext);
                            if (anchor == null) return;
                            final epoch = widget.store.profileEpoch;
                            final operation = await showGlassMenu<String>(
                              context: context,
                              anchor: anchor,
                              alignRight: true,
                              autofocusSelected: true,
                              width: 320,
                              entries: [
                                GlassMenuEntry(
                                  value: 'more',
                                  enabled: status?.hasMore ?? true,
                                  label: const Text('继续加载一页'),
                                  leading: const Icon(
                                    Icons.expand_more_rounded,
                                  ),
                                ),
                                const GlassMenuEntry(
                                  value: 'metadata',
                                  label: Text('补齐资料'),
                                  leading: Icon(Icons.description_outlined),
                                ),
                                if (source.id == 'huangdou')
                                  GlassMenuEntry(
                                    value: 'vipMetadata',
                                    enabled: (status?.unknownVip ?? 0) > 0,
                                    label: Text(
                                      '补齐 VIP 资料（${status?.unknownVip ?? 0} 部）',
                                    ),
                                    leading: const Icon(
                                      Icons.verified_outlined,
                                    ),
                                  ),
                                const GlassMenuEntry(
                                  value: 'checkCatalog',
                                  label: Text('仅检测目录'),
                                  leading: Icon(Icons.fact_check_outlined),
                                ),
                              ],
                            );
                            if (!mounted ||
                                epoch != widget.store.profileEpoch ||
                                operation == null ||
                                _pending.contains(source.id) ||
                                _statuses[source.id]?.running == true ||
                                (_statuses[source.id]?.retrySeconds ?? 0) > 0) {
                              return;
                            }
                            await _run(source, operation);
                          },
                  ),
                ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: status != null && status.total > 0
                    ? (status.completed / status.total).clamp(0, 1)
                    : null,
              ),
              const SizedBox(height: 8),
              Text(
                '${status?.stage ?? '准备中'}${(status?.total ?? 0) > 0 ? ' · ${status!.completed}/${status.total}' : ''}',
              ),
            ] else if (status != null && status.stage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${status.stage}${status.added > 0 ? ' · 新增 ${status.added} 部' : ''}',
              ),
            ],
            if (seconds > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '请在 $seconds 秒后重试',
                  style: TextStyle(color: colors.error),
                ),
              ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SourceMessage(text: error, color: colors.error),
              ),
            if (status != null && status.storageError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.storageError,
                      style: TextStyle(color: colors.error),
                    ),
                    TextButton.icon(
                      key: ValueKey('save-${source.id}'),
                      onPressed:
                          !busy && widget.repository.supportsSourceManagement
                          ? () => _run(source, 'retrySave')
                          : null,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('重试保存'),
                    ),
                  ],
                ),
              ),
            if (health != null) ...[
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      expanded: healthExpanded,
                      child: Tooltip(
                        message: healthExpanded ? '收起检测详情' : '展开检测详情',
                        child: TextButton(
                          key: ValueKey('health-toggle-${source.id}'),
                          onPressed: () => setState(() {
                            if (healthExpanded) {
                              _expandedHealth.remove(source.id);
                            } else {
                              _expandedHealth.add(source.id);
                            }
                          }),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.onSurface,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(health.label),
                                    Text(
                                      sourceTimestamp(health.checkedAt),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                healthExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制诊断信息',
                    onPressed: () => _copy(source, status!),
                    icon: const Icon(Icons.copy_rounded),
                  ),
                ],
              ),
              if (healthExpanded) ...[
                if (health.sample.isNotEmpty) Text('检测剧集：${health.sample}'),
                for (final step in health.steps)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          step.state == 'ok'
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 20,
                          color: step.state == 'ok'
                              ? colors.primary
                              : colors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${step.name}：${step.message}'),
                              if (step.host.isNotEmpty || step.httpStatus > 0)
                                Text(
                                  '${step.host}${step.httpStatus > 0 ? ' · HTTP ${step.httpStatus}' : ''} · ${step.elapsedMs} ms',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ] else ...[
              const SizedBox(height: 12),
              const Text('尚未检测连接'),
            ],
          ],
        ),
      ),
    );
  }
}

class SourceDiagnosticsButton extends StatelessWidget {
  const SourceDiagnosticsButton({
    super.key,
    required this.repository,
    required this.store,
    required this.drama,
  });
  final AppRepository repository;
  final LocalStore store;
  final Drama drama;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SourcesScreen(
          repository: repository,
          store: store,
          initialSource: drama.source,
          drama: drama,
        ),
      ),
    ),
    icon: const Icon(Icons.network_check),
    label: const Text('站源诊断'),
  );
}
