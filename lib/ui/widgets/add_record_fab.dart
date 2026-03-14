import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddRecordFab extends StatelessWidget {
  const AddRecordFab({super.key});

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('記録を追加', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.pool, color: Colors.white)),
                title: const Text('トレーニング記録'),
                subtitle: const Text('水中・陸上メニューを入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/training');
                },
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.orangeAccent, child: Icon(Icons.restaurant, color: Colors.white)),
                title: const Text('食事記録'),
                subtitle: const Text('食事・PFCバランスを入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/nutrition');
                },
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.purpleAccent, child: Icon(Icons.monitor_weight, color: Colors.white)),
                title: const Text('体組成記録'),
                subtitle: const Text('体重・筋肉量・体脂肪率を入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/body_composition');
                },
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.pinkAccent, child: Icon(Icons.bedtime, color: Colors.white)),
                title: const Text('睡眠記録'),
                subtitle: const Text('入眠・起床時間を入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  // HomeScreen に実装する睡眠記録ダイアログを呼び出すための通知
                  // 現状は HomeScreen でのみ有効な想定だが、
                  // 将来的には Global な Provider 等で管理することも可能。
                  // ここでは GoRouter で Home に戻ってからダイアログを出す運用を想定。
                  context.go('/home?action=add_sleep');
                },
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.analytics, color: Colors.white)),
                title: const Text('自己分析シート'),
                subtitle: const Text('レース記録・ラップを詳細入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/analysis');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null, // Avoid hero tag exception when multiple screen scaffolds exist
      onPressed: () => _showAddMenu(context),
      child: const Icon(Icons.add),
    );
  }
}
