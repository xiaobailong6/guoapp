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

  Future<void> pump(
    WidgetTester tester,
    LiveRepository repository,
    LiveStore store, {
    bool greenMode = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveScreen(
            repository: repository,
            store: store,
            greenMode: greenMode,
          ),
        ),
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
      LiveSource.values.first.name,
      '秀果',
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

  testWidgets('绿色模式下直播整源隐藏并给出可操作空态', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store, greenMode: true);

    expect(
      find.byKey(const ValueKey('live-green-empty')),
      findsOneWidget,
      reason: '没有可见直播源时应给出空态，而不是在 .first 上抛异常',
    );
    expect(repository.sources, isEmpty, reason: '绿色模式下不应发起任何取源请求');
    await pump(tester, repository, store, greenMode: false);
    expect(find.byKey(const ValueKey('live-stage')), findsOneWidget);

    const adultOnly = LiveSource(
      id: 'adult-fixture',
      name: '成人源',
      description: '合成成人源',
      protocol: LiveProtocol.list,
      endpoints: ['https://adult.example/list.m3u'],
      adult: true,
    );
    expect(
      LiveSource.visible(true).map((source) => source.id),
      isNot(contains('adult-fixture')),
      reason: '整源标记为成人时绿色模式不展示',
    );
    expect(
      LiveSource.spreadWith(adultOnly, greenMode: false).map((s) => s.id),
      contains('adult-fixture'),
    );
    expect(LiveSource.visible(true), isEmpty, reason: '内置直播源是秀场面板，绿色模式下整体隐藏');
    expect(
      LiveSource.visible(false).map((source) => source.name),
      contains('秀果'),
      reason: '关闭绿色模式后直播源恢复可见',
    );

    expect(
      LiveSource.hidesCategory('卫视直播', greenMode: true),
      isFalse,
      reason: '只有公开电视直播分类在绿色模式下放行',
    );
    expect(
      LiveSource.hidesCategory('十八禁', greenMode: true),
      isTrue,
      reason: '秀场分类名以花名为主，白名单之外一律隐藏',
    );
    expect(
      LiveSource.hidesCategory('卡哇伊', greenMode: true),
      isTrue,
      reason: '卡哇伊是秀场分类，黑名单列不全，必须靠白名单挡住',
    );
    expect(LiveSource.hidesCategory('小黄书', greenMode: true), isTrue);
    expect(
      LiveSource.hidesCategory('十八禁', greenMode: false),
      isFalse,
      reason: '关闭绿色模式后不再过滤分类',
    );
  });

  testWidgets('分类栏只有收藏，没有最近入口', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    expect(
      find.byKey(const ValueKey('live-group-__favourites')),
      findsOneWidget,
    );
    expect(find.text('最近'), findsNothing);
  });

  testWidgets('切换分类载入对应频道', (tester) async {
    final (store, repository) = await create();
    await pump(tester, repository, store);

    expect(
      find.byKey(ValueKey('live-channel-${_channel('央视IPV4', 'CCTV1综合').key}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('live-group-satellite')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('live-channel-${_channel('卫视IPV4', '湖南卫视').key}')),
      findsOneWidget,
    );
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
