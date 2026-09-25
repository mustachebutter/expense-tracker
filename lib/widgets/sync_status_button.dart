import 'package:expense_tracker/providers/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// Cloud icon for the app bar: shows whether everything is synced, and tapping it syncs now
class SyncStatusButton extends ConsumerWidget
{
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    final isOnline = ref.watch(isOnlineProvider);

    final String waiting = pending == 1 ? "1 change waiting to sync" : "$pending changes waiting to sync";
    final String lastSynced = sync.lastSyncedAt == null
      ? ""
      : " · last synced ${DateFormat.jm().format(sync.lastSyncedAt!)}";

    final (IconData icon, String tooltip) = switch (sync.status) {
      SyncStatus.syncing => (Icons.cloud_sync, "Syncing..."),
      _ when !isOnline || sync.status == SyncStatus.offline => (Icons.cloud_off, "Offline · $waiting"),
      SyncStatus.error => (Icons.sync_problem, "Sync failed, tap to retry\n${sync.errorMessage}"),
      _ when pending > 0 => (Icons.cloud_upload, waiting),
      _ => (Icons.cloud_done, "All changes synced$lastSynced"),
    };

    return IconButton(
      tooltip: tooltip,
      onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
      icon: Badge(
        isLabelVisible: pending > 0,
        label: Text("$pending"),
        child: Icon(icon),
      ),
    );
  }
}
