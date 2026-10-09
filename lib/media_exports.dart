part of 'media_library.dart';

bool _validShowFolder(String folder) {
  final components = folder.split(RegExp(r'[/\\]'));
  return !path.isAbsolute(folder) &&
      components.length == 2 &&
      components.first == 'exports' &&
      components.last.isNotEmpty &&
      !{'.', '..'}.contains(components.last) &&
      !components.last.contains(':');
}

String embySpecialNfo(LocalMediaItem item, int number) =>
    '<?xml version="1.0" encoding="utf-8"?>\n<episodedetails>'
    '<title>${xmlText(item.drama.title)} · 合并第 ${item.episodes.first}–${item.episodes.last} 集</title>'
    '<showtitle>${xmlText(item.drama.title)}</showtitle><season>0</season><episode>$number</episode>'
    '<displayseason>1</displayseason><displayepisode>${item.episodes.last + 1}</displayepisode>'
    '<plot>${xmlText('合并第 ${item.episodes.first}–${item.episodes.last} 集，共 ${item.episodes.length} 集。\n${item.drama.description}')}</plot>'
    '<uniqueid type="zhenguojian" default="true">${xmlText(item.special ? item.id : 'special-${item.id}')}</uniqueid></episodedetails>\n';

extension MediaExportOperations on MediaLibrary {
  Future<String> _showDirectory(Drama drama) async {
    final existing = _showFolders[drama.id];
    if (existing != null) return existing;
    final hash = sha256
        .convert(utf8.encode(drama.id))
        .toString()
        .substring(0, 12);
    final folder = path.join(
      'exports',
      '${_safeName(drama.title)} [${drama.source}-$hash]',
    );
    if (_showFolders.values.contains(folder)) {
      throw AppFailure('导出目录与另一部剧冲突，请检查本地媒体记录');
    }
    _showFolders[drama.id] = folder;
    try {
      _check();
      await _save();
    } catch (_) {
      _showFolders.remove(drama.id);
      rethrow;
    }
    return folder;
  }

  Future<void> _writeShowMetadata(Drama drama, Directory showDirectory) async {
    final poster = File(path.join(showDirectory.path, 'poster.jpg'));
    var hasPoster = await poster.exists();
    if (store.exportPosters &&
        !hasPoster &&
        !const bool.fromEnvironment('DISABLE_REMOTE_IMAGES')) {
      try {
        final cover = await repository.cover(drama);
        _check();
        await File(cover).copy(poster.path);
        hasPoster = true;
      } catch (_) {
        _check();
      }
    }
    _check();
    await _writeText(
      File(path.join(showDirectory.path, 'tvshow.nfo')),
      embyShowNfo(drama, localPoster: hasPoster),
    );
  }

  Future<void> _copyOutput(File source, File target, int bytes) async {
    final output = await target.open(mode: FileMode.write);
    var copied = 0;
    try {
      await for (final block in source.openRead()) {
        _check();
        await output.writeFrom(block);
        copied += block.length;
        progress = bytes > 0 ? .4 * copied / bytes : 0;
        notifyListeners();
      }
      await output.flush();
    } finally {
      await output.close();
    }
    _check();
    if (copied != bytes) throw AppFailure('复制成品时文件发生变化，请重试；原成品保留');
  }

  Future<LocalMediaItem> exportMerged(LocalMediaItem selected) => _task(
    '准备导出特别篇',
    (temporary) async {
      final source = _items
          .where((item) => item.id == selected.id && item.merged)
          .firstOrNull;
      if (source == null || source.episodes.isEmpty) {
        throw AppFailure('合并成品不存在，请刷新后重试');
      }
      final file = File(fileFor(source));
      if (!await file.exists() || await file.length() != source.bytes) {
        throw AppFailure('合并成品缺失或不完整，请重新合并');
      }
      final drama = repository.catalogUpdates.current(source.drama);
      final folder = await _showDirectory(drama);
      final key = '${source.drama.id}\u0000${source.id}';
      var number = _specialNumbers[key];
      if (number == null) {
        final prefix = '${source.drama.id}\u0000';
        var highest = 0;
        for (final entry in _specialNumbers.entries.where(
          (entry) => entry.key.startsWith(prefix),
        )) {
          if (entry.value > highest) highest = entry.value;
        }
        number = highest + 1;
        if (number > 100000) throw AppFailure('特别篇数量已达上限');
        _specialNumbers[key] = number;
        try {
          await _save();
        } catch (_) {
          _specialNumbers.remove(key);
          rethrow;
        }
      }
      final relative = path.join(
        folder,
        'Season 00',
        'S00E${number.toString().padLeft(3, '0')}.mkv',
      );
      final target = File(path.join(root!, relative));
      final staged = File(path.join(temporary.path, 'special.mkv'));
      await _copyOutput(file, staged, source.bytes);
      final checked = await executor.probe(staged.path);
      verifyMediaDuration(checked, source.duration);
      await _decodeOutput(staged.path, checked.duration, base: .4, weight: .55);
      await target.parent.create(recursive: true);
      _check();
      await staged.rename(target.path);
      final item = LocalMediaItem(
        id: 'special-${source.id}',
        drama: drama,
        file: relative,
        kind: 'special',
        episodes: source.episodes,
        duration: checked.duration,
        bytes: source.bytes,
        created: DateTime.now(),
        sourceVersion: '${source.id}-${source.bytes}-${source.sourceVersion}',
        decodeVerified: true,
        specialNumber: number,
      );
      await _writeShowMetadata(drama, target.parent.parent);
      await _writeText(
        File(path.setExtension(target.path, '.nfo')),
        embySpecialNfo(item, number),
      );
      final previous = List<LocalMediaItem>.of(_items);
      _items.removeWhere((entry) => entry.id == item.id);
      _items.add(item);
      try {
        _check();
        await _save();
      } catch (_) {
        _items = previous;
        rethrow;
      }
      return item;
    },
    sources: {selected.drama.source},
  );
}

extension MediaFolderExportOperations on MediaLibrary {
  Future<({int exported, int skipped})> exportJobsToDirectory(
    List<DownloadJob> selected,
    String destination,
  ) => _task('准备导出到文件夹', (temporary) async {
    final jobs = selected.where((job) => job.completed).toList()
      ..sort((a, b) => a.episode.number.compareTo(b.episode.number));
    if (jobs.isEmpty) throw AppFailure('没有已下载的分集');
    final show = Directory(
      path.join(destination, _safeName(jobs.first.drama.title)),
    );
    await show.create(recursive: true);
    var exported = 0;
    var skipped = 0;
    for (var i = 0; i < jobs.length; i++) {
      _check();
      final job = jobs[i];
      status = '导出第 ${job.episode.number} 集';
      notifyListeners();
      final plan = await repository.localPlayback(job.drama, job.episode);
      _check();
      if (plan == null || !plan.local) {
        throw AppFailure('第 ${job.episode.number} 集尚未完整下载');
      }
      final sourceExtension = path.extension(plan.url).toLowerCase();
      final playlist = sourceExtension == '.m3u8';
      final extension = playlist
          ? '.mkv'
          : sourceExtension.isEmpty
          ? '.mp4'
          : sourceExtension;
      final target = File(
        path.join(
          show.path,
          '第 ${job.episode.number.toString().padLeft(2, '0')} 集$extension',
        ),
      );
      if (await target.exists()) {
        skipped++;
        progress = (i + 1) / jobs.length;
        notifyListeners();
        continue;
      }
      if (playlist) {
        final intermediate = path.join(temporary.path, 'export-$i.mkv');
        final input = <String>[
          if (plan.decryptionKey.isNotEmpty) ...[
            '-decryption_key',
            plan.decryptionKey,
          ],
          '-allowed_extensions',
          'ALL',
          '-extension_picky',
          '0',
        ];
        await executor.run([
          ...input,
          '-i',
          plan.url,
          '-map',
          '0:v:0',
          '-map',
          '0:a:0?',
          '-c',
          'copy',
          '-map_metadata',
          '-1',
          '-avoid_negative_ts',
          'make_zero',
          intermediate,
        ]);
        _check();
        await File(intermediate).copy(target.path);
        await File(intermediate).delete();
      } else {
        await File(plan.url).copy(target.path);
      }
      exported++;
      progress = (i + 1) / jobs.length;
      notifyListeners();
    }
    status = '导出完成';
    return (exported: exported, skipped: skipped);
  }, sources: selected.map((job) => job.drama.source).toSet());
}
