import 'package:duanju_app/live_models.dart';
import 'package:duanju_app/live_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

LiveChannel _channel(String name, {String source = 'xiuguo'}) => LiveChannel(
  key: LiveChannel.makeKey(source, '央视IPV4', name),
  name: name,
  urls: ['http://a.example/$name.m3u8'],
  number: '001',
  group: '央视IPV4',
  source: source,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LiveStore> create(String profileId) async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData(const {});
    final store = LiveStore(await SharedPreferences.getInstance(), profileId)
      ..load();
    addTearDown(store.dispose);
    return store;
  }

  test('收藏写入后重新载入仍然存在', () async {
    final store = await create('default');
    await store.toggleFavourite(_channel('CCTV1'));
    expect(store.isFavourite(_channel('CCTV1').key), isTrue);

    final reloaded = LiveStore(store.preferences, 'default')..load();
    addTearDown(reloaded.dispose);
    expect(reloaded.favourites.length, 1);
    expect(reloaded.favourites.single.name, 'CCTV1');
    expect(
      reloaded.favourites.single.urls.single,
      'http://a.example/CCTV1.m3u8',
    );
  });

  test('再次收藏同一频道即取消', () async {
    final store = await create('default');
    final channel = _channel('CCTV1');
    await store.toggleFavourite(channel);
    await store.toggleFavourite(channel);
    expect(store.favourites, isEmpty);
  });

  test('最近频道去重并最新在前', () async {
    final store = await create('default');
    await store.remember(_channel('CCTV1'));
    await store.remember(_channel('CCTV2'));
    await store.remember(_channel('CCTV1'));
    expect(store.recent.map((entry) => entry.name).toList(), [
      'CCTV1',
      'CCTV2',
    ]);
    await store.clearRecent();
    expect(store.recent, isEmpty);
  });

  test('不同用户的收藏互相隔离', () async {
    final admin = await create('default');
    await admin.toggleFavourite(_channel('CCTV1'));

    final guest = LiveStore(admin.preferences, 'guest')..load();
    addTearDown(guest.dispose);
    expect(guest.favourites, isEmpty);

    await guest.toggleFavourite(_channel('CCTV2'));
    expect(admin.favourites.single.name, 'CCTV1');
    expect(guest.favourites.single.name, 'CCTV2');
  });

  test('损坏的收藏内容不会导致崩溃', () async {
    final store = await create('default');
    await store.preferences.setString('live.favourites', '{not json');
    final reloaded = LiveStore(store.preferences, 'default')..load();
    addTearDown(reloaded.dispose);
    expect(reloaded.favourites, isEmpty);
  });
}
