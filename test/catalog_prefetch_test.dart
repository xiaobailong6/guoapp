import 'package:duanju_app/catalog_prefetch.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('滚动期间不触发，停止滚动后才补齐提前量', () {
    fakeAsync((async) {
      final scheduler = CatalogPrefetchScheduler(
        bufferScreens: 2,
        idleDelay: const Duration(milliseconds: 320),
      );
      addTearDown(scheduler.dispose);
      var calls = 0;
      scheduler.onIdle = () => calls++;

      for (var i = 0; i < 12; i++) {
        scheduler.scrolled(extentAfter: 400, viewport: 800);
        async.elapse(const Duration(milliseconds: 40));
      }
      expect(calls, 0, reason: '快速滚动时不应插入取页请求');

      async.elapse(const Duration(milliseconds: 400));
      expect(calls, greaterThan(0));
    });
  });

  test('提前量充足时不请求下一页', () {
    fakeAsync((async) {
      final scheduler = CatalogPrefetchScheduler();
      addTearDown(scheduler.dispose);
      var calls = 0;
      scheduler.onIdle = () => calls++;

      scheduler.scrolled(extentAfter: 4000, viewport: 800);
      async.elapse(const Duration(seconds: 1));
      expect(calls, 0);
    });
  });

  test('单次空闲最多补齐到上限轮数', () {
    fakeAsync((async) {
      final scheduler = CatalogPrefetchScheduler(
        maxRounds: 3,
        idleDelay: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);
      var calls = 0;
      scheduler.onIdle = () {
        calls++;
        scheduler.settled(extentAfter: 100, viewport: 800);
      };

      scheduler.scrolled(extentAfter: 100, viewport: 800);
      async.elapse(const Duration(seconds: 5));
      expect(calls, 3);
    });
  });

  test('切换页签会重置轮数并暂停', () {
    fakeAsync((async) {
      final scheduler = CatalogPrefetchScheduler(
        maxRounds: 3,
        idleDelay: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);
      var calls = 0;
      scheduler.onIdle = () => calls++;

      scheduler.scrolled(extentAfter: 100, viewport: 800);
      async.elapse(const Duration(milliseconds: 50));
      expect(calls, 1);

      scheduler.hold();
      scheduler.settled(extentAfter: 100, viewport: 800);
      async.elapse(const Duration(milliseconds: 50));
      expect(calls, 1, reason: '聚合期间不允许继续取页');
    });
  });

  test('重新进入首页后解除暂停并继续补齐', () {
    fakeAsync((async) {
      final scheduler = CatalogPrefetchScheduler(
        idleDelay: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);
      var calls = 0;
      scheduler.onIdle = () => calls++;

      scheduler.scrolled(extentAfter: 100, viewport: 800);
      async.elapse(const Duration(milliseconds: 50));
      expect(calls, 1);

      scheduler.hold();
      expect(scheduler.paused, isTrue);
      scheduler.resume();
      expect(scheduler.paused, isFalse);
      scheduler.settled(extentAfter: 100, viewport: 800);
      async.elapse(const Duration(milliseconds: 50));
      expect(calls, 2);
    });
  });

  test('首屏加载完成后按现有内容判断是否需要预加载', () {
    fakeAsync((async) {
      final scheduler = CatalogPrefetchScheduler(
        idleDelay: const Duration(milliseconds: 10),
      );
      addTearDown(scheduler.dispose);
      var calls = 0;
      scheduler.onIdle = () => calls++;

      scheduler.settled(extentAfter: 100, viewport: 800);
      async.elapse(const Duration(milliseconds: 50));
      expect(calls, 1, reason: '内容不足一屏时应在首次布局后继续取页');

      scheduler.settled(extentAfter: 5000, viewport: 800);
      async.elapse(const Duration(milliseconds: 50));
      expect(calls, 1, reason: '提前量充足时不再取页');
    });
  });

  test('视口不可用时不做提前量判断', () {
    final scheduler = CatalogPrefetchScheduler();
    addTearDown(scheduler.dispose);
    expect(scheduler.wantsMore, isFalse);
  });

  test('释放后不再回调', () {
    fakeAsync((async) {
      final scheduler = CatalogPrefetchScheduler(
        idleDelay: const Duration(milliseconds: 10),
      );
      var calls = 0;
      scheduler.onIdle = () => calls++;
      scheduler.scrolled(extentAfter: 100, viewport: 800);
      scheduler.dispose();
      async.elapse(const Duration(seconds: 1));
      expect(calls, 0);
    });
  });
}
