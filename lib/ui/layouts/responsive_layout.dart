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

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/home')) return 0;
    if (location.startsWith('/weekly')) return 1;
    if (location.startsWith('/agent')) return 2;
    if (location.startsWith('/insight')) return 3;
    if (location.startsWith('/settings')) return 4;
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

    // 共通のデスティネーション定義 (5タブ: Home / Weekly / Coach / Insight / Settings)
    final destinations = <NavigationDestinationData>[
      NavigationDestinationData(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'ホーム'),
      NavigationDestinationData(icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: '週間計画'),
      NavigationDestinationData(icon: Icons.psychology_outlined, selectedIcon: Icons.psychology, label: 'コーチ'),
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
                  destinations: destinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
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
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              height: 76,
              elevation: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 1. ホーム (左端)
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: selectedIndex == 0 ? Icons.home : Icons.home_outlined,
                      label: 'ホーム',
                      selected: selectedIndex == 0,
                      onTap: () => _onItemTapped(0, context),
                    ),
                  ),
                  // 2. 週間計画
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: selectedIndex == 1 ? Icons.calendar_month : Icons.calendar_month_outlined,
                      label: '週間計画',
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
                      icon: selectedIndex == 2 ? Icons.psychology : Icons.psychology_outlined,
                      label: 'コーチ',
                      selected: selectedIndex == 2,
                      onTap: () => _onItemTapped(2, context),
                    ),
                  ),
                  // 5. インサイト
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: selectedIndex == 3 ? Icons.insights : Icons.insights_outlined,
                      label: 'インサイト',
                      selected: selectedIndex == 3,
                      onTap: () => _onItemTapped(3, context),
                    ),
                  ),
                  // 6. 設定
                  Expanded(
                    child: _BottomAppBarItem(
                      icon: selectedIndex == 4 ? Icons.settings : Icons.settings_outlined,
                      label: '設定',
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
  final String label;
  final bool selected;
  final bool isProminent;
  final VoidCallback onTap;

  const _BottomAppBarItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.isProminent = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color iconColor;
    Color? bgColor;

    if (isProminent) {
      bgColor = selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.secondaryContainer;
      iconColor = selected
          ? Theme.of(context).colorScheme.onPrimary
          : Theme.of(context).colorScheme.onSecondaryContainer;
    } else {
      iconColor = selected
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant;
    }

    final textColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isProminent)
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              )
            else
              Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: textColor, fontSize: 10, fontWeight: isProminent ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class NavigationDestinationData {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  NavigationDestinationData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
