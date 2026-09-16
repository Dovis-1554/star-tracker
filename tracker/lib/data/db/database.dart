import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Titles, Episodes, History])
class AppDatabase extends _$AppDatabase {
  /// 默认走应用数据目录，文件名 tracker.sqlite。
  AppDatabase() : super(driftDatabase(name: 'tracker'));

  /// 测试用：内存数据库。
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
      );

  /// 单调时间戳：绝不回退，避免设备时钟回拨导致旧数据覆盖新数据。
  /// 见架构文档第 5 节。
  int nextTimestamp() {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return now > _maxSeen ? now : _maxSeen + 1;
  }

  int _maxSeen = 0;

  void observeTimestamp(int ts) {
    if (ts > _maxSeen) _maxSeen = ts;
  }

  // ---------- 条目 ----------

  Stream<List<TitleRow>> watchTitles({String? status}) {
    final q = select(titles);
    // 条件合并进一个 where：drift 多次调用 where 的行为不保证，合并最稳。
    if (status == null) {
      q.where((t) => t.deleted.equals(0));
    } else {
      q.where((t) => t.deleted.equals(0) & t.status.equals(status));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return q.watch();
  }

  Stream<TitleRow?> watchTitle(String id) =>
      (select(titles)
            ..where((t) => t.id.equals(id) & t.deleted.equals(0)))
          .watchSingleOrNull();

  Future<TitleRow?> getTitle(String id) =>
      (select(titles)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 全部未删除条目（一次性读取，用于季数推算等轻量场景）。
  Future<List<TitleRow>> getAllTitles() =>
      (select(titles)..where((t) => t.deleted.equals(0))).get();

  Future<void> insertTitle(TitlesCompanion row) => into(titles).insert(row);

  /// 按 id 局部更新。必须用 write() 而非 replace()——replace 要求整行
  /// 所有必填字段都在（createdAt 等），部分字段的 Companion 会直接抛
  /// InvalidDataException，这正是「编辑保存不生效」的根因。
  Future<int> updateTitle(TitlesCompanion row) =>
      (update(titles)..where((t) => t.id.equals(row.id.value))).write(row);

  /// 软删除：只置墓碑，绝不做物理删除。
  Future<int> softDeleteTitle(String id) => (update(titles)..where((t) => t.id.equals(id))).write(
        TitlesCompanion(
          deleted: const Value(1),
          updatedAt: Value(nextTimestamp()),
        ),
      );

  // ---------- 集数 ----------

  Stream<List<EpisodeRow>> watchEpisodes(String titleId) {
    final q = select(episodes)
      ..where((e) => e.titleId.equals(titleId) & e.deleted.equals(0))
      ..orderBy([(e) => OrderingTerm.asc(e.season), (e) => OrderingTerm.asc(e.no)]);
    return q.watch();
  }

  Future<void> setEpisodeWatched(EpisodeRow row, {required bool watched}) {
    return (update(episodes)..where((e) => e.id.equals(row.id))).write(
      EpisodesCompanion(
        watched: Value(watched ? 1 : 0),
        watchedAt: Value(watched ? nextTimestamp() : null),
        updatedAt: Value(nextTimestamp()),
      ),
    );
  }

  /// 把该条目内序号 <= [maxNo] 的集数一次性标记 / 取消已看（长按某集的批量操作）。
  Future<int> markEpisodesUpTo(
    String titleId,
    int maxNo, {
    required bool watched,
  }) {
    final ts = nextTimestamp();
    return (update(episodes)
          ..where(
            (e) =>
                e.titleId.equals(titleId) &
                e.no.isSmallerOrEqualValue(maxNo) &
                e.deleted.equals(0),
          ))
        .write(
          EpisodesCompanion(
            watched: Value(watched ? 1 : 0),
            watchedAt: Value(watched ? ts : null),
            updatedAt: Value(ts),
          ),
        );
  }

  /// 按总集数补齐集数行；已存在的跳过，多出来的（超出新总集数）标记删除。
  /// 返回**新增**的集数行数——调用方据此判断「补了新集」。
  Future<int> ensureEpisodes(String titleId, int total) async {
    final existing = await (select(episodes)..where((e) => e.titleId.equals(titleId))).get();
    final have = <int>{for (final e in existing.where((e) => e.deleted == 0)) e.no};
    var added = 0;

    for (var no = 1; no <= total; no++) {
      if (have.contains(no)) continue;
      await into(episodes).insert(
        EpisodesCompanion(
          id: Value(generateId()),
          titleId: Value(titleId),
          no: Value(no),
          updatedAt: Value(nextTimestamp()),
        ),
      );
      added++;
    }

    for (final e in existing) {
      if (e.deleted == 0 && e.no > total) {
        await (update(episodes)..where((x) => x.id.equals(e.id))).write(
          EpisodesCompanion(
            deleted: const Value(1),
            updatedAt: Value(nextTimestamp()),
          ),
        );
      }
    }
    return added;
  }

  // ---------- 统计 ----------

  /// 各条目已看集数，用于列表显示进度。响应式，标记集数后自动刷新。
  Stream<Map<String, int>> watchWatchedCounts() {
    final q = selectOnly(episodes)
      ..addColumns([episodes.titleId, episodes.id.count()])
      ..where(episodes.watched.equals(1) & episodes.deleted.equals(0))
      ..groupBy([episodes.titleId]);
    return q.watch().map((rows) => <String, int>{
          for (final r in rows) r.read(episodes.titleId)!: r.read(episodes.id.count())!,
        });
  }

  Future<int> countByStatus(String status) async {
    final q = selectOnly(titles)
      ..addColumns([titles.id.count()])
      ..where(titles.deleted.equals(0) & titles.status.equals(status));
    final row = await q.getSingle();
    return row.read(titles.id.count()) ?? 0;
  }

  Future<int> countAll() async {
    final q = selectOnly(titles)
      ..addColumns([titles.id.count()])
      ..where(titles.deleted.equals(0));
    final row = await q.getSingle();
    return row.read(titles.id.count()) ?? 0;
  }
}

/// 简易 uuid v4。M1 阶段不引入 uuid 包，够用且避免额外依赖。
String generateId() {
  final r = _RandomHolder.rng;
  const hex = '0123456789abcdef';
  final chars = List<String>.filled(36, '');
  for (var i = 0; i < 36; i++) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      chars[i] = '-';
    } else if (i == 14) {
      chars[i] = '4';
    } else {
      chars[i] = hex[r.nextInt(16)];
    }
  }
  // variant 位
  chars[19] = hex[(r.nextInt(4)) + 8];
  return chars.join();
}

abstract final class _RandomHolder {
  static final rng = Random.secure();
}
