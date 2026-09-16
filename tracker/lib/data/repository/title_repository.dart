import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../db/database.dart';
import '../../ui/cover/cover_generator.dart';

/// 条目读写入口。UI 只跟它打交道，不直接碰 drift。
class TitleRepository {
  const TitleRepository(this._db);

  final AppDatabase _db;

  Stream<List<TitleRow>> watchTitles({String? status}) => _db.watchTitles(status: status);

  /// 单个条目订阅。详情页靠它自动反映编辑后的变化。
  Stream<TitleRow?> watchTitle(String id) => _db.watchTitle(id);

  Stream<List<EpisodeRow>> watchEpisodes(String titleId) => _db.watchEpisodes(titleId);

  /// 一次性读取全部条目（详情页定位默认季等场景）。
  Future<List<TitleRow>> allTitles() => _db.getAllTitles();

  /// 一次性读取各条目已看集数（详情页定位默认季等场景）。
  Future<Map<String, int>> watchedCounts() => _db.watchWatchedCounts().first;

  Future<String> create({
    required String name,
    required String type,
    String? platform,
    required String status,
    int? totalEpisodes,
    String? coverUrl,
    String? externalId,
    String source = Sources.manual,
  }) async {
    final id = generateId();
    final ts = _db.nextTimestamp();

    await _db.insertTitle(
      TitlesCompanion(
        id: Value(id),
        name: Value(name),
        type: Value(type),
        platform: Value(platform),
        status: Value(status),
        totalEpisodes: Value(totalEpisodes),
        coverUrl: Value(coverUrl),
        createdAt: Value(ts),
        updatedAt: Value(ts),
        source: Value(source),
        externalId: Value(externalId),
      ),
    );

    if (totalEpisodes != null && totalEpisodes > 0) {
      await _db.ensureEpisodes(id, totalEpisodes);
    }

    // 没有远程封面时，本地生成占位海报
    if (coverUrl == null || coverUrl.isEmpty) {
      final path = await CoverGenerator.generate(id: id, title: name);
      await _db.updateTitle(
        TitlesCompanion(id: Value(id), coverPath: Value(path)),
      );
    }

    return id;
  }

  Future<void> update(TitlesCompanion row) => _db.updateTitle(row);

  /// 编辑页保存：名称 / 类型 / 平台 / 状态 / 总集数一次性写回。
  ///
  /// 注意：这里必须全字段写回。之前只有 name + totalEpisodes，
  /// 类型与平台的修改被静默丢弃。
  Future<void> saveEdit({
    required String id,
    required String name,
    required String type,
    String? platform,
    required String status,
    int? totalEpisodes,
  }) async {
    final row = await _db.getTitle(id);
    if (row == null) return;

    // 没有远程封面就重绘占位海报：封面文字只取剧名本体（季号由 CoverPainter 剥掉），
    // 每次保存都重绘，历史上带季号的旧封面也就顺手修好了。
    final hasRemoteCover = row.coverUrl != null && row.coverUrl!.isNotEmpty;
    String? coverPath;
    if (!hasRemoteCover) {
      coverPath = await CoverGenerator.generate(id: id, title: name);
    }

    await _db.updateTitle(
      TitlesCompanion(
        id: Value(id),
        name: Value(name),
        type: Value(type),
        platform: Value(platform),
        status: Value(status),
        totalEpisodes: Value(totalEpisodes),
        coverPath: coverPath == null ? const Value.absent() : Value(coverPath),
        updatedAt: Value(_db.nextTimestamp()),
      ),
    );

    if (totalEpisodes != null && totalEpisodes > 0) {
      // 补了新集：本来「已看 / 完结」的条目重新回到在看。
      final added = await _db.ensureEpisodes(id, totalEpisodes);
      await rewindOnNewEpisodes(id, added: added);
    }

    // 同剧多季共用一张封面：编辑了哪一季，封面就跟着那一季走。
    await _syncCoverToSiblings(id, coverPath ?? row.coverPath);
  }

  Future<void> setStatus(String id, String status) async {
    await _db.updateTitle(
      TitlesCompanion(
        id: Value(id),
        status: Value(status),
        updatedAt: Value(_db.nextTimestamp()),
      ),
    );
  }

  Future<void> softDelete(String id) => _db.softDeleteTitle(id);

  /// 剧名去掉季号后的基准名：「X 第2季」→「X」。同剧各季以此聚合到一个详情页。
  static String baseNameOf(String name) => TitleNames.baseNameOf(name);

  /// 条目自身季号；无「第N季」后缀视为第 1 季。
  static int seasonNoOf(String name) => TitleNames.seasonNoOf(name);

  /// 推算下一季条目名：本体按第 1 季，已有「X 第N季」时取最大 N + 1。
  /// 条目按「一季一条记录」建模，与集数表的 season 字段互不影响。
  Future<String> nextSeasonName(String name) async {
    final base = baseNameOf(name);
    final all = await _db.getAllTitles();
    var max = seasonNoOf(name);
    final re = RegExp(r'^' + RegExp.escape(base) + r'\s*第(\d+)季$');
    for (final t in all) {
      final s = re.firstMatch(t.name);
      if (s == null) continue;
      final n = int.tryParse(s.group(1)!);
      if (n != null && n > max) max = n;
    }
    return '$base 第${max + 1}季';
  }

  Future<void> setEpisodeWatched(EpisodeRow row, {required bool watched}) async {
    await _db.setEpisodeWatched(row, watched: watched);
    await syncStatusByEpisodes(row.titleId);
  }

  /// 标记下一集已看：把第一个未看的集数置为已看。
  Future<void> markNextWatched(String titleId) async {
    final list = await _db.watchEpisodes(titleId).first;
    for (final e in list) {
      if (e.watched == 0) {
        await _db.setEpisodeWatched(e, watched: true);
        break;
      }
    }
    await syncStatusByEpisodes(titleId);
  }

  /// 长按某集：把序号小于等于该集的集数全部标记为已看，返回受影响行数。
  Future<int> markUpToWatched(EpisodeRow row) async {
    final n = await _db.markEpisodesUpTo(row.titleId, row.no, watched: true);
    await syncStatusByEpisodes(row.titleId);
    return n;
  }

  /// 集数变动后同步状态：
  /// - 全部集已看 → 自动置为「已看」；
  /// - 已看状态下又取消了一集 → 退回「在看」。
  ///
  /// 没有集数行的条目不动——手动设的想看 / 已看不该被冲掉。
  /// 「弃」是明确的终止选择，也不覆盖。
  Future<void> syncStatusByEpisodes(String titleId) async {
    final row = await _db.getTitle(titleId);
    if (row == null) return;
    final list = await _db.watchEpisodes(titleId).first;
    if (list.isEmpty) return;

    final allWatched = list.every((e) => e.watched == 1);
    if (allWatched &&
        row.status != ItemStatus.watched &&
        row.status != ItemStatus.dropped) {
      await setStatus(titleId, ItemStatus.watched);
    } else if (!allWatched && row.status == ItemStatus.watched) {
      await setStatus(titleId, ItemStatus.watching);
    }
  }

  /// 补了新集 / 加了新一季 → 从「已看 / 完结」回到「在看」。
  /// 只回退这两种终止态，避免把「想看」「暂停」误改成在看。
  Future<void> rewindOnNewEpisodes(String titleId, {required int added}) async {
    if (added <= 0) return;
    final row = await _db.getTitle(titleId);
    if (row == null) return;
    if (row.status == ItemStatus.watched || row.status == ItemStatus.completed) {
      await setStatus(titleId, ItemStatus.watching);
    }
  }

  /// 一次性修复历史封面：早期生成的占位图把「第N季」也画进去了。
  ///
  /// 必须**全量**重绘（无远程封面的都画一遍），不能只挑名字带季号的行——
  /// 封面会在同剧各季间传播，A 季的 coverPath 可能指向 B 季的文件，
  /// 按「本行名字是否带季号」判断会漏。重绘后所有季的图都只有剧名本体。
  /// 不写 updatedAt，避免打乱首页排序；顺带把 coverPath 为空的行补上。
  Future<int> regenerateAllCovers() async {
    final all = await _db.getAllTitles();
    var n = 0;
    for (final t in all) {
      if (t.coverUrl != null && t.coverUrl!.isNotEmpty) continue;
      final path = await CoverGenerator.generate(id: t.id, title: t.name);
      if (t.coverPath == null) {
        await _db.updateTitle(
          TitlesCompanion(id: Value(t.id), coverPath: Value(path)),
        );
      }
      n++;
    }
    return n;
  }

  /// 同剧多季共用一张封面：编辑了哪一季，整部剧的封面就跟着那一季走。
  /// 有远程封面的季不覆盖——那是外部数据，不该被本地占位图冲掉。
  Future<void> _syncCoverToSiblings(String id, String? coverPath) async {
    if (coverPath == null) return;
    final row = await _db.getTitle(id);
    if (row == null) return;
    final base = baseNameOf(row.name);
    final all = await _db.getAllTitles();
    for (final t in all) {
      if (t.id == id || baseNameOf(t.name) != base) continue;
      if (t.coverUrl != null && t.coverUrl!.isNotEmpty) continue;
      await _db.updateTitle(
        TitlesCompanion(
          id: Value(t.id),
          coverPath: Value(coverPath),
          updatedAt: Value(_db.nextTimestamp()),
        ),
      );
    }
  }

  Future<int> countByStatus(String status) => _db.countByStatus(status);
  Future<int> countAll() => _db.countAll();
}
