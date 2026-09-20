import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';

Future<Position> getLocation() async {
  return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high);
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  File? _image;
  Uint8List? _webImage;

  List<dynamic> boxes = [];

  String resultText = "";
  double confidence = 0.0;

  double imageWidth = 1;
  double imageHeight = 1;

  double? lat;
  double? lon;

  final ImagePicker _picker = ImagePicker();

  // ================= IMAGE PICK =================
  Future<void> pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source);

    if (pickedFile != null) {
      if (kIsWeb) {
        _webImage = await pickedFile.readAsBytes();
      } else {
        _image = File(pickedFile.path);
      }

      setState(() {
        boxes = [];
        resultText = "";
      });
    }
  }

  // ================= API CALL =================
  Future<void> sendToAPI() async {
    if (!kIsWeb && _image == null) return;

    // GET GPS
    Position pos = await getLocation();
    lat = pos.latitude;
    lon = pos.longitude;

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('http://192.168.100.8:5000/detect'),
    );

    if (kIsWeb && _webImage != null) {
      request.files.add(
        http.MultipartFile.fromBytes('image', _webImage!,
            filename: 'image.jpg'),
      );
    } else {
      request.files.add(
        await http.MultipartFile.fromPath('image', _image!.path),
      );
    }

    var response = await request.send();

    if (response.statusCode == 200) {
      var res = await http.Response.fromStream(response);
      var data = jsonDecode(res.body);

      setState(() {
        boxes = data["detections"];
        imageWidth = data["image_width"];
        imageHeight = data["image_height"];

        if (boxes.isNotEmpty) {
          resultText = "Damage Detected";
          confidence = boxes[0]["confidence"];
        } else {
          resultText = "No Damage Detected";
          confidence = 0.0;
        }
      });
    } else {
      setState(() {
        resultText = "Error detecting image";
      });
    }
  }

  // ================= IMAGE =================
  Widget buildImage() {
    if (kIsWeb) {
      return _webImage != null
          ? Image.memory(_webImage!, fit: BoxFit.cover)
          : const Center(child: Text("No image selected"));
    } else {
      return _image != null
          ? Image.file(_image!, fit: BoxFit.cover)
          : const Center(child: Text("No image selected"));
    }
  }

  // ================= ROAD HEALTH =================
  int roadHealthScore() {
    int high = boxes.where((b) => b["severity"] == "High").length;
    int medium = boxes.where((b) => b["severity"] == "Medium").length;

    int score = 100 - (high * 10 + medium * 5);
    return score < 0 ? 0 : score;
  }

  // ================= BOXES =================
  Widget buildBoundingBoxes(double displayWidth, double displayHeight) {
    if (boxes.isEmpty) return const SizedBox();

    double scaleX = displayWidth / imageWidth;
    double scaleY = displayHeight / imageHeight;

    return Stack(
      children: boxes.map((box) {
        var coords = box["box"];

        double x1 = coords[0] * scaleX;
        double y1 = coords[1] * scaleY;
        double x2 = coords[2] * scaleX;
        double y2 = coords[3] * scaleY;

        String label = box["class_name"];
        String severity = box["severity"];

        return Positioned(
          left: x1,
          top: y1,
          child: Container(
            width: x2 - x1,
            height: y2 - y1,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red, width: 2),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                color: Colors.red,
                padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  "$label ($severity) ${(box["confidence"] * 100).toStringAsFixed(1)}%",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ================= RESULT CARD =================
  Widget buildResultCard() {
    if (resultText.isEmpty) return const SizedBox();

    int score = roadHealthScore();

    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: resultText.contains("No")
            ? Colors.green[100]
            : Colors.red[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            resultText,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text("Road Health Score: $score%"),
          const SizedBox(height: 8),
          if (lat != null && lon != null)
            Text("Location: $lat, $lon"),
        ],
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RoadSense AI"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // IMAGE + BOXES
              LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    height: 300,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[200],
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: constraints.maxWidth,
                            height: 300,
                            child: buildImage(),
                          ),
                        ),
                        buildBoundingBoxes(constraints.maxWidth, 300),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // BUTTONS
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera),
                      label: const Text("Camera"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo),
                      label: const Text("Gallery"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: sendToAPI,
                  child: const Text("Detect Damage"),
                ),
              ),

              buildResultCard(),
            ],
          ),
        ),
      ),
    );
  }
}