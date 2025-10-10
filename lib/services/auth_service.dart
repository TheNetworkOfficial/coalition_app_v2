import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../amplifyconfiguration.dart';
import '../env.dart';
import '../features/auth/models/user_summary.dart';
import 'session_manager.dart';

class AuthService {
  AuthService({SessionManager? sessionManager, GoogleSignIn? googleSignIn})
      : _sessionManager = sessionManager ?? SessionManager(),
        _googleSignIn = googleSignIn ?? GoogleSignIn(scopes: const ['email', 'profile']);

  final SessionManager _sessionManager;
  final GoogleSignIn _googleSignIn;

  bool _pluginsAdded = false;
  bool _configured = false;
  bool _isConfiguring = false;

  Future<void> _configureIfNeeded() async {
    if (kAuthBypassEnabled) {
      return;
    }
    if (_configured) {
      return;
    }
    if (_isConfiguring) {
      while (_isConfiguring) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }
    _isConfiguring = true;
    try {
      if (!_pluginsAdded) {
        try {
          Amplify.addPlugin(AmplifyAuthCognito());
        } on Exception catch (error, stackTrace) {
          debugPrint('[AuthService] addPlugin failed: $error\n$stackTrace');
          rethrow;
        }
        _pluginsAdded = true;
      }

      try {
        await Amplify.configure(amplifyconfig);
      } on AmplifyAlreadyConfiguredException {
        debugPrint('[AuthService] Amplify already configured; continuing');
      }
      _configured = true;
    } finally {
      _isConfiguring = false;
    }
  }

  Future<bool> isSignedIn() async {
    if (kAuthBypassEnabled) {
      final marker = await _sessionManager.readSessionMarker();
      return marker != null && marker.isNotEmpty;
    }
    await _configureIfNeeded();
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session.isSignedIn;
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] fetchAuthSession failed: $error\n$stackTrace');
      return false;
    }
  }

  Future<UserSummary?> currentUser() async {
    if (kAuthBypassEnabled) {
      final marker = await _sessionManager.readSessionMarker();
      if (marker == null || marker.isEmpty) {
        return null;
      }
      return UserSummary(userId: marker, username: marker, displayName: 'Developer');
    }

    await _configureIfNeeded();
    try {
      final user = await Amplify.Auth.getCurrentUser();
      final attributes = await Amplify.Auth.fetchUserAttributes();
      String? username;
      String? displayName;
      for (final attribute in attributes) {
        switch (attribute.userAttributeKey.key) {
          case 'preferred_username':
          case 'nickname':
            username ??= attribute.value;
            break;
          case 'name':
          case 'given_name':
            displayName ??= attribute.value;
            break;
        }
      }
      username ??= user.username;
      return UserSummary(
        userId: user.userId,
        username: username,
        displayName: displayName,
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] currentUser failed: $error\n$stackTrace');
      return null;
    }
  }

  Future<void> signInWithGoogle() async {
    if (kAuthBypassEnabled) {
      await _sessionManager.persistSessionMarker('u1');
      return;
    }

    await _configureIfNeeded();
    try {
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw Exception('Google sign-in canceled');
      }
      await account.authentication;
      await Amplify.Auth.signInWithWebUI(provider: AuthProvider.google);
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] Google sign-in failed: $error\n$stackTrace');
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[AuthService] Google sign-in unexpected error: $error\n$stackTrace');
      rethrow;
    }
    await _persistSessionMarkerFromUser();
  }

  Future<void> signUpEmail({
    required String username,
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (kAuthBypassEnabled) {
      await _sessionManager.persistSessionMarker(username);
      return;
    }

    await _configureIfNeeded();
    try {
      final options = CognitoSignUpOptions(
        userAttributes: {
          CognitoUserAttributeKey.email: email,
          CognitoUserAttributeKey.preferredUsername: username,
          CognitoUserAttributeKey.name: displayName,
        },
      );
      await Amplify.Auth.signUp(
        username: username,
        password: password,
        options: options,
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] signUpEmail failed: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<void> signInEmail({
    required String usernameOrEmail,
    required String password,
  }) async {
    if (kAuthBypassEnabled) {
      await _sessionManager.persistSessionMarker(usernameOrEmail);
      return;
    }

    await _configureIfNeeded();
    try {
      final result = await Amplify.Auth.signIn(
        username: usernameOrEmail,
        password: password,
      );
      if (!result.isSignedIn) {
        throw Exception('Sign-in not completed');
      }
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] signInEmail failed: $error\n$stackTrace');
      rethrow;
    }
    await _persistSessionMarkerFromUser();
  }

  Future<void> signOut() async {
    if (kAuthBypassEnabled) {
      await _sessionManager.clearSessionMarker();
      return;
    }

    await _configureIfNeeded();
    try {
      await Amplify.Auth.signOut();
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] signOut failed: $error\n$stackTrace');
    }
    await _sessionManager.clearSessionMarker();
  }

  Future<String?> fetchAuthToken() async {
    if (kAuthBypassEnabled) {
      return null;
    }
    await _configureIfNeeded();
    try {
      final session = await Amplify.Auth.fetchAuthSession(
        options: const FetchAuthSessionOptions(forceRefresh: false),
      );
      if (session is CognitoAuthSession) {
        final result = session.userPoolTokensResult;
        if (result.value != null) {
          return result.value.idToken;
        }
      }
    } on AuthException catch (error, stackTrace) {
      debugPrint('[AuthService] fetchAuthToken failed: $error\n$stackTrace');
    }
    return null;
  }

  Future<void> _persistSessionMarkerFromUser() async {
    final summary = await currentUser();
    final marker = summary?.userId ?? summary?.username;
    if (marker != null && marker.isNotEmpty) {
      await _sessionManager.persistSessionMarker(marker);
    }
  }
}
