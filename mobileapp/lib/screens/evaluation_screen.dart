// ══════════════════════════════════════════════════════════════
//  evaluation_screen.dart
//  Model quality report — precision / recall / mAP50 / mAP50-95,
//  a per-class breakdown table, and the confusion matrix produced
//  by YOLO's own validation pass (GET /evaluate on the Flask API).
// ══════════════════════════════════════════════════════════════
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../models/evaluation_model.dart';
import '../services/api_service.dart';
import '../widgets/rs_card.dart';

class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({super.key});
  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  EvaluationReport? _report;
  bool _loading = true;
  bool _inFlight = false; // guards against a double-tap firing 2 requests
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_inFlight) return;
    _inFlight = true;
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ApiService.fetchEvaluation(refresh: refresh);
      if (!mounted) return;
      setState(() => _report = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: context.bg,
          pinned: true,
          toolbarHeight: 64,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: context.text),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichText(text: TextSpan(
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                  letterSpacing: -0.5, color: context.text),
              children: const [
                TextSpan(text: 'Model '),
                TextSpan(text: 'Evaluation',
                    style: TextStyle(color: AppColors.purple)),
              ],
            )),
            Text('Precision · Recall · mAP', style: TextStyle(
                fontSize: 12, color: context.muted)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Re-run evaluation',
              onPressed: (_loading || _inFlight)
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      _load(refresh: true);
                    },
              icon: Icon(Icons.refresh_rounded, color: context.muted, size: 20),
            ),
            const SizedBox(width: 4),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Column(children: [
                  CircularProgressIndicator(color: AppColors.purple, strokeWidth: 2),
                  SizedBox(height: 14),
                  Text('Running validation on the server…\nthis can take 20-30+ minutes on CPU — don\'t tap refresh again',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              )
            else if (_error != null)
              RSCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.error_outline, color: AppColors.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: AppColors.red, fontSize: 13))),
                ]),
                const SizedBox(height: 12),
                Text(
                  'Make sure the Flask server has a VAL_DATA_YAML path configured '
                  'pointing at your dataset\'s data.yaml.',
                  style: TextStyle(fontSize: 12, color: context.muted),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => _load(refresh: true),
                  child: const Text('Retry'),
                ),
              ]))
            else if (_report != null) ...[
              const SectionLabel('Overall Performance'),
              _MetricGrid(overall: _report!.overall),

              const SectionLabel('Per-Class Breakdown'),
              _ClassTable(classes: _report!.perClass),

              if (_report!.confusionMatrixB64 != null) ...[
                const SectionLabel('Confusion Matrix'),
                RSCard(child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(_report!.confusionMatrixB64!),
                    fit: BoxFit.contain,
                  ),
                )),
              ],

              const SizedBox(height: 14),
              Center(child: Column(children: [
                if (_report!.evaluatedAt.isNotEmpty)
                  Text('Evaluated ${_report!.evaluatedAtLabel}',
                      style: TextStyle(fontSize: 11, color: context.muted)),
                if (_report!.dataYaml.isNotEmpty)
                  Text('Dataset: ${_report!.dataYaml}',
                      style: TextStyle(fontSize: 11, color: context.muted,
                          fontFamily: 'monospace')),
              ])),

              const SizedBox(height: 60),
            ],
          ])),
        ),
      ]),
    );
  }
}

// ── Overall metric cards ────────────────────────────────────────
class _MetricGrid extends StatelessWidget {
  final OverallMetrics overall;
  const _MetricGrid({required this.overall});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Precision', overall.precision),
      ('Recall',    overall.recall),
      ('mAP@50',    overall.map50),
      ('mAP@50-95', overall.map5095),
    ];
    return Column(children: [
      Row(children: [
        Expanded(child: _MetricTile(label: tiles[0].$1, value: tiles[0].$2)),
        const SizedBox(width: 10),
        Expanded(child: _MetricTile(label: tiles[1].$1, value: tiles[1].$2)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _MetricTile(label: tiles[2].$1, value: tiles[2].$2)),
        const SizedBox(width: 10),
        Expanded(child: _MetricTile(label: tiles[3].$1, value: tiles[3].$2)),
      ]),
    ]);
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final double value;
  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = metricColor(value);
    return StatCard(
      label: label,
      value: '${(value * 100).toStringAsFixed(1)}%',
      valueColor: color,
      chipLabel: value >= 0.75 ? 'Strong' : value >= 0.5 ? 'Fair' : 'Weak',
      chipColor: color,
    );
  }
}

// ── Per-class table ──────────────────────────────────────────────
class _ClassTable extends StatelessWidget {
  final List<ClassMetric> classes;
  const _ClassTable({required this.classes});

  @override
  Widget build(BuildContext context) {
    if (classes.isEmpty) {
      return RSCard(child: Text('No per-class data returned',
          style: TextStyle(fontSize: 13, color: context.muted)));
    }
    return RSCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(children: [
        // Header row
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(flex: 3, child: Text('Class', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: context.muted))),
            Expanded(flex: 2, child: Text('P', textAlign: TextAlign.right, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: context.muted))),
            Expanded(flex: 2, child: Text('R', textAlign: TextAlign.right, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: context.muted))),
            Expanded(flex: 2, child: Text('mAP50', textAlign: TextAlign.right, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: context.muted))),
          ]),
        ),
        Divider(height: 0.5, color: context.sep),
        ...classes.map((c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Expanded(flex: 3, child: Text(c.className, style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: context.text),
                overflow: TextOverflow.ellipsis)),
            Expanded(flex: 2, child: Text(c.precisionPct, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace',
                    color: metricColor(c.precision)))),
            Expanded(flex: 2, child: Text(c.recallPct, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace',
                    color: metricColor(c.recall)))),
            Expanded(flex: 2, child: Text(c.map50Pct, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, fontFamily: 'monospace',
                    color: metricColor(c.map50)))),
          ]),
        )),
      ]),
    );
  }
}
