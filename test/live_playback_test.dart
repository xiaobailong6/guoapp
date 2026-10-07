import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/live_http.dart';
import 'package:duanju_app/live_models.dart';
import 'package:duanju_app/live_playback.dart';
import 'package:duanju_app/live_repository.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// 合成一个列表型站源：源站直连被拒，只有代理前缀可用。
const _listSource = LiveSource(
  id: 'fixture-list',
  name: '合成列表源',
  description: '合成用',
  protocol: LiveProtocol.list,
  endpoints: ['https://fixture.example/list.m3u'],
  proxies: ['https://p1.example/proxy/', 'https://p2.example/proxy/'],
  group: '主播',
);

const _m3u = '''
#EXTM3U
#EXTINF:-1 ,主播甲
https://stream.example/a.m3u8
#EXTINF:-1 ,主播乙
https://stream.example/b.m3u8
''';

class _FakeHttp extends LiveHttp {
  @override
  Future<String> get(
    String url, {
    Map<String, String> headers = const {},
  }) async => _m3u;
}

/// 按主机名模拟线路质量：列表页正常，命中 dead 前缀的线路取不到播放清单。
class _RankedHttp extends LiveHttp {
  _RankedHttp({
    this.dead = const <String>[],
    this.slow = const <String, Duration>{},
    this.offline = false,
  });

  final List<String> dead;
  final Map<String, Duration> slow;
  final bool offline;

  @override
  Future<String> get(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (url.endsWith('/list.m3u')) return _m3u;
    if (offline) throw AppFailure('直播源连接超时');
    for (final host in dead) {
      if (url.contains(host)) throw AppFailure('直播源返回 403');
    }
    for (final entry in slow.entries) {
      if (url.contains(entry.key)) await Future<void>.delayed(entry.value);
    }
    return '#EXTM3U\n#EXTINF:-1,ok\nhttps://stream.example/seg.ts\n';
  }
}

const _platform = LivePlatform(id: 'all', name: '全部');

LiveChannel _channel(List<String> urls) => LiveChannel(
  key: 'k',
  name: '主播甲',
  urls: urls,
  number: '1',
  headers: const {},
  logo: '',
  group: '主播',
  source: 'fixture-list',
);

void main() {
  test('线路顺序由实测决定：取不到清单的线路沉底，仍保留兜底', () async {
    final repository = LiveRepository(
      http: _RankedHttp(
        dead: ['p1.example'],
        slow: {'p2.example': const Duration(milliseconds: 60)},
      ),
    );
    addTearDown(repository.dispose);

    final channels = await repository.channels(_listSource, _platform);
    expect(channels, hasLength(2));

    final urls = channels.first.urls;
    expect(urls, hasLength(3), reason: '失败线路保留为兜底，不能丢线路');
    expect(urls[0], 'https://stream.example/a.m3u8', reason: '最快的可用线路排第一');
    expect(
      urls[1],
      startsWith('https://p2.example/proxy/'),
      reason: '可用但慢的线路排第二',
    );
    expect(
      urls[2],
      startsWith('https://p1.example/proxy/'),
      reason: '取不到清单的线路沉底',
    );

    final plan = await repository.playback(_listSource, channels.first);
    expect(plan.url, urls.first, reason: '默认从实测可用的首条线路起播');
  });

  test('预检全部失败时保持原顺序，不阻断加载', () async {
    final repository = LiveRepository(http: _RankedHttp(offline: true));
    addTearDown(repository.dispose);

    final channels = await repository.channels(_listSource, _platform);
    final urls = channels.first.urls;
    expect(urls, hasLength(3));
    expect(urls[0], startsWith('https://p1.example/proxy/'));
    expect(urls[1], startsWith('https://p2.example/proxy/'));
    expect(urls[2], 'https://stream.example/a.m3u8');
  });

  test('预检顺序对整个分类生效，不只作用于首条频道', () async {
    final repository = LiveRepository(http: _RankedHttp(dead: ['p1.example']));
    addTearDown(repository.dispose);

    final channels = await repository.channels(_listSource, _platform);
    for (final channel in channels) {
      expect(
        channel.urls.last,
        startsWith('https://p1.example/proxy/'),
        reason: '每条频道都按同一份实测顺序排线',
      );
    }
  });

  test('列表型源按站源指定的默认分组归类，不落进其他', () async {
    final repository = LiveRepository(http: _FakeHttp());
    addTearDown(repository.dispose);

    final channels = await repository.channels(_listSource, _platform);
    expect(channels.every((channel) => channel.group == '主播'), isTrue);
  });

  test('切换线路会更新当前线路标号', () async {
    final repository = LiveRepository(http: _FakeHttp());
    addTearDown(repository.dispose);
    final controller = LivePlaybackController(repository: repository);
    addTearDown(controller.dispose);

    expect(controller.route, 0);
    await controller.playRoute(2);
    expect(controller.route, 2);
    await controller.playRoute(-5);
    expect(controller.route, 0, reason: '越界的线路号收敛到首条');
  });

  test('换台回到首条线路，避免沿用上一台已经劣化的线路', () async {
    final repository = LiveRepository(http: _FakeHttp());
    addTearDown(repository.dispose);
    final controller = LivePlaybackController(repository: repository);
    addTearDown(controller.dispose);

    final first = _channel(['https://p1.example/a', 'https://p2.example/a']);
    final second = _channel(['https://p1.example/b', 'https://p2.example/b']);
    await controller.load(_listSource, [first, second], autoplay: false);
    await controller.playRoute(1);
    expect(controller.route, 1);

    await controller.play(1);
    expect(controller.route, 0, reason: '换台后从第一条线路重新起播');
  });
}
