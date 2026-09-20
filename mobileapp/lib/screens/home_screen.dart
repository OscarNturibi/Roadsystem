import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import 'detect_screen.dart';
import 'navigate_screen.dart';
import 'map_screen.dart';
import 'reports_screen.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _idx = 0;

  static const _pages = [
    DetectScreen(),
    NavigateScreen(),
    MapScreen(),
    ReportsScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Listen for tab switches from any screen (e.g. Live Nav button)
    tabNotifier.addListener(_onTabNotifier);
  }

  @override
  void dispose() {
    tabNotifier.removeListener(_onTabNotifier);
    super.dispose();
  }

  void _onTabNotifier() {
    if (tabNotifier.value != _idx) {
      setState(() => _idx = tabNotifier.value);
    }
  }

  void _onTab(int i) {
    HapticFeedback.selectionClick();
    tabNotifier.value = i;
    setState(() => _idx = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(children: [
        IndexedStack(index: _idx, children: _pages),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _RSTabBar(current: _idx, onTap: _onTab),
        ),
      ]),
    );
  }
}

// ── Tab bar — frosted glass, matching HTML exactly ─────────────
class _RSTabBar extends StatelessWidget {
  final int current;
  final void Function(int) onTap;
  const _RSTabBar({required this.current, required this.onTap});

  static const _tabs = [
    ('Detect',    _detectIcon),
    ('Navigate',  _navIcon),
    ('Map',       _mapIcon),
    ('Reports',   _reportsIcon),
    ('Analytics', _analyticsIcon),
    ('Profile',   _profileIcon),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xF01C1C1F)
                : const Color(0xF5F9F9F9),
            border: Border(
                top: BorderSide(color: context.border, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 58,
              child: Row(
                children: _tabs.asMap().entries.map((e) => _TabItem(
                  label:   e.value.$1,
                  iconFn:  e.value.$2,
                  active:  e.key == current,
                  onTap:   () => onTap(e.key),
                )).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Icon painters matching HTML SVGs
  static Widget _detectIcon(Color c) => Icon(Icons.manage_search_rounded, color: c, size: 22);
  static Widget _navIcon(Color c)    => Icon(Icons.navigation_rounded,    color: c, size: 22);
  static Widget _mapIcon(Color c)    => Icon(Icons.location_on_outlined,  color: c, size: 22);
  static Widget _reportsIcon(Color c)=> Icon(Icons.receipt_long_outlined, color: c, size: 22);
  static Widget _analyticsIcon(Color c)=>Icon(Icons.bar_chart_rounded,    color: c, size: 22);
  static Widget _profileIcon(Color c)=> Icon(Icons.person_outline_rounded,color: c, size: 22);
}

class _TabItem extends StatelessWidget {
  final String label;
  final Widget Function(Color) iconFn;
  final bool active;
  final VoidCallback onTap;
  const _TabItem({required this.label, required this.iconFn,
      required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.lime : context.muted;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: active ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.elasticOut,
                child: iconFn(color),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w500,
                color: color, letterSpacing: 0.1,
              )),
              const SizedBox(height: 3),
              // Indicator dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: active ? 16 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: active ? AppColors.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
