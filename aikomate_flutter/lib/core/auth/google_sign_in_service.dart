import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:aikomate_flutter/core/config/env.dart';

/// Outcome of obtaining a Google ID token for [googleAuth].
class GoogleIdTokenOutcome {
  final bool success;
  final String? idToken;
  /// Set when [success] is false: configuration error, missing token, or exception.
  /// Null when the user cancelled the sign-in sheet.
  final String? errorMessage;

  const GoogleIdTokenOutcome.cancelled()
      : success = false,
        idToken = null,
        errorMessage = null;

  const GoogleIdTokenOutcome.ok(String token)
      : success = true,
        idToken = token,
        errorMessage = null;

  const GoogleIdTokenOutcome.error(String message)
      : success = false,
        idToken = null,
        errorMessage = message;
}

class GoogleSignInService {
  GoogleSignInService._();

  static final GoogleSignInService instance = GoogleSignInService._();

  GoogleSignIn? _client;

  GoogleSignIn get _googleSignIn {
    return _client ??= GoogleSignIn(
      scopes: const ['email', 'profile'],
      serverClientId: Env.googleServerClientId.isEmpty
          ? null
          : Env.googleServerClientId,
    );
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  Future<GoogleIdTokenOutcome> obtainIdToken() async {
    if (Env.googleServerClientId.isEmpty) {
      return const GoogleIdTokenOutcome.error(
        'Google Sign-In is not configured in the app (missing GOOGLE_SERVER_CLIENT_ID). '
        'Build with --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client-id.apps.googleusercontent.com',
      );
    }

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return const GoogleIdTokenOutcome.cancelled();
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        return const GoogleIdTokenOutcome.error(
          'Google did not return an ID token. Check OAuth client ID and platform setup '
          '(Android SHA-1, iOS/macOS URL scheme, web meta tag, etc.).',
        );
      }

      return GoogleIdTokenOutcome.ok(idToken);
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_failed' &&
          (e.message?.contains('10') ?? false)) {
        return const GoogleIdTokenOutcome.error(
          'Google Sign-In Android: ApiException 10 (DEVELOPER_ERROR). '
          'In Google Cloud Console → APIs & Services → Credentials, create or fix an '
          'Android OAuth 2.0 Client with package com.aikomate and '
          'your debug keystore SHA-1 fingerprint. Run: cd android && ./gradlew signingReport '
          '(use JDK 17 or 21 if Gradle fails on JDK 25; use the debug variant SHA-1). '
          'GOOGLE_SERVER_CLIENT_ID must remain the Web client ID that matches the backend.',
        );
      }
      return GoogleIdTokenOutcome.error(e.message ?? e.toString());
    } catch (e) {
      return GoogleIdTokenOutcome.error(e.toString());
    }
  }
}
