import 'package:material_ui/material_ui.dart';

import '../data/sound.dart';
import '../data/storage.dart';
import '../net/link.dart';
import 'link_coordinator.dart';
import 'theme.dart';

/// Handys im WLAN / Hotspot koppeln.
class LinkScreen extends StatefulWidget {
  const LinkScreen({super.key});

  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {
  final _name = TextEditingController(text: Store.deviceName);
  bool _busy = false;

  Link get l => Link.I;

  @override
  void initState() {
    super.initState();
    l.addListener(_onLink);
    if (l.role == LinkRole.none) l.startDiscovery();
  }

  @override
  void dispose() {
    l.removeListener(_onLink);
    if (l.role != LinkRole.client) l.stopDiscovery();
    _name.dispose();
    super.dispose();
  }

  void _onLink() {
    if (mounted) setState(() {});
  }

  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  void _saveName() {
    final v = _name.text.trim();
    if (v.isNotEmpty) Store.deviceName = v;
  }

  Future<void> _host() async {
    _saveName();
    setState(() => _busy = true);
    try {
      l.stopDiscovery();
      await l.startHost();
      Haptics.medium();
    } catch (e) {
      _snack('Raum konnte nicht geöffnet werden: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _join(String address, int port, String code, String? name,
      {bool viewer = false, String? hostDevice}) async {
    _saveName();
    setState(() => _busy = true);
    LinkCoordinator.viewer = viewer;
    final ok = await l.join(address, port, code, name: name, viewer: viewer, hostDevice: hostDevice);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Haptics.medium();
      l.stopDiscovery();
      if (viewer) {
        LinkCoordinator.startViewer();
        return;
      }
      _snack('Verbunden mit ${name ?? address}');
    } else {
      _snack('Keine Verbindung – Code falsch oder Gerät nicht erreichbar (beide im selben WLAN?)');
      l.startDiscovery();
    }
  }

  /// Fragt den Raum-Code (er wird aus Sicherheitsgründen nicht mehr übers Netz verraten).
  Future<String?> _askCode(String name) async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Code für „$name“'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Der Code steht auf dem anderen Gerät unter „Raum eröffnen“. Du musst ihn nur einmal eingeben.',
                style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              onSubmitted: (t) => Navigator.pop(c, t.trim()),
              style: const TextStyle(fontFamily: numFont, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: 8),
              decoration: const InputDecoration(labelText: 'Raum-Code', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Beitreten')),
        ],
      ),
    );
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> _joinRoom(Room r, {bool viewer = false}) async {
    final known = Store.knownHosts.where((h) => h.device == r.device).firstOrNull;
    if (known?.key != null) {
      // schon gekoppelt: per Schlüssel, ohne Code
      await _join(r.address, r.port, '', r.name, viewer: viewer, hostDevice: r.device);
      return;
    }
    final code = r.code ?? await _askCode(r.name);
    if (code == null) return;
    await _join(r.address, r.port, code, r.name, viewer: viewer);
  }

  /// Bekanntes Gerät: erst die aktuell gefundene Adresse, dann die gespeicherte probieren.
  Future<void> _joinKnown(KnownHost h, {required bool viewer}) async {
    final found = l.rooms.value.where((r) => r.device == h.device).firstOrNull;
    final tries = <(String, int, String)>[
      if (found != null) (found.address, found.port, found.code ?? h.code),
      if (found == null || found.address != h.address) (h.address, h.port, h.code),
    ];
    _saveName();
    setState(() => _busy = true);
    LinkCoordinator.viewer = viewer;
    var ok = false;
    for (final (a, p, c) in tries) {
      ok = await l.join(a, p, c, name: h.name, viewer: viewer, hostDevice: h.key != null ? h.device : null);
      if (ok) break;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Haptics.medium();
      l.stopDiscovery();
      if (viewer) {
        LinkCoordinator.startViewer();
        return;
      }
      _snack('Verbunden mit ${h.name}');
    } else {
      _snack('${h.name} ist nicht erreichbar – ist dort der Raum offen und beide im selben WLAN?');
      l.startDiscovery();
    }
  }

  /// Zwei klare Knöpfe: mitspielen (eintragen) oder nur anzeigen (Punktetafel).
  Widget _roleButtons({required VoidCallback onPlay, required VoidCallback onView, bool viewerFirst = false}) => Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : onPlay,
              icon: const Icon(Icons.sports_esports_rounded, size: 18),
              label: const Text('Mitspielen'),
              style: FilledButton.styleFrom(
                backgroundColor: viewerFirst ? C.surface3 : C.dbl,
                foregroundColor: viewerFirst ? C.text : C.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : onView,
              icon: const Icon(Icons.tv_rounded, size: 18),
              label: const Text('Nur anzeigen'),
              style: FilledButton.styleFrom(
                backgroundColor: viewerFirst ? C.accent : C.surface3,
                foregroundColor: viewerFirst ? C.onAccent : C.text,
              ),
            ),
          ),
        ],
      );

  Future<void> _forget(KnownHost h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${h.name} vergessen?'),
        content: const Text('Das Gerät verschwindet aus „Bekannte Geräte“. Du kannst es jederzeit neu koppeln.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Vergessen')),
        ],
      ),
    );
    if (ok == true) setState(() => Store.forgetHost(h.device));
  }

  Widget _knownTile(KnownHost h, List<Room> rooms) {
    final near = rooms.any((r) => r.device == h.device);
    final col = near ? C.dbl : C.muted;
    return GlowCard(
      tint: near ? C.dbl : null,
      strength: near ? 0.12 : 0.05,
      borderAlpha: near ? 0.45 : 0.2,
      onTap: _busy ? null : () => _joinKnown(h, viewer: h.viewer),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(h.viewer ? Icons.tv_rounded : Icons.phone_android_rounded, color: col, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      near ? 'In der Nähe · Raum ${h.code}' : 'Zuletzt ${h.address} · Raum ${h.code}',
                      style: TextStyle(color: near ? C.dbl : C.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '${h.name} vergessen',
                onPressed: () => _forget(h),
                icon: Icon(Icons.delete_outline_rounded, color: C.muted2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _roleButtons(
            onPlay: () => _joinKnown(h, viewer: false),
            onView: () => _joinKnown(h, viewer: true),
            viewerFirst: h.viewer,
          ),
        ],
      ),
    );
  }

  Future<void> _manual() async {
    final addr = TextEditingController();
    final code = TextEditingController();
    var viewer = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raum manuell beitreten'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: addr,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Adresse', hintText: 'z. B. 192.168.0.23'),
            ),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(labelText: 'Raum-Code', counterText: ''),
            ),
            StatefulBuilder(
              builder: (_, set) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: viewer,
                onChanged: (v) => set(() => viewer = v ?? false),
                title: const Text('Nur anzeigen (Scoreboard)'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Beitreten')),
        ],
      ),
    );
    if (ok != true) return;
    final a = addr.text.trim();
    var host = a;
    var port = Link.defaultPort;
    if (a.contains(':')) {
      host = a.split(':').first;
      port = int.tryParse(a.split(':').last) ?? port;
    }
    await _join(host, port, code.text.trim(), null, viewer: viewer);
  }

  Future<void> _leave() async {
    await l.stop();
    l.startDiscovery();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Handys koppeln')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Gekoppelte Handys zeigen dasselbe Spiel, und auf jedem kann eingetragen werden. '
              'Alle Handys müssen im selben WLAN sein – oder eins macht einen Hotspot.',
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
          ),
          GlowCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            strength: 0.04,
            child: TextField(
              controller: _name,
              maxLength: 20,
              onSubmitted: (_) => _saveName(),
              onEditingComplete: _saveName,
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'Name dieses Handys',
                counterText: '',
                border: InputBorder.none,
                labelStyle: TextStyle(color: C.muted),
              ),
            ),
          ),
          const SizedBox(height: 6),
          switch (l.role) {
            LinkRole.host => _hostView(),
            LinkRole.client => _clientView(),
            LinkRole.none => _idleView(),
          },
        ],
      ),
    );
  }

  Widget _idleView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlowCard(
        strength: 0.14,
        borderAlpha: 0.5,
        onTap: _busy ? null : _host,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: C.accentGradient),
              child: Icon(Icons.wifi_tethering_rounded, color: C.onAccent, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Raum eröffnen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('Dieses Handy wird der Host', style: TextStyle(color: C.muted, fontSize: 13)),
                ],
              ),
            ),
            if (_busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
      const SizedBox(height: 8),
      ValueListenableBuilder<List<Room>>(
        valueListenable: l.rooms,
        builder: (_, all, _) {
          final known = Store.knownHosts;
          if (known.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Bekannte Geräte'),
              for (final h in known) ...[_knownTile(h, all), const SizedBox(height: 8)],
            ],
          );
        },
      ),
      ValueListenableBuilder<(int, int)>(
            valueListenable: l.scanProgress,
            builder: (_, p, _) => SectionTitle('Räume in der Nähe',
                trailing: p.$2 == 0 || p.$1 >= p.$2 ? 'suche …' : 'durchsucht ${p.$1} / ${p.$2}'),
          ),
      ValueListenableBuilder<List<Room>>(
        valueListenable: l.rooms,
        builder: (_, all, _) {
          final knownIds = {for (final h in Store.knownHosts) h.device};
          final rooms = all.where((r) => !knownIds.contains(r.device)).toList();
          return Column(
            children: [
              if (rooms.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: C.muted)),
                      const SizedBox(width: 10),
                      Text(
                        all.isEmpty ? 'Noch kein Raum gefunden' : 'Keine weiteren Räume',
                        style: TextStyle(color: C.muted),
                      ),
                    ],
                  ),
                ),
              for (final r in rooms) ...[
                GlowCard(
                  tint: C.dbl,
                  strength: 0.10,
                  borderAlpha: 0.4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.phone_android_rounded, color: C.dbl, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                Text(r.address, style: TextStyle(color: C.muted, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _roleButtons(
                        onPlay: () => _joinRoom(r),
                        onView: () => _joinRoom(r, viewer: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
      TextButton.icon(
        onPressed: _busy ? null : _manual,
        icon: const Icon(Icons.keyboard_rounded),
        label: const Text('Adresse und Code eingeben', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    ],
  );

  Widget _hostView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlowCard(
        tint: C.dbl,
        strength: 0.14,
        borderAlpha: 0.5,
        child: Column(
          children: [
            Text(
              'RAUM-CODE',
              style: TextStyle(color: C.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
            Text(
              l.code ?? '----',
              style: const TextStyle(
                fontFamily: numFont,
                fontSize: 64,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
                height: 1.1,
              ),
            ),
            Text(
              l.addresses.isEmpty
                  ? 'Keine Netzwerkadresse – WLAN oder Hotspot an?'
                  : 'Adresse: ${l.addresses.map((a) => l.port == Link.defaultPort ? a : '$a:${l.port}').join('  ·  ')}',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Der Code bleibt immer gleich (änderbar unter Einstellungen → Daten).',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.muted2, fontSize: 12),
            ),
          ],
        ),
      ),
      SectionTitle('Verbunden', trailing: l.peerCount == 0 ? '1 Gerät' : '${l.peerCount + 1} Geräte'),
      _deviceTile('${Store.deviceName} (dieses Handy, Host)', host: true),
      for (final n in l.peerNames) _deviceTile(n),
      if (l.peerCount == 0)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Auf dem anderen Handy: „Handys koppeln“ öffnen und den Raum antippen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        'Starte jetzt einfach ein Spiel oder öffne ein Turnier – die anderen Handys zeigen es automatisch.',
        textAlign: TextAlign.center,
        style: TextStyle(color: C.muted2, fontSize: 13),
      ),
      const SizedBox(height: 12),
      _syncCard(),
      const SizedBox(height: 12),
      _trustedCard(),
      const SizedBox(height: 12),
      _leaveButton('Raum schließen'),
    ],
  );

  Widget _clientView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlowCard(
        tint: l.isConnected ? C.dbl : C.danger,
        strength: 0.14,
        borderAlpha: 0.5,
        child: Row(
          children: [
            Icon(
              l.isConnected ? Icons.link_rounded : Icons.link_off_rounded,
              color: l.isConnected ? C.dbl : C.danger,
              size: 34,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isConnected ? 'Verbunden mit ${l.hostName ?? l.hostAddress}' : l.status,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Raum ${l.code} · ${l.isConnected ? '${l.peerCount + 1} Geräte' : 'warte …'}',
                    style: TextStyle(color: C.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (l.isConnected) ...[
        const SizedBox(height: 10),
        GlowCard(
          strength: 0.08,
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(
            children: [
              Icon(LinkCoordinator.viewer ? Icons.tv_rounded : Icons.sports_esports_rounded, color: C.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nur anzeigen (Punktetafel)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                        LinkCoordinator.viewer
                            ? 'Dieses Gerät zeigt nur den Spielstand, eintragen geht hier nicht.'
                            : 'Aus: Auf diesem Gerät kann auch eingetragen werden.',
                        style: TextStyle(color: C.muted, fontSize: 13)),
                  ],
                ),
              ),
              Switch(
                value: LinkCoordinator.viewer,
                onChanged: (v) => setState(() => LinkCoordinator.setViewer(v)),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'Spiele, die auf einem gekoppelten Handy starten, erscheinen hier automatisch.',
        textAlign: TextAlign.center,
        style: TextStyle(color: C.muted2, fontSize: 13),
      ),
      const SizedBox(height: 12),
      if (l.isConnected) ...[_syncCard(), const SizedBox(height: 12)],
      _leaveButton('Trennen'),
    ],
  );

  /// Geräte, die ohne Nachfrage beitreten dürfen.
  Widget _trustedCard() {
    final trusted = Store.trustedGuests;
    return GlowCard(
      strength: 0.06,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, color: C.dbl),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Erlaubte Geräte', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            trusted.isEmpty
                ? 'Neue Geräte müssen beim ersten Beitritt hier bestätigt werden.'
                : 'Diese Geräte dürfen ohne Nachfrage beitreten. Neue Geräte musst du bestätigen.',
            style: TextStyle(color: C.muted, fontSize: 13),
          ),
          for (final e in trusted.entries)
            Row(
              children: [
                const SizedBox(width: 4),
                Icon(Icons.devices_rounded, size: 18, color: C.muted2),
                const SizedBox(width: 8),
                Expanded(child: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(
                  tooltip: '${e.value} nicht mehr erlauben',
                  icon: Icon(Icons.remove_circle_outline_rounded, color: C.danger),
                  onPressed: () => setState(() => Store.untrustGuest(e.key)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _syncCard() {
    final enabled = l.isConnected && l.peerCount > 0;
    return GlowCard(
      strength: 0.08,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.sync_rounded, color: C.accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Spielerdaten abgleichen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ValueListenableBuilder<String?>(
            valueListenable: LinkCoordinator.lastSync,
            builder: (_, v, _) => Text(
              v ??
                  (Store.autoSync
                      ? 'Läuft automatisch beim Koppeln und nach jedem Spiel.'
                      : 'Automatischer Abgleich ist aus (Einstellungen → Daten).'),
              style: TextStyle(color: C.muted, fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: Key3(
              semantics: 'Jetzt abgleichen',
              enabled: enabled,
              onTap: enabled ? LinkCoordinator.syncNow : null,
              gradient: C.accentGradient,
              borderColor: Colors.transparent,
              radius: 14,
              child: Text(
                'Jetzt abgleichen',
                style: TextStyle(color: C.onAccent, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(String name, {bool host = false}) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Icon(host ? Icons.router_rounded : Icons.phone_android_rounded, color: host ? C.accent : C.dbl),
        const SizedBox(width: 10),
        Expanded(
          child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );

  Widget _leaveButton(String label) => SizedBox(
    height: 52,
    child: OutlinedButton.icon(
      onPressed: _leave,
      icon: const Icon(Icons.close_rounded),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        foregroundColor: C.danger,
        side: BorderSide(color: C.danger.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
