import 'package:duanju_app/live_models.dart';
import 'package:duanju_app/live_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _textFixture = '''
更新时间,2026-10-04

央视IPV4,#genre#
CCTV1综合,http://a.example/cctv1.m3u8
CCTV2财经,http://a.example/cctv2.m3u8|User-Agent=LiveUA
CCTV3综艺,http://a.example/cctv3.m3u8#http://b.example/cctv3.m3u8

卫视IPV4,#genre#
湖南卫视,http://a.example/hunan.m3u8
浙江卫视,rtmp://a.example/zhejiang

ua=Mozilla/5.0 TestReferer
referer=http://a.example/
东方卫视,http://a.example/dongfang.m3u8
''';

const _m3uFixture = '''
#EXTM3U url-tvg="http://epg.example/e.xml" x-tvg-url="http://epg.example/f.xml"
#EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV1" tvg-logo="http://logo.example/1.png" tvg-chno="1" group-title="央视",CCTV1综合
#EXTVLCOPT:http-user-agent=M3UA
http://a.example/cctv1.m3u8
#EXTINF:-1 group-title="卫视",湖南卫视
http://a.example/hunan.m3u8
#EXTINF:-1 group-title="卫视",湖南卫视
http://b.example/hunan.m3u8
更新时间,2026-10-04
''';

const _jsonFixture = '''
[
  {
    "group": "央视",
    "channel": [
      {"name": "CCTV1综合", "urls": ["http://a.example/cctv1.m3u8"]},
      {"name": "CCTV2财经", "urls": ["http://a.example/cctv2.m3u8", "http://b.example/cctv2.m3u8"]}
    ]
  },
  {
    "group": "卫视",
    "channel": [{"name": "湖南卫视", "url": "http://a.example/hunan.m3u8#http://b.example/hunan.m3u8"}]
  }
]
''';

void main() {
  group('文本直播源', () {
    late LiveParseResult result;

    setUp(() {
      result = LiveParser.parse(_textFixture, source: 'xiuguo');
    });

    test('按 #genre# 分组并保留名称', () {
      expect(result.format, LiveFormat.text);
      expect(result.groups.map((group) => group.name).toList(), [
        '央视IPV4',
        '卫视IPV4',
      ]);
    });

    test('过滤更新时间等元信息行', () {
      final names = [
        for (final group in result.groups)
          for (final channel in group.channels) channel.name,
      ];
      expect(names, isNot(contains('更新时间')));
      expect(names.length, 6);
    });

    test('同名单频道合并多线路且保持顺序', () {
      final cctv3 = result.groups.first.channels.firstWhere(
        (channel) => channel.name == 'CCTV3综艺',
      );
      expect(cctv3.urls, [
        'http://a.example/cctv3.m3u8',
        'http://b.example/cctv3.m3u8',
      ]);
    });

    test('行内 | 后面的请求头单独生效', () {
      final cctv2 = result.groups.first.channels.firstWhere(
        (channel) => channel.name == 'CCTV2财经',
      );
      expect(cctv2.headers['User-Agent'], 'LiveUA');
    });

    test('ua 与 referer 指令作用于后续频道', () {
      final group = result.groups.last;
      final dongfang = group.channels.firstWhere(
        (channel) => channel.name == '东方卫视',
      );
      expect(dongfang.headers['Referer'], 'http://a.example/');
    });

    test('rtmp 线路排在 http 线路之后', () {
      final channels = result.groups.last.channels;
      final zhejiang = channels.firstWhere(
        (channel) => channel.name == '浙江卫视',
      );
      expect(zhejiang.urls.single, 'rtmp://a.example/zhejiang');
      expect(zhejiang.urls.single.startsWith('rtmp'), isTrue);
    });

    test('按顺序自动编号', () {
      final numbers = [
        for (final group in result.groups)
          for (final channel in group.channels) channel.number,
      ];
      expect(numbers.first, '001');
      expect(numbers, numbers.toSet().toList());
    });

    test('频道 key 在源与分组内稳定', () {
      final channel = result.groups.first.channels.first;
      expect(
        channel.key,
        LiveChannel.makeKey('xiuguo', '央视IPV4', 'CCTV1综合'),
      );
    });
  });

  group('M3U 直播源', () {
    late LiveParseResult result;

    setUp(() {
      result = LiveParser.parse(_m3uFixture, source: 'xiuguo');
    });

    test('读取 EPG 地址', () {
      expect(result.format, LiveFormat.m3u);
      expect(result.epg, 'http://epg.example/e.xml');
    });

    test('解析 group-title 与 tvg 属性', () {
      final channel = result.groups.first.channels.first;
      expect(result.groups.first.name, '央视');
      expect(channel.name, 'CCTV1综合');
      expect(channel.tvgId, 'cctv1');
      expect(channel.logo, 'http://logo.example/1.png');
      expect(channel.number, '001');
    });

    test('EXTVLCOPT 设置 User-Agent', () {
      final channel = result.groups.first.channels.first;
      expect(channel.headers['User-Agent'], 'M3UA');
    });

    test('同名频道合并线路而不是重复出现', () {
      final satellite = result.groups.firstWhere(
        (group) => group.name == '卫视',
      );
      expect(satellite.channels.length, 1);
      expect(satellite.channels.single.urls.length, 2);
    });

    test('过滤更新时间行', () {
      final names = [
        for (final group in result.groups)
          for (final channel in group.channels) channel.name,
      ];
      expect(names, isNot(contains('更新时间')));
    });
  });

  group('JSON 直播源', () {
    test('解析分组与多线路', () {
      final result = LiveParser.parse(_jsonFixture, source: 'xiuguo');
      expect(result.format, LiveFormat.json);
      expect(result.groups.length, 2);
      final cctv2 = result.groups.first.channels[1];
      expect(cctv2.urls.length, 2);
      expect(result.groups.last.channels.single.urls.length, 2);
    });
  });

  group('容错', () {
    test('空内容不产生频道', () {
      expect(LiveParser.parse('', source: 'xiuguo').isEmpty, isTrue);
      expect(LiveParser.parse('   \n  ', source: 'xiuguo').isEmpty, isTrue);
    });

    test('丢弃非播放地址', () {
      final result = LiveParser.parse(
        '央视,#genre#\n无效频道,not-a-url\nCCTV1,http://a.example/1.m3u8\n',
        source: 'xiuguo',
      );
      expect(result.channelCount, 1);
    });

    test('没有分组行时归入其他', () {
      final result = LiveParser.parse(
        'CCTV1,http://a.example/1.m3u8\n',
        source: 'xiuguo',
      );
      expect(result.groups.single.name, liveUnsortedGroup);
    });

    test('识别播放协议', () {
      expect(isPlayableLiveUrl('http://a.example/1.m3u8'), isTrue);
      expect(isPlayableLiveUrl('rtmp://a.example/live'), isTrue);
      expect(isPlayableLiveUrl('rtsp://a.example/live'), isTrue);
      expect(isPlayableLiveUrl('udp://@239.0.0.1:1234'), isTrue);
      expect(isPlayableLiveUrl('not-a-url'), isFalse);
      expect(isPlayableLiveUrl('file:///tmp/1.m3u8'), isFalse);
    });

    test('解析请求头字符串', () {
      expect(parseLiveHeaders('User-Agent=UA&Referer=http://a.example/'), {
        'User-Agent': 'UA',
        'Referer': 'http://a.example/',
      });
      expect(parseLiveHeaders('{"User-Agent":"UA"}'), {'User-Agent': 'UA'});
      expect(parseLiveHeaders(''), isEmpty);
    });
  });
}
