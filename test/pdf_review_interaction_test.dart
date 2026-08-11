import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/domain/pdf_models.dart';
import 'package:privacycam/presentation/screens/pdf_review_screen.dart';
import 'package:privacycam/presentation/widgets/image_geometry.dart';
import 'package:privacycam/state/pdf_providers.dart';

class _TestPdfSessionController extends PdfSessionController {
  _TestPdfSessionController(this.initial);

  final PdfSession initial;

  @override
  PdfSession? build() => initial;
}

void main() {
  testWidgets('ordinary PDF text is tappable before its outline is visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(945, 2048));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final text = RedactionItem(
      id: 'ordinary-text',
      category: RedactionCategory.otherText,
      bounds: const Rect.fromLTWH(250, 850, 700, 90),
      selected: false,
      style: RedactionStyle.blackout,
      source: RedactionSource.automatic,
      label: 'Tap this text',
    );
    final imageFile = File('assets/images/2_1.webp').absolute;
    final session = PdfSession(
      sourcePath: 'source.pdf',
      fileName: 'source.pdf',
      status: PdfWorkStatus.ready,
      pages: [
        PdfPageSession(
          pageNumber: 1,
          widthPoints: 612,
          heightPoints: 792,
          image: ImageSession(
            sourcePath: imageFile.path,
            width: 1200,
            height: 1800,
            items: [text],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pdfSessionProvider.overrideWith(
            () => _TestPdfSessionController(session),
          ),
        ],
        child: const MaterialApp(home: PdfReviewScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('Tap text directly at any zoom'),
      findsOneWidget,
    );
    final viewerFinder = find.byType(InteractiveViewer);
    final viewerSize = tester.getSize(viewerFinder);
    final geometry = ImageGeometry(viewerSize, const Size(1200, 1800));
    final tapPosition =
        tester.getTopLeft(viewerFinder) +
        geometry.toLocalRect(text.bounds).center;

    await tester.tapAt(tapPosition);
    await tester.pump(const Duration(milliseconds: 400));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PdfReviewScreen)),
    );
    expect(
      container
          .read(pdfSessionProvider)!
          .currentPage!
          .image
          .items
          .single
          .selected,
      isTrue,
    );
  });
}
