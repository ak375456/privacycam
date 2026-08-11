import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/presentation/widgets/image_geometry.dart';
import 'package:privacycam/presentation/widgets/pdf_review_outline.dart';

void main() {
  final geometry = ImageGeometry(const Size(400, 600), const Size(1200, 1800));

  RedactionItem item({
    RedactionCategory category = RedactionCategory.otherText,
    bool selected = false,
  }) => RedactionItem(
    id: 'item',
    category: category,
    bounds: const Rect.fromLTWH(100, 200, 500, 30),
    selected: selected,
    style: RedactionStyle.blackout,
    source: RedactionSource.automatic,
  );

  test('ordinary text outlines use progressive disclosure', () {
    expect(PdfReviewOutlineLayout.isVisible(item(), 1), isFalse);
    expect(PdfReviewOutlineLayout.isVisible(item(), 1.59), isFalse);
    expect(PdfReviewOutlineLayout.isVisible(item(), 1.6), isTrue);
    expect(PdfReviewOutlineLayout.isVisible(item(selected: true), 1), isTrue);
    expect(
      PdfReviewOutlineLayout.isVisible(
        item(category: RedactionCategory.email),
        1,
      ),
      isTrue,
    );
  });

  test('outline is padded outside text and remains hairline at every zoom', () {
    final detected = item(selected: true);
    final textRect = geometry.toLocalRect(detected.bounds);
    final fittedOutline = PdfReviewOutlineLayout.rectFor(geometry, detected, 1);
    final zoomedOutline = PdfReviewOutlineLayout.rectFor(geometry, detected, 4);

    expect(fittedOutline.left, lessThan(textRect.left));
    expect(fittedOutline.top, lessThan(textRect.top));
    expect(fittedOutline.right, greaterThan(textRect.right));
    expect(fittedOutline.bottom, greaterThan(textRect.bottom));
    expect(fittedOutline.left, textRect.left - 3);
    expect(zoomedOutline.left, textRect.left - .75);
    expect(PdfReviewOutlineLayout.strokeWidth(detected, 1), 1.25);
    expect(PdfReviewOutlineLayout.strokeWidth(detected, 4), .3125);
  });
}
