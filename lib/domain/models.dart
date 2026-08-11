import 'dart:ui';

enum RedactionCategory {
  face,
  person,
  email,
  phone,
  address,
  card,
  cardSecurityCode,
  url,
  qrCode,
  barcode,
  numberPlate,
  otherText,
  manual,
}

enum RedactionStyle { blur, pixelate, blackout, emoji, flowers }

enum RedactionSource { automatic, manual }

enum EditorTool { select, rectangle, brush, eraser, zoom }

enum ScanStage {
  preparing,
  faces,
  people,
  text,
  sensitiveInfo,
  numberPlates,
  codes,
  complete,
}

enum BatchItemStatus {
  queued,
  scanning,
  needsReview,
  safe,
  saved,
  failed,
  skipped,
}

class BatchScanRequest {
  const BatchScanRequest({required this.paths, this.append = false});

  final List<String> paths;
  final bool append;
}

class BatchItem {
  const BatchItem({
    required this.id,
    required this.originalPath,
    required this.status,
    this.session,
    this.error,
    this.selected = true,
  });

  final String id;
  final String originalPath;
  final ImageSession? session;
  final BatchItemStatus status;
  final String? error;
  final bool selected;

  BatchItem copyWith({
    ImageSession? session,
    BatchItemStatus? status,
    String? error,
    bool? selected,
    bool clearError = false,
  }) => BatchItem(
    id: id,
    originalPath: originalPath,
    session: session ?? this.session,
    status: status ?? this.status,
    error: clearError ? null : error ?? this.error,
    selected: selected ?? this.selected,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'originalPath': originalPath,
    'status': status.name,
    'error': error,
    'selected': selected,
    'session': session?.toJson(),
  };

  factory BatchItem.fromJson(Map<String, Object?> json) => BatchItem(
    id: json['id']! as String,
    originalPath: json['originalPath']! as String,
    status: BatchItemStatus.values.byName(json['status']! as String),
    error: json['error'] as String?,
    selected: json['selected'] as bool? ?? true,
    session: json['session'] == null
        ? null
        : ImageSession.fromJson(
            Map<String, Object?>.from(json['session']! as Map),
          ),
  );
}

class BatchSnapshot {
  const BatchSnapshot({required this.items, required this.activeIndex});

  final List<BatchItem> items;
  final int activeIndex;

  bool get isBatch => items.length > 1;
  bool get isEmpty => items.isEmpty;
  int get safeCount => items
      .where(
        (item) =>
            item.status == BatchItemStatus.safe ||
            item.status == BatchItemStatus.saved,
      )
      .length;
  int get selectedSafeCount => items
      .where(
        (item) =>
            item.selected &&
            (item.status == BatchItemStatus.safe ||
                item.status == BatchItemStatus.saved),
      )
      .length;
  int get failedCount =>
      items.where((item) => item.status == BatchItemStatus.failed).length;
  int get needsReviewCount =>
      items.where((item) => item.status == BatchItemStatus.needsReview).length;
  BatchItem? get active => activeIndex >= 0 && activeIndex < items.length
      ? items[activeIndex]
      : null;
}

extension CategoryInfo on RedactionCategory {
  String get label => switch (this) {
    RedactionCategory.face => 'Faces',
    RedactionCategory.person => 'People',
    RedactionCategory.email => 'Emails',
    RedactionCategory.phone => 'Phone numbers',
    RedactionCategory.address => 'Addresses',
    RedactionCategory.card => 'Card numbers',
    RedactionCategory.cardSecurityCode => 'Card security codes',
    RedactionCategory.url => 'URLs',
    RedactionCategory.qrCode => 'QR codes',
    RedactionCategory.barcode => 'Barcodes',
    RedactionCategory.numberPlate => 'Number plates',
    RedactionCategory.otherText => 'Other text',
    RedactionCategory.manual => 'Manual',
  };

  bool get selectedByDefault =>
      this != RedactionCategory.manual &&
      this != RedactionCategory.person &&
      this != RedactionCategory.otherText;
  RedactionStyle get defaultStyle => switch (this) {
    RedactionCategory.face => RedactionStyle.blur,
    RedactionCategory.person => RedactionStyle.blackout,
    RedactionCategory.qrCode => RedactionStyle.pixelate,
    RedactionCategory.numberPlate => RedactionStyle.pixelate,
    RedactionCategory.manual => RedactionStyle.blackout,
    _ => RedactionStyle.blackout,
  };
}

class RedactionItem {
  const RedactionItem({
    required this.id,
    required this.category,
    required this.bounds,
    required this.selected,
    required this.style,
    required this.source,
    this.confidence,
    this.label,
  });
  final String id;
  final RedactionCategory category;
  final Rect bounds;
  final bool selected;
  final RedactionStyle style;
  final RedactionSource source;
  final double? confidence;
  final String? label;

  RedactionItem copyWith({
    Rect? bounds,
    bool? selected,
    RedactionStyle? style,
  }) => RedactionItem(
    id: id,
    category: category,
    bounds: bounds ?? this.bounds,
    selected: selected ?? this.selected,
    style: style ?? this.style,
    source: source,
    confidence: confidence,
    label: label,
  );
}

class BrushStroke {
  const BrushStroke({
    required this.id,
    required this.points,
    required this.size,
    required this.style,
  });
  final String id;
  final List<Offset> points;
  final double size;
  final RedactionStyle style;
}

class ImageSession {
  const ImageSession({
    required this.sourcePath,
    required this.width,
    required this.height,
    this.items = const [],
    this.strokes = const [],
    this.previewPath,
    this.exportPath,
    this.metadataRemoved = false,
  });
  final String sourcePath;
  final int width;
  final int height;
  final List<RedactionItem> items;
  final List<BrushStroke> strokes;
  final String? previewPath;
  final String? exportPath;
  final bool metadataRemoved;

  ImageSession copyWith({
    List<RedactionItem>? items,
    List<BrushStroke>? strokes,
    String? previewPath,
    String? exportPath,
    bool? metadataRemoved,
    bool clearPreview = false,
    bool clearExport = false,
  }) => ImageSession(
    sourcePath: sourcePath,
    width: width,
    height: height,
    items: items ?? this.items,
    strokes: strokes ?? this.strokes,
    previewPath: clearPreview ? null : previewPath ?? this.previewPath,
    exportPath: clearExport ? null : exportPath ?? this.exportPath,
    metadataRemoved: metadataRemoved ?? this.metadataRemoved,
  );

  Map<String, Object?> toJson() => {
    'sourcePath': sourcePath,
    'width': width,
    'height': height,
    'items': [for (final item in items) item.toJson()],
    'strokes': [for (final stroke in strokes) stroke.toJson()],
    'previewPath': previewPath,
    'exportPath': exportPath,
    'metadataRemoved': metadataRemoved,
  };

  factory ImageSession.fromJson(Map<String, Object?> json) => ImageSession(
    sourcePath: json['sourcePath']! as String,
    width: json['width']! as int,
    height: json['height']! as int,
    items: [
      for (final value in json['items'] as List? ?? const [])
        RedactionItemPersistence.fromJson(
          Map<String, Object?>.from(value as Map),
        ),
    ],
    strokes: [
      for (final value in json['strokes'] as List? ?? const [])
        BrushStrokePersistence.fromJson(
          Map<String, Object?>.from(value as Map),
        ),
    ],
    previewPath: json['previewPath'] as String?,
    exportPath: json['exportPath'] as String?,
    metadataRemoved: json['metadataRemoved'] as bool? ?? false,
  );
}

extension RedactionItemPersistence on RedactionItem {
  Map<String, Object?> toJson() => {
    'id': id,
    'category': category.name,
    'bounds': [bounds.left, bounds.top, bounds.right, bounds.bottom],
    'selected': selected,
    'style': style.name,
    'source': source.name,
    'confidence': confidence,
    'label': label,
  };

  static RedactionItem fromJson(Map<String, Object?> json) {
    final values = (json['bounds']! as List).cast<num>();
    return RedactionItem(
      id: json['id']! as String,
      category: RedactionCategory.values.byName(json['category']! as String),
      bounds: Rect.fromLTRB(
        values[0].toDouble(),
        values[1].toDouble(),
        values[2].toDouble(),
        values[3].toDouble(),
      ),
      selected: json['selected']! as bool,
      style: RedactionStyle.values.byName(json['style']! as String),
      source: RedactionSource.values.byName(json['source']! as String),
      confidence: (json['confidence'] as num?)?.toDouble(),
      label: json['label'] as String?,
    );
  }
}

extension BrushStrokePersistence on BrushStroke {
  Map<String, Object?> toJson() => {
    'id': id,
    'points': [
      for (final point in points) [point.dx, point.dy],
    ],
    'size': size,
    'style': style.name,
  };

  static BrushStroke fromJson(Map<String, Object?> json) => BrushStroke(
    id: json['id']! as String,
    points: [
      for (final value in json['points'] as List? ?? const [])
        Offset(
          ((value as List)[0] as num).toDouble(),
          (value[1] as num).toDouble(),
        ),
    ],
    size: (json['size']! as num).toDouble(),
    style: RedactionStyle.values.byName(json['style']! as String),
  );
}

class ExportSettings {
  const ExportSettings({
    this.blurStrength = 18,
    this.pixelSize = 14,
    this.format = 'source',
  });
  final double blurStrength;
  final double pixelSize;
  final String format;
}
