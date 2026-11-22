package de.simon.darts

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import java.net.Inet4Address
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var lock: WifiManager.MulticastLock? = null
    private var linkChannel: MethodChannel? = null
    private var initialLink: String? = null

    /// Nur darts://connect?… weiterreichen (alles andere ignorieren).
    private fun dartsLink(intent: Intent?): String? {
        val data = intent?.data ?: return null
        return if (intent.action == Intent.ACTION_VIEW && data.scheme == "darts") data.toString() else null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Link „App mit diesem Server verbinden“ (darts://connect?server=…)
        initialLink = dartsLink(intent)
        linkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darts/link").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(initialLink)
                    initialLink = null
                } else {
                    result.notImplemented()
                }
            }
        }
        // Ohne Multicast-Sperre verwerfen viele Android-Geräte UDP-Broadcasts
        // (nötig, damit Handys einen Raum im WLAN automatisch finden).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "darts/net").setMethodCallHandler { call, result ->
            when (call.method) {
                "acquire" -> {
                    try {
                        if (lock == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            lock = wifi.createMulticastLock("darts_link").apply { setReferenceCounted(false) }
                        }
                        lock?.acquire()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "networks" -> {
                    // Eigene IPv4-Adressen mit Netzgröße (z. B. 10.192.48.220/19)
                    val out = ArrayList<String>()
                    try {
                        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                        @Suppress("DEPRECATION")
                        for (n in cm.allNetworks) {
                            val lp = cm.getLinkProperties(n) ?: continue
                            for (la in lp.linkAddresses) {
                                val a = la.address
                                if (a is Inet4Address && !a.isLoopbackAddress && !a.isLinkLocalAddress) {
                                    out.add(a.hostAddress + "/" + la.prefixLength)
                                }
                            }
                        }
                    } catch (_: Exception) {}
                    result.success(out)
                }
                "release" -> {
                    try { lock?.release() } catch (_: Exception) {}
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = dartsLink(intent) ?: return
        setIntent(intent)
        linkChannel?.invokeMethod("link", link)
    }

    override fun onDestroy() {
        try { lock?.release() } catch (_: Exception) {}
        super.onDestroy()
    }
}
