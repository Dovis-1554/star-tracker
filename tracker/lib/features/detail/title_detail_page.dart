import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../data/repository/title_repository.dart';
import '../../main.dart';
import '../../ui/cover/cover_generator.dart';
import '../edit/edit_title_page.dart';

/// 详情页：同剧各季聚合在一个页面展示。
///
/// 通过 [repository.watchTitles] 订阅全部条目，按基准名（去季号）聚合出
/// 本剧的季列表；「第N季」标签切换当前季，行尾「＋」新增一季。
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
          group = all
              .where((t) => TitleRepository.baseNameOf(t.name) == base)
              .toList()
            ..sort((a, b) => TitleRepository.seasonNoOf(a.name)
                .compareTo(TitleRepository.seasonNoOf(b.name)));
        }
        if (group.isEmpty) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('条目已删除')),
          );
        }
        // 默认停在最后一季；用户手动切换后以选择为准，选中季被删则回退到最后一季。
        TitleRow current;
        if (_picked) {
          try {
            current = group.firstWhere((t) => t.id == _selectedId);
          } on StateError {
            current = group.last;
          }
        } else {
          current = group.last;
          _selectedId = current.id;
        }
        return _DetailBody(
          item: current,
          seasons: group,
          onSwitch: (id) => setState(() {
            _picked = true;
            _selectedId = id;
          }),
        );
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.item,
    required this.seasons,
    required this.onSwitch,
  });

  /// 当前展示的季。
  final TitleRow item;

  /// 同剧全部季（按季号升序）。
  final List<TitleRow> seasons;

  final ValueChanged<String> onSwitch;

  Future<void> _addSeason(BuildContext context) async {
    final name = await repository.nextSeasonName(item.name);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditTitlePage(
          prefill: TitlePrefill(
            name: name,
            type: item.type,
            platform: item.platform,
            status: ItemStatus.watching,
          ),
        ),
      ),
    );
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
            // 季切换行：第N季标签 + 行尾「＋」新增一季
            _SeasonTabs(
              seasons: seasons,
              selectedId: item.id,
              onSwitch: onSwitch,
              onAdd: () => _addSeason(context),
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
  });

  final List<TitleRow> seasons;
  final String selectedId;
  final ValueChanged<String> onSwitch;
  final VoidCallback onAdd;

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
