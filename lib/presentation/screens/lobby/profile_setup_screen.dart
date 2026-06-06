import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
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

class _ProfileSetupScreenState extends State<ProfileSetupScreen> with SingleTickerProviderStateMixin {
  XFile? _profileImage;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _roomCodeController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 4.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut)
    );
  }

  String _generateRandomRoomCode() {
    final rand = math.Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(4, (index) => chars[rand.nextInt(chars.length)]).join();
  }

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
    _pulseController.dispose();
    _nameController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070708),
      appBar: AppBar(
        title: const Text('SHADOW REGISTRY', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.w800, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background ambient gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Color(0x127A0000), // Very faint dark red ambient
                    Color(0xFF070708),
                  ],
                ),
              ),
            ),
          ),
          
          // CRT scanlines
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CRTScanlinePainter(),
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shield_outlined, color: Colors.redAccent, size: 14),
                              SizedBox(width: 8),
                              Text(
                                'RESTRICTED ACCESSIBILITY',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          // Profile Photo input
                          GestureDetector(
                            onTap: _takePhoto,
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.redAccent.withValues(alpha: 0.15),
                                        blurRadius: _pulseAnimation.value * 3,
                                        spreadRadius: _pulseAnimation.value / 2,
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Colors.redAccent.withValues(alpha: 0.4),
                                      width: 2.0,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 54,
                                    backgroundColor: const Color(0xFF131316),
                                    backgroundImage: _profileImage != null
                                        ? (kIsWeb 
                                            ? NetworkImage(_profileImage!.path) 
                                            : FileImage(File(_profileImage!.path))) as ImageProvider
                                        : null,
                                    child: _profileImage == null
                                        ? CustomPaint(
                                            size: const Size(40, 40),
                                            painter: CameraIconPainter(color: Colors.white38),
                                          )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'CAPTURE PROFILE BIOMETRICS',
                            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 32),
                          
                          TextField(
                            controller: _nameController,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, color: Colors.white, letterSpacing: 1.5),
                            decoration: const InputDecoration(
                              hintText: 'ENTER REAL NAME',
                              prefixIcon: Icon(Icons.person_outline, size: 18, color: Colors.white24),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _roomCodeController,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16, color: Colors.white, letterSpacing: 3),
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: 'ROOM CODE (BLANK TO CREATE)',
                              prefixIcon: Icon(Icons.lock_outline, size: 18, color: Colors.white24),
                            ),
                          ),
                          const SizedBox(height: 32),
                          
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_nameController.text.trim().isNotEmpty) {
                                  // 1. Save data locally
                                  await LocalStorage.instance.savePlayerData(
                                    _nameController.text.trim(),
                                    _profileImage?.path,
                                  );

                                  // 2. Resolve room code
                                  String finalRoomCode = _roomCodeController.text.trim().toUpperCase();
                                  if (finalRoomCode.isEmpty) {
                                    finalRoomCode = _generateRandomRoomCode();
                                  }
                                  await LocalStorage.instance.saveRoomCode(finalRoomCode);
                                  
                                  // 3. Navigate cleanly
                                  if (context.mounted) context.go('/lobby');
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Real name required.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              },
                              child: const Text('ENTER CHANNELS', style: TextStyle(fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CRTScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.015)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CameraIconPainter extends CustomPainter {
  final Color color;
  CameraIconPainter({this.color = Colors.white54});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // Stylized camera body path
    final bodyPath = Path()
      ..moveTo(0, h * 0.3)
      ..lineTo(w * 0.3, h * 0.3)
      ..lineTo(w * 0.38, h * 0.15)
      ..lineTo(w * 0.62, h * 0.15)
      ..lineTo(w * 0.7, h * 0.3)
      ..lineTo(w, h * 0.3)
      ..lineTo(w, h * 0.95)
      ..lineTo(0, h * 0.95)
      ..close();
    canvas.drawPath(bodyPath, paint);

    // Lens circle
    canvas.drawCircle(Offset(w / 2, h * 0.625), w * 0.2, paint);

    // Flash dot
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * 0.8, h * 0.45), 3, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}