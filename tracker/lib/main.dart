import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'data/db/database.dart';
import 'data/repository/title_repository.dart';
import 'features/list/title_list_page.dart';

/// M1 阶段用全局单例，后续（M3 引入同步后）改为 Provider 注入。
late final AppDatabase db;
late final TitleRepository repository;

Future<void> main() async {
  // drift_flutter 内部要调 path_provider 取数据目录，必须先完成绑定。
  WidgetsFlutterBinding.ensureInitialized();
  db = AppDatabase();
  repository = TitleRepository(db);
  runApp(const TrackerApp());

  // 首帧之后再跑，不拖慢启动：把历史封面上多画的「第N季」重绘成纯剧名。
  // 标记位保证只跑一次，之后新建/编辑时生成的封面本身就是纯剧名。
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('cover.basefix') == true) return;
      await repository.regenerateAllCovers();
      await p.setBool('cover.basefix', true);
    } catch (_) {
      // 封面重绘失败不影响主流程，下次启动会再试
    }
  });
}

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '追剧',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const TitleListPage(),
    );
  }
}
