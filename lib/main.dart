import 'package:coalition_app_v2/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assertApiBaseConfigured();
  debugPrint('[Startup] API base: $kApiBaseUrl');
  runApp(const ProviderScope(child: MyApp()));
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
