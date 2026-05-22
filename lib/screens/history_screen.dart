import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../services/database_service.dart';
import '../services/location_service.dart';
import '../models/trip.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Trip> _trips = [];
  bool _loading = true;
  String _userName = 'Driver';
  String _userEmail = '';
  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final trips = await DatabaseService.getAll();
    final user = FirebaseAuth.instance.currentUser;
    if (mounted) {
      setState(() {
        _userName = prefs.getString('name') ?? user?.displayName ?? 'Driver';
        _userEmail = user?.email ?? '';
        _nameCtrl.text = _userName;
        _trips = trips;
        _loading = false;
      });
    }
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', name);
    setState(() => _userName = name);
  }

  Future<void> _deleteTrip(Trip trip) async {
    if (trip.id == null) return;
    await DatabaseService.delete(trip.id!);
    setState(() => _trips.remove(trip));
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Trips?',
            style: TextStyle(color: kTextMain, fontWeight: FontWeight.w800)),
        content: const Text('This action cannot be undone.',
            style: TextStyle(color: kTextMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: kTextMuted, fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Delete All', style: TextStyle(color: kDanger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseService.deleteAll();
      setState(() => _trips = []);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout?',
            style: TextStyle(color: kTextMain, fontWeight: FontWeight.w800)),
        content: const Text('You will need to sign in again to track trips.',
            style: TextStyle(color: kTextMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: kTextMuted, fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Logout', style: TextStyle(color: kDanger, fontWeight: FontWeight.w700))),
        ],
      ),
    );

    if (confirm == true) {
      await LocationService.stop();
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  double get _totalKm => _trips.fold(0.0, (s, t) => s + t.distanceKm);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: kBg,
            foregroundColor: kTextMain,
            pinned: true,
            expandedHeight: 200,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimary.withAlpha(20), kBg],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Editable name
                        TextField(
                          controller: _nameCtrl,
                          style: const TextStyle(
                              color: kTextMain,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.0),
                          decoration: InputDecoration(
                            hintText: 'Your Name',
                            hintStyle: TextStyle(color: kTextMuted.withOpacity(0.5), fontSize: 32),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: _saveName,
                          onEditingComplete: () => _saveName(_nameCtrl.text),
                        ),
                        if (_userEmail.isNotEmpty) ...[
                          Text(
                            _userEmail,
                            style: TextStyle(color: kTextMuted.withOpacity(0.7), fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            const Icon(Icons.route, color: kPrimary, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              '${_totalKm.toStringAsFixed(1)} km total · ${_trips.length} trips',
                              style: const TextStyle(color: kTextMuted, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout, color: kDanger),
                tooltip: 'Logout',
                onPressed: _logout,
              ),
              if (_trips.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: kTextMuted),
                  tooltip: 'Clear all',
                  onPressed: _deleteAll,
                ),
            ],
          ),

          // ── Body ──────────────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: kPrimary)),
            )
          else if (_trips.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.route, size: 72, color: kMuted.withAlpha(80)),
                    const SizedBox(height: 16),
                    const Text('No trips yet',
                        style: TextStyle(color: kTextMain, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text('Start tracking to record your first trip!',
                        style: TextStyle(color: kTextMuted, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _TripCard(
                    trip: _trips[i],
                    onDelete: () => _deleteTrip(_trips[i]),
                  ),
                  childCount: _trips.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Trip card ─────────────────────────────────────────────────────────────────
class _TripCard extends StatefulWidget {
  final Trip trip;
  final VoidCallback onDelete;
  const _TripCard({required this.trip, required this.onDelete});

  @override
  State<_TripCard> createState() => _TripCardState();
}

class _TripCardState extends State<_TripCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: kPrimary.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.location_on, color: kPrimary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.destinationName,
                          style: const TextStyle(
                              color: kTextMain,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              letterSpacing: -0.5),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(t.date,
                          style:
                              const TextStyle(color: kTextMuted, fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: kDanger, size: 20),
                  onPressed: widget.onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Stats chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _chip('${t.distanceKm.toStringAsFixed(2)} km', Icons.straighten, kPrimary),
                _chip('${t.avgSpeedKmh.toStringAsFixed(1)} km/h', Icons.speed, kSecondary),
                _chip('${t.durationMinutes} min', Icons.timer_outlined, kMuted),
              ],
            ),

            // Note (collapsible)
            if (t.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    const Icon(Icons.notes, color: kPrimary, size: 14),
                    const SizedBox(width: 4),
                    Text(_expanded ? 'Hide notes ▲' : 'View notes ▼',
                        style: const TextStyle(
                            color: kPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kPrimary.withAlpha(15),
                    borderRadius: BorderRadius.circular(10),
                    border: const Border(left: BorderSide(color: kPrimary, width: 2)),
                  ),
                  child: Text(t.note,
                      style: const TextStyle(
                          color: kTextMuted, fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
