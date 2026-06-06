import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import '../../widgets/mafia_kill_camera.dart';
import '../../../data/datasources/local_storage.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/utils/image_helper.dart';

class NightPhaseScreen extends StatefulWidget {
  final List<Map<String, dynamic>> players;

  const NightPhaseScreen({super.key, required this.players});

  @override
  State<NightPhaseScreen> createState() => _NightPhaseScreenState();
}

class _NightPhaseScreenState extends State<NightPhaseScreen> {
  String _assignedRole = "STUDENT"; 

  int _secondsLeft = 30;
  Timer? _countdownTimer;
  Timer? _navigationTimer;
  int? _selectedPlayerIndex;
  bool _actionConfirmed = false;
  
  bool _isNavigating = false;
  bool _isGameOver = false; 
  
  List<Map<String, dynamic>> _activePlayers = [];
  StreamSubscription? _socketSubscription;
  bool _copScanning = false;
  String? _scannedTarget;
  bool? _isScannedTargetMafia;
  String? _scannedTargetRole;
  Map<String, String> _deadRoles = {};



  String? _killPhrase;
  final List<String> _phraseTemplates = [
    "The night has come for {name}",
    "Goodbye forever {name}",
    "Classmate {name} must pay the price",
    "{name} has been eliminated by the order of Mafia",
    "Death awaits you {name}",
  ];

  void _selectKillPhrase(String name) {
    final rand = Random();
    final template = _phraseTemplates[rand.nextInt(_phraseTemplates.length)];
    _killPhrase = template.replaceAll("{name}", name);
  }

  String? _myName;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadPlayerData();
    _listenToServer();
  }

  Future<void> _loadPlayerData() async {
    final data = await LocalStorage.instance.getPlayerData();
    final savedRole = await LocalStorage.instance.getRole(); 
    final deadPlayers = await LocalStorage.instance.getDeadPlayers();
    
    if (mounted) {
      setState(() {
        _myName = data['name'];
        _assignedRole = savedRole ?? "STUDENT";
        
        _activePlayers = widget.players.map((p) {
          return {
            "name": p["name"],
            "avatarBase64": p["avatarBase64"],
            "isAlive": !deadPlayers.contains(p["name"]) 
          };
        }).toList();
      });
    }
  }

  void _listenToServer() {
    _socketSubscription = WebSocketService.instance.stream.listen((message) async {
      final decoded = jsonDecode(message);
      
      // 1. GAME OVER TRAP
      if (decoded['event'] == 'game_over') {
        _countdownTimer?.cancel(); // 🚨 Kill the clock!
        _navigationTimer?.cancel();
        _isGameOver = true; 
        if (mounted) {
          _navigationTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) context.go('/game-over', extra: {'winner': decoded['winner']});
          });
        }
      }
      
      // 2. REGULAR PHASE TRANSITION
      if (decoded['event'] == 'morning_briefing') {
        _countdownTimer?.cancel(); // 🚨 Kill the clock!
        _navigationTimer?.cancel();
        
        if (mounted && !_isNavigating) {
          _isNavigating = true;
          final victim = decoded['victim'];
          final doctorSaved = decoded['doctorSaved'] as bool? ?? false;
          
          if (victim != null) {
            await LocalStorage.instance.killPlayer(victim);
          }
          
          _navigationTimer = Timer(const Duration(seconds: 3), () {
            if (mounted && !_isGameOver) { 
               context.go('/game/day', extra: {
                 'victim': victim,
                 'doctorSaved': doctorSaved,
                 'players': widget.players,
                 'videoBase64': decoded['videoBase64'],
                 'ritualStatus': decoded['ritual_status'],
                 'ritualFeedback': decoded['ritual_feedback'],
                 'attemptedTarget': decoded['attempted_target'],
               });
            }
          });
        }
      }
      
      // 3. COP INVESTIGATION RESULT
      if (decoded['event'] == 'investigation_result') {
        final target = decoded['target'];
        final isMafia = decoded['is_mafia'] as bool? ?? false;
        final roleName = decoded['role'];
        if (mounted) {
          setState(() {
            _copScanning = true;
            _scannedTarget = target;
            _isScannedTargetMafia = isMafia;
            _scannedTargetRole = roleName;
          });
        }
      }

      // 4. RECONNECTION SYNC TRAP
      if (decoded['event'] == 'room_sync') {
        final List<dynamic> totalPlayers = decoded['players'] ?? [];
        final Map<String, dynamic> profiles = decoded['profiles'] ?? {};
        final String serverPhase = decoded['phase'] ?? 'NIGHT';
        final Map<String, dynamic> aliveMap = decoded['alive'] ?? {};
        final Map<String, dynamic> serverDeadRoles = decoded['dead_roles'] ?? {};
        
        // Reconcile dead list
        List<String> deadPlayers = [];
        aliveMap.forEach((name, isAlive) {
          if (isAlive == false) {
            deadPlayers.add(name);
          }
        });
        await LocalStorage.instance.setDeadPlayers(deadPlayers);
        
        if (mounted) {
          setState(() {
            _deadRoles = serverDeadRoles.map((k, v) => MapEntry(k, v.toString()));
            _activePlayers = totalPlayers.map((pName) {
              bool isDead = deadPlayers.contains(pName);
              return {
                "name": pName,
                "avatarBase64": profiles[pName],
                "isAlive": !isDead
              };
            }).toList();
          });
        }
        
        if (serverPhase == 'DAY') {
          _countdownTimer?.cancel();
          _navigationTimer?.cancel();
          if (mounted && !_isNavigating) {
            _isNavigating = true;
            context.go('/game/day', extra: {
              'victim': null,
              'doctorSaved': false,
              'players': widget.players,
              'videoBase64': null,
            });
          }
        } else if (serverPhase == 'LOBBY') {
          _countdownTimer?.cancel();
          _navigationTimer?.cancel();
          if (mounted && !_isNavigating) {
            _isNavigating = true;
            context.go('/lobby');
          }
        }
      }

      // 5. RESET TIMER ON MY OWN RECONNECTION
      if (decoded['event'] == 'player_joined') {
        final joinedPlayer = decoded['player_name'];
        if (joinedPlayer == _myName) {
          _countdownTimer?.cancel();
          _navigationTimer?.cancel();
          if (mounted) {
            setState(() {
              _secondsLeft = 30;
            });
            _startTimer();
          }
        }
      }

      // 6. SYNC ROLE DYNAMICALLY ON RECONNECT
      if (decoded['event'] == 'role_assigned') {
        final newRole = decoded['role'];
        await LocalStorage.instance.saveRole(newRole);
        if (mounted) {
          setState(() {
            _assignedRole = newRole;
          });
        }
      }
    });
  }

  void _startTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _countdownTimer?.cancel();
        _handleTimeOut();
      }
    });
  }

  void _handleTimeOut() {
    WebSocketService.instance.sendAction({"action": "sunrise"});
    _navigationTimer?.cancel();
    _navigationTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_isNavigating && !_isGameOver) {
        _isNavigating = true;
        context.go('/game/day', extra: {
          'victim': null,
          'players': widget.players,
          'videoBase64': null,
        });
      }
    });
  }

  Future<void> _confirmAction([XFile? videoFile]) async {
    if (_selectedPlayerIndex != null) {
      final targetName = _activePlayers[_selectedPlayerIndex!]["name"];
      
      String? videoBase64;
      if (videoFile != null) {
        try {
          final bytes = await videoFile.readAsBytes();
          videoBase64 = base64Encode(bytes);
        } catch (e) {
          debugPrint("Error reading video file: $e");
        }
      }

      final payload = {
        "action": "night_action",
        "role": _assignedRole,
        "target": targetName,
      };
      if (_assignedRole == "MAFIA" && _killPhrase != null) {
        payload["killPhrase"] = _killPhrase;
      }
      if (videoBase64 != null) {
        payload["videoBase64"] = videoBase64;
      }
      WebSocketService.instance.sendAction(payload);

      if (mounted) {
        setState(() => _actionConfirmed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action locked on $targetName...'),
            backgroundColor: _getRoleColor().shade900,
          ),
        );
      }
    }
  }

  MaterialColor _getRoleColor() {
    if (_assignedRole == "DOCTOR") return Colors.teal;
    if (_assignedRole == "COP") return Colors.blue;
    if (_assignedRole == "MAFIA") return Colors.red;
    return Colors.grey; 
  }

  String _getRoleInstruction() {
    if (_assignedRole == "DOCTOR") return "SELECT A PLAYER TO PROTECT FROM ELIMINATION";
    if (_assignedRole == "COP") return "SELECT A PLAYER TO INVESTIGATE THEIR ALIBI";
    return "TARGET ACQUISITION: SELECT TARGET AND RECORD ELIMINATION VIDEO"; 
  }

  String _getButtonText() {
    if (_assignedRole == "DOCTOR") return "DISPATCH MEDICAL AID";
    if (_assignedRole == "COP") return "INITIATE BACKGROUND CHECK";
    return "CONFIRM KILL";
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _navigationTimer?.cancel();
    _socketSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activePlayers.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.red)));

    final bool isMeDead = _myName != null && _activePlayers.any((p) => p["name"] == _myName && !p["isAlive"]);

    if (_assignedRole == "STUDENT" || isMeDead) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CreepyMoonIcon(size: 80),
              const SizedBox(height: 24),
              Text(
                isMeDead ? 'YOU ARE DEAD.' : 'GO TO SLEEP.',
                style: const TextStyle(color: Colors.white38, fontSize: 24, letterSpacing: 4),
              ),
              const SizedBox(height: 16),
              Text("00:${_secondsLeft.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white12, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final roleColor = _getRoleColor();

    return Scaffold(
      backgroundColor: const Color(0xFF070708),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_assignedRole, style: TextStyle(color: roleColor.shade400, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
                      Text("00:${_secondsLeft.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: Text(_getRoleInstruction(), style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 20),

                  Expanded(
                    flex: 1,
                    child: GridView.builder(
                      padding: const EdgeInsets.only(top: 12),
                      itemCount: _activePlayers.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.35,
                      ),
                      itemBuilder: (context, index) {
                        final player = _activePlayers[index];
                        final bool isAlive = player["isAlive"];
                        final bool isSelected = _selectedPlayerIndex == index;
                        
                        final imageBytes = ImageHelper.base64ToImage(player["avatarBase64"]);
                        final hasValidAvatar = imageBytes != null;
                        final channelStr = "CAM ${(index + 1).toString().padLeft(2, '0')}";

                        return GestureDetector(
                          onTap: (!isAlive || _actionConfirmed)
                              ? null
                              : () {
                                  setState(() {
                                    _selectedPlayerIndex = index;
                                    _selectKillPhrase(_activePlayers[index]["name"]);
                                  });
                                },
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C0C0E),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: !isAlive 
                                    ? Colors.red.withValues(alpha: 0.3) 
                                    : (isSelected ? roleColor.shade400 : Colors.white12),
                                width: 1.5,
                              ),
                              boxShadow: isSelected 
                                  ? [
                                      BoxShadow(
                                        color: roleColor.withValues(alpha: 0.25),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : [],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3.0),
                              child: Stack(
                                children: [
                                  // Static/Feed content
                                  Positioned.fill(
                                    child: !isAlive
                                        ? const SurveillanceStaticFeed()
                                        : Container(
                                            decoration: BoxDecoration(
                                              image: hasValidAvatar
                                                  ? DecorationImage(
                                                      image: MemoryImage(imageBytes),
                                                      fit: BoxFit.cover,
                                                      colorFilter: ColorFilter.mode(
                                                        roleColor.withValues(alpha: isSelected ? 0.25 : 0.05),
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
                                                      size: 44,
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

                                  // Vignette overlay
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: RadialGradient(
                                            center: Alignment.center,
                                            radius: 1.1,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withValues(alpha: !isAlive ? 0.75 : 0.45),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Top-left label (LIVE / SIGNAL LOST)
                                  Positioned(
                                    top: 6,
                                    left: 8,
                                    child: !isAlive
                                        ? const Text(
                                            "SIGNAL LOST",
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace',
                                              letterSpacing: 0.5,
                                            ),
                                          )
                                        : const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.videocam, color: Colors.greenAccent, size: 10),
                                              SizedBox(width: 4),
                                              Text(
                                                "FEED LIVE",
                                                style: TextStyle(
                                                  color: Colors.greenAccent,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
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
                                        color: !isAlive ? Colors.redAccent.withValues(alpha: 0.3) : Colors.white54,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
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
                                        player["name"] + (!isAlive ? " (DEAD - ${(_deadRoles[player["name"]] ?? 'STUDENT').toUpperCase()})" : ""),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: !isAlive ? Colors.red.shade400 : (isSelected ? roleColor.shade400 : Colors.white),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  if (_selectedPlayerIndex != null && !_actionConfirmed && _assignedRole == "MAFIA")
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          if (_killPhrase != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.warning, color: Colors.redAccent, size: 16),
                                      SizedBox(width: 8),
                                      Text(
                                        "RITUAL REQUIRED: WRITE & SPEAK",
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "\"$_killPhrase\"",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontStyle: FontStyle.italic,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: MafiaKillCamera(
                                onKillRecorded: (videoFile) {
                                  _confirmAction(videoFile);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_selectedPlayerIndex != null && !_actionConfirmed && _assignedRole != "MAFIA")
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: roleColor.shade800, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          onPressed: () => _confirmAction(),
                          child: Text(_getButtonText(), style: const TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),

                  if (_actionConfirmed)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 32.0),
                      child: Text("ACTION LOCKED. WAITING FOR SUNRISE...", style: TextStyle(color: Colors.white38, letterSpacing: 2)),
                    )
                ],
              ),
            ),
          ),
          if (_copScanning && _scannedTarget != null)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.9),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                child: Center(
                  child: SingleChildScrollView(
                    child: CopScannerCard(
                      targetName: _scannedTarget!,
                      isMafia: _isScannedTargetMafia,
                      roleName: _scannedTargetRole,
                      avatarBase64: _activePlayers.firstWhere(
                        (p) => p["name"] == _scannedTarget,
                        orElse: () => <String, dynamic>{},
                      )["avatarBase64"] as String?,
                      onClose: () {
                        setState(() {
                          _copScanning = false;
                          _scannedTarget = null;
                          _isScannedTargetMafia = null;
                          _scannedTargetRole = null;
                        });
                      },
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

class CreepyMoonIcon extends StatelessWidget {
  final double size;
  const CreepyMoonIcon({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MoonPainter(color: Colors.white24),
    );
  }
}

class _MoonPainter extends CustomPainter {
  final Color color;
  _MoonPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addOval(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutPath = Path()
      ..addOval(Rect.fromLTWH(size.width * 0.25, -size.height * 0.1, size.width, size.height));

    final moonPath = Path.combine(PathOperation.difference, path, cutPath);
    canvas.drawPath(moonPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CopScannerCard extends StatefulWidget {
  final String targetName;
  final bool? isMafia;
  final String? roleName;
  final String? avatarBase64;
  final VoidCallback onClose;

  const CopScannerCard({
    super.key,
    required this.targetName,
    required this.isMafia,
    required this.roleName,
    required this.avatarBase64,
    required this.onClose,
  });

  @override
  State<CopScannerCard> createState() => _CopScannerCardState();
}

class _CopScannerCardState extends State<CopScannerCard> with TickerProviderStateMixin {
  late AnimationController _laserController;
  late AnimationController _radarController;
  late AnimationController _stampController;
  late Animation<double> _stampScale;
  
  bool _isScanning = true;
  final List<String> _logLines = [];
  Timer? _logTimer;
  int _logStep = 0;

  final List<String> _possibleLogs = [
    "CONNECTING TO YOUSHIEN DB...",
    "EXTRACTING CLASS 2-3 REGISTERS...",
    "CORRELATING RETREAT SURVEY LOGS...",
    "RUNNING HEURISTIC THREAT SCANS...",
    "DECRYPTION COMPLETED."
  ];

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _stampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _stampScale = Tween<double>(begin: 3.0, end: 1.0).animate(
      CurvedAnimation(parent: _stampController, curve: Curves.bounceOut),
    );

    // Add logs step-by-step every 500ms
    _logTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_logStep < _possibleLogs.length) {
        if (mounted) {
          setState(() {
            _logLines.add(_possibleLogs[_logStep]);
            _logStep++;
          });
        }
      } else {
        _logTimer?.cancel();
        // After logs finish, trigger scan complete
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            setState(() {
              _isScanning = false;
            });
            _stampController.forward();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _laserController.dispose();
    _radarController.dispose();
    _stampController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = widget.avatarBase64 != null ? ImageHelper.base64ToImage(widget.avatarBase64) : null;
    final isTargetMafia = widget.isMafia ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0C10),
        border: Border.all(
          color: _isScanning 
              ? Colors.blueAccent.withValues(alpha: 0.3) 
              : (isTargetMafia ? Colors.redAccent.withValues(alpha: 0.4) : Colors.greenAccent.withValues(alpha: 0.4)),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: _isScanning 
                ? Colors.blue.withValues(alpha: 0.1) 
                : (isTargetMafia ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1)),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isMafia == null ? Icons.radar : Icons.verified_user_outlined,
                color: _isScanning 
                    ? Colors.blueAccent 
                    : (isTargetMafia ? Colors.redAccent : Colors.greenAccent),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                _isScanning ? "BIOMETRIC SURVEY SCAN" : "SCANNER ANALYSIS REPORT",
                style: TextStyle(
                  color: _isScanning 
                      ? Colors.blueAccent.shade200 
                      : (isTargetMafia ? Colors.redAccent.shade200 : Colors.greenAccent.shade200),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_isScanning) ...[
            // SCANNING STATE
            Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(110, 110),
                      painter: RadarScannerPainter(
                        rotationAngle: _radarController.value * 2 * pi,
                        color: Colors.blueAccent,
                      ),
                    );
                  },
                ),
                AnimatedBuilder(
                  animation: _laserController,
                  builder: (context, child) {
                    final yOffset = -50 + _laserController.value * 100;
                    return Transform.translate(
                      offset: Offset(0, yOffset),
                      child: Container(
                        width: 90,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.8),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const Icon(
                  Icons.fingerprint_rounded,
                  color: Colors.white12,
                  size: 50,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              "TARGET: ${widget.targetName.toUpperCase()}",
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            // Scrolling status logs
            Container(
              height: 70,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _logLines.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: Text(
                      "> ${_logLines[index]}",
                      style: TextStyle(
                        color: index == _logLines.length - 1 ? Colors.blueAccent.shade100 : Colors.white38,
                        fontSize: 9,
                        fontFamily: 'monospace',
                        letterSpacing: 1,
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            // RESULTS STATE
            Container(
              height: 110,
              width: 110,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isTargetMafia ? Colors.redAccent.withValues(alpha: 0.3) : Colors.greenAccent.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: imageBytes != null
                    ? Image.memory(
                        imageBytes,
                        fit: BoxFit.cover,
                        color: isTargetMafia ? Colors.red.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
                        colorBlendMode: BlendMode.colorBurn,
                      )
                    : Container(
                        color: Colors.white10,
                        child: const Icon(Icons.person, color: Colors.white24, size: 50),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.targetName.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 12),
            
            // Stamped report block
            ScaleTransition(
              scale: _stampScale,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isTargetMafia ? Colors.redAccent : Colors.greenAccent,
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  color: isTargetMafia ? Colors.red.withValues(alpha: 0.05) : Colors.green.withValues(alpha: 0.05),
                ),
                child: Text(
                  isTargetMafia ? "THREAT DETECTED" : "VERIFIED CLASSMATE",
                  style: TextStyle(
                    color: isTargetMafia ? Colors.redAccent : Colors.greenAccent,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    shadows: [
                      Shadow(
                        color: isTargetMafia ? Colors.red : Colors.green,
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isTargetMafia
                  ? "SYSTEM ALERT: Target alignment correlates with the perpetrator group (MAFIA)."
                  : "SYSTEM CHECK: Target registers safe alibi coordinates. Non-threat asset.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isTargetMafia ? Colors.red.shade200 : Colors.green.shade200,
                fontSize: 10,
                letterSpacing: 1,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 140,
              height: 38,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isTargetMafia ? const Color(0xFF220507) : const Color(0xFF05220C),
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: isTargetMafia ? Colors.redAccent.withValues(alpha: 0.5) : Colors.greenAccent.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: widget.onClose,
                child: const Text(
                  "ACKNOWLEDGE",
                  style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RadarScannerPainter extends CustomPainter {
  final double rotationAngle;
  final Color color;

  RadarScannerPainter({required this.rotationAngle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paintCircle = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw concentric circles
    canvas.drawCircle(center, radius, paintCircle);
    canvas.drawCircle(center, radius * 0.66, paintCircle);
    canvas.drawCircle(center, radius * 0.33, paintCircle);

    // Draw grid axes
    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), paintCircle);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), paintCircle);

    // Draw rotating sweep sector
    final paintSweep = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.4),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.25],
        transform: GradientRotation(rotationAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, paintSweep);
  }

  @override
  bool shouldRepaint(covariant RadarScannerPainter oldDelegate) {
    return oldDelegate.rotationAngle != rotationAngle || oldDelegate.color != color;
  }
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
  final Random _random = Random();
  
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