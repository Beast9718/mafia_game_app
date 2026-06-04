import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;

class RoleRevealScreen extends StatefulWidget {
  final String assignedRole;
  final List<Map<String, dynamic>> players; // --- NEW ---

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
  
  bool _isRevealed = false;

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
        setState(() => _isRevealed = true);
        _controller.forward();
      }
    });

    // --- NEW: Mafia starts at night! Pass the players list ---
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        context.go('/game/night', extra: {'players': widget.players});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      body: Center(
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
              child: Container(
                width: 250,
                height: 350,
                decoration: BoxDecoration(
                  color: isFront ? Colors.grey.shade900 : roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isFront ? Colors.white24 : roleColor,
                    width: 2,
                  ),
                  boxShadow: isFront ? [] : [
                    BoxShadow(color: roleColor.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                  ]
                ),
                child: isFront
                    ? const Center(
                        child: Icon(Icons.help_outline, size: 80, color: Colors.white24),
                      )
                    : Transform(
                        transform: Matrix4.identity()..rotateY(math.pi),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.assignedRole == "MAFIA" ? Icons.bloodtype 
                              : widget.assignedRole == "COP" ? Icons.local_police
                              : widget.assignedRole == "DOCTOR" ? Icons.medical_services
                              : Icons.school,
                              size: 80, 
                              color: roleColor
                            ),
                            const SizedBox(height: 24),
                            const Text("YOUR ROLE IS", style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12)),
                            const SizedBox(height: 8),
                            Text(
                              widget.assignedRole, 
                              style: TextStyle(
                                color: roleColor, 
                                fontSize: 32, 
                                fontWeight: FontWeight.bold, 
                                letterSpacing: 6
                              )
                            ),
                          ],
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}