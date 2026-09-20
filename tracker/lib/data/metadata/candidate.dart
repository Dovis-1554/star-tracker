import '../../core/constants.dart';

/// 元数据搜索命中的一条候选。
///
/// 只携带「录入时能自动填充」的字段。评分与简介豆瓣 suggest 接口不提供，
/// 因此这里也不设，避免 UI 上出现永远为空的输入框。
class MetadataCandidate {
  const MetadataCandidate({
    required this.externalId,
    required this.title,
    this.year,
    this.episode,
    this.coverUrl,
  });

  /// 来源站点内的条目 ID（豆瓣 subject id）。
  final String externalId;

  /// 来源站点的原始标题，例如「仙逆 年番2」。入库前需过 [normalizeSeasonName]。
  final String title;

  final String? year;

  /// 总集数。豆瓣叫 episode，是这个接口最有用的字段。
  final int? episode;

  /// 远程封面 URL。下载到本地后方可使用（doubanio 对无 Referer 请求返回 418）。
  final String? coverUrl;

  /// 猜类型：1 集 → 电影，其余 → 剧集。
  ///
  /// 豆瓣 suggest 的 type 字段恒为 movie，区分不出动漫 / 剧集，
  /// 所以只能按集数粗猜，让用户在编辑页改。
  String guessType() => episode == 1 ? ItemTypes.movie : ItemTypes.tv;
}
