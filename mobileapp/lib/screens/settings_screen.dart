import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/server_discovery.dart';
import '../widgets/rs_card.dart';
import 'evaluation_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _url = '';
  bool   _pinging = false;
  bool?  _online;
  String _pingDetail = '';
  bool   _discovering = false;
  int    _scanProgress = 0;
  int    _scanTotal    = 254;
  String _discoveryMsg = '';

  final _urlCtrl = TextEditingController();
  final _waCtrl  = TextEditingController(text: '254707558206');

  double _conf = 0.30;
  double _iou  = 0.45;

  @override
  void initState() { super.initState(); _loadUrl(); }

  @override
  void dispose() { _urlCtrl.dispose(); _waCtrl.dispose(); super.dispose(); }

  Future<void> _loadUrl() async {
    final u = await ApiService.baseUrl;
    setState(() { _url = u; _urlCtrl.text = u; });
    _ping();
  }

  Future<void> _ping() async {
    setState(() { _pinging = true; _online = null; _pingDetail = ''; });
    final result = await ApiService.ping();
    if (!mounted) return;
    if (result != null) {
      final count = result['history_count'] ?? 0;
      final model = result['model'] ?? 'best.pt';
      setState(() {
        _online = true;
        _pingDetail = 'model: $model · $count scans';
        _pinging = false;
      });
    } else {
      setState(() { _online = false; _pinging = false; });
    }
  }

  Future<void> _saveUrl(String raw) async {
    String url = raw.trim();
    if (!url.startsWith('http')) url = 'http://$url';
    url = url.replaceAll(RegExp(r'/$'), '');
    await ApiService.setBaseUrl(url);
    setState(() { _url = url; _urlCtrl.text = url; });
    _ping();
    HapticFeedback.selectionClick();
  }

  Future<void> _discover() async {
    if (_discovering) return;
    setState(() {
      _discovering = true; _scanProgress = 0;
      _discoveryMsg = 'Scanning local network…'; _online = null;
    });
    final found = await ServerDiscovery.findServer(
      onProgress: (scanned, total) {
        if (!mounted) return;
        setState(() { _scanProgress = scanned; _scanTotal = total;
          _discoveryMsg = 'Scanning… $scanned / $total'; });
      },
    );
    if (!mounted) return;
    if (found != null) {
      await ApiService.setBaseUrl(found);
      setState(() { _url = found; _urlCtrl.text = found;
        _discoveryMsg = 'Found: $found'; _discovering = false; });
      _ping();
    } else {
      setState(() { _discoveryMsg = 'Not found. Enter IP manually.';
        _discovering = false; });
    }
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear scan history?', style: TextStyle(
            color: context.text, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text('This removes all scan records from the Flask server.',
            style: TextStyle(color: context.muted, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: context.muted))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear',
                  style: TextStyle(color: AppColors.red,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.clearHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('History cleared')));
          _ping();
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(slivers: [

        // ── App bar ──────────────────────────────────────────
        SliverAppBar(
          backgroundColor: context.bg,
          pinned: true, floating: true,
          toolbarHeight: 64,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(text: TextSpan(
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                  letterSpacing: -0.6, color: context.text),
              children: const [
                TextSpan(text: 'App '),
                TextSpan(text: 'Settings',
                    style: TextStyle(color: AppColors.lime)),
              ],
            )),
            Text('Preferences & backend',
                style: TextStyle(fontSize: 12, color: context.muted)),
          ]),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: context.muted, size: 20),
              onPressed: _ping,
            ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // ── Profile banner ─────────────────────────────
            const SectionLabel('Profile'),
            _ProfileBanner(),

            // ── Connection ─────────────────────────────────
            const SectionLabel('Backend Connection'),
            _StatusCard(
              online: _online, pinging: _pinging,
              detail: _pingDetail, url: _url, onPing: _ping),
            const SizedBox(height: 10),

            // URL editor
            RSCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.link_rounded,
                      color: AppColors.blue, size: 16),
                  const SizedBox(width: 8),
                  Text('Server URL', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: context.text)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: context.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.border),
                    ),
                    child: TextField(
                      controller: _urlCtrl,
                      style: TextStyle(fontSize: 13, color: context.text,
                          fontFamily: 'monospace'),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          border: InputBorder.none, isDense: true,
                          contentPadding: EdgeInsets.zero),
                      onSubmitted: _saveUrl,
                    ),
                  )),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _saveUrl(_urlCtrl.text),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text('Format: http://IP:5000',
                    style: TextStyle(fontSize: 11, color: context.muted)),
              ]),
            ),
            const SizedBox(height: 10),

            // Auto-discover
            _DiscoverButton(
              discovering: _discovering,
              progress: _scanProgress,
              total: _scanTotal,
              message: _discoveryMsg,
              onTap: _discover,
            ),

            // ── Appearance ─────────────────────────────────
            const SectionLabel('Appearance'),
            RSCard(
              padding: EdgeInsets.zero,
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (_, mode, __) => IosRow(
                  leading: RowIcon(
                    icon: mode == ThemeMode.dark
                        ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                    color: AppColors.amber,
                  ),
                  title: 'Theme',
                  subtitle: mode == ThemeMode.dark
                      ? 'Dark mode active' : 'Light mode active',
                  showChevron: false,
                  isLast: true,
                  trailing: Switch.adaptive(
                    value: mode == ThemeMode.dark,
                    activeThumbColor: AppColors.lime,
                    activeTrackColor: AppColors.lime.withValues(alpha: 0.4),
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      themeNotifier.value =
                          v ? ThemeMode.dark : ThemeMode.light;
                    },
                  ),
                ),
              ),
            ),

            // ── Detection defaults ──────────────────────────
            const SectionLabel('Detection Defaults'),
            RSCard(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                _SliderRow(
                  label: 'Confidence threshold',
                  value: _conf, color: AppColors.blue,
                  onChanged: (v) => setState(() => _conf = v),
                ),
                const SizedBox(height: 16),
                _SliderRow(
                  label: 'IOU threshold',
                  value: _iou, color: AppColors.teal,
                  onChanged: (v) => setState(() => _iou = v),
                ),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight,
                  child: Text('Sent with each /detect request',
                      style: TextStyle(fontSize: 11, color: context.muted))),
              ]),
            ),

            // ── WhatsApp ────────────────────────────────────
            const SectionLabel('WhatsApp Alerts'),
            RSCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Row(children: [
                  const Icon(Icons.phone_rounded,
                      color: AppColors.lime, size: 16),
                  const SizedBox(width: 8),
                  Text('Recipient number', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: context.text)),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: context.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.border),
                  ),
                  child: TextField(
                    controller: _waCtrl,
                    style: TextStyle(fontSize: 13, color: context.text,
                        fontFamily: 'monospace'),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        border: InputBorder.none, isDense: true,
                        contentPadding: EdgeInsets.zero),
                  ),
                ),
                const SizedBox(height: 6),
                Text('Include country code, no + (e.g. 254712345678)',
                    style: TextStyle(fontSize: 11, color: context.muted)),
              ]),
            ),

            // ── Data ────────────────────────────────────────
            const SectionLabel('Data'),
            RSCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                IosRow(
                  leading: RowIcon(
                      icon: Icons.delete_outline_rounded, color: AppColors.red),
                  title: 'Clear scan history',
                  subtitle: 'Removes all records from server',
                  onTap: _clearHistory, isLast: false,
                ),
                IosRow(
                  leading: RowIcon(
                      icon: Icons.download_rounded, color: AppColors.blue),
                  title: 'Export CSV',
                  subtitle: 'Run a scan first to export',
                  isLast: true,
                ),
              ]),
            ),

            // ── About ───────────────────────────────────────
            const SectionLabel('About'),
            RSCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                IosRow(leading: RowIcon(icon: Icons.info_outline_rounded,
                    color: AppColors.blue),
                  title: 'RoadSense v4',
                  subtitle: 'Final Year Project · 2024/25', isLast: false),
                IosRow(leading: RowIcon(icon: Icons.model_training_outlined,
                    color: AppColors.purple),
                  title: 'Model',
                  subtitle: 'YOLOv8 · best.pt · view evaluation',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const EvaluationScreen())),
                  isLast: false),
                IosRow(leading: RowIcon(icon: Icons.code_rounded,
                    color: AppColors.teal),
                  title: 'Stack',
                  subtitle: 'Flutter · Flask · Ultralytics', isLast: true),
              ]),
            ),

            const SizedBox(height: 110),
          ])),
        ),
      ]),
    );
  }
}

// ── Profile banner ─────────────────────────────────────────────
class _ProfileBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RSCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF1A4020), Color(0xFF2C5A28)],
            ),
            border: Border.all(
                color: AppColors.lime.withValues(alpha: 0.3), width: 1),
          ),
          child: const Icon(Icons.engineering_outlined,
              color: AppColors.lime, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Field Engineer', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: context.text)),
            Text('Nairobi Road Authority',
                style: TextStyle(fontSize: 13, color: context.muted)),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.lime.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: AppColors.lime.withValues(alpha: 0.28), width: 0.5),
          ),
          child: const Text('v4.0', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.lime, fontFamily: 'monospace')),
        ),
      ]),
    );
  }
}

// ── Status card ────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final bool? online;
  final bool pinging;
  final String detail, url;
  final VoidCallback onPing;
  const _StatusCard({required this.online, required this.pinging,
      required this.detail, required this.url, required this.onPing});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;

    if (pinging || online == null) {
      color = AppColors.amber; label = 'Checking…'; icon = Icons.sync_rounded;
    } else if (online == true) {
      color = AppColors.lime;  label = 'Online';    icon = Icons.cloud_done_outlined;
    } else {
      color = AppColors.red;   label = 'Offline';   icon = Icons.cloud_off_outlined;
    }

    return RSCard(
      accentColor: color,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: pinging
              ? Padding(padding: const EdgeInsets.all(13),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            if (detail.isNotEmpty)
              Text(detail, style: TextStyle(
                  fontSize: 11, color: context.muted, fontFamily: 'monospace')),
            Text(url, style: TextStyle(
                fontSize: 11, color: context.muted, fontFamily: 'monospace'),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        )),
        GestureDetector(
          onTap: onPing,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: context.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.border),
            ),
            child: Text('Ping', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: context.text)),
          ),
        ),
      ]),
    );
  }
}

// ── Discover button ────────────────────────────────────────────
class _DiscoverButton extends StatelessWidget {
  final bool discovering;
  final int progress, total;
  final String message;
  final VoidCallback onTap;
  const _DiscoverButton({required this.discovering, required this.progress,
      required this.total, required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: discovering ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.lime.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.lime.withValues(alpha: 0.28)),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (discovering)
              const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.lime))
            else
              const Icon(Icons.wifi_find_rounded,
                  color: AppColors.lime, size: 18),
            const SizedBox(width: 10),
            Text(
              discovering ? 'Scanning network…' : 'Auto-discover Flask server',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                  color: AppColors.lime)),
          ]),
          if (discovering) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? progress / total : null,
                backgroundColor: AppColors.lime.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation(AppColors.lime),
                minHeight: 4,
              ),
            ),
          ],
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(message,
              style: TextStyle(fontSize: 12, color: context.muted,
                  fontFamily: 'monospace'),
              textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}

// ── Slider row ─────────────────────────────────────────────────
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final Color  color;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value,
      required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(
            fontSize: 13, color: context.text, fontWeight: FontWeight.w500)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(value.toStringAsFixed(2), style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color,
              fontFamily: 'monospace')),
        ),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor:   color,
          inactiveTrackColor: color.withValues(alpha: 0.16),
          thumbColor:         color,
          overlayShape:       const RoundSliderOverlayShape(overlayRadius: 14),
          trackHeight:        3,
        ),
        child: Slider(
            value: value, min: 0.10, max: 0.90, onChanged: onChanged),
      ),
    ]);
  }
}
