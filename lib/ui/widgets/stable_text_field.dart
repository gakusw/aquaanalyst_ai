import 'package:flutter/material.dart';

/// 極めてシンプルかつ IME が安定したマルチライン入力フィールド
/// 自動伸長 (minLines 1 -> maxLines N) をサポートしつつ、
/// デザイン上の無駄（過剰な背景や余白）を排除した最小限のスタイルを提供します。
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
  // TextField の状態を安定させるための Key
  final GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Theme(
      // 背景色や境界線の無駄を削ぎ落とした最小限のテーマ設定
      data: Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.labelText != null) ...[
            Text(
              widget.labelText!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
          ],
          TextField(
            key: _key,
            controller: widget.controller,
            minLines: 1, // 1行から開始（無駄な空白を作らない）
            maxLines: widget.lines, // 内容に応じて増え、上限でスクロール
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            style: const TextStyle(fontSize: 16, height: 1.4),
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: Theme.of(context).hintColor.withOpacity(0.4),
                fontSize: 15,
              ),
              // 下線のみのシンプルなデザイン（無駄のない洗練されたスタイル）
              border: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).dividerColor,
                ),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).dividerColor.withOpacity(0.5),
                ),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}
