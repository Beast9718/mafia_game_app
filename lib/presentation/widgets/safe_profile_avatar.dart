import 'dart:io';
import 'package:flutter/material.dart';

class SafeProfileAvatar extends StatelessWidget {
  final String? imagePath;
  final double radius;
  final bool isAlive;
  final bool isSelected;
  final Color highlightColor;

  const SafeProfileAvatar({
    super.key,
    required this.imagePath,
    this.radius = 38,
    this.isAlive = true,
    this.isSelected = false,
    this.highlightColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    // Safely check if the path exists and points to a real file on the Android device
    final bool hasValidFile = imagePath != null && File(imagePath!).existsSync();

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? highlightColor : Colors.transparent,
          width: 3,
        ),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: isAlive ? Colors.grey.shade900 : Colors.black,
        // Only attempt to load the file if we confirmed it exists
        backgroundImage: hasValidFile ? FileImage(File(imagePath!)) : null,
        // Fallback icon if there is no image or the file was lost from cache
        child: !hasValidFile
            ? Icon(
                Icons.person,
                color: isAlive
                    ? (isSelected ? highlightColor.withOpacity(0.5) : Colors.white54)
                    : Colors.white10,
                size: radius,
              )
            : null,
      ),
    );
  }
}