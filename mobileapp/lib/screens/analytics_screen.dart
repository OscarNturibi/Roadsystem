import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../services/api_service.dart';
import '../widgets/rs_card.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with TickerProviderStateMixin {
  AppStats _stats = AppStats.empty();
  bool _loading = true;
  String? _error;

  late final AnimationController _ringCtrl;
  late final Animation<double>   _ringAnim;

  @override
  void initState() {
    super.initState();
    _ringCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1200));
    _ringAnim = CurvedAnimation(parent: _ringCtrl,
        curve: Curves.easeOutCubic);
    _load();
  }

  @override
  void dispose() { _ringCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final s = await ApiService.fetchStats();
      setState(() => _stats = s);
      _ringCtrl.forward(from: 0);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
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
                TextSpan(text: 'Road '),
                TextSpan(text: 'Analytics',
                    style: TextStyle(color: AppColors.lime)),
              ],
            )),
            Text('Infrastructure insights',
                style: TextStyle(fontSize: 12, color: context.muted)),
          ]),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.lime.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.lime.withValues(alpha: 0.28)),
              ),
              child: const Row(children: [
                _Pip(),
                SizedBox(width: 5),
                Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.lime, letterSpacing: 0.5,
                    fontFamily: 'monospace')),
              ]),
            ),
            IconButton(onPressed: _load,
                icon: Icon(Icons.refresh_rounded, color: context.muted, size: 20)),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            if (_loading)
              const SizedBox(height: 200,
                child: Center(child: CircularProgressIndicator(
                    color: AppColors.lime, strokeWidth: 2)))
            else if (_error != null)
              RSCard(child: Row(children: [
                const Icon(Icons.error_outline, color: AppColors.red, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 13))),
              ]))
            else ...[

              // ── Health ring hero ───────────────────────────
              const SectionLabel('Health Overview'),
              _HealthHeroCard(stats: _stats, anim: _ringAnim),

              // ── KPI grid ──────────────────────────────────
              const SectionLabel('Key Metrics'),
              Row(children: [
                Expanded(child: StatCard(
                  label: 'Total Scans',
                  value: '${_stats.totalScans}',
                  valueColor: AppColors.blue,
                  icon: _IconBlob(icon: Icons.document_scanner_outlined,
                      color: AppColors.blue),
                  chipLabel: 'Session',
                  chipColor: AppColors.blue,
                )),
                const SizedBox(width: 10),
                Expanded(child: StatCard(
                  label: 'Total Defects',
                  value: '${_stats.totalDefects}',
                  valueColor: AppColors.orange,
                  icon: _IconBlob(icon: Icons.warning_amber_rounded,
                      color: AppColors.orange),
                  chipLabel: 'All types',
                  chipColor: AppColors.orange,
                )),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: StatCard(
                  label: 'High Severity',
                  value: '${_stats.highCount}',
                  valueColor: AppColors.red,
                  accentBorder: AppColors.red.withValues(alpha: 0.3),
                  chipLabel: 'Critical',
                  chipColor: AppColors.red,
                )),
                const SizedBox(width: 8),
                Expanded(child: StatCard(
                  label: 'Medium',
                  value: '${_stats.mediumCount}',
                  valueColor: AppColors.orange,
                )),
                const SizedBox(width: 8),
                Expanded(child: StatCard(
                  label: 'Low',
                  value: '${_stats.lowCount}',
                  valueColor: AppColors.lime,
                )),
              ]),

              // ── Condition distribution ─────────────────────
              const SectionLabel('Condition Distribution'),
              _ConditionBars(stats: _stats),

              // ── Defect frequency bars ──────────────────────
              const SectionLabel('Defect Frequency'),
              _FrequencyChart(stats: _stats),

              const SizedBox(height: 110),
            ],
          ])),
        ),
      ]),
    );
  }
}

// ── Health ring hero ──────────────────────────────────────────
class _HealthHeroCard extends StatelessWidget {
  final AppStats stats;
  final Animation<double> anim;
  const _HealthHeroCard({required this.stats, required this.anim});

  @override
  Widget build(BuildContext context) {
    final h     = stats.avgHealth.round();
    final color = h >= 70 ? AppColors.lime : h >= 40 ? AppColors.orange : AppColors.red;
    final label = h >= 70 ? 'Good' : h >= 40 ? 'Fair' : 'Poor';

    return RSCard(
      accentColor: color,
      padding: const EdgeInsets.all(22),
      child: Row(children: [
        // Animated ring
        SizedBox(width: 100, height: 100,
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, __) => CustomPaint(
              painter: _RingPainter(
                progress: (stats.avgHealth / 100) * anim.value,
                color:    color,
                bgColor:  context.surface2,
              ),
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$h', style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900,
                    color: context.text, letterSpacing: -1.5)),
                  Text('/100', style: TextStyle(
                    fontSize: 10, color: context.muted, fontFamily: 'monospace')),
                ],
              )),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Avg Health', style: TextStyle(
                fontSize: 13, color: context.muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Road\nCondition', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: context.text, letterSpacing: -0.5, height: 1.1)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:  color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.32)),
              ),
              child: Text(label, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color,
                letterSpacing: 0.2)),
            ),
          ],
        )),
        // Scans count circle
        Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.blue.withValues(alpha: 0.12),
              border: Border.all(
                  color: AppColors.blue.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Center(child: Text('${stats.totalScans}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.blue))),
          ),
          const SizedBox(height: 4),
          Text('scans', style: TextStyle(
              fontSize: 10, color: context.muted, fontFamily: 'monospace')),
        ]),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color, bgColor;
  const _RingPainter({required this.progress, required this.color,
      required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final r  = math.min(cx, cy) - 8;
    final p  = Paint()..strokeWidth = 8..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

    // Track
    p.color = bgColor;
    canvas.drawCircle(Offset(cx, cy), r, p);

    // Arc
    p.color = color;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false, p,
    );
  }
  @override bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.color != color;
}

// ── Condition bars ────────────────────────────────────────────
class _ConditionBars extends StatelessWidget {
  final AppStats stats;
  const _ConditionBars({required this.stats});

  @override
  Widget build(BuildContext context) {
    const conds = [
      ('Critical', AppColors.red),
      ('Poor',     AppColors.red),
      ('Fair',     AppColors.orange),
      ('Good',     AppColors.lime),
    ];
    final total = stats.conditionDist.values
        .fold<int>(0, (a, b) => a + b).clamp(1, 999999);

    return RSCard(child: Column(
      children: conds.map((c) {
        final count = stats.conditionDist[c.$1] ?? 0;
        final frac  = count / total;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 8, height: 8,
                decoration: BoxDecoration(
                    color: c.$2, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text(c.$1, style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: context.text))),
              Text('$count', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: c.$2,
                  fontFamily: 'monospace')),
            ]),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:       frac,
                backgroundColor: context.surface2,
                valueColor:  AlwaysStoppedAnimation(c.$2),
                minHeight:   5,
              ),
            ),
          ]),
        );
      }).toList(),
    ));
  }
}

// ── Frequency chart ───────────────────────────────────────────
class _FrequencyChart extends StatelessWidget {
  final AppStats stats;
  const _FrequencyChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total  = stats.totalDefects.clamp(1, 999999);
    final rows   = [
      ('High Sev.',   stats.highCount,   AppColors.red),
      ('Medium Sev.', stats.mediumCount, AppColors.orange),
      ('Low Sev.',    stats.lowCount,    AppColors.lime),
    ];
    return RSCard(child: Column(
      children: rows.map((row) {
        final frac = row.$2 / total;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            SizedBox(width: 86,
                child: Text(row.$1, style: TextStyle(
                    fontSize: 12, color: context.muted))),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:        frac,
                backgroundColor: context.surface2,
                valueColor:   AlwaysStoppedAnimation(row.$3),
                minHeight:    7,
              ),
            )),
            const SizedBox(width: 10),
            SizedBox(width: 34,
              child: Text('${(frac * 100).round()}%',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: row.$3, fontFamily: 'monospace'),
                textAlign: TextAlign.right)),
          ]),
        );
      }).toList(),
    ));
  }
}

// ── helpers ───────────────────────────────────────────────────
class _IconBlob extends StatelessWidget {
  final IconData icon;
  final Color    color;
  const _IconBlob({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: color, size: 18),
  );
}

class _Pip extends StatefulWidget {
  const _Pip();
  @override State<_Pip> createState() => _PipState();
}
class _PipState extends State<_Pip> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override void initState() {
    super.initState();
    _c = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, __) => Container(
      width: 6, height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.lime.withValues(alpha: 0.3 + 0.7 * _c.value),
      ),
    ),
  );
}
