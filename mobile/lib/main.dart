import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/queue_sync_service.dart';
import 'theme/yoma_theme.dart';

final queueSyncService = QueueSyncService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  queueSyncService.start();
  runApp(const YomaApp());
}

class YomaApp extends StatelessWidget {
  const YomaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yoma Triage',
      debugShowCheckedModeBanner: false,
      theme: buildYomaTheme(),
      home: const HomeScreen(),
    );
  }
}
