import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

typedef FoundPlace = ({String? city, String? state, String? country});

enum PlaceProblem
{
  // Location is switched off for the whole phone
  locationOff,
  // The user said no to the permission prompt (it can be asked again)
  permissionDenied,
  // The user said "don't ask again", only the phone's settings can change it now
  permissionBlocked,
  // Got a position but couldn't turn it into a place, or it took too long
  notFound,
}

class PlaceNotFound implements Exception
{
  final PlaceProblem problem;

  const PlaceNotFound(this.problem);

  @override
  String toString() => "Couldn't find the current place: ${problem.name}";
}

// Finds which city / state / country the phone is in right now.
// NOTE: Only the names are kept, never the coordinates, and it only runs when the user taps
// "Use my location"
class PlaceFinder
{
  // NOTE: Turning a position into a place name needs the phone's own geocoder, which only
  // exists on Android and iOS
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Throws PlaceNotFound, and only PlaceNotFound, when it can't: whatever goes wrong (even
  // the location plugin missing from an old build), the form can say so instead of crashing
  Future<FoundPlace> findCurrentPlace() async
  {
    try
    {
      if (!await Geolocator.isLocationServiceEnabled()) throw const PlaceNotFound(PlaceProblem.locationOff);

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) throw const PlaceNotFound(PlaceProblem.permissionDenied);
      if (permission == LocationPermission.deniedForever) throw const PlaceNotFound(PlaceProblem.permissionBlocked);

      // NOTE: Low accuracy is enough for a city, and it's faster and easier on the battery
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
      );
      final places = await Geocoding().placemarkFromCoordinates(position.latitude, position.longitude);
      if (places.isEmpty) throw const PlaceNotFound(PlaceProblem.notFound);

      final place = places.first;
      String? tidy(String? name) => (name == null || name.trim().isEmpty) ? null : name.trim();
      return (
        // Some places have no "locality" (e.g. outside a town), the district is next best
        city: tidy(place.locality) ?? tidy(place.subAdministrativeArea),
        state: tidy(place.administrativeArea),
        country: tidy(place.country),
      );
    }
    on PlaceNotFound
    {
      rethrow;
    }
    catch (e)
    {
      print("Couldn't work out the current place: $e");
      throw const PlaceNotFound(PlaceProblem.notFound);
    }
  }

  // For "don't ask again": the only way back is the app's page in the phone's settings
  Future<void> openSettings() => Geolocator.openAppSettings();
}
