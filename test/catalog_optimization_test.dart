import 'package:duanju_app/catalog_browser.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class _CachedRepository extends FixtureRepository {
  @override
  Future<CatalogPage> cached(String source, {String category = ''}) async =>
      CatalogPage([
        Drama(id: '$source:1', source: source, title: '合成剧', category: '都市'),
      ], fresh: true);
}

void main() {
  test('category cache refreshes after category metadata changes', () async {
    final browser = CatalogBrowser(_CachedRepository());
    const group = SourceGroup('hongguo', '红果', [SourceSite.hongguo]);
    await browser.load(group, cacheOnly: true);
    final before = browser.categories(group);
    final repeat = browser.categories(group);
    expect(identical(before[1], repeat[1]), isTrue);
    browser.updateDrama(
      const Drama(
        id: 'hongguo:1',
        source: 'hongguo',
        title: '合成剧',
        category: '悬疑',
      ),
    );
    expect(
      browser.categories(group).map((entry) => entry.name),
      contains('悬疑'),
    );
    expect(
      browser.categories(group).map((entry) => entry.name),
      isNot(contains('都市')),
    );
  });

  test('drama comparison detects metadata and tag changes', () {
    const original = Drama(
      id: 'hongguo:1',
      source: 'hongguo',
      title: '合成剧',
      tags: ['都市'],
    );
    expect(original.sameAs(original.merge(original)), isTrue);
    expect(
      original.sameAs(
        original.merge(
          const Drama(
            id: 'hongguo:1',
            source: 'hongguo',
            title: '新剧名',
            tags: ['都市'],
          ),
        ),
      ),
      isFalse,
    );
    expect(
      original.sameAs(
        original.merge(
          const Drama(
            id: 'hongguo:1',
            source: 'hongguo',
            title: '合成剧',
            tags: ['悬疑'],
          ),
        ),
      ),
      isFalse,
    );
  });
}
