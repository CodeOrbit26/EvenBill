class FriendModel {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final double netBalance;
  final String currency;
  final String status;

  const FriendModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.netBalance,
    this.currency = 'USD',
    this.status = 'SETTLED',
  });

  factory FriendModel.fromJson(Map<String, dynamic> json) {
    return FriendModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Friend',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      netBalance: double.tryParse(json['net_balance']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      status: json['status'] as String? ?? 'SETTLED',
    );
  }

  bool get isSettled => netBalance.abs() < 0.0001;
  bool get youAreOwed => netBalance > 0.0001;
  bool get youOwe => netBalance < -0.0001;
}
