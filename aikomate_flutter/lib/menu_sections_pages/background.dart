import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aikomate_flutter/reusable_widgets/glass.dart';
import 'package:aikomate_flutter/core/storage/settings_storage.dart';

class BackgroundConfig {
  final String type; // image | video | room | none
  final String url;

  const BackgroundConfig({
    required this.type,
    required this.url,
  });

  Map<String, dynamic> toJson() => {
        "type": type,
        "url": url,
      };

  static BackgroundConfig fromJson(Map<String, dynamic> data) {
    return BackgroundConfig(
      type: data["type"]?.toString() ?? "none",
      url: data["url"]?.toString() ?? "",
    );
  }
}

class BackgroundItem {
  final String id;
  final String type; // image | video | room | none
  final String url;
  final String label;
  final String? thumbnail;
  final String source; // app | user

  const BackgroundItem({
    required this.id,
    required this.type,
    required this.url,
    required this.label,
    required this.source,
    this.thumbnail,
  });

  BackgroundConfig toConfig() => BackgroundConfig(type: type, url: url);

  Map<String, dynamic> toJson() => {
        "id": id,
        "type": type,
        "url": url,
        "label": label,
        "thumbnail": thumbnail,
        "source": source,
      };

  static BackgroundItem fromJson(Map<String, dynamic> data) {
    return BackgroundItem(
      id: data["id"]?.toString() ?? "",
      type: data["type"]?.toString() ?? "image",
      url: data["url"]?.toString() ?? "",
      label: data["label"]?.toString() ?? "Background",
      thumbnail: data["thumbnail"]?.toString(),
      source: data["source"]?.toString() ?? "user",
    );
  }
}

class BackgroundCard extends StatelessWidget {
  final BackgroundItem item;
  final bool selected;
  final VoidCallback onTap;
  final String subtitle;
  final IconData fallbackIcon;

  const BackgroundCard({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.subtitle,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Stack(
          children: [
            GlassContainer(
              style: GlassPresets.card,
              radius: 16,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: SizedBox(
                      height: 86,
                      child: BackgroundThumbnail(
                        item: item,
                        fallbackIcon: fallbackIcon,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                right: 8,
                top: 8,
                child: Icon(
                  Icons.check_circle,
                  color: Colors.lightBlueAccent.withOpacity(0.9),
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BackgroundThumbnail extends StatelessWidget {
  final BackgroundItem item;
  final IconData fallbackIcon;

  const BackgroundThumbnail({
    super.key,
    required this.item,
    required this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final preview = _previewUrl(item);
    if (preview != null) {
      if (_isAsset(preview)) {
        return Image.asset(preview, fit: BoxFit.cover);
      }
      if (_isFile(preview)) {
        final path = preview.startsWith("file://")
            ? preview.replaceFirst("file://", "")
            : preview;
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _thumbnailFallback(),
        );
      }
      return Image.network(
        preview,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbnailFallback(),
      );
    }
    return _thumbnailFallback();
  }

  Widget _thumbnailFallback() {
    return Container(
      color: Colors.white.withOpacity(0.06),
      child: Center(
        child: Icon(
          fallbackIcon,
          color: Colors.white54,
          size: 30,
        ),
      ),
    );
  }

  String? _previewUrl(BackgroundItem item) {
    final thumb = item.thumbnail?.trim();
    if (thumb != null && thumb.isNotEmpty) return thumb;
    if (item.type == "image") return item.url;
    return null;
  }

  bool _isAsset(String value) => value.startsWith("assets/");
  bool _isFile(String value) =>
      value.startsWith("file://") || value.startsWith("/");
}

class BackgroundView extends StatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<BackgroundConfig> onApply;

  const BackgroundView({
    super.key,
    required this.onBack,
    required this.onApply,
  });

  @override
  State<BackgroundView> createState() => _BackgroundViewState();
}

class _BackgroundViewState extends State<BackgroundView> {
  static const _storageKey = "backgrounds";
  static final List<BackgroundItem> _baseBackgrounds = [
    BackgroundItem(
      id: "builtin_none",
      type: "none",
      url: "",
      label: "None",
      source: "app",
    ),
    BackgroundItem(
      id: "builtin_world",
      type: "room",
      url: "rooms/world.glb",
      label: "Starter Room",
      source: "app",
    ),
  ];

  final TextEditingController _labelController = TextEditingController();
  List<BackgroundItem> _appItems = [];
  List<BackgroundItem> _userItems = [];
  String? _selectedId;
  bool _showAddForm = false;
  String _newType = "image";
  bool _loading = true;
  String? _error;
  String? _formError;
  String? _pickedPath;
  String? _pickedThumbnail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await SettingsStorage.readAll();
    _appItems = await _loadAppBackgrounds();
    _userItems = _readBackgroundList(data[_storageKey]);
    final config = _readCurrentBackground(data["background"]);
    _selectedId = _findMatchingId(config);
    setState(() => _loading = false);
  }

  Future<List<BackgroundItem>> _loadAppBackgrounds() async {
    final results = <BackgroundItem>[..._baseBackgrounds];
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      final manifest = Map<String, dynamic>.from(
        jsonDecode(raw) as Map,
      );
      const prefix = 'assets/web/backgroud_images/';
      for (final entry in manifest.keys) {
        if (!entry.startsWith(prefix)) continue;
        if (!_isImageAsset(entry)) continue;
        final name = entry.split('/').last;
        results.add(
          BackgroundItem(
            id: 'builtin_img_$name',
            type: 'image',
            url: entry.replaceFirst('assets/web/', ''),
            label: _titleFromFilename(name),
            thumbnail: entry,
            source: 'app',
          ),
        );
      }
    } catch (_) {
      // ignore asset scan errors
    }
    return results;
  }

  bool _isImageAsset(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  String _titleFromFilename(String name) {
    final base = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    if (base.isEmpty) return 'Background';
    return base
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  List<BackgroundItem> _readBackgroundList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => BackgroundItem.fromJson(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .where((item) => item.id.isNotEmpty)
          .toList();
    }
    return [];
  }

  BackgroundConfig? _readCurrentBackground(dynamic value) {
    if (value is Map) {
      return BackgroundConfig.fromJson(
        value.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return null;
  }

  String? _findMatchingId(BackgroundConfig? config) {
    if (config == null) return null;
    final all = _allItems();
    for (final item in all) {
      if (item.type == config.type && item.url == config.url) {
        return item.id;
      }
    }
    return null;
  }

  List<BackgroundItem> _allItems() => [..._appItems, ..._userItems];

  Future<void> _applyItem(BackgroundItem item) async {
    final config = item.toConfig();
    await SettingsStorage.update({
      "background": config.toJson(),
    });
    setState(() => _selectedId = item.id);
    widget.onApply(config);
  }

  Future<void> _saveUserBackground() async {
    final label = _labelController.text.trim();
    final picked = _pickedPath;

    if (label.isEmpty) {
      setState(() => _formError = "Add a name for this background.");
      return;
    }
    if (_newType != "none" && (picked == null || picked.isEmpty)) {
      setState(() => _formError = "Pick a file first.");
      return;
    }

    final path = _normalizePickedPath(picked);
    final item = BackgroundItem(
      id: "user_${DateTime.now().millisecondsSinceEpoch}",
      type: _newType,
      url: path ?? "",
      label: label,
      thumbnail: _pickedThumbnail,
      source: "user",
    );

    final updated = [..._userItems, item];
    await SettingsStorage.update({
      _storageKey: updated.map((e) => e.toJson()).toList(),
    });

    setState(() {
      _userItems = updated;
      _showAddForm = false;
      _formError = null;
      _labelController.clear();
      _newType = "image";
      _pickedPath = null;
      _pickedThumbnail = null;
    });
  }

  String? _normalizePickedPath(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('file://') || path.startsWith('content://')) {
      return path;
    }
    return 'file://$path';
  }

  Future<void> _pickFileForType() async {
    FileType type = FileType.any;
    List<String>? extensions;
    if (_newType == "image") {
      type = FileType.image;
    } else if (_newType == "video") {
      type = FileType.video;
    } else if (_newType == "room") {
      type = FileType.custom;
      extensions = ["glb", "gltf"];
    }

    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: extensions,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) {
      setState(() => _formError = "Could not access that file path.");
      return;
    }
    setState(() {
      _pickedPath = file.path;
      _formError = null;
      if (_newType == "image") {
        _pickedThumbnail = _normalizePickedPath(file.path);
      }
      if (_labelController.text.trim().isEmpty) {
        _labelController.text = _titleFromFilename(file.name);
      }
    });
  }

  Future<void> _pickThumbnail() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) {
      setState(() => _formError = "Could not access that thumbnail path.");
      return;
    }
    setState(() {
      _pickedThumbnail = _normalizePickedPath(file.path);
      _formError = null;
    });
  }

  Widget _buildTypeChip(String label, String type, IconData icon) {
    final selected = _newType == type;
    return GestureDetector(
      onTap: () => setState(() => _newType = type),
      child: GlassContainer(
        style: selected ? GlassPresets.card : GlassPresets.panel,
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white.withOpacity(0.9)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAddCard() {
    return GestureDetector(
      onTap: () => setState(() => _showAddForm = !_showAddForm),
      child: GlassContainer(
        style: GlassPresets.card,
        radius: 16,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 150,
          height: 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showAddForm ? Icons.close : Icons.add,
                  color: Colors.white70,
                  size: 26,
                ),
                const SizedBox(height: 8),
                Text(
                  _showAddForm ? "Close" : "Add background",
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case "image":
        return "Static image";
      case "video":
        return "Dynamic video";
      case "room":
        return "3D room";
      case "none":
      default:
        return "No background";
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case "image":
        return Icons.image_outlined;
      case "video":
        return Icons.movie_outlined;
      case "room":
        return Icons.chair_outlined;
      case "none":
      default:
        return Icons.block;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return GlassContainer(
      style: GlassPresets.panel,
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 380,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GlassIconButton(
                  adaptiveIconSize: true,
                  size: 40,
                  radius: 12,
                  style: GlassPresets.button,
                  icon: Icons.arrow_back,
                  onPressed: widget.onBack,
                ),
                const Text(
                  "Background",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                GlassIconButton(
                  adaptiveIconSize: true,
                  size: 40,
                  radius: 12,
                  style: GlassPresets.button,
                  icon: Icons.check,
                  onPressed: widget.onBack,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle("App backgrounds"),
                    if (_appItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          "No built-in backgrounds yet.",
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final item in _appItems)
                            BackgroundCard(
                              item: item,
                              selected: _selectedId == item.id,
                              onTap: () => _applyItem(item),
                              subtitle: _typeLabel(item.type),
                              fallbackIcon: _typeIcon(item.type),
                            ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    _buildSectionTitle("Your backgrounds"),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final item in _userItems)
                          BackgroundCard(
                            item: item,
                            selected: _selectedId == item.id,
                            onTap: () => _applyItem(item),
                            subtitle: _typeLabel(item.type),
                            fallbackIcon: _typeIcon(item.type),
                          ),
                        _buildAddCard(),
                      ],
                    ),
                    if (_showAddForm) ...[
                      const SizedBox(height: 16),
                      GlassContainer(
                        style: GlassPresets.card,
                        radius: 16,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Add background",
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildTypeChip("Image", "image", Icons.image_outlined),
                                _buildTypeChip("Video", "video", Icons.movie_outlined),
                                _buildTypeChip("3D Room", "room", Icons.chair_outlined),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _labelController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: "Name",
                                hintStyle: TextStyle(color: Colors.white54),
                                border: InputBorder.none,
                              ),
                            ),
                            const SizedBox(height: 8),
                            GlassContainer(
                              style: GlassPresets.panel,
                              radius: 12,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _pickedPath == null
                                          ? "No file selected"
                                          : _pickedPath!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GlassIconButton(
                                    adaptiveIconSize: true,
                                    size: 34,
                                    radius: 10,
                                    style: GlassPresets.button,
                                    icon: Icons.folder_open,
                                    onPressed: _pickFileForType,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_newType != "image")
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _pickedThumbnail == null
                                          ? "No thumbnail selected"
                                          : _pickedThumbnail!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GlassIconButton(
                                    adaptiveIconSize: true,
                                    size: 34,
                                    radius: 10,
                                    style: GlassPresets.button,
                                    icon: Icons.image_outlined,
                                    onPressed: _pickThumbnail,
                                  ),
                                ],
                              ),
                            if (_newType != "image") const SizedBox(height: 10),
                            Text(
                              _newType == "room"
                                  ? "Use a .glb or .gltf room file."
                                  : "Use a jpg/png or mp4/webm file.",
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            if (_formError != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _formError!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: GlassIconButton(
                                adaptiveIconSize: true,
                                size: 40,
                                radius: 12,
                                style: GlassPresets.button,
                                icon: Icons.check,
                                onPressed: _saveUserBackground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
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
