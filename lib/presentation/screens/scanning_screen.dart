import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/privacy_loader.dart';

enum _ScanFailureAction { chooseAnother, retry }

class ScanningScreen extends ConsumerStatefulWidget {
  const ScanningScreen({super.key, this.request});
  final BatchScanRequest? request;
  @override
  ConsumerState<ScanningScreen> createState() => _ScanningState();
}

class _ScanningState extends ConsumerState<ScanningScreen> {
  ScanStage stage = ScanStage.preparing;
  bool cancelled = false;
  bool imported = false;
  int currentPhoto = 1;
  int totalPhotos = 1;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_scan);
  }

  Future<void> _scan() async {
    try {
      if (widget.request != null && !imported) {
        await ref
            .read(sessionProvider.notifier)
            .beginBatch(widget.request!.paths, append: widget.request!.append);
        imported = true;
        if (cancelled) {
          return;
        }
      }
      await ref
          .read(sessionProvider.notifier)
          .processPending(
            shouldCancel: () => cancelled,
            onItem: (current, total) {
              if (mounted) {
                setState(() {
                  currentPhoto = current;
                  totalPhotos = total;
                  stage = ScanStage.preparing;
                });
              }
            },
            onStage: (value) {
              if (mounted) setState(() => stage = value);
            },
          );
      if (mounted && !cancelled) {
        final batch = ref.read(batchProvider);
        if (batch.needsReviewCount > 0 && !(widget.request?.append ?? false)) {
          context.go('/review');
        } else {
          context.go('/batch');
        }
      }
    } catch (e) {
      if (mounted) {
        final action = await showAdaptiveActionSheet<_ScanFailureAction>(
          context: context,
          title: 'We couldn’t finish the scan',
          message: '$e',
          dismissible: false,
          cancelLabel: 'Choose another image',
          actions: const [
            AdaptiveAction(
              label: 'Try again',
              value: _ScanFailureAction.retry,
              icon: Icons.refresh_rounded,
            ),
            AdaptiveAction(
              label: 'Choose another image',
              value: _ScanFailureAction.chooseAnother,
              icon: Icons.photo_library_outlined,
            ),
          ],
        );
        if (!mounted) return;
        if (action == _ScanFailureAction.retry) {
          _scan();
        } else {
          context.go('/home');
        }
      }
    }
  }

  String get label => switch (stage) {
    ScanStage.preparing => 'Preparing image',
    ScanStage.faces => 'Detecting faces',
    ScanStage.people => 'Detecting people',
    ScanStage.text => 'Reading visible text',
    ScanStage.sensitiveInfo => 'Checking sensitive information',
    ScanStage.numberPlates => 'Detecting number plates',
    ScanStage.codes => 'Detecting QR codes and barcodes',
    ScanStage.complete => 'Finishing review',
  };
  double get progress => switch (stage) {
    ScanStage.preparing => 0,
    ScanStage.faces => .14,
    ScanStage.people => .28,
    ScanStage.text => .42,
    ScanStage.sensitiveInfo => .55,
    ScanStage.numberPlates => .7,
    ScanStage.codes => .85,
    ScanStage.complete => 1,
  };
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (s != null)
                    Image.file(File(s.sourcePath), fit: BoxFit.contain)
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
                  if (s != null)
                    Container(color: Colors.black.withValues(alpha: .28)),
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.fromLTRB(30, 28, 30, 30),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .96),
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
                        label: label,
                        progress: progress,
                        detail: totalPhotos > 1
                            ? 'Photo $currentPhoto of $totalPhotos · Everything stays on this device'
                            : 'Everything stays on this device',
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
                onPressed: () {
                  cancelled = true;
                  final batch = ref.read(batchProvider);
                  context.go(batch.isEmpty ? '/home' : '/batch');
                },
                child: Text(totalPhotos > 1 ? 'Stop scanning' : 'Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
