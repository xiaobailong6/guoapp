import 'catalog_browser.dart';
import 'catalog_sort.dart';
import 'models.dart';

class CatalogViewCache {
  List<Drama>? _rows;
  Object? _key;
  List<Drama> _visible = [];
  final Map<Drama, String> _searchText = {};

  List<Drama> select(
    List<Drama> rows, {
    required String query,
    required String category,
    required bool onlineSearch,
    required bool hideVip,
    required Set<String> allowedSources,
    required int profileEpoch,
    required CatalogView view,
  }) {
    final permissionKey = allowedSources.toList()..sort();
    final key = (
      query,
      category,
      onlineSearch,
      hideVip,
      permissionKey.join('\u0000'),
      profileEpoch,
      view.sort,
      view.release,
    );
    if (identical(rows, _rows) && key == _key) return _visible;
    if (!identical(rows, _rows)) {
      _searchText.clear();
      _rows = rows;
    }
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .map(normalizedSearchText)
        .where((word) => word.isNotEmpty)
        .toList();
    final visible = sortCatalog(
      rows.where((drama) {
        if (!allowedSources.contains(drama.source)) return false;
        if (category.startsWith('local:') &&
            categoryName(drama.category) != category.substring(6)) {
          return false;
        }
        if (hideVip && drama.source == 'huangdou' && drama.vip) return false;
        if (onlineSearch || terms.isEmpty) return true;
        final text = _searchText.putIfAbsent(
          drama,
          () => normalizedSearchText(
            '${drama.title} ${drama.description} ${drama.tags.join(' ')}',
          ),
        );
        return terms.every(text.contains);
      }),
      view,
    );
    _key = key;
    _visible = visible;
    return visible;
  }
}
