{{flutter_js}}
{{flutter_build_config}}

// Darts – Start der Web-App.
// - CanvasKit kommt vom eigenen Server (nicht vom Google-CDN): offline startbar, keine Daten an Dritte.
// - Eigener Service Worker (sw.js) statt Flutters flutter_service_worker.js
//   (der räumt in dieser Flutter-Version nur noch auf und cacht nichts).
(function () {
  var splash = document.getElementById('splash');

  function hideSplash() {
    if (!splash) return;
    splash.classList.add('hide');
    var s = splash;
    splash = null;
    setTimeout(function () { s.remove(); }, 400);
  }
  window.addEventListener('flutter-first-frame', hideSplash, { once: true });

  _flutter.loader.load({
    config: {
      canvasKitBaseUrl: 'canvaskit/',
    },
    onEntrypointLoaded: async function (engineInitializer) {
      try {
        var appRunner = await engineInitializer.initializeEngine({
          canvasKitBaseUrl: 'canvaskit/',
        });
        await appRunner.runApp();
      } catch (e) {
        console.error(e);
        if (splash) splash.classList.add('failed');
      }
    },
  }).catch(function (e) {
    console.error(e);
    if (splash) splash.classList.add('failed');
  });

  // Service Worker: Offline-Start und zuverlässige Updates (siehe sw.js).
  // Nicht im Entwicklungsmodus (flutter run), damit nichts Altes hängen bleibt.
  var isDev = location.hostname === 'localhost' && /[?&]nosw\b/.test(location.search);
  if ('serviceWorker' in navigator && !isDev && location.protocol !== 'file:') {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('sw.js').then(function (reg) {
        // Beim Zurückkehren in die App nach Updates schauen.
        document.addEventListener('visibilitychange', function () {
          if (document.visibilityState === 'visible') reg.update().catch(function () {});
        });
      }).catch(function (e) {
        console.warn('Service Worker nicht registriert:', e);
      });
    });

    // Nach dem Start: alle bereits geladenen Dateien (Programm, CanvasKit, Schriften, Töne)
    // dem Service Worker melden, damit schon der erste Besuch offline startbar ist.
    window.addEventListener('flutter-first-frame', function () {
      setTimeout(function () {
        navigator.serviceWorker.ready.then(function (reg) {
          var urls = [location.href];
          try {
            performance.getEntriesByType('resource').forEach(function (e) { urls.push(e.name); });
          } catch (e) {}
          if (reg.active) reg.active.postMessage({ type: 'cache', urls: urls });
        }).catch(function () {});
      }, 5000);
    }, { once: true });
  }
})();
