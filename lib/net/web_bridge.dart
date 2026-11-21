/// Kleine Plattform-Weiche für das, was im Browser anders geht (HTTP-Abruf, Seite neu laden).
library;

export 'web_bridge_io.dart' if (dart.library.js_interop) 'web_bridge_web.dart';
