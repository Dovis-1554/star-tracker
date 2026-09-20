import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/metadata/candidate.dart';
import '../../data/metadata/douban_provider.dart';
import '../../data/metadata/metadata_provider.dart';
import '../../main.dart';
import '../edit/edit_title_page.dart';

/// 元数据搜索页。首页「+」与详情页「新增一季」共用。
///
/// 结果支持两种用法：
/// - 点卡片 → 单条进编辑页（可改名字/类型/集数再保存）
/// - 勾选多条 → 底部「添加 N 项」批量入库（全部归一化为「第N季」并自动合成一部剧）
///
/// 搜不到、断网、被风控都只提示，底部常驻「手动创建」，录入流程绝不卡死。
class SearchTitlePage extends StatefulWidget {
  const SearchTitlePage({super.key, this.baseName});

  /// 详情页「新增一季」传基准剧名：预填关键词，手动创建时按下一季命名。
  final String? baseName;

  @override
  State<SearchTitlePage> createState() => _SearchTitlePageState();
}

class _SearchTitlePageState extends State<SearchTitlePage> {
  final MetadataProvider _provider = DoubanProvider();
  final TextEditingController _controller = TextEditingController();
  final Set<String> _checked = <String>{};

  Timer? _debounce;
  List<MetadataCandidate> _results = const <MetadataCandidate>[];
  bool _loading = false;
  String? _error;
  bool _searched = false;
  bool _working = false; // 下载封面 / 批量入库中

  @override
  void initState() {
    super.initState();
    final base = widget.baseName;
    if (base != null && base.isNotEmpty) {
      _controller.text = base;
      // 详情页进来时直接搜，省一次点击
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(base));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const <MetadataCandidate>[];
        _error = null;
        _searched = false;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String keyword) async {
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final list = await _provider.search(keyword);
      // 按上映时间升序（无年份的排最后），同剧各季读起来是正序。
      list.sort(_byYear);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } on MetadataException catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const <MetadataCandidate>[];
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// 上映时间升序；年份缺失的排最后。
  static int _byYear(MetadataCandidate a, MetadataCandidate b) {
    final ay = int.tryParse(a.year ?? '');
    final by = int.tryParse(b.year ?? '');
    if (ay == null && by == null) return 0;
    if (ay == null) return 1;
    if (by == null) return -1;
    return ay.compareTo(by);
  }

  /// 入库名 = 豆瓣原始标题，不做改写。
  ///
  /// 乐生要求取消季名归一（不要把「年番2」改成「第2季」）。同剧各季的合并
  /// 交给 `TitleNames.baseNameOf` 在聚合时识别，不靠改写名字实现。
  String _nameOf(MetadataCandidate c) => c.title.trim();

  Future<void> _openSingle(MetadataCandidate c) async {
    final name = _nameOf(c);
    final exists = await repository.findByName(name);
    if (!mounted) return;
    if (exists != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name 已存在，不能重复添加')));
      return;
    }

    setState(() => _working = true);
    final id = generateId();
    final path = c.coverUrl == null
        ? null
        : await _provider.downloadCover(c.coverUrl!, id);
    if (!mounted) return;
    setState(() => _working = false);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditTitlePage(
          prefill: TitlePrefill(
            id: id,
            name: name,
            type: c.guessType(),
            status: ItemStatus.watching,
            totalEpisodes: c.episode,
            releaseDate: c.year,
            externalId: c.externalId,
            coverUrl: c.coverUrl,
            coverPath: path,
            source: Sources.douban,
          ),
        ),
      ),
    );
  }

  Future<void> _addChecked() async {
    final picked = _results
        .where((c) => _checked.contains(c.externalId))
        .toList();
    if (picked.isEmpty) return;

    setState(() => _working = true);
    var added = 0;
    var skipped = 0;
    for (final c in picked) {
      final name = _nameOf(c);
      if (await repository.findByName(name) != null) {
        skipped++;
        continue;
      }
      final id = generateId();
      final path = c.coverUrl == null
          ? null
          : await _provider.downloadCover(c.coverUrl!, id);
      await repository.create(
        id: id,
        name: name,
        type: c.guessType(),
        status: ItemStatus.watching,
        totalEpisodes: c.episode,
        releaseDate: c.year,
        externalId: c.externalId,
        coverUrl: c.coverUrl,
        coverPath: path,
        source: Sources.douban,
      );
      added++;
    }
    if (!mounted) return;
    setState(() => _working = false);
    Navigator.of(
      context,
    ).pop('已添加 $added 项${skipped > 0 ? '，跳过 $skipped 项（已存在）' : ''}');
  }

  Future<void> _createManually() async {
    String? name;
    final base = widget.baseName;
    if (base != null && base.isNotEmpty) {
      name = await repository.nextSeasonName('$base 第1季');
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditTitlePage(prefill: TitlePrefill(name: name)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkedCount = _checked.length;
    return Scaffold(
      // 输入法弹出时把底部操作条顶上去，避免被键盘盖住。
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(widget.baseName == null ? '添加条目' : '新增一季')),
      // 底栏必须放在 body 里：Scaffold 的 bottomNavigationBar 是按整屏高定位的，
      // 键盘只压缩 body，不会把它顶起来（会被键盘盖住）。
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _controller,
                    autofocus: widget.baseName == null,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: (v) => _search(v.trim()),
                    decoration: InputDecoration(
                      hintText: '搜剧名，例如「仙逆」',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _controller.clear();
                                _onChanged('');
                              },
                            ),
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(child: _buildBody()),
                // 操作条常驻底部：body 高度随键盘收缩，所以它会跟着输入法一起抬高。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _working ? null : _createManually,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('手动创建'),
                          ),
                        ),
                      ),
                      if (checkedCount > 0) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _working ? null : _addChecked,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('添加 $checkedCount 项'),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_working) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: AppTheme.textTertiary),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeNormal,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '可以点下方「手动创建」继续录入',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_searched) {
      return const Center(
        child: Text(
          '输入剧名开始搜索',
          style: TextStyle(
            fontSize: AppTheme.fontSizeNormal,
            color: AppTheme.textTertiary,
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text(
          '豆瓣没找到，可点下方「手动创建」',
          style: TextStyle(
            fontSize: AppTheme.fontSizeNormal,
            color: AppTheme.textTertiary,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _CandidateTile(
        candidate: _results[i],
        checked: _checked.contains(_results[i].externalId),
        onToggle: (v) => setState(() {
          if (v) {
            _checked.add(_results[i].externalId);
          } else {
            _checked.remove(_results[i].externalId);
          }
        }),
        onTap: () => _openSingle(_results[i]),
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.checked,
    required this.onToggle,
    required this.onTap,
  });

  final MetadataCandidate candidate;
  final bool checked;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (candidate.year != null) candidate.year!,
      if (candidate.episode != null) '${candidate.episode} 集',
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 40,
        height: 60,
        child: candidate.coverUrl == null
            ? Container(color: AppTheme.surface)
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                // doubanio 无 Referer 会返回 418，必须带
                child: Image.network(
                  candidate.coverUrl!,
                  headers: const <String, String>{
                    'Referer': 'https://movie.douban.com/',
                  },
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: AppTheme.surface),
                ),
              ),
      ),
      title: Text(
        candidate.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: AppTheme.fontSizeNormal,
          color: AppTheme.textPrimary,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: AppTheme.textTertiary,
              ),
            ),
      trailing: Checkbox(
        value: checked,
        onChanged: (v) => onToggle(v ?? false),
        activeColor: AppTheme.accent,
      ),
      onTap: onTap,
    );
  }
}
