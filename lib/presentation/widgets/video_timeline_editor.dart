import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../domain/video_models.dart';

class VideoTimelineEditor extends StatefulWidget {
  const VideoTimelineEditor({
    super.key,
    required this.session,
    required this.timestampMs,
    required this.thumbnails,
    required this.canUndo,
    required this.canRedo,
    required this.onSeek,
    required this.onSplit,
    required this.onDeleteSegment,
    required this.onUndo,
    required this.onRedo,
    required this.onToggleMute,
    required this.onTrimChanged,
  });

  final VideoSession session;
  final int timestampMs;
  final List<VideoFrame> thumbnails;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<int> onSeek;
  final ValueChanged<int> onSplit;
  final ValueChanged<VideoTimeRange> onDeleteSegment;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onToggleMute;
  final void Function(int startMs, int endMs) onTrimChanged;

  @override
  State<VideoTimelineEditor> createState() => _VideoTimelineEditorState();
}

class _VideoTimelineEditorState extends State<VideoTimelineEditor> {
  final _scrollController = ScrollController();
  Timer? _scrubTimer;
  double _pixelsPerSecond = 82;
  double _scaleStartPixels = 82;
  double _scaleStartClipWidth = 1;
  double _scaleStartScroll = 0;
  double _scaleStartFocal = 0;
  double _viewportWidth = 1;
  double _clipWidth = 1;
  bool _programmaticScroll = false;
  bool _showTrim = false;
  VideoTimeRange? _selectedSegment;
  late double _trimStartMs;
  late double _trimEndMs;

  VideoEditPlan get _plan => widget.session.resolvedEditPlan;
  int get _outputDuration => _plan.outputDurationMs(widget.session.durationMs);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollChanged);
    _syncTrim();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncToPlayhead());
  }

  @override
  void didUpdateWidget(covariant VideoTimelineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.resolvedEditPlan.trimStartMs != _plan.trimStartMs ||
        oldWidget.session.resolvedEditPlan.trimEndMs != _plan.trimEndMs) {
      _syncTrim();
    }
    final oldPlan = oldWidget.session.resolvedEditPlan;
    final structureChanged =
        oldPlan.trimStartMs != _plan.trimStartMs ||
        oldPlan.trimEndMs != _plan.trimEndMs ||
        oldPlan.splitPointsMs.length != _plan.splitPointsMs.length ||
        oldPlan.removedRanges.length != _plan.removedRanges.length;
    if (structureChanged &&
        oldPlan.splitPointsMs.length != _plan.splitPointsMs.length) {
      _selectedSegment = _segmentAt(widget.timestampMs, preferRight: true);
    } else if (_selectedSegment != null &&
        !_plan
            .keptSegments(widget.session.durationMs)
            .any((segment) => _sameRange(segment, _selectedSegment!))) {
      _selectedSegment = null;
    }
    if ((structureChanged ||
            (oldWidget.timestampMs - widget.timestampMs).abs() > 80) &&
        !_programmaticScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncToPlayhead());
    }
  }

  void _syncTrim() {
    _trimStartMs = _plan.trimStartMs.toDouble();
    _trimEndMs = _plan.trimEndMs.toDouble();
  }

  @override
  void dispose() {
    _scrubTimer?.cancel();
    _scrollController
      ..removeListener(_scrollChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9E5E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.content_cut_rounded, color: forest, size: 20),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Clip editor',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${_format(_outputDuration)} · ${(_pixelsPerSecond / 82).toStringAsFixed(1)}×',
                style: const TextStyle(
                  color: Color(0xFF52615D),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          const Text(
            'Move the filmstrip under the line. Pinch to make the timeline longer or shorter.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF52615D)),
          ),
          const SizedBox(height: 9),
          LayoutBuilder(builder: _timeline),
          const SizedBox(height: 8),
          _toolBar(),
          if (_selectedSegment != null) ...[
            const SizedBox(height: 7),
            Text(
              'Selected ${_format(_segmentOutputStart(_selectedSegment!))}–${_format(_segmentOutputStart(_selectedSegment!) + _selectedSegment!.durationMs)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: forest,
              ),
            ),
          ],
          if (_showTrim) ...[const SizedBox(height: 8), _trimControl()],
        ],
      ),
    );
  }

  Widget _timeline(BuildContext context, BoxConstraints constraints) {
    _viewportWidth = constraints.maxWidth;
    _clipWidth = max(72.0, _outputDuration / 1000 * _pixelsPerSecond);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) {
        _scaleStartPixels = _pixelsPerSecond;
        _scaleStartClipWidth = _clipWidth;
        _scaleStartScroll = _scrollController.hasClients
            ? _scrollController.offset
            : 0;
        _scaleStartFocal = details.localFocalPoint.dx;
        _programmaticScroll = true;
      },
      onScaleUpdate: (details) {
        if (!_scrollController.hasClients) return;
        if (details.pointerCount > 1) {
          final next = (_scaleStartPixels * details.scale).clamp(46.0, 340.0);
          final nextClipWidth = max(72.0, _outputDuration / 1000 * next);
          final factor = nextClipWidth / max(1, _scaleStartClipWidth);
          setState(() => _pixelsPerSecond = next);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollController.hasClients) return;
            final anchored =
                (_scaleStartScroll + _scaleStartFocal) * factor -
                details.localFocalPoint.dx;
            _scrollController.jumpTo(
              anchored.clamp(0, _scrollController.position.maxScrollExtent),
            );
            _emitScrub();
          });
        } else {
          final target =
              _scaleStartScroll -
              (details.localFocalPoint.dx - _scaleStartFocal);
          _scrollController.jumpTo(
            target.clamp(0, _scrollController.position.maxScrollExtent),
          );
          _emitScrub();
        }
      },
      onScaleEnd: (_) {
        _programmaticScroll = false;
        _emitScrub(immediate: true);
      },
      onTapUp: (details) {
        final timestamp = _timestampForLocalX(details.localPosition.dx);
        setState(() => _selectedSegment = _segmentAt(timestamp));
      },
      child: SizedBox(
        height: 96,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: _clipWidth + _viewportWidth,
                    child: Row(
                      children: [
                        SizedBox(width: _viewportWidth / 2),
                        SizedBox(width: _clipWidth, child: _clipStrip()),
                        SizedBox(width: _viewportWidth / 2),
                      ],
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 3,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: forest,
                          spreadRadius: 1,
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: forest,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 5,
                left: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    child: Text(
                      _format(
                        _plan.outputOffsetForSourceTimestamp(
                          widget.timestampMs,
                          widget.session.durationMs,
                        ),
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clipStrip() {
    final ranges = _plan.keptRanges(widget.session.durationMs);
    final segments = _plan.keptSegments(widget.session.durationMs);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF202624)),
        if (widget.thumbnails.isEmpty)
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          )
        else
          for (final range in ranges) _keptRangeStrip(range),
        for (final segment in segments) _segmentOverlay(segment),
        for (var index = 1; index < segments.length; index++)
          _joinMarker(segments[index]),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _TimelineTicksPainter(
                durationMs: _outputDuration,
                pixelsPerSecond: _pixelsPerSecond,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _keptRangeStrip(VideoTimeRange range) {
    final outputStart = _plan.outputOffsetForSourceTimestamp(
      range.startMs,
      widget.session.durationMs,
    );
    final frames = widget.thumbnails
        .where(
          (frame) =>
              frame.timestampMs >= range.startMs &&
              frame.timestampMs < range.endMs,
        )
        .toList();
    if (frames.isEmpty && widget.thumbnails.isNotEmpty) {
      final middle = range.startMs + range.durationMs ~/ 2;
      frames.add(
        widget.thumbnails.reduce(
          (a, b) =>
              (a.timestampMs - middle).abs() <= (b.timestampMs - middle).abs()
              ? a
              : b,
        ),
      );
    }
    return Positioned(
      left: outputStart / max(1, _outputDuration) * _clipWidth,
      width: range.durationMs / max(1, _outputDuration) * _clipWidth,
      top: 0,
      bottom: 0,
      child: Row(
        children: [
          for (final frame in frames)
            Expanded(
              child: Image.file(
                File(frame.path),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              ),
            ),
        ],
      ),
    );
  }

  Widget _segmentOverlay(VideoTimeRange segment) {
    final selected =
        _selectedSegment != null && _sameRange(segment, _selectedSegment!);
    final outputStart = _plan.outputOffsetForSourceTimestamp(
      segment.startMs,
      widget.session.durationMs,
    );
    return Positioned(
      left: outputStart / max(1, _outputDuration) * _clipWidth,
      width: segment.durationMs / max(1, _outputDuration) * _clipWidth,
      top: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? mint.withValues(alpha: .16) : Colors.transparent,
          border: Border.all(
            color: selected
                ? const Color(0xFFFFC247)
                : Colors.white.withValues(alpha: .72),
            width: selected ? 3 : 1,
          ),
        ),
        child: null,
      ),
    );
  }

  Widget _joinMarker(VideoTimeRange rightSegment) {
    final outputStart = _plan.outputOffsetForSourceTimestamp(
      rightSegment.startMs,
      widget.session.durationMs,
    );
    return Positioned(
      left: outputStart / max(1, _outputDuration) * _clipWidth - 9,
      bottom: 5,
      width: 18,
      height: 18,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: forest.withValues(alpha: .92),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.2),
          ),
          child: const Icon(Icons.link_rounded, color: Colors.white, size: 12),
        ),
      ),
    );
  }

  Widget _toolBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFFDDE5E1)),
    ),
    child: Row(
      children: [
        Expanded(
          child: _tool(
            icon: Icons.undo_rounded,
            label: 'Undo',
            onTap: widget.canUndo ? widget.onUndo : null,
          ),
        ),
        Expanded(
          child: _tool(
            icon: Icons.redo_rounded,
            label: 'Redo',
            onTap: widget.canRedo ? widget.onRedo : null,
          ),
        ),
        Expanded(
          child: _tool(
            icon: Icons.content_cut_rounded,
            label: 'Split',
            emphasized: true,
            onTap: _canSplit ? _splitAtPlayhead : null,
          ),
        ),
        Expanded(
          child: _tool(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            destructive: true,
            onTap: _canDelete ? _deleteSelected : null,
          ),
        ),
        Expanded(
          child: _tool(
            icon: _plan.audioMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_outlined,
            label: _plan.audioMuted ? 'Muted' : 'Mute',
            onTap: widget.session.hasAudio ? widget.onToggleMute : null,
          ),
        ),
        Expanded(
          child: _tool(
            icon: Icons.vertical_align_center_rounded,
            label: 'Trim',
            onTap: () => setState(() => _showTrim = !_showTrim),
          ),
        ),
      ],
    ),
  );

  Widget _tool({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool emphasized = false,
    bool destructive = false,
  }) => Semantics(
    button: true,
    enabled: onTap != null,
    label: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: emphasized ? 23 : 20,
              color: onTap == null
                  ? Colors.black26
                  : destructive
                  ? const Color(0xFFB3261E)
                  : forest,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                color: onTap == null ? Colors.black26 : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _trimControl() => Container(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 3),
    decoration: BoxDecoration(
      color: mint.withValues(alpha: .24),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Text(
          'Keep',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        Expanded(
          child: RangeSlider(
            values: RangeValues(_trimStartMs, _trimEndMs),
            min: 0,
            max: max(1, widget.session.durationMs).toDouble(),
            labels: RangeLabels(
              _format(_trimStartMs.round()),
              _format(_trimEndMs.round()),
            ),
            onChanged: (values) => setState(() {
              _trimStartMs = values.start;
              _trimEndMs = values.end;
            }),
            onChangeEnd: (values) =>
                widget.onTrimChanged(values.start.round(), values.end.round()),
          ),
        ),
      ],
    ),
  );

  bool get _canSplit {
    if (!_plan.includes(widget.timestampMs, widget.session.durationMs)) {
      return false;
    }
    return <int>[
      _plan.trimStartMs,
      ..._plan.splitPointsMs,
      _plan.trimEndMs,
    ].every((point) => (point - widget.timestampMs).abs() >= 80);
  }

  bool get _canDelete =>
      _selectedSegment != null &&
      _outputDuration - _selectedSegment!.durationMs >= 100;

  void _splitAtPlayhead() {
    widget.onSplit(widget.timestampMs);
  }

  void _deleteSelected() {
    final selected = _selectedSegment;
    if (selected == null) return;
    setState(() => _selectedSegment = null);
    widget.onDeleteSegment(selected);
  }

  void _scrollChanged() {
    if (_programmaticScroll) return;
    _emitScrub();
  }

  void _emitScrub({bool immediate = false}) {
    if (!_scrollController.hasClients || _clipWidth <= 0) return;
    final outputOffset =
        (_scrollController.offset / _clipWidth * _outputDuration).round().clamp(
          0,
          _outputDuration,
        );
    final timestamp = _plan.sourceTimestampForOutputOffset(
      outputOffset,
      widget.session.durationMs,
    );
    _scrubTimer?.cancel();
    if (immediate) {
      widget.onSeek(timestamp);
    } else {
      _scrubTimer = Timer(
        const Duration(milliseconds: 32),
        () => widget.onSeek(timestamp),
      );
    }
  }

  void _syncToPlayhead() {
    if (!_scrollController.hasClients || _clipWidth <= 0) return;
    final outputOffset = _plan.outputOffsetForSourceTimestamp(
      widget.timestampMs,
      widget.session.durationMs,
    );
    final target = outputOffset / max(1, _outputDuration) * _clipWidth;
    if ((_scrollController.offset - target).abs() < 2) return;
    _programmaticScroll = true;
    _scrollController.jumpTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
    );
    _programmaticScroll = false;
  }

  int _timestampForLocalX(double localX) {
    final scroll = _scrollController.hasClients ? _scrollController.offset : 0;
    final contentX = scroll + localX - _viewportWidth / 2;
    final outputOffset = (contentX / max(1, _clipWidth) * _outputDuration)
        .round()
        .clamp(0, _outputDuration);
    return _plan.sourceTimestampForOutputOffset(
      outputOffset,
      widget.session.durationMs,
    );
  }

  VideoTimeRange? _segmentAt(int timestampMs, {bool preferRight = false}) {
    final segments = _plan.keptSegments(widget.session.durationMs);
    for (final segment in segments) {
      if (timestampMs > segment.startMs && timestampMs < segment.endMs) {
        return segment;
      }
      if (timestampMs == segment.startMs) return segment;
      if (!preferRight && timestampMs == segment.endMs) return segment;
    }
    return null;
  }

  bool _sameRange(VideoTimeRange a, VideoTimeRange b) =>
      a.startMs == b.startMs && a.endMs == b.endMs;

  int _segmentOutputStart(VideoTimeRange segment) =>
      _plan.outputOffsetForSourceTimestamp(
        segment.startMs,
        widget.session.durationMs,
      );

  String _format(int milliseconds) {
    final safe = milliseconds.clamp(0, 3599999);
    final minutes = safe ~/ 60000;
    final seconds = (safe ~/ 1000).remainder(60).toString().padLeft(2, '0');
    final tenths = safe.remainder(1000) ~/ 100;
    return '$minutes:$seconds.$tenths';
  }
}

class _TimelineTicksPainter extends CustomPainter {
  const _TimelineTicksPainter({
    required this.durationMs,
    required this.pixelsPerSecond,
  });

  final int durationMs;
  final double pixelsPerSecond;

  @override
  void paint(Canvas canvas, Size size) {
    final intervalMs = pixelsPerSecond >= 220
        ? 250
        : pixelsPerSecond >= 110
        ? 500
        : 1000;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .72)
      ..strokeWidth = 1;
    for (var time = 0; time <= durationMs; time += intervalMs) {
      final x = time / max(1, durationMs) * size.width;
      final major = time % 1000 == 0;
      canvas.drawLine(
        Offset(x, size.height - (major ? 12 : 7)),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineTicksPainter oldDelegate) =>
      oldDelegate.durationMs != durationMs ||
      oldDelegate.pixelsPerSecond != pixelsPerSecond;
}
