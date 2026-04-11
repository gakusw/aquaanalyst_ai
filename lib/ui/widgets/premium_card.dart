import 'package:flutter/material.dart';

class PremiumCard extends StatelessWidget {
  final Widget child;
  final IconData? icon;
  final Widget? customIcon;
  final List<Color>? gradientColors;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry? padding;
  final double? margin;

  const PremiumCard({
    super.key,
    required this.child,
    this.icon,
    this.customIcon,
    this.gradientColors,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: EdgeInsets.only(bottom: margin ?? 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors ?? (isDark 
            ? [
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                colorScheme.surface.withValues(alpha: 0.4),
              ]
            : [
                colorScheme.surface,
                colorScheme.secondaryContainer.withValues(alpha: 0.2),
              ]),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (customIcon != null || icon != null)
            Positioned(
              right: -20,
              top: -20,
              child: Opacity(
                opacity: 0.05,
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: customIcon ?? Icon(
                    icon,
                    size: 100,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: padding ?? const EdgeInsets.all(20.0),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
