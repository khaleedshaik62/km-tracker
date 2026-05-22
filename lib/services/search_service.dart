import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchService {
  // Recent searches (like Google Maps)
  static Future<List<Map<String, dynamic>>> getRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('recent_searches') ?? '[]';
      final list = jsonDecode(jsonStr) as List;
      return list.cast<Map<String, dynamic>>().take(5).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addRecentSearch(Map<String, dynamic> place) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getRecentSearches();

      // Remove duplicate if exists
      current.removeWhere(
          (p) => p['lat'] == place['lat'] && p['lng'] == place['lng']);

      // Add to front
      current.insert(0, place);

      // Keep only last 10
      if (current.length > 10) current.removeLast();

      await prefs.setString('recent_searches', jsonEncode(current));
    } catch (_) {}
  }

  // Smart place search with Google-like features
  static Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    LatLng? userLocation,
    int maxResults = 8,
  }) async {
    try {
      if (query.trim().isEmpty) return [];

      final results = <Map<String, dynamic>>[];

      // Get exact matches from Photon API
      String url =
          'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=$maxResults&osm_tag=!tourism';
      if (userLocation != null) {
        url += '&lat=${userLocation.latitude}&lon=${userLocation.longitude}';
      }

      final res = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];

        for (final f in features) {
          try {
            final props = f['properties'] as Map<String, dynamic>? ?? {};
            final coords = f['geometry']['coordinates'] as List?;

            if (coords == null || coords.length < 2) continue;

            final distance = userLocation != null
                ? _calculateDistance(
                    userLocation,
                    LatLng(
                      (coords[1] as num).toDouble(),
                      (coords[0] as num).toDouble(),
                    ),
                  )
                : null;

            final parts = [
              props['name'],
              props['address'],
              props['city'],
              props['state'],
              props['country']
            ].whereType<String>().toList();

            results.add({
              'name': props['name'] ?? props['city'] ?? 'Unknown',
              'display': parts.join(', '),
              'lat': (coords[1] as num).toDouble(),
              'lng': (coords[0] as num).toDouble(),
              'distance': distance,
              'type': props['osm_value'] ?? 'place',
            });
          } catch (_) {
            continue;
          }
        }
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  // Calculate distance between two coordinates (in km)
  static double _calculateDistance(LatLng pos1, LatLng pos2) {
    const earthRadius = 6371; // Radius in km
    final lat1 = pos1.latitude * math.pi / 180;
    final lat2 = pos2.latitude * math.pi / 180;
    final deltaLat = (pos2.latitude - pos1.latitude) * math.pi / 180;
    final deltaLng = (pos2.longitude - pos1.longitude) * math.pi / 180;

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  // Get nearby categories (restaurants, gas stations, etc.)
  static Future<List<Map<String, dynamic>>> getNearbyPlaces(
    LatLng userLocation, {
    String? category,
  }) async {
    try {
      // Using Overpass API for category-based search
      // Categories: restaurant, fuel, cafe, hospital, bank, etc.
      final bbox =
          '${userLocation.latitude - 0.05},${userLocation.longitude - 0.05},'
          '${userLocation.latitude + 0.05},${userLocation.longitude + 0.05}';

      final query = category == 'fuel'
          ? '[bbox:$bbox];(node["amenity"="fuel"];way["amenity"="fuel"];);out geom;'
          : category == 'restaurant'
              ? '[bbox:$bbox];(node["amenity"="restaurant"];way["amenity"="restaurant"];);out geom;'
              : '[bbox:$bbox];(node;way;);out geom;';

      final url =
          'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}';

      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        // Parse OSM data - simplified
        return [];
      }

      return [];
    } catch (_) {
      return [];
    }
  }
}
