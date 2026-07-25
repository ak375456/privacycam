import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../domain/pdf_models.dart';
import '../../state/pdf_providers.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/privacy_loader.dart';

class PdfExportScreen extends ConsumerStatefulWidget {
  const PdfExportScreen({super.key});

  @override
  ConsumerState<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends ConsumerState<PdfExportScreen> {
  bool busy = true;
  int exportPage = 1;
  int exportTotal = 1;
  late double blurStrength;
  late double pixelSize;
  RedactionStyle effect = RedactionStyle.blackout;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    blurStrength = settings.blurStrength;
    pixelSize = settings.pixelSize;
    final document = ref.read(pdfSessionProvider);
    final selected = document?.pages
        .expand((page) => page.image.items)
        .where((item) => item.selected)
        .toList();
    if (selected != null && selected.isNotEmpty) {
      effect = selected.any((item) => item.style == RedactionStyle.blur)
          ? RedactionStyle.blur
          : selected.any((item) => item.style == RedactionStyle.pixelate)
          ? RedactionStyle.pixelate
          : RedactionStyle.blackout;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _buildPreview());
  }

  Future<void> _buildPreview() async {
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final settings = ref.read(settingsProvider);
      await ref
          .read(settingsProvider.notifier)
          .update(
            settings.copyWith(blurStrength: blurStrength, pixelSize: pixelSize),
          );
      await ref
          .read(pdfSessionProvider.notifier)
          .export(
            onPage: (page, total) {
              if (mounted) {
                setState(() {
                  exportPage = page;
                  exportTotal = total;
                });
              }
            },
          );
    } catch (error) {
      if (mounted) showAdaptiveMessage(context, '$error', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(pdfSessionProvider);
    final page = document?.currentPage;
    if (document == null || page == null) {
      return const Scaffold(body: Center(child: Text('No PDF is open.')));
    }
    final previewPath = page.image.exportPath ?? page.image.sourcePath;
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Privacy-safe PDF'),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Colors.black87,
                    width: double.infinity,
                    child: Image.file(
                      File(previewPath),
                      key: ValueKey(previewPath),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
                _pageStrip(document),
                Flexible(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                    child: Column(
                      children: [
                        _verificationCard(document),
                        const SizedBox(height: 12),
                        _strengthCard(),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: AdaptiveButton(
                                onPressed: busy ? null : _buildPreview,
                                icon: const Icon(Icons.refresh_rounded),
                                child: const Text('Update preview'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AdaptiveButton(
                                style: AdaptiveButtonStyle.secondary,
                                onPressed: busy || document.exportPath == null
                                    ? null
                                    : _share,
                                icon: Icon(
                                  adaptiveIcon(
                                    context,
                                    material: Icons.ios_share_outlined,
                                    cupertino: CupertinoIcons.share,
                                  ),
                                ),
                                child: const Text('Save or share'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.plain,
                              onPressed: busy ? null : () => context.pop(),
                              child: const Text('Edit again'),
                            ),
                            AdaptiveButton(
                              style: AdaptiveButtonStyle.plain,
                              onPressed: busy
                                  ? null
                                  : () async {
                                      await ref
                                          .read(pdfSessionProvider.notifier)
                                          .clear();
                                      if (context.mounted) context.go('/home');
                                    },
                              child: const Text('Start over'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .52),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 30,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: PrivacyLoader(
                        label: 'Flattening safe PDF',
                        progress: exportTotal == 0
                            ? null
                            : exportPage / exportTotal,
                        detail:
                            'Page $exportPage of $exportTotal · Removing original text layers and metadata',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pageStrip(PdfSession document) => SizedBox(
    height: 45,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      itemCount: document.pageCount,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, index) => ChoiceChip(
        label: Text('${index + 1}'),
        selected: index == document.currentPageIndex,
        onSelected: (_) =>
            ref.read(pdfSessionProvider.notifier).setCurrentPage(index),
      ),
    ),
  );

  Widget _verificationCard(PdfSession document) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: document.flatteningVerified ? mint : const Color(0xFFFFF7E0),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: document.flatteningVerified
            ? const Color(0xFFB2D8CA)
            : const Color(0xFFE8C96B),
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Icon(
              document.flatteningVerified
                  ? Icons.verified_user_outlined
                  : Icons.hourglass_top_rounded,
              color: document.flatteningVerified ? forest : Colors.orange,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                document.flatteningVerified
                    ? '${document.selectedCount} items hidden across ${document.pageCount} pages'
                    : 'Safe PDF preview is not ready yet',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        if (document.flatteningVerified) ...[
          const SizedBox(height: 7),
          const Row(
            children: [
              Icon(Icons.layers_clear_outlined, color: forest, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Flattening verified: original text layers and document metadata are not carried into this copy.',
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _strengthCard() {
    final showSlider = effect != RedactionStyle.blackout;
    final blur = effect == RedactionStyle.blur;
    final value = blur ? blurStrength : pixelSize;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          AdaptiveSegmentedControl<RedactionStyle>(
            value: effect,
            children: const {
              RedactionStyle.blur: Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Text('Blur'),
              ),
              RedactionStyle.pixelate: Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Text('Pixelate'),
              ),
              RedactionStyle.blackout: Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Text('Blackout'),
              ),
            },
            onChanged: busy
                ? (_) {}
                : (next) {
                    setState(() => effect = next);
                    ref
                        .read(pdfSessionProvider.notifier)
                        .setDocumentStyle(next);
                  },
          ),
          if (showSlider) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(blur ? Icons.blur_on_outlined : Icons.grid_4x4_outlined),
                Expanded(
                  child: AdaptiveSlider(
                    value: value,
                    min: blur ? 2 : 4,
                    max: blur ? 64 : 80,
                    divisions: blur ? 31 : 38,
                    onChanged: busy
                        ? null
                        : (next) => setState(() {
                            if (blur) {
                              blurStrength = next;
                            } else {
                              pixelSize = next;
                            }
                          }),
                  ),
                ),
                Text(blur ? '${value.round()}' : '${value.round()} px'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _share() async {
    final path = ref.read(pdfSessionProvider)?.exportPath;
    if (path == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'application/pdf')],
          text: 'Privacy-safe PDF created with PrivacyCam',
        ),
      );
    } catch (error) {
      if (mounted) showAdaptiveMessage(context, '$error', error: true);
    }
  }
}
