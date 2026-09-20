import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/detection_model.dart';
import '../models/evaluation_model.dart';

class ApiService {
  static const String _prefKey    = 'rs_base_url';
  static const String _defaultUrl = 'http://192.168.1.5:5000';

  /// Plain string — no await needed anywhere in the app
  static String baseUrl = _defaultUrl;

  // ── Call once in main() before runApp ───────────────────
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_prefKey) ?? _defaultUrl;
  }

  // ── Persist a new URL ───────────────────────────────────
  static Future<void> setBaseUrl(String raw) async {
    String url = raw.trim().replaceAll(RegExp(r'/$'), '');
    if (!url.startsWith('http')) url = 'http://$url';
    baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, baseUrl);
  }

  // ── PING — returns Map? so settings can read model/count ─
  static Future<Map<String, dynamic>?> ping() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/ping'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ── DETECT ─────────────────────────────────────────────
  static Future<DetectionResult> detect(
      File imageFile, {
        double? lat,
        double? lon,
        String? street,
        double conf = 0.30,
        double iou  = 0.45,
      }) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/detect'));
    request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path));
    if (lat    != null) request.fields['lat']    = lat.toString();
    if (lon    != null) request.fields['lon']    = lon.toString();
    if (street != null) request.fields['street'] = street;
    request.fields['conf'] = conf.toStringAsFixed(2);
    request.fields['iou']  = iou.toStringAsFixed(2);

    final streamed = await request.send().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception(
          'Timed out — is Flask running on $baseUrl?'),
    );
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data.containsKey('error')) throw Exception(data['error']);
      return DetectionResult.fromJson(data);
    }
    throw Exception('Server error ${response.statusCode}');
  }

  // ── MODEL VARIANTS (n/s/m comparison + production s) ────
  static Future<List<Map<String, dynamic>>> fetchModels() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/models'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['models'] as List<dynamic>? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  static Future<bool> selectModel(String key) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/select_model'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'key': key}),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── HISTORY ────────────────────────────────────────────
  static Future<List<HistoryEntry>> fetchHistory({int limit = 20}) async {
    final res = await http
        .get(Uri.parse('$baseUrl/history?limit=$limit'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['history'] as List<dynamic>? ?? [];
      return list
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('History fetch failed: ${res.statusCode}');
  }

  // ── STATS ──────────────────────────────────────────────
  static Future<AppStats> fetchStats() async {
    final res = await http
        .get(Uri.parse('$baseUrl/stats'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return AppStats.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('Stats fetch failed');
  }

  // ── MODEL EVALUATION (precision/recall/mAP + confusion matrix) ──
  // First call runs a full YOLO val() pass on the server, which on CPU can
  // realistically take 20-30+ minutes for a few thousand validation images,
  // so we allow a generous timeout. Pass refresh: true to force
  // recomputation (e.g. after retraining or swapping best.pt).
  static Future<EvaluationReport> fetchEvaluation({bool refresh = false}) async {
    final uri = Uri.parse(
        '$baseUrl/evaluate${refresh ? '?refresh=true' : ''}');
    final res = await http.get(uri).timeout(
      const Duration(minutes: 45),
      onTimeout: () => throw Exception(
          'Evaluation timed out after 45 minutes — check the api.py '
          'terminal to see if it is still progressing'),
    );
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      data = null;
    }
    if (res.statusCode == 200 && data != null && !data.containsKey('error')) {
      return EvaluationReport.fromJson(data);
    }
    if (res.statusCode == 409) {
      throw Exception(data?['error'] ??
          'An evaluation is already running — please wait for it to finish.');
    }
    final serverMsg = data?['error'];
    throw Exception(serverMsg != null
        ? serverMsg.toString()
        : 'Evaluation fetch failed: ${res.statusCode}');
  }

  // ── CLEAR ──────────────────────────────────────────────
  static Future<void> clearHistory() async {
    await http
        .post(Uri.parse('$baseUrl/clear'))
        .timeout(const Duration(seconds: 10));
  }
}