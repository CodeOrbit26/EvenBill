class SplitAllocationItem {
  final String userId;
  final double value;

  const SplitAllocationItem({
    required this.userId,
    required this.value,
  });

  factory SplitAllocationItem.fromJson(Map<String, dynamic> json) {
    return SplitAllocationItem(
      userId: json['user_id'] as String? ?? '',
      value: double.tryParse(json['value']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'value': value,
  };
}

class SplitTemplateModel {
  final String id;
  final String groupId;
  final String name;
  final String splitType;
  final List<SplitAllocationItem> allocations;
  final bool isDefault;
  final String createdBy;
  final DateTime createdAt;

  const SplitTemplateModel({
    required this.id,
    required this.groupId,
    required this.name,
    required this.splitType,
    required this.allocations,
    required this.isDefault,
    required this.createdBy,
    required this.createdAt,
  });

  factory SplitTemplateModel.fromJson(Map<String, dynamic> json) {
    final rawAllocations = (json['allocations'] as List<dynamic>? ?? [])
        .map((a) => SplitAllocationItem.fromJson(a as Map<String, dynamic>))
        .toList();

    return SplitTemplateModel(
      id: json['id'] as String? ?? '',
      groupId: json['group_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      splitType: json['split_type'] as String? ?? 'EQUAL',
      allocations: rawAllocations,
      isDefault: json['is_default'] as bool? ?? false,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'split_type': splitType,
    'allocations': allocations.map((a) => a.toJson()).toList(),
    'is_default': isDefault,
  };
}
