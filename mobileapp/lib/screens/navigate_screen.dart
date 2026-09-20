import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../services/location_service.dart';

// ── Shared GPS + detection state ──────────────────────────────
class MapState {
  static double lat    = -1.2921;
  static double lon    = 36.8219;
  static String street = 'Uhuru Highway, Nairobi';
  static List<Detection> detections = [];
}

// ── Open Google Maps navigation (top-level, shared with map_screen) ──
Future<void> openGoogleMapsNav(double lat, double lon) async {
  final native = Uri.parse('google.navigation:q=$lat,$lon&mode=d');
  final web    = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving');
  if (await canLaunchUrl(native)) {
    await launchUrl(native);
  } else {
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }
}

class NavigateScreen extends StatefulWidget {
  const NavigateScreen({super.key});
  @override
  State<NavigateScreen> createState() => _NavigateScreenState();
}

class _NavigateScreenState extends State<NavigateScreen>
    with TickerProviderStateMixin {
  bool _satellite = false;
  int  _etaSecs   = 1169; // 19:29 countdown
  Timer? _etaTimer;

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  // Live location in navigate screen
  StreamSubscription<Position>? _posSub;
  double _lat = MapState.lat;
  double _lon = MapState.lon;

  @override
  void initState() {
    super.initState();

    // Countdown ETA
    _etaTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_etaSecs > 0 && mounted) setState(() => _etaSecs--);
    });

    // GPS pulse ring animation
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _pulseAnim = Tween<double>(begin: 12, end: 28)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));

    // Start live location
    _startLocation();
  }

  Future<void> _startLocation() async {
    final ok = await LocationService.requestPermission();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Location permission required for navigation.\nTap to open Settings.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => Geolocator.openAppSettings(),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }
    // Immediate fix
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
        MapState.lat    = _lat;
        MapState.lon    = _lon;
      });
    }
    // Then stream
    final stream = LocationService.getPositionStream();
    if (stream != null) {
      _posSub = stream.listen((p) {
        if (!mounted) return;
        setState(() {
          _lat = p.latitude;
          _lon = p.longitude;
          MapState.lat = _lat;
          MapState.lon = _lon;
        });
      });
    }
  }

  @override
  void dispose() {
    _etaTimer?.cancel();
    _pulseCtrl.dispose();
    _posSub?.cancel();
    super.dispose();
  }

  String get _etaLabel {
    final m = (_etaSecs ~/ 60).toString().padLeft(2, '0');
    final s = (_etaSecs  % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _highCount =>
      MapState.detections.where((d) => d.severity == 'High').length;

  String get _streetName =>
      MapState.street.split(',').first.trim().isNotEmpty
          ? MapState.street.split(',').first.trim()
          : 'Uhuru Highway';

  @override
  Widget build(BuildContext context) {
    // Tab bar height: 58 (bar) + bottom safe area
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final tabBarH   = 58.0 + bottomPad;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor:           Colors.transparent,
        statusBarIconBrightness:  Brightness.light,
        statusBarBrightness:      Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1A0E),
        // The map fills the screen MINUS the tab bar height at the bottom
        body: SizedBox(
          width:  double.infinity,
          // Exact HTML: height = 100vh - nav-h (82px) — we subtract tabBarH
          height: MediaQuery.of(context).size.height - tabBarH,
          child: Stack(children: [

            // ── Full-bleed map (road or satellite) ──────────
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _satellite
                    ? _SatelliteView(key: const ValueKey('sat'))
                    : _RoadView(
                        key: const ValueKey('road'),
                        pulseAnim: _pulseAnim,
                        pulseCtrl: _pulseCtrl,
                      ),
              ),
            ),

            // Top gradient for legibility
            Positioned(
              top: 0, left: 0, right: 0, height: 130,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.52),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Top bar: back · Road/Sat toggle · recenter ──
            // Matches HTML .map-topbar exactly
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(children: [
                    // Back → detect
                    _GlassBtn(
                      onTap: () => tabNotifier.value = 0,
                      child: const Icon(Icons.chevron_left,
                          color: Colors.white, size: 22),
                    ),

                    const Spacer(),

                    // Road / Satellite pill — matches .map-view-seg
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _SegBtn('Road', !_satellite,
                            () => setState(() => _satellite = false)),
                        _SegBtn('Satellite', _satellite,
                            () => setState(() => _satellite = true)),
                      ]),
                    ),

                    const Spacer(),

                    // Recenter / open maps
                    _GlassBtn(
                      onTap: () =>
                          openGoogleMapsNav(_lat, _lon),
                      child: CustomPaint(
                          size: const Size(15, 15),
                          painter: _CrosshairPainter()),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Bottom sheet — fixed, compact, matches HTML .nav-bottom ──
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _NavSheet(
                etaLabel:   _etaLabel,
                highCount:  _highCount,
                streetName: _streetName,
                lat: _lat, lon: _lon,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Glass round button ─────────────────────────────────────────
class _GlassBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _GlassBtn({required this.child, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38, height: 38,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.40),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Center(child: child),
    ),
  );
}

// ── Segment button ─────────────────────────────────────────────
class _SegBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegBtn(this.label, this.active, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.9)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600,
        color: active
            ? const Color(0xFF0A0A0A)
            : Colors.white.withValues(alpha: 0.65),
      )),
    ),
  );
}

// ── Crosshair painter ──────────────────────────────────────────
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.white..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final cx = s.width / 2, cy = s.height / 2, r = s.width * 0.35;
    c.drawCircle(Offset(cx, cy), r, p);
    c.drawCircle(Offset(cx, cy), r * 0.32, Paint()..color = Colors.white);
    for (final pts in [
      [Offset(cx, 0), Offset(cx, cy - r - 2)],
      [Offset(cx, cy + r + 2), Offset(cx, s.height)],
      [Offset(0, cy), Offset(cx - r - 2, cy)],
      [Offset(cx + r + 2, cy), Offset(s.width, cy)],
    ]) c.drawLine(pts[0], pts[1], p);
  }
  @override bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── Bottom sheet — compact, matches HTML .nav-bottom ─────────
class _NavSheet extends StatelessWidget {
  final String etaLabel, streetName;
  final int highCount;
  final double lat, lon;
  const _NavSheet({
    required this.etaLabel, required this.streetName,
    required this.highCount, required this.lat, required this.lon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [BoxShadow(
            color: Colors.black38, blurRadius: 30, offset: Offset(0, -6))],
        border: Border(top: BorderSide(
            color: context.border.withValues(alpha: 0.5), width: 0.5)),
      ),
      // Fixed padding — no scroll needed
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 36, height: 5,
          decoration: BoxDecoration(color: context.border,
              borderRadius: BorderRadius.circular(3))),
        const SizedBox(height: 14),

        // Route row — matches .nb-route
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(color: AppColors.blue,
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.location_pin, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(streetName, style: TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.text, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Row(children: [
                Text('Route A · ', style: TextStyle(
                    fontSize: 12, color: context.muted,
                    fontFamily: 'monospace')),
                const Text('ACTIVE', style: TextStyle(fontSize: 12,
                    color: AppColors.lime, fontWeight: FontWeight.w600,
                    fontFamily: 'monospace')),
              ]),
            ],
          )),
          // Recenter dot
          GestureDetector(
            onTap: () => openGoogleMapsNav(lat, lon),
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: context.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.border)),
              child: CustomPaint(size: const Size(15, 15),
                  painter: _CrosshairPainter()),
            ),
          ),
        ]),

        const SizedBox(height: 14),

        // Turn card — matches .turn-card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.border),
          ),
          child: Row(children: [
            Expanded(child: Text('In 32m, Turn Left',
                style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: context.text, letterSpacing: -0.5))),
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.turn_left_rounded,
                  color: Colors.white, size: 26),
            ),
          ]),
        ),

        const SizedBox(height: 16),

        // Stats row — matches .nb-stats
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _Stat('ETA',      etaLabel,        context.text),
          Container(width: 1, height: 28, color: context.sep),
          _Stat('Hazards',  '$highCount HIGH',
              highCount > 0 ? AppColors.red : context.text),
          Container(width: 1, height: 28, color: context.sep),
          _Stat('Distance', '19 km',         context.text),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: TextStyle(fontSize: 11, color: context.muted,
        fontFamily: 'monospace')),
    const SizedBox(height: 3),
    Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
        color: color, fontFamily: 'monospace', letterSpacing: -0.3)),
  ]);
}

// ══════════════════════════════════════════════════════════════
//  ROAD VIEW — perspective road with animated GPS pulse
// ══════════════════════════════════════════════════════════════
class _RoadView extends StatelessWidget {
  final Animation<double> pulseAnim;
  final AnimationController pulseCtrl;
  const _RoadView({super.key, required this.pulseAnim, required this.pulseCtrl});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: pulseCtrl,
    builder: (_, __) => CustomPaint(
      painter: _RoadPainter(
        pulseR:       pulseAnim.value,
        pulseOpacity: (1 - pulseCtrl.value) * 0.35,
      ),
      size: Size.infinite,
    ),
  );
}

class _RoadPainter extends CustomPainter {
  final double pulseR, pulseOpacity;
  _RoadPainter({required this.pulseR, required this.pulseOpacity});

  // Map HTML 390×620 viewBox → canvas
  Offset _p(Size s, double x, double y) =>
      Offset(x / 390 * s.width, y / 620 * s.height);
  double _x(Size s, double v) => v / 390 * s.width;
  double _y(Size s, double v) => v / 620 * s.height;

  @override
  void paint(Canvas c, Size s) {
    // Sky gradient
    c.drawRect(Rect.fromLTWH(0, 0, s.width, s.height), Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFF2A4A5A), Color(0xFF5A8A80)],
      ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)));

    // Clouds
    void cloud(double cx, double cy, double rx, double ry, double op) =>
        c.drawOval(Rect.fromCenter(center: _p(s, cx, cy),
            width: _x(s, rx*2), height: _y(s, ry*2)),
            Paint()..color = Colors.white.withValues(alpha: op));
    cloud(90, 70, 58, 22, .14);
    cloud(130, 62, 44, 18, .16);
    cloud(300, 90, 62, 24, .11);

    // Trees
    void tree(double cx, double cy, double rx, double ry, Color col) =>
        c.drawOval(Rect.fromCenter(center: _p(s, cx, cy),
            width: _x(s, rx*2), height: _y(s, ry*2)),
            Paint()..color = col);
    tree( 20, 260, 42, 74, const Color(0xFF142810).withValues(alpha: .98));
    tree( 58, 240, 52, 86, const Color(0xFF1E3C18).withValues(alpha: .98));
    tree(370, 252, 42, 74, const Color(0xFF142810).withValues(alpha: .98));
    tree(334, 235, 50, 82, const Color(0xFF1E3C18).withValues(alpha: .95));
    tree(145, 168, 35, 58, const Color(0xFF2A4820).withValues(alpha: .70));
    tree(248, 160, 36, 60, const Color(0xFF2A4820).withValues(alpha: .65));

    // Road M102 620 L158 295 L232 295 L288 620
    c.drawPath(Path()
      ..moveTo(_x(s,102), _y(s,620))
      ..lineTo(_x(s,158), _y(s,295))
      ..lineTo(_x(s,232), _y(s,295))
      ..lineTo(_x(s,288), _y(s,620))..close(),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: const [Color(0xFF484E40), Color(0xFF242820)],
      ).createShader(Rect.fromLTWH(
          _x(s,102), _y(s,295), _x(s,186), _y(s,325))));

    // Road edges
    final ep = Paint()..color=const Color(0xFF5A6050)
        ..strokeWidth=1.5..style=PaintingStyle.stroke;
    c.drawLine(_p(s,104,620), _p(s,160,297), ep);
    c.drawLine(_p(s,286,620), _p(s,230,297), ep);

    // Horizon curve
    c.drawPath(Path()
      ..moveTo(_x(s,158),_y(s,295))
      ..quadraticBezierTo(_x(s,195),_y(s,278),_x(s,232),_y(s,295)),
      Paint()..color=const Color(0xFF5A6050)
             ..strokeWidth=2..style=PaintingStyle.stroke);

    // Center dashes
    void dash(double y1, double y2, double op, double sw) =>
        c.drawLine(_p(s,195,y1), _p(s,195,y2), Paint()
          ..color=const Color(0xFFC8B040).withValues(alpha:op)
          ..strokeWidth=sw..strokeCap=StrokeCap.round..style=PaintingStyle.stroke);
    dash(588,558,.90,5.5); dash(538,508,.70,5.5);
    dash(488,462,.50,5.0); dash(444,424,.30,4.5);

    // Green route line
    c.drawLine(_p(s,195,620), _p(s,195,365), Paint()
      ..color=AppColors.lime.withValues(alpha:.92)
      ..strokeWidth=_x(s,5.5)..strokeCap=StrokeCap.round..style=PaintingStyle.stroke);
    c.drawPath(Path()
      ..moveTo(_x(s,195),_y(s,365))
      ..quadraticBezierTo(_x(s,196),_y(s,315),_x(s,225),_y(s,297)),
      Paint()..color=AppColors.lime.withValues(alpha:.55)
             ..strokeWidth=_x(s,4)..strokeCap=StrokeCap.round..style=PaintingStyle.stroke);

    // Animated GPS pulse ring
    final gps = _p(s,195,455);
    c.drawCircle(gps, _y(s,pulseR), Paint()
      ..color=AppColors.lime.withValues(alpha:pulseOpacity)
      ..style=PaintingStyle.stroke..strokeWidth=2.5);
    // Static outer ring
    c.drawCircle(gps, _y(s,18), Paint()
      ..color=AppColors.lime.withValues(alpha:.30)
      ..style=PaintingStyle.stroke..strokeWidth=2);
    // GPS dot + white centre
    c.drawCircle(gps, _y(s,12), Paint()..color=AppColors.lime);
    c.drawCircle(gps, _y(s, 6), Paint()..color=Colors.white);
  }

  @override bool shouldRepaint(_RoadPainter o) =>
      o.pulseR != pulseR || o.pulseOpacity != pulseOpacity;
}

// ══════════════════════════════════════════════════════════════
//  SATELLITE VIEW
// ══════════════════════════════════════════════════════════════
class _SatelliteView extends StatelessWidget {
  const _SatelliteView({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SatPainter(), size: Size.infinite);
}

class _SatPainter extends CustomPainter {
  Offset _p(Size s, double x, double y) =>
      Offset(x/390*s.width, y/620*s.height);
  double _x(Size s, double v) => v/390*s.width;
  double _y(Size s, double v) => v/620*s.height;

  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Rect.fromLTWH(0,0,s.width,s.height), Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        colors: const [Color(0xFF1E3020), Color(0xFF0C1A0C)],
      ).createShader(Rect.fromLTWH(0,0,s.width,s.height)));

    void blk(double x,double y,double w,double h,Color col) =>
        c.drawRect(Rect.fromLTWH(_x(s,x),_y(s,y),_x(s,w),_y(s,h)),
            Paint()..color=col);
    blk(  0,  0,140,220, const Color(0xFF1A2E18).withValues(alpha:.9));
    blk(250,  0,140,240, const Color(0xFF1A2E18).withValues(alpha:.9));
    blk(  0,350,120,270, const Color(0xFF142410).withValues(alpha:.85));
    blk(270,330,120,290, const Color(0xFF142410).withValues(alpha:.85));

    void bld(double x,double y,double w,double h,Color col) =>
        c.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(_x(s,x),_y(s,y),_x(s,w),_y(s,h)),
            const Radius.circular(4)),
            Paint()..color=col.withValues(alpha:.8));
    bld( 20,270, 70,50,const Color(0xFF223C1E));
    bld(300,250, 65,58,const Color(0xFF223C1E));
    bld( 25,380, 50,62,const Color(0xFF1A3018));

    c.drawRect(Rect.fromLTWH(_x(s,174),0,_x(s,42),s.height),
        Paint()..color=const Color(0xFF3C4038));
    c.drawRect(Rect.fromLTWH(_x(s,182),0,_x(s,26),s.height),
        Paint()..color=const Color(0xFF2C2E28));

    c.drawLine(_p(s,195,620), _p(s,195,100), Paint()
      ..color=AppColors.lime.withValues(alpha:.88)
      ..strokeWidth=_x(s,5.5)..strokeCap=StrokeCap.round..style=PaintingStyle.stroke);

    void ring(double x,double y,double r,Color col) =>
        c.drawCircle(_p(s,x,y), _y(s,r), Paint()
          ..color=col..style=PaintingStyle.stroke..strokeWidth=2);
    ring(192,235,8,AppColors.red.withValues(alpha:.9));
    ring(197,380,7,AppColors.amber.withValues(alpha:.8));

    c.drawCircle(_p(s,195,455), _y(s,11), Paint()..color=AppColors.lime);
    c.drawCircle(_p(s,195,455), _y(s, 5), Paint()..color=Colors.white);
  }

  @override bool shouldRepaint(covariant CustomPainter _) => false;
}
