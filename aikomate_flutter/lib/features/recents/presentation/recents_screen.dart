import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aikomate_flutter/core/api/templates_api.dart';
import 'package:aikomate_flutter/features/viewer/open_template_in_viewer.dart';

const int _pageSize = 24;

class RecentsScreen extends StatefulWidget {
  const RecentsScreen({super.key});

  @override
  State<RecentsScreen> createState() => _RecentsScreenState();
}

class _RecentsScreenState extends State<RecentsScreen> {
  bool _loading = true;
  String? _error;
  final List<Map<String, dynamic>> _items = [];
  int _currentPage = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await getTemplateRecents(page: 1, limit: _pageSize);
    if (!mounted) return;
    final page = TemplatesListPage.tryParse(res);
    if (page == null) {
      setState(() {
        _loading = false;
        _error = res.error ?? 'Could not load recents';
        _items.clear();
        _total = 0;
      });
      return;
    }
    setState(() {
      _loading = false;
      _error = null;
      _items
        ..clear()
        ..addAll(page.items);
      _currentPage = page.page;
      _total = page.total;
    });
  }

  Future<void> _loadMore() async {
    if (_items.length >= _total) return;
    final nextPage = _currentPage + 1;
    final res = await getTemplateRecents(page: nextPage, limit: _pageSize);
    if (!mounted) return;
    final page = TemplatesListPage.tryParse(res);
    if (page == null) return;
    setState(() {
      _items.addAll(page.items);
      _currentPage = page.page;
      _total = page.total;
    });
  }

  String _titleLine(Map<String, dynamic> item) {
    return item['title']?.toString() ??
        item['name']?.toString() ??
        'Untitled';
  }

  String? _lastUsedLine(Map<String, dynamic> item) {
    final dt = lastUsedAtFromItem(item);
    if (dt == null) return null;
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return 'Last used $y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recents')),
      body: SafeArea(
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
                : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        _items.isEmpty
                            ? 1
                            : _items.length +
                                (_items.length < _total ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(
                            child: Text(
                              'No recent characters yet.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      if (index == _items.length) {
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
                      final item = _items[index];
                      final templateId = templateIdFromItem(item);
                      return _RecentTemplateTile(
                        key: ValueKey(templateId ?? 'recent-$index'),
                        title: _titleLine(item),
                        coverUrl: coverImageUrlFromItem(item),
                        subtitle: _lastUsedLine(item),
                        onOpen: () {
                          if (templateId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not open this character (missing id).',
                                ),
                              ),
                            );
                            return;
                          }
                          openTemplateInViewer(
                            context,
                            item,
                            templateId: templateId,
                          );
                        },
                      );
                    },
                  ),
                ),
      ),
    );
  }
}

class _RecentTemplateTile extends StatelessWidget {
  const _RecentTemplateTile({
    super.key,
    required this.title,
    required this.coverUrl,
    required this.subtitle,
    required this.onOpen,
  });

  final String title;
  final String? coverUrl;
  final String? subtitle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              height: 84,
              child:
                  coverUrl != null && coverUrl!.isNotEmpty
                      ? Image.network(
                        coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _CoverFallback(),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                      )
                      : const _CoverFallback(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.person_outline, size: 36)),
    );
  }
}
