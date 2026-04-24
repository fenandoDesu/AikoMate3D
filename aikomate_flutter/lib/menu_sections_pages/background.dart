import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:aikomate_flutter/reusable_widgets/glass.dart';
import 'package:aikomate_flutter/core/storage/settings_storage.dart';
import 'package:aikomate_flutter/menu_sections_pages/background_framing_editor.dart';

class BackgroundConfig {
  final String type; // image | video | room | none
  final String url;
  /// 0–1: horizontal center of visible region (image / video backgrounds).
  final double imageFocusX;
  /// 0–1: vertical center of visible region.
  final double imageFocusY;
  /// 1 = fit; larger = zoom in (see more detail, smaller area).
  final double imageZoom;

  const BackgroundConfig({
    required this.type,
    required this.url,
    this.imageFocusX = 0.5,
    this.imageFocusY = 0.5,
    this.imageZoom = 1.0,
  });

  Map<String, dynamic> toJson() => {
        "type": type,
        "url": url,
        "focusX": imageFocusX,
        "focusY": imageFocusY,
        "zoom": imageZoom,
      };

  static BackgroundConfig fromJson(Map<String, dynamic> data) {
    return BackgroundConfig(
      type: data["type"]?.toString() ?? "none",
      url: data["url"]?.toString() ?? "",
      imageFocusX: (data["focusX"] as num?)?.toDouble() ?? 0.5,
      imageFocusY: (data["focusY"] as num?)?.toDouble() ?? 0.5,
      imageZoom: (data["zoom"] as num?)?.toDouble() ?? 1.0,
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

  BackgroundConfig toConfig() =>
      BackgroundConfig(type: type, url: url);

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
  final VoidCallback? onLongPress;
  final bool deleteSelectionMode;
  final bool markedForDeletion;
  final String subtitle;
  final IconData fallbackIcon;

  const BackgroundCard({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.subtitle,
    required this.fallbackIcon,
    this.onLongPress,
    this.deleteSelectionMode = false,
    this.markedForDeletion = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
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
            if (deleteSelectionMode && item.source == 'user')
              Positioned(
                left: 8,
                top: 8,
                child: Icon(
                  markedForDeletion
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: markedForDeletion
                      ? Colors.orangeAccent
                      : Colors.white54,
                  size: 22,
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
  static const _framesKey = "backgroundImageFrames";
  static final List<BackgroundItem> _baseBackgrounds = [
    BackgroundItem(
      id: "builtin_none",
      type: "none",
      url: "",
      label: "None",
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
  PlatformFile? _pickedMainFile;
  bool _userDeleteMode = false;
  final Set<String> _userIdsMarkedForDeletion = {};

  /// Per-image URL → framing (persists across sessions).
  Map<String, Map<String, double>> _imageFrames = {};

  double _frameFocusX = 0.5;
  double _frameFocusY = 0.5;
  double _frameZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await SettingsStorage.readAll();
    _appItems = await _loadAppBackgrounds();
    _userItems = _readBackgroundList(data[_storageKey]);
    _imageFrames = _readImageFrames(data[_framesKey]);
    final config = _readCurrentBackground(data["background"]);
    _selectedId = _findMatchingId(config);
    _syncFrameControlsFromSelection(config);
    setState(() => _loading = false);
  }

  Map<String, Map<String, double>> _readImageFrames(dynamic value) {
    if (value is! Map) return {};
    final out = <String, Map<String, double>>{};
    for (final e in value.entries) {
      final url = e.key.toString();
      final raw = e.value;
      if (raw is! Map) continue;
      final m = raw.map((k, v) => MapEntry(k.toString(), v));
      out[url] = {
        'focusX': (m['focusX'] as num?)?.toDouble() ?? 0.5,
        'focusY': (m['focusY'] as num?)?.toDouble() ?? 0.5,
        'zoom': (m['zoom'] as num?)?.toDouble() ?? 1.0,
      };
    }
    return out;
  }

  Map<String, dynamic> _imageFramesToJson() {
    return _imageFrames.map(
      (k, v) => MapEntry(
        k,
        {
          'focusX': v['focusX'] ?? 0.5,
          'focusY': v['focusY'] ?? 0.5,
          'zoom': v['zoom'] ?? 1.0,
        },
      ),
    );
  }

  BackgroundItem? _getSelectedItem() {
    for (final i in _appItems) {
      if (i.id == _selectedId) return i;
    }
    for (final i in _userItems) {
      if (i.id == _selectedId) return i;
    }
    return null;
  }

  void _syncFrameControlsFromSelection(BackgroundConfig? saved) {
    final item = _getSelectedItem();
    if (item != null &&
        (item.type == 'image' || item.type == 'video')) {
      final f = _imageFrames[item.url];
      _frameFocusX = (f?['focusX'] ?? 0.5).clamp(0.0, 1.0);
      _frameFocusY = (f?['focusY'] ?? 0.5).clamp(0.0, 1.0);
      _frameZoom = (f?['zoom'] ?? 1.0).clamp(1.0, 3.0);
      return;
    }
    if (saved != null &&
        (saved.type == 'image' || saved.type == 'video') &&
        saved.url.isNotEmpty) {
      _frameFocusX = saved.imageFocusX.clamp(0.0, 1.0);
      _frameFocusY = saved.imageFocusY.clamp(0.0, 1.0);
      _frameZoom = saved.imageZoom.clamp(1.0, 3.0);
      return;
    }
    _frameFocusX = 0.5;
    _frameFocusY = 0.5;
    _frameZoom = 1.0;
  }

  BackgroundConfig _configForItem(BackgroundItem item) {
    if (item.type == 'image' || item.type == 'video') {
      final isSelected = item.id == _selectedId;
      if (isSelected) {
        return BackgroundConfig(
          type: item.type,
          url: item.url,
          imageFocusX: _frameFocusX.clamp(0.0, 1.0),
          imageFocusY: _frameFocusY.clamp(0.0, 1.0),
          imageZoom: _frameZoom.clamp(1.0, 3.0),
        );
      }
      final f = _imageFrames[item.url];
      return BackgroundConfig(
        type: item.type,
        url: item.url,
        imageFocusX: (f?['focusX'] ?? 0.5).clamp(0.0, 1.0),
        imageFocusY: (f?['focusY'] ?? 0.5).clamp(0.0, 1.0),
        imageZoom: (f?['zoom'] ?? 1.0).clamp(1.0, 3.0),
      );
    }
    return BackgroundConfig(type: item.type, url: item.url);
  }

  void _applyFramingPreview() {
    final item = _getSelectedItem();
    if (item == null || (item.type != 'image' && item.type != 'video')) {
      return;
    }
    widget.onApply(_configForItem(item));
  }

  Future<void> _commitFramingFromEditor(
    double fx,
    double fy,
    double zoom,
  ) async {
    final item = _getSelectedItem();
    if (item == null || (item.type != 'image' && item.type != 'video')) {
      return;
    }
    setState(() {
      _frameFocusX = fx.clamp(0.0, 1.0);
      _frameFocusY = fy.clamp(0.0, 1.0);
      _frameZoom = zoom.clamp(1.0, 3.0);
    });
    _imageFrames[item.url] = {
      'focusX': _frameFocusX,
      'focusY': _frameFocusY,
      'zoom': _frameZoom,
    };
    await SettingsStorage.update({
      _framesKey: _imageFramesToJson(),
      "background": _configForItem(item).toJson(),
    });
    _applyFramingPreview();
  }

  Future<List<BackgroundItem>> _loadAppBackgrounds() async {
    final results = <BackgroundItem>[..._baseBackgrounds];
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys = manifest.listAssets();
      const imagePrefixes = [
        'assets/web/backgroud_images/',
        'assets/web/background_images/',
      ];
      const roomsPrefix = 'assets/web/rooms/';

      for (final entry in keys) {
        if (entry == 'assets/web/rooms/.gitkeep') continue;

        var matched = false;
        for (final prefix in imagePrefixes) {
          if (entry.startsWith(prefix) && _isImageAsset(entry)) {
            final name = entry.split('/').last;
            results.add(
              BackgroundItem(
                id: entry,
                type: 'image',
                url: entry.replaceFirst('assets/web/', ''),
                label: _titleFromFilename(name),
                thumbnail: entry,
                source: 'app',
              ),
            );
            matched = true;
            break;
          }
        }
        if (matched) continue;

        if (entry.startsWith(roomsPrefix)) {
          final lower = entry.toLowerCase();
          if (_isRoomAsset(lower)) {
            final name = entry.split('/').last;
            results.add(
              BackgroundItem(
                id: entry,
                type: 'room',
                url: entry.replaceFirst('assets/web/', ''),
                label: _titleFromFilename(name),
                source: 'app',
              ),
            );
          } else if (_isVideoAsset(lower)) {
            final name = entry.split('/').last;
            results.add(
              BackgroundItem(
                id: entry,
                type: 'video',
                url: entry.replaceFirst('assets/web/', ''),
                label: _titleFromFilename(name),
                source: 'app',
              ),
            );
          }
        }
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

  bool _isRoomAsset(String lowerPath) {
    return lowerPath.endsWith('.glb') || lowerPath.endsWith('.gltf');
  }

  bool _isVideoAsset(String lowerPath) {
    return lowerPath.endsWith('.mp4') ||
        lowerPath.endsWith('.webm') ||
        lowerPath.endsWith('.mov') ||
        lowerPath.endsWith('.m4v');
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

  String _inferMediaExtension(PlatformFile file, String type) {
    final n = file.name;
    final dot = n.lastIndexOf('.');
    if (dot >= 0 && dot < n.length - 1) {
      return n.substring(dot).toLowerCase();
    }
    switch (type) {
      case 'video':
        return '.mp4';
      case 'room':
        return '.glb';
      default:
        return '.bin';
    }
  }

  Future<String?> _persistUserPickedMedia(
    PlatformFile file,
    String type,
  ) async {
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/user_backgrounds');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = _inferMediaExtension(file, type);
      final out = File(
        '${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      if (file.bytes != null) {
        await out.writeAsBytes(file.bytes!, flush: true);
      } else if (file.path != null && file.path!.isNotEmpty) {
        final src = File(file.path!);
        if (await src.exists()) {
          await src.copy(out.path);
        } else {
          return null;
        }
      } else {
        return null;
      }
      return Uri.file(out.path, windows: Platform.isWindows).toString();
    } catch (_) {
      return null;
    }
  }

  /// First-frame (near) JPEG thumbnail for video cards and framing UI.
  Future<String?> _thumbnailFileForVideo(String persistedVideoUri) async {
    try {
      final videoPath = Uri.parse(persistedVideoUri).toFilePath();
      if (!await File(videoPath).exists()) return null;
      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/user_backgrounds/thumbs');
      if (!await dir.exists()) await dir.create(recursive: true);
      final out = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 88,
        timeMs: 400,
      );
      if (out == null || out.isEmpty) return null;
      return Uri.file(out, windows: Platform.isWindows).toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteLocalFileIfAny(String? ref) async {
    if (ref == null || ref.isEmpty) return;
    if (!ref.startsWith('file://')) return;
    try {
      final path = Uri.parse(ref).toFilePath();
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  void _cancelUserDeleteMode() {
    setState(() {
      _userDeleteMode = false;
      _userIdsMarkedForDeletion.clear();
    });
  }

  void _onBackgroundCardTap(BackgroundItem item) {
    if (item.source == 'user' && _userDeleteMode) {
      setState(() {
        if (_userIdsMarkedForDeletion.contains(item.id)) {
          _userIdsMarkedForDeletion.remove(item.id);
          if (_userIdsMarkedForDeletion.isEmpty) {
            _userDeleteMode = false;
          }
        } else {
          _userIdsMarkedForDeletion.add(item.id);
        }
      });
      return;
    }
    if (_userDeleteMode) {
      setState(() {
        _userDeleteMode = false;
        _userIdsMarkedForDeletion.clear();
      });
    }
    _applyItem(item);
  }

  void _onUserCardLongPress(BackgroundItem item) {
    if (item.source != 'user') return;
    setState(() {
      if (!_userDeleteMode) {
        _userDeleteMode = true;
        _userIdsMarkedForDeletion.add(item.id);
      } else {
        if (_userIdsMarkedForDeletion.contains(item.id)) {
          _userIdsMarkedForDeletion.remove(item.id);
        } else {
          _userIdsMarkedForDeletion.add(item.id);
        }
        if (_userIdsMarkedForDeletion.isEmpty) {
          _userDeleteMode = false;
        }
      }
    });
  }

  Future<void> _deleteMarkedUserBackgrounds() async {
    if (_userIdsMarkedForDeletion.isEmpty) return;

    final data = await SettingsStorage.readAll();
    final current = _readCurrentBackground(data['background']);
    final toRemove = _userItems
        .where((e) => _userIdsMarkedForDeletion.contains(e.id))
        .toList();

    for (final item in toRemove) {
      _imageFrames.remove(item.url);
      await _deleteLocalFileIfAny(item.url);
      await _deleteLocalFileIfAny(item.thumbnail);
    }

    final shouldClearBackground = current != null &&
        toRemove.any(
          (e) => e.type == current.type && e.url == current.url,
        );

    final remaining = _userItems
        .where((e) => !_userIdsMarkedForDeletion.contains(e.id))
        .toList();

    final patch = <String, dynamic>{
      _storageKey: remaining.map((e) => e.toJson()).toList(),
      _framesKey: _imageFramesToJson(),
    };

    if (shouldClearBackground) {
      patch['background'] =
          const BackgroundConfig(type: 'none', url: '').toJson();
    }

    await SettingsStorage.update(patch);

    setState(() {
      _userItems = remaining;
      _userDeleteMode = false;
      _userIdsMarkedForDeletion.clear();
      if (shouldClearBackground) {
        _selectedId = 'builtin_none';
      } else {
        _selectedId = _findMatchingId(current);
      }
    });

    if (shouldClearBackground) {
      widget.onApply(const BackgroundConfig(type: 'none', url: ''));
    }
  }

  Future<void> _applyItem(BackgroundItem item) async {
    final f = _imageFrames[item.url];
    if (item.type == 'image' || item.type == 'video') {
      _frameFocusX = (f?['focusX'] ?? 0.5).clamp(0.0, 1.0);
      _frameFocusY = (f?['focusY'] ?? 0.5).clamp(0.0, 1.0);
      _frameZoom = (f?['zoom'] ?? 1.0).clamp(1.0, 3.0);
    }
    final config = _configForItem(item);
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

    PlatformFile? mainFile = _pickedMainFile;
    if (mainFile == null && picked != null && picked.isNotEmpty) {
      mainFile = PlatformFile(
        name: picked.split(RegExp(r'[/\\]')).last,
        path: picked.startsWith('file://') ? Uri.parse(picked).toFilePath() : picked,
        size: 0,
      );
    }

    if (mainFile == null) {
      setState(() => _formError = "Pick a file first.");
      return;
    }

    final persistedUrl = await _persistUserPickedMedia(mainFile, _newType);
    if (persistedUrl == null || persistedUrl.isEmpty) {
      setState(
        () => _formError = "Could not save that file. Try picking it again.",
      );
      return;
    }

    String? thumbRef;
    if (_newType == "image") {
      thumbRef = persistedUrl;
    } else if (_newType == "video") {
      thumbRef = await _thumbnailFileForVideo(persistedUrl);
      if (thumbRef == null) {
        await _deleteLocalFileIfAny(persistedUrl);
        setState(
          () => _formError =
              "Could not create a preview image for this video. Try another file or format.",
        );
        return;
      }
    }

    final item = BackgroundItem(
      id: "user_${DateTime.now().millisecondsSinceEpoch}",
      type: _newType,
      url: persistedUrl,
      label: label,
      thumbnail: thumbRef,
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
      _pickedMainFile = null;
    });
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
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null && file.bytes == null) {
      setState(() => _formError = "Could not read that file.");
      return;
    }
    setState(() {
      _pickedMainFile = file;
      _pickedPath = file.path ?? file.name;
      _formError = null;
      if (_labelController.text.trim().isEmpty) {
        _labelController.text = _titleFromFilename(file.name);
      }
    });
  }

  Widget _buildTypeChip(String label, String type, IconData icon) {
    final selected = _newType == type;
    return GestureDetector(
      onTap: () => setState(() {
        _newType = type;
        _pickedPath = null;
        _pickedMainFile = null;
        _formError = null;
      }),
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
      onTap: () => setState(() {
        _userDeleteMode = false;
        _userIdsMarkedForDeletion.clear();
        _showAddForm = !_showAddForm;
      }),
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

  Widget _buildImageVideoFramingPanel() {
    final item = _getSelectedItem();
    if (item == null || (item.type != 'image' && item.type != 'video')) {
      return const SizedBox.shrink();
    }
    final canEdit = backgroundFramingImageProvider(
          type: item.type,
          url: item.url,
          thumbnail: item.thumbnail,
        ) !=
        null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        _buildSectionTitle("Framing"),
        const Text(
          "Open the editor: drag to pan, pinch to zoom. The frame shows what appears behind the avatar.",
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: !canEdit
                ? null
                : () {
                    final mq = MediaQuery.of(context);
                    final aspect = mq.size.width / math.max(mq.size.height, 1.0);
                    openBackgroundFramingEditor(
                      context: context,
                      type: item.type,
                      url: item.url,
                      thumbnail: item.thumbnail,
                      viewAspect: aspect,
                      initialFocusX: _frameFocusX,
                      initialFocusY: _frameFocusY,
                      initialZoom: _frameZoom,
                      onApply: (fx, fy, z) {
                        unawaited(_commitFramingFromEditor(fx, fy, z));
                      },
                    );
                  },
            icon: const Icon(Icons.crop_free, color: Colors.lightBlueAccent, size: 20),
            label: Text(
              canEdit ? "Adjust with touch" : "Adjust (add image / re-save video)",
              style: TextStyle(
                color: canEdit ? Colors.lightBlueAccent : Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
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
                              onTap: () => _onBackgroundCardTap(item),
                              subtitle: _typeLabel(item.type),
                              fallbackIcon: _typeIcon(item.type),
                            ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    _buildSectionTitle("Your backgrounds"),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        "Long-press your card to select and delete.",
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    if (_userDeleteMode) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: _cancelUserDeleteMode,
                              child: const Text(
                                "Cancel",
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _userIdsMarkedForDeletion.isEmpty
                                  ? null
                                  : () => _deleteMarkedUserBackgrounds(),
                              child: Text(
                                "Delete (${_userIdsMarkedForDeletion.length})",
                                style: TextStyle(
                                  color: _userIdsMarkedForDeletion.isEmpty
                                      ? Colors.white24
                                      : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final item in _userItems)
                          BackgroundCard(
                            item: item,
                            selected: _selectedId == item.id,
                            onTap: () => _onBackgroundCardTap(item),
                            onLongPress: () => _onUserCardLongPress(item),
                            deleteSelectionMode: _userDeleteMode,
                            markedForDeletion: _userIdsMarkedForDeletion
                                .contains(item.id),
                            subtitle: _typeLabel(item.type),
                            fallbackIcon: _typeIcon(item.type),
                          ),
                        _buildAddCard(),
                      ],
                    ),
                    _buildImageVideoFramingPanel(),
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
                            if (_newType == "video")
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  "A preview image is created automatically from your video.",
                                  style: TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ),
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
