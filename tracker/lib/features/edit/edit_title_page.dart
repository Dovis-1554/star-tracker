import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/db/database.dart';
import '../../main.dart';
import '../../ui/widgets/option_chips.dart';

/// 新建页的预填内容（例如详情页「新增一季」跳转过来时使用）。
class TitlePrefill {
  const TitlePrefill({
    this.name,
    this.type,
    this.platform,
    this.status,
  });

  final String? name;
  final String? type;
  final String? platform;
  final String? status;
}

/// 新建 / 编辑条目。M1 为纯手动录入；M2 会在这之前插入元数据搜索态。
class EditTitlePage extends StatefulWidget {
  const EditTitlePage({super.key, this.item, this.prefill});

  /// 传值则为编辑模式，否则为新建。
  final TitleRow? item;

  /// 新建时的预填值。[item] 非空时忽略。
  final TitlePrefill? prefill;

  bool get isEdit => item != null;

  @override
  State<EditTitlePage> createState() => _EditTitlePageState();
}

class _EditTitlePageState extends State<EditTitlePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _totalController;
  final FocusNode _nameFocus = FocusNode();
  late String _type;
  late String? _platform;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final prefill = widget.prefill;
    _nameController = TextEditingController(
      text: item?.name ?? prefill?.name ?? '',
    );
    _totalController = TextEditingController(
      text: item?.totalEpisodes?.toString() ?? '',
    );
    // comic 与 manga 曾重复显示为「漫画」，旧数据统一归并为 manga。
    _type = item?.type ?? prefill?.type ?? ItemTypes.tv;
    if (_type == ItemTypes.comic) _type = ItemTypes.manga;
    _platform = item?.platform ?? prefill?.platform;
    _status = item?.status ?? prefill?.status ?? ItemStatus.watching;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _totalController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // 连点保护
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题不能为空')),
      );
      return;
    }
    final total = int.tryParse(_totalController.text.trim());

    setState(() => _saving = true);
    // 先收起输入法：安卓上正在输入时，首次点击常被 IME 吞掉，
    // 且 pop 与键盘收起动画同时发生会偶发吞掉返回。
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      if (widget.isEdit) {
        // total 为 null 表示「未知总集数」，保留原值不动。
        await repository.saveEdit(
          id: widget.item!.id,
          name: name,
          type: _type,
          platform: _platform,
          status: _status,
          totalEpisodes: total,
        );
      } else {
        await repository.create(
          name: name,
          type: _type,
          platform: _platform,
          status: _status,
          totalEpisodes: total,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      // 保存失败必须可见：否则按钮只是悄悄恢复，看起来像点了没反应。
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$err')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 标题输入框：本地已有条目联想。输入时按子串匹配，点选回填标题。
  /// 远程（豆瓣）联想属 M2 范围，会以搜索页形式插在这个输入之前。
  Widget _titleField() {
    return StreamBuilder<List<TitleRow>>(
      stream: repository.watchTitles(),
      builder: (context, snapshot) {
        final titles = snapshot.data ?? const <TitleRow>[];
        return RawAutocomplete<TitleRow>(
          textEditingController: _nameController,
          focusNode: _nameFocus,
          displayStringForOption: (t) => t.name,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            if (q.isEmpty) return const <TitleRow>[];
            return titles
                .where((t) => t.id != widget.item?.id)
                .where((t) => t.name.toLowerCase().contains(q))
                .take(8);
          },
          onSelected: (t) {
            _nameController.text = t.name;
            _nameController.selection =
                TextSelection.collapsed(offset: t.name.length);
            _nameFocus.unfocus();
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: !widget.isEdit,
              textInputAction: TextInputAction.done,
              // 键盘「完成」也能保存，作为保存按钮之外的备选路径。
              onSubmitted: (_) => _save(),
              style: const TextStyle(
                fontSize: AppTheme.fontSizeNormal,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(hintText: '请输入剧名'),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: AppTheme.surface,
                elevation: 6,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width - 32,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final t = options.elementAt(i);
                        final subtitle = [
                          ItemTypes.label(t.type),
                          if (t.platform != null) Platforms.label(t.platform!),
                        ].join(' · ');
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(
                            t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppTheme.fontSizeNormal,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: AppTheme.fontSizeBody,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                          onTap: () => onSelected(t),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? '编辑条目' : '新建条目'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FieldLabel('标题'),
            const SizedBox(height: 8),
            _titleField(),
            const SizedBox(height: 20),

            _FieldLabel('类型'),
            const SizedBox(height: 8),
            OptionChips<String>(
              options: ItemTypes.all,
              selected: _type,
              labelOf: ItemTypes.label,
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 20),

            _FieldLabel('平台'),
            const SizedBox(height: 8),
            OptionChips<String?>(
              options: Platforms.all,
              selected: _platform,
              // 平台选填，selected 可能为 null；兜底成「其他」只影响标签显示。
              labelOf: (v) => Platforms.label(v ?? Platforms.other),
              onChanged: (v) => setState(() => _platform = v),
            ),
            const SizedBox(height: 20),

            _FieldLabel('总集数'),
            const SizedBox(height: 8),
            TextField(
              controller: _totalController,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                fontSize: AppTheme.fontSizeNormal,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(hintText: '留空表示未知'),
            ),
            const SizedBox(height: 20),

            _FieldLabel('状态'),
            const SizedBox(height: 8),
            OptionChips<String>(
              options: ItemStatus.all,
              selected: _status,
              labelOf: ItemStatus.label,
              onChanged: (v) => setState(() => _status = v),
            ),
            const SizedBox(height: 32),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: AppTheme.fontSizeBody,
        color: AppTheme.textSecondary,
      ),
    );
  }
}
