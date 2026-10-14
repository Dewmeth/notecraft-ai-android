import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as im;

/// Filter modes shown in the Editor. All filters retain pixel-level strokes.
/// They do NOT invent content or reconstruct missing handwriting.
enum ScanStyle { paper, color, mono, original }

extension ScanStyleName on ScanStyle {
  String get label => switch (this) {
    ScanStyle.paper => 'Clean paper',
    ScanStyle.color => 'Color boost',
    ScanStyle.mono => 'Black ink',
    ScanStyle.original => 'Original',
  };
}

/// Serializable inputs let Flutter run heavy pixel work in a background isolate.
class EnhancementRequest {
  const EnhancementRequest(this.bytes, this.styleIndex, this.rotation);
  final Uint8List bytes;
  final int styleIndex;
  final int rotation;
}

class ScanEnhancement {
  static Future<Uint8List> process(Uint8List input, ScanStyle style, {int rotation = 0}) =>
      compute(_processPixels, EnhancementRequest(input, style.index, rotation));
}

/// Pure Dart image processing; executed away from the UI thread.
/// Output is JPEG at up to 2000 px on the longest edge to control memory.
/// The "paper" mode whitens dull paper, emphasizes fine ink and retains colors.
Uint8List _processPixels(EnhancementRequest request) {
  var decoded = im.decodeImage(request.bytes);
  if (decoded == null) throw const FormatException('Unsupported image file');
  decoded = im.bakeOrientation(decoded);
  if (request.rotation % 360 != 0) {
    decoded = im.copyRotate(decoded, angle: request.rotation.toDouble());
  }
  const maxEdge = 2000;
  final biggest = decoded.width > decoded.height ? decoded.width : decoded.height;
  if (biggest > maxEdge) {
    final ratio = maxEdge / biggest;
    decoded = im.copyResize(decoded,
      width: (decoded.width * ratio).round(),
      height: (decoded.height * ratio).round(),
      interpolation: im.Interpolation.linear);
  }
  final mode = ScanStyle.values[request.styleIndex];
  if (mode == ScanStyle.original) return Uint8List.fromList(im.encodeJpg(decoded, quality: 93));

  // Estimate the background illumination independently in small paper regions.
  // Unlike simple global contrast, this flattens desk shadows and dark corners.
  const tile = 120;
  final cols = (decoded.width + tile - 1) ~/ tile;
  final rows = (decoded.height + tile - 1) ~/ tile;
  final backgrounds = List<double>.filled(cols * rows, 220);
  for (var ty = 0; ty < rows; ty++) {
    for (var tx = 0; tx < cols; tx++) {
      final samples = <double>[];
      for (var y = ty * tile; y < (ty + 1) * tile && y < decoded.height; y += 7) {
        for (var x = tx * tile; x < (tx + 1) * tile && x < decoded.width; x += 7) {
          final p = decoded.getPixel(x, y);
          samples.add(.2126 * p.r + .7152 * p.g + .0722 * p.b);
        }
      }
      samples.sort();
      if (samples.isNotEmpty) {
        backgrounds[ty * cols + tx] = samples[(samples.length * .86).floor().clamp(0, samples.length - 1).toInt()];
      }
    }
  }
  for (final pixel in decoded) {
    final r = pixel.r.toDouble();
    final g = pixel.g.toDouble();
    final b = pixel.b.toDouble();
    final luma = .2126 * r + .7152 * g + .0722 * b;
    // Bilinear interpolation prevents visible boundaries between background tiles.
    final fx = (pixel.x / tile - .5).clamp(0.0, (cols - 1).toDouble());
    final fy = (pixel.y / tile - .5).clamp(0.0, (rows - 1).toDouble());
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = (x0 + 1).clamp(0, cols - 1).toInt();
    final y1 = (y0 + 1).clamp(0, rows - 1).toInt();
    final dx = fx - x0, dy = fy - y0;
    final top = backgrounds[y0 * cols + x0] * (1 - dx) + backgrounds[y0 * cols + x1] * dx;
    final bottom = backgrounds[y1 * cols + x0] * (1 - dx) + backgrounds[y1 * cols + x1] * dx;
    final bg = top * (1 - dy) + bottom * dy;
    final target = mode == ScanStyle.color ? 238.0 : 250.0;
    final factor = (target / bg.clamp(75.0, 255.0)).clamp(.85, 2.30);
    final corrected = (luma * factor).clamp(0.0, 255.0);
    if (mode == ScanStyle.mono) {
      // Smooth contrast preserves fine pencil / cursive strokes over hard binarization.
      final ink = ((corrected - 45) / 178).clamp(0.0, 1.0);
      final gray = (ink * ink * (3 - 2 * ink) * 255).round().clamp(0, 255).toInt();
      pixel.r = gray; pixel.g = gray; pixel.b = gray;
    } else {
      final strength = mode == ScanStyle.paper ? 1.07 : 1.34;
      // Restore colorful pen ink, highlighting and diagram labels after flattening.
      final lift = mode == ScanStyle.paper && corrected > 206
          ? (corrected + (255 - corrected) * .58).clamp(0.0, 255.0)
          : corrected;
      pixel.r = (lift + (r - luma) * factor * strength).round().clamp(0, 255).toInt();
      pixel.g = (lift + (g - luma) * factor * strength).round().clamp(0, 255).toInt();
      pixel.b = (lift + (b - luma) * factor * strength).round().clamp(0, 255).toInt();
    }
  }
  return Uint8List.fromList(im.encodeJpg(decoded, quality: 91));
}
