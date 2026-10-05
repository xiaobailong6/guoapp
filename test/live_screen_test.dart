import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/live_models.dart';
import 'package:duanju_app/live_repository.dart';
import 'package:duanju_app/live_screen.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:duanju_app/live_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 合成直播源：不联网，只验证界面与收藏交互。
class _FakeRepository extends LiveRepository {
  _FakeRepository({this.extraGroups = 0, this.failGroups = const {}});

  final int extraGroups;
  final Set<String> failGroups;
  final List<String> sources = [];
  int channelCalls = 0;

  @override
  Future<List<LivePlatform>> platforms(
    LiveSource source, {
    bool force = false,
  }) async {
    sources.add(source.id);
    return [
      const LivePlatform(id: 'cctv', name: '央视IPV4', count: 3),
      const LivePlatform(id: 'satellite', name: '卫视IPV4', count: 2),
      for (var index = 0; index < extraGroups; index++)
        LivePlatform(id: 'group$index', name: '分类$index', count: 1),
    ];
  }

  @override
  Future<List<LiveChannel>> channels(
    LiveSource source,
    LivePlatform platform, {
    int page = 1,
    bool force = false,
  }) async {
    channelCalls++;
    if (failGroups.contains(platform.id)) throw AppFailure('直播源返回 404');
    if (platform.id == 'satellite') {
      return [
        LiveChannel(
          key: LiveChannel.makeKey('xiuguo', platform.name, '湖南卫视'),
          name: '湖南卫视',
          urls: const ['http://a.example/hunan.m3u8'],
          number: '001',
          group: platform.name,
          source: 'xiuguo',
        ),
      ];
    }
    return [
      for (final (index, name) in ['CCTV1综合', 'CCTV2财经', 'CCTV3综艺'].indexed)
        LiveChannel(
          key: LiveChannel.makeKey('xiuguo', platform.name, name),
          name: name,
          urls: ['http://a.example/cctv${index + 1}.m3u8'],
          number: '00${index + 1}',
          group: platform.name,
          source: 'xiuguo',
        ),
    ];
  }

  @override
  Future<LivePlayback> playback(LiveSource source, LiveChannel channel) async =>
      LivePlayback(url: channel.urls.first);
}

class _FailingRepository extends LiveRepository {
  @override
  Future<List<LivePlatform>> platforms(
    LiveSource source, {
    bool force = false,
  }) async => throw AppFailure('直播源返回 500');
}

LiveChannel _channel(String group, String name) => LiveChannel(
  key: LiveChannel.makeKey('xiuguo', group, name),
  name: name,
  urls: const ['http://a.example/x.m3u8'],
  group: group,
  source: 'xiuguo',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(LiveStore, _FakeRepository)> create() async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData(const {});
    final store = LiveStore(await SharedPreferences.getInstance(), 'default')
      ..load();
    addTearDown(store.dispose);
    final repository = _FakeRepository();
    addTearDown(repository.dispose);
    return (store, repository);
  }

  Future<void> pump(WidgetTester tester, LiveRepository repository, LiveStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LiveScreen(repository: repository, store: store)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('播放器固定在顶部，频道列表位于其下方', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    final stage = find.byKey(const ValueKey('live-stage'));
    expect(stage, findsOneWidget);
    expect(tester.getRect(stage).top, 0);

    final group = find.byKey(const ValueKey('live-group-cctv'));
    expect(group, findsOneWidget);
    expect(
      tester.getRect(group).top,
      greaterThanOrEqualTo(tester.getRect(stage).bottom),
      reason: '分类与频道列表必须在播放器下方',
    );
  });

  testWidgets('内置直播源合并为单一入口，站源面板收在频道卡上', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    expect(
      LiveSource.values.length,
      1,
      reason: '两个面板是同一上游的镜像，已合并成一个直播源',
    );
    expect(repository.sources, [LiveSource.values.first.id]);
    expect(
      find.textContaining(LiveSource.values.first.name),
      findsWidgets,
      reason: '当前频道的说明行应展示直播源名称',
    );

    await tester.tap(find.byKey(const ValueKey('live-source-button')));
    await tester.pumpAndSettle();

    for (final source in LiveSource.values) {
      expect(
        find.byKey(ValueKey('live-source-${source.id}')),
        findsOneWidget,
        reason: '缺少直播源入口 ${source.name}',
      );
    }

    await tester.tap(
      find.byKey(ValueKey('live-source-${LiveSource.values.first.id}')),
    );
    await tester.pumpAndSettle();

    expect(repository.sources.last, LiveSource.values.first.id);
    expect(find.text('央视IPV4'), findsOneWidget);
  });

  testWidgets('分类栏只有收藏，没有最近入口', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    expect(find.byKey(const ValueKey('live-group-__favourites')), findsOneWidget);
    expect(find.text('最近'), findsNothing);
  });

  testWidgets('切换分类载入对应频道', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    expect(find.byKey(ValueKey('live-channel-${_channel('央视IPV4', 'CCTV1综合').key}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-group-satellite')));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('live-channel-${_channel('卫视IPV4', '湖南卫视').key}')), findsOneWidget);
    expect(
      find.byKey(ValueKey('live-channel-${_channel('央视IPV4', 'CCTV1综合').key}')),
      findsNothing,
    );
  });

  testWidgets('收藏的频道出现在收藏分类，点击后拿到该频道的播放计划', (tester) async {
    final (store, repository) = await create();
    final channel = _channel('央视IPV4', 'CCTV1综合');
    store.toggleFavourite(channel);
    await pump(tester, repository, store);

    expect(store.favourites.single.name, 'CCTV1综合');

    await tester.tap(find.byKey(const ValueKey('live-group-__favourites')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('live-channel-${channel.key}')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('live-channel-${channel.key}')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '点击收藏频道不应抛异常');
  });

  testWidgets('收藏分类里取消收藏只更新列表，不重新取源', (tester) async {
    final (store, repository) = await create();
    final channel = _channel('央视IPV4', 'CCTV1综合');
    store.toggleFavourite(channel);
    await pump(tester, repository, store);

    await tester.tap(find.byKey(const ValueKey('live-group-__favourites')));
    await tester.pumpAndSettle();
    final before = repository.channelCalls;

    store.toggleFavourite(channel);
    await tester.pumpAndSettle();

    expect(find.text('还没有收藏频道'), findsOneWidget);
    expect(repository.channelCalls, before);
  });

  testWidgets('播放引擎不可用时给出可见错误而不是崩溃', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    expect(find.text('直播暂时中断'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重新连接'), findsOneWidget);
  });

  testWidgets('空收藏给出提示而不是频道列表', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    await tester.tap(find.byKey(const ValueKey('live-group-__favourites')));
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏频道'), findsOneWidget);
  });

  testWidgets('直播源失败时显示可重试的错误面板', (tester) async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData(const {});
    final store = LiveStore(await SharedPreferences.getInstance(), 'default')
      ..load();
    addTearDown(store.dispose);
    final repository = _FailingRepository();
    addTearDown(repository.dispose);

    await pump(tester, repository, store);

    expect(
      find.text('${LiveSource.values.first.name} 直播源暂时不可用'),
      findsOneWidget,
    );
    expect(find.text('直播源返回 500'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
  });
}
