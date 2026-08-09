import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Rasterizes the map's custom marker bitmaps: a circular photo thumbnail
/// with a white border and soft shadow for individual memories, and a
/// themed count badge for clusters — matching TouchGrass's forest/nature
/// visual language instead of the generic default Google Maps pins.
///
/// Stateless; callers are responsible for caching results (marker generation
/// is comparatively expensive and shouldn't be repeated every rebuild).
abstract final class PhotoMarkerGenerator {
  static const double baseDiameter = 48;
  static const double selectedDiameter = 60;

  // Supersample so the rasterized PNG stays crisp at the device's actual
  // pixel density instead of looking soft when Google Maps upscales it.
  static const double _rasterScale = 3.0;

  /// Loads and decodes [url] into a [ui.Image], independent of any marker
  /// rendering. Split out from marker rasterization so callers can cache the
  /// decoded image per photo URL and reuse it across, e.g., a marker's
  /// selected and unselected variants — toggling selection then only re-runs
  /// the (cheap) canvas step instead of re-fetching over the network. Throws
  /// on any load failure (network error, decode error).
  static Future<ui.Image> loadImage(String url) {
    final completer = Completer<ui.Image>();
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Rasterizes a circular photo marker from an already-decoded [image] (see
  /// [loadImage]). Synchronous work only — no network access — so this is
  /// cheap enough to re-run whenever just the selected state changes.
  static Future<BitmapDescriptor> rasterizePhotoMarker({
    required ui.Image image,
    required bool selected,
    required Color accentColor,
  }) async {
    final logicalDiameter = selected ? selectedDiameter : baseDiameter;
    final diameter = logicalDiameter * _rasterScale;
    final borderWidth = (selected ? 4.0 : 3.0) * _rasterScale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(diameter / 2, diameter / 2);
    final photoRadius = diameter / 2 - borderWidth;

    // Soft shadow, baked into the raster since Marker doesn't support
    // BoxShadow natively.
    canvas.drawCircle(
      center,
      photoRadius + borderWidth * 0.6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // White border ring.
    canvas.drawCircle(
      center,
      photoRadius + borderWidth,
      Paint()..color = Colors.white,
    );

    // Clipped, cover-fitted photo.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: photoRadius)),
    );
    final srcSize = Size(image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromCircle(center: center, radius: photoRadius);
    final fitted = applyBoxFit(BoxFit.cover, srcSize, dstRect.size);
    final srcRect =
        Alignment.center.inscribe(fitted.source, Offset.zero & srcSize);
    canvas.drawImageRect(
      image,
      srcRect,
      dstRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    if (selected) {
      canvas.drawCircle(
        center,
        photoRadius + borderWidth,
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth * 0.7,
      );
    }

    final rendered = await recorder
        .endRecording()
        .toImage(diameter.round(), diameter.round());
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: _rasterScale,
    );
  }

  /// Builds a cluster marker showing [count] inside a themed circle.
  static Future<BitmapDescriptor> buildClusterMarker({
    required int count,
    required Color color,
  }) async {
    const logicalDiameter = baseDiameter;
    const diameter = logicalDiameter * _rasterScale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(diameter / 2, diameter / 2);
    const borderWidth = 3.0 * _rasterScale;
    const radius = diameter / 2 - borderWidth;

    canvas.drawCircle(
      center,
      radius + borderWidth * 0.6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      center,
      radius + borderWidth,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(center, radius, Paint()..color = color);

    final label = count > 99 ? '99+' : '$count';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: (label.length > 2 ? 15.0 : 18.0) * _rasterScale,
          fontWeight: FontWeight.w800,
          fontFamily: 'Nunito',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );

    final rendered = await recorder
        .endRecording()
        .toImage(diameter.round(), diameter.round());
    final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: _rasterScale,
    );
  }
}
