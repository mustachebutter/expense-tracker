import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

typedef FoundPlace = ({String? city, String? state, String? country});

// Turns a position into place names. A parameter so tests can fake it
typedef PlaceLookup = Future<List<Placemark>> Function(double latitude, double longitude);

enum PlaceProblem
{
  // Location is switched off for the whole phone
  locationOff,
  // The user said no to the permission prompt (it can be asked again)
  permissionDenied,
  // The user said "don't ask again", only the phone's settings can change it now
  permissionBlocked,
  // The phone couldn't get a position in time (common indoors)
  noPosition,
  // Got a position, but couldn't turn it into a place name (this needs the internet)
  noPlaceName,
  // Anything else, e.g. location isn't working in this build of the app at all
  unavailable,
}

class PlaceNotFound implements Exception
{
  final PlaceProblem problem;
  // What actually went wrong, for the logs
  final Object? cause;

  const PlaceNotFound(this.problem, [this.cause]);

  @override
  String toString() => "Couldn't find the current place: ${problem.name}${cause == null ? "" : " ($cause)"}";
}

// Finds which city / state / country the phone is in right now.
// NOTE: Only the names are kept, never the coordinates, and it only runs when the user taps
// "Use my location"
class PlaceFinder
{
  final PlaceLookup _lookUp;

  PlaceFinder({PlaceLookup? lookUp})
    : _lookUp = lookUp ?? ((latitude, longitude) => Geocoding().placemarkFromCoordinates(latitude, longitude));

  // NOTE: Turning a position into a place name needs the phone's own geocoder, which only
  // exists on Android and iOS
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Throws PlaceNotFound, and only PlaceNotFound, when it can't: whatever goes wrong (even
  // the location plugin missing from an old build), the form can say so instead of crashing
  Future<FoundPlace> findCurrentPlace() async
  {
    try
    {
      final position = await _findPosition();
      return await _nameOf(position);
    }
    on PlaceNotFound catch (e)
    {
      debugPrint("📍 $e");
      rethrow;
    }
    catch (e)
    {
      debugPrint("📍 Location isn't working: $e");
      throw PlaceNotFound(PlaceProblem.unavailable, e);
    }
  }

  Future<Position> _findPosition() async
  {
    if (!await Geolocator.isLocationServiceEnabled()) throw const PlaceNotFound(PlaceProblem.locationOff);

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) throw const PlaceNotFound(PlaceProblem.permissionDenied);
    if (permission == LocationPermission.deniedForever) throw const PlaceNotFound(PlaceProblem.permissionBlocked);

    // NOTE: The phone usually already knows roughly where it is (from any app that used
    // location recently). That's instant and plenty for a city, so try it first
    try
    {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
    }
    catch (e)
    {
      debugPrint("📍 No last known position: $e");
    }

    // Otherwise wait for a fresh one. Low accuracy is enough for a city, and it's faster
    try
    {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
      );
    }
    catch (e)
    {
      throw PlaceNotFound(PlaceProblem.noPosition, e);
    }
  }

  Future<FoundPlace> _nameOf(Position position) async
  {
    final List<Placemark> places;
    try
    {
      places = await _lookUp(position.latitude, position.longitude);
    }
    catch (e)
    {
      throw PlaceNotFound(PlaceProblem.noPlaceName, e);
    }

    String? tidy(String? name) => (name == null || name.trim().isEmpty) ? null : name.trim();

    // NOTE: Several results can come back, the first with a country is the useful one
    for (final place in places)
    {
      final found = (
        // Some places have no "locality" (e.g. outside a town), the district is next best
        city: tidy(place.locality) ?? tidy(place.subAdministrativeArea),
        state: tidy(place.administrativeArea),
        country: tidy(place.country),
      );
      if (found.country != null || found.city != null) return found;
    }
    throw const PlaceNotFound(PlaceProblem.noPlaceName);
  }

  // For "don't ask again": the only way back is the app's page in the phone's settings
  Future<void> openSettings() => Geolocator.openAppSettings();
}
