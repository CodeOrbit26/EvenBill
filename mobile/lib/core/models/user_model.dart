class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? phoneNumber;
  final String? avatarUrl;
  final String defaultCurrency;
  final bool isPro;
  final bool isActive;
  final bool isVerified;
  final bool hasPassword;
  final DateTime? createdAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.phoneNumber,
    this.avatarUrl,
    this.defaultCurrency = 'USD',
    this.isPro = false,
    this.isActive = true,
    this.isVerified = false,
    this.hasPassword = false,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String? ?? 'User',
      phoneNumber: json['phone_number'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      defaultCurrency: json['default_currency'] as String? ?? 'USD',
      isPro: json['is_pro'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isVerified: json['is_verified'] as bool? ?? false,
      hasPassword: json['has_password'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'avatar_url': avatarUrl,
      'default_currency': defaultCurrency,
      'is_pro': isPro,
      'is_active': isActive,
      'is_verified': isVerified,
      'has_password': hasPassword,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? fullName,
    String? phoneNumber,
    String? avatarUrl,
    String? defaultCurrency,
    bool? isPro,
    bool? isActive,
    bool? isVerified,
    bool? hasPassword,
    DateTime? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      defaultCurrency: defaultCurrency ?? this.defaultCurrency,
      isPro: isPro ?? this.isPro,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      hasPassword: hasPassword ?? this.hasPassword,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
