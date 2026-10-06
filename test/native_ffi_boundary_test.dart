import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

// 这一层验证 Dart 实际调用的 C ABI：导出符号、字符串所有权与 JSON 信封。
// 动态库由 scripts/build_native.py --platform darwin --all-sources 生成。
const _libraryPath = 'native/build/darwin/libduanju_core.dylib';

typedef _NativeRequest = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _DartRequest = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _NativeFree = Void Function(Pointer<Utf8>);
typedef _DartFree = void Function(Pointer<Utf8>);

Future<List<int>> fetchBytes(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
  try {
    final response = await client
        .getUrl(Uri.parse(url))
        .then((request) => request.close())
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) {
      fail('播放代理返回 ${response.statusCode}');
    }
    final bytes = await response
        .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk))
        .timeout(const Duration(seconds: 90));
    return bytes;
  } finally {
    client.close(force: true);
  }
}

/// 逐个尝试分片；部分站源的流开头是连不通的预滚广告，播放器会自行跳过，
/// 因此只要求至少有一个分片能取回真实数据。
Future<MapEntry<int, int>> firstPlayableSegment(
  String playlist,
  String base,
) async {
  final segments = playlist
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  expect(segments, isNotEmpty, reason: '清单里没有分片');
  final attempts = segments.take(8).toList();
  for (var index = 0; index < attempts.length; index++) {
    final List<int> bytes;
    try {
      bytes = await fetchBytes(
        Uri.parse(base).resolve(attempts[index]).toString(),
      );
    } on Object {
      continue;
    }
    if (bytes.length > 1024) {
      return MapEntry(index, bytes.length);
    }
  }
  fail('清单里的分片都取不到内容（共 ${segments.length} 片）');
}

/// 樱果与露果要从本机网络之外的节点访问，实测时用 LIVE_PROXY 显式传入代理；
/// 桌面端没有原生系统代理探测，Android 上则由 SystemProxyMonitor 自动补上。
void applyProxy(Map<String, dynamic> Function(Map<String, dynamic>) call) {
  final proxy = Platform.environment['LIVE_PROXY'] ?? '';
  if (proxy.isEmpty) {
    return;
  }
  final result = call({
    'action': 'updateSystemProxy',
    'systemProxy': {'http': proxy, 'https': proxy},
  });
  expect(result['ok'], isTrue, reason: '设置代理失败：$result');
}

void main() {
  final library = File(_libraryPath);
  if (!library.existsSync()) {
    test('原生 FFI 边界在缺少动态库时跳过', () {}, skip: '未构建 darwin 动态库');
    return;
  }
  late DynamicLibrary handle;
  late _DartRequest request;
  late _DartFree free;

  setUpAll(() {
    handle = DynamicLibrary.open(_libraryPath);
    request = handle.lookupFunction<_NativeRequest, _DartRequest>(
      'DuanjuRequest',
    );
    free = handle.lookupFunction<_NativeFree, _DartFree>('DuanjuFree');
  });

  Map<String, dynamic> call(Object body) {
    final input = jsonEncode(body).toNativeUtf8();
    Pointer<Utf8> output = nullptr;
    try {
      output = request(input);
      if (output == nullptr) {
        fail('原生层没有返回结果');
      }
      final text = output.toDartString();
      free(output);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        fail('原生层返回值不是 JSON 对象：$text');
      }
      return decoded;
    } finally {
      malloc.free(input);
    }
  }

  test('导出符号可查表且信封契约稳定', () {
    final directory = Directory.systemTemp.createTempSync('duanju-ffi').path;
    expect(
      call({'action': 'initialize', 'directory': directory}),
      containsPair('ok', true),
    );
    // 请求格式无效时必须回 ok=false 且带 error，而不是抛异常或返回空指针。
    final invalid = call({'action': '不存在的操作'});
    expect(invalid['ok'], isFalse);
    expect(invalid['error'], isA<String>());
    expect(call({'action': 'release'}), containsPair('ok', true));
  });

  test('顶层入口返回站源目录与分类', () {
    final directory = Directory.systemTemp.createTempSync('duanju-ffi').path;
    expect(
      call({'action': 'initialize', 'directory': directory}),
      containsPair('ok', true),
    );
    addTearDown(() => call({'action': 'release'}));
    applyProxy(call);

    final categories = call({'action': 'categories', 'source': 'chengguo'});
    expect(categories['ok'], isTrue, reason: 'chinese name: $categories');
    final items = (categories['data'] as Map)['items'] as List;
    expect(items, isNotEmpty);
    expect(items.map((item) => (item as Map)['id']), contains('1'));
  });

  test('顶层入口把剧集解析到可播放地址', () async {
    if (Platform.environment['CHECK_LIVE_PROVIDERS'] != 'true') {
      return;
    }
    final directory = Directory.systemTemp.createTempSync('duanju-ffi').path;
    expect(
      call({'action': 'initialize', 'directory': directory}),
      containsPair('ok', true),
    );
    addTearDown(() => call({'action': 'release'}));
    applyProxy(call);

    final catalog = call({
      'action': 'catalog',
      'source': 'chengguo',
      'category': '1',
      'page': 1,
    });
    expect(catalog['ok'], isTrue, reason: '$catalog');
    final items = ((catalog['data'] as Map)['items'] as List).cast<Map>();
    expect(items, isNotEmpty);

    final drama = items.first.cast<String, dynamic>();
    final title = drama['title'] as String;
    expect(title, isNotEmpty);
    for (final noise in ['详情介绍', '在线播放', '立即播放', '<em>']) {
      expect(title.contains(noise), isFalse, reason: '标题残留：$title');
    }

    final detail = call({'action': 'detail', 'drama': drama});
    expect(detail['ok'], isTrue, reason: '$detail');
    final chapters = ((detail['data'] as Map)['chapters'] as List).cast<Map>();
    expect(chapters, isNotEmpty, reason: '详情没有分集');

    final plan = call({
      'action': 'resolve',
      'drama': drama,
      'chapter': chapters.first,
      'index': 1,
      'quality': 0,
      'sequence': 4701,
    });
    expect(plan['ok'], isTrue, reason: '$plan');
    final url = (plan['data'] as Map)['url'] as String? ?? '';
    expect(url, isNotEmpty, reason: '没有解析到播放地址');
    expect(Uri.parse(url).hasScheme, isTrue, reason: '播放地址不合法：$url');
    // 解析出的通常是本机播放代理地址；清单可读并且首个分片真的取回，才算可播。
    final playlist = utf8.decode(await fetchBytes(url), allowMalformed: true);
    expect(
      playlist.contains('#EXTM3U'),
      isTrue,
      reason: '播放代理返回的不是清单：${playlist.substring(0, 120)}',
    );
    final segment = await firstPlayableSegment(playlist, url);
    // ignore: avoid_print
    print(
      '播放链路：$title -> ${chapters.length} 集 -> 清单 ${playlist.length} 字节 -> '
      '第 ${segment.key} 片 ${segment.value} 字节',
    );
  });

  test('每个站源都能通过顶层入口取到可播放内容', () async {
    if (Platform.environment['CHECK_LIVE_PROVIDERS'] != 'true') {
      return;
    }
    final directory = Directory.systemTemp.createTempSync('duanju-ffi').path;
    expect(
      call({'action': 'initialize', 'directory': directory}),
      containsPair('ok', true),
    );
    addTearDown(() => call({'action': 'release'}));
    applyProxy(call);

    const sources = <String, String>{
      'miguo': '米果',
      'shuangguo': '爽果',
      'yanguo': '艳果',
      'taoguo': '桃果',
      'youguo': '柚果',
      'liuguo': '榴果',
      'meiguo': '美果',
      'chengguo': '城果',
      'xiaoguo': '宵果',
      'yingguo': '樱果',
      'luguo': '露果',
      'liguo': '荔果',
      'juguo': '橘果',
      'zaoguo': '枣果',
      'ningguo': '柠果',
      'mangguo': '芒果',
    };
    // 可用 FFI_SOURCES=逗号分隔的来源 id 缩小范围，便于单独复测。
    final filter =
        Platform.environment['FFI_SOURCES']?.split(',') ?? const <String>[];
    final selected = filter.isEmpty
        ? sources.entries.toList()
        : sources.entries.where((entry) => filter.contains(entry.key)).toList();
    expect(selected, isNotEmpty, reason: 'FFI_SOURCES 没有匹配到站源');
    var sequence = 5000;
    final report = <String>[];
    for (final entry in selected) {
      try {
        final categories = call({'action': 'categories', 'source': entry.key});
        final first =
            ((categories['data'] as Map)['items'] as List).first as Map;
        final catalog = call({
          'action': 'catalog',
          'source': entry.key,
          'category': first['id'],
          'page': 1,
        });
        if (catalog['ok'] != true) {
          report.add('${entry.value} 失败：目录 $catalog');
          continue;
        }
        final items = ((catalog['data'] as Map)['items'] as List).cast<Map>();
        if (items.isEmpty) {
          report.add('${entry.value} 失败：目录为空');
          continue;
        }
        final drama = items.first.cast<String, dynamic>();
        final detail = call({'action': 'detail', 'drama': drama});
        if (detail['ok'] != true) {
          report.add('${entry.value} 失败：详情 $detail');
          continue;
        }
        final chapters = ((detail['data'] as Map)['chapters'] as List)
            .cast<Map>();
        if (chapters.isEmpty) {
          report.add('${entry.value} 失败：没有分集');
          continue;
        }
        final plan = call({
          'action': 'resolve',
          'drama': drama,
          'chapter': chapters.first,
          'index': 1,
          'quality': 0,
          'sequence': ++sequence,
        });
        if (plan['ok'] != true) {
          report.add('${entry.value} 失败：解析 $plan');
          continue;
        }
        final url = (plan['data'] as Map)['url'] as String? ?? '';
        if (url.isEmpty) {
          report.add('${entry.value} 失败：没有解析到地址');
          continue;
        }
        final playlist = utf8.decode(
          await fetchBytes(url),
          allowMalformed: true,
        );
        if (!playlist.contains('#EXTM3U')) {
          report.add('${entry.value} 失败：取回的不是清单');
          continue;
        }
        final segment = await firstPlayableSegment(playlist, url);
        report.add(
          '${entry.value} 可播：${drama['title']} -> 第 ${segment.key} 片 '
          '${segment.value} 字节',
        );
      } on Object catch (error) {
        report.add('${entry.value} 失败：$error');
      } finally {
        call({'action': 'cancelPlayback', 'sequence': sequence});
      }
    }
    for (final line in report) {
      // ignore: avoid_print
      print(line);
    }
    expect(
      report.where((line) => line.contains('失败')).toList(),
      isEmpty,
      reason: '有站源无法播放',
    );
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('每个已接入站源都能通过顶层入口读取目录', () {
    final directory = Directory.systemTemp.createTempSync('duanju-ffi').path;
    expect(
      call({'action': 'initialize', 'directory': directory}),
      containsPair('ok', true),
    );
    addTearDown(() => call({'action': 'release'}));
    applyProxy(call);

    // 站源清单必须与 Go 目录一致；这里只校验静态分类可读，不触网。
    const sources = <String, String>{
      'yaguo': '芽果',
      'miguo': '米果',
      'shuangguo': '爽果',
      'yanguo': '艳果',
      'taoguo': '桃果',
      'youguo': '柚果',
      'liuguo': '榴果',
      'meiguo': '美果',
      'chengguo': '城果',
      'xiaoguo': '宵果',
      'yingguo': '樱果',
      'luguo': '露果',
      'liguo': '荔果',
      'juguo': '橘果',
      'zaoguo': '枣果',
      'ningguo': '柠果',
      'mangguo': '芒果',
    };
    for (final entry in sources.entries) {
      final response = call({'action': 'categories', 'source': entry.key});
      expect(response['ok'], isTrue, reason: '${entry.value} 分类读取失败：$response');
    }
  });
}
