import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/screens/editor_screen.dart';
import '../presentation/screens/export_screen.dart';
import '../presentation/screens/batch_screen.dart';
import '../presentation/screens/camera_screen.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/onboarding_screen.dart';
import '../presentation/screens/pdf_editor_screen.dart';
import '../presentation/screens/pdf_export_screen.dart';
import '../presentation/screens/pdf_review_screen.dart';
import '../presentation/screens/pdf_scanning_screen.dart';
import '../presentation/screens/pro_screen.dart';
import '../presentation/screens/review_screen.dart';
import '../presentation/screens/scanning_screen.dart';
import '../presentation/screens/settings_screen.dart';
import '../presentation/screens/video_editor_screen.dart';
import '../presentation/screens/video_export_screen.dart';
import '../presentation/screens/video_clip_selection_screen.dart';
import '../presentation/screens/video_scanning_screen.dart';
import '../state/providers.dart';
import '../domain/models.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: ref.read(settingsProvider).onboardingDone
        ? '/home'
        : '/onboarding',
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/camera', builder: (_, _) => const CameraScreen()),
      GoRoute(
        path: '/scan',
        builder: (_, state) {
          final extra = state.extra;
          return ScanningScreen(
            request: switch (extra) {
              BatchScanRequest request => request,
              String path => BatchScanRequest(paths: [path]),
              _ => null,
            },
          );
        },
      ),
      GoRoute(path: '/batch', builder: (_, _) => const BatchScreen()),
      GoRoute(path: '/review', builder: (_, _) => const ReviewScreen()),
      GoRoute(path: '/editor', builder: (_, _) => const EditorScreen()),
      GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/pdf/scan',
        builder: (_, state) => PdfScanningScreen(path: state.extra! as String),
      ),
      GoRoute(path: '/pdf/review', builder: (_, _) => const PdfReviewScreen()),
      GoRoute(path: '/pdf/editor', builder: (_, _) => const PdfEditorScreen()),
      GoRoute(path: '/pdf/export', builder: (_, _) => const PdfExportScreen()),
      GoRoute(
        path: '/video/scan',
        builder: (_, state) =>
            VideoScanningScreen(path: state.extra as String?),
      ),
      GoRoute(
        path: '/video/trim',
        builder: (_, _) => const VideoClipSelectionScreen(),
      ),
      GoRoute(
        path: '/video/editor',
        builder: (_, _) => const VideoEditorScreen(),
      ),
      GoRoute(
        path: '/video/export',
        builder: (_, _) => const VideoExportScreen(),
      ),
      GoRoute(
        path: '/pro',
        builder: (_, state) => ProScreen(
          request: state.extra is BatchScanRequest
              ? state.extra! as BatchScanRequest
              : null,
        ),
      ),
    ],
  ),
);
