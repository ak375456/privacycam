import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/domain/pdf_models.dart';
import 'package:privacycam/state/pdf_providers.dart';

class _TestPdfController extends PdfSessionController {
  _TestPdfController(this.initial);

  final PdfSession initial;

  @override
  PdfSession? build() => initial;
}

void main() {
  test('eraser cuts a detected text mask and Undo restores it', () {
    const detected = RedactionItem(
      id: 'address',
      category: RedactionCategory.address,
      bounds: Rect.fromLTWH(10, 20, 100, 12),
      selected: true,
      style: RedactionStyle.blackout,
      source: RedactionSource.automatic,
    );
    const session = PdfSession(
      sourcePath: 'source.pdf',
      fileName: 'source.pdf',
      status: PdfWorkStatus.ready,
      pages: [
        PdfPageSession(
          pageNumber: 1,
          widthPoints: 100,
          heightPoints: 100,
          image: ImageSession(
            sourcePath: 'page.jpg',
            width: 100,
            height: 100,
            items: [detected],
          ),
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        pdfSessionProvider.overrideWith(() => _TestPdfController(session)),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(pdfSessionProvider.notifier);

    expect(controller.eraseAt(const Offset(60, 26), radius: 8), isTrue);
    var image = container.read(pdfSessionProvider)!.currentPage!.image;
    expect(image.items.single.selected, isFalse);
    expect(image.strokes, hasLength(2));

    controller.undo();
    image = container.read(pdfSessionProvider)!.currentPage!.image;
    expect(image.items.single.selected, isTrue);
    expect(image.strokes, isEmpty);
  });
}
