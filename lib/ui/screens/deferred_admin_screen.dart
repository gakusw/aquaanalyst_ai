import 'package:flutter/material.dart';
import 'admin_screen.dart' deferred as admin;

class DeferredAdminScreen extends StatefulWidget {
  const DeferredAdminScreen({super.key});

  @override
  State<DeferredAdminScreen> createState() => _DeferredAdminScreenState();
}

class _DeferredAdminScreenState extends State<DeferredAdminScreen> {
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadAdminModule();
  }

  Future<void> _loadAdminModule() async {
    try {
      await admin.loadLibrary();
      if (mounted) {
        setState(() => _loaded = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('エラー')),
        body: Center(child: Text('管理者モジュールの読み込みに失敗しました: $_error')),
      );
    }

    if (!_loaded) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('管理者メニューを読み込んでいます...'),
            ],
          ),
        ),
      );
    }

    return admin.AdminScreen();
  }
}
