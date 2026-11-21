/// Tonausgabe im Browser über die Web-Audio-API (eine gemeinsame AudioContext).
///
/// Warum nicht audioplayers? Dessen Web-Teil legt je Player ein eigenes
/// `<audio>`-Element samt AudioContext an (bei uns ~20 Stück) – Safari begrenzt
/// das, und auf dem iPhone dürfen solche Elemente nur direkt nach einem Tippen
/// starten. Die Anzeige (Tablet) spielt Ansagen aber ohne Tippen ab.
///
/// Lösung: eine einzige AudioContext, beim ersten Tippen freigeschaltet
/// (iOS: Audio-Unlock). Danach klingen alle Töne jederzeit.
library;

export 'web_audio_io.dart' if (dart.library.js_interop) 'web_audio_web.dart';
