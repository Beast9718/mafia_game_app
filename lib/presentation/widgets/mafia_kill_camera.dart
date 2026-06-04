import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class MafiaKillCamera extends StatefulWidget {
  final Function(String videoPath) onKillRecorded;
  
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
      final XFile videoFile = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);
      widget.onKillRecorded(videoFile.path);
    } else {
      await _controller!.prepareForVideoRecording();
      await _controller!.startVideoRecording();
      setState(() => _isRecording = true);
    }
  }

  @override
  void dispose() {
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
        
        // Target Reticle
        Icon(Icons.center_focus_weak, size: 100, color: Colors.redAccent.withOpacity(0.5)),

        // Flip Camera Button (Top Right)
        if (!_isRecording && _cameras.length > 1)
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 30),
              onPressed: _flipCamera,
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ),

        // Recording Indicator
        if (_isRecording)
          Positioned(
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
              child: const Row(
                children: [
                  Icon(Icons.circle, color: Colors.white, size: 12),
                  SizedBox(width: 8),
                  Text("RECORDING...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
                color: _isRecording ? Colors.redAccent : Colors.transparent,
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.fiber_manual_record,
                color: _isRecording ? Colors.white : Colors.redAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}