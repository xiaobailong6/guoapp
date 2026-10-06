import 'dart:convert';

import 'package:duanju_app/app_build.dart';
import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/local_profiles.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const red = FixtureRepository.free;
  const other = FixtureRepository.vip;

  test('绿色模式默认开启并隐藏成人站源', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.fullMode, isFalse, reason: '完整模式默认关闭');
    expect(store.greenMode, isTrue, reason: '默认必须是绿色模式');
    expect(SourceSite.isKnown('yanguo'), isTrue);
    expect(SourceSite.isAdult('yanguo'), isTrue, reason: '艳果应标记为成人站源');
    expect(SourceSite.isAdult('shuangguo'), isFalse, reason: '爽果是绿色站源');
    if (allSourcesEnabled) {
      expect(
        store.sources.any((source) => source.id == 'yanguo'),
        isFalse,
        reason: '绿色模式下成人站源不应出现在可用站源里',
      );
    }
    await store.setGreenMode(false);
    expect(store.greenMode, isTrue, reason: '未开启完整模式时关不掉绿色模式');
    await store.setFullMode(true);
    await store.setGreenMode(false);
    if (allSourcesEnabled) {
      expect(store.greenMode, isFalse);
      expect(store.fullMode, isTrue);
      expect(
        store.sources.any((source) => source.id == 'yanguo'),
        isTrue,
        reason: '关闭绿色模式后成人站源应可选',
      );
    } else {
      expect(store.fullMode, isFalse, reason: '绿果鉴没有完整模式，点版本号也开不出来');
      expect(store.greenMode, isTrue, reason: '绿果鉴必须始终是绿色模式');
      expect(
        store.sources.any((source) => source.adult),
        isFalse,
        reason: '绿果鉴的可用站源里不能出现成人站源',
      );
    }
    store.dispose();
  });

  test('配置备份导出与导入都保留完整模式与分级限制开关', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'greenMode': false,
      'fullMode': true,
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    if (!allSourcesEnabled) {
      expect(store.greenMode, isTrue, reason: '绿果鉴忽略存量完整模式，保持绿色');
      store.dispose();
      return;
    }
    expect(store.greenMode, isFalse);
    final exported = await store.exportBackup();
    final restored = LocalStore(await SharedPreferences.getInstance());
    await restored.importBackup(exported);
    expect(restored.greenMode, isFalse, reason: '导入应还原关闭状态');
    // 旧备份没有这个键时，必须回落到默认的开启状态。
    final legacy = Map<String, dynamic>.from(jsonDecode(exported) as Map);
    legacy.remove('greenMode');
    legacy.remove('fullMode');
    final upgraded = LocalStore(await SharedPreferences.getInstance());
    await upgraded.importBackup(jsonEncode(legacy));
    expect(upgraded.greenMode, isTrue, reason: '缺少该键的旧备份应回落到绿色模式');
    store.dispose();
    restored.dispose();
    upgraded.dispose();
  });

  test('edition sources include DSD only in the all-source build', () async {
    SharedPreferences.setMockInitialValues({'source': 'huangdou'});
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(appSlug, allSourcesEnabled ? 'zhenguojian' : 'lvguojian');
    // 默认绿色模式下，两个版本可选的都是非成人站源。
    expect(
      store.sources.length,
      SourceSite.allValues.where((site) => !site.adult).length,
    );
    expect(
      SourceSite.values.any((source) => source.id == 'dsd'),
      allSourcesEnabled,
    );
    expect(SourceSite.isAvailable('dsd'), allSourcesEnabled);
    expect(SourceSite.isKnown('dsd'), isTrue);
    expect(SourceSite.byId('dsd').name, '帝果');
    expect(store.allowsSource('dsd'), isFalse);
    expect(store.source, 'hongguo', reason: '豆果已标为成人，应回落到红果');
    store.dispose();
  });

  test('分级限制过滤收藏与记录，备份仍保留被过滤的条目', () async {
    final history = [
      for (final drama in [red, other])
        WatchEntry(
          drama: drama,
          episode: 1,
          position: 12,
          duration: 60,
          updatedAt: DateTime(2026, 9, 19),
        ).toJson(),
    ];
    SharedPreferences.setMockInitialValues({
      'source': 'huangdou',
      'favorites': jsonEncode([red.toJson(), other.toJson()]),
      'history': jsonEncode(history),
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    // 豆果是成人站源，任何版本下绿色模式都不显示它的收藏与记录。
    expect(store.favorites.map((drama) => drama.id), [red.id]);
    expect(store.history.map((entry) => entry.drama.id), [red.id]);
    expect(store.isFavorite(other.id), isFalse);
    expect(store.watched(other.id) != null, isFalse);
    await store.toggleFavorite(red);
    final backup = await store.exportBackup();
    final library = (jsonDecode(backup)['libraries'] as Map)['default'] as Map;
    expect((library['favorites'] as List).map((row) => (row as Map)['id']), [
      other.id,
    ]);
    expect(library['history'], hasLength(2));
    await store.importBackup(backup);
    expect(store.preferences.getString('source'), 'huangdou');
    expect(store.history, hasLength(1));
    expect(store.favorites, isEmpty);
    store.dispose();
  });

  test(
    'a restored foreign-source profile keeps its identity and permissions',
    () async {
      SharedPreferences.setMockInitialValues({
        'profiles': jsonEncode([
          LocalProfile(
            id: 'default',
            name: '管理员',
            admin: true,
            salt: '0' * 32,
            pinHash: '1' * 64,
          ).toJson(),
          const LocalProfile(
            id: 'viewer',
            name: '已有用户',
            sources: ['huangdou'],
            download: false,
          ).toJson(),
        ]),
        'activeProfile': 'viewer',
        'profile.viewer.source': 'huangdou',
      });
      final store = LocalStore(await SharedPreferences.getInstance());
      expect(store.profile.id, 'viewer');
      expect(store.profile.admin, isFalse);
      expect(store.profile.sources, ['huangdou']);
      expect(store.canDownload, isFalse);
      expect(store.source, '', reason: '豆果已标为成人，任何版本都不可选');
      expect(store.allowsSource('hongguo'), isFalse);
      expect(store.allowsSource('huangdou'), isFalse);
      store.dispose();
    },
  );

  test('restored DSD profile data follows edition availability', () async {
    SharedPreferences.setMockInitialValues({
      'profiles': jsonEncode([
        LocalProfile(
          id: 'default',
          name: '管理员',
          admin: true,
          salt: '0' * 32,
          pinHash: '1' * 64,
        ).toJson(),
        const LocalProfile(
          id: 'viewer',
          name: '帝果旧用户',
          sources: ['dsd'],
          download: false,
        ).toJson(),
      ]),
      'activeProfile': 'viewer',
      'profile.viewer.source': 'dsd',
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    expect(store.configurationError, isNull);
    expect(store.profile.sources, ['dsd']);
    // 帝果已标为成人，绿色模式下两个版本都不会把它列进可选站源。
    expect(store.sources.map((source) => source.id), isEmpty);
    expect(store.source, '');
    expect(store.allowsSource('dsd'), isFalse);
    store.dispose();
  });

  test(
    'background requests reject unavailable sources before native I/O',
    () async {
      final repository = NativeRepository(background: true);
      final denied = [
        ...SourceSite.allValues
            .where((source) => !SourceSite.isAvailable(source.id))
            .map((source) => source.id),
        'unknown',
      ];
      for (final source in denied) {
        final drama = Drama(id: '$source:123', source: source, title: '合成数据');
        final episode = Episode({'id': '1'}, 1);
        for (final request in [
          () => repository.catalog(source),
          () => repository.cached(source),
          () => repository.sourceStatus(source),
          () => repository.startSourceJob(source, 'update'),
          () => repository.cancelSourceJob(source),
          () => repository.detail(drama),
          () => repository.cover(drama),
          () => repository.resolve(drama, episode),
          () => repository.resolveOnline(drama, episode),
          () => repository.enqueueDownloads(DramaDetail(drama, [episode]), [
            episode,
          ]),
          () => repository.localPlayback(drama, episode),
        ]) {
          await expectLater(
            request(),
            throwsA(
              isA<AppFailure>().having(
                (error) => error.message,
                'message',
                '当前版本不包含此站源',
              ),
            ),
          );
        }
      }
    },
  );
}
