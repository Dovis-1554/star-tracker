import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../ui/cover/cover_generator.dart';
import 'candidate.dart';
import 'metadata_provider.dart';

/// 豆瓣搜索建议接口。
///
/// 非官方内部接口（2026-09-17 广州实测可用，约 0.3s）：
/// ```
/// GET https://movie.douban.com/j/subject_suggest?q={关键词}
/// Headers: User-Agent: <浏览器 UA> / Referer: https://movie.douban.com/
/// ```
/// 返回 JSON 数组，字段：id / title / sub_title / year / episode（集数）/ img / url。
/// `type` 恒为 movie，不可用；不返回评分与简介。
///
/// 详情页抓取会被反爬拦截（返回验证页），因此**只做搜索态**，不抓详情。
class DoubanProvider implements MetadataProvider {
  DoubanProvider({http.Client? client}) : _client = client ?? http.Client();

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// doubanio 图床对无 Referer 的请求返回 418，下载封面时必须带上。
  static const _referer = 'https://movie.douban.com/';

  static const _searchUrl = 'https://movie.douban.com/j/subject_suggest';

  static const Duration _searchTimeout = Duration(seconds: 4);
  static const Duration _imageTimeout = Duration(seconds: 8);

  final http.Client _client;

  @override
  String get id => Sources.douban;

  @override
  Future<List<MetadataCandidate>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return const <MetadataCandidate>[];

    final uri = Uri.parse('$_searchUrl?q=${Uri.encodeQueryComponent(q)}');
    http.Response res;
    try {
      res = await _client
          .get(uri, headers: <String, String>{
            'User-Agent': _userAgent,
            'Referer': _referer,
          })
          .timeout(_searchTimeout);
    } catch (_) {
      // 超时 / 断网 / DNS 失败，统一按「搜不到」处理，UI 转手动录入。
      throw const MetadataException('网络请求失败，请检查网络');
    }

    if (res.statusCode == 403) {
      throw const MetadataException('豆瓣拒绝了请求（403），稍后再试或手动录入');
    }
    if (res.statusCode != 200) {
      throw MetadataException('豆瓣返回 ${res.statusCode}');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      throw const MetadataException('豆瓣返回内容无法解析（可能被风控拦截）');
    }
    if (decoded is! List) {
      throw const MetadataException('豆瓣返回结构异常');
    }

    final result = <MetadataCandidate>[];
    for (final raw in decoded) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id']?.toString();
      final title = raw['title']?.toString().trim();
      if (id == null || id.isEmpty || title == null || title.isEmpty) continue;
      result.add(
        MetadataCandidate(
          externalId: id,
          title: title,
          year: raw['year']?.toString(),
          episode: int.tryParse(raw['episode']?.toString() ?? ''),
          coverUrl: raw['img']?.toString(),
        ),
      );
    }
    return result;
  }

  @override
  Future<String?> downloadCover(String url, String saveAsId) async {
    try {
      final res = await _client
          .get(Uri.parse(url), headers: <String, String>{
            'User-Agent': _userAgent,
            'Referer': _referer,
          })
          .timeout(_imageTimeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;

      // 与程序化封面用同一路径，保证「下载失败 → 生成占位图」时槽位一致。
      final path = await CoverGenerator.coverPathFor(saveAsId);
      await File(path).writeAsBytes(res.bodyBytes);
      return path;
    } catch (_) {
      return null;
    }
  }
}
