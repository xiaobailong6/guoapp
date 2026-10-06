import 'dart:convert';

import 'package:duanju_app/live_http.dart';
import 'package:duanju_app/live_models.dart';
import 'package:duanju_app/live_repository.dart';
import 'package:duanju_app/live_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录请求并按路径回放合成内容，用于验证分类与频道过滤。
class _FakeHttp extends LiveHttp {
  _FakeHttp(this.routes);

  final Map<String, String> routes;
  final List<String> requested = [];

  @override
  Future<String> get(String url, {Map<String, String> headers = const {}}) async {
    requested.add(url);
    for (final entry in routes.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    throw StateError('未合成的请求：$url');
  }
}

/// 两个镜像：分类子集不同，且同一分类的计数可能不同步。
const _mirrorAJson = '''
{"pingtai":[
 {"title":"卫视直播","address":"jsonweishizhibo.txt","Number":"36"},
 {"title":"卡哇伊","address":"jsonkawayi.txt","Number":"83"},
 {"title":"咪狐","address":"jsonmihu.txt","Number":"77"},
 {"title":"付宝","address":"jsonfubao.txt","Number":"0"},
 {"title":"龙珠","address":"jsonlongzhu.txt","Number":"0"}
]}
''';

const _mirrorBJson = '''
{"pingtai":[
 {"title":"卡哇伊","address":"jsonkawayi.txt","Number":"83"},
 {"title":"咪狐","address":"jsonmihu.txt","Number":"77"},
 {"title":"付宝","address":"jsonfubao.txt","Number":"77"},
 {"title":"龙珠","address":"jsonlongzhu.txt","Number":"0"},
 {"title":"小红帽","address":"jsonxiaohongmao.txt","Number":"90"}
]}
''';

/// 上游不带频道数字段时不做过滤。
const _untaggedJson = '''
{"pingtai":[
 {"title":"卡哇伊","address":"jsonkawayi.txt"},
 {"title":"咪狐","address":"jsonmihu.txt"}
]}
''';

/// 同一频道内容在两个镜像下完全一致，用于验证按分类路由。
const _mirrorChannelsJson = '''
{"zhubo":[{"title":"主播甲","address":"https://live.example/a.flv"}]}
''';

const _cctvJson = '''
{"zhubo":[
 {"title":"CCTV1综合","address":"https://live.example/cctv1.m3u8"},
 {"title":"CCTV5体育","address":"https://live.example/cctv5.m3u8"},
 {"title":"浙江卫视","address":"https://live.example/zj.m3u8"}
]}
''';

const _showJson = '''
{"zhubo":[
 {"title":"主播甲","address":"https://live.example/a.flv"},
 {"title":"主播乙","address":"rtmp://live.example/b"},
 {"title":"央视网选","address":"https://live.example/cctv.m3u8"},
 {"title":"主播甲","address":"https://live.example/dup.flv"}
]}
''';

void main() {
  final source = LiveSource.values.first;

  test('多镜像分类取并集，失效与空分类被剔除', () async {
    final http = _FakeHttp({
      'vipmisss.com:81/xcdsw/json.txt': _mirrorAJson,
      'hclyz.com:81/mf/json.txt': _mirrorBJson,
    });
    final repository = LiveRepository(http: http);
    addTearDown(repository.dispose);

    final platforms = await repository.platforms(source);
    final ids = platforms.map((item) => item.id).toList();

    expect(
      ids,
      ['jsonkawayi.txt', 'jsonmihu.txt', 'jsonfubao.txt', 'jsonxiaohongmao.txt'],
      reason: '两镜像各自的分类都要保留，龙珠两边都为空要剔除',
    );
    expect(ids, isNot(contains('jsonweishizhibo.txt')));
    expect(ids, isNot(contains('jsonlongzhu.txt')));
  });

  test('同一分类两镜像计数不同步时取有内容的一边', () async {
    final http = _FakeHttp({
      'vipmisss.com:81/xcdsw/json.txt': _mirrorAJson,
      'hclyz.com:81/mf/json.txt': _mirrorBJson,
    });
    final repository = LiveRepository(http: http);
    addTearDown(repository.dispose);

    final platforms = await repository.platforms(source);
    final fubao = platforms.firstWhere((item) => item.id == 'jsonfubao.txt');

    expect(fubao.count, 77, reason: '视果记 0 而彩果记 77，应取有内容的一边');
    expect(
      fubao.endpoint,
      contains('hclyz.com'),
      reason: '要跟随报告有内容的镜像取频道',
    );
  });

  test('分类按提供它的镜像取频道', () async {
    final http = _FakeHttp({
      'vipmisss.com:81/xcdsw/json.txt': _mirrorAJson,
      'hclyz.com:81/mf/json.txt': _mirrorBJson,
      'hclyz.com:81/mf/jsonxiaohongmao.txt': _mirrorChannelsJson,
    });
    final repository = LiveRepository(http: http);
    addTearDown(repository.dispose);

    final platforms = await repository.platforms(source);
    final only = platforms.firstWhere((item) => item.id == 'jsonxiaohongmao.txt');
    final channels = await repository.channels(source, only);

    expect(channels.map((item) => item.name), ['主播甲']);
    expect(
      http.requested.any((url) => url.contains('jsonxiaohongmao')),
      isTrue,
      reason: '该分类只有彩果镜像提供，必须请求到对应域名',
    );
    expect(
      http.requested.any(
        (url) => url.contains('vipmisss') && url.contains('jsonxiaohongmao'),
      ),
      isFalse,
      reason: '不应把分类请求发到不提供它的镜像',
    );
  });

  test('首选镜像不可用时回退到其他镜像', () async {
    final http = _FakeHttp({
      'vipmisss.com:81/xcdsw/jsonkawayi.txt': _mirrorChannelsJson,
    });
    final repository = LiveRepository(http: http);
    addTearDown(repository.dispose);

    final channels = await repository.channels(
      source,
      const LivePlatform(
        id: 'jsonkawayi.txt',
        name: '卡哇伊',
        count: 83,
        endpoint: 'http://api.hclyz.com:81/mf',
      ),
    );

    expect(channels.map((item) => item.name), ['主播甲']);
  });

  test('上游不带频道数字段时不过滤分类', () async {
    final http = _FakeHttp({'vipmisss.com:81/xcdsw/json.txt': _untaggedJson});
    final repository = LiveRepository(http: http);
    addTearDown(repository.dispose);

    final platforms = await repository.platforms(source);

    expect(platforms.map((item) => item.id), ['jsonkawayi.txt', 'jsonmihu.txt']);
  });

  test('央视与卫视频道被过滤', () async {
    final http = _FakeHttp({'jsonweishizhibo.txt': _cctvJson});
    final repository = LiveRepository(http: http);
    addTearDown(repository.dispose);

    final channels = await repository.channels(
      source,
      const LivePlatform(id: 'jsonweishizhibo.txt', name: '卫视直播'),
    );

    expect(channels.map((item) => item.name), ['浙江卫视']);
  });

  test('收藏频道经序列化往返后仍解析出播放地址', () async {
    final repository = LiveRepository(http: _FakeHttp({}));
    addTearDown(repository.dispose);
    final channel = LiveChannel(
      key: LiveChannel.makeKey('xiuguo', '卡哇伊', '主播甲'),
      name: '主播甲',
      urls: const ['https://live.example/a.flv'],
      number: '003',
      group: '卡哇伊',
      source: 'xiuguo',
      subtitle: '观众 12',
    );

    final restored = LiveChannel.fromFavourite(
      jsonDecode(jsonEncode(channel.toFavourite())) as Map<String, dynamic>,
    );

    expect(restored.urls, channel.urls, reason: '收藏持久化不能丢线路');
    expect(restored.key, channel.key);
    final plan = await repository.playback(source, restored);
    expect(plan.url, 'https://live.example/a.flv');
  });

  test('收藏频道保留请求头', () async {
    final repository = LiveRepository(http: _FakeHttp({}));
    addTearDown(repository.dispose);
    final channel = LiveChannel(
      key: LiveChannel.makeKey('xiuguo', '卡哇伊', '主播乙'),
      name: '主播乙',
      urls: const ['https://live.example/b.m3u8'],
      headers: const {'Referer': 'https://live.example/'},
      group: '卡哇伊',
      source: 'xiuguo',
    );

    final restored = LiveChannel.fromFavourite(
      jsonDecode(jsonEncode(channel.toFavourite())) as Map<String, dynamic>,
    );

    final plan = await repository.playback(source, restored);
    expect(plan.headers['Referer'], 'https://live.example/');
  });

  test('秀场频道保留，RTMP 后排，重名去重', () async {
    final http = _FakeHttp({'jsonkawayi.txt': _showJson});
    final repository = LiveRepository(http: http);
    addTearDown(repository.dispose);

    final channels = await repository.channels(
      source,
      const LivePlatform(id: 'jsonkawayi.txt', name: '卡哇伊'),
    );

    expect(channels.map((item) => item.name), ['主播甲', '主播乙']);
    expect(channels.last.urls.single, startsWith('rtmp'));
    expect(channels.map((item) => item.number), ['001', '002']);
  });
}
