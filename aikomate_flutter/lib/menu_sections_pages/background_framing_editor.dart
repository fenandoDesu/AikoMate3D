import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Image / thumbnail source for the framing UI (same rules as background thumbnails).
ImageProvider? backgroundFramingImageProvider({
  required String type,
  required String url,
  String? thumbnail,
}) {
  if (type == 'image') {
    final thumb = thumbnail?.trim();
    if (thumb != null && thumb.isNotEmpty) {
      if (thumb.startsWith('assets/')) return AssetImage(thumb);
    }
    final u = url.trim();
    if (u.startsWith('file://')) {
      return FileImage(File(Uri.parse(u).toFilePath()));
    }
    if (u.startsWith('assets/')) return AssetImage(u);
    if (!u.contains('://')) return AssetImage('assets/web/$u');
  }
  if (type == 'video') {
    final t = thumbnail?.trim();
    if (t == null || t.isEmpty) return null;
    if (t.startsWith('assets/')) return AssetImage(t);
    if (t.startsWith('file://')) {
      return FileImage(File(Uri.parse(t).toFilePath()));
    }
  }
  return null;
}

/// Same cover UV math as [viewer.js] `applyRasterCoverToTexture` (flipY true for scene.background).
Rect _srcRectForFrame(
  double iw,
  double ih,
  double viewAspect,
  double focusX,
  double focusY,
  double zoom,
) {
  final ia = iw / ih;
  final z = zoom.clamp(0.5, 4.0);
  final fx = focusX.clamp(0.0, 1.0);
  final fy = focusY.clamp(0.0, 1.0);

  double repeatX;
  double repeatY;
  if (ia > viewAspect) {
    repeatX = (viewAspect / ia) / z;
    repeatY = 1 / z;
  } else {
    repeatX = 1 / z;
    repeatY = (ia / viewAspect) / z;
  }

  final offsetX = fx * (1 - repeatX);
  final offsetY = fy * (1 - repeatY);

  final srcLeft = offsetX * iw;
  final srcW = repeatX * iw;
  final srcH = repeatY * ih;
  final srcTop = (1.0 - offsetY - repeatY) * ih;

  return Rect.fromLTWH(srcLeft, srcTop, srcW, srcH);
}

Rect _centeredHole(Size size, double viewAspect) {
  final w = size.width;
  final h = size.height;
  double holeW;
  double holeH;
  if (w / h > viewAspect) {
    holeH = h * 0.72;
    holeW = holeH * viewAspect;
  } else {
    holeW = w * 0.92;
    holeH = holeW / viewAspect;
  }
  final left = (w - holeW) / 2;
  final top = (h - holeH) / 2;
  return Rect.fromLTWH(left, top, holeW, holeH);
}

class _FramingPreviewPainter extends CustomPainter {
  _FramingPreviewPainter({
    required this.image,
    required this.viewAspect,
    required this.focusX,
    required this.focusY,
    required this.zoom,
  });

  final ui.Image? image;
  final double viewAspect;
  final double focusX;
  final double focusY;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = _centeredHole(size, viewAspect);
    final rHole = RRect.fromRectXY(hole, 6, 6);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101010),
    );

    if (image == null) return;

    final iw = image!.width.toDouble();
    final ih = image!.height.toDouble();
    final src = _srcRectForFrame(iw, ih, viewAspect, focusX, focusY, zoom);

    canvas.save();
    canvas.clipRRect(rHole);
    canvas.drawImageRect(
      image!,
      src,
      hole,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xAA000000),
    );
    canvas.drawRRect(rHole, Paint()..blendMode = BlendMode.dstOut);
    canvas.restore();

    canvas.drawRRect(
      rHole,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawRRect(
      rHole,
      Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
  }

  @override
  bool shouldRepaint(covariant _FramingPreviewPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.focusX != focusX ||
        oldDelegate.focusY != focusY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.viewAspect != viewAspect;
  }
}

/// Pinch to zoom, drag to pan — updates framing to match the WebGL viewer.
class BackgroundFramingEditor extends StatefulWidget {
  const BackgroundFramingEditor({
    super.key,
    required this.imageProvider,
    required this.viewAspect,
    required this.initialFocusX,
    required this.initialFocusY,
    required this.initialZoom,
    required this.onDone,
    required this.onCancel,
  });

  final ImageProvider imageProvider;
  final double viewAspect;
  final double initialFocusX;
  final double initialFocusY;
  final double initialZoom;
  final void Function(double focusX, double focusY, double zoom) onDone;
  final VoidCallback onCancel;

  @override
  State<BackgroundFramingEditor> createState() => _BackgroundFramingEditorState();
}

class _BackgroundFramingEditorState extends State<BackgroundFramingEditor> {
  ui.Image? _image;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  late double _focusX;
  late double _focusY;
  late double _zoom;

  double _pinchStartZoom = 1;
  Offset _panStartFocus = Offset.zero;
  Offset _panAccum = Offset.zero;
  Size _paintSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _focusX = widget.initialFocusX.clamp(0.0, 1.0);
    _focusY = widget.initialFocusY.clamp(0.0, 1.0);
    _zoom = widget.initialZoom.clamp(1.0, 3.0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveImage());
  }

  void _resolveImage() {
    final stream = widget.imageProvider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _image = info.image);
      },
      onError: (_, __) {
        if (mounted) setState(() => _image = null);
      },
    );
    _stream = stream;
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails d) {
    _pinchStartZoom = _zoom;
    _panStartFocus = Offset(_focusX, _focusY);
    _panAccum = Offset.zero;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _zoom = (_pinchStartZoom * d.scale).clamp(1.0, 3.0);
      _panAccum += d.focalPointDelta;
      final w = math.max(_paintSize.width, 120.0);
      final h = math.max(_paintSize.height, 120.0);
      final kx = 1.25 / (w * _zoom);
      final ky = 1.25 / (h * _zoom);
      _focusX = (_panStartFocus.dx - _panAccum.dx * kx).clamp(0.0, 1.0);
      _focusY = (_panStartFocus.dy + _panAccum.dy * ky).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Framing',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Drag to move. Pinch to zoom. The framed area matches what you see behind the avatar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 380,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _paintSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: CustomPaint(
                    painter: _FramingPreviewPainter(
                      image: _image,
                      viewAspect: widget.viewAspect,
                      focusX: _focusX,
                      focusY: _focusY,
                      zoom: _zoom,
                    ),
                    child: _image == null
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.white54),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => widget.onDone(_focusX, _focusY, _zoom),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openBackgroundFramingEditor({
  required BuildContext context,
  required String type,
  required String url,
  String? thumbnail,
  required double viewAspect,
  required double initialFocusX,
  required double initialFocusY,
  required double initialZoom,
  required void Function(double fx, double fy, double zoom) onApply,
}) async {
  final provider = backgroundFramingImageProvider(
    type: type,
    url: url,
    thumbnail: thumbnail,
  );
  if (provider == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No preview image for this background.'),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) {
      return Dialog(
        backgroundColor: const Color(0xFF1A1A1E),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SizedBox(
          width: 380,
          height: 520,
          child: BackgroundFramingEditor(
            imageProvider: provider,
            viewAspect: viewAspect,
            initialFocusX: initialFocusX,
            initialFocusY: initialFocusY,
            initialZoom: initialZoom,
            onCancel: () => Navigator.of(ctx).pop(),
            onDone: (fx, fy, z) {
              Navigator.of(ctx).pop();
              onApply(fx, fy, z);
            },
          ),
        ),
      );
    },
  );
}
