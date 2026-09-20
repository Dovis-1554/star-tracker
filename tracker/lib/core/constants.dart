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
  /// 季号的各种写法。豆瓣常用「第一季 / 年番2」，我们自己的记录写作「第N季」，
  /// 聚合与季号识别必须同时认得这几种，否则同剧各季会散成多张卡。
  ///
  /// 注意：**只用于识别，不用于改写名字**——从元数据导入的条目保留来源原始标题。
  static final List<RegExp> seasonPatterns = <RegExp>[
    RegExp(r'第\s*(\d+)\s*季'),
    RegExp(r'第\s*([一二三四五六七八九十]+)\s*季'),
    RegExp(r'年番\s*(\d+)'),
    RegExp(r'第\s*([一二三四五六七八九十]+)\s*部'),
    RegExp(r'[Ss]eason\s*(\d+)'),
    RegExp(r'\b[Ss](\d{1,2})\b'),
  ];

  static const _cnDigits = <String, int>{
    '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };

  /// 去季号后的基准名：「X 第2季」「X 年番2」→「X」；无季号则原样返回。
  static String baseNameOf(String name) {
    for (final re in seasonPatterns) {
      final m = re.firstMatch(name);
      if (m == null) continue;
      return _trimSeparators(name.substring(0, m.start).trim());
    }
    return name.trim();
  }

  /// 条目自身季号；识别不出季号视为第 1 季。
  static int seasonNoOf(String name) {
    for (final re in seasonPatterns) {
      final m = re.firstMatch(name);
      if (m == null) continue;
      final raw = m.group(1)!;
      return int.tryParse(raw) ?? _parseCn(raw) ?? 1;
    }
    return 1;
  }

  static String _trimSeparators(String s) {
    var out = s;
    while (out.isNotEmpty && '·•-—_:： '.contains(out[out.length - 1])) {
      out = out.substring(0, out.length - 1);
    }
    return out.trim();
  }

  /// 中文数字 → 阿拉伯数字，支持到九十九（季号够用）。
  static int? _parseCn(String s) {
    if (s.isEmpty) return null;
    if (s.contains('十')) {
      final parts = s.split('十');
      final tens = parts[0].isEmpty ? 1 : (_cnDigits[parts[0]] ?? 0);
      final ones = parts.length > 1 && parts[1].isNotEmpty
          ? (_cnDigits[parts[1]] ?? 0)
          : 0;
      return tens * 10 + ones;
    }
    var value = 0;
    for (final ch in s.split('')) {
      final d = _cnDigits[ch];
      if (d == null) return null;
      value = value * 10 + d;
    }
    return value;
  }
}

/// 数据来源。manual 为手动创建，其余为各元数据提供者。
abstract final class Sources {
  static const manual = 'manual';
  static const douban = 'douban';
  static const tmdb = 'tmdb';
  static const tvmaze = 'tvmaze';
}
