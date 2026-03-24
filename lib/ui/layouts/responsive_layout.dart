import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/add_record_fab.dart';

class ResponsiveLayout extends StatefulWidget {
  final Widget child;

  const ResponsiveLayout({super.key, required this.child});

  @override
  State<ResponsiveLayout> createState() => _ResponsiveLayoutState();
}

class _ResponsiveLayoutState extends State<ResponsiveLayout> {

  Widget _buildAppIcon(BuildContext context, {required bool isSelected, double size = 40}) {
    final color = isSelected 
        ? Theme.of(context).colorScheme.primary 
        : Theme.of(context).colorScheme.onSurfaceVariant;
    
    // 背景（ネイビー）を切り取った新画像を使用
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        'assets/images/app_icon_nav.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      ),
    );
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/weekly')) return 1;
    if (location.startsWith('/agent')) return 2;
    if (location.startsWith('/insight')) return 3;
    if (location.startsWith('/settings') || location.startsWith('/admin')) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0: context.go('/home'); break;
      case 1: context.go('/weekly'); break;
      case 2: context.go('/agent'); break;
      case 3: context.go('/insight'); break;
      case 4: context.go('/settings'); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    // モバイル用（BottomAppBar）のデスティネーション定義
    final mobileDestinations = <NavigationDestinationData>[
      NavigationDestinationData(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'ホーム'),
      NavigationDestinationData(icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: '週間計画'),
      NavigationDestinationData(
        icon: Icons.psychology_outlined, 
        selectedIcon: Icons.psychology, 
        label: 'コーチに相談',
        customIcon: _buildAppIcon(context, isSelected: false, size: 32),
        customSelectedIcon: _buildAppIcon(context, isSelected: true, size: 32),
      ),
      NavigationDestinationData(icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'インサイト'),
      NavigationDestinationData(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '設定'),
    ];

    // PC用（NavigationRail）のデスティネーション定義
    final railDestinations = <NavigationDestinationData>[
      NavigationDestinationData(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'ホーム'),
      NavigationDestinationData(icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: '週間計画'),
      NavigationDestinationData(
        icon: Icons.psychology_outlined, 
        selectedIcon: Icons.psychology, 
        label: 'コーチに相談',
        customIcon: _buildAppIcon(context, isSelected: false, size: 26),
        customSelectedIcon: _buildAppIcon(context, isSelected: true, size: 26),
      ),
      NavigationDestinationData(icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'インサイト'),
      NavigationDestinationData(icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: '設定'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget layout;
        if (constraints.maxWidth >= 600) {
          // ===== PC/タブレット: NavigationRail =====
          layout = Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  // 常にFABを表示
                  leading: const Padding(padding: EdgeInsets.only(bottom: 8.0, top: 4.0), child: AddRecordFab()),
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => _onItemTapped(index, context),
                  labelType: NavigationRailLabelType.all,
                  destinations: railDestinations
                      .map((d) => NavigationRailDestination(
                            icon: SizedBox(width: 32, height: 32, child: d.customIcon ?? Icon(d.icon, size: 28)),
                            selectedIcon: SizedBox(width: 32, height: 32, child: d.customSelectedIcon ?? Icon(d.selectedIcon, size: 28)),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: widget.child),
              ],
            ),
          );
        } else {
          // ===== スマホ: 全タブ同列のBottomAppBar =====
          layout = Scaffold(
            body: widget.child,
            bottomNavigationBar: BottomAppBar(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
              height: 72,
              clipBehavior: Clip.none,
              elevation: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. ホーム (左端)
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: mobileDestinations[0].icon,
                      selectedIcon: mobileDestinations[0].selectedIcon,
                      label: mobileDestinations[0].label,
                      selected: selectedIndex == 0,
                      onTap: () => _onItemTapped(0, context),
                    ),
                  ),
                  // 2. 週間計画
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: mobileDestinations[1].icon,
                      selectedIcon: mobileDestinations[1].selectedIcon,
                      label: mobileDestinations[1].label,
                      selected: selectedIndex == 1,
                      onTap: () => _onItemTapped(1, context),
                    ),
                  ),
                  // 3. FAB (中央)
                  const Expanded(
                    child: Center(
                      child: AddRecordFab(),
                    ),
                  ),
                  // 4. コーチ
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: mobileDestinations[2].icon,
                      selectedIcon: mobileDestinations[2].selectedIcon,
                      customIcon: mobileDestinations[2].customIcon,
                      customSelectedIcon: mobileDestinations[2].customSelectedIcon,
                      label: mobileDestinations[2].label,
                      selected: selectedIndex == 2,
                      onTap: () => _onItemTapped(2, context),
                    ),
                  ),
                  // 5. インサイト
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: mobileDestinations[3].icon,
                      selectedIcon: mobileDestinations[3].selectedIcon,
                      label: mobileDestinations[3].label,
                      selected: selectedIndex == 3,
                      onTap: () => _onItemTapped(3, context),
                    ),
                  ),
                  // 6. 設定
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: mobileDestinations[4].icon,
                      selectedIcon: mobileDestinations[4].selectedIcon,
                      label: mobileDestinations[4].label,
                      selected: selectedIndex == 4,
                      onTap: () => _onItemTapped(4, context),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return layout;
      },
    );
  }
}

/// スマホ用 BottomAppBar の個別アイテム
class _BottomAppBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final Widget? customIcon;
  final Widget? customSelectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomAppBarItem({
    required this.icon,
    required this.selectedIcon,
    this.customIcon,
    this.customSelectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconData = selected ? selectedIcon : icon;
    final iconColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final textColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    Widget iconWidget;
    if (selected && customSelectedIcon != null) {
      iconWidget = customSelectedIcon!;
    } else if (!selected && customIcon != null) {
      iconWidget = customIcon!;
    } else {
      iconWidget = Icon(iconData, color: iconColor, size: 28);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 40, 
              child: Center(child: iconWidget),
            ),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class NavigationDestinationData {
  final IconData icon;
  final IconData selectedIcon;
  final Widget? customIcon;
  final Widget? customSelectedIcon;
  final String label;

  NavigationDestinationData({
    required this.icon,
    required this.selectedIcon,
    this.customIcon,
    this.customSelectedIcon,
    required this.label,
  });
}
