import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../games/catalog.dart';
import '../games/x01.dart';
import '../models/player.dart';

/// Bestleistung und Bilanz eines Spielers in einem Trainings-/Minispiel-Modus.
class ModeStats {
  int played = 0;
  int wins = 0;
  num? best;

  Map<String, dynamic> toJson() => {'played': played, 'wins': wins, 'best': best};

  void merge(ModeStats o, {required bool lowerIsBetter}) {
    played += o.played;
    wins += o.wins;
    final ob = o.best;
    if (ob != null && (best == null || (lowerIsBetter ? ob < best! : ob > best!))) best = ob;
  }
  static ModeStats fromJson(Map<String, dynamic> j) => ModeStats()
    ..played = (j['played'] as num?)?.toInt() ?? 0
    ..wins = (j['wins'] as num?)?.toInt() ?? 0
    ..best = j['best'] as num?;
}

class PlayerStats {
  X01Stats x01 = X01Stats();
  Map<String, ModeStats> modes = {};

  /// Bilanz gegen Bots: Stufe → (Siege, Niederlagen).
  Map<String, List<int>> bots = {};

  /// Turniere: gespielt, gewonnen, Podestplätze.
  int tournaments = 0;
  int tournamentWins = 0;
  int podiums = 0;

  void merge(PlayerStats o) {
    x01.merge(o.x01);
    o.modes.forEach((k, v) {
      final lower = modes_lowerIsBetter(k);
      modes.putIfAbsent(k, ModeStats.new).merge(v, lowerIsBetter: lower);
    });
    o.bots.forEach((k, v) {
      final r = bots.putIfAbsent(k, () => [0, 0]);
      r[0] += v[0];
      r[1] += v[1];
    });
    tournaments += o.tournaments;
    tournamentWins += o.tournamentWins;
    podiums += o.podiums;
  }

  bool get isEmpty => x01.darts == 0 && x01.matches == 0 && modes.isEmpty && bots.isEmpty && tournaments == 0;

  Map<String, dynamic> toJson() => {
        'x01': x01.toJson(),
        'modes': modes.map((k, v) => MapEntry(k, v.toJson())),
        'bots': bots,
        'tournaments': tournaments,
        'tournamentWins': tournamentWins,
        'podiums': podiums,
      };

  static PlayerStats fromJson(Map<String, dynamic> j) {
    final s = PlayerStats();
    if (j['x01'] != null) s.x01 = X01Stats.fromJson(Map<String, dynamic>.from(j['x01'] as Map));
    final m = j['modes'] as Map? ?? {};
    m.forEach((k, v) => s.modes[k as String] = ModeStats.fromJson(Map<String, dynamic>.from(v as Map)));
    final b = j['bots'] as Map? ?? {};
    b.forEach((k, v) => s.bots[k as String] = [for (final x in v as List) (x as num).toInt()]);
    s.tournaments = (j['tournaments'] as num?)?.toInt() ?? 0;
    s.tournamentWins = (j['tournamentWins'] as num?)?.toInt() ?? 0;
    s.podiums = (j['podiums'] as num?)?.toInt() ?? 0;
    return s;
  }
}

// ignore: non_constant_identifier_names
bool modes_lowerIsBetter(String modeId) => modes.where((m) => m.id == modeId).firstOrNull?.lowerIsBetter ?? false;

/// Ein Eintrag im Match-Protokoll: der Beitrag eines Spielers aus einem Match.
///
/// [rid] kennzeichnet das Match (geräteübergreifend gleich), [oid] den Spieler
/// auf dem Ursprungsgerät. Zusammen ergeben sie den Schlüssel für den Abgleich –
/// derselbe Eintrag wird nie doppelt gezählt. [pid] ist der Spieler auf diesem Gerät.
class LogEntry {
  LogEntry({required this.rid, required this.oid, required this.pid, required this.t, required this.mode, required this.d});
  final String rid;
  final String oid;
  String pid;
  final int t;
  final String mode;
  final PlayerStats d;

  String get key => '$rid:$oid';

  Map<String, dynamic> toJson() => {'r': rid, 'o': oid, 'p': pid, 't': t, 'm': mode, 'd': d.toJson()};
  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        rid: j['r'] as String,
        oid: j['o'] as String,
        pid: j['p'] as String,
        t: (j['t'] as num).toInt(),
        mode: j['m'] as String,
        d: PlayerStats.fromJson(Map<String, dynamic>.from(j['d'] as Map)),
      );
}

/// Ein komplett gespeichertes Match (für Historie, Direktvergleich, Doppel-Analyse).
/// Spieler-IDs sind die des Ursprungsgeräts; Anzeige über [Store.localIdOf].
class MatchRecord {
  MatchRecord({
    required this.rid,
    required this.t,
    required this.mode,
    required this.options,
    required this.players,
    required this.start,
    required this.seed,
    required this.darts,
    this.tid,
  });

  final String rid;
  final int t;
  final String mode;
  final Map<String, dynamic> options;

  /// (ID, Name, Farbe)
  final List<(String, String, int)> players;
  final int start;
  final int seed;

  /// Kompakt: Feld * 4 + Multiplikator.
  final List<int> darts;
  final String? tid;

  List<String> get playerIds => [for (final p in players) p.$1];

  Map<String, dynamic> toJson() => {
        'r': rid,
        't': t,
        'm': mode,
        'o': options,
        'p': [
          for (final (id, n, c) in players) [id, n, c]
        ],
        's': start,
        'seed': seed,
        'd': darts,
        if (tid != null) 'tid': tid,
      };

  factory MatchRecord.fromJson(Map<String, dynamic> j) => MatchRecord(
        rid: j['r'] as String,
        t: (j['t'] as num).toInt(),
        mode: j['m'] as String,
        options: Map<String, dynamic>.from(j['o'] as Map),
        players: [
          for (final p in j['p'] as List) ((p as List)[0] as String, p[1] as String, (p[2] as num).toInt())
        ],
        start: (j['s'] as num).toInt(),
        seed: (j['seed'] as num).toInt(),
        darts: [for (final d in j['d'] as List) (d as num).toInt()],
        tid: j['tid'] as String?,
      );
}

/// Einfache lokale Ablage über SharedPreferences (JSON).
class Store {
  Store._();
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _log = null;
    _archive = null;
    _migrateLog();
  }

  // ---------------- Gerät ----------------
  /// Zufällige, dauerhafte Kennung dieses Geräts (für eindeutige Match-IDs).
  static String get deviceId {
    var id = _p.getString('deviceId');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
      _p.setString('deviceId', id);
    }
    return id;
  }

  static String get deviceName => _p.getString('deviceName') ?? 'Handy ${deviceId.substring(0, 4).toUpperCase()}';
  static set deviceName(String v) => _p.setString('deviceName', v.trim());

  static String newId(String prefix) =>
      '$prefix-$deviceId-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  // ---------------- Match-Protokoll ----------------
  static List<LogEntry>? _log;

  static List<LogEntry> get log {
    if (_log != null) return _log!;
    final raw = _p.getString('matchlog');
    final out = <LogEntry>[];
    if (raw != null) {
      for (final e in jsonDecode(raw) as List) {
        try {
          out.add(LogEntry.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    }
    return _log = out;
  }

  static void _saveLog() => _p.setString('matchlog', jsonEncode([for (final e in log) e.toJson()]));

  /// Fügt Einträge hinzu (bekannte werden übersprungen) und aktualisiert die
  /// Statistik der betroffenen Spieler. Liefert die Anzahl neuer Einträge.
  static int addEntries(Iterable<LogEntry> entries) {
    final keys = {for (final e in log) e.key};
    final touched = <String>{};
    var added = 0;
    for (final e in entries) {
      if (keys.contains(e.key)) continue;
      keys.add(e.key);
      log.add(e);
      touched.add(e.pid);
      added++;
    }
    if (added > 0) {
      _saveLog();
      touched.forEach(recomputeStats);
    }
    return added;
  }

  /// Statistik eines Spielers aus dem Protokoll neu berechnen.
  static void recomputeStats(String pid) {
    final s = PlayerStats();
    for (final e in log.where((e) => e.pid == pid)) {
      s.merge(e.d);
    }
    saveStats(pid, s);
  }

  /// Bisherige (summierte) Statistik einmalig als Grundstand ins Protokoll übernehmen.
  static void _migrateLog() {
    if (_p.getBool('logV1') == true) return;
    final entries = <LogEntry>[];
    for (final pr in profiles) {
      final raw = _p.getString('stats_${pr.id}');
      if (raw == null) continue;
      final s = PlayerStats.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (s.isEmpty) continue;
      entries.add(LogEntry(
          rid: 'base-$deviceId', oid: pr.id, pid: pr.id, t: DateTime.now().millisecondsSinceEpoch, mode: 'base', d: s));
    }
    if (entries.isNotEmpty) addEntries(entries);
    _p.setBool('logV1', true);
  }

  // ---------------- Match-Archiv ----------------
  static List<MatchRecord>? _archive;

  static List<MatchRecord> get archive {
    if (_archive != null) return _archive!;
    final raw = _p.getString('archive');
    final out = <MatchRecord>[];
    if (raw != null) {
      for (final e in jsonDecode(raw) as List) {
        try {
          out.add(MatchRecord.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    }
    return _archive = out;
  }

  /// Fügt Matches hinzu (bekannte werden übersprungen). Liefert die Anzahl neuer.
  static int addRecords(Iterable<MatchRecord> records) {
    final known = {for (final r in archive) r.rid};
    var added = 0;
    for (final r in records) {
      if (known.add(r.rid)) {
        archive.add(r);
        added++;
      }
    }
    if (added > 0) {
      archive.sort((a, b) => a.t.compareTo(b.t));
      _p.setString('archive', jsonEncode([for (final r in archive) r.toJson()]));
    }
    return added;
  }

  /// Lokale Spieler-ID zu einer (evtl. fremden) ID.
  static String localIdOf(String id) => knownLocalId(id) ?? id;

  // ---------------- Fremde Spieler-IDs ----------------
  /// Zuordnung: Spieler-ID eines anderen Geräts → Spieler-ID hier.
  static Map<String, String> get aliases {
    final raw = _p.getString('aliases');
    return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
  }

  static void setAlias(String foreignId, String localId) {
    final a = aliases;
    if (foreignId == localId) {
      a.remove(foreignId);
    } else {
      a[foreignId] = localId;
    }
    _p.setString('aliases', jsonEncode(a));
  }

  static Profile? profileById(String id) => profiles.where((p) => p.id == id).firstOrNull;

  /// Lokaler Spieler zu einer fremden ID (ohne Anlegen), sonst null.
  static String? knownLocalId(String foreignId) {
    if (profileById(foreignId) != null) return foreignId;
    final a = aliases[foreignId];
    if (a != null && profileById(a) != null) return a;
    return null;
  }

  /// Lokaler Spieler zu einer fremden ID – per Zuordnung, Name oder neu angelegt.
  static String resolveForeign(String foreignId, String name) {
    final known = knownLocalId(foreignId);
    if (known != null) return known;
    final byName = profiles.where((p) => p.name.toLowerCase() == name.trim().toLowerCase()).firstOrNull;
    if (byName != null) {
      setAlias(foreignId, byName.id);
      return byName.id;
    }
    addProfile(Profile(foreignId, name.trim()));
    return foreignId;
  }

  static void addProfile(Profile p) {
    final list = profiles;
    if (list.any((x) => x.id == p.id)) return;
    _saveProfiles([...list, p]);
  }

  // ---------------- Einstellungen ----------------
  static bool get soundOn => _p.getBool('sound') ?? true;
  static set soundOn(bool v) => _p.setBool('sound', v);

  /// Lautstärke 0..1.
  static double get volume => _p.getDouble('volume') ?? 1.0;
  static set volume(double v) => _p.setDouble('volume', v.clamp(0, 1));

  static bool get vibration => _p.getBool('vibration') ?? true;
  static set vibration(bool v) => _p.setBool('vibration', v);

  /// Große Jubel-Animationen (180, Ton+, Leg/Match-Gewinn).
  static bool get celebrations => _p.getBool('celebrations') ?? true;
  static set celebrations(bool v) => _p.setBool('celebrations', v);

  /// Single Out anbieten, wenn jemand im Finish festhängt.
  static bool get singleOutOffer => _p.getBool('singleOutOffer') ?? true;
  static set singleOutOffer(bool v) => _p.setBool('singleOutOffer', v);

  static bool get checkoutHint => _p.getBool('checkoutHint') ?? true;
  static set checkoutHint(bool v) => _p.setBool('checkoutHint', v);

  /// Bot-Tempo: 0 = langsam, 1 = normal, 2 = schnell.
  static int get botSpeed => _p.getInt('botSpeed') ?? 1;
  static set botSpeed(int v) => _p.setInt('botSpeed', v.clamp(0, 2));

  static String get themeId => _p.getString('theme') ?? 'arena';
  static set themeId(String v) => _p.setString('theme', v);

  /// Bei „Automatisch“ (themeId == 'auto'): dunkles Theme für die Nacht.
  static String get nightThemeId => _p.getString('nightTheme') ?? 'arena';
  static set nightThemeId(String v) => _p.setString('nightTheme', v);

  /// Schriftgröße: 1.0 normal, 1.15 groß.
  static double get fontScale => _p.getDouble('fontScale') ?? 1.0;
  static set fontScale(double v) => _p.setDouble('fontScale', v);

  /// Farbschwäche-Modus: andere Farben + Symbole für Double/Triple/Miss.
  static bool get colorblind => _p.getBool('colorblind') ?? false;
  static set colorblind(bool v) => _p.setBool('colorblind', v);

  /// Gekoppelte Handys gleichen Spielerdaten automatisch ab.
  static bool get autoSync => _p.getBool('autoSync') ?? true;
  static set autoSync(bool v) => _p.setBool('autoSync', v);

  /// Fester Raum-Code dieses Geräts (beim ersten Mal zufällig, danach gleich).
  static String get roomCode {
    var c = _p.getString('roomCode');
    if (c == null || !RegExp(r'^\d{4}$').hasMatch(c)) {
      c = (1000 + Random().nextInt(9000)).toString();
      _p.setString('roomCode', c);
    }
    return c;
  }

  static set roomCode(String v) {
    if (RegExp(r'^\d{4}$').hasMatch(v)) _p.setString('roomCode', v);
  }

  /// Geräte, mit denen dieses Gerät schon verbunden war (neueste zuerst).
  static List<KnownHost> get knownHosts {
    try {
      final raw = jsonDecode(_p.getString('knownHosts') ?? '[]') as List;
      return [for (final m in raw) KnownHost.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (_) {
      return [];
    }
  }

  static void _saveKnown(List<KnownHost> l) =>
      _p.setString('knownHosts', jsonEncode([for (final h in l.take(8)) h.toJson()]));

  /// Merkt sich einen Host (ein vorhandener Schlüssel bleibt erhalten).
  static void rememberHost(KnownHost h) {
    final old = knownHosts.where((x) => x.device == h.device).firstOrNull;
    final merged = h.key == null && old?.key != null ? h.withKey(old!.key) : h;
    _saveKnown([merged, ...knownHosts.where((x) => x.device != h.device)]);
  }

  /// Schlüssel für einen bekannten Host setzen oder löschen.
  static void setHostKey(String device, String? key) {
    final l = knownHosts;
    final i = l.indexWhere((h) => h.device == device);
    if (i < 0) return;
    l[i] = l[i].withKey(key);
    _saveKnown(l);
  }

  static void updateHost(String device, {required String address, required int port, String? code}) {
    final l = knownHosts;
    final i = l.indexWhere((h) => h.device == device);
    if (i < 0) return;
    final h = l[i];
    final c = code ?? h.code;
    if (h.address == address && h.port == port && h.code == c) return;
    l[i] = KnownHost(
        device: h.device, name: h.name, address: address, port: port, code: c, viewer: h.viewer, key: h.key, t: h.t);
    _saveKnown(l);
  }

  static void forgetHost(String device) => _saveKnown(knownHosts.where((x) => x.device != device).toList());

  /// Geräte, die sich mit diesem Host verbinden dürfen (device → Name).
  /// Erlaubte Geräte mit gemeinsamem Schlüssel: device → {n: Name, k: Schlüssel}.
  static Map<String, Map<String, String>> get _guests {
    try {
      final raw = jsonDecode(_p.getString('trustedGuests2') ?? '{}') as Map;
      return {for (final e in raw.entries) '${e.key}': Map<String, String>.from(e.value as Map)};
    } catch (_) {
      return {};
    }
  }

  static void _saveGuests(Map<String, Map<String, String>> g) => _p.setString('trustedGuests2', jsonEncode(g));

  /// Erlaubte Geräte (device → Name).
  static Map<String, String> get trustedGuests => {for (final e in _guests.entries) e.key: e.value['n'] ?? 'Gerät'};

  static bool isTrustedGuest(String device) => guestKey(device) != null;

  /// Gemeinsamer Schlüssel mit einem erlaubten Gerät.
  static String? guestKey(String device) => device.isEmpty ? null : _guests[device]?['k'];

  static void trustGuest(String device, String name, String key) =>
      _saveGuests({..._guests, device: {'n': name, 'k': key}});

  static void untrustGuest(String device) => _saveGuests(_guests..remove(device));

  /// Caller-Ansage.
  /// Ansagen mit den eigenen Sounds (80–180, Bullseye, 1, You win).
  static bool get announce => _p.getBool('announce') ?? true;
  static set announce(bool v) => _p.setBool('announce', v);

  /// Einführung beim ersten Start gesehen.
  static bool get onboarded => _p.getBool('onboarded') ?? false;
  static set onboarded(bool v) => _p.setBool('onboarded', v);

  /// Zuletzt gesehene App-Version (für „Was ist neu“).
  static String? get seenVersion => _p.getString('seenVersion');
  static set seenVersion(String? v) => v == null ? _p.remove('seenVersion') : _p.setString('seenVersion', v);

  // ---------------- Profile ----------------
  static List<Profile> get profiles {
    final raw = _p.getString('profiles');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static void _saveProfiles(List<Profile> list) =>
      _p.setString('profiles', jsonEncode(list.map((e) => e.toJson()).toList()));

  /// Findet ein Profil per Name (ohne Groß/Klein) oder legt es an.
  static Profile ensureProfile(String name) {
    final list = profiles;
    final existing =
        list.where((p) => p.name.toLowerCase() == name.trim().toLowerCase()).firstOrNull;
    if (existing != null) return existing;
    final id = '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';
    final p = Profile(id, name.trim());
    _saveProfiles([...list, p]);
    return p;
  }

  static void deleteProfile(String id) {
    _saveProfiles(profiles.where((p) => p.id != id).toList());
    _p.remove('stats_$id');
    log.removeWhere((e) => e.pid == id);
    _saveLog();
  }

  // ---------------- Statistik ----------------
  static PlayerStats statsFor(String id) {
    final raw = _p.getString('stats_$id');
    if (raw == null) return PlayerStats();
    return PlayerStats.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  static void saveStats(String id, PlayerStats s) =>
      _p.setString('stats_$id', jsonEncode(s.toJson()));

  // ---------------- Letztes Setup ----------------
  static Map<String, dynamic>? get lastSetup {
    final raw = _p.getString('lastSetup');
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static set lastSetup(Map<String, dynamic>? v) =>
      v == null ? _p.remove('lastSetup') : _p.setString('lastSetup', jsonEncode(v));

  static Map<String, dynamic> optionsFor(String modeId) {
    final raw = _p.getString('opts_$modeId');
    return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static void saveOptions(String modeId, Map<String, dynamic> o) =>
      _p.setString('opts_$modeId', jsonEncode(o));

  // ---------------- Laufendes Match ----------------
  /// Anzeige: welche Scheibe gezeigt wird (0 = alle laufenden Spiele).
  static int get viewerBoard => _p.getInt('viewerBoard') ?? 0;
  static set viewerBoard(int v) => _p.setInt('viewerBoard', v);

  /// Letzte Kopplung (Raum offen bzw. verbunden) mit Zeitstempel `ts` (ms) –
  /// für die automatische Wiederherstellung nach Absturz/Neustart.
  static Map<String, dynamic>? get linkSession {
    final raw = _p.getString('linkSession');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static set linkSession(Map<String, dynamic>? v) =>
      v == null ? _p.remove('linkSession') : _p.setString('linkSession', jsonEncode(v));

  static Map<String, dynamic>? get activeMatch {
    final raw = _p.getString('activeMatch');
    return raw == null ? null : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  static set activeMatch(Map<String, dynamic>? v) =>
      v == null ? _p.remove('activeMatch') : _p.setString('activeMatch', jsonEncode(v));

  // ---------------- Turniere ----------------
  static List<Map<String, dynamic>> get tournaments {
    final raw = _p.getString('tournaments');
    if (raw == null) return [];
    return [for (final e in jsonDecode(raw) as List) Map<String, dynamic>.from(e as Map)];
  }

  static set tournaments(List<Map<String, dynamic>> v) => _p.setString('tournaments', jsonEncode(v));

  // ---------------- Daten verwalten ----------------
  static void resetStats() {
    for (final k in _p.getKeys().where((k) => k.startsWith('stats_')).toList()) {
      _p.remove(k);
    }
    log.clear();
    _saveLog();
    _p.remove('archive');
    _archive = null;
  }

  static void deleteAllPlayers() {
    resetStats();
    _p.remove('profiles');
    _p.remove('lastSetup');
    _p.remove('aliases');
    _p.remove('archive');
    _archive = null;
  }

  static const _backupKeys = {'profiles', 'tournaments', 'lastSetup', 'matchlog', 'aliases', 'logV1', 'archive'};

  static bool _inBackup(String k) =>
      _backupKeys.contains(k) || k.startsWith('stats_') || k.startsWith('opts_');

  /// Alle Spieler, Statistiken, Turniere und Spiel-Einstellungen als JSON.
  static String exportBackup() {
    final data = <String, dynamic>{};
    for (final k in _p.getKeys().where(_inBackup)) {
      data[k] = _p.get(k);
    }
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'darts_counter',
      'version': 1,
      'created': DateTime.now().toIso8601String(),
      'data': data,
    });
  }

  /// Ersetzt die gespeicherten Daten durch ein Backup. Liefert die Anzahl der Spieler.
  static Future<int> importBackup(String json) async {
    final root = jsonDecode(json);
    if (root is! Map || root['app'] != 'darts_counter' || root['data'] is! Map) {
      throw const FormatException('Keine Darts-Counter-Sicherung');
    }
    final data = Map<String, dynamic>.from(root['data'] as Map);
    for (final k in _p.getKeys().where(_inBackup).toList()) {
      await _p.remove(k);
    }
    for (final e in data.entries) {
      if (!_inBackup(e.key)) continue;
      final v = e.value;
      if (v is String) {
        await _p.setString(e.key, v);
      } else if (v is bool) {
        await _p.setBool(e.key, v);
      } else if (v is int) {
        await _p.setInt(e.key, v);
      } else if (v is double) {
        await _p.setDouble(e.key, v);
      }
    }
    _log = null;
    _archive = null;
    _migrateLog();
    return profiles.length;
  }
}


/// Ein Gerät, mit dem schon einmal gekoppelt wurde.
class KnownHost {
  KnownHost({
    required this.device,
    required this.name,
    required this.address,
    required this.port,
    required this.code,
    this.viewer = false,
    this.key,
    int? t,
  }) : t = t ?? DateTime.now().millisecondsSinceEpoch;

  /// Gemeinsamer Schlüssel nach der ersten Erlaubnis (dann ohne Code verbinden).
  final String? key;

  KnownHost withKey(String? k) =>
      KnownHost(device: device, name: name, address: address, port: port, code: code, viewer: viewer, key: k, t: t);

  final String device;
  final String name;
  final String address;
  final int port;
  final String code;

  /// Zuletzt als reine Anzeige verbunden.
  final bool viewer;
  final int t;

  Map<String, dynamic> toJson() =>
      {'device': device, 'name': name, 'address': address, 'port': port, 'code': code, 'viewer': viewer, 't': t, 'key': key};

  factory KnownHost.fromJson(Map<String, dynamic> j) => KnownHost(
        device: j['device'] as String,
        name: j['name'] as String? ?? 'Gerät',
        address: j['address'] as String,
        port: (j['port'] as num?)?.toInt() ?? 47123,
        code: j['code'] as String,
        viewer: j['viewer'] as bool? ?? false,
        key: j['key'] as String?,
        t: (j['t'] as num?)?.toInt(),
      );
}
