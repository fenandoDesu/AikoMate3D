import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:aikomate_flutter/core/api/templates_api.dart';
import 'package:aikomate_flutter/features/create/data/read_platform_file.dart';

/// Must match presign `fileType` and the R2 `PUT` `Content-Type` header.
const _vrmFileType = 'model/vrm';
const _allowedCoverExt = {'png', 'jpg', 'jpeg', 'webp'};

class CreateTemplateScreen extends StatefulWidget {
  const CreateTemplateScreen({super.key});

  @override
  State<CreateTemplateScreen> createState() => _CreateTemplateScreenState();
}

class _CreateTemplateScreenState extends State<CreateTemplateScreen> {
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _fishAudioIdController = TextEditingController();

  PlatformFile? _vrmFile;
  PlatformFile? _coverImageFile;
  bool _public = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _promptController.dispose();
    _descriptionController.dispose();
    _fishAudioIdController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _readBytes(PlatformFile f) => readPlatformFileBytes(f);

  Future<void> _pickVrm() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['vrm'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _vrmFile = result.files.first;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final title =
        _titleController.text.trim().isEmpty
            ? name
            : _titleController.text.trim();
    final prompt = _promptController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a character name.');
      return;
    }
    if (prompt.isEmpty) {
      setState(() => _error = 'Enter a personality prompt.');
      return;
    }
    final fishAudioIdTrim = _fishAudioIdController.text.trim();
    if (fishAudioIdTrim.length > templateFishAudioIdMaxLength) {
      setState(
        () => _error =
            'Fish Audio voice id must be at most $templateFishAudioIdMaxLength characters.',
      );
      return;
    }
    if (_vrmFile == null) {
      setState(() => _error = 'Select a VRM model.');
      return;
    }
    if (_coverImageFile == null) {
      setState(() => _error = 'Select a cover image.');
      return;
    }

    final fileName = _vrmFile!.name.trim();
    if (!fileName.toLowerCase().endsWith('.vrm')) {
      setState(
        () => _error = 'File name must end with .vrm (required by the server).',
      );
      return;
    }

    final vrmBytes = await _readBytes(_vrmFile!);
    if (vrmBytes == null) {
      setState(() => _error = 'Could not read the VRM file.');
      return;
    }
    final coverBytes = await _readBytes(_coverImageFile!);
    if (coverBytes == null) {
      setState(() => _error = 'Could not read the cover image file.');
      return;
    }
    if (_coverContentType(_coverImageFile!) == null) {
      setState(
        () => _error = 'Cover image must be one of: .png, .jpg, .jpeg, .webp.',
      );
      return;
    }
    final convertedCover = await _convertCoverToWebp(
      bytes: coverBytes,
      originalFileName: _coverImageFile!.name,
    );
    if (convertedCover == null) {
      setState(() => _error = 'Could not convert cover image to WebP.');
      return;
    }
    final coverContentType = 'image/webp';

    setState(() {
      _submitting = true;
      _error = null;
    });

    final vrmMeta = TemplateVrmPresignMeta(
      fileName: fileName,
      fileType: _vrmFileType,
      fileSize: vrmBytes.length,
    );
    final coverMeta = TemplateCoverImagePresignMeta(
      fileName: convertedCover.fileName,
      fileType: coverContentType,
      fileSize: convertedCover.bytes.length,
    );

    final urls = await requestTemplateUploadUrls(
      vrm: vrmMeta,
      coverImage: coverMeta,
    );
    if (!urls.success || urls.vrm == null || urls.coverImage == null) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = urls.error ?? 'Upload URL request failed';
        });
      }
      return;
    }

    final putVrm = await putFileToPresignedUrl(
      uploadUrl: urls.vrm!.uploadUrl,
      bytes: vrmBytes,
      contentType: _vrmFileType,
    );
    if (putVrm.statusCode < 200 || putVrm.statusCode >= 300) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error =
              'VRM upload failed (${putVrm.statusCode}). Content-Type must match presign fileType ($_vrmFileType).';
        });
      }
      return;
    }

    final putCover = await putFileToPresignedUrl(
      uploadUrl: urls.coverImage!.uploadUrl,
      bytes: convertedCover.bytes,
      contentType: coverContentType,
    );
    if (putCover.statusCode < 200 || putCover.statusCode >= 300) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Cover image upload failed (${putCover.statusCode}).';
        });
      }
      return;
    }

    final description = _descriptionController.text.trim();
    final visibility = _public ? 'public' : 'private';

    final created = await createTemplate(
      name: name,
      title: title,
      description: description,
      prompt: prompt,
      visibility: visibility,
      vrmTarget: urls.vrm!,
      coverImageTarget: urls.coverImage!,
      vrmSize: vrmBytes.length,
      coverImageSize: convertedCover.bytes.length,
      vrmContentType: _vrmFileType,
      coverImageContentType: coverContentType,
      fishAudioId: fishAudioIdTrim.isEmpty ? null : fishAudioIdTrim,
    );

    if (!mounted) return;

    setState(() => _submitting = false);

    if (!created.success) {
      setState(() => _error = created.error ?? 'Create template failed');
      return;
    }

    final status = created.rawBody?['status']?.toString() ?? 'unknown';
    final modNote = created.rawBody?['moderationNote']?.toString();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Template created'),
            content: Text(
              _successMessage(
                visibility: visibility,
                status: status,
                moderationNote: modNote,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _pickCoverImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedCoverExt.toList(),
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _coverImageFile = result.files.first;
      _error = null;
    });
  }

  String? _coverContentType(PlatformFile file) {
    final name = file.name.toLowerCase().trim();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  Future<_WebpCover?> _convertCoverToWebp({
    required Uint8List bytes,
    required String originalFileName,
  }) async {
    final encoded = await FlutterImageCompress.compressWithList(
      bytes,
      format: CompressFormat.webp,
      quality: 84,
      keepExif: false,
    );
    if (encoded.isEmpty) return null;
    return _WebpCover(
      bytes: encoded,
      fileName: _toWebpFileName(originalFileName),
    );
  }

  String _toWebpFileName(String original) {
    final trimmed = original.trim();
    final dot = trimmed.lastIndexOf('.');
    final base = dot > 0 ? trimmed.substring(0, dot) : trimmed;
    final sanitized = base.isEmpty ? 'cover' : base;
    return '$sanitized.webp';
  }

  String _successMessage({
    required String visibility,
    required String status,
    String? moderationNote,
  }) {
    if (visibility == 'public') {
      var s =
          'Your template was submitted. Status: $status. Public templates stay pending until an admin approves; you can refresh status from My templates or the template detail screen.';
      if (moderationNote != null && moderationNote.isNotEmpty) {
        s += '\n\nNote: $moderationNote';
      }
      return s;
    }
    return 'Your template is ready. Status: $status. Load the model from the template’s vrm.fileUrl when you open it in the viewer.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create template')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Character name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Listing title',
                hintText: 'Defaults to character name if empty',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: 'Personality prompt',
                hintText: 'How the character behaves and speaks',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Short blurb for cards / store',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fishAudioIdController,
              decoration: const InputDecoration(
                labelText: 'Fish Audio voice id (optional)',
                hintText: 'Voice reference_id — same as chat fish_audio_id',
                border: OutlineInputBorder(),
                helperText:
                    'Up to $templateFishAudioIdMaxLength characters. Leave empty to use the server default voice for your language.',
              ),
              maxLength: templateFishAudioIdMaxLength,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('VRM model'),
              subtitle: Text(_vrmFile?.name ?? 'No file selected'),
              trailing: FilledButton.tonal(
                onPressed: _submitting ? null : _pickVrm,
                child: const Text('Choose'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Uses fileType $_vrmFileType for presign and R2 upload (must match server).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Cover image'),
              subtitle: Text(_coverImageFile?.name ?? 'No file selected'),
              trailing: FilledButton.tonal(
                onPressed: _submitting ? null : _pickCoverImage,
                child: const Text('Choose'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Required for Discover card. Allowed: .png, .jpg, .jpeg, .webp.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Public on Discover'),
              subtitle: const Text(
                'Public templates start as pending until an admin approves.',
              ),
              value: _public,
              onChanged:
                  _submitting
                      ? null
                      : (v) => setState(() {
                        _public = v;
                        _error = null;
                      }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child:
                  _submitting
                      ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Text('Upload & create template'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebpCover {
  const _WebpCover({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}
