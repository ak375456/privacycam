import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../domain/video_models.dart';
import '../../state/video_providers.dart';
import '../widgets/adaptive_ui.dart';
import '../widgets/privacy_loader.dart';

class VideoScanningScreen extends ConsumerStatefulWidget {
  const VideoScanningScreen({super.key, required this.path});
  final String path;

  @override
  ConsumerState<VideoScanningScreen> createState() =>
      _VideoScanningScreenState();
}

class _VideoScanningScreenState extends ConsumerState<VideoScanningScreen> {
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    Future.microtask(_start);
  }

  Future<void> _start() async {
    try {
      await ref.read(videoEditorProvider.notifier).importPath(widget.path);
      if (!mounted) return;
      await ref.read(videoEditorProvider.notifier).scan();
      if (!mounted) return;
      final state = ref.read(videoEditorProvider);
      if (state.stage == VideoWorkStage.ready) context.go('/video/editor');
    } on VideoProRequiredException {
      if (!mounted) return;
      final unlocked = await context.push<bool>('/pro');
      if (!mounted) return;
      if (unlocked == true) {
        await _start();
        return;
      }
      await ref.read(videoServiceProvider).deleteWorkingFile(widget.path);
      await ref.read(videoEditorProvider.notifier).clear();
      if (mounted) context.go('/home');
    } catch (_) {
      // The controller owns the user-safe error message.
    }
  }

  Future<void> _cancel() async {
    await ref.read(videoEditorProvider.notifier).cancelWork();
    await ref.read(videoEditorProvider.notifier).clear();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoEditorProvider);
    final failed = state.stage == VideoWorkStage.failed;
    return Scaffold(
      appBar: adaptiveNavigationBar(
        context,
        title: const Text('Checking video'),
        automaticallyImplyLeading: false,
        actions: [
          AdaptiveIconButton(
            tooltip: 'Cancel',
            onPressed: _cancel,
            icon: Icon(
              adaptiveIcon(
                context,
                material: Icons.close_rounded,
                cupertino: CupertinoIcons.xmark,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 54,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Video review stopped',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        state.error ??
                            'PrivacyCam could not analyze this video.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      AdaptiveButton(
                        onPressed: () {
                          setState(() => _started = false);
                          didChangeDependencies();
                        },
                        child: const Text('Try again'),
                      ),
                      AdaptiveButton(
                        style: AdaptiveButtonStyle.plain,
                        onPressed: _cancel,
                        child: const Text('Choose another video'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PrivacyLoader(
                        label: 'Protecting the moments that matter',
                        detail: 'Everything stays on this device',
                      ),
                      const SizedBox(height: 28),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: state.progress.clamp(0, 1),
                          minHeight: 9,
                          color: forest,
                          backgroundColor: mint,
                        ),
                      ),
                      const SizedBox(height: 14),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          state.detail,
                          key: ValueKey(state.detail),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF52615D)),
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'You will review and adjust every result before export. Audio is kept, but its contents are not analyzed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
