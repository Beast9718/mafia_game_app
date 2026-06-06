import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../data/datasources/local_storage.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/utils/image_helper.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  String roomCode = "D3AD-N1T3";

  // 2. Make sure this points to your Render domain (no wss:// or http:// here):
  final String serverIpAddress = "mafia-game-master.onrender.com"; 

  List<Map<String, dynamic>> livePlayers = [];
  String? myName;
  String? myBase64Avatar;
  String? secretAssignedRole; 
  String _currentServerPhase = "LOBBY";
  StreamSubscription? _socketSubscription;

  void _navigateToActiveGame(String phase, String role) {
    if (!mounted) return;
    if (phase == 'DAY') {
      context.go('/game/day', extra: {
        'players': livePlayers,
        'victim': null,
        'doctorSaved': false,
        'videoBase64': null,
      });
    } else if (phase == 'NIGHT') {
      context.go('/game/night', extra: {
        'players': livePlayers,
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeLobby();
  }

  Future<void> _initializeLobby() async {
    // 🚨 Clean up any previous active socket connection first!
    WebSocketService.instance.disconnect();

    await LocalStorage.instance.clearGraveyard();

    final data = await LocalStorage.instance.getPlayerData();
    myName = data['name'] ?? "Unknown";
    final imagePath = data['imagePath'];

    final savedCode = await LocalStorage.instance.getRoomCode();
    if (savedCode != null && savedCode.isNotEmpty) {
      if (mounted) {
        setState(() {
          roomCode = savedCode;
        });
      }
    }

    myBase64Avatar = await ImageHelper.imageToBase64(imagePath);

    if (mounted) {
      setState(() {
        livePlayers.add({
          "name": myName,
          "isHost": false, 
          "avatarBase64": myBase64Avatar,
        });
      });
    }

    WebSocketService.instance.connect(roomCode, myName!, serverIpAddress);

    Future.delayed(const Duration(seconds: 1), () {
      WebSocketService.instance.sendAction({
        "action": "update_profile",
        "avatar": myBase64Avatar
      });
    });

    _socketSubscription = WebSocketService.instance.stream.listen((message) async {
      if (!mounted) return;
      final decodedMessage = jsonDecode(message);
      
      if (decodedMessage['event'] == 'room_sync') {
        final List<dynamic> totalPlayers = decodedMessage['players'] ?? [];
        final Map<String, dynamic> profiles = decodedMessage['profiles'] ?? {};
        final String? hostName = decodedMessage['host'];
        final String serverPhase = decodedMessage['phase'] ?? 'LOBBY';
        final Map<String, dynamic> aliveMap = decodedMessage['alive'] ?? {};
        
        _currentServerPhase = serverPhase;
        
        setState(() {
          livePlayers.clear();
          for (var pName in totalPlayers) {
            livePlayers.add({
              "name": pName,
              "isHost": pName == hostName, 
              "avatarBase64": profiles[pName],
            });
          }
        });

        // Update local graveyard
        List<String> deadPlayers = [];
        aliveMap.forEach((name, isAlive) {
          if (isAlive == false) {
            deadPlayers.add(name);
          }
        });
        await LocalStorage.instance.setDeadPlayers(deadPlayers);

        if (serverPhase == 'DAY' || serverPhase == 'NIGHT') {
          final savedRole = await LocalStorage.instance.getRole();
          if (savedRole != null && savedRole.isNotEmpty) {
            _navigateToActiveGame(serverPhase, savedRole);
          }
        }
      }

      if (decodedMessage['event'] == 'player_joined') {
        final newPlayer = decodedMessage['player_name'];
        if (newPlayer != myName) {
          setState(() {
            if (!livePlayers.any((p) => p['name'] == newPlayer)) {
              livePlayers.add({
                "name": newPlayer,
                "isHost": false,
                "avatarBase64": null, 
              });
            }
          });
        }
      }
      
      if (decodedMessage['event'] == 'player_left') {
        setState(() {
          livePlayers.removeWhere((p) => p['name'] == decodedMessage['player_name']);
        });
      }

      if (decodedMessage['event'] == 'profile_updated') {
        setState(() {
          for (var player in livePlayers) {
            if (player['name'] == decodedMessage['player_name']) {
              player['avatarBase64'] = decodedMessage['avatar'];
            }
          }
        });
      }

      // 🚨 THE CRITICAL FIX IS HERE 🚨
      if (decodedMessage['event'] == 'role_assigned') {
        secretAssignedRole = decodedMessage['role'];
        // We must save the role to the hard drive so the Night Phase can read it!
        await LocalStorage.instance.saveRole(secretAssignedRole!);
        
        if (_currentServerPhase == 'DAY' || _currentServerPhase == 'NIGHT') {
          _navigateToActiveGame(_currentServerPhase, secretAssignedRole!);
        }
      }

      if (decodedMessage['event'] == 'game_started') {
        if (mounted && secretAssignedRole != null) {
          context.go('/role-reveal', extra: {
            'assignedRole': secretAssignedRole,
            'players': livePlayers
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  bool get _amIHost {
    final me = livePlayers.firstWhere((p) => p['name'] == myName, orElse: () => <String, dynamic>{});
    return me['isHost'] == true;
  }

  void _startRoleReveal() {
    WebSocketService.instance.sendAction({"action": "start_game"});
  }

  @override
  Widget build(BuildContext context) {
    if (livePlayers.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF070708),
        body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }

    final displayPlayers = List<Map<String, dynamic>>.from(livePlayers);
    while (displayPlayers.length < 10) {
      displayPlayers.add({"name": "Waiting...", "isHost": false, "avatarBase64": null});
    }

    return Scaffold(
      backgroundColor: const Color(0xFF070708),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text('SURVEILLANCE HUB', style: TextStyle(fontSize: 10, color: Colors.white38, letterSpacing: 3, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text("ROOM: $roomCode", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 4, color: Colors.white)),
          ],
        ),
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
                    Color(0x0E7A0000), // Very faint dark red ambient
                    Color(0xFF070708),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ACTIVE FEEDS: ${livePlayers.length} / 10 CONNECTED',
                        style: const TextStyle(color: Colors.redAccent, letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    itemCount: displayPlayers.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.25,
                    ),
                    itemBuilder: (context, index) {
                      return CCTVMonitor(player: displayPlayers[index], index: index);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (_amIHost)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _startRoleReveal,
                      child: const Text('BEGIN PROTOCOLS', style: TextStyle(fontSize: 14, letterSpacing: 3, fontWeight: FontWeight.bold)),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF121215),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Text(
                      'AWAITING COMMAND PATH FROM HOST',
                      style: TextStyle(color: Colors.white30, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CCTVMonitor extends StatefulWidget {
  final Map<String, dynamic> player;
  final int index;

  const CCTVMonitor({super.key, required this.player, required this.index});

  @override
  State<CCTVMonitor> createState() => _CCTVMonitorState();
}

class _CCTVMonitorState extends State<CCTVMonitor> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _blinkAnimation = CurvedAnimation(parent: _blinkController, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWaiting = widget.player["name"] == "Waiting...";
    final base64String = widget.player["avatarBase64"];
    final imageBytes = ImageHelper.base64ToImage(base64String);
    final hasValidAvatar = imageBytes != null;
    final isHost = widget.player["isHost"] == true;

    final channelStr = "CAM ${(widget.index + 1).toString().padLeft(2, '0')}";

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isWaiting ? Colors.white12 : Colors.redAccent.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: isWaiting
            ? []
            : [
                BoxShadow(
                  color: Colors.redAccent.withValues(alpha: 0.05),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3.0),
        child: Stack(
          children: [
            // Static/Feed content
            Positioned.fill(
              child: isWaiting
                  ? const SurveillanceStaticFeed()
                  : Container(
                      decoration: BoxDecoration(
                        image: hasValidAvatar
                            ? DecorationImage(
                                image: MemoryImage(imageBytes),
                                fit: BoxFit.cover,
                                colorFilter: ColorFilter.mode(
                                  Colors.redAccent.withValues(alpha: 0.15),
                                  BlendMode.colorBurn,
                                ),
                              )
                            : null,
                      ),
                      child: !hasValidAvatar
                          ? Center(
                              child: Icon(
                                Icons.person,
                                color: Colors.white.withValues(alpha: 0.15),
                                size: 48,
                              ),
                            )
                          : null,
                    ),
            ),

            // CRT Scanlines overlay
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CRTScanlinePainter(),
                ),
              ),
            ),

            // Dark vignette
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.1,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: isWaiting ? 0.75 : 0.45),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Top-left status
            Positioned(
              top: 6,
              left: 8,
              child: isWaiting
                  ? Text(
                      "NO FEED",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.2),
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FadeTransition(
                          opacity: _blinkAnimation,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          "LIVE",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
            ),

            // Top-right channel number
            Positioned(
              top: 6,
              right: 8,
              child: Text(
                channelStr,
                style: TextStyle(
                  color: isWaiting ? Colors.white.withValues(alpha: 0.15) : Colors.white60,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  fontFamily: 'monospace',
                ),
              ),
            ),

            // Bottom Player Name Label
            Positioned(
              bottom: 6,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: Colors.black54,
                child: Text(
                  isWaiting ? "CONNECTING..." : widget.player["name"] + (isHost ? " *" : ""),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isWaiting ? Colors.white24 : Colors.redAccent.shade100,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SurveillanceStaticFeed extends StatefulWidget {
  const SurveillanceStaticFeed({super.key});

  @override
  State<SurveillanceStaticFeed> createState() => _SurveillanceStaticFeedState();
}

class _SurveillanceStaticFeedState extends State<SurveillanceStaticFeed> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: StaticNoisePainter(),
        );
      },
    );
  }
}

class StaticNoisePainter extends CustomPainter {
  final math.Random _random = math.Random();
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..strokeWidth = 1;
      
    // Draw random white/grey horizontal lines or dots
    for (int i = 0; i < 12; i++) {
      double y = _random.nextDouble() * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    
    // Also draw some random speckles
    final specklePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..style = PaintingStyle.fill;
    for (int i = 0; i < 8; i++) {
      double x = _random.nextDouble() * size.width;
      double y = _random.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), _random.nextDouble() * 1.5, specklePaint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CRTScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.012)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}