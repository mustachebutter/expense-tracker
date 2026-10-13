import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show TableInfo, Variable;
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_scan_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// NOTE: This only knows if the device has a network connection (wifi, mobile, ethernet),
// not whether Supabase is actually reachable. A sync can still fail while "online",
// which is fine: the rows stay unsynced and go up next time
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  bool isConnected(List<ConnectivityResult> results) => !results.contains(ConnectivityResult.none);

  // onConnectivityChanged doesn't emit the current state on every platform, so ask first
  yield isConnected(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isConnected).distinct();
});

// Assume online until we know otherwise, a failed sync attempt costs nothing
final isOnlineProvider = Provider<bool>((ref) => ref.watch(connectivityProvider).value ?? true);

// How many local rows are waiting to be uploaded, across every synced table
final pendingChangesProvider = StreamProvider<int>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(0);

  final db = ref.watch(databaseProvider);
  final tables = <TableInfo>[db.categories, db.templates, db.transactions, db.savingsGoals, db.investments];
  final counts = tables
    .map((t) => "(SELECT COUNT(*) FROM ${t.actualTableName} WHERE user_id = ?1 AND is_synced = 0)")
    .join(" + ");

  // NOTE: readsFrom tells Drift which tables this raw SQL depends on, so the stream
  // re-emits whenever any of them changes, just like the generated .watch() queries
  return db.customSelect(
    "SELECT $counts AS pending",
    variables: [Variable<String>(userId)],
    readsFrom: tables.toSet(),
  ).watchSingle().map((row) => row.read<int>("pending"));
});

enum SyncStatus { idle, syncing, offline, error }

class SyncState
{
  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? errorMessage;

  const SyncState({this.status = SyncStatus.idle, this.lastSyncedAt, this.errorMessage});

  SyncState copyWith({SyncStatus? status, DateTime? lastSyncedAt, String? errorMessage})
  {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: errorMessage,
    );
  }
}

// The one place that decides WHEN to sync. The SyncEngine does the actual work
class SyncController extends Notifier<SyncState>
{
  static const Duration debounceDelay = Duration(seconds: 3);

  Timer? _debounce;
  Future<void>? _running;
  bool _syncAgain = false;

  @override
  SyncState build()
  {
    ref.onDispose(() => _debounce?.cancel());
    return const SyncState();
  }

  // Sync a few seconds from now. Calling it again restarts the countdown, so a burst
  // of edits (e.g. adding 5 transactions quickly) becomes a single sync
  void scheduleSync({Duration delay = debounceDelay})
  {
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  // Sync right away. If a sync is already running, one more runs after it finishes
  // instead of two running at the same time
  Future<void> syncNow() async
  {
    _debounce?.cancel();

    if (_running != null)
    {
      _syncAgain = true;
      return _running;
    }

    _running = _run();
    try
    {
      await _running;
    }
    finally
    {
      _running = null;
    }

    if (_syncAgain && ref.mounted)
    {
      _syncAgain = false;
      await syncNow();
    }
  }

  // Reads receipts that are waiting, if this device can. Never fails the sync
  Future<void> _scanWaitingReceipts() async
  {
    try
    {
      await ref.read(receiptScanServiceProvider).scanWaiting();
    }
    catch (e)
    {
      print("❌ Scanning waiting receipts failed: $e");
    }
  }

  Future<void> _run() async
  {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    // NOTE: Scanning is local, so it happens even offline. The scanned fields go up with
    // this sync, or the next one
    await _scanWaitingReceipts();
    if (!ref.mounted) return;

    if (!ref.read(isOnlineProvider))
    {
      state = state.copyWith(status: SyncStatus.offline);
      return;
    }

    state = state.copyWith(status: SyncStatus.syncing);
    try
    {
      await ref.read(syncEngineProvider).runSync(userId);
      if (!ref.mounted) return;
      state = state.copyWith(status: SyncStatus.idle, lastSyncedAt: DateTime.now());

      // Photos imported on another device (e.g. Windows) may have just arrived
      await _scanWaitingReceipts();
    }
    catch (e)
    {
      if (!ref.mounted) return;
      state = state.copyWith(status: SyncStatus.error, errorMessage: e.toString());
    }
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
