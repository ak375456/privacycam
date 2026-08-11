import 'dart:ui';

import '../../domain/models.dart';
import 'image_geometry.dart';

/// Keeps PDF review annotations useful without painting over document text.
class PdfReviewOutlineLayout {
  const PdfReviewOutlineLayout._();

  static const ordinaryTextRevealScale = 1.6;

  static bool isVisible(RedactionItem item, double viewerScale) =>
      item.selected ||
      item.category != RedactionCategory.otherText ||
      viewerScale >= ordinaryTextRevealScale;

  static Rect rectFor(
    ImageGeometry geometry,
    RedactionItem item,
    double viewerScale,
  ) {
    final scale = viewerScale.clamp(1.0, 8.0);
    final screenPadding = item.category == RedactionCategory.otherText
        ? 3.0
        : 2.5;
    return geometry.toLocalRect(item.bounds).inflate(screenPadding / scale);
  }

  static double strokeWidth(RedactionItem item, double viewerScale) {
    final scale = viewerScale.clamp(1.0, 8.0);
    return (item.selected ? 1.25 : 1.0) / scale;
  }
}
