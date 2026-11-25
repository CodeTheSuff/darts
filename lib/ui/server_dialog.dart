import 'package:material_ui/material_ui.dart';

import '../data/storage.dart';
import '../net/server_config.dart';
import 'theme.dart';

/// Einstellungen → „Server“: eigene Server-Adresse eintragen, testen oder auf den Standard
/// zurücksetzen. Im Normalfall braucht das niemand – der Standard-Server ist eingebaut.
Future<void> showServerDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _ServerDialog(),
    );

class _ServerDialog extends StatefulWidget {
  const _ServerDialog();

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final _ctl = TextEditingController(text: Store.serverUrl ?? '');
  String? _result;
  bool _ok = true;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _save() {
    final v = _ctl.text.trim();
    final norm = v.isEmpty ? null : ServerConfig.normalize(v);
    // Standard-Adresse eingetippt: nichts Eigenes speichern.
    Store.serverUrl = norm == defaultServerUrl ? null : norm;
    _ctl.text = Store.serverUrl ?? '';
    setState(() {
      _ok = true;
      _result = Store.serverUrl == null ? 'Standard-Server wird benutzt.' : 'Gespeichert.';
    });
  }

  void _reset() {
    Store.serverUrl = null;
    _ctl.text = '';
    setState(() {
      _ok = true;
      _result = 'Zurückgesetzt – Standard-Server wird benutzt.';
    });
  }

  Future<void> _test() async {
    final v = _ctl.text.trim();
    setState(() {
      _ok = true;
      _result = 'Teste …';
    });
    final err = await ServerConfig.test(v.isEmpty ? null : v);
    if (!mounted) return;
    setState(() {
      _ok = err == null;
      _result = err ?? 'Server erreichbar.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Aktuell: ${ServerConfig.url}', style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('server-field'),
            controller: _ctl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'Eigene Server-Adresse',
              hintText: defaultServerUrl,
              helperText: 'Leer lassen für den Standard-Server. Zum Testen z. B. http://192.168.0.10:8080',
              helperMaxLines: 2,
            ),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_result!, style: TextStyle(color: _ok ? C.dbl : C.danger, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Standard')),
        TextButton(onPressed: _test, child: const Text('Testen')),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
