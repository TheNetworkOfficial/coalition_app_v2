import 'package:coalition_app_v2/router/app_router.dart' as router;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug/logging.dart';
import 'env.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
  };
  assertApiBaseConfigured();
  debugPrint('[Startup] API base: $kApiBaseUrl');
  runApp(const ProviderScope(
    observers: <ProviderObserver>[DebugObserver()],
    child: MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Coalition App V2',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      routerConfig: router.appRouter,
    );
  }
}

final class DebugObserver extends ProviderObserver {
  const DebugObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    logDebug(
      'PROVIDER',
      '[${context.provider.name ?? context.provider.runtimeType}] error: $error',
      extra: stackTrace.toString(),
    );
  }
}
