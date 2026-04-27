import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aikomate_flutter/app/session_scope.dart';
import 'package:aikomate_flutter/core/auth/auth_session_notifier.dart';
import 'package:aikomate_flutter/core/router/app_router.dart';

class AikoMateApp extends StatefulWidget {
  const AikoMateApp({super.key, required this.session});

  final AuthSessionNotifier session;

  @override
  State<AikoMateApp> createState() => _AikoMateAppState();
}

class _AikoMateAppState extends State<AikoMateApp> {
  late final GoRouter _router = createAppRouter(widget.session);

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: widget.session,
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          return MaterialApp.router(
            title: 'AikoMate',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
              useMaterial3: true,
            ),
            routerConfig: _router,
          );
        },
      ),
    );
  }
}
