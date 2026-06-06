import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

class ImageHelper {
  static Future<String?> imageToBase64(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;
    
    try {
      final xfile = XFile(imagePath);
      final bytes = await xfile.readAsBytes();
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