import 'package:flutter/material.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';

/// Provides [AuthSessionNotifier] (login + `isAdmin` from `/auth/me`) below [MaterialApp].
class SessionScope extends InheritedWidget {
  const SessionScope({
    super.key,
    required this.session,
    required super.child,
  });

  final AuthSessionNotifier session;

  static AuthSessionNotifier of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope not found');
    return scope!.session;
  }

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      oldWidget.session != session;
}
