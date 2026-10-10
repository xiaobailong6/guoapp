import 'dart:async';
import 'package:duanju_app/source_status.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/sources_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

Future<LocalStore> mount(
  WidgetTester tester, {
  FixtureRepository? repository,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = LocalStore(await SharedPreferences.getInstance());
  addTearDown(store.dispose);
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SourcesScreen(
        repository: repository ?? FixtureRepository(),
        store: store,
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return store;
}

void main() {
  testWidgets('source count stays pending until a real count arrives', (
    tester,
  ) async {
    final repository = _PendingBatchRepository();
    final store = await mount(tester, repository: repository);
    expect(find.text('0 部'), findsNothing);
    expect(find.text('读取中'), findsWidgets);
    repository.pending.complete({
      for (final source in store.sources)
        source.id: SourceStatus.fromJson({'source': source.id, 'count': 0}),
    });
    await tester.pump();
    expect(find.text('0 部'), findsWidgets);
    expect(find.text('读取中'), findsNothing);
  });

  testWidgets('status refresh uses one batch and builds source cards lazily', (
    tester,
  ) async {
    final repository = _BatchRepository();
    final store = await mount(tester, repository: repository);
    expect(repository.batches, 1);
    expect(repository.singleCalls, 0);
    expect(
      repository.requested.toSet(),
      store.sources.map((s) => s.id).toSet(),
    );
    final cards = find.byWidgetPredicate(
      (widget) =>
          widget is Card &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('source-'),
    );
    expect(cards.evaluate().length, lessThan(store.sources.length));
    final ordered = [
      for (final group in SourceGroup.fromSources(store.sources))
        ...group.sources,
    ];
    final last = find.byKey(ValueKey('source-${ordered.last.id}'));
    expect(last, findsNothing);
    await tester.scrollUntilVisible(
      last,
      350,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    expect(last, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every 黄果 entrance forms its own card like other sources', (
    tester,
  ) async {
    final store = await mount(tester);
    for (final id in ['huangguo-video', 'huangguoai', 'cloudfront']) {
      final card = find.byKey(ValueKey('source-$id'));
      await tester.scrollUntilVisible(
        card,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(card, findsOneWidget, reason: '$id 应与其他站源一样独立成卡片');
    }
    expect(find.text('黄果'), findsNothing, reason: '不再使用黄果折叠分组');
    expect(find.byType(ExpansionTile), findsNothing);
    expect(store.sources.length, SourceSite.values.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a 黄果 card and its actions keeps the app alive', (
    tester,
  ) async {
    await mount(tester);
    final card = find.byKey(const ValueKey('source-huangguo-video'));
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(card);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    final update = find.byKey(const ValueKey('update-huangguo-video'));
    expect(update, findsOneWidget);
    await tester.tap(update);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
  });
}

class _BatchRepository extends FixtureRepository {
  int batches = 0;
  int singleCalls = 0;
  List<String> requested = [];

  @override
  Future<Map<String, SourceStatus>> sourceStatuses(List<String> sources) async {
    batches++;
    requested = List.of(sources);
    return {
      for (final source in sources)
        source: SourceStatus.fromJson({'source': source, 'count': 7}),
    };
  }

  @override
  Future<SourceStatus> sourceStatus(String source) async {
    singleCalls++;
    return SourceStatus.fromJson({'source': source});
  }
}

class _PendingBatchRepository extends FixtureRepository {
  final pending = Completer<Map<String, SourceStatus>>();

  @override
  Future<Map<String, SourceStatus>> sourceStatuses(List<String> sources) =>
      pending.future;
}
