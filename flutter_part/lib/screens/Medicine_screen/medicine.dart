enum MedicineType { tablet, syrup }

class Medicine {
  String name;
  MedicineType type;
  DateTime expiryDate;
  String tags;

  Medicine({
    required this.name,
    required this.type,
    required this.expiryDate,
    this.tags = '',
  });

  bool get isExpired {
    return DateTime.now().isAfter(expiryDate);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'expiryDate': expiryDate.toIso8601String(),
      'tags': tags,
    };
  }

  factory Medicine.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String? ?? 'tablet').toLowerCase();
    final type = rawType == 'syrup' ? MedicineType.syrup : MedicineType.tablet;

    return Medicine(
      name: json['name'] as String? ?? '',
      type: type,
      expiryDate:
          DateTime.tryParse(json['expiryDate'] as String? ?? '') ??
          DateTime.now(),
      tags: json['tags'] as String? ?? '',
    );
  }
}
