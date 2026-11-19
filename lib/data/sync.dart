import 'dart:convert';

import '../games/tournament.dart';
import '../models/player.dart';
import 'storage.dart';
import 'tournament_store.dart';

/// Was mit einem eingehenden Spieler passieren soll.
enum MergeKind { merge, create, skip }

class MergeChoice {
  MergeChoice(this.kind, [this.localId]);
  MergeKind kind;
  String? localId;
}

/// Ein Datenpaket zum Austausch zwischen Geräten.
class SharePackage {
  SharePackage({
    required this.device,
    required this.deviceName,
    required this.created,
    required this.profiles,
    required this.entries,
    required this.tournaments,
    this.archive = const [],
  });

  final String device;
  final String deviceName;
  final DateTime created;
  final List<Profile> profiles;
  final List<LogEntry> entries;
  final List<Map<String, dynamic>> tournaments;
  final List<MatchRecord> archive;

  static const kind = 'players';

  Map<String, dynamic> toJson() => {
        'app': 'darts_counter',
        'kind': kind,
        'v': 1,
        'device': device,
        'deviceName': deviceName,
        'created': created.toIso8601String(),
        'profiles': [for (final p in profiles) p.toJson()],
        'entries': [for (final e in entries) e.toJson()],
        'tournaments': tournaments,
        'archive': [for (final r in archive) r.toJson()],
      };

  String encode() => jsonEncode(toJson());

  static bool looksLike(Object? root) => root is Map && root['app'] == 'darts_counter' && root['kind'] == kind;

  factory SharePackage.fromJson(Map<String, dynamic> j) => SharePackage(
        device: j['device'] as String,
        deviceName: j['deviceName'] as String? ?? 'Anderes Gerät',
        created: DateTime.parse(j['created'] as String),
        profiles: [for (final p in j['profiles'] as List) Profile.fromJson(Map<String, dynamic>.from(p as Map))],
        entries: [for (final e in j['entries'] as List) LogEntry.fromJson(Map<String, dynamic>.from(e as Map))],
        tournaments: [for (final t in j['tournaments'] as List? ?? []) Map<String, dynamic>.from(t as Map)],
        archive: [
          for (final r in j['archive'] as List? ?? []) _tryRecord(r),
        ].whereType<MatchRecord>().toList(),
      );

  static MatchRecord? _tryRecord(Object? r) {
    try {
      return MatchRecord.fromJson(Map<String, dynamic>.from(r as Map));
    } catch (_) {
      return null;
    }
  }

  /// Anzahl der Einträge je eingehendem Spieler.
  int entriesOf(String pid) => entries.where((e) => e.pid == pid).length;

  /// Einträge, die hier noch fehlen.
  int newEntriesOf(String pid) {
    final known = {for (final e in Store.log) e.key};
    return entries.where((e) => e.pid == pid && !known.contains(e.key)).length;
  }
}

class Sync {
  Sync._();

  /// Paket für die gewählten Spieler (optional mit Turnieren, an denen sie beteiligt sind).
  static SharePackage build(Set<String> profileIds, {bool tournaments = false}) {
    final profs = Store.profiles.where((p) => profileIds.contains(p.id)).toList();
    final entries = Store.log.where((e) => profileIds.contains(e.pid)).toList();
    final ts = <Map<String, dynamic>>[];
    if (tournaments) {
      for (final t in TournamentStore.all()) {
        if (t.players.any((p) => profileIds.contains(p.profileId))) ts.add(t.toJson());
      }
    }
    return SharePackage(
      device: Store.deviceId,
      deviceName: Store.deviceName,
      created: DateTime.now(),
      profiles: profs,
      entries: entries,
      tournaments: ts,
      archive: [
        for (final r in Store.archive)
          if (r.playerIds.any((id) => profileIds.contains(Store.localIdOf(id)))) r,
      ],
    );
  }

  /// Vorschlag: bekannter Spieler oder gleicher Name → zusammenführen, sonst neu anlegen.
  static Map<String, MergeChoice> suggest(SharePackage pkg) {
    final local = Store.profiles;
    return {
      for (final p in pkg.profiles)
        p.id: () {
          final known = Store.knownLocalId(p.id);
          if (known != null) return MergeChoice(MergeKind.merge, known);
          final byName = local.where((l) => l.name.toLowerCase() == p.name.toLowerCase()).firstOrNull;
          if (byName != null) return MergeChoice(MergeKind.merge, byName.id);
          return MergeChoice(MergeKind.create);
        }(),
    };
  }

  /// Übernimmt das Paket. Liefert (neue Einträge, neue Spieler, Turniere).
  static (int, int, int) apply(SharePackage pkg, Map<String, MergeChoice> choices) {
    final map = <String, String>{};
    var created = 0;
    for (final p in pkg.profiles) {
      final c = choices[p.id] ?? MergeChoice(MergeKind.create);
      switch (c.kind) {
        case MergeKind.skip:
          continue;
        case MergeKind.merge:
          final target = c.localId ?? p.id;
          Store.setAlias(p.id, target);
          map[p.id] = target;
        case MergeKind.create:
          if (Store.profileById(p.id) != null) {
            map[p.id] = p.id;
            continue;
          }
          var name = p.name;
          final names = {for (final l in Store.profiles) l.name.toLowerCase()};
          for (var k = 2; names.contains(name.toLowerCase()); k++) {
            name = '${p.name} ($k)';
          }
          Store.addProfile(Profile(p.id, name));
          map[p.id] = p.id;
          created++;
      }
    }
    final entries = [
      for (final e in pkg.entries)
        if (map[e.pid] != null) LogEntry(rid: e.rid, oid: e.oid, pid: map[e.pid]!, t: e.t, mode: e.mode, d: e.d),
    ];
    final added = Store.addEntries(entries);
    Store.addRecords(pkg.archive);

    var tCount = 0;
    for (final tj in pkg.tournaments) {
      try {
        final incoming = Tournament.fromJson(tj);
        final players = [
          for (final p in incoming.players)
            TPlayer(map[p.profileId] ?? Store.knownLocalId(p.profileId) ?? p.profileId, p.name),
        ];
        final mapped = Tournament.fromJson({
          ...tj,
          'players': [for (final p in players) p.toJson()],
        });
        final existing = TournamentStore.byId(mapped.id);
        if (existing == null || mapped.playedCount > existing.playedCount) {
          TournamentStore.save(mapped);
          tCount++;
        }
      } catch (_) {}
    }
    return (added, created, tCount);
  }
}

/// Automatischer Abgleich zwischen gekoppelten Geräten.
class AutoSync {
  AutoSync._();

  /// Was dieses Gerät hat (nur Schlüssel, keine Daten).
  static Map<String, dynamic> have() => {
        'keys': [for (final e in Store.log) e.key],
        'tours': {for (final t in TournamentStore.all()) t.id: t.playedCount},
        'arch': [for (final a in Store.archive) a.rid],
      };

  /// Paket mit allem, was dem anderen Gerät laut [other] fehlt (oder null, wenn nichts fehlt).
  static SharePackage? missingFor(Map<String, dynamic> other) {
    final keys = {for (final k in other['keys'] as List? ?? const []) k as String};
    final tours = Map<String, dynamic>.from(other['tours'] as Map? ?? const {});
    final arch = {for (final k in other['arch'] as List? ?? const []) k as String};
    final entries = Store.log.where((e) => !keys.contains(e.key)).toList();
    final ts = [
      for (final t in TournamentStore.all())
        if (!tours.containsKey(t.id) || t.playedCount > (tours[t.id] as num).toInt()) t.toJson(),
    ];
    final records = Store.archive.where((a) => !arch.contains(a.rid)).toList();
    if (entries.isEmpty && ts.isEmpty && records.isEmpty) return null;
    final pids = {for (final e in entries) e.pid};
    for (final r in records) {
      pids.addAll(r.playerIds);
    }
    final profiles = Store.profiles.where((p) => pids.contains(p.id)).toList();
    return SharePackage(
      device: Store.deviceId,
      deviceName: Store.deviceName,
      created: DateTime.now(),
      profiles: profiles,
      entries: entries,
      tournaments: ts,
      archive: records,
    );
  }

  /// Übernimmt ein Paket ohne Vorschau. Nur bei gleichem Namen ohne bekannte
  /// Zuordnung wird [confirm] gefragt (true = derselbe Spieler).
  static Future<(int, int, int)> apply(SharePackage pkg,
      {Future<bool> Function(Profile incoming, Profile local)? confirm}) async {
    final choices = <String, MergeChoice>{};
    for (final p in pkg.profiles) {
      final known = Store.knownLocalId(p.id);
      if (known != null) {
        choices[p.id] = MergeChoice(MergeKind.merge, known);
        continue;
      }
      final byName =
          Store.profiles.where((l) => l.name.toLowerCase() == p.name.toLowerCase()).firstOrNull;
      if (byName == null) {
        choices[p.id] = MergeChoice(MergeKind.create);
        continue;
      }
      final same = confirm == null ? true : await confirm(p, byName);
      choices[p.id] = same ? MergeChoice(MergeKind.merge, byName.id) : MergeChoice(MergeKind.create);
    }
    return Sync.apply(pkg, choices);
  }
}
