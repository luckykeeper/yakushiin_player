// yakushiin_player
// @CreateTime    : 2025/05/03 10:21
// @Author        : Luckykeeper
// @Email         : luckykeeper@luckykeeper.site
// @Project       : yakushiin_player

import 'package:flutter/material.dart';
import 'package:yakushiin_player/theme/font.dart';

/// 自定义开关组件
/// - 左侧“关”，右侧“开”
/// - 激活侧文字显示绿色，非激活侧显示红色
/// - 底部 description 为说明性文字
/// - 支持 [leading] 占位组件（如 Icon），以对齐 TextFormField 的 icon
/// - 支持 [crossAxisAlignment] 控制列内对齐方式
/// - 支持 [padding] 外部边距
class CustomSwitchWithDescription extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String description;
  final Widget? leading;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsetsGeometry? padding;

  const CustomSwitchWithDescription({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    required this.description,
    this.leading,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 左侧占位组件（通常为图标，与 TextFormField 的 icon 对齐）
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              SizedBox(width: 10),
              Text(title, style: styleFontSimkaiBold),
              SizedBox(width: 10),
              // 左侧“关”
              GestureDetector(
                onTap: () {
                  if (!value && onChanged != null) {
                    onChanged!(true);
                  }
                },
                child: Text(
                  '关',
                  style: TextStyle(
                    color: value ? Colors.pink[300] : Colors.green[300],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: fontSimkaiFamily,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Material Switch
              Switch(value: value, onChanged: onChanged),
              const SizedBox(width: 8),
              // 右侧“开”
              GestureDetector(
                onTap: () {
                  if (value && onChanged != null) {
                    onChanged!(false);
                  }
                },
                child: Text(
                  '开',
                  style: TextStyle(
                    color: value ? Colors.green[300] : Colors.pink[300],
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: fontSimkaiFamily,
                  ),
                ),
              ),
            ],
          ),
          // const SizedBox(height: 6),
          // 说明文字
          Text(
            description,
            style: const TextStyle(fontSize: 12, fontFamily: fontSimkaiFamily),
          ),
        ],
      ),
    );
  }
}
