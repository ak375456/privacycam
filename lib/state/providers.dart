import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:share_handler/share_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../services/detection_service.dart';
import '../services/export_service.dart';
import '../services/image_io_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError(),
);
final imageIoProvider = Provider((_) => ImageIoService());
final detectionProvider = Provider((ref) {
  final service = DetectionService();
  ref.onDispose(service.dispose);
  return service;
});
final exportProvider = Provider((_) => ExportService());

class AppSettings {
  static const minBlurStrength = 2.0;
  static const maxBlurStrength = 64.0;
  static const minPixelSize = 4.0;
  static const maxPixelSize = 80.0;

  const AppSettings({
    required this.onboardingDone,
    required this.autoHideCategories,
    required this.faceStyle,
    required this.peopleStyle,
    required this.sensitiveStyle,
    required this.blurStrength,
    required this.pixelSize,
    required this.format,
    required this.keepTemporary,
  });
  final bool onboardingDone;
  final Set<RedactionCategory> autoHideCategories;
  final RedactionStyle faceStyle;
  final RedactionStyle peopleStyle;
  final RedactionStyle sensitiveStyle;
  final double blurStrength;
  final double pixelSize;
  final String format;
  final bool keepTemporary;
  AppSettings copyWith({
    bool? onboardingDone,
    Set<RedactionCategory>? autoHideCategories,
    RedactionStyle? faceStyle,
    RedactionStyle? peopleStyle,
    RedactionStyle? sensitiveStyle,
    double? blurStrength,
    double? pixelSize,
    String? format,
    bool? keepTemporary,
  }) => AppSettings(
    onboardingDone: onboardingDone ?? this.onboardingDone,
    autoHideCategories: Set.unmodifiable(
      autoHideCategories ?? this.autoHideCategories,
    ),
    faceStyle: faceStyle ?? this.faceStyle,
    peopleStyle: peopleStyle ?? this.peopleStyle,
    sensitiveStyle: sensitiveStyle ?? this.sensitiveStyle,
    blurStrength: blurStrength ?? this.blurStrength,
    pixelSize: pixelSize ?? this.pixelSize,
    format: format ?? this.format,
    keepTemporary: keepTemporary ?? this.keepTemporary,
  );
}

class SettingsController extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final savedBlur = _prefs.getDouble('blurStrength') ?? 18;
    final savedPixels = _prefs.getDouble('pixelSize') ?? 14;
    final blurStrength = _normalizeBlur(savedBlur);
    final pixelSize = _normalizePixels(savedPixels);
    if (savedBlur != blurStrength) {
      unawaited(_prefs.setDouble('blurStrength', blurStrength));
    }
    if (savedPixels != pixelSize) {
      unawaited(_prefs.setDouble('pixelSize', pixelSize));
    }
    return AppSettings(
      onboardingDone: _prefs.getBool('onboardingDone') ?? false,
      autoHideCategories: _readAutoHideCategories(_prefs),
      faceStyle: RedactionStyle.values.byName(
        _prefs.getString('faceStyle') ?? 'blur',
      ),
      peopleStyle: RedactionStyle.values.byName(
        _prefs.getString('peopleStyle') ?? 'blackout',
      ),
      sensitiveStyle: RedactionStyle.values.byName(
        _prefs.getString('sensitiveStyle') ?? 'blackout',
      ),
      blurStrength: blurStrength,
      pixelSize: pixelSize,
      format: _prefs.getString('format') ?? 'source',
      keepTemporary: _prefs.getBool('keepTemporary') ?? false,
    );
  }

  Future<void> update(AppSettings value) async {
    final normalized = value.copyWith(
      blurStrength: _normalizeBlur(value.blurStrength),
      pixelSize: _normalizePixels(value.pixelSize),
    );
    state = normalized;
    await Future.wait([
      _prefs.setBool('onboardingDone', normalized.onboardingDone),
      _prefs.setStringList(
        'autoHideCategories',
        normalized.autoHideCategories.map((category) => category.name).toList()
          ..sort(),
      ),
      _prefs.setString('faceStyle', normalized.faceStyle.name),
      _prefs.setString('peopleStyle', normalized.peopleStyle.name),
      _prefs.setString('sensitiveStyle', normalized.sensitiveStyle.name),
      _prefs.setDouble('blurStrength', normalized.blurStrength),
      _prefs.setDouble('pixelSize', normalized.pixelSize),
      _prefs.setString('format', normalized.format),
      _prefs.setBool('keepTemporary', normalized.keepTemporary),
    ]);
  }

  void setBlurStrength(double value) {
    final normalized = _normalizeBlur(value);
    state = state.copyWith(blurStrength: normalized);
    unawaited(_prefs.setDouble('blurStrength', normalized));
  }

  void setPixelSize(double value) {
    final normalized = _normalizePixels(value);
    state = state.copyWith(pixelSize: normalized);
    unawaited(_prefs.setDouble('pixelSize', normalized));
  }

  double _normalizeBlur(double value) => value.isFinite
      ? value
            .clamp(AppSettings.minBlurStrength, AppSettings.maxBlurStrength)
            .toDouble()
      : 18;

  double _normalizePixels(double value) => value.isFinite
      ? value
            .clamp(AppSettings.minPixelSize, AppSettings.maxPixelSize)
            .toDouble()
      : 14;
}

Set<RedactionCategory> _readAutoHideCategories(SharedPreferences preferences) {
  final saved = preferences.getStringList('autoHideCategories');
  const addressMigrationKey = 'autoHideAddressIntroducedV1';
  if (saved == null) {
    unawaited(preferences.setBool(addressMigrationKey, true));
    return Set.unmodifiable(
      RedactionCategory.values.where(
        (category) =>
            category != RedactionCategory.manual &&
            category != RedactionCategory.person,
      ),
    );
  }
  final savedCategories = saved.toSet();
  if (preferences.getBool(addressMigrationKey) != true) {
    savedCategories.add(RedactionCategory.address.name);
    unawaited(
      preferences.setStringList(
        'autoHideCategories',
        savedCategories.toList()..sort(),
      ),
    );
    unawaited(preferences.setBool(addressMigrationKey, true));
  }
  return Set.unmodifiable(
    RedactionCategory.values.where(
      (category) =>
          category != RedactionCategory.manual &&
          savedCategories.contains(category.name),
    ),
  );
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

const privacyCamProProductId = 'app.privacycam.pro.lifetime';

enum ProPurchaseActivity { idle, loadingStore, purchasing, pending, restoring }

class ProPurchaseState {
  const ProPurchaseState({
    required this.supported,
    required this.isPro,
    this.storeAvailable = false,
    this.product,
    this.activity = ProPurchaseActivity.idle,
    this.error,
    this.notice,
  });

  final bool supported;
  final bool isPro;
  final bool storeAvailable;
  final ProductDetails? product;
  final ProPurchaseActivity activity;
  final String? error;
  final String? notice;

  bool get isBusy => activity != ProPurchaseActivity.idle;
  bool get canPurchase =>
      supported && storeAvailable && product != null && !isBusy && !isPro;

  ProPurchaseState copyWith({
    bool? supported,
    bool? isPro,
    bool? storeAvailable,
    ProductDetails? product,
    ProPurchaseActivity? activity,
    String? error,
    String? notice,
    bool clearProduct = false,
    bool clearError = false,
    bool clearNotice = false,
  }) => ProPurchaseState(
    supported: supported ?? this.supported,
    isPro: isPro ?? this.isPro,
    storeAvailable: storeAvailable ?? this.storeAvailable,
    product: clearProduct ? null : product ?? this.product,
    activity: activity ?? this.activity,
    error: clearError ? null : error ?? this.error,
    notice: clearNotice ? null : notice ?? this.notice,
  );
}

class ProPurchaseController extends Notifier<ProPurchaseState> {
  static const _entitlementKey = 'privacyCamProLifetimeUnlockedV1';
  final InAppPurchase _store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  int _restoreAttempt = 0;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  String get _storeName => Platform.isAndroid ? 'Google Play' : 'App Store';

  String get _storeAccountName =>
      Platform.isAndroid ? 'Google Account' : 'Apple Account';

  @override
  ProPurchaseState build() {
    final supported = Platform.isIOS || Platform.isAndroid;
    final initial = ProPurchaseState(
      supported: supported,
      isPro: supported ? _prefs.getBool(_entitlementKey) ?? false : false,
      activity: supported
          ? ProPurchaseActivity.loadingStore
          : ProPurchaseActivity.idle,
    );
    if (supported) {
      _purchaseSubscription = _store.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error) {
          state = state.copyWith(
            activity: ProPurchaseActivity.idle,
            error: 'The store purchase could not be completed. Try again.',
            clearNotice: true,
          );
        },
      );
      ref.onDispose(() => _purchaseSubscription?.cancel());
      scheduleMicrotask(_initializeStore);
    }
    return initial;
  }

  Future<void> _initializeStore() async {
    await loadProduct();
    if (!state.storeAvailable) return;
    if (Platform.isAndroid) {
      await _syncAndroidEntitlement(userInitiated: false);
      return;
    }
    // StoreKit 2 returns only verified current entitlements here. This quietly
    // recovers a lifetime purchase after reinstall while the visible Restore
    // Purchases control remains available for the user.
    try {
      await _store.restorePurchases();
    } catch (_) {
      // Product loading still succeeded, so a temporary restore failure should
      // not prevent a new purchase or replace an already cached entitlement.
    }
  }

  Future<void> loadProduct() async {
    if (!state.supported) return;
    state = state.copyWith(
      activity: ProPurchaseActivity.loadingStore,
      clearError: true,
      clearNotice: true,
    );
    try {
      final available = await _store.isAvailable();
      if (!available) {
        state = state.copyWith(
          storeAvailable: false,
          activity: ProPurchaseActivity.idle,
          error: '$_storeName is unavailable right now. Try again later.',
          clearProduct: true,
        );
        return;
      }
      final response = await _store.queryProductDetails({
        privacyCamProProductId,
      });
      final product = response.productDetails
          .where((item) => item.id == privacyCamProProductId)
          .firstOrNull;
      if (response.error != null || product == null) {
        state = state.copyWith(
          storeAvailable: true,
          activity: ProPurchaseActivity.idle,
          error:
              'PrivacyCam Pro is not available from $_storeName yet. Try again shortly.',
          clearProduct: true,
        );
        return;
      }
      state = state.copyWith(
        storeAvailable: true,
        product: product,
        activity: ProPurchaseActivity.idle,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        storeAvailable: false,
        activity: ProPurchaseActivity.idle,
        error: 'PrivacyCam could not contact $_storeName. Try again.',
        clearProduct: true,
      );
    }
  }

  Future<void> purchase() async {
    if (!state.supported || state.isPro || state.isBusy) return;
    if (state.product == null || !state.storeAvailable) {
      await loadProduct();
    }
    final product = state.product;
    if (product == null || !state.storeAvailable || state.isBusy) return;
    state = state.copyWith(
      activity: ProPurchaseActivity.purchasing,
      clearError: true,
      clearNotice: true,
    );
    try {
      final started = await _store.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!started) {
        state = state.copyWith(
          activity: ProPurchaseActivity.idle,
          error: 'The purchase could not be started. Please try again.',
        );
      }
    } catch (_) {
      state = state.copyWith(
        activity: ProPurchaseActivity.idle,
        error: 'The purchase could not be started. Please try again.',
      );
    }
  }

  Future<void> restore() async {
    if (!state.supported || state.isBusy) return;
    if (Platform.isAndroid) {
      await _syncAndroidEntitlement(userInitiated: true);
      return;
    }
    final attempt = ++_restoreAttempt;
    state = state.copyWith(
      activity: ProPurchaseActivity.restoring,
      clearError: true,
      clearNotice: true,
    );
    try {
      await _store.restorePurchases();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (attempt != _restoreAttempt ||
          state.activity != ProPurchaseActivity.restoring) {
        return;
      }
      state = state.copyWith(
        activity: ProPurchaseActivity.idle,
        notice: state.isPro
            ? 'PrivacyCam Pro is already unlocked.'
            : 'No previous PrivacyCam Pro purchase was found for this $_storeAccountName.',
      );
    } catch (_) {
      if (attempt != _restoreAttempt) return;
      state = state.copyWith(
        activity: ProPurchaseActivity.idle,
        error: 'Your purchase could not be restored. Please try again.',
      );
    }
  }

  Future<void> _syncAndroidEntitlement({required bool userInitiated}) async {
    if (!Platform.isAndroid || !state.supported) return;
    final attempt = ++_restoreAttempt;
    if (userInitiated) {
      state = state.copyWith(
        activity: ProPurchaseActivity.restoring,
        clearError: true,
        clearNotice: true,
      );
    }
    try {
      final addition = _store
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      if (attempt != _restoreAttempt) return;
      if (response.error != null) {
        throw StateError(response.error!.message);
      }
      final purchase = response.pastPurchases
          .where(
            (item) =>
                item.productID == privacyCamProProductId &&
                (item.status == PurchaseStatus.purchased ||
                    item.status == PurchaseStatus.restored),
          )
          .firstOrNull;
      final ownsPro = purchase != null && _hasStoreVerificationData(purchase);
      await _prefs.setBool(_entitlementKey, ownsPro);
      if (attempt != _restoreAttempt) return;
      state = state.copyWith(
        isPro: ownsPro,
        activity: ProPurchaseActivity.idle,
        notice: userInitiated
            ? ownsPro
                  ? 'PrivacyCam Pro was restored.'
                  : 'No previous PrivacyCam Pro purchase was found for this $_storeAccountName.'
            : null,
        clearNotice: !userInitiated,
        clearError: true,
      );
      if (purchase?.pendingCompletePurchase ?? false) {
        await _completePurchaseSafely(purchase!);
      }
    } catch (_) {
      if (attempt != _restoreAttempt) return;
      state = state.copyWith(
        activity: ProPurchaseActivity.idle,
        error: userInitiated
            ? 'Your purchase could not be restored. Please try again.'
            : state.error,
        clearNotice: userInitiated,
      );
    }
  }

  bool _hasStoreVerificationData(PurchaseDetails purchase) {
    if (!Platform.isAndroid) return true;
    return purchase.verificationData.source == 'google_play' &&
        purchase.verificationData.localVerificationData.isNotEmpty &&
        purchase.verificationData.serverVerificationData.isNotEmpty;
  }

  Future<void> _completePurchaseSafely(PurchaseDetails purchase) async {
    try {
      await _store.completePurchase(purchase);
    } catch (_) {
      // An unfinished transaction is returned again by the store. The next
      // foreground launch or Restore Purchases retries acknowledgement.
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != privacyCamProProductId) continue;
      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(
            activity: ProPurchaseActivity.pending,
            notice:
                'Purchase pending. Pro will unlock after payment is approved.',
            clearError: true,
          );
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          // StoreKit 2 forwards verified transactions. Google Play purchases
          // must also carry the signed purchase JSON and purchase token; a
          // production backend can verify that token with the Play API.
          if (!_hasStoreVerificationData(purchase)) {
            state = state.copyWith(
              activity: ProPurchaseActivity.idle,
              error:
                  'The store could not verify this purchase. Please try again.',
              clearNotice: true,
            );
            continue;
          }
          await _prefs.setBool(_entitlementKey, true);
          state = state.copyWith(
            isPro: true,
            activity: ProPurchaseActivity.idle,
            notice: purchase.status == PurchaseStatus.restored
                ? 'PrivacyCam Pro was restored.'
                : 'PrivacyCam Pro is unlocked for life.',
            clearError: true,
          );
          _restoreAttempt++;
          if (purchase.pendingCompletePurchase) {
            await _completePurchaseSafely(purchase);
          }
        case PurchaseStatus.canceled:
          state = state.copyWith(
            activity: ProPurchaseActivity.idle,
            notice: 'Purchase cancelled. Nothing was charged.',
            clearError: true,
          );
        case PurchaseStatus.error:
          state = state.copyWith(
            activity: ProPurchaseActivity.idle,
            error:
                purchase.error?.message ??
                '$_storeName could not complete the purchase.',
            clearNotice: true,
          );
      }
    }
  }

  void clearFeedback() {
    state = state.copyWith(clearError: true, clearNotice: true);
  }
}

final proPurchaseProvider =
    NotifierProvider<ProPurchaseController, ProPurchaseState>(
      ProPurchaseController.new,
    );

final proAccessProvider = Provider<bool>((ref) {
  final purchase = ref.watch(proPurchaseProvider);
  return !purchase.supported || purchase.isPro;
});

final batchAccessProvider = Provider<bool>(
  (ref) => ref.watch(proAccessProvider),
);

final batchLimitProvider = Provider<int>(
  (ref) => ref.watch(batchAccessProvider) ? 10 : 1,
);

class BatchRevisionController extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final batchRevisionProvider = NotifierProvider<BatchRevisionController, int>(
  BatchRevisionController.new,
);

class SessionController extends Notifier<ImageSession?> {
  static const _batchStorageKey = 'privacyCamBatchV1';
  final _undo = <ImageSession>[];
  final _redo = <ImageSession>[];
  List<BatchItem> _batch = [];
  int _activeIndex = -1;
  Future<void> _persistenceChain = Future.value();

  BatchSnapshot get batchSnapshot => BatchSnapshot(
    items: List.unmodifiable(_batch),
    activeIndex: _activeIndex,
  );

  @override
  ImageSession? build() {
    _restoreBatch();
    if (_activeIndex < 0 || _activeIndex >= _batch.length) return null;
    return _batch[_activeIndex].session;
  }

  void _restoreBatch() {
    final raw = ref.read(sharedPreferencesProvider).getString(_batchStorageKey);
    if (raw == null) return;
    try {
      final json = Map<String, Object?>.from(jsonDecode(raw) as Map);
      final restored = <BatchItem>[];
      for (final value in json['items'] as List? ?? const []) {
        var item = BatchItem.fromJson(Map<String, Object?>.from(value as Map));
        final sessionExists =
            item.session != null && File(item.session!.sourcePath).existsSync();
        final originalExists = File(item.originalPath).existsSync();
        if (!sessionExists && !originalExists) continue;
        if (!sessionExists) {
          item = BatchItem(
            id: item.id,
            originalPath: item.originalPath,
            status: BatchItemStatus.queued,
            selected: item.selected,
          );
        } else {
          final session = item.session!;
          final previewExists =
              session.previewPath != null &&
              File(session.previewPath!).existsSync();
          final exportExists =
              session.exportPath != null &&
              File(session.exportPath!).existsSync();
          final restoredSession = session.copyWith(
            clearPreview: !previewExists,
            clearExport: !exportExists,
          );
          var status = item.status == BatchItemStatus.scanning
              ? BatchItemStatus.queued
              : item.status;
          if ((status == BatchItemStatus.safe ||
                  status == BatchItemStatus.saved) &&
              !previewExists &&
              !exportExists) {
            status = BatchItemStatus.needsReview;
          }
          item = item.copyWith(session: restoredSession, status: status);
        }
        restored.add(item);
      }
      _batch = restored;
      if (_batch.isEmpty) return;
      final savedIndex = json['activeIndex'] as int? ?? 0;
      _activeIndex = savedIndex.clamp(0, _batch.length - 1);
      if (_batch[_activeIndex].session == null) {
        _activeIndex = _batch.indexWhere((item) => item.session != null);
      }
    } catch (_) {
      _batch = [];
      _activeIndex = -1;
      unawaited(ref.read(sharedPreferencesProvider).remove(_batchStorageKey));
    }
  }

  void _notifyBatch() {
    ref.read(batchRevisionProvider.notifier).bump();
    final json = jsonEncode({
      'activeIndex': _activeIndex,
      'items': [for (final item in _batch) item.toJson()],
    });
    _persistenceChain = _persistenceChain
        .then(
          (_) => ref
              .read(sharedPreferencesProvider)
              .setString(_batchStorageKey, json),
        )
        .then((_) {})
        .catchError((_) {});
  }

  void _syncActive(
    ImageSession session, {
    BatchItemStatus? status,
    String? error,
    bool clearError = false,
  }) {
    state = session;
    if (_activeIndex >= 0 && _activeIndex < _batch.length) {
      _batch[_activeIndex] = _batch[_activeIndex].copyWith(
        session: session,
        status: status,
        error: error,
        clearError: clearError,
      );
    }
    _notifyBatch();
  }

  Future<void> importPath(String path) async {
    await beginBatch([path]);
    await processPending();
  }

  Future<void> replace(ImageSession value) async {
    await clear();
    _batch = [
      BatchItem(
        id: 'image_${DateTime.now().microsecondsSinceEpoch}',
        originalPath: value.sourcePath,
        session: value,
        status: BatchItemStatus.needsReview,
      ),
    ];
    _activeIndex = 0;
    _syncActive(value, status: BatchItemStatus.needsReview);
  }

  Future<int> beginBatch(List<String> paths, {bool append = false}) async {
    if (!append) await clear();
    final available = ref.read(batchLimitProvider) - _batch.length;
    if (available <= 0) return 0;
    final accepted = paths.take(available).toList();
    final start = _batch.length;
    _batch = [
      ..._batch,
      for (var index = 0; index < accepted.length; index++)
        BatchItem(
          id: 'image_${DateTime.now().microsecondsSinceEpoch}_${start + index}',
          originalPath: accepted[index],
          status: BatchItemStatus.queued,
        ),
    ];
    if (_activeIndex < 0 && _batch.isNotEmpty) _activeIndex = 0;
    _notifyBatch();
    return accepted.length;
  }

  Future<void> processPending({
    void Function(int current, int total)? onItem,
    void Function(ScanStage stage)? onStage,
    bool Function()? shouldCancel,
  }) async {
    _requireBatchAccess();
    final pending = [
      for (var index = 0; index < _batch.length; index++)
        if (_batch[index].status == BatchItemStatus.queued) index,
    ];
    for (var position = 0; position < pending.length; position++) {
      if (shouldCancel?.call() ?? false) break;
      final index = pending[position];
      onItem?.call(position + 1, pending.length);
      _activeIndex = index;
      _undo.clear();
      _redo.clear();
      var item = _batch[index].copyWith(
        status: BatchItemStatus.scanning,
        clearError: true,
      );
      _batch[index] = item;
      state = item.session;
      _notifyBatch();
      try {
        var session = item.session;
        if (session == null) {
          session = await ref
              .read(imageIoProvider)
              .normalize(item.originalPath);
          if (session.sourcePath != item.originalPath) {
            await ref
                .read(imageIoProvider)
                .deleteIfTemporary(item.originalPath);
          }
          item = item.copyWith(session: session);
          _batch[index] = item;
          state = session;
          _notifyBatch();
        }
        if (shouldCancel?.call() ?? false) {
          _batch[index] = _batch[index].copyWith(
            status: BatchItemStatus.queued,
          );
          _notifyBatch();
          break;
        }
        await scan(onStage ?? (_) {});
        if (shouldCancel?.call() ?? false) break;
      } catch (error) {
        _batch[index] = _batch[index].copyWith(
          status: BatchItemStatus.failed,
          error: error.toString(),
        );
        state = _batch[index].session;
        _notifyBatch();
      }
    }
    final firstReview = _batch.indexWhere(
      (item) => item.status == BatchItemStatus.needsReview,
    );
    final firstSafe = _batch.indexWhere(
      (item) =>
          item.status == BatchItemStatus.safe ||
          item.status == BatchItemStatus.saved,
    );
    final next = firstReview >= 0 ? firstReview : firstSafe;
    if (next >= 0) activate(next);
  }

  void activate(int index) {
    if (index < 0 || index >= _batch.length) return;
    final session = _batch[index].session;
    if (session == null) return;
    _activeIndex = index;
    _undo.clear();
    _redo.clear();
    state = session;
    _notifyBatch();
  }

  Future<void> clear() async {
    final oldBatch = [..._batch];
    final old = state;
    state = null;
    _batch = [];
    _activeIndex = -1;
    _undo.clear();
    _redo.clear();
    await _persistenceChain;
    await ref.read(sharedPreferencesProvider).remove(_batchStorageKey);
    ref.read(batchRevisionProvider.notifier).bump();
    if (!ref.read(settingsProvider).keepTemporary) {
      final io = ref.read(imageIoProvider);
      final sessions = <ImageSession>{
        for (final item in oldBatch)
          if (item.session != null) item.session!,
      };
      if (old != null) sessions.add(old);
      for (final session in sessions) {
        await io.deleteWorkingFile(session.sourcePath);
        await io.deleteWorkingFile(session.previewPath);
        await io.deleteWorkingFile(session.exportPath);
      }
    }
  }

  void _commit(ImageSession next) {
    final previous = state;
    if (previous != null) _undo.add(previous);
    final updated = next.copyWith(clearPreview: true, clearExport: true);
    _syncActive(updated, status: BatchItemStatus.needsReview);
    _redo.clear();
    if (previous != null && !ref.read(settingsProvider).keepTemporary) {
      unawaited(
        ref.read(imageIoProvider).deleteWorkingFile(previous.previewPath),
      );
      unawaited(
        ref.read(imageIoProvider).deleteWorkingFile(previous.exportPath),
      );
    }
  }

  void toggle(String id) {
    final s = state!;
    _commit(
      s.copyWith(
        items: [
          for (final i in s.items)
            i.id == id ? i.copyWith(selected: !i.selected) : i,
        ],
      ),
    );
  }

  void selectAll() {
    final s = state!;
    _commit(
      s.copyWith(items: [for (final i in s.items) i.copyWith(selected: true)]),
    );
  }

  void setCategorySelected(RedactionCategory category, bool selected) {
    final s = state!;
    _commit(
      s.copyWith(
        items: [
          for (final item in s.items)
            item.category == category
                ? item.copyWith(selected: selected)
                : item,
        ],
      ),
    );
  }

  void setStyle(String id, RedactionStyle style) {
    final s = state!;
    _commit(
      s.copyWith(
        items: [
          for (final i in s.items) i.id == id ? i.copyWith(style: style) : i,
        ],
      ),
    );
  }

  void setAllStyle(RedactionStyle style) {
    final s = state!;
    _commit(
      s.copyWith(
        items: [
          for (final i in s.items)
            if (i.selected) i.copyWith(style: style) else i,
        ],
      ),
    );
  }

  void updateBounds(String id, Rect bounds) {
    final s = state!;
    _commit(
      s.copyWith(
        items: [
          for (final i in s.items) i.id == id ? i.copyWith(bounds: bounds) : i,
        ],
      ),
    );
  }

  void deleteItem(String id) {
    final s = state!;
    _commit(s.copyWith(items: s.items.where((i) => i.id != id).toList()));
  }

  String addRectangle(Rect rect, RedactionStyle style) {
    final s = state!;
    final id = 'manual_${DateTime.now().microsecondsSinceEpoch}';
    _commit(
      s.copyWith(
        items: [
          ...s.items,
          RedactionItem(
            id: id,
            category: RedactionCategory.manual,
            bounds: rect,
            selected: true,
            style: style,
            source: RedactionSource.manual,
          ),
        ],
      ),
    );
    return id;
  }

  void addStroke(BrushStroke stroke) {
    final s = state!;
    _commit(s.copyWith(strokes: [...s.strokes, stroke]));
  }

  void eraseNearest(Offset point) {
    final s = state!;
    if (s.strokes.isEmpty) return;
    final sorted = [...s.strokes]
      ..sort((a, b) => _distance(a, point).compareTo(_distance(b, point)));
    _commit(
      s.copyWith(
        strokes: s.strokes.where((e) => e.id != sorted.first.id).toList(),
      ),
    );
  }

  double _distance(BrushStroke s, Offset p) => s.points.isEmpty
      ? double.infinity
      : s.points.map((e) => (e - p).distance).reduce((a, b) => a < b ? a : b);
  void undo() {
    if (_undo.isEmpty || state == null) return;
    _redo.add(state!);
    _syncActive(
      _undo.removeLast().copyWith(clearPreview: true, clearExport: true),
      status: BatchItemStatus.needsReview,
    );
  }

  void redo() {
    if (_redo.isEmpty || state == null) return;
    _undo.add(state!);
    _syncActive(
      _redo.removeLast().copyWith(clearPreview: true, clearExport: true),
      status: BatchItemStatus.needsReview,
    );
  }

  void resetEdits() {
    final s = state!;
    final autoHide = ref.read(settingsProvider).autoHideCategories;
    _commit(
      s.copyWith(
        items: [
          for (final item in s.items.where(
            (i) => i.source == RedactionSource.automatic,
          ))
            item.copyWith(selected: autoHide.contains(item.category)),
        ],
        strokes: const [],
      ),
    );
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  Future<void> scan(void Function(ScanStage) onStage) async {
    final s = state!;
    final size = Size(s.width.toDouble(), s.height.toDouble());
    final service = ref.read(detectionProvider);
    onStage(ScanStage.faces);
    final faces = await service.detectFaces(s.sourcePath, size);
    onStage(ScanStage.people);
    final people = await service.detectPeople(s.sourcePath, size);
    onStage(ScanStage.text);
    final text = await service.detectText(s.sourcePath, size);
    onStage(ScanStage.sensitiveInfo);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    onStage(ScanStage.numberPlates);
    final numberPlates = await service.detectNumberPlates(s.sourcePath, size);
    onStage(ScanStage.codes);
    final codes = await service.detectCodes(s.sourcePath, size);
    final settings = ref.read(settingsProvider);
    _syncActive(
      s.copyWith(
        items: [
          // People are placed below faces so a face remains easy to tap when
          // the two automatic regions overlap.
          for (final item in [
            ...people,
            ...faces,
            ...text,
            ...numberPlates,
            ...codes,
          ])
            item.copyWith(
              selected: settings.autoHideCategories.contains(item.category),
              style: switch (item.category) {
                RedactionCategory.face => settings.faceStyle,
                RedactionCategory.person => settings.peopleStyle,
                RedactionCategory.qrCode => RedactionStyle.pixelate,
                RedactionCategory.numberPlate => RedactionStyle.pixelate,
                RedactionCategory.cardSecurityCode => RedactionStyle.blackout,
                RedactionCategory.otherText => item.style,
                _ => settings.sensitiveStyle,
              },
            ),
        ],
      ),
      status: BatchItemStatus.needsReview,
      clearError: true,
    );
    onStage(ScanStage.complete);
  }

  Future<void> export() async {
    final settings = ref.read(settingsProvider);
    final previous = state!;
    final next = await ref
        .read(exportProvider)
        .export(
          previous,
          ExportSettings(
            blurStrength: settings.blurStrength,
            pixelSize: settings.pixelSize,
            format: settings.format,
          ),
        );
    final previousStatus = _activeIndex >= 0 && _activeIndex < _batch.length
        ? _batch[_activeIndex].status
        : BatchItemStatus.safe;
    _syncActive(
      next,
      status: previousStatus == BatchItemStatus.saved
          ? BatchItemStatus.saved
          : BatchItemStatus.safe,
      clearError: true,
    );
    if (!settings.keepTemporary &&
        previous.exportPath != null &&
        previous.exportPath != next.exportPath) {
      await ref.read(imageIoProvider).deleteWorkingFile(previous.exportPath);
    }
  }

  Future<void> preview() async {
    final settings = ref.read(settingsProvider);
    final previous = state!;
    final next = await ref
        .read(exportProvider)
        .preview(
          previous,
          ExportSettings(
            blurStrength: settings.blurStrength,
            pixelSize: settings.pixelSize,
            format: settings.format,
          ),
        );
    _syncActive(next, status: BatchItemStatus.safe, clearError: true);
    if (!settings.keepTemporary) {
      if (previous.previewPath != null &&
          previous.previewPath != next.previewPath) {
        await ref.read(imageIoProvider).deleteWorkingFile(previous.previewPath);
      }
      if (previous.exportPath != null && next.exportPath == null) {
        await ref.read(imageIoProvider).deleteWorkingFile(previous.exportPath);
      }
    }
  }

  int? nextNeedsReviewIndex({bool includeCurrent = false}) {
    if (_batch.isEmpty) return null;
    final start = includeCurrent ? _activeIndex : _activeIndex + 1;
    for (var offset = 0; offset < _batch.length; offset++) {
      final index = (start + offset) % _batch.length;
      if (_batch[index].status == BatchItemStatus.needsReview &&
          _batch[index].session != null) {
        return index;
      }
    }
    return null;
  }

  int? previousReviewableIndex() {
    if (_batch.length < 2) return null;
    for (var offset = 1; offset < _batch.length; offset++) {
      final index = (_activeIndex - offset) % _batch.length;
      if (_batch[index].session != null &&
          _batch[index].status != BatchItemStatus.failed &&
          _batch[index].status != BatchItemStatus.skipped) {
        return index;
      }
    }
    return null;
  }

  void toggleBatchSelection(int index) {
    if (index < 0 || index >= _batch.length) return;
    _batch[index] = _batch[index].copyWith(selected: !_batch[index].selected);
    _notifyBatch();
  }

  void setAllSafeSelected(bool selected) {
    _batch = [
      for (final item in _batch)
        if (item.status == BatchItemStatus.safe ||
            item.status == BatchItemStatus.saved)
          item.copyWith(selected: selected)
        else
          item,
    ];
    _notifyBatch();
  }

  void markActiveSaved() {
    if (_activeIndex < 0 || _activeIndex >= _batch.length) return;
    _batch[_activeIndex] = _batch[_activeIndex].copyWith(
      status: BatchItemStatus.saved,
    );
    _notifyBatch();
  }

  void skip(int index) {
    if (index < 0 || index >= _batch.length) return;
    _batch[index] = _batch[index].copyWith(status: BatchItemStatus.skipped);
    _notifyBatch();
  }

  void retry(int index) {
    if (index < 0 || index >= _batch.length) return;
    _batch[index] = _batch[index].copyWith(
      status: BatchItemStatus.queued,
      clearError: true,
    );
    _notifyBatch();
  }

  Future<void> removeFromBatch(int index) async {
    if (index < 0 || index >= _batch.length) return;
    final removed = _batch[index];
    _batch = [..._batch]..removeAt(index);
    if (_batch.isEmpty) {
      state = null;
      _activeIndex = -1;
    } else {
      if (_activeIndex > index) _activeIndex--;
      if (_activeIndex >= _batch.length) _activeIndex = _batch.length - 1;
      if (_activeIndex == index || state == removed.session) {
        final replacement = _batch.indexWhere((item) => item.session != null);
        _activeIndex = replacement >= 0 ? replacement : 0;
        state = _batch[_activeIndex].session;
      }
    }
    _undo.clear();
    _redo.clear();
    _notifyBatch();
    if (!ref.read(settingsProvider).keepTemporary && removed.session != null) {
      final io = ref.read(imageIoProvider);
      await io.deleteWorkingFile(removed.session!.sourcePath);
      await io.deleteWorkingFile(removed.session!.previewPath);
      await io.deleteWorkingFile(removed.session!.exportPath);
    }
  }

  Future<List<String>> exportSelected({
    void Function(int current, int total)? onProgress,
  }) async {
    _requireBatchAccess();
    final selected = [
      for (var index = 0; index < _batch.length; index++)
        if (_batch[index].selected &&
            (_batch[index].status == BatchItemStatus.safe ||
                _batch[index].status == BatchItemStatus.saved) &&
            _batch[index].session != null)
          index,
    ];
    final settings = ref.read(settingsProvider);
    final paths = <String>[];
    for (var position = 0; position < selected.length; position++) {
      final index = selected[position];
      onProgress?.call(position + 1, selected.length);
      var session = _batch[index].session!;
      if (session.exportPath == null) {
        session = await ref
            .read(exportProvider)
            .export(
              session,
              ExportSettings(
                blurStrength: settings.blurStrength,
                pixelSize: settings.pixelSize,
                format: settings.format,
              ),
            );
        _batch[index] = _batch[index].copyWith(session: session);
        if (index == _activeIndex) state = session;
        _notifyBatch();
      }
      if (session.exportPath != null) paths.add(session.exportPath!);
    }
    return paths;
  }

  Future<({int saved, List<String> errors})> saveSelected({
    void Function(int current, int total)? onProgress,
  }) async {
    _requireBatchAccess();
    final paths = await exportSelected(onProgress: onProgress);
    var saved = 0;
    final errors = <String>[];
    for (var index = 0; index < paths.length; index++) {
      onProgress?.call(index + 1, paths.length);
      try {
        await ref.read(imageIoProvider).saveToGallery(paths[index]);
        final entryIndex = _batch.indexWhere(
          (item) => item.session?.exportPath == paths[index],
        );
        if (entryIndex >= 0) {
          _batch[entryIndex] = _batch[entryIndex].copyWith(
            status: BatchItemStatus.saved,
          );
        }
        saved++;
      } catch (error) {
        errors.add(error.toString());
      }
    }
    _notifyBatch();
    return (saved: saved, errors: errors);
  }

  void _requireBatchAccess() {
    if (_batch.length > 1 && !ref.read(batchAccessProvider)) {
      throw StateError(
        'PrivacyCam Pro is required to process more than one photo.',
      );
    }
  }
}

final sessionProvider = NotifierProvider<SessionController, ImageSession?>(
  SessionController.new,
);

final batchProvider = Provider<BatchSnapshot>((ref) {
  ref.watch(batchRevisionProvider);
  ref.watch(sessionProvider);
  return ref.read(sessionProvider.notifier).batchSnapshot;
});

final incomingShareProvider = StreamProvider<SharedMedia>((ref) async* {
  final initial = await ShareHandler.instance.getInitialSharedMedia();
  if (initial != null) yield initial;
  yield* ShareHandler.instance.sharedMediaStream;
});
