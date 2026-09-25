import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_providers.dart';
import 'package:expense_tracker/providers/settings_providers.dart';
import 'package:expense_tracker/services/receipt_scanner.dart';
import 'package:expense_tracker/services/receipt_text_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final receiptScannerProvider = Provider<ReceiptScanner>((ref) => MlKitReceiptScanner());

// Whether "03/04" on a receipt means 3 April. Only the US (and the Philippines) write the
// month first, so follow the device's region
final receiptDatesDayFirstProvider = Provider<bool>((ref) {
  if (kIsWeb) return true;
  final parts = Platform.localeName.replaceAll("-", "_").split("_");
  final country = parts.length > 1 ? parts[1].toUpperCase() : "";
  return !const {"US", "PH"}.contains(country);
});

// Whether receipts can be read on this device with the chosen mode
final canScanHereProvider = Provider<bool>((ref) {
  // NOTE: Check the scanner first, so devices that can't scan never need the settings
  if (!ref.watch(receiptScannerProvider).isAvailable) return false;
  return ref.watch(receiptScanModeProvider) == ReceiptScanMode.onDevice;
});

class ReceiptScanService
{
  final Ref _ref;

  ReceiptScanService(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);

  // Reads the receipt's photo and fills in whatever the user hasn't typed themselves.
  // Returns the receipt as saved (scanned, or failed if nothing could be read)
  Future<Receipt> scan(Receipt receipt) async
  {
    final userId = _ref.requireUserId();
    final file = await _ref.read(receiptImageStoreProvider).fileFor(receipt.id);

    ParsedReceipt parsed;
    try
    {
      final rows = await _ref.read(receiptScannerProvider).readRows(file);
      parsed = ReceiptTextParser(dayFirst: _ref.read(receiptDatesDayFirstProvider)).parse(rows);
    }
    catch (e)
    {
      print("❌ Couldn't scan receipt ${receipt.id}: $e");
      parsed = const ParsedReceipt();
    }

    // NOTE: Scanning takes a moment, so start from the receipt as it is NOW. If the user
    // edited it (or deleted it) meanwhile, their changes win
    final latest = await _db.receiptsDao.getReceiptById(receipt.id, userId);
    if (latest == null || latest.isDeleted) return receipt;

    final actions = _ref.read(receiptActionsProvider);
    if (parsed.isEmpty) return actions.update(latest.copyWith(scanStatus: ReceiptScanStatus.failed));

    final merchant = latest.merchant ?? parsed.merchant;
    final categoryId = latest.categoryId
      ?? (merchant == null ? null : await _db.receiptsDao.categoryUsedBefore(merchant, userId));

    return actions.update(latest.copyWith(
      merchant: Value(merchant),
      total: Value(latest.total ?? parsed.total),
      date: Value(latest.date ?? parsed.date),
      categoryId: Value(categoryId),
      scanStatus: ReceiptScanStatus.scanned,
    ));
  }

  // Scans every receipt that's waiting, if this device can. Receipts imported on Windows
  // get read here once the phone has synced and downloaded their photos
  Future<int> scanWaiting() async
  {
    if (!_ref.read(canScanHereProvider)) return 0;

    final userId = _ref.requireUserId();
    final images = _ref.read(receiptImageStoreProvider);
    var scanned = 0;

    for (final receipt in await _db.receiptsDao.getWaitingToScan(userId))
    {
      // Photo not downloaded yet, the next sync will bring it
      if (!await images.exists(receipt.id)) continue;
      await scan(receipt);
      scanned++;
    }
    return scanned;
  }
}

final receiptScanServiceProvider = Provider<ReceiptScanService>((ref) => ReceiptScanService(ref));
