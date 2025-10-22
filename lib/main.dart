import 'package:coalition_app_v2/router/app_router.dart';
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
      routerConfig: appRouter,
    );
  }
}

class DebugObserver extends ProviderObserver {
  const DebugObserver();

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    logDebug(
      'PROVIDER',
      '[${provider.name ?? provider.runtimeType}] error: $error',
      extra: stackTrace.toString(),
    );
  }
}
