import 'package:flutter/material.dart';
import 'upload_screen.dart'; // make sure this file exists

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RoadSense Dashboard"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            Card(
              child: ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("Upload Road Image"),
                subtitle: const Text("Detect potholes and cracks"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UploadScreen(),
                    ),
                  );
                },
              ),
            ),

          ],
        ),
      ),
    );
  }
}