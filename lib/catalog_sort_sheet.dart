import 'package:flutter/material.dart';

import 'app_layout.dart';
import 'catalog_sort.dart';
import 'glass_panel.dart';

Future<CatalogView?> chooseCatalogView(
  BuildContext context,
  CatalogView current,
) => showModalBottomSheet<CatalogView>(
  context: context,
  showDragHandle: false,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: (context) {
    var selected = current;
    final viewPaddingBottom = MediaQuery.viewPaddingOf(context).bottom;
    final paddingBottom = MediaQuery.paddingOf(context).bottom;
    final systemInset = viewPaddingBottom > paddingBottom
        ? viewPaddingBottom
        : paddingBottom;
    return StatefulBuilder(
      builder: (context, update) => GlassPanel(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20 +
                (systemInset > MediaQuery.viewInsetsOf(context).bottom
                    ? systemInset
                    : MediaQuery.viewInsetsOf(context).bottom),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('排序与筛选', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sort in CatalogSort.values)
                    ChoiceChip(
                      autofocus:
                          AppLayout.isTelevision(context) &&
                          sort == CatalogSort.values.first,
                      label: Text(sort.label),
                      selected: selected.sort == sort,
                      onSelected: (_) => update(
                        () => selected = selected.copyWith(sort: sort),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('剧集状态'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in const {
                    '': '全部',
                    'ongoing': '连载中',
                    'finished': '已完结',
                    'unknown': '状态未知',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: selected.release == entry.key,
                      onSelected: (_) => update(
                        () => selected = selected.copyWith(release: entry.key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '排序和筛选作用于已加载的剧集；缺少排序资料的条目排在最后。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text('应用'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
