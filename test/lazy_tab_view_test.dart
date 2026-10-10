import 'package:duanju_app/lazy_tab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.index, this.events);
  final int index;
  final List<String> events;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.events.add('start-${widget.index}');
  }

  @override
  void dispose() {
    widget.events.add('stop-${widget.index}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('page-${widget.index}');
}

void main() {
  testWidgets('tabs start lazily, keep state and release transient pages', (
    tester,
  ) async {
    final events = <String>[];
    Future<void> show(int index, {int epoch = 0}) => tester.pumpWidget(
      MaterialApp(
        home: LazyTabView(
          key: ValueKey(epoch),
          index: index,
          transientTabs: const {2},
          builder: (index) => _Probe(index, events),
        ),
      ),
    );
    await show(0);
    expect(events, ['start-0']);
    await show(1);
    expect(events, ['start-0', 'start-1']);
    expect(find.text('page-0'), findsNothing);
    await show(0);
    expect(events, ['start-0', 'start-1']);
    expect(find.text('page-0'), findsOneWidget);
    await show(2);
    await show(1);
    expect(events, contains('stop-2'));
    expect(events, isNot(contains('stop-0')));
    await show(1, epoch: 1);
    expect(events, contains('stop-0'));
    expect(events.where((event) => event == 'start-1').length, 2);
    expect(tester.takeException(), isNull);
  });
}
