import 'package:geolocator/geolocator.dart';

/// Custom Exception for Location errors
class LocationCustomException implements Exception {
  final String message;
  final String? code;

  const LocationCustomException(this.message, {this.code});

  @override
  String toString() => message;
}

/// Service to acquire real GPS location from device hardware
/// and calculate distance from company office geofence coordinates.
class LocationService {
  /// Checks permissions and fetches current GPS position with high accuracy.
  static Future<Position> getCurrentPosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationCustomException(
        'Location services are disabled on your device. Please turn on GPS/Location.',
        code: 'LOCATION_SERVICES_DISABLED',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationCustomException(
          'Location permission was denied. GPS access is required to verify the 5-metre geofence.',
          code: 'PERMISSION_DENIED',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationCustomException(
        'Location permissions are permanently denied. Please enable location access in system settings.',
        code: 'PERMISSION_DENIED_FOREVER',
      );
    }

    // Try acquiring fresh GPS fix
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      // Fallback 1: High accuracy with 4 second limit
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 4),
          ),
        );
      } catch (_) {
        // Fallback 2: Check last known position (essential on emulators & indoor GPS shadows)
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return lastKnown;
        }

        throw const LocationCustomException(
          'Could not acquire GPS fix. Please ensure location is enabled and GPS signal is available.',
          code: 'GPS_FIX_FAILED',
        );
      }
    }
  }

  /// Calculates geodesic Haversine distance in metres between two coordinates
  static double distanceBetween({
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
  }) {
    return Geolocator.distanceBetween(
      startLatitude,
      startLongitude,
      endLatitude,
      endLongitude,
    );
  }
}
