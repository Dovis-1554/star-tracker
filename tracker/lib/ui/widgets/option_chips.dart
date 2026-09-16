import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 单选 chips 组。类型 / 平台 / 状态 / 筛选都用它。
///
/// 泛型 [T] 允许选项是 `String?`（例如筛选栏的「全部」= null）。
class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> options;

  /// 当前选中项。`T` 可空时，null 表示「全部 / 未选」。
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in options)
          ChoiceChip(
            label: Text(
              labelOf(value),
              style: TextStyle(
                fontSize: AppTheme.fontSizeBody,
                color: selected == value ? AppTheme.onAccent : AppTheme.textSecondary,
              ),
            ),
            selected: selected == value,
            showCheckmark: false,
            onSelected: (_) => onChanged(value),
            backgroundColor: AppTheme.surface,
            selectedColor: AppTheme.accent,
            shape: const StadiumBorder(
              side: BorderSide(color: AppTheme.border, width: 0.5),
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
