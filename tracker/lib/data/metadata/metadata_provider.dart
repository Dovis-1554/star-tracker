import 'candidate.dart';

/// 元数据搜索失败。UI 据此给出可读提示，并降级为手动录入。
class MetadataException implements Exception {
  const MetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 元数据来源。当前只有豆瓣一个实现，接口先立好，后续加源不用改调用方。
abstract class MetadataProvider {
  /// 来源标识，见 [Sources]。
  String get id;

  /// 按关键词搜索，返回候选列表。无结果返回空列表，失败抛 [MetadataException]。
  Future<List<MetadataCandidate>> search(String keyword);

  /// 把远程封面下载到本地，返回文件路径；失败返回 null（调用方降级为程序化封面）。
  ///
  /// 各站点的图片防盗链规则不同（doubanio 必须带 Referer，否则 418），
  /// 所以下载动作留给各源自己实现。
  Future<String?> downloadCover(String url, String saveAsId);
}
