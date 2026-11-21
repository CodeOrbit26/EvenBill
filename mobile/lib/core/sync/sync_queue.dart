import 'dart:convert';
import 'package:uuid/uuid.dart';

enum SyncOperationStatus {
  pending,
  syncing,
  synced,
  conflict,
  rejectedPlanLimit,
  failed,
}

enum SyncOperationType {
  createExpense,
  updateExpense,
  deleteExpense,
  createSettlement,
}

class SyncOperation {
  final String operationId;
  final String idempotencyKey;
  final SyncOperationType type;
  final String? targetEntityId;
  final Map<String, dynamic> payload;
  final int? expectedVersion;
  final DateTime createdAt;
  SyncOperationStatus status;
  int retryCount;
  String? lastError;
  int? serverVersion;

  SyncOperation({
    String? operationId,
    String? idempotencyKey,
    required this.type,
    this.targetEntityId,
    required this.payload,
    this.expectedVersion,
    DateTime? createdAt,
    this.status = SyncOperationStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.serverVersion,
  })  : operationId = operationId ?? const Uuid().v4(),
        idempotencyKey = idempotencyKey ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().toUtc();

  bool get isSynchronized => status == SyncOperationStatus.synced;
  bool get isPending => status == SyncOperationStatus.pending || status == SyncOperationStatus.syncing;
  bool get hasConflict => status == SyncOperationStatus.conflict;

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'idempotencyKey': idempotencyKey,
        'type': type.name,
        'targetEntityId': targetEntityId,
        'payload': payload,
        'expectedVersion': expectedVersion,
        'status': status.name,
        'retryCount': retryCount,
        'lastError': lastError,
        'serverVersion': serverVersion,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        operationId: json['operationId'] as String,
        idempotencyKey: json['idempotencyKey'] as String,
        type: SyncOperationType.values.byName(json['type'] as String),
        targetEntityId: json['targetEntityId'] as String?,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        expectedVersion: json['expectedVersion'] as int?,
        status: SyncOperationStatus.values.byName(json['status'] as String),
        retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
        lastError: json['lastError'] as String?,
        serverVersion: (json['serverVersion'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class DurableSyncQueue {
  final List<SyncOperation> _queue = [];
  static const int maxRetries = 5;

  List<SyncOperation> get allOperations => List.unmodifiable(_queue);
  List<SyncOperation> get pendingOperations => _queue.where((op) => op.isPending).toList();
  List<SyncOperation> get conflictOperations => _queue.where((op) => op.hasConflict).toList();
  int get pendingCount => pendingOperations.length;

  void enqueue(SyncOperation operation) {
    _queue.add(operation);
  }

  void markSyncing(String operationId) {
    final op = _getOp(operationId);
    if (op != null) {
      op.status = SyncOperationStatus.syncing;
    }
  }

  void markSuccess(String operationId) {
    final op = _getOp(operationId);
    if (op != null) {
      op.status = SyncOperationStatus.synced;
      op.lastError = null;
    }
  }

  void markConflict(String operationId, {required int serverVersion, required String detail}) {
    final op = _getOp(operationId);
    if (op != null) {
      op.status = SyncOperationStatus.conflict;
      op.serverVersion = serverVersion;
      op.lastError = detail;
    }
  }

  void markPlanLimitRejected(String operationId, {required String detail}) {
    final op = _getOp(operationId);
    if (op != null) {
      op.status = SyncOperationStatus.rejectedPlanLimit;
      op.lastError = detail;
    }
  }

  void markFailed(String operationId, String error) {
    final op = _getOp(operationId);
    if (op != null) {
      op.retryCount += 1;
      op.lastError = error;
      if (op.retryCount >= maxRetries) {
        op.status = SyncOperationStatus.failed;
      } else {
        op.status = SyncOperationStatus.pending;
      }
    }
  }

  void remove(String operationId) {
    _queue.removeWhere((op) => op.operationId == operationId);
  }

  void clear() {
    _queue.clear();
  }

  SyncOperation? _getOp(String id) {
    try {
      return _queue.firstWhere((op) => op.operationId == id);
    } catch (_) {
      return null;
    }
  }

  String serialize() => jsonEncode(_queue.map((op) => op.toJson()).toList());

  void deserialize(String serializedJson) {
    _queue.clear();
    final List<dynamic> list = jsonDecode(serializedJson);
    for (final item in list) {
      _queue.add(SyncOperation.fromJson(Map<String, dynamic>.from(item)));
    }
  }
}
