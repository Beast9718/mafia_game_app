import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../data/datasources/local_storage.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/utils/image_helper.dart'; 
import '../../../core/utils/video_helper.dart';
import '../../widgets/terminal_chat_panel.dart';

class DayPhaseScreen extends StatefulWidget {
  final String? victimName;
  final bool doctorSaved;
  final List<Map<String, dynamic>> players; 
  final String? murderVideoBase64;
  final String? ritualStatus;
  final String? ritualFeedback;
  final String? attemptedTarget;

  const DayPhaseScreen({
    super.key, 
    this.victimName, 
    this.doctorSaved = false,
    required this.players,
    this.murderVideoBase64,
    this.ritualStatus,
    this.ritualFeedback,
    this.attemptedTarget,
  });

  @override
  State<DayPhaseScreen> createState() => _DayPhaseScreenState();
}

class _DayPhaseScreenState extends State<DayPhaseScreen> {
  int _secondsLeft = 60; 
  Timer? _countdownTimer;
  Timer? _navigationTimer;
  bool _showSystemAnnouncement = true;
  late String _announcementText;
  
  int? _selectedPlayerIndex;
  bool _voteConfirmed = false;
  String? _myName;
  
  bool _isNavigating = false;
  bool _isGameOver = false; 
  
  List<Map<String, dynamic>> _activePlayers = []; 
  StreamSubscription? _socketSubscription;
  String? _videoSource;
  bool _showLynchedAnimation = false;
  String? _executedPlayerName;
  Map<String, String> _deadRoles = {};
  List<String> _failedToVotePlayers = [];
  final List<Map<String, dynamic>> _chatMessages = [];

  void _sendChatMessage(String text) {
    WebSocketService.instance.sendAction({
      "action": "send_chat",
      "channel": "public",
      "message": text,
    });
  }



  @override
  void initState() {
    super.initState();
    
    if (widget.ritualStatus == "failed") {
      _announcementText = "⚠️ BOTCHED MAFIA RITUAL\n\nLast night, a dark shadow hovered over ${widget.attemptedTarget}.\n\nThe Mafia attempted an execution, but failed the sacred ritual.\n\nREASON: ${widget.ritualFeedback ?? 'Ritual requirements not met.'}\n\nNO ONE DIED.";
    } else if (widget.doctorSaved) {
      _announcementText = "🔊 DOCTOR INTERVENTION\n\nA critical save occurred last night.\n\nMedical aid was deployed in time to protect a life.";
    } else if (widget.victimName == null) {
      _announcementText = "🔊 MORNING BRIEFING\n\nA miracle occurred.\n\nNOBODY DIED LAST NIGHT.";
    } else {
      _announcementText = "🔊 MORNING BRIEFING\n\n${widget.victimName} was brutally targeted last night.\n\nTHEY ARE NO LONGER IN THE GAME.";
    }

    _startTimer();
    _loadPlayerData();
    _listenToServer();
    _initializeMurderVideo();

    if (widget.murderVideoBase64 == null) {
      final delaySeconds = (widget.doctorSaved || widget.ritualStatus == "failed") ? 6 : 4;
      Future.delayed(Duration(seconds: delaySeconds), () {
        if (mounted) setState(() => _showSystemAnnouncement = false);
      });
    }
  }

  Future<void> _initializeMurderVideo() async {
    if (widget.murderVideoBase64 == null || widget.murderVideoBase64!.isEmpty) return;
    try {
      if (kIsWeb) {
        final blobUrl = createVideoUrl(widget.murderVideoBase64!);
        if (mounted) {
          setState(() {
            _videoSource = blobUrl;
          });
        }
        debugPrint("Murder video loaded as Blob URL: $blobUrl");
      } else {
        final bytes = base64Decode(widget.murderVideoBase64!);
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/murder_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        if (mounted) {
          setState(() {
            _videoSource = filePath;
          });
        }
        debugPrint("Murder video saved to temporary file: $filePath");
      }
    } catch (e) {
      debugPrint("Error saving/loading murder video: $e");
    }
  }

  Future<void> _loadPlayerData() async {
    final data = await LocalStorage.instance.getPlayerData();
    final deadPlayers = await LocalStorage.instance.getDeadPlayers();
    
    if (mounted) {
      setState(() {
        _myName = data['name'] ?? "Unknown";
        
        _activePlayers = widget.players.map((p) {
          bool isDead = deadPlayers.contains(p["name"]) || p["name"] == widget.victimName;
          return {
            "name": p["name"],
            "avatarBase64": p["avatarBase64"],
            "isAlive": !isDead
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
      if (decoded['event'] == 'dusk_briefing') {
        _countdownTimer?.cancel(); // 🚨 Kill the clock!
        _navigationTimer?.cancel();
        
        if (mounted && !_isNavigating) {
           _isNavigating = true;
           final executedPlayer = decoded['executed'];
           final List<dynamic> serverFailed = decoded['failed_to_vote'] ?? [];
           final List<String> failedToVote = List<String>.from(serverFailed);
           
           if (executedPlayer != null) {
             await LocalStorage.instance.killPlayer(executedPlayer);
           }
           for (final p in failedToVote) {
             await LocalStorage.instance.killPlayer(p);
           }
           
           if (mounted) {
             setState(() {
               _executedPlayerName = executedPlayer;
               _failedToVotePlayers = failedToVote;
               _showLynchedAnimation = true;
             });
           }

          _navigationTimer = Timer(const Duration(milliseconds: 5500), () {
            if (mounted && !_isGameOver) {
               context.go('/game/night', extra: {'players': widget.players});
            }
          });
        }
      }

      // 3. RECONNECTION SYNC TRAP
      if (decoded['event'] == 'room_sync') {
        final List<dynamic> totalPlayers = decoded['players'] ?? [];
        final Map<String, dynamic> profiles = decoded['profiles'] ?? {};
        final String serverPhase = decoded['phase'] ?? 'DAY';
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
        
        if (serverPhase == 'NIGHT') {
          _countdownTimer?.cancel();
          _navigationTimer?.cancel();
          if (mounted && !_isNavigating) {
            _isNavigating = true;
            context.go('/game/night', extra: {'players': widget.players});
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

      // 4. RESET TIMER ON MY OWN RECONNECTION
      if (decoded['event'] == 'player_joined') {
        final joinedPlayer = decoded['player_name'];
        if (joinedPlayer == _myName) {
          _countdownTimer?.cancel();
          _navigationTimer?.cancel();
          if (mounted) {
            setState(() {
              _secondsLeft = 60;
            });
            _startTimer();
          }
        }
      }

      // 5. CHAT MESSAGE RECEIVER
      if (decoded['event'] == 'chat_message' && decoded['channel'] == 'public') {
        if (mounted) {
          setState(() {
            _chatMessages.add({
              "sender": decoded['sender'],
              "message": decoded['message'],
            });
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
    WebSocketService.instance.sendAction({"action": "dusk"});
    
    _navigationTimer?.cancel();
    _navigationTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isNavigating && !_isGameOver) {
        _isNavigating = true;
        context.go('/game/night', extra: {'players': widget.players});
      }
    });
  }

  void _confirmVote() {
    if (_selectedPlayerIndex != null && _myName != null) {
      final targetName = _activePlayers[_selectedPlayerIndex!]["name"];
      
      WebSocketService.instance.sendAction({
        "action": "day_action",
        "voter": _myName,
        "target": targetName
      });

      setState(() => _voteConfirmed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Vote locked for $targetName'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _navigationTimer?.cancel();
    _socketSubscription?.cancel();
    if (kIsWeb && _videoSource != null) {
      revokeVideoUrl(_videoSource!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activePlayers.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.red)));

    final bool isMeDead = _myName != null && _activePlayers.any((p) => p["name"] == _myName && !p["isAlive"]);

    return Scaffold(
      backgroundColor: const Color(0xFF070708),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          "DISCUSSION TIME: 00:${_secondsLeft.toString().padLeft(2, '0')}",
                          style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text("DISCUSS AND VOTE FOR EXECUTIONS", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
                  const SizedBox(height: 24),

                  Expanded(
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
                          onTap: (isMeDead || !isAlive || _voteConfirmed) ? null : () => setState(() => _selectedPlayerIndex = index),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C0C0E),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: !isAlive 
                                    ? Colors.red.withValues(alpha: 0.3) 
                                    : (isSelected ? Colors.redAccent : Colors.white12),
                                width: 1.5,
                              ),
                              boxShadow: isSelected 
                                  ? [
                                      BoxShadow(
                                        color: Colors.redAccent.withValues(alpha: 0.25),
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
                                                        Colors.redAccent.withValues(alpha: isSelected ? 0.25 : 0.05),
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
                                          color: !isAlive ? Colors.red.shade400 : (isSelected ? Colors.redAccent : Colors.white),
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

                  if (_selectedPlayerIndex != null && !_voteConfirmed && !isMeDead)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade900,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _confirmVote,
                          child: Text(
                            "CAST EXECUTION VOTE FOR: ${_activePlayers[_selectedPlayerIndex!]["name"].toUpperCase()}",
                            style: const TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),

                  if (isMeDead)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 24.0),
                      child: Text(
                        "YOU ARE ELIMINATED. SPECTATING THE MATCH...",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TerminalChatPanel(
                    channel: "public",
                    themeColor: Colors.greenAccent,
                    isDisabled: isMeDead,
                    messages: _chatMessages,
                    myName: _myName ?? "Guest",
                    onSendMessage: _sendChatMessage,
                  ),
                ],
              ),
            ),
          ),

          if (_showSystemAnnouncement)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.95),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        const CreepyWarningIcon(size: 80),
                        const SizedBox(height: 24),
                        Text(
                          _announcementText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                            height: 1.5,
                          ),
                        ),
                        if (widget.victimName != null || widget.ritualStatus == "failed") ...[
                          const SizedBox(height: 32),
                          if (widget.murderVideoBase64 != null) ...[
                            if (_videoSource != null) ...[
                              Text(
                                widget.ritualStatus == "failed"
                                    ? "BOTCHED TAPE RECOVERY..."
                                    : "WITNESS THEIR FINAL MOMENTS...",
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 12),
                              CreepyInlineVideoPlayer(videoSource: _videoSource!),
                            ] else ...[
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(color: Colors.redAccent),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                          ],
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: () {
                              setState(() => _showSystemAnnouncement = false);
                            },
                            child: const Text(
                              "CLOSE ANNOUNCEMENT",
                              style: TextStyle(
                                  color: Colors.white60,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                        if (widget.doctorSaved) ...[
                          const SizedBox(height: 32),
                          const EcgHeartbeatCard(),
                          const SizedBox(height: 24),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            onPressed: () {
                              setState(() => _showSystemAnnouncement = false);
                            },
                            child: const Text(
                              "CLOSE ANNOUNCEMENT",
                              style: TextStyle(
                                  color: Colors.white60,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showLynchedAnimation)
            Positioned.fill(
              child: LynchingOverlay(
                playerName: _executedPlayerName,
                failedToVotePlayers: _failedToVotePlayers,
                activePlayers: _activePlayers,
              ),
            ),
        ],
      ),
    );
  }
}

class CreepyWarningIcon extends StatelessWidget {
  final double size;
  const CreepyWarningIcon({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _WarningPainter(color: Colors.red),
    );
  }
}

class _WarningPainter extends CustomPainter {
  final Color color;
  _WarningPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width / 2, size.height * 0.1)
      ..lineTo(size.width * 0.1, size.height * 0.9)
      ..lineTo(size.width * 0.9, size.height * 0.9)
      ..close();

    canvas.drawPath(path, paint);

    final paintFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Exclamation mark line
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width / 2 - 2.5, size.height * 0.38, 5, size.height * 0.25),
        const Radius.circular(2.5),
      ),
      paintFill,
    );

    // Exclamation mark dot
    canvas.drawCircle(Offset(size.width / 2, size.height * 0.76), 3.5, paintFill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CreepyInlineVideoPlayer extends StatefulWidget {
  final String videoSource;
  const CreepyInlineVideoPlayer({super.key, required this.videoSource});

  @override
  State<CreepyInlineVideoPlayer> createState() => _CreepyInlineVideoPlayerState();
}

class _CreepyInlineVideoPlayerState extends State<CreepyInlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _isBlinking = true;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || widget.videoSource.startsWith('http') || widget.videoSource.startsWith('blob:')) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoSource));
    } else {
      _controller = VideoPlayerController.file(File(widget.videoSource));
    }
    _controller.initialize().then((_) {
        if (mounted) {
          setState(() {
            _initialized = true;
          });
          _controller.play();
          _controller.setLooping(true);
        }
      }).catchError((error) {
        debugPrint("Inline Video Player error: $error");
        if (mounted) {
          setState(() {
            _hasError = true;
          });
        }
      });

    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (mounted) {
        setState(() {
          _isBlinking = !_isBlinking;
        });
      }
    });
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade900, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.2),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_initialized)
            GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          else if (_hasError)
            const Center(
              child: Text(
                "FAILED TO DECODE TAPE",
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            )
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: CircularProgressIndicator(color: Colors.red),
              ),
            ),

          // CRT scanline overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.red.withValues(alpha: 0.05),
                      Colors.transparent,
                      Colors.red.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Blinking REC dot (Custom container to bypass font fallback errors)
          Positioned(
            top: 12,
            left: 12,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isBlinking ? Colors.red : Colors.red.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  "REC",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // Blinking LIVE Indicator
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                "LIVE",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Custom Paused text
          if (_initialized && !_controller.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "PAUSED",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EcgHeartbeatCard extends StatefulWidget {
  const EcgHeartbeatCard({super.key});

  @override
  State<EcgHeartbeatCard> createState() => _EcgHeartbeatCardState();
}

class _EcgHeartbeatCardState extends State<EcgHeartbeatCard> with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _stabilizeController;
  late AnimationController _heartController;
  late Animation<double> _heartScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _stabilizeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..forward();

    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();

    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.25), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1.25, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.35), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.35, end: 1.0), weight: 50),
    ]).animate(_heartController);
  }

  @override
  void dispose() {
    _controller.dispose();
    _stabilizeController.dispose();
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _stabilizeController,
      builder: (context, child) {
        final double factor = _stabilizeController.value;
        Color accentColor = Colors.tealAccent;
        Color borderColor = Colors.teal.shade900;
        String statusText = "HEART RATE: STABLE";

        if (factor < 0.35) {
          accentColor = Colors.redAccent;
          borderColor = Colors.red.shade900;
          statusText = "HEART RATE: FLATLINE (ALERT)";
        } else if (factor < 0.7) {
          accentColor = Colors.orangeAccent;
          borderColor = Colors.orange.shade900;
          statusText = "HEART RATE: ARRHYTHMIA (STABILIZING)";
        }

        return Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.15),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(double.infinity, 160),
                    painter: EcgPainter(
                      animationValue: _controller.value,
                      stabilizationFactor: factor,
                      color: accentColor,
                    ),
                  );
                },
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  children: [
                    ScaleTransition(
                      scale: factor > 0.35 ? _heartScale : const AlwaysStoppedAnimation(1.0),
                      child: Icon(
                        Icons.favorite, 
                        color: factor < 0.35 ? Colors.redAccent : (factor < 0.7 ? Colors.orangeAccent : Colors.tealAccent), 
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    factor < 0.7 ? "INTERVENING..." : "PATIENT SECURED",
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class EcgPainter extends CustomPainter {
  final double animationValue;
  final double stabilizationFactor;
  final Color color;

  EcgPainter({
    required this.animationValue,
    required this.stabilizationFactor,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;

    // Draw grid lines first for the high-tech look
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double i = 0; i < width; i += 20) {
      canvas.drawLine(Offset(i, 0), Offset(i, height), gridPaint);
    }
    for (double i = 0; i < height; i += 20) {
      canvas.drawLine(Offset(0, i), Offset(width, i), gridPaint);
    }

    // Draw the ECG wave
    for (double x = 0; x < width; x++) {
      double y = centerY;

      // Distance from the current animation pulse sweep
      final sweepX = animationValue * width;
      final distance = (x - sweepX).abs();
      
      if (distance < 40) {
        final t = (40 - distance) / 40; // 1 at sweepX, 0 at borders
        final waveIndex = ((x - sweepX) / 40) * 2 * pi; // range [-pi, pi]
        
        if (waveIndex > -pi && waveIndex < pi) {
          if (stabilizationFactor < 0.35) {
            // Near flatline with slight sensor twitching
            y += sin(x * 0.4) * 1.5 * t;
          } else if (stabilizationFactor < 0.7) {
            // Arrhythmia: chaotic multiple beats
            y -= sin(waveIndex * 8) * (height * 0.22) * t;
          } else {
            // QRS complex approximation (sinus rhythm)
            if (waveIndex > -pi/4 && waveIndex < pi/4) {
              y -= sin(waveIndex * 4) * (height * 0.4) * t;
            } else if (waveIndex > -pi/2 && waveIndex < -pi/4) {
              y += sin(waveIndex * 2) * (height * 0.08) * t;
            } else if (waveIndex > pi/4 && waveIndex < pi/2) {
              y -= sin(waveIndex * 2) * (height * 0.12) * t;
            }
          }
        }
      }

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Glowing scan head dot
    final scanHeadX = animationValue * width;
    final glowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(scanHeadX, centerY), 5, glowPaint);
    canvas.drawCircle(Offset(scanHeadX, centerY), 10, Paint()..color = color.withValues(alpha: 0.2)..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant EcgPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
           oldDelegate.stabilizationFactor != stabilizationFactor ||
           oldDelegate.color != color;
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

// =================== LYNCHING / VOTE RESOLUTION OVERLAY ===================
class LynchingOverlay extends StatefulWidget {
  final String? playerName;
  final List<String> failedToVotePlayers;
  final List<Map<String, dynamic>> activePlayers;

  const LynchingOverlay({
    super.key,
    required this.playerName,
    required this.failedToVotePlayers,
    required this.activePlayers,
  });

  @override
  State<LynchingOverlay> createState() => _LynchingOverlayState();
}

class _LynchingOverlayState extends State<LynchingOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _stampScaleAnimation;
  late Animation<double> _stampRotationAnimation;
  bool _showStamp = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
      ),
    );

    _stampScaleAnimation = Tween<double>(begin: 4.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.65, curve: Curves.elasticOut),
      ),
    );

    _stampRotationAnimation = Tween<double>(begin: -0.5, end: -0.2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();

    // Delay stamp showing to match the scale animation trigger time
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _showStamp = true;
        });
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
    final hasCasualties = widget.playerName != null || widget.failedToVotePlayers.isNotEmpty;

    // Gather all casualty info
    final List<Map<String, dynamic>> casualties = [];
    if (widget.playerName != null) {
      final pMap = widget.activePlayers.firstWhere(
        (p) => p["name"] == widget.playerName,
        orElse: () => <String, dynamic>{},
      );
      casualties.add({
        "name": widget.playerName!,
        "avatarBase64": pMap["avatarBase64"],
        "reason": "EXECUTED (POPULAR VOTE)",
        "stamp": "VOTED OUT"
      });
    }
    for (final name in widget.failedToVotePlayers) {
      final pMap = widget.activePlayers.firstWhere(
        (p) => p["name"] == name,
        orElse: () => <String, dynamic>{},
      );
      casualties.add({
        "name": name,
        "avatarBase64": pMap["avatarBase64"],
        "reason": "PENALTY: FAILURE TO VOTE",
        "stamp": "SYSTEM ELIM"
      });
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: Colors.black.withValues(alpha: 0.98),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient red warning pulse
            if (hasCasualties)
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.2, end: 0.6),
                  duration: const Duration(seconds: 1),
                  builder: (context, value, child) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.2,
                          colors: [
                            Colors.red.withValues(alpha: value * 0.15),
                            Colors.black,
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Scanlines
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CRTScanlinePainter(),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Top blinking alarm label
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          !hasCasualties ? Icons.warning_amber_rounded : Icons.gavel,
                          color: !hasCasualties ? Colors.orangeAccent : Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          !hasCasualties ? "VOTE TIED - NO CONSENSUS" : "CLASS RESOLUTION REGISTERED",
                          style: TextStyle(
                            color: !hasCasualties ? Colors.orangeAccent : Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    if (hasCasualties) ...[
                      // Casualty count notification
                      Text(
                        "${casualties.length} CASUALTIES REGISTERED DUSK",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // List/Display of casualties
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: casualties.length,
                          itemBuilder: (context, index) {
                            final cas = casualties[index];
                            final imageBytes = cas["avatarBase64"] != null 
                                ? ImageHelper.base64ToImage(cas["avatarBase64"]) 
                                : null;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C0D10),
                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.15)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  // Profile Picture
                                  Container(
                                    height: 90,
                                    width: 90,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25), width: 1.5),
                                      color: const Color(0xFF0F0F12),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (imageBytes != null)
                                          Image.memory(
                                            imageBytes,
                                            fit: BoxFit.cover,
                                            height: 90,
                                            width: 90,
                                            color: Colors.red.withValues(alpha: 0.25),
                                            colorBlendMode: BlendMode.colorBurn,
                                          )
                                        else
                                          const Icon(Icons.person, color: Colors.white24, size: 40),
                                        
                                        // Target Brackets overlay
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: TargetBracketsPainter(color: Colors.redAccent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  
                                  // Details and stamp
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cas["name"].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          cas["reason"],
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          "STATUS: SYSTEM TERMINATED",
                                          style: TextStyle(
                                            color: Colors.white24,
                                            fontFamily: 'monospace',
                                            fontSize: 8,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Diagonal Stamp
                                  if (_showStamp)
                                    AnimatedBuilder(
                                      animation: _controller,
                                      builder: (context, child) {
                                        return Transform.rotate(
                                          angle: _stampRotationAnimation.value,
                                          child: Transform.scale(
                                            scale: _stampScaleAnimation.value,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: Colors.redAccent, width: 2),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                cas["stamp"].toUpperCase(),
                                                style: const TextStyle(
                                                  color: Colors.redAccent,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 2,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.red,
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ] else ...[
                      // Tie graphic
                      Container(
                        height: 180,
                        width: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2), width: 3),
                        ),
                        child: Center(
                          child: Container(
                            height: 140,
                            width: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.orangeAccent.withValues(alpha: 0.05),
                              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.4), width: 1),
                            ),
                            child: const Icon(
                              Icons.people_outline,
                              color: Colors.orangeAccent,
                              size: 60,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        "NO CONSENSUS",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "DECISION: TIED VOTE SPLIT",
                        style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "STATUS: ALL CLASSMATES SAFE FOR NOW",
                        style: TextStyle(
                          color: Colors.white30,
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TargetBracketsPainter extends CustomPainter {
  final Color color;
  TargetBracketsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final length = 20.0;
    
    // Top-left bracket
    canvas.drawPath(
      Path()
        ..moveTo(0, length)
        ..lineTo(0, 0)
        ..lineTo(length, 0),
      paint,
    );

    // Top-right bracket
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, length),
      paint,
    );

    // Bottom-left bracket
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height - length)
        ..lineTo(0, size.height)
        ..lineTo(length, size.height),
      paint,
    );

    // Bottom-right bracket
    canvas.drawPath(
      Path()
        ..moveTo(size.width - length, size.height)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width, size.height - length),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}