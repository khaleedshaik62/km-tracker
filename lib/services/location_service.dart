import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

// ── Background isolate entry point ───────────────────────────────────────────
// @pragma ensures this function is kept by the tree-shaker in release builds.
@pragma('vm:entry-point')
void locationTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

/// Runs entirely in the background isolate.
/// Receives GPS updates and sends them to the main isolate via IPC.
/// Keeps accumulating distance even when the screen is locked.
class _LocationTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _sub;
  Position? _last;
  double _totalMeters = 0;
  bool _paused = false;
  String _vehicle = 'car';

  // Meters-per-update cap per vehicle (rejects GPS jumps / satellite glitches)
  // Reduced caps for better accuracy - filters off-road GPS jumps
  static const _cap = {
    'car': 100.0, // ~360 km/h at max, filters highway jumps
    'bike': 80.0, // ~288 km/h at max
    'truck': 90.0, // ~324 km/h at max
    'walking': 15.0, // ~54 km/h at max
  };

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition);
  }

  void _onPosition(Position pos) {
    // Reject poor-accuracy readings (screen-lock degrades GPS signal)
    // Stricter accuracy threshold prevents off-road ghost paths
    if (pos.accuracy > 30) return;

    // Always send position so the map updates even when paused
    FlutterForegroundTask.sendDataToMain({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'accuracy': pos.accuracy,
      'speed': _paused ? 0.0 : pos.speed * 3.6, // m/s → km/h
      'totalMeters': _totalMeters,
    });

    if (_paused) return; // Don't accumulate distance while paused

    if (_last != null) {
      final dist = Geolocator.distanceBetween(
        _last!.latitude,
        _last!.longitude,
        pos.latitude,
        pos.longitude,
      );
      final maxDist = _cap[_vehicle] ?? 100.0;
      // Accept only realistic movement (8m–cap): filters jitter AND satellite jumps
      // Minimum 8m prevents tiny GPS fluctuations from counting
      if (dist >= 8 && dist <= maxDist) {
        _totalMeters += dist;
      }
    }
    _last = pos;

    // Update the persistent notification with live distance
    FlutterForegroundTask.updateService(
      notificationText:
          '📍 ${(_totalMeters / 1000).toStringAsFixed(2)} km recorded',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _sub?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map<String, dynamic>) return;
    switch (data['cmd'] as String?) {
      case 'pause':
        _paused = true;
      case 'resume':
        _paused = false;
        _last =
            null; // Reset baseline so paused movement isn't counted on resume
      case 'reset':
        _totalMeters = 0;
        _last = null;
        _paused = false;
      case 'vehicle':
        _vehicle = data['v'] as String? ?? 'car';
    }
  }
}

// ── Main-isolate service API ──────────────────────────────────────────────────
class LocationService {
  static bool _initialized = false;

  /// Call once before using any other methods.
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'km_tracker_gps',
        channelName: 'KM Tracker GPS',
        channelDescription:
            'Shows live tracking status. Required to keep GPS active when screen is locked.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWifiLock: true,
      ),
    );
  }

  /// Request location permission. Returns true if sufficient for tracking.
  static Future<bool> requestPermissions() async {
    // Request notification permission (Android 13+)
    await FlutterForegroundTask.requestNotificationPermission();

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    return perm != LocationPermission.denied;
  }

  /// Start the foreground service. GPS continues even when screen is locked.
  static Future<void> start() async {
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'KM Tracker Active',
      notificationText: '📍 0.00 km recorded — tap to open',
      callback: locationTaskCallback,
    );
  }

  /// Stop the foreground service.
  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  /// Send a command to the background task isolate.
  static void send(Map<String, dynamic> cmd) {
    FlutterForegroundTask.sendDataToTask(cmd);
  }

  static void addListener(void Function(Object) cb) =>
      FlutterForegroundTask.addTaskDataCallback(cb);

  static void removeListener(void Function(Object) cb) =>
      FlutterForegroundTask.removeTaskDataCallback(cb);
}
