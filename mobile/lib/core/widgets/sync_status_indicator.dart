import 'package:flutter/material.dart';
import 'package:evenbill/core/sync/sync_engine.dart';

class SyncStatusIndicator extends StatelessWidget {
  final SyncEngine syncEngine;
  final VoidCallback? onConflictTap;

  const SyncStatusIndicator({
    super.key,
    required this.syncEngine,
    this.onConflictTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: syncEngine.isSyncingStream,
      initialData: syncEngine.isProcessing,
      builder: (context, syncingSnapshot) {
        final isSyncing = syncingSnapshot.data ?? false;

        return StreamBuilder<int>(
          stream: syncEngine.pendingCountStream,
          initialData: syncEngine.queue.pendingCount,
          builder: (context, pendingSnapshot) {
            final pendingCount = syncEngine.queue.pendingCount;
            final hasConflicts = syncEngine.queue.conflictOperations.isNotEmpty;

            if (hasConflicts) {
              return InkWell(
                onTap: onConflictTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Conflict detected (tap to resolve)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade900),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (isSyncing) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Syncing $pendingCount change${pendingCount > 1 ? 's' : ''}...',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.blue.shade900),
                    ),
                  ],
                ),
              );
            }

            if (pendingCount > 0) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_queue, size: 16, color: Colors.amber.shade800),
                    const SizedBox(width: 6),
                    Text(
                      'Offline: $pendingCount queued',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.amber.shade900),
                    ),
                  ],
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF16A34A)),
                  SizedBox(width: 6),
                  Text(
                    'All synced',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF166534)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
