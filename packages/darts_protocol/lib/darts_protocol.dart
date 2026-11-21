/// Gemeinsames Protokoll zwischen Darts-App (APK + Web) und dem Vermittlungs-Server.
///
/// Grundidee: Der Server ist nur ein **Relais**. Die App spricht durch ihn genau dasselbe
/// Protokoll wie bei der WLAN-Kopplung (hello / auth / welcome / state / dart / sync …).
/// Der Server packt diese Nachrichten nur in Umschläge („Frames“) und reicht sie zwischen
/// dem Host eines Raums und seinen Gästen weiter. Er versteht und speichert den Inhalt nicht.
///
/// Siehe docs/web_architektur.md.
library;

export 'src/frames.dart';
export 'src/room_code.dart';
export 'src/version_info.dart';
