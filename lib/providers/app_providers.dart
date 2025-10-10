import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager();
});

final authServiceProvider = Provider<AuthService>((ref) {
  final sessionManager = ref.watch(sessionManagerProvider);
  final service = AuthService(sessionManager: sessionManager);
  return service;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final authService = ref.watch(authServiceProvider);
  final client = ApiClient(authService: authService);
  ref.onDispose(client.close);
  return client;
});
