import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // Gives us kIsWeb

class ImageHelper {
  static Future<String?> imageToBase64(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;
    
    try {
      // 🚨 ANTI-CRASH SAFEGUARD 🚨
      // Web browsers cannot read local files. This prevents the infinite loading screen.
      if (kIsWeb) {
        debugPrint("Image conversion skipped: Running on Web. Please use a physical phone.");
        return null;
      }

      final file = File(imagePath);
      if (!file.existsSync()) return null;

      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('Error encoding image: $e');
      return null;
    }
  }

  static Uint8List? base64ToImage(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    try {
      return base64Decode(base64String);
    } catch (e) {
      debugPrint('Error decoding image: $e');
      return null;
    }
  }
}