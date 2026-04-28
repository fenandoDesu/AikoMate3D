import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aikomate_flutter/core/api/auth_api.dart';
import 'package:aikomate_flutter/core/api/templates_api.dart';
import 'package:aikomate_flutter/features/viewer/viewer_launch_args.dart';

/// Loads full template, then opens [ViewerScreen] with [ViewerLaunchArgs].
///
/// [templateId] overrides [templateIdFromItem] when the list row shape needs an
/// explicit id (same function is used to resolve it in the UI).
Future<void> openTemplateInViewer(
  BuildContext context,
  Map<String, dynamic> item, {
  String? templateId,
}) async {
  final id =
      (templateId != null && templateId.trim().isNotEmpty)
          ? templateId.trim()
          : templateIdFromItem(item);
  if (id == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open this character (missing template id).'),
        ),
      );
    }
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => const Center(child: CircularProgressIndicator()),
  );

  void closeLoading() {
    if (!context.mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) nav.pop();
  }

  try {
    final authRes = await auth();
    final userName = authRes.result?['name']?.toString();
    final res = await getTemplate(id);
    if (!context.mounted) return;

    final raw = res.json;
    final map =
        raw is Map<String, dynamic>
            ? raw
            : raw is Map
            ? Map<String, dynamic>.from(raw)
            : null;

    if (!res.success || map == null) {
      closeLoading();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Could not load template')),
      );
      return;
    }

    final vrmUrl = vrmFileUrlFromItem(map);
    if (vrmUrl == null || vrmUrl.isEmpty) {
      closeLoading();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This template has no VRM URL yet.')),
      );
      return;
    }

    final title = map['title']?.toString();
    final name = map['name']?.toString();
    final display =
        (title != null && title.isNotEmpty)
            ? title
            : (name != null && name.isNotEmpty)
            ? name
            : 'Companion';
    final promptRaw = map['prompt']?.toString();
    final prompt =
        promptRaw != null && promptRaw.trim().isNotEmpty
            ? promptRaw.trim()
            : null;
    final fishAudioId = fishAudioIdFromMap(map);

    closeLoading();
    context.push(
      '/viewer',
      extra: ViewerLaunchArgs(
        vrmUrl: vrmUrl,
        displayName: display,
        templateId: id,
        personalityPrompt: prompt,
        userName: userName,
        fishAudioId: fishAudioId,
      ),
    );
  } catch (e) {
    closeLoading();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open viewer: $e')));
    }
  }
}
