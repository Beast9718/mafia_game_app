import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../data/datasources/local_storage.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  XFile? _profileImage;
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Future<void> _takePhoto() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );
    if (photo != null) {
      setState(() {
        _profileImage = photo;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ID Registration', style: TextStyle(letterSpacing: 2)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _takePhoto,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey.shade900,
                backgroundImage: _profileImage != null
                    ? (kIsWeb 
                        ? NetworkImage(_profileImage!.path) 
                        : FileImage(File(_profileImage!.path))) as ImageProvider
                    : null,
                child: _profileImage == null
                    ? const Icon(Icons.camera_alt, size: 40, color: Colors.white54)
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'TAP TO CAPTURE ID PHOTO',
              style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.5),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _nameController,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ENTER YOUR NAME',
                hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 2),
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  if (_nameController.text.trim().isNotEmpty) {
                    // 1. Save data locally
                    await LocalStorage.instance.savePlayerData(
                      _nameController.text.trim(),
                      _profileImage?.path,
                    );
                    
                    // 2. Navigate cleanly
                    if (mounted) context.go('/lobby');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a name to survive.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('ENTER GAME', style: TextStyle(fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}