import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../widgets/rs_card.dart';
import 'navigate_screen.dart' show MapState, openGoogleMapsNav;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapCtrl = MapController();
  Detection? _selected;

  @override
  Widget build(BuildContext context) {
    final dets   = MapState.detections;
    final center = LatLng(MapState.lat, MapState.lon);

    // Build markers
    final markers = [
      // Current GPS position
      Marker(
        point: center,
        width: 44, height: 44,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [BoxShadow(
                  color: AppColors.blue.withValues(alpha: 0.4), blurRadius: 8)],
            ),
            child: const Icon(Icons.my_location,
                color: Colors.white, size: 18),
          ),
        ]),
      ),
      // Defect pins
      ...dets.map((d) => Marker(
        point: center, // same GPS — real app would have per-detection coords
        width: 52, height: 52,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() => _selected = _selected == d ? null : d);
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _selected == d ? 40 : 32,
              height: _selected == d ? 40 : 32,
              decoration: BoxDecoration(
                color: d.severityColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(
                    color: d.severityColor.withValues(alpha: 0.5),
                    blurRadius: _selected == d ? 16 : 8,
                    spreadRadius: _selected == d ? 3 : 0)],
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Colors.white, size: 15),
            ),
            Container(width: 2, height: 8, color: d.severityColor),
          ]),
        ),
      )),
    ];

    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(children: [
        // ── Full screen map ──────────────────────────────
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.roadsense.app',
                maxZoom: 19,
              ),
              MarkerLayer(markers: markers),
            ],
          ),
        ),

        // ── Top app bar (frosted glass) ──────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.border, width: 0.5),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16)],
              ),
              child: Row(children: [
                // Title
                RichText(text: TextSpan(
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                      letterSpacing: -0.5, color: context.text),
                  children: const [
                    TextSpan(text: 'Live '),
                    TextSpan(text: 'Map',
                        style: TextStyle(color: AppColors.lime)),
                  ],
                )),
                const SizedBox(width: 8),
                // Pin count chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.border, width: 0.5),
                  ),
                  child: Text('${dets.length} pins',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: context.muted)),
                ),
                const Spacer(),
                // Recenter
                GestureDetector(
                  onTap: () {
                    _mapCtrl.move(center, 15.5);
                    HapticFeedback.selectionClick();
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: context.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: context.border),
                    ),
                    child: Icon(Icons.gps_fixed_rounded,
                        color: context.muted, size: 16),
                  ),
                ),
                const SizedBox(width: 8),
                // Open Google Maps
                GestureDetector(
                  onTap: () => openGoogleMapsNav(MapState.lat, MapState.lon),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(children: [
                      Icon(Icons.navigation_rounded,
                          color: Colors.white, size: 13),
                      SizedBox(width: 5),
                      Text('Navigate',
                          style: TextStyle(fontSize: 13,
                              fontWeight: FontWeight.w600, color: Colors.white)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),

        // ── Selected detection detail card ────────────────
        if (_selected != null)
          Positioned(
            left: 12, right: 12,
            bottom: 100 + MediaQuery.of(context).padding.bottom,
            child: _DetectionCard(
              detection: _selected!,
              onDismiss: () => setState(() => _selected = null),
            ),
          ),

        // ── Empty state overlay ────────────────────────────
        if (dets.isEmpty)
          Positioned(
            left: 12, right: 12,
            bottom: 100 + MediaQuery.of(context).padding.bottom,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.border, width: 0.5),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: context.muted, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(
                  'Run a scan on the Detect tab to pin defects on the map.',
                  style: TextStyle(fontSize: 13, color: context.muted),
                )),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ── Detection detail popup card ───────────────────────────────
class _DetectionCard extends StatelessWidget {
  final Detection detection;
  final VoidCallback onDismiss;
  const _DetectionCard({required this.detection, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final d = detection;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border, width: 0.5),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.15), blurRadius: 20)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: d.severityBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: d.severityColor.withValues(alpha: 0.3)),
            ),
            child: Icon(
              d.severity == 'High' ? Icons.warning_amber_rounded
                  : d.severity == 'Medium' ? Icons.info_outline
                  : Icons.check_circle_outline,
              color: d.severityColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.className,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: context.text)),
              Text('${d.classCode} · ${d.confidencePct} confidence',
                  style: TextStyle(fontSize: 12, color: context.muted,
                      fontFamily: 'monospace')),
            ])),
          GestureDetector(
            onTap: onDismiss,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                  color: context.surface2, shape: BoxShape.circle),
              child: Icon(Icons.close, color: context.muted, size: 14),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _InfoPill(label: 'Severity', value: d.severity, color: d.severityColor),
          const SizedBox(width: 8),
          _InfoPill(label: 'Area', value: '${d.area} px²', color: context.muted),
          const SizedBox(width: 8),
          _InfoPill(label: 'GPS',
              value: '${MapState.lat.toStringAsFixed(3)}, ${MapState.lon.toStringAsFixed(3)}',
              color: context.muted),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => openGoogleMapsNav(MapState.lat, MapState.lon),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.blue.withValues(alpha: 0.25)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.navigation_rounded,
                    color: AppColors.blue, size: 16),
                SizedBox(width: 8),
                Text('Navigate to defect',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppColors.blue)),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label, value;
  final Color color;
  const _InfoPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Column(children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: context.muted)),
        const SizedBox(height: 2),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: color, fontFamily: 'monospace')),
      ]),
    ));
  }
}
