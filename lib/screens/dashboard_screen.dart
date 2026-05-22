import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../models/trip.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../services/search_service.dart';
import 'history_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // ── Map ────────────────────────────────────────────────────────────────────
  final _mapCtrl = MapController();
  LatLng? _pos;
  bool _followUser = true;
  bool _satellite = false;

  // ── Tracking ───────────────────────────────────────────────────────────────
  bool _isTracking = false;
  bool _isPaused = false;
  double _km = 0;
  double _speed = 0;
  List<LatLng> _path = [];
  String _vehicle = 'car';
  DateTime? _startTime;

  // ── Route / destination ───────────────────────────────────────────────────
  LatLng? _destCoords;
  String? _destName;
  List<LatLng> _routePath = [];
  String? _routeKm;
  bool _loadingRoute = false;

  // ── Pause Logs ────────────────────────────────────────────────────────────
  final List<String> _pauseLogs = [];

  // ── Search ─────────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _recentSearches = [];
  bool _searching = false;
  bool _showResults = false;
  Timer? _searchDebounce;

  // ── Profile ────────────────────────────────────────────────────────────────
  String _userName = 'Driver';

  // ── Live location (used when NOT tracking via foreground service) ──────────
  StreamSubscription<Position>? _liveLocSub;

  // ── Pulse animation for the tracking indicator ────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _setup();
  }

  Future<void> _setup() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _userName = prefs.getString('name') ?? 'Driver');

    LocationService.initialize();
    await LocationService.requestPermissions();
    LocationService.addListener(_onGpsData);

    await _getInitialPos();
    _startLiveLoc();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final recent = await SearchService.getRecentSearches();
    if (mounted) setState(() => _recentSearches = recent);
  }

  Future<void> _getInitialPos() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() => _pos = LatLng(p.latitude, p.longitude));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapCtrl.move(_pos!, 15);
        } catch (_) {}
      });
    } catch (_) {}
  }

  void _startLiveLoc() {
    _liveLocSub?.cancel();
    _liveLocSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((p) {
      if (_isTracking || !mounted) return;
      setState(() => _pos = LatLng(p.latitude, p.longitude));
      if (_followUser) _moveMap(_pos!, 15);
    });
  }

  /// Receives position data streamed from the background foreground service.
  void _onGpsData(Object data) {
    if (!mounted || !_isTracking) return;
    if (data is! Map<String, dynamic>) return;

    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final newPos = LatLng(lat, lng);
    setState(() {
      _pos = newPos;
      _speed = (data['speed'] as num?)?.toDouble() ?? 0;
      _km = ((data['totalMeters'] as num?)?.toDouble() ?? 0) / 1000;
      if (!_isPaused) _path.add(newPos);
    });

    if (_followUser) _moveMap(newPos, 16);
  }

  void _moveMap(LatLng pos, double zoom) {
    try {
      _mapCtrl.move(pos, zoom);
    } catch (_) {}
  }

  // ── Tracking actions ───────────────────────────────────────────────────────
  Future<void> _startTracking() async {
    // Cancel live loc — foreground service will now drive all updates
    _liveLocSub?.cancel();

    LocationService.send({'cmd': 'reset'});
    LocationService.send({'cmd': 'vehicle', 'v': _vehicle});

    setState(() {
      _isTracking = true;
      _isPaused = false;
      _km = 0;
      _speed = 0;
      _path = _pos != null ? [_pos!] : [];
      _startTime = DateTime.now();
      _followUser = true;
      _pauseLogs.clear();
    });

    await LocationService.start();
  }

  void _pauseTracking() {
    LocationService.send({'cmd': 'pause'});
    final now = DateTime.now();
    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final dur = _startTime != null ? now.difference(_startTime!).inMinutes : 0;
    _pauseLogs.add(
        'Paused at $timeStr (Dist: ${_km.toStringAsFixed(2)} km, Dur: $dur min)');
    setState(() => _isPaused = true);
  }

  void _resumeTracking() {
    LocationService.send({'cmd': 'resume'});
    final timeStr =
        '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}';
    _pauseLogs.add('Resumed at $timeStr');
    setState(() => _isPaused = false);
  }

  Future<void> _stopTracking() async {
    await LocationService.stop();

    final km = _km;
    final path = List<LatLng>.from(_path);
    final duration = _startTime != null
        ? DateTime.now().difference(_startTime!).inMinutes
        : 0;

    setState(() {
      _isTracking = false;
      _isPaused = false;
    });

    _startLiveLoc();

    if (mounted) _showSaveDialog(km, duration, path);
  }

  // ── Save trip dialog ───────────────────────────────────────────────────────
  void _showSaveDialog(double km, int duration, List<LatLng> path) {
    final nameCtrl =
        TextEditingController(text: _destName?.split(',').first ?? '');
    final noteCtrl = TextEditingController(text: _pauseLogs.join('\n'));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _SaveSheet(
          km: km,
          duration: duration,
          nameCtrl: nameCtrl,
          noteCtrl: noteCtrl,
          onSave: (name, note) async {
            if (name.isEmpty && _pos != null) {
              name = await _reverseGeocode(_pos!);
            }
            final avgSpeedKmh = duration > 0 ? (km / (duration / 60.0)) : 0.0;
            final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
            final trip = Trip(
              date: _fmtDate(DateTime.now()),
              distanceKm: km,
              destinationName: name.isEmpty ? 'Free Trip' : name,
              avgSpeedKmh: avgSpeedKmh,
              durationMinutes: duration,
              note: note,
              path: path,
              userId: userId,
            );
            await DatabaseService.insert(trip);
            if (ctx.mounted) Navigator.pop(ctx);
            _resetTrip();
          },
          onDiscard: () {
            Navigator.pop(ctx);
            _resetTrip();
          },
        ),
      ),
    );
  }

  void _resetTrip() {
    setState(() {
      _km = 0;
      _speed = 0;
      _path = [];
      _destCoords = null;
      _destName = null;
      _routePath = [];
      _routeKm = null;
      _startTime = null;
    });
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  Future<String> _reverseGeocode(LatLng pos) async {
    try {
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}'),
        headers: {'User-Agent': 'KMTrackerApp/1.0'},
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr != null) {
        return (addr['road'] ??
            addr['suburb'] ??
            addr['city'] ??
            addr['county'] ??
            addr['state'] ??
            'Unknown') as String;
      }
    } catch (_) {}
    return '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
  }

  // ── Search ─────────────────────────────────────────────────────────────────
  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = _recentSearches;
        _showResults = _recentSearches.isNotEmpty;
      });
      return;
    }
    _searchDebounce =
        Timer(const Duration(milliseconds: 400), () => _searchPlaces(q));
  }

  Future<void> _searchPlaces(String q) async {
    setState(() => _searching = true);
    try {
      final results = await SearchService.searchPlaces(
        q,
        userLocation: _pos,
        maxResults: 8,
      );

      if (mounted) {
        setState(() {
          _results = results;
          _showResults = results.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _results = []);
    }
    if (mounted) setState(() => _searching = false);
  }

  void _selectDest(Map<String, dynamic> place) {
    final coords = LatLng(place['lat'] as double, place['lng'] as double);
    setState(() {
      _destCoords = coords;
      _destName = place['display'] as String;
      _results = [];
      _showResults = false;
      _followUser = false;
      _routePath = [];
      _routeKm = null;
    });

    // Add to recent searches
    SearchService.addRecentSearch(place);
    _loadRecentSearches();

    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    if (_pos != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapCtrl.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints([_pos!, coords]),
              padding: const EdgeInsets.all(80),
            ),
          );
        } catch (_) {}
      });
    }
  }

  Future<void> _fetchRoute() async {
    if (_pos == null || _destCoords == null) return;
    setState(() => _loadingRoute = true);
    try {
      final o = '${_pos!.longitude},${_pos!.latitude}';
      final d = '${_destCoords!.longitude},${_destCoords!.latitude}';
      final url =
          'https://router.project-osrm.org/route/v1/driving/$o;$d?overview=full&geometries=geojson';
      final res = await http.get(Uri.parse(url));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List)
          .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      setState(() {
        _routePath = coords;
        _routeKm = ((route['distance'] as num) / 1000).toStringAsFixed(1);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not fetch route. Check connection.')),
        );
      }
    }
    setState(() => _loadingRoute = false);
  }

  void _clearDest() {
    setState(() {
      _destCoords = null;
      _destName = null;
      _routePath = [];
      _routeKm = null;
      _followUser = true;
    });
    if (_pos != null) _moveMap(_pos!, 15);
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Logout', style: TextStyle(color: kDanger))),
        ],
      ),
    );

    if (confirm != true) return;

    await LocationService.stop();
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _liveLocSub?.cancel();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    LocationService.removeListener(_onGpsData);
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(topPad),
          if (!_isTracking) _buildSearchArea(topPad),
          _buildFABs(),
          _buildDraggablePanel(),
          if (_pos == null) _buildLocatingOverlay(),
        ],
      ),
    );
  }

  // ── Map ────────────────────────────────────────────────────────────────────
  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapCtrl,
      options: MapOptions(
        initialCenter: _pos ?? const LatLng(17.3850, 78.4867),
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (_, hasGesture) {
          if (hasGesture && _followUser) setState(() => _followUser = false);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _satellite
              ? 'https://mt1.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
              : 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
          userAgentPackageName: 'com.example.km_tracker',
          maxZoom: 20,
        ),
        if (_routePath.isNotEmpty)
          PolylineLayer(polylines: [
            Polyline(
              points: _routePath,
              color: Colors.blueGrey.withAlpha(190),
              strokeWidth: 5,
            ),
          ]),
        if (_path.length > 1)
          PolylineLayer(polylines: <Polyline>[
            Polyline(points: _path, color: kPrimary, strokeWidth: 5),
          ]),
        MarkerLayer(markers: [
          if (_pos != null)
            Marker(
              point: _pos!,
              width: 52,
              height: 52,
              child: _VehicleMarker(
                vehicle: _isTracking && !_isPaused ? _vehicle : null,
                pulseAnim: _pulseAnim,
              ),
            ),
          if (_destCoords != null)
            Marker(
              point: _destCoords!,
              width: 40,
              height: 56,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.location_pin, color: kDanger, size: 48),
            ),
        ]),
      ],
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(double topPad) {
    return Positioned(
      top: topPad + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _glass(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route, color: kPrimary, size: 18),
                const SizedBox(width: 8),
                const Text('KM Tracker',
                    style: TextStyle(
                        color: kTextMain,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: -0.5)),
                if (_isTracking && !_isPaused) ...[
                  const SizedBox(width: 10),
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Opacity(
                      opacity: _pulseAnim.value,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: kSuccess, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text('Live',
                      style: TextStyle(
                          color: kSuccess,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
            child: _glass(
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline, color: kPrimary, size: 18),
                  SizedBox(width: 6),
                  Text('Profile',
                      style: TextStyle(
                          color: kTextMain,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search ─────────────────────────────────────────────────────────────────
  Widget _buildSearchArea(double topPad) {
    return Positioned(
      top: topPad + 62,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _glass(
            padding: EdgeInsets.zero,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(
                  color: kTextMain, fontSize: 14, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Search destination...',
                hintStyle: const TextStyle(color: kMuted, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: kMuted, size: 20),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kPrimary)))
                    : _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: kMuted, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {
                                _results = [];
                                _showResults = false;
                              });
                            })
                        : null,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: _onSearchChanged,
              onTap: () {
                if (_results.isNotEmpty) setState(() => _showResults = true);
              },
            ),
          ),

          // Search results dropdown
          if (_showResults && _results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withAlpha(20),
                      blurRadius: 20,
                      offset: const Offset(0, 10))
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _results.length.clamp(0, 5),
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: kPrimary.withAlpha(25)),
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined,
                        color: kPrimary, size: 18),
                    title: Text(r['name'] as String,
                        style: const TextStyle(
                            color: kTextMain,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(r['display'] as String,
                        style: const TextStyle(color: kTextMuted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    onTap: () => _selectDest(r),
                  );
                },
              ),
            ),

          // Destination card
          if (_destCoords != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 15)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_pin, color: kDanger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _destName?.split(',').first ?? '',
                          style: const TextStyle(
                              color: kTextMain,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_routeKm != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: kPrimary.withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('$_routeKm km',
                              style: const TextStyle(
                                  color: kPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _clearDest,
                        child: const Icon(Icons.close, color: kMuted, size: 18),
                      ),
                    ],
                  ),
                  if (_routeKm == null) ...[
                    const SizedBox(height: 10),
                    _btn(
                      label: _loadingRoute ? 'Finding Route...' : 'Show Route',
                      icon: Icons.alt_route,
                      onTap: _loadingRoute ? null : _fetchRoute,
                      outlined: true,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── FABs ───────────────────────────────────────────────────────────────────
  Widget _buildFABs() {
    return Positioned(
      right: 16,
      bottom: 120, // Moved up to clear the compact sheet
      child: Column(
        children: [
          _fabBtn(
            icon: Icons.my_location,
            onTap: () {
              setState(() => _followUser = true);
              if (_pos != null) _moveMap(_pos!, 16);
            },
            active: _followUser,
          ),
          const SizedBox(height: 12),
          _fabBtn(
            icon: _satellite ? Icons.map_outlined : Icons.satellite_alt,
            onTap: () => setState(() => _satellite = !_satellite),
          ),
        ],
      ),
    );
  }

  Widget _fabBtn(
      {required IconData icon,
      required VoidCallback onTap,
      bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active ? kPrimary.withAlpha(20) : kPanelBg,
          shape: BoxShape.circle,
          border: Border.all(
              color: active ? kPrimary : kBorder, width: active ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Icon(icon, color: active ? kPrimary : kTextMain, size: 20),
      ),
    );
  }

  // ── Bottom tracking panel ──────────────────────────────────────────────────
  Widget _buildDraggablePanel() {
    return DraggableScrollableSheet(
      initialChildSize: 0.12, // Default to collapsed as requested
      minChildSize: 0.12,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: kPanelBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 20)
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: kMuted.withAlpha(80),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isTracking
                                  ? (_isPaused
                                      ? 'Trip Paused ⏸'
                                      : 'Recording...')
                                  : 'Ready to Track',
                              style: const TextStyle(
                                  color: kTextMain,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isTracking && !_isPaused
                                  ? '🔒 GPS active — works with screen locked'
                                  : _isTracking
                                      ? 'Resume to continue recording'
                                      : 'Select vehicle and start',
                              style: TextStyle(
                                  color: _isTracking && !_isPaused
                                      ? kSecondary
                                      : kTextMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Metrics
                  Row(
                    children: [
                      _metric(
                          _km.toStringAsFixed(2), 'km', 'Distance', kPrimary),
                      const SizedBox(width: 8),
                      _metric(_speed.toStringAsFixed(1), 'km/h', 'Speed',
                          kSecondary),
                      if (_routeKm != null && _isTracking) ...[
                        const SizedBox(width: 8),
                        _metric(
                          ((double.tryParse(_routeKm!) ?? 0) - _km)
                              .clamp(0, 9999)
                              .toStringAsFixed(1),
                          'km',
                          'Remaining',
                          kDanger,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!_isTracking) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: ['car', 'bike', 'walking', 'truck']
                          .map(_vehicleBtn)
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_isTracking)
                    Row(
                      children: [
                        Expanded(
                            child: _isPaused
                                ? _btn(
                                    label: 'Resume',
                                    icon: Icons.play_arrow,
                                    onTap: _resumeTracking,
                                    outlined: true)
                                : _btn(
                                    label: 'Pause',
                                    icon: Icons.pause,
                                    onTap: _pauseTracking,
                                    outlined: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _btn(
                                label: 'Stop',
                                icon: Icons.stop_circle_outlined,
                                onTap: _stopTracking,
                                danger: true)),
                      ],
                    )
                  else
                    _btn(
                      label: _destCoords != null
                          ? 'Start Route'
                          : 'Start Tracking',
                      icon: Icons.play_arrow_rounded,
                      onTap: _pos != null ? _startTracking : null,
                      wide: true,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Helper widgets ─────────────────────────────────────────────────────────
  Widget _metric(String val, String unit, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(val,
                    style: TextStyle(
                        color: color,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1)),
                const SizedBox(width: 2),
                Text(unit,
                    style: TextStyle(
                        color: color.withAlpha(150),
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            Text(label,
                style: const TextStyle(
                    color: kTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }

  Widget _vehicleBtn(String type) {
    const emojis = {'car': '🚗', 'bike': '🏍️', 'walking': '🚶', 'truck': '🚚'};
    final sel = _vehicle == type;
    return GestureDetector(
      onTap: () {
        setState(() => _vehicle = type);
        if (_isTracking) LocationService.send({'cmd': 'vehicle', 'v': type});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: sel ? kPrimary.withAlpha(40) : Colors.transparent,
          shape: BoxShape.circle,
          border:
              Border.all(color: sel ? kPrimary : kBorder, width: sel ? 2 : 1),
        ),
        child: Text(emojis[type]!, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  Widget _btn({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
    bool wide = false,
    bool outlined = false,
    bool danger = false,
  }) {
    Color bg = danger
        ? kDanger
        : outlined
            ? Colors.transparent
            : kPrimary;
    Color fg = (outlined && !danger) ? kTextMain : Colors.white;
    if (danger && outlined) {
      bg = Colors.transparent;
      fg = kDanger;
    }

    return SizedBox(
      width: wide ? double.infinity : null,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: onTap != null ? bg : bg.withAlpha(80),
            borderRadius: BorderRadius.circular(14),
            gradient: (!outlined && !danger && onTap != null)
                ? const LinearGradient(
                    colors: [kPrimary, kPrimaryL],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            border:
                outlined ? Border.all(color: danger ? kDanger : kBorder) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: fg, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glass({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ??
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: kPanelBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha(15),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ]),
          child: child,
        ),
      ),
    );
  }

  Widget _buildLocatingOverlay() {
    return Positioned.fill(
      child: Container(
        color: kBg.withOpacity(0.8),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: kPrimary),
              SizedBox(height: 16),
              Text('Acquiring GPS signal...',
                  style: TextStyle(color: kText, fontSize: 16)),
              SizedBox(height: 6),
              Text('Please ensure location is enabled',
                  style: TextStyle(color: kMuted, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Vehicle marker on map ────────────────────────────────────────────────────
class _VehicleMarker extends StatelessWidget {
  final String? vehicle;
  final Animation<double> pulseAnim;
  const _VehicleMarker({this.vehicle, required this.pulseAnim});

  @override
  Widget build(BuildContext context) {
    const emojis = {'car': '🚗', 'bike': '🏍️', 'walking': '🚶', 'truck': '🚚'};
    final emoji = vehicle != null ? emojis[vehicle] : null;

    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          color: kPrimary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: kPrimary.withAlpha((pulseAnim.value * 120).toInt()),
              blurRadius: 16,
              spreadRadius: 4,
            )
          ],
        ),
        child: Center(
          child: emoji != null
              ? Text(emoji, style: const TextStyle(fontSize: 22))
              : const Icon(Icons.my_location, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

// ── Save trip bottom sheet ────────────────────────────────────────────────────
class _SaveSheet extends StatelessWidget {
  final double km;
  final int duration;
  final TextEditingController nameCtrl;
  final TextEditingController noteCtrl;
  final void Function(String name, String note) onSave;
  final VoidCallback onDiscard;

  const _SaveSheet({
    required this.km,
    required this.duration,
    required this.nameCtrl,
    required this.noteCtrl,
    required this.onSave,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: kMuted.withAlpha(80),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Trip Complete! 🎉',
              style: TextStyle(
                  color: kTextMain,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text('${km.toStringAsFixed(2)} km · ${duration}m',
              style: const TextStyle(
                  color: kTextMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          TextField(
            controller: nameCtrl,
            style:
                const TextStyle(color: kTextMain, fontWeight: FontWeight.w500),
            decoration: const InputDecoration(labelText: 'Trip Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            style:
                const TextStyle(color: kTextMain, fontWeight: FontWeight.w500),
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDiscard,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kDanger),
                    foregroundColor: kDanger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => onSave(nameCtrl.text, noteCtrl.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Save Trip',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
