import 'dart:async';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../main.dart';
import '../theme/app_theme.dart';
import '../models/detection_model.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/rs_card.dart';
import '../widgets/detection_painter.dart';
import 'navigate_screen.dart' show MapState;
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

// Input mode
enum _InputMode { upload, camera, rtsp }

class DetectScreen extends StatefulWidget {
  const DetectScreen({super.key});
  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  File?            _image;
  DetectionResult? _result;
  Position?        _position;
  PlaceInfo?       _place;
  String           _street  = 'Acquiring location…';
  bool             _loading = false;
  String?          _error;
  VisualizationMode _vizMode = VisualizationMode.bbox;

  _InputMode _inputMode = _InputMode.upload;

  final _picker = ImagePicker();
  double _conf = 0.30;
  double _iou  = 0.45;

  StreamSubscription<Position>? _locationSub;

  // Real model list, fetched from GET /models -- replaces the previous
  // hardcoded list (which included "YOLOv8l · Max", a variant that was
  // never actually trained, and tapping any chip never told the server
  // to switch models).
  List<Map<String, dynamic>> _models = [];
  String? _activeModelKey;
  bool _modelsLoading = true;
  bool _switchingModel = false;

  Future<void> _loadModels() async {
    final list = await ApiService.fetchModels();
    if (!mounted) return;
    setState(() {
      _models = list;
      _modelsLoading = false;
      final active = list.firstWhere(
            (m) => m['active'] == true,
        orElse: () => <String, dynamic>{},
      );
      _activeModelKey = active['key'] as String?;
    });
  }

  Future<void> _onSelectModel(Map<String, dynamic> m) async {
    final key = m['key'] as String;
    final available = m['available'] == true;
    if (!available) {
      _snack('${m['variant']?.toString().toUpperCase() ?? key} weights not '
          'found on the server -- train/download it first.');
      return;
    }
    if (key == _activeModelKey || _switchingModel) return;

    setState(() => _switchingModel = true);
    HapticFeedback.selectionClick();
    final ok = await ApiService.selectModel(key);
    if (!mounted) return;
    setState(() {
      _switchingModel = false;
      if (ok) _activeModelKey = key;
    });
    if (!ok) _snack('Failed to switch model -- check the server connection.');
  }

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadModels();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    // One-shot for immediate position
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      setState(() { _position = pos; _street = 'Getting address…'; });
      // Reverse geocode immediately
      final place = await LocationService.reverseGeocode(
          pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _place  = place;
        _street = place.displayShort;
        MapState.lat    = pos.latitude;
        MapState.lon    = pos.longitude;
        MapState.street = _street;
      });
    }
    // Then subscribe to live stream
    final stream = LocationService.getPositionStream();
    if (stream != null) {
      _locationSub = stream.listen((p) async {
        if (!mounted) return;
        setState(() { _position = p; });
        // Re-geocode on significant movement
        final place = await LocationService.reverseGeocode(
            p.latitude, p.longitude);
        if (!mounted) return;
        setState(() {
          _place  = place;
          _street = place.displayShort;
          MapState.lat    = p.latitude;
          MapState.lon    = p.longitude;
          MapState.street = _street;
        });
      });
    }
  }

  Future<void> _pick(ImageSource src) async {
    final x = await _picker.pickImage(
        source: src, imageQuality: 90);
    if (x == null) return;
    setState(() {
      _image  = File(x.path);
      _result = null;
      _error  = null;
    });
  }

  Future<void> _detect() async {
    if (_image == null) {
      _snack('Please select an image first');
      return;
    }
    setState(() { _loading = true; _error = null; });
    HapticFeedback.mediumImpact();
    try {
      final result = await ApiService.detect(
        _image!,
        lat:    _position?.latitude,
        lon:    _position?.longitude,
        street: _street,
        conf:   _conf,
        iou:    _iou,
      );
      MapState.lat        = _position?.latitude  ?? -1.2921;
      MapState.lon        = _position?.longitude ?? 36.8219;
      MapState.detections = result.detections;
      MapState.street     = _street;
      setState(() => _result = result);
      if (result.detections.isNotEmpty) HapticFeedback.heavyImpact();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }


  Future<void> _openGoogleMapsNav() async {
    final lat = _position?.latitude ?? MapState.lat;
    final lon = _position?.longitude ?? MapState.lon;
    final googleMapsUrl = Uri.parse(
        'google.navigation:q=$lat,$lon&mode=d');
    final fallback = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving');
    if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl);
    } else {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWhatsApp() async {
    final r = _result;

    if (r == null) {
      _snack('Run road detection first.');
      return;
    }

    try {
      // ---------------------------------------------------------
      // 1. Get location information
      // ---------------------------------------------------------

      final lat = _position?.latitude ?? MapState.lat;
      final lon = _position?.longitude ?? MapState.lon;

      // ---------------------------------------------------------
      // 2. Build alert message
      // ---------------------------------------------------------

      final msgText = '''
🚨 RoadSense v4 Alert

📍 Location: $_street
🗺 GPS: ${lat.toStringAsFixed(4)}°, ${lon.toStringAsFixed(4)}°
⚠️ High severity: ${r.highCount} | Total defects: ${r.detections.length}
❤️ Road health: ${r.healthScore}/100

Immediate road repairs required.
''';

      // ---------------------------------------------------------
      // 3. Generate annotated image
      // ---------------------------------------------------------

      if (_image == null) {
        _snack('No image available for the alert.');
        return;
      }

      final annotatedBytes = await _renderAnnotatedImage();

      if (annotatedBytes == null) {
        _snack('Could not create annotated image.');
        return;
      }

      // ---------------------------------------------------------
      // 4. Save it as a real PNG and hand it to the OS share sheet
      //    (Share charm on Windows, share sheet on Android/iOS).
      //    This brings back the "pick an app" dialog you had before,
      //    now with the image correctly saved/labelled as PNG instead
      //    of the old PNG-bytes-in-a-.jpg mismatch.
      // ---------------------------------------------------------

      final tempDir = await getTemporaryDirectory();

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final imageFile = File(
        '${tempDir.path}${Platform.pathSeparator}RoadSense_Alert_$timestamp.png',
      );

      await imageFile.writeAsBytes(
        annotatedBytes,
        flush: true,
      );

      await Share.shareXFiles(
        [
          XFile(
            imageFile.path,
            mimeType: 'image/png',
          ),
        ],
        text: msgText,
        subject:
        'RoadSense v4 Alert — ${r.summary.condition} Condition',
      );

      // -------------------------------------------------------
      // Windows' share target often only passes the file through
      // and drops the accompanying "text" — WhatsApp Desktop's
      // share handler in particular ignores it. So also put the
      // alert text on the clipboard as a reliable fallback: the
      // user can paste it into the chat right after attaching
      // the image.
      // -------------------------------------------------------

      if (Platform.isWindows) {
        await Clipboard.setData(
          ClipboardData(text: msgText),
        );

        if (mounted) {
          _snack(
            'Alert text copied to clipboard — paste it into the chat.',
          );
        }
      }
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR: WhatsApp alert failed: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (mounted) {
        _snack(
          'Could not prepare WhatsApp alert: $e',
        );
      }
    }
  }

  Future<Uint8List?> _renderAnnotatedImage() async {
    if (_image == null || _result == null) {
      return null;
    }

    try {
      // Read original image
      final rawBytes = await _image!.readAsBytes();

      // Decode image
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final srcImg = frame.image;

      final double imgW = srcImg.width.toDouble();
      final double imgH = srcImg.height.toDouble();

      // Create drawing recorder
      final recorder = ui.PictureRecorder();

      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(
          0,
          0,
          imgW,
          imgH,
        ),
      );

      // Draw original image
      canvas.drawImage(
        srcImg,
        Offset.zero,
        Paint(),
      );

      // Draw YOLO detections
      DetectionPainter(
        detections: _result!.detections,
        imageWidth: imgW,
        imageHeight: imgH,
        mode: VisualizationMode.bbox,
      ).paint(
        canvas,
        Size(imgW, imgH),
      );

      // RoadSense watermark
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'RoadSense v4',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(
                color: Colors.black,
                blurRadius: 8,
                offset: Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();

      textPainter.paint(
        canvas,
        Offset(
          12,
          imgH - textPainter.height - 12,
        ),
      );

      // Finish drawing
      final picture = recorder.endRecording();

      final renderedImage = await picture.toImage(
        srcImg.width,
        srcImg.height,
      );

      // IMPORTANT:
      // Return actual PNG bytes.
      final byteData = await renderedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (e, stackTrace) {
      debugPrint(
        'ERROR: Failed to render annotated image: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      return null;
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Color get _healthColor {
    final s = _result?.healthScore ?? 100;
    if (s >= 70) return AppColors.lime;
    if (s >= 40) return AppColors.amber;
    return AppColors.red;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning, Engineer 👋';
    if (h < 17) return 'Good afternoon, Engineer 👋';
    return 'Good evening, Engineer 👋';
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      // FAB
      floatingActionButton: FloatingActionButton(
        onPressed: _loading ? null : _detect,
        backgroundColor: AppColors.lime,
        foregroundColor: const Color(0xFF0A1F0A),
        elevation: 4,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        child: _loading
            ? const SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF0A1F0A)))
            : const Icon(Icons.manage_search_rounded, size: 26),
      ),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHeroCard(),
                const SizedBox(height: 12),
                _buildGpsCard(),
                const SizedBox(height: 12),
                _buildStatGrid(),
                _sectionLabel('Input Source'),
                _buildInputSource(),
                _buildDropZone(),        // ← drop zone below selector
                _sectionLabel('Model Configuration'),
                _buildModelConfig(),
                _sectionLabel('Detection Output'),
                _buildResultCard(),
                if (_result != null &&
                    _result!.detections.isNotEmpty) ...[
                  _sectionLabel('Detected Defects'),
                  _buildDefectList(),
                ],
                const SizedBox(height: 96),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── App bar ──────────────────────────────────────────────────
  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      backgroundColor: context.bg,
      pinned: true, floating: true,
      expandedHeight: 0,
      toolbarHeight: 60,
      title: Row(children: [
        // App logo (road icon, NOT Flutter logo)
        _RSLogo(),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800,
                letterSpacing: -0.5, color: context.text),
            children: const [
              TextSpan(text: 'Road'),
              TextSpan(text: 'Sense',
                  style: TextStyle(color: AppColors.lime)),
            ],
          ),
        ),
      ]),
      actions: [
        // GPS live pill
        Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.lime.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.lime.withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            _LivePip(),
            SizedBox(width: 5),
            Text('GPS',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.lime,
                    letterSpacing: 0.3, fontFamily: 'monospace')),
          ]),
        ),
        // Theme toggle
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, mode, __) => IconButton(
            onPressed: () {
              themeNotifier.value = mode == ThemeMode.dark
                  ? ThemeMode.light : ThemeMode.dark;
            },
            icon: Icon(
                mode == ThemeMode.dark
                    ? Icons.wb_sunny_outlined
                    : Icons.nightlight_round,
                color: context.muted, size: 20),
          ),
        ),
        // Notifications
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.notifications_outlined,
                  color: context.muted, size: 22),
            ),
            Positioned(
              right: 10, top: 10,
              child: Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: AppColors.red, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Hero card ────────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0A1F0A), Color(0xFF1A3A18)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting(),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: Colors.white60)),
        const SizedBox(height: 8),
        RichText(
          text: const TextSpan(
            style: TextStyle(
                fontSize: 25, fontWeight: FontWeight.w800,
                color: Colors.white, letterSpacing: -0.5, height: 1.15),
            children: [
              TextSpan(text: "Let's scan the\n"),
              TextSpan(text: 'road ahead.',
                  style: TextStyle(color: AppColors.lime)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _HeroBtn(
              label: 'Live Nav', icon: Icons.navigation_rounded,
              onTap: () { tabNotifier.value = 1; }, primary: true)),
          const SizedBox(width: 8),
          Expanded(child: _HeroBtn(
              label: 'Quick Scan', icon: Icons.camera_alt_outlined,
              onTap: () => _pick(ImageSource.camera), primary: false)),
        ]),
      ]),
    );
  }

  // ── GPS strip ────────────────────────────────────────────────
  Widget _buildGpsCard() {
    final coordinates = _position != null
        ? LocationService.formatCoords(
        _position!.latitude, _position!.longitude)
        : 'LAT — · LNG —';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 0.5),
        boxShadow: context.isDark ? [] : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.amber.withValues(alpha: 0.2)),
          ),
          child: const Icon(Icons.my_location_rounded,
              color: AppColors.amber, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_street,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: context.text)),
            Text(coordinates,
                style: TextStyle(fontSize: 11, color: context.muted,
                    fontFamily: 'monospace')),
          ],
        )),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.lime.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.lime.withValues(alpha: 0.25)),
            ),
            child: const Text('LOCKED',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.lime, fontFamily: 'monospace')),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _openGoogleMapsNav,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.blue.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.navigation_rounded,
                  color: AppColors.blue, size: 16),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Stat grid ─────────────────────────────────────────────────
  Widget _buildStatGrid() {
    final r = _result;
    return Column(children: [
      Row(children: [
        Expanded(child: _StatCard(
          label: 'High Severity', value: '${r?.highCount ?? 0}',
          color: AppColors.red, chipLabel: 'Urgent',
          icon: const Icon(Icons.warning_amber_rounded,
              color: AppColors.red, size: 18),
          iconBg: AppColors.red.withValues(alpha: 0.12),
          borderColor: AppColors.red.withValues(alpha: 0.2),
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          label: 'Health Score', value: '${r?.healthScore ?? 100}',
          color: _healthColor, chipLabel: r != null
            ? (r.healthScore >= 70 ? 'Good' : 'Poor') : 'Good',
          icon: Icon(Icons.favorite_border_rounded,
              color: _healthColor, size: 18),
          iconBg: _healthColor.withValues(alpha: 0.12),
          borderColor: _healthColor.withValues(alpha: 0.2),
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatCard(
            label: 'Defects', value: '${r?.detections.length ?? 0}',
            color: AppColors.amber)),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
            label: 'Potholes', value: '${r?.potholeCount ?? 0}',
            color: AppColors.teal)),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
            label: 'Medium', value: '${r?.mediumCount ?? 0}',
            color: AppColors.purple)),
      ]),
    ]);
  }

  // ── Input source selector ────────────────────────────────────
  Widget _buildInputSource() {
    return RSCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        _InputRow(
          iconColor: AppColors.blue,
          icon: Icons.upload_file_rounded,
          title: 'Upload Image / Video',
          subtitle: 'JPG · PNG · MP4 · WEBM',
          active: _inputMode == _InputMode.upload,
          isLast: false,
          onTap: () {
            setState(() => _inputMode = _InputMode.upload);
            _pick(ImageSource.gallery);
          },
        ),
        _InputRow(
          iconColor: AppColors.purple,
          icon: Icons.camera_alt_rounded,
          title: 'Camera Capture',
          subtitle: 'Live capture mode',
          active: _inputMode == _InputMode.camera,
          isLast: false,
          onTap: () {
            setState(() => _inputMode = _InputMode.camera);
            _pick(ImageSource.camera);
          },
        ),
        _InputRow(
          iconColor: AppColors.red,
          icon: Icons.videocam_outlined,
          title: 'RTSP / CCTV Live',
          subtitle: 'Stream input mode',
          active: _inputMode == _InputMode.rtsp,
          isLast: true,
          onTap: () => setState(() => _inputMode = _InputMode.rtsp),
        ),
      ]),
    );
  }

  // ── Drop zone  ───────────────────────────────────────────────
  Widget _buildDropZone() {
    // Show appropriate zone per mode
    if (_inputMode == _InputMode.upload) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: GestureDetector(
          onTap: () => _pick(ImageSource.gallery),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: context.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: context.border.withValues(alpha: 1.5), width: 1.5,
                  style: BorderStyle.solid),
            ),
            child: Column(children: [
              // Upload icon box
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.2)),
                ),
                child: const Icon(Icons.cloud_upload_outlined,
                    color: AppColors.blue, size: 28),
              ),
              const SizedBox(height: 12),
              Text('Drop road image here',
                  style: TextStyle(fontSize: 15,
                      fontWeight: FontWeight.w600, color: context.text)),
              const SizedBox(height: 4),
              Text('or tap to browse from Photos',
                  style: TextStyle(fontSize: 12, color: context.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, children: const [
                _FmtTag('JPG'), _FmtTag('PNG'),
                _FmtTag('MP4'), _FmtTag('WEBM'),
              ]),
            ]),
          ),
        ),
      );
    }
    if (_inputMode == _InputMode.camera) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: context.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.border, width: 1.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.blue, size: 22),
            ),
            const SizedBox(width: 10),
            Text('Camera capture active',
                style: TextStyle(fontSize: 13, color: context.muted)),
          ]),
        ),
      );
    }
    // RTSP
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: context.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.border, width: 1.5),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.videocam_outlined,
                color: AppColors.red, size: 22),
          ),
          const SizedBox(width: 10),
          Text('RTSP stream mode',
              style: TextStyle(fontSize: 13, color: context.muted)),
        ]),
      ),
    );
  }

  // ── Model config ─────────────────────────────────────────────
  Widget _buildModelConfig() {
    return RSCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Model chips -- built from GET /models, so this always reflects
        // what's actually trained and available on the server, and tapping
        // a chip really does switch the active model via POST /select_model.
        if (_modelsLoading)
          SizedBox(
            height: 38,
            child: Row(children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: context.muted),
              ),
              const SizedBox(width: 10),
              Text('Loading models…',
                  style: TextStyle(fontSize: 13, color: context.muted)),
            ]),
          )
        else if (_models.isEmpty)
          Row(children: [
            Icon(Icons.error_outline, size: 16, color: context.muted),
            const SizedBox(width: 8),
            Text('Could not reach /models -- check server connection',
                style: TextStyle(fontSize: 13, color: context.muted)),
          ])
        else
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _models.length,
              itemBuilder: (_, i) {
                final m = _models[i];
                final key = m['key'] as String;
                final available = m['available'] == true;
                final active = key == _activeModelKey;
                final variant = (m['variant']?.toString() ?? '?').toUpperCase();
                final epochs = m['epochs_trained'];
                final label = 'YOLOv8$variant · ${epochs}ep';

                return GestureDetector(
                  onTap: _switchingModel ? null : () => _onSelectModel(m),
                  child: Opacity(
                    opacity: available ? 1.0 : 0.4,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.blue.withValues(alpha: 0.14)
                            : context.surface2,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? AppColors.blue.withValues(alpha: 0.4)
                              : context.border,
                          width: 1.5,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (active && _switchingModel)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.blue),
                            ),
                          ),
                        Text(
                          available ? label : '$label (not trained)',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: active ? AppColors.blue : context.muted),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 18),
        _IosSlider(
          label: 'Confidence Threshold',
          value: _conf,
          onChanged: (v) => setState(() => _conf = v),
        ),
        const SizedBox(height: 12),
        _IosSlider(
          label: 'IOU Threshold',
          value: _iou,
          onChanged: (v) => setState(() => _iou = v),
        ),
      ]),
    );
  }

  // ── Result card ──────────────────────────────────────────────
  Widget _buildResultCard() {
    return RSCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(children: [
            Text('Result',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                    color: context.text)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: context.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.border),
              ),
              child: Text(
                  _result != null
                      ? '${_result!.detections.length} DETECTED'
                      : 'AWAITING',
                  style: TextStyle(fontSize: 10, color: context.muted,
                      fontFamily: 'monospace')),
            ),
            if (_result != null && _result!.detections.isNotEmpty) ...[
              const SizedBox(width: 8),
              _VizToggle(
                  mode: _vizMode,
                  onChanged: (m) => setState(() => _vizMode = m)),
            ],
          ]),
        ),

        // Image with bounding boxes
        LayoutBuilder(builder: (_, cst) {
          return Container(
            height: 280,
            width: cst.maxWidth,
            color: const Color(0xFF111111),
            child: _image == null
                ? Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined,
                      size: 44, color: context.muted),
                  const SizedBox(height: 10),
                  Text('Upload image to begin',
                      style: TextStyle(fontSize: 14, color: context.muted)),
                ]))
                : Stack(fit: StackFit.expand, children: [
              Image.file(_image!, fit: BoxFit.contain),
              if (_result != null)
                CustomPaint(
                  painter: DetectionPainter(
                    detections: _result!.detections,
                    imageWidth:  _result!.imageWidth,
                    imageHeight: _result!.imageHeight,
                    mode: _vizMode,
                  ),
                ),
              if (_loading)
                Container(
                  color: Colors.black54,
                  child: const Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.blue),
                      SizedBox(height: 14),
                      Text('Running YOLOv8…',
                          style: TextStyle(
                              color: Colors.white, fontSize: 14)),
                    ],
                  )),
                ),
            ]),
          );
        }),

        // Error
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.red.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppColors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!,
                    style: const TextStyle(
                        color: AppColors.red, fontSize: 13))),
              ]),
            ),
          ),

        // Perf chips
        if (_result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Wrap(spacing: 6, children: [
              _PerfChip('⚡ 38ms'),
              _PerfChip('📐 640×640'),
              _PerfChip('🤖 best.pt'),
              _PerfChip('${_result!.detections.length} detections'),
            ]),
          ),

        // Run button
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _detect,
              child: Text(
                  _result != null ? 'Scan Again' : 'Run Detection',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        // WhatsApp alert button after detection
        if (_result != null && _result!.detections.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: GestureDetector(
              onTap: _openWhatsApp,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: const Color(0x1A25D366),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0x4025D366), width: 1),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send, color: Color(0xFF25D366), size: 18),
                    SizedBox(width: 9),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('Send WhatsApp Alert',
                            style: TextStyle(fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF25D366))),
                        Text('with annotated image',
                            style: TextStyle(fontSize: 11,
                                color: Color(0x9925D366))),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 14),
      ]),
    );
  }

  // ── Defect list ──────────────────────────────────────────────
  Widget _buildDefectList() {
    return Column(
      children: _result!.detections.asMap().entries.map((e) {
        final i = e.key;
        final d = e.value;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + i * 80),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
                offset: Offset(-12 * (1 - v), 0), child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RSCard(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: d.severityBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: d.severityColor.withValues(alpha: 0.2)),
                  ),
                  child: Icon(
                      d.severity == 'High'
                          ? Icons.warning_amber_rounded
                          : d.severity == 'Medium'
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      color: d.severityColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.className,
                        style: TextStyle(fontSize: 15,
                            fontWeight: FontWeight.w600, color: context.text)),
                    const SizedBox(height: 2),
                    Text(
                      '${d.classCode} · ${d.area} px² · ${_street.split(',').first}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: context.muted,
                          fontFamily: 'monospace'),
                    ),
                  ],
                )),
                _SevBadge(d.severity),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: context.muted, letterSpacing: 0.8)),
  );
}

// ══════════════════════════════════════════════════════════════
//  SUB-WIDGETS
// ══════════════════════════════════════════════════════════════

// ── App logo (road / scan icon) ───────────────────────────────
class _RSLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3218), Color(0xFF2C4A22)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;
    final p = Paint()
      ..color = AppColors.lime
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Road perspective lines
    c.drawLine(Offset(cx - 6, s.height - 4), Offset(cx - 2, cy - 2), p);
    c.drawLine(Offset(cx + 6, s.height - 4), Offset(cx + 2, cy - 2), p);

    // Center dashes
    final dp = Paint()
      ..color = AppColors.lime
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    c.drawLine(Offset(cx, s.height - 5), Offset(cx, s.height - 9), dp);
    c.drawLine(Offset(cx, s.height - 12), Offset(cx, s.height - 15), dp);

    // Scan circle
    c.drawCircle(Offset(cx, cy - 2), 5, Paint()
      ..color = AppColors.lime.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    c.drawCircle(Offset(cx, cy - 2), 1.5,
        Paint()..color = AppColors.lime);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Animated live pip ─────────────────────────────────────────
class _LivePip extends StatefulWidget {
  const _LivePip();
  @override
  State<_LivePip> createState() => _LivePipState();
}
class _LivePipState extends State<_LivePip>
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
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          color: AppColors.lime.withValues(alpha: 0.4 + _c.value * 0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Format tag ────────────────────────────────────────────────
class _FmtTag extends StatelessWidget {
  final String label;
  const _FmtTag(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.border),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontFamily: 'monospace',
              fontWeight: FontWeight.w500, color: context.muted)),
    );
  }
}

// ── Input row ─────────────────────────────────────────────────
class _InputRow extends StatelessWidget {
  final Color iconColor;
  final IconData icon;
  final String title, subtitle;
  final bool active, isLast;
  final VoidCallback onTap;
  const _InputRow({
    required this.iconColor, required this.icon,
    required this.title, required this.subtitle,
    required this.active, required this.isLast,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: active ? iconColor.withValues(alpha: 0.05) : Colors.transparent,
          border: isLast ? null
              : Border(bottom: BorderSide(color: context.sep, width: 0.5)),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                      color: context.text)),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: context.muted,
                      fontFamily: 'monospace')),
            ],
          )),
          if (active)
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  color: iconColor, shape: BoxShape.circle),
            )
          else
            Icon(Icons.chevron_right_rounded,
                color: context.muted, size: 18),
        ]),
      ),
    );
  }
}

// ── iOS-style slider ──────────────────────────────────────────
class _IosSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _IosSlider(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                color: context.text)),
        Text(value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.blue, fontFamily: 'monospace')),
      ]),
      const SizedBox(height: 8),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          activeTrackColor: AppColors.blue,
          inactiveTrackColor: context.surface2,
          thumbColor: Colors.white,
          overlayColor: AppColors.blue.withValues(alpha: 0.12),
          thumbShape:
          const RoundSliderThumbShape(enabledThumbRadius: 11),
          overlayShape:
          const RoundSliderOverlayShape(overlayRadius: 18),
        ),
        child: Slider(
            value: value, min: 0.10, max: 0.90, onChanged: onChanged),
      ),
    ]);
  }
}

// ── Viz mode toggle ───────────────────────────────────────────
class _VizToggle extends StatelessWidget {
  final VisualizationMode mode;
  final ValueChanged<VisualizationMode> onChanged;
  const _VizToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final modes = [
      (VisualizationMode.bbox,    'Boxes'),
      (VisualizationMode.heatmap, 'Heat'),
      (VisualizationMode.both,    'Both'),
    ];
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: context.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: modes.map((m) {
        final active = mode == m.$1;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(m.$1);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 9),
            height: 28,
            decoration: BoxDecoration(
              color: active ? context.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              boxShadow: active
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 3)]
                  : [],
            ),
            child: Center(child: Text(m.$2,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                    color: active ? context.text : context.muted))),
          ),
        );
      }).toList()),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final String? chipLabel;
  final Widget? icon;
  final Color? iconBg, borderColor;
  const _StatCard({
    required this.label, required this.value, required this.color,
    this.chipLabel, this.icon, this.iconBg, this.borderColor,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? context.border,
            width: borderColor != null ? 1 : 0.5),
        boxShadow: context.isDark ? [] : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icon != null)
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Center(child: icon),
          ),
        if (icon != null) const SizedBox(height: 10),
        Text(value,
            style: TextStyle(fontSize: icon != null ? 28 : 22,
                fontWeight: FontWeight.w800, color: color,
                letterSpacing: -1.5, height: 1)),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: context.muted)),
        if (chipLabel != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(chipLabel!,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                    color: color, fontFamily: 'monospace')),
          ),
        ],
      ]),
    );
  }
}

// ── Perf chip ─────────────────────────────────────────────────
class _PerfChip extends StatelessWidget {
  final String label;
  const _PerfChip(this.label);
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.surface2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: context.border, width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: context.muted,
              fontFamily: 'monospace')),
    );
  }
}

// ── Severity badge ────────────────────────────────────────────
class _SevBadge extends StatelessWidget {
  final String severity;
  const _SevBadge(this.severity);
  @override
  Widget build(BuildContext context) {
    final col = severity == 'High' ? AppColors.red
        : severity == 'Medium' ? AppColors.amber : AppColors.lime;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.withValues(alpha: 0.25)),
      ),
      child: Text(severity,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: col, fontFamily: 'monospace')),
    );
  }
}

// ── Hero button ───────────────────────────────────────────────
class _HeroBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const _HeroBtn({required this.label, required this.icon,
    required this.onTap, required this.primary});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: primary
              ? AppColors.lime
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: primary ? null
              : Border.all(
              color: Colors.white.withValues(alpha: 0.2), width: 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              color: primary ? const Color(0xFF0A1F0A) : Colors.white,
              size: 16),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: primary ? const Color(0xFF0A1F0A) : Colors.white,
                  letterSpacing: -0.2)),
        ]),
      ),
    );
  }
}