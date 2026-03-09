import 'package:flutter/material.dart';

/// コーチ画面のような「枠」を持ちつつ、極限までスリムで安定したマルチライン入力フィールド。
/// 右端に到達すると自動で改行され、縦に伸びる挙動を徹底しています。
class StableTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final int lines;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;

  const StableTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.lines = 5,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction = TextInputAction.newline,
    this.onChanged,
  });

  @override
  State<StableTextField> createState() => _StableTextFieldState();
}

class _StableTextFieldState extends State<StableTextField> {
  // TextField の実体を固定し、レイアウト変更（改行）時の IME 解除を防ぐための Key
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              widget.labelText!,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.primary.withOpacity(0.8),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        // 幅を固定（親に追従）させるための制約
        Container(
          width: double.infinity, 
          decoration: BoxDecoration(
            // 非常に薄い背景をつけることで「無駄のない枠」を表現
            color: colorScheme.surfaceVariant.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            key: _key,
            controller: widget.controller,
            // 1行から開始し、指定された lines まで自動で伸びる
            minLines: 1,
            maxLines: widget.lines > 1 ? widget.lines : 1, 
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            style: const TextStyle(fontSize: 15, height: 1.4),
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: theme.hintColor.withOpacity(0.35),
                fontSize: 14,
              ),
              // 視覚的な「右端」を提示するための非常に薄い枠線
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.05)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.primary.withOpacity(0.3), width: 1),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
