import 'dart:async';

import 'package:expense_tracker/providers/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Wrap the signed in part of the app with this. It kicks off a sync when:
// - it first appears (app start / sign in)
// - the network comes back
// - the app comes back to the foreground
// - local data changes (debounced, so a burst of edits is one sync)
// - every few minutes, to pick up changes made on other devices
class SyncTriggers extends ConsumerStatefulWidget
{
  static const Duration periodicInterval = Duration(minutes: 5);

  final Widget child;

  const SyncTriggers({super.key, required this.child});

  @override
  ConsumerState<SyncTriggers> createState() => _SyncTriggersState();
}

class _SyncTriggersState extends ConsumerState<SyncTriggers>
{
  late final AppLifecycleListener _lifecycleListener;
  Timer? _periodicTimer;

  SyncController get _sync => ref.read(syncControllerProvider.notifier);

  @override
  void initState() {
    super.initState();

    _lifecycleListener = AppLifecycleListener(onResume: () => _sync.syncNow());
    _periodicTimer = Timer.periodic(SyncTriggers.periodicInterval, (_) => _sync.syncNow());

    // NOTE: Providers can't be changed while widgets are building, so wait one frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync.syncNow();
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _periodicTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: ref.listen runs a callback when a provider changes, without rebuilding this widget
    ref.listen<bool>(isOnlineProvider, (wasOnline, isOnline) {
      if (wasOnline == false && isOnline) _sync.syncNow();
    });

    ref.listen<AsyncValue<int>>(pendingChangesProvider, (previous, next) {
      // Only react to the count going UP after we already knew it, i.e. a real local edit.
      // Going down means a sync just uploaded rows, and that shouldn't start another one
      if (previous == null || !previous.hasValue || !next.hasValue) return;
      if (next.value! > previous.value!) _sync.scheduleSync();
    });

    return widget.child;
  }
}
