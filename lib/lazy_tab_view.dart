import 'package:flutter/material.dart';

class LazyTabView extends StatefulWidget {
  const LazyTabView({
    super.key,
    required this.index,
    required this.builder,
    this.transientTabs = const {},
  });

  final int index;
  final Widget Function(int index) builder;
  final Set<int> transientTabs;

  @override
  State<LazyTabView> createState() => _LazyTabViewState();
}

class _LazyTabViewState extends State<LazyTabView> {
  final _pages = <int, Widget>{};

  @override
  Widget build(BuildContext context) {
    _pages.removeWhere(
      (index, _) =>
          index != widget.index && widget.transientTabs.contains(index),
    );
    _pages[widget.index] = widget.builder(widget.index);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in _pages.entries)
          Offstage(
            key: ValueKey(entry.key),
            offstage: entry.key != widget.index,
            child: TickerMode(
              enabled: entry.key == widget.index,
              child: ExcludeFocus(
                excluding: entry.key != widget.index,
                child: entry.value,
              ),
            ),
          ),
      ],
    );
  }
}
