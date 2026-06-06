import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;

class RoleRevealScreen extends StatefulWidget {
  final String assignedRole;
  final List<Map<String, dynamic>> players; 

  const RoleRevealScreen({
    super.key, 
    required this.assignedRole, 
    required this.players
  });

  @override
  State<RoleRevealScreen> createState() => _RoleRevealScreenState();
}

class _RoleRevealScreenState extends State<RoleRevealScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  Timer? _navigationTimer;

  Color get roleColor {
    if (widget.assignedRole == "MAFIA") return Colors.redAccent;
    if (widget.assignedRole == "COP") return Colors.blue;
    if (widget.assignedRole == "DOCTOR") return Colors.teal;
    return Colors.grey; 
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack)
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _controller.forward();
      }
    });

    _navigationTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) {
        context.go('/game/night', extra: {'players': widget.players});
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _getRoleLore() {
    if (widget.assignedRole == "MAFIA") {
      return "DIRECTIVE: Infiltrate town channels. Coordinate with assets to execute players each night. Deflect suspicion to survive.";
    }
    if (widget.assignedRole == "COP") {
      return "DIRECTIVE: Query biometric databases. Scan one target classmate each night to reveal alignment. Guide town selections.";
    }
    if (widget.assignedRole == "DOCTOR") {
      return "DIRECTIVE: Deploy clinical aid. Safeguard one target classmate each night. Shield target from mafia execution strikes.";
    }
    return "DIRECTIVE: Survive the nightmare. Analyze voting vectors. Root out hidden mafia elements and execute them at dusk.";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF040405),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    roleColor.withValues(alpha: 0.08),
                    const Color(0xFF040405),
                  ],
                ),
              ),
            ),
          ),
          
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CRTScanlinePainter(),
              ),
            ),
          ),

          Center(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                final transform = Matrix4.identity()
                  ..setEntry(3, 2, 0.001) 
                  ..rotateY(_animation.value * math.pi); 

                final isFront = _animation.value < 0.5;

                return Transform(
                  transform: transform,
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 270,
                        height: 380,
                        decoration: BoxDecoration(
                          color: isFront ? Colors.white.withValues(alpha: 0.02) : roleColor.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isFront ? Colors.white12 : roleColor.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          boxShadow: isFront ? [] : [
                            BoxShadow(color: roleColor.withValues(alpha: 0.1), blurRadius: 25, spreadRadius: 2)
                          ]
                        ),
                        child: CustomPaint(
                          painter: TerminalFramePainter(color: isFront ? Colors.white24 : roleColor),
                          child: isFront
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.lock, size: 64, color: Colors.white24),
                                      SizedBox(height: 16),
                                      Text(
                                        "DECRYPTING RECORD...",
                                        style: TextStyle(
                                          color: Colors.white30,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Transform(
                                  transform: Matrix4.identity()..rotateY(math.pi),
                                  alignment: Alignment.center,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          widget.assignedRole == "MAFIA" ? Icons.bloodtype 
                                          : widget.assignedRole == "COP" ? Icons.local_police
                                          : widget.assignedRole == "DOCTOR" ? Icons.medical_services
                                          : Icons.school,
                                          size: 64, 
                                          color: roleColor
                                        ),
                                        const SizedBox(height: 16),
                                        const Text("IDENTITY DECRYPTED", style: TextStyle(color: Colors.white38, letterSpacing: 2, fontSize: 8, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(
                                          widget.assignedRole, 
                                          style: TextStyle(
                                            color: roleColor, 
                                            fontSize: 24, 
                                            fontWeight: FontWeight.w900, 
                                            letterSpacing: 6,
                                            shadows: [
                                              Shadow(color: roleColor.withValues(alpha: 0.5), blurRadius: 10),
                                            ],
                                          )
                                        ),
                                        const SizedBox(height: 16),
                                        const Divider(color: Colors.white10, height: 1),
                                        const SizedBox(height: 16),
                                        Expanded(
                                          child: TypewriterText(
                                            text: _getRoleLore(),
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              height: 1.5,
                                              fontFamily: 'monospace',
                                            ),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TerminalFramePainter extends CustomPainter {
  final Color color;

  TerminalFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const len = 16.0;

    canvas.drawPath(Path()
      ..moveTo(0, len)
      ..lineTo(0, 0)
      ..lineTo(len, 0), paint);

    canvas.drawPath(Path()
      ..moveTo(size.width - len, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, len), paint);

    canvas.drawPath(Path()
      ..moveTo(0, size.height - len)
      ..lineTo(0, size.height)
      ..lineTo(len, size.height), paint);

    canvas.drawPath(Path()
      ..moveTo(size.width - len, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, size.height - len), paint);
  }

  @override
  bool shouldRepaint(covariant TerminalFramePainter oldDelegate) => oldDelegate.color != color;
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
  bool shouldRepaint(covariant CRTScanlinePainter oldDelegate) => false;
}

class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration duration;

  const TypewriterText({
    super.key,
    required this.text,
    required this.style,
    this.duration = const Duration(milliseconds: 30),
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = "";
  Timer? _timer;
  int _charIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(widget.duration, (timer) {
      if (_charIndex < widget.text.length) {
        if (mounted) {
          setState(() {
            _displayedText += widget.text[_charIndex];
            _charIndex++;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Text(_displayedText, style: widget.style),
    );
  }
}