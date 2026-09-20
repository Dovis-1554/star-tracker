import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/repository/title_repository.dart';
import '../../main.dart';
import '../../ui/cover/cover_generator.dart';
import '../../ui/widgets/option_chips.dart';
import '../detail/title_detail_page.dart';
import '../search/search_title_page.dart';

/// 片单页：封面墙 / 列表双视图 + 状态筛选。
///
/// 排序固定为「按打开（最后修改）时间倒序」；多季的排序放在详情页。
class TitleListPage extends StatefulWidget {
  const TitleListPage({super.key});

  @override
  State<TitleListPage> createState() => _TitleListPageState();
}

class _TitleListPageState extends State<TitleListPage> {
  bool _grid = true;
  int _columns = 2; // 封面墙列数，2-5 可调
  String? _status; // null 表示「全部」

  /// 每个分类一页，左右滑动切换；顶部 chips 与它双向同步。
  static final List<String?> _pages = <String?>[null, ...ItemStatus.all];

  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _grid = p.getBool('view.grid') ?? _grid;
        _columns = p.getInt('grid.columns') ?? _columns;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _persistView() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('view.grid', _grid);
    await p.setInt('grid.columns', _columns);
  }

  // ---------- 长按多选删除 ----------

  /// 多选模式下选中的是「整部剧」，键为基准名（去季号）。
  /// 首页一张卡 = 一部剧，删除时该剧所有季一起删。
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggleSelected(String base) => setState(() {
        if (_selected.contains(base)) {
          _selected.remove(base);
          if (_selected.isEmpty) _selecting = false;
        } else {
          _selected.add(base);
        }
      });

  void _enterSelection(String base) => setState(() {
        _selecting = true;
        _selected.add(base);
      });

  Future<void> _deleteSelected() async {
    final bases = _selected.toList()..sort();
    final all = await repository.allTitles();
    if (!mounted) return;
    final doomed = all
        .where((t) => bases.contains(TitleRepository.baseNameOf(t.name)))
        .toList();
    if (doomed.isEmpty) {
      _exitSelection();
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除选中条目'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final b in bases)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· $b',
                  style: const TextStyle(
                    fontSize: AppTheme.fontSizeBody,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '连同各季共 ${doomed.length} 条记录一起删除，不可恢复。',
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '删除',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    for (final t in doomed) {
      await repository.softDelete(t.id);
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 ${bases.length} 部剧（${doomed.length} 条记录）'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                tooltip: '退出多选',
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              )
            : null,
        title: Text(_selecting ? '已选 ${_selected.length} 部' : '追剧'),
        actions: [
          if (_selecting)
            IconButton(
              tooltip: '删除所选',
              icon: const Icon(Icons.delete_outline),
              onPressed: _selected.isEmpty ? null : _deleteSelected,
            )
          else ...[
          PopupMenuButton<int>(
            tooltip: '封面列数',
            icon: const Icon(Icons.view_column_outlined),
            onSelected: (v) {
              setState(() => _columns = v);
              _persistView();
            },
            itemBuilder: (_) => [
              for (final n in const [2, 3, 4, 5])
                PopupMenuItem<int>(
                  value: n,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: n == _columns
                            ? const Icon(Icons.check,
                                size: 16, color: AppTheme.accent)
                            : null,
                      ),
                      Text('$n 列'),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: _grid ? '切换为列表' : '切换为封面墙',
            icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
            onPressed: () {
              setState(() => _grid = !_grid);
              _persistView();
            },
          ),
          ],
        ],
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
        backgroundColor: AppTheme.accent,
        foregroundColor: AppTheme.onAccent,
        onPressed: () async {
          final msg = await Navigator.of(context).push<String>(
            MaterialPageRoute<String>(
              builder: (_) => const SearchTitlePage(),
            ),
          );
          if (msg == null || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: OptionChips<String?>(
              options: _pages,
              selected: _status,
              labelOf: (v) => v == null ? '全部' : ItemStatus.label(v),
              onChanged: (v) {
                setState(() => _status = v);
                _pageController.animateToPage(
                  _pages.indexOf(v),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              },
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (i) => setState(() => _status = _pages[i]),
              children: [
                for (final s in _pages)
                  _CategoryPage(
                    status: s,
                    grid: _grid,
                    columns: _columns,
                    selecting: _selecting,
                    selected: _selected,
                    onToggle: _toggleSelected,
                    onLongPress: _enterSelection,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个分类页。首页的每一屏就是一个分类，左右滑动在分类间切换。
class _CategoryPage extends StatelessWidget {
  const _CategoryPage({
    required this.status,
    required this.grid,
    required this.columns,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final String? status;
  final bool grid;
  final int columns;
  final bool selecting;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onLongPress;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TitleRow>>(
      // 一律订阅全部条目：分类是在「整部剧」层面判定的。
      // 若直接在 SQL 里按 status 过滤，旧季（已看）与新季（在看）会各命中一页，
      // 同一部剧就同时出现在两个分类里。
      stream: repository.watchTitles(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        // 同剧各季在首页只保留一张卡，点进去仍是多季详情页。
        final groups = _groupSeasons(snapshot.data!);
        final items = <TitleRow>[
          for (final g in groups)
            if (status == null || _showStatus(g) == status) _pickRepresentative(g),
        ];
        if (items.isEmpty) {
          return Center(
            child: Text(
              status == null
                  ? '还没有条目，点右下角 + 添加'
                  : '「${ItemStatus.label(status!)}」里还没有条目',
              style: const TextStyle(
                fontSize: AppTheme.fontSizeNormal,
                color: AppTheme.textTertiary,
              ),
            ),
          );
        }
        return StreamBuilder<Map<String, int>>(
          stream: db.watchWatchedCounts(),
          builder: (context, countSnapshot) {
            final counts = countSnapshot.data ?? const <String, int>{};
            return grid
                ? _CoverWall(
                    items: items,
                    counts: counts,
                    columns: columns,
                    selecting: selecting,
                    selected: selected,
                    onToggle: onToggle,
                    onLongPress: onLongPress,
                  )
                : _TitleListView(
                    items: items,
                    counts: counts,
                    selecting: selecting,
                    selected: selected,
                    onToggle: onToggle,
                    onLongPress: onLongPress,
                  );
          },
        );
      },
    );
  }
}

/// 按基准名（去季号）把各季分组，组内按季号升序；组间按「本组最后修改时间」倒序。
///
/// 首页一直按打开（最后修改）时间排——最近动过的剧在最前。
/// 多季内部的排序不在这里做，交给详情页（见 [SeasonSort]）。
List<List<TitleRow>> _groupSeasons(List<TitleRow> all) {
  final groups = <String, List<TitleRow>>{};
  for (final t in all) {
    groups.putIfAbsent(TitleRepository.baseNameOf(t.name), () => <TitleRow>[]).add(t);
  }

  final result = <List<TitleRow>>[];
  for (final seasons in groups.values) {
    final ordered = [...seasons]
      ..sort((a, b) => TitleRepository.seasonNoOf(a.name)
          .compareTo(TitleRepository.seasonNoOf(b.name)));
    result.add(ordered);
  }

  int lastUpdated(List<TitleRow> g) =>
      g.fold<int>(0, (m, t) => t.updatedAt > m ? t.updatedAt : m);

  result.sort((a, b) {
    // 排序键取组内最后修改时间；时间相同的按剧名稳定排序，避免刷新后顺序乱跳。
    final c = lastUpdated(b).compareTo(lastUpdated(a));
    return c != 0
        ? c
        : TitleRepository.baseNameOf(a.first.name)
            .compareTo(TitleRepository.baseNameOf(b.first.name));
  });
  return result;
}

/// 整部剧对外呈现的状态 = **最后一季**的状态。
///
/// 一季一条记录，旧季可能是「已看」、新季是「在看」；整部剧只算一个状态，
/// 否则它会在两个分类页里各出现一次。
String _showStatus(List<TitleRow> seasons) => seasons.last.status;

/// 卡片代表季：取最后一季，与详情页默认停最后一季保持一致。
TitleRow _pickRepresentative(List<TitleRow> seasons) => seasons.last;

class _CoverWall extends StatelessWidget {
  const _CoverWall({
    required this.items,
    required this.counts,
    required this.columns,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final List<TitleRow> items;
  final Map<String, int> counts;
  final int columns;
  final bool selecting;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onLongPress;

  @override
  Widget build(BuildContext context) {
    // 封面固定 2:3（AspectRatio 保证不裁切），文字区预留固定高度，
    // 因此格子纵横比 = 宽 / (封面高 + 文字区)，随列数动态计算。
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        const textAreaHeight = 46.0;
        final cellW =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final aspect = cellW / (cellW / AppTheme.coverAspect + textAreaHeight);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: 16,
            childAspectRatio: aspect,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final t = items[i];
            return _CoverCard(
              item: t,
              watched: counts[t.id] ?? 0,
              selecting: selecting,
              checked: selected.contains(TitleRepository.baseNameOf(t.name)),
              onToggle: onToggle,
              onLongPress: onLongPress,
            );
          },
        );
      },
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({
    required this.item,
    required this.watched,
    required this.selecting,
    required this.checked,
    required this.onToggle,
    required this.onLongPress,
  });

  final TitleRow item;
  final int watched;
  final bool selecting;
  final bool checked;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onLongPress;

  @override
  Widget build(BuildContext context) {
    final total = item.totalEpisodes;
    final base = TitleRepository.baseNameOf(item.name);
    return GestureDetector(
      onTap: () {
        if (selecting) {
          onToggle(base);
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => TitleDetailPage(item: item)),
        );
      },
      onLongPress: () => onLongPress(base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 固定 2:3，占位图与远程封面都不会被裁切或压扁
          AspectRatio(
            aspectRatio: AppTheme.coverAspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GeneratedCover(
                  title: item.name,
                  path: item.coverPath,
                ),
                if (selecting)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _SelectMark(checked: checked),
                  ),
                if (checked)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0x331D9E75),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(color: AppTheme.accent, width: 1.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TitleRepository.baseNameOf(item.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTheme.fontSizeNormal,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  total == null ? ItemStatus.label(item.status) : '$watched / $total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTheme.fontSizeBody,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 多选模式下的勾选标记（未选空心圆、已选绿色对勾）。
class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? AppTheme.accent : const Color(0x99000000),
        border: Border.all(
          color: checked ? AppTheme.accent : AppTheme.border,
          width: 1.2,
        ),
      ),
      child: checked
          ? const Icon(Icons.check, size: 14, color: AppTheme.onAccent)
          : null,
    );
  }
}

class _TitleListView extends StatelessWidget {
  const _TitleListView({
    required this.items,
    required this.counts,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final List<TitleRow> items;
  final Map<String, int> counts;
  final bool selecting;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onLongPress;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = items[i];
        final total = t.totalEpisodes;
        final platform = t.platform;
        final base = TitleRepository.baseNameOf(t.name);
        final checked = selected.contains(base);
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: selecting
              ? SizedBox(
                  width: 40,
                  child: Center(child: _SelectMark(checked: checked)),
                )
              : GeneratedCover(
                  title: t.name,
                  path: t.coverPath,
                  width: 40,
                ),
          title: Text(
            TitleRepository.baseNameOf(t.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTheme.fontSizeNormal,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            [
              if (platform != null) Platforms.label(platform),
              if (total != null) '${counts[t.id] ?? 0} / $total',
            ].join(' · '),
            style: const TextStyle(
              fontSize: AppTheme.fontSizeBody,
              color: AppTheme.textTertiary,
            ),
          ),
          trailing: selecting
              ? (checked
                  ? const Icon(Icons.check_circle, color: AppTheme.accent, size: 20)
                  : const Icon(Icons.radio_button_unchecked,
                      color: AppTheme.textTertiary, size: 20))
              : _StatusBadge(status: t.status),
          selected: checked,
          onTap: () {
            if (selecting) {
              onToggle(base);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => TitleDetailPage(item: t)),
            );
          },
          onLongPress: () => onLongPress(base),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final active = status == ItemStatus.watching;
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
        ItemStatus.label(status),
        style: TextStyle(
          fontSize: AppTheme.fontSizeBody,
          color: active ? AppTheme.accent : AppTheme.textSecondary,
        ),
      ),
    );
  }
}
