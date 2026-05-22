import 'package:sqflite/sqflite.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/trip.dart';

class DatabaseService {
  static Database? _db;
  static const _version = 1;
  static const _table = 'trips';

  static Future<Database> get db async => _db ??= await _open();

  static Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = '$dir/km_tracker.db';
    return openDatabase(
      path,
      version: _version,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE $_table (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          date             TEXT    NOT NULL,
          distance_km      REAL    NOT NULL,
          destination_name TEXT    NOT NULL,
          avg_speed_kmh    REAL    NOT NULL,
          duration_minutes INTEGER NOT NULL DEFAULT 0,
          note             TEXT    DEFAULT '',
          path_json        TEXT    DEFAULT '',
          user_id          TEXT    NOT NULL
        )
      '''),
    );
  }

  static Future<int> insert(Trip trip) async {
    final database = await db;
    return database.insert(_table, trip.toMap());
  }

  static Future<List<Trip>> getAll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final database = await db;
    final rows = await database.query(_table,
        where: 'user_id = ?', whereArgs: [uid], orderBy: 'id DESC');
    return rows.map(Trip.fromMap).toList();
  }

  static Future<void> delete(int id) async {
    final database = await db;
    await database.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteAll() async {
    final database = await db;
    await database.delete(_table);
  }

  static Future<double> totalKm() async {
    final trips = await getAll();
    return trips.fold<double>(0.0, (sum, t) => sum + t.distanceKm);
  }
}
