class GroupInvitationModel {
  final String id;
  final String groupId;
  final String email;
  final String invitedBy;
  final String? inviterName;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;

  const GroupInvitationModel({
    required this.id,
    required this.groupId,
    required this.email,
    required this.invitedBy,
    this.inviterName,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  factory GroupInvitationModel.fromJson(Map<String, dynamic> json) {
    return GroupInvitationModel(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      email: json['email'] as String,
      invitedBy: json['invited_by'] as String,
      inviterName: json['inviter_name'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  bool get isPending => status == 'PENDING' && expiresAt.isAfter(DateTime.now());
  bool get isExpired => status == 'EXPIRED' || (status == 'PENDING' && expiresAt.isBefore(DateTime.now()));
  bool get isAccepted => status == 'ACCEPTED';
  bool get isRevoked => status == 'REVOKED';

  GroupInvitationModel copyWith({
    String? id,
    String? groupId,
    String? email,
    String? invitedBy,
    String? inviterName,
    String? status,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return GroupInvitationModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      email: email ?? this.email,
      invitedBy: invitedBy ?? this.invitedBy,
      inviterName: inviterName ?? this.inviterName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

