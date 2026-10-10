import 'package:duanju_app/library_updater.dart';
import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/source_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

class _Repository extends FixtureRepository {
  int batches = 0;
  int singles = 0;
  int count = 3;
  @override
  bool get supportsSourceManagement => true;
  @override
  Future<Map<String, SourceStatus>> sourceStatuses(List<String> sources) async {
    batches++;
    return {
      for (final source in sources)
        source: SourceStatus.fromJson({'source': source, 'count': count}),
    };
  }

  @override
  Future<SourceStatus> sourceStatus(String source) async {
    singles++;
    return SourceStatus.fromJson({'source': source});
  }
}

void main() {
  test(
    'updater batches polling and suppresses unchanged notifications',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final repository = _Repository();
      final updater = LibraryUpdater(repository, store);
      addTearDown(updater.dispose);
      addTearDown(store.dispose);
      var notifications = 0;
      updater.addListener(() => notifications++);
      await updater.refresh();
      expect(notifications, 1);
      await updater.refresh();
      expect(notifications, 1);
      repository.count = 4;
      await updater.refresh();
      expect(notifications, 2);
      expect(repository.batches, 3);
      expect(repository.singles, 0);
    },
  );
}
