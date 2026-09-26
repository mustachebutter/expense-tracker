import 'package:expense_tracker/services/place_finder.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart' show Placemark;
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
  Position? lastKnown;
  Object? currentFailsWith;
  var currentAsked = 0;

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

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async => lastKnown;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async
  {
    currentAsked++;
    if (currentFailsWith != null) throw currentFailsWith!;
    return hanoiPosition;
  }
}

final hanoiPosition = Position(
  latitude: 21.03, longitude: 105.85, timestamp: DateTime(2026, 9, 26), accuracy: 500,
  altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
);

void main()
{
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocationPlugin plugin;
  late List<({double latitude, double longitude})> lookedUp;
  late Future<List<Placemark>> Function() lookUpAnswer;
  late PlaceFinder finder;

  setUp(() {
    plugin = _FakeLocationPlugin();
    GeolocatorPlatform.instance = plugin;
    lookedUp = [];
    lookUpAnswer = () async => const [Placemark(locality: "Hanoi", administrativeArea: "Hà Nội", country: "Vietnam")];
    finder = PlaceFinder(lookUp: (latitude, longitude) {
      lookedUp.add((latitude: latitude, longitude: longitude));
      return lookUpAnswer();
    });
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

    expect(await problem(), PlaceProblem.unavailable);
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

  group("position", () {
    test("uses the position the phone already knows, without waiting for a new one", () async {
      plugin.lastKnown = hanoiPosition;

      final place = await finder.findCurrentPlace();

      expect(place, (suburb: null, city: "Hanoi", state: "Hà Nội", country: "Vietnam"));
      expect(plugin.currentAsked, 0);
    });

    test("waits for a fresh position when the phone doesn't know one yet", () async {
      final place = await finder.findCurrentPlace();

      expect(place.city, "Hanoi");
      expect(plugin.currentAsked, 1);
    });

    test("no position in time", () async {
      plugin.currentFailsWith = Exception("Time limit reached");

      expect(await problem(), PlaceProblem.noPosition);
    });
  });

  group("place name", () {
    test("the lookup failing, e.g. no internet", () async {
      lookUpAnswer = () async => throw Exception("Service not Available");

      expect(await problem(), PlaceProblem.noPlaceName);
    });

    test("the lookup finding nothing", () async {
      lookUpAnswer = () async => const [];

      expect(await problem(), PlaceProblem.noPlaceName);
    });

    test("skips results without a place, and uses the district outside towns", () async {
      lookUpAnswer = () async => const [
        Placemark(name: "Some road"),
        Placemark(subAdministrativeArea: "Ba Vì District", administrativeArea: "Hà Nội", country: "Vietnam"),
      ];

      expect(await finder.findCurrentPlace(), (suburb: null, city: "Ba Vì District", state: "Hà Nội", country: "Vietnam"));
    });
  });
}
