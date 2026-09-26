import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: Per-device preferences (not synced): the scan mode can differ between your phone
// and your PC. Loaded once in main() before the app starts, so reading it is synchronous
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError("Override sharedPreferencesProvider with SharedPreferences.getInstance() in main()");
});

enum ReceiptScanMode
{
  // Google ML Kit, on the phone itself. Free and offline, but only on Android and iOS
  onDevice,
  // An open model on your own server or PC (Ollama). Comes in the next update
  selfHosted,
}

class ReceiptScanModeNotifier extends Notifier<ReceiptScanMode>
{
  static const String _key = "receipt_scan_mode";

  @override
  ReceiptScanMode build()
  {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return ReceiptScanMode.values.firstWhere((mode) => mode.name == saved, orElse: () => ReceiptScanMode.onDevice);
  }

  Future<void> select(ReceiptScanMode mode) async
  {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

final receiptScanModeProvider = NotifierProvider<ReceiptScanModeNotifier, ReceiptScanMode>(ReceiptScanModeNotifier.new);
