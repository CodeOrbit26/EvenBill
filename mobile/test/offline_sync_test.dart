import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/core/sync/sync_queue.dart';
import 'package:evenbill/core/sync/sync_engine.dart';
import 'package:evenbill/core/widgets/sync_status_indicator.dart';

void main() {
  group('Offline Mode & Durable Sync Queue Tests', () {
    late DurableSyncQueue queue;

    setUp(() {
      queue = DurableSyncQueue();
    });

    test('Enqueue generates unique operationId and idempotencyKey', () {
      final op1 = SyncOperation(
        type: SyncOperationType.createExpense,
        payload: {'description': 'Coffee', 'amount': 4.50},
      );
      final op2 = SyncOperation(
        type: SyncOperationType.createExpense,
        payload: {'description': 'Tea', 'amount': 3.00},
      );

      queue.enqueue(op1);
      queue.enqueue(op2);

      expect(op1.operationId, isNotEmpty);
      expect(op2.operationId, isNotEmpty);
      expect(op1.operationId, isNot(equals(op2.operationId)));
      expect(op1.idempotencyKey, isNot(equals(op2.idempotencyKey)));
      expect(queue.pendingCount, equals(2));
      expect(op1.isPending, isTrue);
      expect(op1.isSynchronized, isFalse);
    });

    test('Queue persists and restores correctly via serialization', () {
      final op = SyncOperation(
        type: SyncOperationType.updateExpense,
        targetEntityId: 'exp_123',
        expectedVersion: 2,
        payload: {'description': 'Updated Dinner'},
      );
      queue.enqueue(op);

      final serialized = queue.serialize();
      expect(serialized, contains('exp_123'));
      expect(serialized, contains('updateExpense'));

      final restoredQueue = DurableSyncQueue();
      restoredQueue.deserialize(serialized);

      expect(restoredQueue.pendingCount, equals(1));
      final restoredOp = restoredQueue.pendingOperations.first;
      expect(restoredOp.targetEntityId, equals('exp_123'));
      expect(restoredOp.expectedVersion, equals(2));
      expect(restoredOp.type, equals(SyncOperationType.updateExpense));
    });

    test('Offline writes are not promised as synced until server confirms', () async {
      bool serverConfirmed = false;

      final engine = SyncEngine(
        queue: queue,
        executor: (op) async {
          if (!serverConfirmed) {
            throw Exception('Network unreachable');
          }
          return {'id': 'exp_999', 'status': 'confirmed'};
        },
      );

      final op = SyncOperation(
        type: SyncOperationType.createExpense,
        payload: {'description': 'Lunch', 'amount': 15.00},
      );
      queue.enqueue(op);

      // Attempt sync while offline -> fails, stays pending
      await engine.processQueue();
      expect(op.isSynchronized, isFalse);
      expect(op.retryCount, equals(1));
      expect(op.status, equals(SyncOperationStatus.pending));

      // Network restored -> server confirms
      serverConfirmed = true;
      await engine.processQueue();
      expect(op.isSynchronized, isTrue);
      expect(op.status, equals(SyncOperationStatus.synced));
      expect(queue.pendingCount, equals(0));
    });

    test('Conflicting edits are flagged explicitly rather than silently overwriting', () async {
      int attempt = 0;
      final engine = SyncEngine(
        queue: queue,
        executor: (op) async {
          attempt++;
          if (attempt == 1) {
            // First attempt: Server returns HTTP 409 Conflict
            throw SyncConflictException(
              serverVersion: 3,
              message: 'Conflict: Server has version 3, but client submitted version 1.',
            );
          }
          // Second attempt succeeds
          return {'id': op.targetEntityId ?? 'exp_555', 'version': 3};
        },
      );

      final op = SyncOperation(
        type: SyncOperationType.updateExpense,
        targetEntityId: 'exp_555',
        expectedVersion: 1,
        payload: {'description': 'My offline edit'},
      );
      queue.enqueue(op);

      await engine.processQueue();

      expect(op.status, equals(SyncOperationStatus.conflict));
      expect(op.hasConflict, isTrue);
      expect(op.serverVersion, equals(3));
      expect(queue.conflictOperations.length, equals(1));

      // Resolve conflict: user chooses to re-base on server version
      await engine.resolveConflict(
        operationId: op.operationId,
        acceptServerVersion: false,
        resolvedPayload: {'description': 'Reconciled Edit with Server'},
      );

      // Original conflicting op removed, new op queued with expectedVersion 3
      expect(queue.conflictOperations.isEmpty, isTrue);
    });

    test('Offline actions cannot bypass server plan limits', () async {
      final engine = SyncEngine(
        queue: queue,
        executor: (op) async {
          // Server enforces plan limit
          throw PlanLimitSyncException('Free tier limit of 4 daily expenses reached. Upgrade to Pro.');
        },
      );

      final op = SyncOperation(
        type: SyncOperationType.createExpense,
        payload: {'description': '5th expense of the day'},
      );
      queue.enqueue(op);

      await engine.processQueue();

      expect(op.status, equals(SyncOperationStatus.rejectedPlanLimit));
      expect(op.lastError, contains('Free tier limit'));
      expect(op.isSynchronized, isFalse);
    });

    testWidgets('SyncStatusIndicator displays synced, offline, and conflict states', (tester) async {
      final engine = SyncEngine(
        queue: queue,
        executor: (op) async => {},
      );

      // State 1: All synced
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SyncStatusIndicator(syncEngine: engine)),
      ));
      expect(find.text('All synced'), findsOneWidget);

      // State 2: 1 queued offline
      queue.enqueue(SyncOperation(
        type: SyncOperationType.createExpense,
        payload: {'description': 'Taxi'},
      ));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SyncStatusIndicator(syncEngine: engine)),
      ));
      expect(find.text('Offline: 1 queued'), findsOneWidget);

      // State 3: Conflict detected
      queue.markConflict(
        queue.pendingOperations.first.operationId,
        serverVersion: 2,
        detail: 'Version conflict',
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SyncStatusIndicator(syncEngine: engine)),
      ));
      expect(find.text('Conflict detected (tap to resolve)'), findsOneWidget);
    });
  });
}
