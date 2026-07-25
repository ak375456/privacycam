import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/privacy_showcase.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    await ref
        .read(settingsProvider.notifier)
        .update(ref.read(settingsProvider).copyWith(onboardingDone: true));
    if (mounted) context.go('/home');
  }

  void _continue() {
    if (_page == 3) {
      _done();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 5, 10, 3),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Image.asset(
                      'assets/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: mint,
                        child: Icon(
                          Icons.shield_outlined,
                          color: forest,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                const Text(
                  'PrivacyCam',
                  style: TextStyle(
                    color: ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_page + 1} of 4',
                  style: const TextStyle(
                    color: Colors.black45,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                AdaptiveButton(
                  style: AdaptiveButtonStyle.plain,
                  onPressed: _done,
                  child: const Text('Skip'),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (value) => setState(() => _page = value),
              children: [
                const _AppOverviewPage(),
                const _PhotoProtectionPage(),
                _VideoProtectionPage(active: _page == 2),
                const _PdfProtectionPage(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: index == _page ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: index == _page ? forest : Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                SizedBox(
                  width: double.infinity,
                  child: AdaptiveButton(
                    onPressed: _continue,
                    icon: Icon(
                      _page == 3
                          ? Icons.shield_outlined
                          : Icons.arrow_forward_rounded,
                    ),
                    child: Text(_page == 3 ? 'Start protecting' : 'Continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AppOverviewPage extends StatelessWidget {
  const _AppOverviewPage();

  @override
  Widget build(BuildContext context) => const _OnboardingPage(
    eyebrow: 'PRIVATE BY DESIGN',
    title: 'Share freely. Keep private details private.',
    description:
        'PrivacyCam helps you find and hide sensitive details in photos, short videos and PDFs before you share.',
    child: _OverviewVisual(),
  );
}

class _PhotoProtectionPage extends StatelessWidget {
  const _PhotoProtectionPage();

  @override
  Widget build(BuildContext context) => _OnboardingPage(
    eyebrow: 'PHOTO REDACTION',
    title: 'Compare before and after',
    description:
        'Drag the divider. Faces and number plates remain visible in the original, then become safer in the protected copy.',
    child: Column(
      children: [
        const Expanded(
          child: _FittedComparison(
            ratio: 3 / 4,
            originalAsset: 'assets/images/1_1.webp',
            protectedAsset: 'assets/images/1_2.webp',
            fit: BoxFit.cover,
            semanticsLabel: 'Original and protected car photo comparison',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 7,
          runSpacing: 6,
          children: const [
            _CapabilityChip(icon: Icons.face_outlined, label: 'Faces'),
            _CapabilityChip(
              icon: Icons.directions_car_outlined,
              label: 'Plates',
            ),
            _CapabilityChip(icon: Icons.qr_code_rounded, label: 'Codes'),
            _CapabilityChip(
              icon: Icons.text_fields_rounded,
              label: 'Private text',
            ),
          ],
        ),
      ],
    ),
  );
}

class _VideoProtectionPage extends StatefulWidget {
  const _VideoProtectionPage({required this.active});

  final bool active;

  @override
  State<_VideoProtectionPage> createState() => _VideoProtectionPageState();
}

class _VideoProtectionPageState extends State<_VideoProtectionPage> {
  late final VideoPlayerController _video;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _video = VideoPlayerController.asset(
      'assets/onboarding/video_before_after.mp4',
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _video.initialize();
      await _video.setLooping(true);
      await _video.setVolume(0);
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.active) await _video.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant _VideoProtectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready || oldWidget.active == widget.active) return;
    if (widget.active) {
      unawaited(_video.play());
    } else {
      unawaited(_video.pause());
    }
  }

  @override
  void dispose() {
    unawaited(_video.dispose());
    super.dispose();
  }

  void _togglePlayback() {
    if (!_ready) return;
    setState(() {
      if (_video.value.isPlaying) {
        unawaited(_video.pause());
      } else {
        unawaited(_video.play());
      }
    });
  }

  @override
  Widget build(BuildContext context) => _OnboardingPage(
    eyebrow: 'VIDEO REDACTION',
    title: 'Watch protection follow the scene',
    description:
        'The original is shown above and the protected copy below. Faces stay blurred and the number plate stays hidden as the scene moves.',
    child: Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 8 / 9,
              child: Semantics(
                label: 'Original video above and privacy-protected video below',
                button: true,
                child: GestureDetector(
                  onTap: _togglePlayback,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: ColoredBox(
                      color: const Color(0xFF151817),
                      child: LayoutBuilder(
                        builder: (context, constraints) => Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_ready)
                              VideoPlayer(_video)
                            else if (_failed)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'Video preview unavailable',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              )
                            else
                              const Center(
                                child: AdaptiveProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            Positioned(
                              left: 10,
                              top: 10,
                              child: _VideoLabel(
                                icon: Icons.visibility_outlined,
                                label: 'Original',
                                color: Color(0xFF2F3A37),
                              ),
                            ),
                            Positioned(
                              left: 10,
                              top: constraints.maxHeight / 2 + 10,
                              child: const _VideoLabel(
                                icon: Icons.shield_outlined,
                                label: 'Protected',
                                color: forest,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: constraints.maxHeight / 2 - 1,
                              child: const ColoredBox(
                                color: Colors.white,
                                child: SizedBox(height: 2),
                              ),
                            ),
                            if (_ready)
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .62),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(7),
                                    child: Icon(
                                      _video.value.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.volume_off_outlined, size: 17, color: forest),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Muted 8-second demo • tap to pause or replay',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF52615D),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _VideoLabel extends StatelessWidget {
  const _VideoLabel({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PdfProtectionPage extends StatefulWidget {
  const _PdfProtectionPage();

  @override
  State<_PdfProtectionPage> createState() => _PdfProtectionPageState();
}

class _PdfProtectionPageState extends State<_PdfProtectionPage> {
  int _pdfPage = 0;

  @override
  Widget build(BuildContext context) {
    final pageNumber = _pdfPage + 1;
    return _OnboardingPage(
      eyebrow: 'PDF REDACTION',
      title: 'Protect entire PDFs, page by page',
      description:
          'Review sensitive text and codes on every page, then export a flattened privacy-safe copy.',
      child: Column(
        children: [
          SegmentedButton<int>(
            showSelectedIcon: true,
            segments: const [
              ButtonSegment(value: 0, label: Text('Page 1')),
              ButtonSegment(value: 1, label: Text('Page 2')),
            ],
            selected: {_pdfPage},
            onSelectionChanged: (value) =>
                setState(() => _pdfPage = value.first),
          ),
          const SizedBox(height: 9),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _FittedComparison(
                key: ValueKey(pageNumber),
                ratio: 960 / 1358,
                originalAsset:
                    'assets/onboarding/pdf_original_$pageNumber.webp',
                protectedAsset:
                    'assets/onboarding/pdf_protected_$pageNumber.webp',
                fit: BoxFit.contain,
                semanticsLabel:
                    'Original and protected PDF page $pageNumber comparison',
              ),
            ),
          ),
          const SizedBox(height: 9),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swipe_rounded, size: 18, color: forest),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Drag to compare • exported pages are flattened',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF52615D),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            eyebrow,
            style: const TextStyle(
              color: forest,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .75,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontSize: 29, height: 1.05),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(
            color: Color(0xFF52615D),
            fontSize: 15,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(child: child),
      ],
    ),
  );
}

class _OverviewVisual extends StatelessWidget {
  const _OverviewVisual();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFE8F4EE)],
      ),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFFD3E5DC)),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .07),
          blurRadius: 25,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 285;
        return Column(
          children: [
            Row(
              children: [
                Container(
                  width: compact ? 52 : 62,
                  height: compact ? 52 : 62,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(color: Color(0x1A000000), blurRadius: 12),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Image.asset(
                      'assets/app_icon.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: mint,
                        child: Icon(
                          Icons.shield_outlined,
                          color: forest,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Private processing, clear results',
                        style: TextStyle(
                          color: ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Nothing is uploaded to a developer-operated media server.',
                        style: TextStyle(
                          color: Color(0xFF52615D),
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Row(
              children: [
                Expanded(
                  child: _MediaTile(
                    icon: Icons.photo_outlined,
                    label: 'Photos',
                    detail: 'Faces & details',
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _MediaTile(
                    icon: Icons.videocam_outlined,
                    label: 'Videos',
                    detail: 'Track masks',
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: _MediaTile(
                    icon: Icons.picture_as_pdf_outlined,
                    label: 'PDFs',
                    detail: 'Page by page',
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Row(
              children: [
                Expanded(
                  child: _FlowStep(number: '1', label: 'Choose'),
                ),
                _FlowArrow(),
                Expanded(
                  child: _FlowStep(number: '2', label: 'Review'),
                ),
                _FlowArrow(),
                Expanded(
                  child: _FlowStep(number: '3', label: 'Share safer'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.icon,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .88),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD9E6E0)),
    ),
    child: Column(
      children: [
        Icon(icon, color: forest, size: 24),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            color: ink,
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black45, fontSize: 9.5),
        ),
      ],
    ),
  );
}

class _FlowStep extends StatelessWidget {
  const _FlowStep({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 27,
        height: 27,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: forest, shape: BoxShape.circle),
        child: Text(
          number,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        style: const TextStyle(
          color: ink,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: 18),
    child: Icon(
      Icons.arrow_forward_rounded,
      color: Color(0xFF8AA69B),
      size: 17,
    ),
  );
}

class _FittedComparison extends StatelessWidget {
  const _FittedComparison({
    super.key,
    required this.ratio,
    required this.originalAsset,
    required this.protectedAsset,
    required this.fit,
    required this.semanticsLabel,
  });

  final double ratio;
  final String originalAsset;
  final String protectedAsset;
  final BoxFit fit;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var height = constraints.maxHeight;
      var width = height * ratio;
      if (width > constraints.maxWidth) {
        width = constraints.maxWidth;
        height = width / ratio;
      }
      width = math.max(1, width);
      height = math.max(1, height);
      return Center(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF202422),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD2DED8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: BeforeAfterComparison(
            originalAsset: originalAsset,
            protectedAsset: protectedAsset,
            aspectRatio: null,
            fit: fit,
            borderRadius: 19,
            semanticsLabel: semanticsLabel,
          ),
        ),
      );
    },
  );
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: forest, size: 15),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: forest,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
