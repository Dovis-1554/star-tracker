/// 类型 / 平台 / 状态的取值与中文显示名。
/// 存英文值，显示中文——避免改名时污染历史数据。
library;

abstract final class ItemTypes {
  static const tv = 'tv';
  static const anime = 'anime';
  static const movie = 'movie';
  static const manga = 'manga';
  static const shortDrama = 'short_drama';
  static const aiDrama = 'ai_drama';

  /// [comic] 与 [manga] 曾同时显示为「漫画」，已合并为 manga。
  /// 保留常量与映射仅为兼容历史数据，UI 选项里不再出现。
  static const comic = 'comic';

  static const all = <String>[tv, anime, shortDrama, aiDrama, movie, manga];

  static String label(String v) => switch (v) {
        tv => '剧集',
        anime => '动漫',
        movie => '电影',
        manga => '漫画',
        shortDrama => '短剧',
        aiDrama => 'AI漫剧',
        comic => '漫画',
        _ => v,
      };
}

abstract final class Platforms {
  static const hongguo = 'hongguo';
  static const douyin = 'douyin';
  static const huolong = 'huolong';
  static const paoman = 'paoman';
  static const bilibili = 'bilibili';
  static const qimao = 'qimao';
  static const netflix = 'netflix';
  static const other = 'other';

  static const all = <String>[
    hongguo,
    douyin,
    huolong,
    paoman,
    bilibili,
    qimao,
    netflix,
    other,
  ];

  static String label(String v) => switch (v) {
        hongguo => '红果',
        douyin => '抖音',
        huolong => '火龙漫剧',
        paoman => '泡漫',
        bilibili => 'B站',
        qimao => '七猫',
        netflix => 'Netflix',
        other => '其他',
        _ => v,
      };
}

abstract final class ItemStatus {
  static const plan = 'plan';
  static const watching = 'watching';
  static const paused = 'paused';

  /// 自己看完了（集数全部标记已看时由程序自动置位）。
  /// 与 [completed]（作品本身完结）区分：完结是作品状态，已看是观看状态。
  static const watched = 'watched';

  static const completed = 'completed';
  static const dropped = 'dropped';

  static const all = <String>[
    plan,
    watching,
    paused,
    watched,
    completed,
    dropped,
  ];

  static String label(String v) => switch (v) {
        plan => '想看',
        watching => '在看',
        paused => '暂停',
        watched => '已看',
        completed => '完结',
        dropped => '弃',
        _ => v,
      };
}

/// 剧名与季号的拆分工具。
///
/// 数据模型是「一季一条记录」（`X 第N季`），但很多地方只需要剧名本体——
/// 封面文字、详情页标题、首页聚合都用它。放 core 层，UI 与封面生成都能直接引。
abstract final class TitleNames {
  static final RegExp seasonPattern = RegExp(r'^(.*?)\s*第(\d+)季$');

  /// 去季号后的基准名：「X 第2季」→「X」；无季号则原样返回。
  static String baseNameOf(String name) =>
      seasonPattern.firstMatch(name)?.group(1) ?? name;

  /// 条目自身季号；无「第N季」后缀视为第 1 季。
  static int seasonNoOf(String name) {
    final m = seasonPattern.firstMatch(name);
    return m != null ? int.tryParse(m.group(2)!) ?? 1 : 1;
  }
}

/// 数据来源。manual 为手动创建，其余为各元数据提供者。
abstract final class Sources {
  static const manual = 'manual';
  static const douban = 'douban';
  static const tmdb = 'tmdb';
  static const tvmaze = 'tvmaze';
}
