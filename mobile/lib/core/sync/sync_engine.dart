import 'dart:async';
import 'dart:math';
import 'package:evenbill/core/sync/sync_queue.dart';

typedef SyncExecutor = Future<Map<String, dynamic>> Function(SyncOperation operation);

class SyncConflictException implements Exception {
  final int serverVersion;
  final String message;
  SyncConflictException({required this.serverVersion, required this.message});

  @override
  String toString() => 'SyncConflictException(serverVersion: $serverVersion, message: $message)';
}

class PlanLimitSyncException implements Exception {
  final String message;
  PlanLimitSyncException(this.message);

  @override
  String toString() => 'PlanLimitSyncException($message)';
}

class SyncEngine {
  final DurableSyncQueue queue;
  final SyncExecutor executor;

  final _syncStateController = StreamController<bool>.broadcast();
  final _pendingCountController = StreamController<int>.broadcast();
  final _conflictController = StreamController<SyncOperation>.broadcast();

  bool _isProcessing = false;

  SyncEngine({
    required this.queue,
    required this.executor,
  });

  Stream<bool> get isSyncingStream => _syncStateController.stream;
  Stream<int> get pendingCountStream => _pendingCountController.stream;
  Stream<SyncOperation> get conflictStream => _conflictController.stream;

  bool get isProcessing => _isProcessing;

  void dispose() {
    _syncStateController.close();
    _pendingCountController.close();
    _conflictController.close();
  }

  Future<void> enqueueAndTrigger(SyncOperation operation) async {
    queue.enqueue(operation);
    _pendingCountController.add(queue.pendingCount);
    await processQueue();
  }

  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    _syncStateController.add(true);

    try {
      final operations = queue.pendingOperations;
      for (final op in operations) {
        queue.markSyncing(op.operationId);

        try {
          // Bounded retry backoff delay with jitter if retryCount > 0
          if (op.retryCount > 0) {
            final backoffMs = min(1000 * pow(2, op.retryCount - 1).toInt(), 10000);
            final jitter = Random().nextInt(200);
            await Future.delayed(Duration(milliseconds: backoffMs + jitter));
          }

          await executor(op);
          queue.markSuccess(op.operationId);
        } on SyncConflictException catch (conflict) {
          // Explicit 409 Conflict handling: NEVER silently overwrite
          queue.markConflict(
            op.operationId,
            serverVersion: conflict.serverVersion,
            detail: conflict.message,
          );
          _conflictController.add(op);
        } on PlanLimitSyncException catch (limitExc) {
          // Server rejected operation due to plan tier limit (cannot bypass offline)
          queue.markPlanLimitRejected(
            op.operationId,
            detail: limitExc.message,
          );
        } catch (err) {
          queue.markFailed(op.operationId, err.toString());
        }
      }
    } finally {
      _isProcessing = false;
      _syncStateController.add(false);
      _pendingCountController.add(queue.pendingCount);
    }
  }

  /// Manually reconciles a conflicted operation by taking user's explicit choice
  Future<void> resolveConflict({
    required String operationId,
    required bool acceptServerVersion,
    Map<String, dynamic>? resolvedPayload,
  }) async {
    final op = queue.allOperations.firstWhere((o) => o.operationId == operationId);
    if (acceptServerVersion) {
      // Discard client edit and adopt server's version
      queue.remove(operationId);
    } else {
      // Re-queue with the incremented server version as expected version
      final updatedOp = SyncOperation(
        type: op.type,
        targetEntityId: op.targetEntityId,
        payload: resolvedPayload ?? op.payload,
        expectedVersion: op.serverVersion,
      );
      queue.remove(operationId);
      await enqueueAndTrigger(updatedOp);
    }
    _pendingCountController.add(queue.pendingCount);
  }
}
