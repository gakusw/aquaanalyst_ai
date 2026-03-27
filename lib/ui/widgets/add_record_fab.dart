import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/app_colors.dart';
import 'training_form.dart';
import 'nutrition_form.dart';
import 'body_composition_form.dart';
import '../screens/analysis_sheet_form.dart';

class AddRecordFab extends StatelessWidget {
  const AddRecordFab({super.key});

  void _showFormDialog({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required Widget Function(BuildContext dialogContext, GlobalKey<dynamic> key) formBuilder,
  }) {
    final GlobalKey<dynamic> formKey = GlobalKey();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: formBuilder(ctx, formKey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          (() {
            bool isSaving = false;
            return StatefulBuilder(
              builder: (ctx, setBtnState) {
                return ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    // 各Stateの公開メソッドを安全に呼び出す
                    final state = formKey.currentState;
                    if (state != null) {
                      setBtnState(() => isSaving = true);
                      try {
                        // ignore: avoid_dynamic_calls
                        await state.saveRecord();
                      } catch (e) {
                        // メソッドが存在しない場合のフォールバック（通常は起こらないはず）
                        debugPrint('Save method not found: $e');
                      } finally {
                        if (ctx.mounted) setBtnState(() => isSaving = false);
                      }
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('保存'),
                );
              }
            );
          })(),
        ],
      ),
    );
  }

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
                leading: CircleAvatar(backgroundColor: AppColors.pool, child: const Icon(Icons.pool, color: Colors.white)),
                title: const Text('トレーニング記録'),
                subtitle: const Text('水中・陸上メニューを入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFormDialog(
                    context: context,
                    title: 'トレーニング記録',
                    icon: Icons.pool,
                    color: AppColors.pool,
                    formBuilder: (dCtx, key) => TrainingForm(key: key, isDialog: true, onSaveSuccess: () => Navigator.pop(dCtx)),
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.fat, child: const Icon(Icons.restaurant, color: Colors.white)),
                title: const Text('食事記録'),
                subtitle: const Text('食事・PFCバランスを入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFormDialog(
                    context: context,
                    title: '食事記録',
                    icon: Icons.restaurant,
                    color: AppColors.fat,
                    formBuilder: (dCtx, key) => NutritionForm(key: key, isDialog: true, onSaveSuccess: () => Navigator.pop(dCtx)),
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.bodyComp, child: const Icon(Icons.monitor_weight, color: Colors.white)),
                title: const Text('体組成記録'),
                subtitle: const Text('体重・筋肉量・体脂肪率を入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFormDialog(
                    context: context,
                    title: '体組成記録',
                    icon: Icons.monitor_weight,
                    color: AppColors.bodyComp,
                    formBuilder: (dCtx, key) => BodyCompositionForm(key: key, isDialog: true, onSaveSuccess: () => Navigator.pop(dCtx)),
                  );
                },
              ),
              ListTile(
                leading: CircleAvatar(backgroundColor: AppColors.sleep, child: const Icon(Icons.bedtime, color: Colors.white)),
                title: const Text('睡眠記録'),
                subtitle: const Text('入眠・起床時間を入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  context.go('/home?action=add_sleep');
                },
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: AppColors.skyBlue, child: Icon(Icons.analytics, color: Colors.white)),
                title: const Text('レース結果記録'),
                subtitle: const Text('レース記録・ラップを詳細入力'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _showFormDialog(
                    context: context,
                    title: 'レース結果記録',
                    icon: Icons.analytics,
                    color: AppColors.skyBlue,
                    formBuilder: (dCtx, key) => AnalysisSheetForm(key: key, isDialog: true, onSaveSuccess: () => Navigator.pop(dCtx)),
                  );
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
      heroTag: null,
      onPressed: () => _showAddMenu(context),
      child: const Icon(Icons.add),
    );
  }
}
