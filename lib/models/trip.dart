import 'dart:convert';
import 'package:latlong2/latlong.dart';

class Trip {
  final int? id;
  final String date;
  final double distanceKm;
  final String destinationName;
  final double avgSpeedKmh;
  final int durationMinutes;
  final String note;
  final List<LatLng> path;
  final String userId; // New field to store Google UID

  const Trip({
    this.id,
    required this.date,
    required this.distanceKm,
    required this.destinationName,
    required this.avgSpeedKmh,
    required this.durationMinutes,
    required this.note,
    required this.path,
    required this.userId,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'date': date,
        'distance_km': distanceKm,
        'destination_name': destinationName,
        'avg_speed_kmh': avgSpeedKmh,
        'duration_minutes': durationMinutes,
        'note': note,
        'path_json': jsonEncode(
          path.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
        ),
        'user_id': userId, // Persist user UID
      };

  factory Trip.fromMap(Map<String, dynamic> map) {
    List<LatLng> path = [];
    final raw = map['path_json'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        path = decoded
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList();
      } catch (_) {}
    }
    return Trip(
      id: map['id'] as int?,
      date: map['date'] as String,
      distanceKm: (map['distance_km'] as num).toDouble(),
      destinationName: map['destination_name'] as String,
      avgSpeedKmh: (map['avg_speed_kmh'] as num).toDouble(),
      durationMinutes: (map['duration_minutes'] as num?)?.toInt() ?? 0,
      note: map['note'] as String? ?? '',
      path: path,
      userId: map['user_id'] as String? ?? '', // Default empty if missing
    );
  }
}
