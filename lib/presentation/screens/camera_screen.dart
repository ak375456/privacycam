import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/adaptive_ui.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _selectedCamera;
  List<CameraDescription> _cameras = const [];
  Object? _error;
  bool _initializing = true;
  bool _capturing = false;
  bool _pausedByLifecycle = false;
  bool _cameraPermissionDenied = false;
  FlashMode _flashMode = FlashMode.off;
  int _initializationId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive &&
        controller != null &&
        controller.value.isInitialized) {
      _pausedByLifecycle = true;
      _controller = null;
      _initializationId++;
      controller.dispose();
    } else if (state == AppLifecycleState.resumed && _pausedByLifecycle) {
      _pausedByLifecycle = false;
      _initializeCamera(_selectedCamera);
    }
  }

  Future<void> _initializeCamera([CameraDescription? preferred]) async {
    final initializationId = ++_initializationId;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
        _cameraPermissionDenied = false;
      });
    }

    CameraController? nextController;
    try {
      final cameras = _cameras.isEmpty ? await availableCameras() : _cameras;
      if (cameras.isEmpty) {
        throw CameraException(
          'NoCamera',
          'No camera was found on this device.',
        );
      }
      final selected =
          preferred ??
          cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
            orElse: () => cameras.first,
          );
      nextController = CameraController(
        selected,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await nextController.initialize();
      await nextController.setFlashMode(FlashMode.off);

      if (!mounted || initializationId != _initializationId) {
        await nextController.dispose();
        return;
      }
      final previous = _controller;
      setState(() {
        _cameras = cameras;
        _selectedCamera = selected;
        _controller = nextController;
        _flashMode = FlashMode.off;
        _initializing = false;
      });
      await previous?.dispose();
    } on CameraException catch (error) {
      await nextController?.dispose();
      if (!mounted || initializationId != _initializationId) return;
      final denied =
          error.code.contains('AccessDenied') ||
          error.code.contains('AccessRestricted');
      setState(() {
        _initializing = false;
        _cameraPermissionDenied = denied;
        _error = denied
            ? 'Camera access is off. PrivacyCam only uses it when you choose to take a photo.'
            : (error.description ?? 'The camera could not be started.');
      });
    } catch (_) {
      await nextController?.dispose();
      if (!mounted || initializationId != _initializationId) return;
      setState(() {
        _initializing = false;
        _error = 'The camera could not be started. Please try again.';
      });
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (_capturing ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(photo.path);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() => _capturing = false);
      showAdaptiveMessage(
        context,
        error.description ?? 'The photo could not be taken.',
        error: true,
      );
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    final next = _flashMode == FlashMode.off ? FlashMode.auto : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } on CameraException {
      if (!mounted) return;
      showAdaptiveMessage(
        context,
        'Flash is not available on this camera.',
        error: true,
      );
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 ||
        _selectedCamera == null ||
        _capturing ||
        _initializing) {
      return;
    }
    final currentIndex = _cameras.indexOf(_selectedCamera!);
    final next = _cameras[(currentIndex + 1) % _cameras.length];
    await _initializeCamera(next);
  }

  Future<void> _openCameraSettings() async {
    _pausedByLifecycle = true;
    final opened = await openAppSettings();
    if (!opened && mounted) {
      _pausedByLifecycle = false;
      showAdaptiveMessage(
        context,
        'Device settings could not be opened.',
        error: true,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initializationId++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            _CameraPreview(controller: controller)
          else
            _CameraStatus(
              loading: _initializing,
              message: _error?.toString(),
              permissionDenied: _cameraPermissionDenied,
              onRetry: _initializeCamera,
              onOpenSettings: _openCameraSettings,
            ),
          if (controller != null) const _CameraShade(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _RoundControl(
                        tooltip: 'Close camera',
                        icon: adaptiveIcon(
                          context,
                          material: Icons.close,
                          cupertino: CupertinoIcons.clear,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      if (controller != null)
                        _RoundControl(
                          tooltip: _flashMode == FlashMode.off
                              ? 'Use automatic flash'
                              : 'Turn flash off',
                          icon: _flashMode == FlashMode.off
                              ? adaptiveIcon(
                                  context,
                                  material: Icons.flash_off_rounded,
                                  cupertino: CupertinoIcons.bolt_slash,
                                )
                              : adaptiveIcon(
                                  context,
                                  material: Icons.flash_auto_rounded,
                                  cupertino: CupertinoIcons.bolt,
                                ),
                          onPressed: _toggleFlash,
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                if (controller != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Hold steady — scanning starts after capture',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, height: 1.25),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_cameras.length > 1 && controller != null)
                        Positioned(
                          right: 28,
                          child: _RoundControl(
                            tooltip: 'Switch camera',
                            icon: adaptiveIcon(
                              context,
                              material: Icons.cameraswitch_rounded,
                              cupertino: CupertinoIcons.camera_rotate,
                            ),
                            onPressed: _switchCamera,
                          ),
                        ),
                      if (controller != null)
                        _ShutterButton(busy: _capturing, onPressed: _takePhoto),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return const SizedBox.shrink();
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: portrait ? preview.height : preview.width,
            height: portrait ? preview.width : preview.height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _CameraShade extends StatelessWidget {
  const _CameraShade();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x99000000),
          Colors.transparent,
          Colors.transparent,
          Color(0xCC000000),
        ],
        stops: [0, .2, .65, 1],
      ),
    ),
  );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (usesCupertinoUi(context)) {
      return Tooltip(
        message: tooltip,
        child: CupertinoButton(
          minimumSize: const Size.square(48),
          padding: EdgeInsets.zero,
          color: Colors.black45,
          borderRadius: BorderRadius.circular(24),
          onPressed: onPressed,
          child: Icon(icon, color: Colors.white),
        ),
      );
    }
    return IconButton.filled(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black45,
        foregroundColor: Colors.white,
        minimumSize: const Size.square(48),
      ),
      icon: Icon(icon),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: busy ? 'Taking photo' : 'Take photo',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: busy ? 72 : 82,
          height: busy ? 72 : 82,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(17),
                    child: AdaptiveProgressIndicator(dimension: 28),
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}

class _CameraStatus extends StatelessWidget {
  const _CameraStatus({
    required this.loading,
    required this.message,
    required this.permissionDenied,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final bool loading;
  final String? message;
  final bool permissionDenied;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: AdaptiveProgressIndicator(color: Colors.white, dimension: 28),
      );
    }
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 52,
              ),
              const SizedBox(height: 18),
              Text(
                message ?? 'The camera is unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.4),
              ),
              const SizedBox(height: 22),
              AdaptiveButton(
                onPressed: permissionDenied ? onOpenSettings : onRetry,
                child: Text(permissionDenied ? 'Open settings' : 'Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
