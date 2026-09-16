import 'package:drift/drift.dart';

/// 条目表：一部剧 / 动漫 / 漫画一条记录。
///
/// 同步相关字段见架构文档第 5 节：
/// - [updatedAt] 必须单调递增，用于多设备合并时取新
/// - [deleted] 是墓碑标记，删除只置 1，绝不物理删除
@DataClassName('TitleRow')
class Titles extends Table {
  TextColumn get id => text()(); // uuid v4
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get platform => text().nullable()();
  TextColumn get status => text()();
  IntColumn get totalEpisodes => integer().nullable()();

  /// 远程封面完整 URL。豆瓣直接用返回的 img；TMDB 需拼 base + size + path 后存入。
  TextColumn get coverUrl => text().nullable()();

  /// 本地封面文件路径（生成的占位图或缓存下来的图）。
  TextColumn get coverPath => text().nullable()();

  RealColumn get score => real().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get startedAt => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  /// 数据来源，见 [Sources]。
  TextColumn get source => text().withDefault(const Constant('manual'))();

  /// 来源站点内的条目 ID，配合 [source] 唯一定位。
  TextColumn get externalId => text().nullable()();

  TextColumn get originalName => text().nullable()();
  TextColumn get overview => text().nullable()();
  TextColumn get releaseDate => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 集数表。独立成表而非记 currentEpisode，是为了支持跳看与重看。
@DataClassName('EpisodeRow')
class Episodes extends Table {
  TextColumn get id => text()(); // uuid v4

  /// 外键 -> Titles.id。不建数据库级外键，同步合并时顺序无法保证。
  TextColumn get titleId => text()();

  IntColumn get season => integer().withDefault(const Constant(1))();
  IntColumn get no => integer()();
  IntColumn get watched => integer().withDefault(const Constant(0))();
  IntColumn get watchedAt => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get deleted => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 操作历史，用于「本月进度」「看了多少部」等统计。
@DataClassName('HistoryRow')
class History extends Table {
  TextColumn get id => text()(); // uuid v4
  TextColumn get titleId => text()();
  TextColumn get action => text()();
  TextColumn get value => text().nullable()();
  IntColumn get at => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
