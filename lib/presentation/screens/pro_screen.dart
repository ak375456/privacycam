import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_links.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';

class ProScreen extends ConsumerStatefulWidget {
  const ProScreen({super.key, this.request});

  final BatchScanRequest? request;

  @override
  ConsumerState<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends ConsumerState<ProScreen> {
  bool _handledUnlock = false;

  @override
  Widget build(BuildContext context) {
    final purchase = ref.watch(proPurchaseProvider);
    ref.listen<ProPurchaseState>(proPurchaseProvider, (previous, next) {
      if (!(previous?.isPro ?? false) && next.isPro) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _finishAfterUnlock();
        });
      }
    });

    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('PrivacyCam Pro'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
          children: [
            _ProHero(unlocked: purchase.isPro),
            const SizedBox(height: 24),
            if (purchase.isPro)
              _UnlockedContent(onDone: _finishAfterUnlock)
            else ...[
              Text(
                'Privacy protection stays free. Pro saves time.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'All photo and video privacy tools stay free. PDFs up to 2 pages are free too.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF52615D),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              const _Benefit(
                icon: Icons.picture_as_pdf_outlined,
                title: 'Protect longer PDFs',
                detail: 'Review and flatten PDFs beyond the free 2-page limit.',
              ),
              const _Benefit(
                icon: Icons.collections_outlined,
                title: 'Process up to 10 photos',
                detail: 'Choose once and review each photo in order.',
              ),
              const _Benefit(
                icon: Icons.playlist_add_check_circle_outlined,
                title: 'Resume unfinished batches',
                detail: 'Your progress waits safely on this device.',
              ),
              const _Benefit(
                icon: Icons.ios_share_outlined,
                title: 'Save or share together',
                detail: 'Export selected safe copies as one batch.',
              ),
              const SizedBox(height: 18),
              if (purchase.error != null)
                _FeedbackCard(
                  message: purchase.error!,
                  error: true,
                  onDismiss: () =>
                      ref.read(proPurchaseProvider.notifier).clearFeedback(),
                )
              else if (purchase.notice != null)
                _FeedbackCard(
                  message: purchase.notice!,
                  onDismiss: () =>
                      ref.read(proPurchaseProvider.notifier).clearFeedback(),
                ),
              const SizedBox(height: 12),
              AdaptiveButton(
                onPressed: purchase.isBusy
                    ? null
                    : purchase.product == null
                    ? () => ref.read(proPurchaseProvider.notifier).loadProduct()
                    : () => ref.read(proPurchaseProvider.notifier).purchase(),
                icon: purchase.isBusy
                    ? const AdaptiveProgressIndicator(
                        color: Colors.white,
                        dimension: 20,
                      )
                    : const Icon(Icons.workspace_premium_outlined),
                child: Text(_purchaseButtonLabel(purchase)),
              ),
              const SizedBox(height: 10),
              AdaptiveButton(
                style: AdaptiveButtonStyle.secondary,
                onPressed: purchase.activity == ProPurchaseActivity.purchasing
                    ? null
                    : _continueFree,
                child: Text(_continueLabel),
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: 4),
                AdaptiveButton(
                  style: AdaptiveButtonStyle.plain,
                  onPressed: purchase.isBusy
                      ? null
                      : () => ref.read(proPurchaseProvider.notifier).restore(),
                  icon: purchase.activity == ProPurchaseActivity.restoring
                      ? const AdaptiveProgressIndicator(dimension: 18)
                      : Icon(
                          adaptiveIcon(
                            context,
                            material: Icons.restore_rounded,
                            cupertino: CupertinoIcons.refresh,
                          ),
                        ),
                  child: const Text('Restore Purchases'),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'One-time purchase. No subscription or recurring charge. Payment is handled securely by ${Platform.isAndroid ? 'Google Play' : 'Apple'}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 2,
                children: [
                  AdaptiveButton(
                    style: AdaptiveButtonStyle.plain,
                    onPressed: () => _openLink(AppLinks.privacyPolicy),
                    child: const Text('Privacy Policy'),
                  ),
                  AdaptiveButton(
                    style: AdaptiveButtonStyle.plain,
                    onPressed: () => _openLink(AppLinks.termsOfService),
                    child: const Text('Terms of Service'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _purchaseButtonLabel(ProPurchaseState state) =>
      switch (state.activity) {
        ProPurchaseActivity.loadingStore =>
          'Checking ${Platform.isAndroid ? 'Google Play' : 'App Store'}…',
        ProPurchaseActivity.purchasing => 'Confirm purchase…',
        ProPurchaseActivity.pending => 'Purchase pending',
        ProPurchaseActivity.restoring => 'Restoring…',
        ProPurchaseActivity.idle =>
          state.product == null
              ? 'Check ${Platform.isAndroid ? 'Google Play' : 'App Store'}'
              : 'Unlock forever — ${state.product!.price}',
      };

  String get _continueLabel {
    if (widget.request == null) return 'Not now';
    if (widget.request!.append && !ref.read(batchProvider).isEmpty) {
      return 'Keep current batch';
    }
    return 'Continue with one photo';
  }

  void _finishAfterUnlock() {
    if (_handledUnlock) return;
    _handledUnlock = true;
    final request = widget.request;
    if (request != null) {
      context.go('/scan', extra: request);
      return;
    }
    if (Navigator.canPop(context)) {
      context.pop(true);
    } else {
      context.go('/home');
    }
  }

  void _continueFree() {
    final request = widget.request;
    if (request == null) {
      if (Navigator.canPop(context)) {
        context.pop(false);
      } else {
        context.go('/home');
      }
      return;
    }
    final batch = ref.read(batchProvider);
    if (request.append && !batch.isEmpty) {
      context.go('/batch');
      return;
    }
    if (request.paths.isEmpty) {
      context.go('/home');
      return;
    }
    context.go('/scan', extra: BatchScanRequest(paths: [request.paths.first]));
  }

  Future<void> _openLink(Uri uri) async {
    try {
      final opened = await AppLinks.open(uri);
      if (!opened && mounted) {
        showAdaptiveMessage(context, 'Could not open this link.', error: true);
      }
    } catch (_) {
      if (mounted) {
        showAdaptiveMessage(context, 'Could not open this link.', error: true);
      }
    }
  }
}

class _ProHero extends StatelessWidget {
  const _ProHero({required this.unlocked});

  final bool unlocked;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 118,
      height: 118,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD9F2E8), Color(0xFFAFE0CF)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: forest.withValues(alpha: .18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Icon(
        unlocked ? Icons.verified_rounded : Icons.auto_awesome_rounded,
        size: 54,
        color: forest,
      ),
    ),
  );
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E6E2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: mint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: forest),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(color: Color(0xFF52615D), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.message,
    required this.onDismiss,
    this.error = false,
  });

  final String message;
  final VoidCallback onDismiss;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFECEA) : mint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(
          error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
          color: error ? const Color(0xFFA5362A) : forest,
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(message, style: const TextStyle(height: 1.3))),
        AdaptiveIconButton(
          tooltip: 'Dismiss message',
          onPressed: onDismiss,
          icon: const Icon(Icons.close_rounded, size: 19),
        ),
      ],
    ),
  );
}

class _UnlockedContent extends StatelessWidget {
  const _UnlockedContent({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        'Pro is unlocked',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'You can process up to 10 photos at a time and protect PDFs beyond 2 pages.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF52615D), height: 1.4),
      ),
      const SizedBox(height: 26),
      SizedBox(
        width: double.infinity,
        child: AdaptiveButton(
          onPressed: onDone,
          icon: const Icon(Icons.check_circle_outline_rounded),
          child: const Text('Continue'),
        ),
      ),
    ],
  );
}
