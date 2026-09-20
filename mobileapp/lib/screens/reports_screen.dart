import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../services/api_service.dart';
import '../widgets/rs_card.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<HistoryEntry> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final h = await ApiService.fetchHistory(limit: 30);
      setState(() => _history = h);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total  = _history.length;
    final highs  = _history.fold<int>(0, (a, e) => a + e.summary.high);
    final avgH   = total == 0 ? 100
        : (_history.fold<int>(0, (a, e) => a + e.healthScore) / total).round();
    final hColor = avgH >= 70 ? AppColors.lime
        : avgH >= 40 ? AppColors.orange : AppColors.red;

    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: context.bg,
          pinned: true, floating: true,
          toolbarHeight: 64,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(text: TextSpan(
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                  letterSpacing: -0.6, color: context.text),
              children: const [
                TextSpan(text: 'Scan '),
                TextSpan(text: 'Reports',
                    style: TextStyle(color: AppColors.lime)),
              ],
            )),
            Text('Inspection history',
                style: TextStyle(fontSize: 12, color: context.muted)),
          ]),
          actions: [
            IconButton(
              onPressed: () { HapticFeedback.mediumImpact(); _load(); },
              icon: Icon(Icons.refresh_rounded, color: context.muted, size: 20),
            ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // ── Summary strip ──────────────────────────────
            const SectionLabel('Summary'),
            Row(children: [
              Expanded(child: StatCard(
                  label: 'Total Scans', value: '$total',
                  valueColor: AppColors.blue)),
              const SizedBox(width: 10),
              Expanded(child: StatCard(
                  label: 'Avg Health', value: '$avgH',
                  valueColor: hColor,
                  accentBorder: hColor.withValues(alpha: 0.25))),
              const SizedBox(width: 10),
              Expanded(child: StatCard(
                  label: 'High Sev.', value: '$highs',
                  valueColor: AppColors.red)),
            ]),

            const SectionLabel('Scan History'),

            if (_loading)
              const SizedBox(height: 180,
                child: Center(child: CircularProgressIndicator(
                    color: AppColors.lime, strokeWidth: 2)))
            else if (_error != null)
              _ErrorCard(error: _error!, onRetry: _load)
            else if (_history.isEmpty)
              _EmptyState()
            else
              ..._history.asMap().entries.map((e) =>
                TweenAnimationBuilder<double>(
                  key: ValueKey(e.key),
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 200 + e.key * 40),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(
                        offset: Offset(0, 12 * (1 - v)), child: child)),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _HistoryCard(entry: e.value),
                  ),
                )),

            const SizedBox(height: 110),
          ])),
        ),
      ]),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final s      = entry.summary;
    final h      = entry.healthScore;
    final hColor = h >= 70 ? AppColors.lime
        : h >= 40 ? AppColors.orange : AppColors.red;
    final condColor = s.conditionColor;

    return RSCard(
      accentColor: hColor,
      padding: EdgeInsets.zero,
      child: Column(children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(children: [
            // Scan ID
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.blue.withValues(alpha: 0.22), width: 0.5),
              ),
              child: Text(entry.scanId, style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.blue, fontFamily: 'monospace')),
            ),
            const Spacer(),
            // Condition
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: condColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: condColor.withValues(alpha: 0.28), width: 0.5),
              ),
              child: Text(s.condition.toUpperCase(), style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: condColor,
                fontFamily: 'monospace')),
            ),
          ]),
        ),

        // Location
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.location_on_outlined, size: 14, color: context.muted),
            const SizedBox(width: 6),
            Expanded(child: Text(entry.location.street,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: context.text))),
          ]),
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.access_time_outlined, size: 12, color: context.muted),
            const SizedBox(width: 6),
            Text(entry.timeLabel, style: TextStyle(
                fontSize: 11, color: context.muted, fontFamily: 'monospace')),
          ]),
        ),

        // Pills + health ring
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Row(children: [
            _Pill('${s.total}', 'total', context.muted),
            const SizedBox(width: 6),
            _Pill('${s.high}',   'high',   AppColors.red),
            const SizedBox(width: 6),
            _Pill('${s.medium}', 'med',    AppColors.orange),
            const SizedBox(width: 6),
            _Pill('${s.low}',    'low',    AppColors.lime),
            const Spacer(),
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hColor.withValues(alpha: 0.10),
                border: Border.all(
                    color: hColor.withValues(alpha: 0.32), width: 1.5),
              ),
              child: Center(child: Text('$h',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                    color: hColor))),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String value, label;
  final Color color;
  const _Pill(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withValues(alpha: 0.20), width: 0.5),
    ),
    child: RichText(text: TextSpan(
      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      children: [
        TextSpan(text: value,
            style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        TextSpan(text: ' $label',
            style: TextStyle(color: color.withValues(alpha: 0.65))),
      ],
    )),
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => RSCard(
    child: SizedBox(height: 160,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: context.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.receipt_long_outlined, size: 26, color: context.muted),
        ),
        const SizedBox(height: 14),
        Text('No scans yet', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: context.text)),
        const SizedBox(height: 4),
        Text('Run detection on the Detect tab to build history.',
            style: TextStyle(fontSize: 13, color: context.muted),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorCard({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => RSCard(
    child: Column(children: [
      Row(children: [
        const Icon(Icons.error_outline, color: AppColors.red, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text('Could not load history',
            style: TextStyle(fontWeight: FontWeight.w600, color: context.text))),
      ]),
      const SizedBox(height: 6),
      Text(error, style: TextStyle(fontSize: 12, color: context.muted)),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity,
        child: OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.blue,
            side: BorderSide(color: AppColors.blue.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Retry'),
        )),
    ]),
  );
}
