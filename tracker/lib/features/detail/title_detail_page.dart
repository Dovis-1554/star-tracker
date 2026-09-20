import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/repository/title_repository.dart';
import '../../main.dart';
import '../../ui/cover/cover_generator.dart';
import '../edit/edit_title_page.dart';
import '../search/search_title_page.dart';

/// 详情页多季列表的排序方式。存 shared_preferences（key: detail.seasonSort）。
abstract final class SeasonSort {
  /// 按上映年份升序（默认）——第 1 季在最前，与搜索结果的排序一致。
  static const year = 'year';

  /// 按季号升序。
  static const no = 'no';

  /// 按添加时间升序，先录入的在前。
  static const added = 'added';

  static const all = <String>[year, no, added];

  static String label(String v) => switch (v) {
        year => '上映年份',
        no => '季号',
        _ => '添加时间',
      };
}

/// 详情页：同剧各季聚合在一个页面展示。
///
/// 通过 [repository.watchTitles] 订阅全部条目，按基准名（去季号）聚合出
/// 本剧的季列表；「第N季」标签切换当前季，行尾「＋」新增一季、排序按钮调季序。
/// 数据仍是一季一条记录，这里只做聚合展示。
class TitleDetailPage extends StatefulWidget {
  const TitleDetailPage({super.key, required this.item});

  /// 进入详情页时定位到的条目（某季）。
  final TitleRow item;

  @override
  State<TitleDetailPage> createState() => _TitleDetailPageState();
}

class _TitleDetailPageState extends State<TitleDetailPage> {
  late String _selectedId = widget.item.id;

  /// 用户手动切过季后就尊重他的选择；没切过则一直停在最后一季。
  bool _picked = false;

  String _seasonSort = SeasonSort.year;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _seasonSort = p.getString('detail.seasonSort') ?? _seasonSort);
    });
  }

  Future<void> _setSeasonSort(String v) async {
    setState(() => _seasonSort = v);
    final p = await SharedPreferences.getInstance();
    await p.setString('detail.seasonSort', v);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TitleRow>>(
      stream: repository.watchTitles(),
      builder: (context, snapshot) {
        final all = snapshot.data;
        // 首帧流未到时先按单条渲染，避免闪「已删除」。
        final List<TitleRow> group;
        if (all == null) {
          group = [widget.item];
        } else {
          final base = TitleRepository.baseNameOf(widget.item.name);
          group = _sortSeasons(
            all.where((t) => TitleRepository.baseNameOf(t.name) == base).toList(),
            _seasonSort,
          );
        }
        if (group.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('条目已删除')),
          );
        }
        // 默认停在最后一季（季号最大）；用户手动切换后以选择为准，
        // 选中季被删则回退到最后一季。这里不取列表末尾——列表顺序会随排序方式变。
        TitleRow current;
        if (_picked) {
          try {
            current = group.firstWhere((t) => t.id == _selectedId);
          } on StateError {
            current = _latestSeason(group);
          }
        } else {
          current = _latestSeason(group);
          _selectedId = current.id;
        }
        return _DetailBody(
          item: current,
          seasons: group,
          seasonSort: _seasonSort,
          onSeasonSortChanged: _setSeasonSort,
          onSwitch: (id) => setState(() {
            _picked = true;
            _selectedId = id;
          }),
        );
      },
    );
  }

  /// 「最后一季」= 季号最大的一季（季号相同取最近更新的），与展示顺序无关。
  TitleRow _latestSeason(List<TitleRow> seasons) {
    final ordered = [...seasons]..sort((a, b) {
      final c = TitleRepository.seasonNoOf(a.name)
          .compareTo(TitleRepository.seasonNoOf(b.name));
      return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
    });
    return ordered.last;
  }
}

List<TitleRow> _sortSeasons(List<TitleRow> list, String mode) {
  final out = [...list];
  int byNo(TitleRow a, TitleRow b) =>
      TitleRepository.seasonNoOf(a.name).compareTo(TitleRepository.seasonNoOf(b.name));

  switch (mode) {
    case SeasonSort.no:
      out.sort(byNo);
      break;
    case SeasonSort.added:
      out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      break;
    default:
      // 上映年份升序；缺年份的排最后；同年按季号兜底。
      out.sort((a, b) {
        final ay = a.releaseDate;
        final by = b.releaseDate;
        if (ay == null && by == null) return byNo(a, b);
        if (ay == null) return 1;
        if (by == null) return -1;
        final c = ay.compareTo(by);
        return c != 0 ? c : byNo(a, b);
      });
  }
  return out;
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.item,
    required this.seasons,
    required this.onSwitch,
    required this.seasonSort,
    required this.onSeasonSortChanged,
  });

  /// 当前展示的季。
  final TitleRow item;

  /// 同剧全部季，顺序由 [seasonSort] 决定。
  final List<TitleRow> seasons;

  final ValueChanged<String> onSwitch;
  final String seasonSort;
  final ValueChanged<String> onSeasonSortChanged;

  /// 新增一季走豆瓣搜索（关键词预填基准剧名），搜不到可退回手动创建。
  Future<void> _addSeason(BuildContext context) async {
    final base = TitleRepository.baseNameOf(item.name);
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => SearchTitlePage(baseName: base),
      ),
    );
    if (msg == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EditTitlePage(item: item),
              ),
            ),
            child: const Text(
              '编辑',
              style: TextStyle(fontSize: AppTheme.fontSizeBody),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                await repository.softDelete(item.id);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'delete', child: Text('删除本季')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(item: item),
            // 季切换行：第N季标签 + 行尾排序、新增一季
            _SeasonTabs(
              seasons: seasons,
              selectedId: item.id,
              onSwitch: onSwitch,
              onAdd: () => _addSeason(context),
              seasonSort: seasonSort,
              onSeasonSortChanged: onSeasonSortChanged,
            ),
            const SizedBox(height: 12),
            _Progress(item: item),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '点击切换单集 · 长按标记之前全部已看',
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _EpisodeGrid(
                key: ValueKey(item.id), // 切季时重置滚动位置
                titleId: item.id,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => repository.markNextWatched(item.id),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('标记下一集已看'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 季切换行。每季一个标签，行尾「＋」新增。
class _SeasonTabs extends StatelessWidget {
  const _SeasonTabs({
    required this.seasons,
    required this.selectedId,
    required this.onSwitch,
    required this.onAdd,
    required this.seasonSort,
    required this.onSeasonSortChanged,
  });

  final List<TitleRow> seasons;
  final String selectedId;
  final ValueChanged<String> onSwitch;
  final VoidCallback onAdd;
  final String seasonSort;
  final ValueChanged<String> onSeasonSortChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in seasons)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => onSwitch(s.id),
                        child: _Tag(
                          text: '第${TitleRepository.seasonNoOf(s.name)}季',
                          active: s.id == selectedId,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 只有多于一季时排序才有意义
          if (seasons.length > 1)
            PopupMenuButton<String>(
              tooltip: '季排序',
              icon: const Icon(Icons.sort, size: 20),
              onSelected: onSeasonSortChanged,
              itemBuilder: (_) => [
                for (final s in SeasonSort.all)
                  PopupMenuItem<String>(
                    value: s,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: s == seasonSort
                              ? const Icon(Icons.check,
                                  size: 14, color: AppTheme.accent)
                              : null,
                        ),
                        Text(SeasonSort.label(s)),
                      ],
                    ),
                  ),
              ],
            ),
          IconButton(
            tooltip: '新增一季',
            icon: const Icon(Icons.add),
            color: AppTheme.accent,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final TitleRow item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GeneratedCover(title: item.name, path: item.coverPath, width: 80),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 展示基准剧名（不带季号），具体季由标签行表达
                Text(
                  TitleRepository.baseNameOf(item.name),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ItemTypes.label(item.type),
                  style: const TextStyle(
                    fontSize: AppTheme.fontSizeBody,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    if (item.platform != null) _Tag(text: Platforms.label(item.platform!)),
                    _Tag(
                      text: ItemStatus.label(item.status),
                      active: item.status == ItemStatus.watching,
                    ),
                  ],
                ),
                if (item.score != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '评分 ${item.score}',
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeBody,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.active = false});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: active ? AppTheme.accent : AppTheme.border,
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.fontSizeBody,
          color: active ? AppTheme.accent : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.item});

  final TitleRow item;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EpisodeRow>>(
      stream: repository.watchEpisodes(item.id),
      builder: (context, snapshot) {
        final list = snapshot.data ?? const <EpisodeRow>[];
        final watched = list.where((e) => e.watched == 1).length;
        final total = item.totalEpisodes ?? list.length;
        final ratio = total > 0 ? (watched / total).clamp(0.0, 1.0) : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已看 $watched / $total',
                style: const TextStyle(
                  fontSize: AppTheme.fontSizeBody,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: AppTheme.surface,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({super.key, required this.titleId});

  final String titleId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EpisodeRow>>(
      stream: repository.watchEpisodes(titleId),
      builder: (context, snapshot) {
        final list = snapshot.data ?? const <EpisodeRow>[];
        if (list.isEmpty) {
          return Center(
            child: Text(
              '未设置总集数',
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: AppTheme.textTertiary,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            // 2.0 = 宽高比 2:1，宽度不变、竖向高度减半（长方形）
            childAspectRatio: 2.0,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final e = list[i];
            final watched = e.watched == 1;
            return GestureDetector(
              onTap: () => repository.setEpisodeWatched(e, watched: !watched),
              onLongPress: () async {
                await repository.markUpToWatched(e);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已把第 1 到第 ${e.no} 集标记为已看')),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: watched ? AppTheme.accent : AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${e.no}',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeBody,
                    color: watched ? AppTheme.onAccent : AppTheme.textTertiary,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
