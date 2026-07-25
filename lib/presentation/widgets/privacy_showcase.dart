import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'adaptive_ui.dart';

class PrivacyShowcase extends StatefulWidget {
  const PrivacyShowcase({super.key});

  @override
  State<PrivacyShowcase> createState() => _PrivacyShowcaseState();
}

class _PrivacyShowcaseState extends State<PrivacyShowcase> {
  late final Future<List<_ShowcasePair>> _pairs = _loadPairs();
  int _pairIndex = 0;

  static Future<List<_ShowcasePair>> _loadPairs() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final pattern = RegExp(
      r'^assets/images/(\d+)_(1|2)\.(?:webp|png|jpe?g)$',
      caseSensitive: false,
    );
    final grouped = <int, Map<int, String>>{};

    for (final asset in manifest.listAssets()) {
      final match = pattern.firstMatch(asset);
      if (match == null) continue;
      final pairNumber = int.parse(match.group(1)!);
      final version = int.parse(match.group(2)!);
      grouped.putIfAbsent(pairNumber, () => {})[version] = asset;
    }

    final pairNumbers = grouped.keys.toList()..sort();
    return [
      for (final number in pairNumbers)
        if (grouped[number]![1] != null && grouped[number]![2] != null)
          _ShowcasePair(
            number: number,
            original: grouped[number]![1]!,
            protected: grouped[number]![2]!,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_ShowcasePair>>(
    future: _pairs,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const SizedBox.shrink();
      final pairs = snapshot.data;
      if (pairs == null) return const _ShowcasePlaceholder();
      if (pairs.isEmpty) return const SizedBox.shrink();

      final safeIndex = math.min(_pairIndex, pairs.length - 1);
      final pair = pairs[safeIndex];
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFD9E5DF)),
          boxShadow: [
            BoxShadow(
              color: ink.withValues(alpha: .07),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(5, 1, 5, 12),
              child: Row(
                children: [
                  _ShowcaseIcon(),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'See the protection',
                          style: TextStyle(
                            color: ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Drag across the photo to compare',
                          style: TextStyle(
                            color: Color(0xFF5D6B67),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _OnDeviceBadge(),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: BeforeAfterComparison(
                key: ValueKey(pair.number),
                originalAsset: pair.original,
                protectedAsset: pair.protected,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 10, 5, 0),
              child: Row(
                children: [
                  const Icon(Icons.swipe_rounded, color: forest, size: 20),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Swipe the handle — your photo stays on your device.',
                      style: TextStyle(
                        color: Color(0xFF52615D),
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (pairs.length > 1) ...[
                    AdaptiveIconButton(
                      tooltip: 'Previous example',
                      onPressed: safeIndex == 0
                          ? null
                          : () => setState(() => _pairIndex = safeIndex - 1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Text(
                      '${safeIndex + 1}/${pairs.length}',
                      style: const TextStyle(
                        color: ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    AdaptiveIconButton(
                      tooltip: 'Next example',
                      onPressed: safeIndex == pairs.length - 1
                          ? null
                          : () => setState(() => _pairIndex = safeIndex + 1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class BeforeAfterComparison extends StatefulWidget {
  const BeforeAfterComparison({
    super.key,
    required this.originalAsset,
    required this.protectedAsset,
    this.aspectRatio = 3 / 4,
    this.fit = BoxFit.cover,
    this.borderRadius = 19,
    this.semanticsLabel = 'Original and protected comparison',
  });

  final String originalAsset;
  final String protectedAsset;
  final double? aspectRatio;
  final BoxFit fit;
  final double borderRadius;
  final String semanticsLabel;

  @override
  State<BeforeAfterComparison> createState() => _BeforeAfterComparisonState();
}

class _BeforeAfterComparisonState extends State<BeforeAfterComparison> {
  double _reveal = .5;

  void _updateReveal(double localX, double width) {
    setState(() => _reveal = (localX / width).clamp(.04, .96));
  }

  @override
  Widget build(BuildContext context) {
    final comparison = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cacheWidth = (width * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(600, 1400);
        return Semantics(
          slider: true,
          label: widget.semanticsLabel,
          value: '${(_reveal * 100).round()} percent original visible',
          increasedValue: 'Show more of the original',
          decreasedValue: 'Show more of the protected copy',
          onIncrease: () =>
              setState(() => _reveal = (_reveal + .1).clamp(.04, .96)),
          onDecrease: () =>
              setState(() => _reveal = (_reveal - .1).clamp(.04, .96)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _updateReveal(details.localPosition.dx, width),
              onHorizontalDragStart: (details) =>
                  _updateReveal(details.localPosition.dx, width),
              onHorizontalDragUpdate: (details) =>
                  _updateReveal(details.localPosition.dx, width),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    widget.protectedAsset,
                    fit: widget.fit,
                    cacheWidth: cacheWidth,
                    gaplessPlayback: true,
                  ),
                  ClipRect(
                    clipper: _RevealClipper(_reveal),
                    child: Image.asset(
                      widget.originalAsset,
                      fit: widget.fit,
                      cacheWidth: cacheWidth,
                      gaplessPlayback: true,
                    ),
                  ),
                  const Positioned(
                    left: 10,
                    top: 10,
                    child: _ImageLabel(label: 'ORIGINAL'),
                  ),
                  const Positioned(
                    right: 10,
                    top: 10,
                    child: _ImageLabel(label: 'PROTECTED', protected: true),
                  ),
                  Positioned(
                    left: width * _reveal - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: Colors.white.withValues(alpha: .95),
                    ),
                  ),
                  Positioned(
                    left: width * _reveal - 20,
                    top: constraints.maxHeight / 2 - 20,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: forest.withValues(alpha: .28),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.compare_arrows_rounded,
                        color: forest,
                        size: 23,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    final ratio = widget.aspectRatio;
    return ratio == null
        ? comparison
        : AspectRatio(aspectRatio: ratio, child: comparison);
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  const _RevealClipper(this.reveal);

  final double reveal;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * reveal, size.height);

  @override
  bool shouldReclip(_RevealClipper oldClipper) => oldClipper.reveal != reveal;
}

class _ShowcasePair {
  const _ShowcasePair({
    required this.number,
    required this.original,
    required this.protected,
  });

  final int number;
  final String original;
  final String protected;
}

class _ImageLabel extends StatelessWidget {
  const _ImageLabel({required this.label, this.protected = false});

  final String label;
  final bool protected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: protected
          ? forest.withValues(alpha: .92)
          : Colors.black.withValues(alpha: .68),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .22)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: .65,
      ),
    ),
  );
}

class _ShowcaseIcon extends StatelessWidget {
  const _ShowcaseIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.auto_fix_high_rounded, color: forest, size: 21),
  );
}

class _OnDeviceBadge extends StatelessWidget {
  const _OnDeviceBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F6F3),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.phone_iphone_rounded, color: forest, size: 13),
        SizedBox(width: 3),
        Text(
          'ON-DEVICE',
          style: TextStyle(
            color: forest,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: .45,
          ),
        ),
      ],
    ),
  );
}

class _ShowcasePlaceholder extends StatelessWidget {
  const _ShowcasePlaceholder();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 3 / 4,
    child: Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3F8F5), Color(0xFFE3F1EB)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      alignment: Alignment.center,
      child: const AdaptiveProgressIndicator(dimension: 24),
    ),
  );
}
