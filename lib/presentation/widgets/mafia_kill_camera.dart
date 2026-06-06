import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class MafiaKillCamera extends StatefulWidget {
  final Function(XFile videoFile) onKillRecorded;
  
  const MafiaKillCamera({super.key, required this.onKillRecorded});

  @override
  State<MafiaKillCamera> createState() => _MafiaKillCameraState();
}

class _MafiaKillCameraState extends State<MafiaKillCamera> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isInitializing = true;
  bool _isRecording = false;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _setupCameras();
  }

  Future<void> _setupCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      // Default to front camera first, if available
      _selectedCameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      if (_selectedCameraIndex == -1) _selectedCameraIndex = 0; // Fallback to first camera

      await _initCamera(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint("Camera setup error: $e");
    }
  }

  Future<void> _initCamera(CameraDescription cameraDescription) async {
    setState(() => _isInitializing = true);
    
    // Dispose old controller if we are flipping the camera
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  void _flipCamera() {
    if (_cameras.length < 2 || _isRecording) return; // Can't flip while recording
    
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    _initCamera(_cameras[_selectedCameraIndex]);
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isRecording) {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      final XFile videoFile = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);
      widget.onKillRecorded(videoFile);
    } else {
      await _controller!.prepareForVideoRecording();
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);

      // Automatically stop recording after 5 seconds to keep size small
      _recordingTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _isRecording) {
          _toggleRecording();
        }
      });
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Camera Preview Feed
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 1 / _controller!.value.aspectRatio,
            child: CameraPreview(_controller!),
          ),
        ),
        
        // Target Reticle (Custom drawn to prevent missing icons on web)
        CustomPaint(
          size: const Size(120, 120),
          painter: ReticlePainter(color: Colors.redAccent.withValues(alpha: 0.5)),
        ),

        // Flip Camera Button (Top Right)
        if (!_isRecording && _cameras.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: _flipCamera,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  "FLIP",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),

        // Recording Indicator
        if (_isRecording)
          Positioned(
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text("RECORDING...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          ),

        // Record Button
        Positioned(
          bottom: 16,
          child: GestureDetector(
            onTap: _toggleRecording,
            child: Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.redAccent, width: 3),
                color: _isRecording ? Colors.redAccent.withValues(alpha: 0.2) : Colors.transparent,
              ),
              child: Center(
                child: _isRecording
                    ? Container(
                        height: 20,
                        width: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Container(
                        height: 24,
                        width: 24,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.redAccent,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ReticlePainter extends CustomPainter {
  final Color color;
  ReticlePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final len = 20.0; // corner line length

    // Top-Left corner
    canvas.drawLine(const Offset(0, 0), Offset(len, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, len), paint);

    // Top-Right corner
    canvas.drawLine(Offset(w, 0), Offset(w - len, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);

    // Bottom-Left corner
    canvas.drawLine(Offset(0, h), Offset(len, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - len), paint);

    // Bottom-Right corner
    canvas.drawLine(Offset(w, h), Offset(w - len, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - len), paint);

    // Center circle
    canvas.drawCircle(Offset(w / 2, h / 2), 8, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}