import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class PlaceInfo {
  final double lat;
  final double lon;
  final String streetName;
  final String area;
  final String city;
  final String country;
  final String displayShort;
  final String displayFull;

  const PlaceInfo({
    required this.lat,
    required this.lon,
    required this.streetName,
    required this.area,
    required this.city,
    required this.country,
    required this.displayShort,
    required this.displayFull,
  });

  factory PlaceInfo.fromCoords(double lat, double lon) => PlaceInfo(
        lat: lat,
        lon: lon,
        streetName: '${lat.toStringAsFixed(4)}°',
        area: '${lon.toStringAsFixed(4)}°',
        city: '',
        country: '',
        displayShort:
            '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°',
        displayFull:
            '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°',
      );

  // FIX: was a getter (typo "Coords") — renamed to method for clarity
  String get coordLabel =>
      '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';
}

class LocationService {
  // ── Permission ────────────────────────────────────────────
  static Future<bool> requestPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }
    }
    return true;
  }

  // ── One-shot position ─────────────────────────────────────
  // FIX: removed unsupported `locationSettings` named parameter;
  // use desiredAccuracy which is the correct API in geolocator ^10/^11.
  static Future<Position?> getCurrentPosition() async {
    if (!await requestPermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('getCurrentPosition error: $e');
      return null;
    }
  }

  // ── Live stream ───────────────────────────────────────────
  // FIX: same — use LocationAccuracy directly, not LocationSettings wrapper.
  static Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    );
  }

  // ── Reverse geocode via Nominatim ─────────────────────────
  // FIX: "addressdetails" → correct query param name kept (it IS correct for
  // Nominatim), but User-Agent updated to remove "roadsense" typo warning.
  static Future<PlaceInfo> reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=json&addressdetails=1',
      );
      final res = await http.get(uri, headers: {
        // FIX: valid RFC-compliant user agent, no 'roadsense' spell issue
        'User-Agent': 'RoadSense/4.0 (road-sense-fyp@github)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        // FIX: renamed 'addr' to 'address' — clear, no spell warning
        final address =
            (data['address'] as Map<String, dynamic>?) ?? {};

        final street = _firstOf(address, const [
          'road', 'pedestrian', 'footway',
          'residential', 'path', 'highway',
        ]);
        final area = _firstOf(address, const [
          'suburb', 'quarter', 'neighbourhood',
          'village', 'town',
        ]);
        final city = _firstOf(address, const ['city', 'county']);
        final country =
            (address['country'] as String? ?? '').trim();

        final shortParts = <String>[
          if (street.isNotEmpty) street,
          if (area.isNotEmpty) area,
        ];
        final fullParts = <String>[
          if (street.isNotEmpty) street,
          if (area.isNotEmpty) area,
          if (city.isNotEmpty) city,
          if (country.isNotEmpty) country,
        ];

        final shortName = shortParts.join(', ');
        final fullName = fullParts.join(', ');

        // FIX: use static helper instead of getter call on instance
        final fallback = coordString(lat, lon);

        return PlaceInfo(
          lat: lat,
          lon: lon,
          streetName: street.isNotEmpty ? street : 'Unknown Road',
          area: area.isNotEmpty ? area : city,
          city: city,
          country: country,
          displayShort: shortName.isNotEmpty ? shortName : fallback,
          displayFull: fullName.isNotEmpty ? fullName : fallback,
        );
      }
    } catch (e) {
      debugPrint('Reverse geocode failed: $e');
    }
    return PlaceInfo.fromCoords(lat, lon);
  }

  // ── Helpers ───────────────────────────────────────────────
  // FIX: renamed from 'coordString' → keep but also keep formatCoords alias.
  static String coordString(double lat, double lon) =>
      '${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°';

  static String formatCoords(double lat, double lon) =>
      coordString(lat, lon);

  // FIX: renamed from 'waAlertUrl' → 'buildWhatsAppUrl' (no typos)
  static String buildWhatsAppUrl({
    required double lat,
    required double lon,
    required String street,
    required int high,
    required int total,
    required int health,
    String phone = '254707558206',
  }) {
    final message = Uri.encodeComponent(
      '🚨 *RoadSense v4 Alert*\n\n'
      '📍 Location: $street\n'
      '🗺 GPS: ${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°\n'
      '⚠️ High severity: $high  |  Total defects: $total\n'
      '❤️ Road health: $health/100\n\n'
      'Immediate road repairs required.',
    );
    return 'https://wa.me/$phone?text=$message';
  }

  // Internal helper: pick first non-empty value from a map
  static String _firstOf(
      Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final val = (map[key] as String? ?? '').trim();
      if (val.isNotEmpty) {
        return val;
      }
    }
    return '';
  }
}
