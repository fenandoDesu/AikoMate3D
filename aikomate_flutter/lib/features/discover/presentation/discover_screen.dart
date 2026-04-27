import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:aikomate_flutter/app/session_scope.dart';
import 'package:aikomate_flutter/core/api/auth_api.dart';
import 'package:aikomate_flutter/core/api/templates_api.dart';
import 'package:aikomate_flutter/features/viewer/viewer_launch_args.dart';

const int _pageSize = 24;
const int _adminPendingPageSize = 50;

Future<void> openTemplateInViewer(
  BuildContext context,
  Map<String, dynamic> item,
) async {
  final id = templateIdFromItem(item);
  if (id == null) return;

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

    closeLoading();
    context.push(
      '/viewer',
      extra: ViewerLaunchArgs(
        vrmUrl: vrmUrl,
        displayName: display,
        templateId: id,
        personalityPrompt: prompt,
        userName: userName,
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

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: ListenableBuilder(
        listenable: session,
        builder:
            (context, _) =>
                _PublicTemplatesTab(showAdminPending: session.isAdmin),
      ),
    );
  }
}

class _PublicTemplatesTab extends StatefulWidget {
  const _PublicTemplatesTab({required this.showAdminPending});

  final bool showAdminPending;

  @override
  State<_PublicTemplatesTab> createState() => _PublicTemplatesTabState();
}

class _PublicTemplatesTabState extends State<_PublicTemplatesTab> {
  final List<Map<String, dynamic>> _pendingItems = [];
  final List<Map<String, dynamic>> _items = [];
  int _currentPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _pendingLoading = false;
  bool _pendingForbidden = false;
  String? _pendingError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (widget.showAdminPending) {
      await _loadPending();
    } else {
      _pendingItems.clear();
      _pendingForbidden = false;
      _pendingError = null;
    }
    final res = await getPublicTemplates(page: 1, limit: _pageSize);
    if (!mounted) return;
    final page = TemplatesListPage.tryParse(res);
    setState(() {
      _loading = false;
      if (page != null) {
        _items
          ..clear()
          ..addAll(page.items);
        _currentPage = page.page;
        _total = page.total;
        _error = null;
      } else {
        _error = res.error ?? 'Could not load templates';
      }
    });
  }

  Future<void> _loadPending() async {
    setState(() {
      _pendingLoading = true;
      _pendingForbidden = false;
      _pendingError = null;
    });
    final res = await getAdminPendingTemplates(
      page: 1,
      limit: _adminPendingPageSize,
    );
    if (!mounted) return;
    if (res.statusCode == 403) {
      setState(() {
        _pendingLoading = false;
        _pendingForbidden = true;
        _pendingItems.clear();
      });
      return;
    }
    final page = TemplatesListPage.tryParse(res);
    setState(() {
      _pendingLoading = false;
      if (page != null) {
        _pendingItems
          ..clear()
          ..addAll(page.items);
      } else {
        _pendingError = res.error ?? 'Could not load pending templates';
      }
    });
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    final id = templateIdFromItem(item);
    if (id == null) return;
    final r = await approveTemplateAdmin(id);
    if (!mounted) return;
    if (!r.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(r.error ?? 'Approve failed')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Template approved')));
    await _refresh();
  }

  Future<void> _decline(Map<String, dynamic> item) async {
    final id = templateIdFromItem(item);
    if (id == null) return;
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Decline template'),
            content: TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Moderation note (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Decline'),
              ),
            ],
          ),
    );
    final noteText = noteController.text.trim();
    noteController.dispose();
    if (confirmed != true || !mounted) return;
    final r = await declineTemplateAdmin(
      id,
      moderationNote: noteText.isEmpty ? null : noteText,
    );
    if (!mounted) return;
    if (!r.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(r.error ?? 'Decline failed')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Template declined')));
    await _refresh();
  }

  Future<void> _loadMore() async {
    if (_items.length >= _total) return;
    final nextPage = _currentPage + 1;
    final res = await getPublicTemplates(page: nextPage, limit: _pageSize);
    if (!mounted) return;
    final page = TemplatesListPage.tryParse(res);
    if (page == null) return;
    setState(() {
      _items.addAll(page.items);
      _currentPage = page.page;
      _total = page.total;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final showEmptyPublic = _items.isEmpty;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _computedItemCount(showEmptyPublic),
        itemBuilder: (context, index) {
          var dataIndex = index;
          if (widget.showAdminPending) {
            if (index == 0) {
              return _AdminPendingSection(
                loading: _pendingLoading,
                forbidden: _pendingForbidden,
                error: _pendingError,
                items: _pendingItems,
                onApprove: _approve,
                onDecline: _decline,
              );
            }
            dataIndex = index - 1;
          }
          if (showEmptyPublic && dataIndex == 0) {
            return const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Text('No public templates yet.')),
            );
          }
          if (dataIndex == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: TextButton(
                  onPressed: _loadMore,
                  child: const Text('Load more'),
                ),
              ),
            );
          }
          final item = _items[dataIndex];
          return _TemplatePublicTile(
            item: item,
            onOpen: () => openTemplateInViewer(context, item),
          );
        },
      ),
    );
  }

  int _computedItemCount(bool showEmptyPublic) {
    final adminHeaderCount = widget.showAdminPending ? 1 : 0;
    if (showEmptyPublic) return adminHeaderCount + 1;
    return _items.length + (_items.length < _total ? 1 : 0) + adminHeaderCount;
  }
}

class _TemplatePublicTile extends StatelessWidget {
  const _TemplatePublicTile({required this.item, required this.onOpen});

  final Map<String, dynamic> item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final title =
        item['title']?.toString() ?? item['name']?.toString() ?? 'Untitled';
    final name = item['name']?.toString();
    final description = item['description']?.toString() ?? '';
    final coverUrl = coverImageUrlFromItem(item);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (coverUrl != null && coverUrl.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      debugPrint('Discover cover failed: $coverUrl | $error');
                      return const _CoverImageFallback();
                    },
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                ),
              ),
            ListTile(
              title: Text(title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (name != null && name != title) Text('Character: $name'),
                  if (description.isNotEmpty)
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              isThreeLine: description.isNotEmpty,
              trailing: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPendingSection extends StatelessWidget {
  const _AdminPendingSection({
    required this.loading,
    required this.forbidden,
    required this.error,
    required this.items,
    required this.onApprove,
    required this.onDecline,
  });

  final bool loading;
  final bool forbidden;
  final String? error;
  final List<Map<String, dynamic>> items;
  final Future<void> Function(Map<String, dynamic> item) onApprove;
  final Future<void> Function(Map<String, dynamic> item) onDecline;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending moderation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (loading) const LinearProgressIndicator(),
            if (forbidden)
              const Text(
                'You do not have access to the moderation queue (403).',
              ),
            if (!forbidden && error != null) Text(error!),
            if (!forbidden && !loading && error == null && items.isEmpty)
              const Text('No templates pending review.'),
            if (!forbidden && !loading && items.isNotEmpty)
              ...items.map(
                (item) => _AdminPendingCard(
                  item: item,
                  onOpen: () => openTemplateInViewer(context, item),
                  onApprove: () => onApprove(item),
                  onDecline: () => onDecline(item),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminPendingCard extends StatelessWidget {
  const _AdminPendingCard({
    required this.item,
    required this.onOpen,
    required this.onApprove,
    required this.onDecline,
  });

  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final title =
        item['title']?.toString() ?? item['name']?.toString() ?? 'Untitled';
    final name = item['name']?.toString();
    final description = item['description']?.toString() ?? '';
    final prompt = item['prompt']?.toString() ?? '';
    final userId = item['userId']?.toString() ?? item['user_id']?.toString();
    final coverUrl = coverImageUrlFromItem(item);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty) ...[
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint(
                          'Discover admin cover failed: $coverUrl | $error',
                        );
                        return const _CoverImageFallback();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (name != null && name != title)
                Text(
                  'Name: $name',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (userId != null)
                Text(
                  'Owner: $userId',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(description, maxLines: 4, overflow: TextOverflow.ellipsis),
              ],
              if (prompt.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Prompt: $prompt',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Tap card to open in viewer',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDecline,
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverImageFallback extends StatelessWidget {
  const _CoverImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined),
    );
  }
}
