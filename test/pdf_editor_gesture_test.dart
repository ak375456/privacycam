import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacycam/domain/models.dart';
import 'package:privacycam/domain/pdf_models.dart';
import 'package:privacycam/presentation/screens/pdf_editor_screen.dart';
import 'package:privacycam/state/pdf_providers.dart';

class _TestPdfSessionController extends PdfSessionController {
  _TestPdfSessionController(this.initial);

  final PdfSession initial;

  @override
  PdfSession? build() => initial;
}

void main() {
  testWidgets('PDF editor uses direct pinch zoom without a Zoom tool', (
    tester,
  ) async {
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
          scanned: true,
          image: ImageSession(
            sourcePath: imageFile.path,
            width: 612,
            height: 792,
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
        child: const MaterialApp(home: PdfEditorScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Zoom'), findsNothing);
    expect(find.text('Flowers'), findsOneWidget);
    expect(find.byIcon(Icons.pinch_rounded), findsOneWidget);
    var viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.scaleEnabled, isTrue);
    expect(viewer.panEnabled, isFalse);

    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tap(find.text('Rectangle'));
    await tester.pump();
    await tester.dragFrom(center - const Offset(30, 30), const Offset(70, 70));
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PdfEditorScreen)),
    );
    expect(
      container.read(pdfSessionProvider)!.currentPage!.image.items,
      hasLength(1),
    );

    final first = await tester.startGesture(
      center - const Offset(24, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(24, 0),
      pointer: 2,
    );
    await first.moveTo(center - const Offset(70, 0));
    await second.moveTo(center + const Offset(70, 0));
    await tester.pump();

    viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(viewer.panEnabled, isTrue);

    await first.up();
    await second.up();
    await tester.pump();
  });
}
