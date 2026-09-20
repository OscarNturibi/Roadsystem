import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class ServerDiscovery {
  static const int _port    = 5000;
  static const int _timeout = 200; // ms per probe
  static const int _batch   = 20;  // parallel probes per batch

  /// Scan the local subnet derived from [localIp] for a Flask server on port 5000.
  /// Returns the first reachable URL, e.g. "http://192.168.1.45:5000", or null.
  static Future<String?> findServer({
    void Function(int scanned, int total)? onProgress,
  }) async {
    final localIp = await _getLocalIp();
    if (localIp == null) return null;

    final parts   = localIp.split('.');
    final subnet  = '${parts[0]}.${parts[1]}.${parts[2]}';
    final hosts   = List.generate(254, (i) => '$subnet.${i + 1}');
    final total   = hosts.length;
    int scanned   = 0;

    // Work through hosts in parallel batches
    for (var i = 0; i < total; i += _batch) {
      final batch  = hosts.skip(i).take(_batch).toList();
      final probes = batch.map((ip) => _probe(ip));
      final results = await Future.wait(probes);

      scanned += batch.length;
      onProgress?.call(scanned, total);

      for (int j = 0; j < results.length; j++) {
        if (results[j]) return 'http://${batch[j]}:$_port';
      }
    }
    return null;
  }

  /// Quick TCP knock on [ip]:5000 — no HTTP overhead.
  static Future<bool> _probe(String ip) async {
    try {
      final sock = await Socket.connect(
        ip, _port,
        timeout: Duration(milliseconds: _timeout),
      );
      sock.destroy();
      // Confirm it's actually the Flask RoadSense API
      return await _verifyFlask('http://$ip:$_port');
    } catch (_) {
      return false;
    }
  }

  /// Hit /ping and check for the "RoadSense" marker.
  static Future<bool> _verifyFlask(String url) async {
    try {
      final res = await http
          .get(Uri.parse('$url/ping'))
          .timeout(const Duration(milliseconds: 800));
      return res.statusCode == 200 && res.body.contains('ok');
    } catch (_) {
      return false;
    }
  }

  /// Get the device's own WiFi/LAN IP.
  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        // Prefer WiFi interfaces (wlan, en0, Wi-Fi)
        if (iface.name.toLowerCase().contains('wlan') ||
            iface.name.toLowerCase().contains('en0')  ||
            iface.name.toLowerCase().contains('wifi') ||
            iface.name.toLowerCase().contains('wi-fi')) {
          for (final addr in iface.addresses) {
            if (addr.address.startsWith('192.') ||
                addr.address.startsWith('10.')  ||
                addr.address.startsWith('172.')) {
              return addr.address;
            }
          }
        }
      }
      // Fallback: first private address on any interface
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.startsWith('192.') ||
              addr.address.startsWith('10.')  ||
              addr.address.startsWith('172.')) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}