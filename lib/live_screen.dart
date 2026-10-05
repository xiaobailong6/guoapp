import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_layout.dart';
import 'live_models.dart';
import 'live_playback.dart';
import 'live_player_screen.dart';
import 'live_repository.dart';
import 'live_sources.dart';
import 'live_store.dart';
import 'player_route.dart';
import 'remote_widgets.dart';
import 'widgets.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({
    super.key,
    required this.repository,
    required this.store,
    this.onExitLeft,
  });

  final LiveRepository repository;
  final LiveStore store;
  final VoidCallback? onExitLeft;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const _favouritesId = '__favourites';
  static const _playbackShare = 9;
  static const _listShare = 14;

  LiveSource _source = LiveSource.values.first;
  List<LivePlatform> _platforms = const [];
  List<LiveChannel> _channels = const [];
  String _group = '';
  ({String group, List<LiveChannel> channels})? _lastGood;
  bool _loading = true;
  bool _detached = false;
  bool _more = false;
  bool _hasMore = false;
  String? _error;
  int _page = 1;
  int _generation = 0;
  late final LivePlaybackController _playback;
  final _listKey = GlobalKey<RemoteListState>();
  final _groupScroll = ScrollController();
  final _channelScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _playback = LivePlaybackController(repository: widget.repository)
      ..addListener(_playbackChanged);
    widget.store.addListener(_storeChanged);
    _loadPlatforms();
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    _playback.removeListener(_playbackChanged);
    _playback.dispose();
    _groupScroll.dispose();
    _channelScroll.dispose();
    super.dispose();
  }

  void _playbackChanged() {
    if (mounted) setState(() {});
  }

  void _storeChanged() {
    if (!mounted) return;
    // 只同步列表内容，不重建播放，否则刚点开的频道会被重置回第一条。
    setState(() {
      if (_group == _favouritesId) _channels = widget.store.favourites;
    });
  }

  List<({String id, String name, int count})> get _entries => [
    (id: _favouritesId, name: '收藏', count: widget.store.favourites.length),
    for (final platform in _platforms)
      (id: platform.id, name: platform.name, count: platform.count),
  ];

  String get _groupName =>
      _entries
          .where((entry) => entry.id == _group)
          .map((entry) => entry.name)
          .firstOrNull ??
      '直播';

  void _applyChannels(List<LiveChannel> channels) {
    _channels = channels;
    unawaited(_playback.load(_source, channels, autoplay: channels.isNotEmpty));
  }

  Future<void> _loadPlatforms() async {
    final token = ++_generation;
    widget.repository.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _platforms = const [];
      _channels = const [];
      _group = '';
      _lastGood = null;
      _page = 1;
    });
    try {
      final platforms = await widget.repository.platforms(_source);
      if (!mounted || token != _generation) return;
      setState(() {
        _platforms = platforms;
        _loading = false;
      });
      if (platforms.isNotEmpty) await _loadChannels(platforms.first.id);
    } catch (error) {
      if (!mounted || token != _generation) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _loadChannels(String id, {bool append = false}) async {
    if (id == _favouritesId) {
      final channels = widget.store.favourites;
      _lastGood = (group: id, channels: channels);
      // 切到收藏只换列表，不打断正在播放的频道。
      setState(() {
        _group = id;
        _channels = channels;
        _error = null;
        _loading = false;
        _more = false;
        _hasMore = false;
      });
      return;
    }
    final platform = _platforms.where((entry) => entry.id == id).firstOrNull;
    if (platform == null) return;
    if (append && !_hasMore) return;
    if (!append && id == _group) return;
    if (!append) _lastGood = (group: _group, channels: _channels);
    final page = append ? _page + 1 : 1;
    setState(() {
      _group = id;
      _error = null;
      _more = append;
      if (!append) {
        _loading = true;
        _hasMore = false;
        _channels = const [];
      }
    });
    final token = _generation;
    try {
      final channels = await widget.repository.channels(
        _source,
        platform,
        page: page,
      );
      if (!mounted || token != _generation) return;
      if (!append) _lastGood = (group: id, channels: channels);
      setState(() {
        _page = page;
        _loading = false;
        _more = false;
        _hasMore = _source.paginated && channels.length >= 24;
        _applyChannels(
          append && !_playback.ready
              ? [..._channels, ...channels]
              : append
              ? [..._playback.channels, ...channels]
              : channels,
        );
      });
    } catch (error) {
      if (!mounted || token != _generation) return;
      final restore = _lastGood;
      final fallback =
          !append && restore != null && restore.channels.isNotEmpty;
      setState(() {
        _loading = false;
        _more = false;
        if (fallback) {
          _group = restore.group;
          _channels = restore.channels;
          _error = null;
        } else {
          _error = '$error';
        }
      });
      if (fallback && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('${platform.name} 暂时不可用，已保留原分类')),
        );
      }
    }
  }

  void _changeSource(LiveSource source) {
    if (source.id == _source.id) return;
    setState(() => _source = source);
    _loadPlatforms();
  }

  void _open(LiveChannel channel) {
    final index = _playback.channels.indexWhere(
      (entry) => entry.key == channel.key,
    );
    if (index >= 0) {
      unawaited(_playback.play(index));
      return;
    }
    final local = _channels.indexWhere((entry) => entry.key == channel.key);
    if (local < 0) return;
    unawaited(_playback.load(_source, _channels, index: local));
  }

  Future<void> _openFullscreen() async {
    if (_playback.channel == null || _playback.channels.isEmpty) return;
    setState(() => _detached = true);
    await Navigator.push<void>(
      context,
      playerRoute(
        LivePlayerScreen(
          playback: _playback,
          source: _source,
          store: widget.store,
          onExit: () => setState(() => _detached = false),
        ),
      ),
    );
    if (mounted) setState(() => _detached = false);
  }

  void _pickSource() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '直播源',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final source in LiveSource.values)
              ListTile(
                key: ValueKey('live-source-${source.id}'),
                leading: Icon(
                  source.id == _source.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: source.id == _source.id
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(source.name),
                subtitle: Text(source.description),
                onTap: () {
                  Navigator.pop(context);
                  _changeSource(source);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final television = AppLayout.isTelevision(context);
    return Column(
      children: [
        Expanded(flex: _playbackShare, child: _video(context, television)),
        Expanded(flex: _listShare, child: _panel(context, television)),
      ],
    );
  }

  Widget _video(BuildContext context, bool television) {
    final controller = _playback.controller;
    final error = _playback.error;
    return ColoredBox(
      key: const ValueKey('live-stage'),
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && !_detached)
            Video(
              controller: controller,
              fit: BoxFit.contain,
              wakelock: false,
              controls: (_) => const SizedBox.shrink(),
            )
          else if (!_detached)
            const Center(
              child: Text(
                '选择频道开始播放',
                style: TextStyle(color: Color(0xFF8B8F99), fontSize: 13),
              ),
            ),
          if (error == null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openFullscreen,
                onDoubleTap: () => unawaited(_playback.retry()),
                child: const SizedBox.expand(),
              ),
            ),
          if (error != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .82),
                child: StatusPanel(
                  title: '直播暂时中断',
                  message: error,
                  icon: Icons.wifi_off_rounded,
                  action: '重新连接',
                  onRetry: () => unawaited(_playback.retry()),
                ),
              ),
            )
          else if (_playback.loading || _playback.buffering)
            const Center(
              child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          if (_playback.channel != null && error == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _nowPlaying(context),
            ),
          if (television)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _groupName,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nowPlaying(BuildContext context) {
    final channel = _playback.channel!;
    final favourite = widget.store.isFavourite(channel.key);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xB3000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 4, 4),
        child: Row(
          children: [
            Text(
              channel.number,
              style: const TextStyle(
                color: Color(0xB3FFFFFF),
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              channel.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (channel.subtitle.isNotEmpty) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channel.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 12,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            if (channel.urls.length > 1)
              Text(
                '线路 ${channel.urls.length}',
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: favourite ? '取消收藏' : '收藏频道',
              onPressed: () => widget.store.toggleFavourite(channel),
              icon: Icon(
                favourite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 20,
                color: favourite ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, bool television) => Column(
    children: [
      _current(context),
      Expanded(child: _lists(context, television)),
    ],
  );

  Widget _current(BuildContext context) {
    final theme = Theme.of(context);
    final channel = _playback.channel;
    final logo = channel?.logo ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 86,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 58,
                  height: 58,
                  child: logo.isEmpty
                      ? _logoFallback(theme)
                      : Image.network(
                          logo,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => _logoFallback(theme),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        channel?.name ?? _groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _caption(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: IconButton(
                    key: const ValueKey('live-source-button'),
                    tooltip: '切换直播源',
                    onPressed: _pickSource,
                    icon: const Icon(Icons.tv_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _caption() {
    if (_loading) return '载入中…';
    final channel = _playback.channel;
    if (channel == null) return '${_source.name} · 选择一个频道';
    return '${_source.name} · ${channel.group} · '
        '${_playback.index + 1}/${_playback.count}';
  }

  Widget _logoFallback(ThemeData theme) => Container(
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Text(
      'TV',
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _lists(BuildContext context, bool television) {
    final error = _error;
    if (_platforms.isEmpty && error != null && !_loading) {
      return StatusPanel(
        title: '${_source.name} 直播源暂时不可用',
        message: error,
        icon: Icons.wifi_off_rounded,
        onRetry: _loadPlatforms,
      );
    }
    final entries = _entries;
    if (entries.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return StatusPanel(
        title: '没有可用分类',
        message: '可以切换其他直播源。',
        icon: Icons.live_tv_rounded,
      );
    }
    if (television) {
      return RemoteList(
        key: _listKey,
        itemKeys: [for (final entry in entries) entry.id],
        itemExtent: RemoteListTile.extent,
        onExitUp: null,
        onExitLeft: widget.onExitLeft,
        itemBuilder: (_, index, node, onFocus) => RemoteListTile(
          key: ValueKey('live-group-${entries[index].id}'),
          title: entries[index].name,
          subtitle: entries[index].count > 0
              ? '${entries[index].count} 个频道'
              : '',
          selected: entries[index].id == _group,
          focusNode: node,
          onFocus: onFocus,
          onPressed: () => _loadChannels(entries[index].id),
        ),
      );
    }
    return Row(
      children: [
        Expanded(flex: 31, child: _groupRail(context, entries)),
        Expanded(flex: 57, child: _channelPane(context)),
      ],
    );
  }

  Widget _channelPane(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null && _channels.isEmpty) {
      return StatusPanel(
        title: '这个分类暂时不可用',
        message: error,
        icon: Icons.wifi_off_rounded,
        onRetry: () => _loadChannels(_group),
      );
    }
    return _channelList(context);
  }

  Widget _groupRail(
    BuildContext context,
    List<({String id, String name, int count})> entries,
  ) {
    final theme = Theme.of(context);
    return Scrollbar(
      controller: _groupScroll,
      child: ListView.builder(
        key: const ValueKey('live-group-rail'),
        controller: _groupScroll,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final selected = entry.id == _group;
          return InkWell(
            key: ValueKey('live-group-${entry.id}'),
            onTap: () => _loadChannels(entry.id),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 2, 6, 2),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                entry.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _channelList(BuildContext context) {
    final theme = Theme.of(context);
    if (_channels.isEmpty) {
      return StatusPanel(
        title: _group == _favouritesId ? '还没有收藏频道' : '没有可用频道',
        message: _group == _favouritesId ? '播放时点星标即可加入收藏。' : '可以切换其他分类或直播源。',
        icon: Icons.live_tv_rounded,
      );
    }
    final current = _playback.channel?.key;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 600 &&
            !_more &&
            _hasMore &&
            _group != _favouritesId) {
          unawaited(_loadChannels(_group, append: true));
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('live-channel-list'),
        controller: _channelScroll,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _channels.length + (_more ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _channels.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final channel = _channels[index];
          final selected = channel.key == current;
          return InkWell(
            key: ValueKey('live-channel-${channel.key}'),
            onTap: () => _open(channel),
            child: Container(
              margin: const EdgeInsets.fromLTRB(6, 2, 12, 2),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      channel.number,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: selected
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? theme.colorScheme.onSecondaryContainer
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
