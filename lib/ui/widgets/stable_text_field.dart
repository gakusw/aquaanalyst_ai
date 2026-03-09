import 'package:flutter/material.dart';

/// コーチ画面（チャット欄）と同様の、安定したマルチライン入力フィールド
/// 高さが固定され、内部でスクロールするため、IME変換がレイアウト変更で解除されるのを防ぎます。
class StableTextField extends StatelessWidget {
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
    this.lines = 3,
    this.keyboardType = TextInputType.multiline,
    this.textInputAction = TextInputAction.newline,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelText != null) ...[
          Text(
            labelText!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: TextField(
            controller: controller,
            minLines: lines,
            maxLines: lines, // 高さを完全に固定
            textAlignVertical: TextAlignVertical.top,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hintText,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
