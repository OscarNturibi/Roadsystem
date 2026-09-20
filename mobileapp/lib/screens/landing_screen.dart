import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
//  DATA: each slide shown in the PageView
// ─────────────────────────────────────────────────────────────
class _Slide {
  final String tag;
  final String headline;
  final String accent;      // highlighted word in headline
  final String body;
  final Color  accentColor;
  const _Slide({
    required this.tag,
    required this.headline,
    required this.accent,
    required this.body,
    this.accentColor = AppColors.lime,
  });
}

const _slides = [
  _Slide(
    tag:      'YOLOv8 · Real-time Detection',
    headline: 'Smart Roads\nStart ',
    accent:   'Here.',
    body:     'AI-powered pothole and road defect detection '
              'with live GPS mapping for Nairobi\'s roads.',
  ),
  _Slide(
    tag:      'Live GPS · Geocoded',
    headline: 'Map Every\nDefect ',
    accent:   'Live.',
    body:     'Every scan is GPS-tagged and reverse-geocoded '
              'to a real street name — automatically.',
    accentColor: AppColors.blue,
  ),
  _Slide(
    tag:      'Analytics · Reports',
    headline: 'Instant\nRoad ',
    accent:   'Reports.',
    body:     'Health scores, severity breakdowns, and '
              'WhatsApp alerts to road authorities in one tap.',
    accentColor: AppColors.amber,
  ),
];

// ─────────────────────────────────────────────────────────────
//  LANDING SCREEN
// ─────────────────────────────────────────────────────────────
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int   _page   = 0;
  Timer? _autoTimer;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();

    // Entrance fade
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Auto-advance every 4 s
    _autoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_page + 1) % _slides.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _enter() {
    _autoTimer?.cancel();
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder:        (_, a, __) => const HomeScreen(),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 400),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Light icons on dark background — real phone clock shows through
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor:          Colors.transparent,
        statusBarIconBrightness: Brightness.light,   // white icons
        statusBarBrightness:     Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1F0A),
        body: Stack(children: [

          // ── Road illustration (full screen) ─────────────
          Positioned.fill(
            child: CustomPaint(painter: _RoadBgPainter()),
          ),

          // ── Bottom dark gradient ─────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            height: size.height * 0.65,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin:  Alignment.topCenter,
                  end:    Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xDD0A1F0A), Color(0xFF0A1F0A)],
                  stops:  [0, 0.38, 1],
                ),
              ),
            ),
          ),

          // ── Content — SafeArea so real status bar is respected ──
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: Column(children: [
                // Flexible spacer — shrinks on small screens
                Expanded(flex: 3, child: const SizedBox.shrink()),

                // ── PageView: slides ─────────────────────
                SizedBox(
                  height: 230,
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount:  _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) {
                      final slide = _slides[i];
                      return _SlideContent(slide: slide);
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // ── Dot indicators ───────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_slides.length, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width:  active ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active
                            ? _slides[_page].accentColor
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 20),

                // ── Buttons ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(children: [
                    SizedBox(
                      width: double.infinity,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: _slides[_page].accentColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: _slides[_page].accentColor
                                  .withValues(alpha: 0.40),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _enter,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 17),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.play_circle_fill,
                                      size: 20,
                                      color: Color(0xFF0A1F0A)),
                                  const SizedBox(width: 10),
                                  const Text('Get Started',
                                      style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0A1F0A),
                                          letterSpacing: -0.3)),
                                  const SizedBox(width: 10),
                                  const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                      color: Color(0xFF0A1F0A)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _enter,
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Colors.white.withValues(alpha: 0.80),
                          side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.20),
                              width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                        ),
                        child: const Text('Explore Features',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      'GPS · YOLOv8 · Flask · Auto-sync',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.28),
                          fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ]),
                ),
                // Bottom breathing room
                Expanded(flex: 1, child: const SizedBox.shrink()),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Individual slide content
// ─────────────────────────────────────────────────────────────
class _SlideContent extends StatelessWidget {
  final _Slide slide;
  const _SlideContent({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tag pill with animated dot
          Row(children: [
            _PulsingDot(color: slide.accentColor),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: slide.accentColor.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: slide.accentColor.withValues(alpha: 0.28)),
              ),
              child: Text(slide.tag,
                  style: TextStyle(
                      color: slide.accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3)),
            ),
          ]),

          const SizedBox(height: 16),

          // Headline
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                  letterSpacing: -1.8),
              children: [
                TextSpan(text: slide.headline),
                TextSpan(
                    text: slide.accent,
                    style: TextStyle(color: slide.accentColor)),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Body
          Text(slide.body,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontSize: 14,
                  height: 1.6)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Pulsing dot (animated)
// ─────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            color: widget.color
                .withValues(alpha: 0.4 + _c.value * 0.6),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color:
                      widget.color.withValues(alpha: _c.value * 0.5),
                  blurRadius: 6),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Road background painter (no fake status bar)
// ─────────────────────────────────────────────────────────────
class _RoadBgPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width;
    final h = s.height;

    // Sky gradient
    c.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [Color(0xFF1A4020), Color(0xFF0A1F0A)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    void tree(double cx, double cy, double rx, double ry, Color col) {
      c.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy), width: rx * 2, height: ry * 2),
        Paint()..color = col,
      );
    }
    tree(w * .08, h * .38, 44, 74, const Color(0xFF142810));
    tree(w * .16, h * .34, 50, 82, const Color(0xFF1E3C18));
    tree(w * .92, h * .36, 44, 74, const Color(0xFF142810));
    tree(w * .84, h * .32, 50, 80, const Color(0xFF1E3C18));
    tree(w * .37, h * .26, 35, 56, const Color(0xFF243A20));
    tree(w * .63, h * .24, 36, 58, const Color(0xFF243A20));

    // Ground
    c.drawPath(
      Path()
        ..moveTo(0, h * .58)
        ..cubicTo(w * .3, h * .52, w * .7, h * .52, w, h * .58)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = const Color(0xFF1A3018),
    );

    // Road
    c.drawPath(
      Path()
        ..moveTo(w * .28, h)
        ..lineTo(w * .42, h * .52)
        ..lineTo(w * .58, h * .52)
        ..lineTo(w * .72, h)
        ..close(),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [Color(0xFF484E40), Color(0xFF242820)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Road edges
    final ep = Paint()
      ..color = const Color(0xFF5A6050)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    c.drawLine(Offset(w * .28, h), Offset(w * .42, h * .52), ep);
    c.drawLine(Offset(w * .72, h), Offset(w * .58, h * .52), ep);

    final cx = w * .5;
    // FIX: if statement body must be in braces
    final dashData = [
      [h * .92, h * .86, 0.9],
      [h * .80, h * .74, 0.65],
      [h * .68, h * .63, 0.40],
    ];
    for (final d in dashData) {
      c.drawLine(
        Offset(cx, d[0]),
        Offset(cx, d[1]),
        Paint()
          ..color = const Color(0xFFC8A830)
              .withValues(alpha: d[2])
          ..strokeWidth = 4.5
          ..strokeCap   = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    // Route line
    c.drawLine(
      Offset(cx, h * .75),
      Offset(cx, h * .54),
      Paint()
        ..color = AppColors.lime.withValues(alpha: .75)
        ..strokeWidth = 4
        ..strokeCap   = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // GPS dot
    final gx = cx, gy = h * .51;
    c.drawCircle(Offset(gx, gy), 20,
        Paint()
          ..color = AppColors.lime.withValues(alpha: .18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    c.drawCircle(Offset(gx, gy), 13,
        Paint()
          ..color = AppColors.lime.withValues(alpha: .40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
    c.drawCircle(Offset(gx, gy), 7,
        Paint()..color = AppColors.lime);

    // Pothole detection box
    final bx = w * .43, by = h * .68;
    final bw = w * .085, bh = h * .058;
    c.drawOval(
      Rect.fromCenter(
          center: Offset(bx + bw * .3, by + bh * .4),
          width:  bw * .7,
          height: bh * .5),
      Paint()..color = const Color(0xFF151A10).withValues(alpha: .8),
    );
    c.drawRect(
      Rect.fromLTWH(bx, by, bw * 1.1, bh * 1.1),
      Paint()
        ..color = AppColors.red.withValues(alpha: .9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    c.drawRRect(
      RRect.fromRectAndCorners(
          Rect.fromLTWH(bx, by - 13, bw * 1.1, 13),
          topLeft:  const Radius.circular(3),
          topRight: const Radius.circular(3)),
      Paint()..color = AppColors.red.withValues(alpha: .9),
    );
  }

  @override
  bool shouldRepaint(_RoadBgPainter _) => false;
}
