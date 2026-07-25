import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models.dart';
import '../../domain/pdf_models.dart';
import '../../state/pdf_providers.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/privacy_loader.dart';

class PdfScanningScreen extends ConsumerStatefulWidget {
  const PdfScanningScreen({super.key, required this.path});

  final String path;

  @override
  ConsumerState<PdfScanningScreen> createState() => _PdfScanningScreenState();
}

class _PdfScanningScreenState extends ConsumerState<PdfScanningScreen> {
  PdfScanProgress progress = const PdfScanProgress(
    page: 1,
    totalPages: 1,
    stage: ScanStage.preparing,
  );
  bool cancelled = false;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_start);
  }

  Future<void> _start() async {
    try {
      final inspection = await ref
          .read(pdfServiceProvider)
          .inspect(widget.path);
      if (!mounted) return;
      if (inspection.pageCount > pdfFreePageLimit &&
          !ref.read(batchAccessProvider)) {
        final unlocked = await context.push<bool>('/pro');
        if (!mounted) return;
        if (unlocked != true) {
          context.go('/home');
          return;
        }
      }
      await ref
          .read(pdfSessionProvider.notifier)
          .importAndScan(
            widget.path,
            shouldCancel: () => cancelled,
            onProgress: (value) {
              if (mounted) setState(() => progress = value);
            },
          );
      if (mounted && !cancelled) context.go('/pdf/review');
    } catch (error) {
      if (!mounted) return;
      await showAdaptiveActionSheet<void>(
        context: context,
        title: 'This PDF could not be prepared',
        message: '$error',
        actions: const [],
        cancelLabel: 'Choose another file',
      );
      if (mounted) context.go('/home');
    }
  }

  String get _label => switch (progress.stage) {
    ScanStage.preparing => 'Preparing PDF page',
    ScanStage.faces => 'Detecting faces',
    ScanStage.people => 'Detecting people',
    ScanStage.text => 'Reading visible text',
    ScanStage.sensitiveInfo => 'Checking sensitive information',
    ScanStage.numberPlates => 'Detecting number plates',
    ScanStage.codes => 'Detecting QR codes and barcodes',
    ScanStage.complete => 'Finishing page review',
  };

  double get _stageProgress => switch (progress.stage) {
    ScanStage.preparing => 0,
    ScanStage.faces => .12,
    ScanStage.people => .26,
    ScanStage.text => .42,
    ScanStage.sensitiveInfo => .56,
    ScanStage.numberPlates => .72,
    ScanStage.codes => .88,
    ScanStage.complete => 1,
  };

  double get _overallProgress =>
      ((progress.page - 1) + _stageProgress) / progress.totalPages;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(pdfSessionProvider);
    final page = session?.currentPage;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (page != null)
                    Image.file(File(page.image.sourcePath), fit: BoxFit.contain)
                  else
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFE7F5EF), Color(0xFFF8F7F1)],
                        ),
                      ),
                    ),
                  Container(color: Colors.black.withValues(alpha: .28)),
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.fromLTRB(30, 28, 30, 30),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .97),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 30,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: PrivacyLoader(
                        label: _label,
                        progress: _overallProgress.clamp(0, 1),
                        detail:
                            'Page ${progress.page} of ${progress.totalPages} · Everything stays on this device',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: AdaptiveButton(
                style: AdaptiveButtonStyle.secondary,
                onPressed: () async {
                  cancelled = true;
                  await ref.read(pdfSessionProvider.notifier).clear();
                  if (context.mounted) context.go('/home');
                },
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
