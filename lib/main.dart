import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/sync/sync_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.maximize();
    });
  }

  runApp(const ProviderScope(child: BillingApp()));
}

class BillingApp extends ConsumerWidget {
  const BillingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Initialize sync manager on startup
    ref.listenManual(syncManagerProvider, (prev, next) {
      next.connect().then((_) => next.syncData());
    }, fireImmediately: true);

    return MaterialApp.router(
      title: 'Maligai POS',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
