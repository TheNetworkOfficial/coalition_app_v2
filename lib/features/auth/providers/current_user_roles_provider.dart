import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';

final currentUserRolesProvider = FutureProvider<List<String>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final profile = await apiClient.getMyProfile();
  debugPrint(
    '[RolesProvider][TEMP] profile roles=${profile.roles} isAdmin=${profile.isAdmin}',
  );
  if (profile.roles.isNotEmpty) {
    debugPrint(
      '[RolesProvider][TEMP] returning profile roles=${profile.roles}',
    );
    return profile.roles;
  }
  if (profile.isAdmin) {
    debugPrint('[RolesProvider][TEMP] profile isAdmin true, using fallback');
    return const ['admin'];
  }
  debugPrint('[RolesProvider][TEMP] returning empty roles list');
  return const <String>[];
});

final hasAdminAccessProvider = Provider<bool>((ref) {
  final rolesAsync = ref.watch(currentUserRolesProvider);
  final hasAdmin = rolesAsync.maybeWhen(
    data: (roles) => roles.contains('admin'),
    orElse: () => false,
  );
  final rolesState = rolesAsync.isLoading
      ? 'loading'
      : rolesAsync.hasError
          ? 'error'
          : 'data';
  final rolesValue = rolesAsync.maybeWhen<List<String>?>(
    data: (roles) => roles,
    orElse: () => null,
  );
  debugPrint(
    '[RolesProvider][TEMP] hasAdminAccessProvider state=$rolesState roles=$rolesValue hasAdmin=$hasAdmin',
  );
  return hasAdmin;
});
