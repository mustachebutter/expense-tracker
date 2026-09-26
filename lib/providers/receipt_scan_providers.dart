import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:expense_tracker/database.dart';
import 'package:expense_tracker/providers/core_providers.dart';
import 'package:expense_tracker/providers/receipt_crop_providers.dart';
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

  // How much of the receipt a reading found. The total matters most
  static int _score(ParsedReceipt parsed)
  {
    return (parsed.total != null ? 2 : 0) + (parsed.merchant != null ? 1 : 0) + (parsed.date != null ? 1 : 0);
  }

  // A shop and a total is enough to stop looking
  static const int _goodEnough = 3;

  Future<ParsedReceipt> _read(File file, int quarterTurns) async
  {
    try
    {
      final rows = await _ref.read(receiptScannerProvider).readRows(file, quarterTurns: quarterTurns);
      return ReceiptTextParser(dayFirst: _ref.read(receiptDatesDayFirstProvider)).parse(rows);
    }
    catch (e)
    {
      print("❌ Couldn't read the receipt photo (turned $quarterTurns): $e");
      return const ParsedReceipt();
    }
  }

  // Reads the photo the way it's shown. If that finds no total, the photo is probably
  // sideways or upside down, so try the other three ways round and keep the best reading
  Future<({ParsedReceipt parsed, int quarterTurns})> _readBestWayUp(File file, int shownTurns) async
  {
    var best = (parsed: await _read(file, shownTurns), quarterTurns: shownTurns);

    // NOTE: Sideways (1 and 3 turns) is far more common than upside down, so try those first
    for (final extraTurns in const [1, 3, 2])
    {
      if (_score(best.parsed) >= _goodEnough) break;

      final turns = (shownTurns + extraTurns) % 4;
      final parsed = await _read(file, turns);
      if (_score(parsed) > _score(best.parsed)) best = (parsed: parsed, quarterTurns: turns);
    }
    return best;
  }

  // Reads the receipt's photo and fills in whatever the user hasn't typed themselves, or
  // with [replaceExisting] (the user asked to scan again), replaces what was there.
  // Also turns the photo upright if it had to be turned to be read.
  // Returns the receipt as saved (scanned, or failed if nothing could be read)
  Future<Receipt> scan(Receipt receipt, {bool replaceExisting = false}) async
  {
    final userId = _ref.requireUserId();
    final store = _ref.read(receiptImageStoreProvider);

    // NOTE: A cropped receipt is read from its cropped copy (already upright, no background),
    // and isn't tried other ways round: the crop already says which way up it goes
    final cropped = receipt.cropCorners == null ? null : await croppedReceiptFile(
      store,
      _ref.read(receiptCropperProvider),
      receiptId: receipt.id,
      quarterTurns: receipt.imageQuarterTurns,
      cropCorners: receipt.cropCorners!,
    );
    final reading = cropped != null
      ? (parsed: await _read(cropped, 0), quarterTurns: receipt.imageQuarterTurns)
      : await _readBestWayUp(await store.fileFor(receipt.id), receipt.imageQuarterTurns);
    final parsed = reading.parsed;

    // NOTE: Scanning takes a moment, so start from the receipt as it is NOW. If the user
    // edited it (or deleted it) meanwhile, their changes win
    final latest = await _db.receiptsDao.getReceiptById(receipt.id, userId);
    if (latest == null || latest.isDeleted) return receipt;

    final actions = _ref.read(receiptActionsProvider);
    if (parsed.isEmpty) return actions.update(latest.copyWith(scanStatus: ReceiptScanStatus.failed));

    // Keep what's there, unless the user asked for a fresh reading (then keep it only where
    // the new reading found nothing)
    T? pick<T>(T? existing, T? found) => replaceExisting ? (found ?? existing) : (existing ?? found);

    final merchant = pick(latest.merchant, parsed.merchant);
    final categoryId = latest.categoryId
      ?? (merchant == null ? null : await _db.receiptsDao.categoryUsedBefore(merchant, userId));

    // Same idea for the location: a shop you've been to before is probably in the same place.
    // Only when the receipt has no location yet, so a typed one is never replaced
    final hasLocation = latest.city != null || latest.state != null || latest.country != null;
    final sameShop = (hasLocation || merchant == null)
      ? null
      : await _db.receiptsDao.locationUsedBefore(merchant, userId, exceptId: latest.id);

    return actions.update(latest.copyWith(
      merchant: Value(merchant),
      total: Value(pick(latest.total, parsed.total)),
      date: Value(pick(latest.date, parsed.date)),
      categoryId: Value(categoryId),
      city: Value(latest.city ?? sameShop?.city),
      state: Value(latest.state ?? sameShop?.state),
      country: Value(latest.country ?? sameShop?.country),
      // NOTE: Saved as a pair: the crop corners only make sense with the rotation they were
      // drawn on, so keep the two that were actually read together
      imageQuarterTurns: reading.quarterTurns,
      cropCorners: Value(receipt.cropCorners),
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
