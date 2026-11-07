import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/audio_recorder.dart';
import 'services/cho_store.dart';
import 'services/queue_sync_service.dart';
import 'theme/yoma_theme.dart';

final queueSyncService = QueueSyncService();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(purgeStaleRecordings());
  queueSyncService.start();
  runApp(const YomaApp());
}

class YomaApp extends StatefulWidget {
  const YomaApp({super.key});

  @override
  State<YomaApp> createState() => _YomaAppState();
}

class _YomaAppState extends State<YomaApp> {
  final _navigator = GlobalKey<NavigatorState>();
  bool _loaded = false;
  ChoIdentity? _identity;

  @override
  void initState() {
    super.initState();
    ChoStore.removals.addListener(_onRemoved);
    unawaited(_loadIdentity());
  }

  @override
  void dispose() {
    ChoStore.removals.removeListener(_onRemoved);
    super.dispose();
  }

  /// A sync found this CHO deactivated or moved. Leave whatever screen is open: the
  /// identity it was using is gone. Setup explains why and keeps unsent referrals visible.
  void _onRemoved() {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    unawaited(_loadIdentity());
  }

  Future<void> _loadIdentity() async {
    final identity = await ChoStore().load();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (!_loaded) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (_identity == null) {
      home = SetupScreen(
        onComplete: (identity) => setState(() => _identity = identity),
      );
    } else {
      home = const HomeScreen();
    }
    return MaterialApp(
      title: 'Yoma Triage',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: buildYomaTheme(),
      home: home,
    );
  }
}
