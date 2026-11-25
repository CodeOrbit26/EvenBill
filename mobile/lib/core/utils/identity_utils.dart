import '../di/injection.dart';
import '../models/user_model.dart';
import '../network/api_client.dart';

/// Matches standard dashed 36-character RFC-4122 UUIDs.
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

const Set<String> _placeholderUserIds = <String>{
  'current_user',
  'usr_me',
  'usr_current',
  'friend_1',
  'member_2',
  'guest',
  'demo_user',
};

/// Returns true if [value] is a well-formed 36-character UUID string.
bool isValidUuid(String? value) {
  if (value == null) return false;
  return _uuidPattern.hasMatch(value.trim());
}

/// Returns true if [value] is null, blank, or a known client placeholder ID.
bool isPlaceholderUserId(String? value) {
  if (value == null) return true;
  final clean = value.trim();
  if (clean.isEmpty) return true;
  return _placeholderUserIds.contains(clean.toLowerCase());
}

/// Throws an [ApiException] (HTTP 422) if [userId] is a placeholder or non-UUID.
void ensureValidBackendUuid(String? userId, {String fieldName = 'user_id'}) {
  if (isPlaceholderUserId(userId) || !isValidUuid(userId)) {
    throw ApiException(
      'Invalid UUID for $fieldName: "${userId ?? ''}". Expected authenticated user UUID.',
      statusCode: 422,
    );
  }
}

/// Resolves the canonical authenticated user from secure cache or `/auth/me`,
/// refreshing stale cache if its ID is missing or a legacy placeholder.
Future<UserModel?> resolveAuthenticatedUser({bool forceRefresh = false}) async {
  UserModel? cached;
  try {
    cached = await Injection.tokenStorage.getCachedUser();
  } catch (_) {}

  if (!forceRefresh && cached != null && !isPlaceholderUserId(cached.id)) {
    return cached;
  }

  try {
    final fresh = await Injection.authRepository.getMe();
    if (!isPlaceholderUserId(fresh.id)) {
      return fresh;
    }
  } catch (_) {}

  return (cached != null && !isPlaceholderUserId(cached.id)) ? cached : null;
}
