/// Gespeichertes Spielerprofil (für Langzeitstatistik).
class Profile {
  final String id;
  final String name;

  const Profile(this.id, this.name);

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(j['id'] as String, j['name'] as String);
}

/// Ein Spieler innerhalb eines Matches.
class GamePlayer {
  final String profileId;
  final String name;
  final int color; // ARGB

  const GamePlayer(this.profileId, this.name, this.color);

  Map<String, dynamic> toJson() => {'p': profileId, 'n': name, 'c': color};
  factory GamePlayer.fromJson(Map<String, dynamic> j) =>
      GamePlayer(j['p'] as String, j['n'] as String, j['c'] as int);
}
