import 'package:expense_tracker/services/place_finder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// NOTE: Stands in for the phone's location plugin. Each test sets what it answers
class _FakeLocationPlugin extends GeolocatorPlatform with MockPlatformInterfaceMixin
{
  Object? failWith;
  bool locationOn = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterAsking = LocationPermission.whileInUse;
  var asked = 0;

  @override
  Future<bool> isLocationServiceEnabled() async
  {
    if (failWith != null) throw failWith!;
    return locationOn;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async
  {
    asked++;
    return afterAsking;
  }
}

void main()
{
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocationPlugin plugin;
  final finder = PlaceFinder();

  setUp(() {
    plugin = _FakeLocationPlugin();
    GeolocatorPlatform.instance = plugin;
  });

  Future<PlaceProblem?> problem() async
  {
    try
    {
      await finder.findCurrentPlace();
      return null;
    }
    on PlaceNotFound catch (e)
    {
      return e.problem;
    }
  }

  // NOTE: Regression test. An app built before the location plugin was added (e.g. after a
  // hot restart) throws MissingPluginException, which used to escape as an unhandled error
  test("a broken or missing location plugin becomes a message, not a crash", () async {
    plugin.failWith = MissingPluginException("No implementation found for method isLocationServiceEnabled");

    expect(await problem(), PlaceProblem.notFound);
  });

  test("location switched off", () async {
    plugin.locationOn = false;

    expect(await problem(), PlaceProblem.locationOff);
  });

  test("asks for permission once, and says so when refused", () async {
    plugin.permission = LocationPermission.denied;
    plugin.afterAsking = LocationPermission.denied;

    expect(await problem(), PlaceProblem.permissionDenied);
    expect(plugin.asked, 1);
  });

  test("permission blocked for good", () async {
    plugin.permission = LocationPermission.deniedForever;

    expect(await problem(), PlaceProblem.permissionBlocked);
    expect(plugin.asked, 0, reason: "the phone won't show the prompt again, so don't try");
  });
}
