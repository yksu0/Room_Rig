// lib/models/item_detection.dart
// Canonical 2D detection entity from a scan frame (bbox + confidence).

class BBox2D {
  final double left;
  final double top;
  final double width;
  final double height;

  const BBox2D({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  factory BBox2D.fromJson(Map<String, dynamic> json) {
    return BBox2D(
      left: (json['left'] as num?)?.toDouble() ?? 0,
      top: (json['top'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 0,
      height: (json['height'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Detected item from a scan frame before fusion into a [ScanObject].
class ItemDetection {
  final String id;
  final String label;
  final String category;
  final BBox2D bbox;
  final double confidence;
  final int sourceFrame;

  const ItemDetection({
    required this.id,
    required this.label,
    required this.category,
    required this.bbox,
    required this.confidence,
    required this.sourceFrame,
  });

  ItemDetection copyWith({
    String? label,
    String? category,
    BBox2D? bbox,
    double? confidence,
    int? sourceFrame,
  }) {
    return ItemDetection(
      id: id,
      label: label ?? this.label,
      category: category ?? this.category,
      bbox: bbox ?? this.bbox,
      confidence: confidence ?? this.confidence,
      sourceFrame: sourceFrame ?? this.sourceFrame,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'category': category,
        'bbox': bbox.toJson(),
        'confidence': confidence,
        'sourceFrame': sourceFrame,
      };

  factory ItemDetection.fromJson(Map<String, dynamic> json) {
    return ItemDetection(
      id: (json['id'] as String?) ?? 'det_unknown',
      label: (json['label'] as String?) ?? 'Unknown',
      category: (json['category'] as String?) ?? 'neutral',
      bbox: BBox2D.fromJson((json['bbox'] as Map?)?.cast<String, dynamic>() ?? const {}),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      sourceFrame: (json['sourceFrame'] as num?)?.toInt() ?? 0,
    );
  }
}
