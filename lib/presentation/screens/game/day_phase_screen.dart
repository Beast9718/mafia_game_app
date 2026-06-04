import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../data/datasources/local_storage.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/utils/image_helper.dart'; 

class DayPhaseScreen extends StatefulWidget {
  final String? victimName;
  final List<Map<String, dynamic>> players; 

  const DayPhaseScreen({super.key, this.victimName, required this.players});

  @override
  State<DayPhaseScreen> createState() => _DayPhaseScreenState();
}

class _DayPhaseScreenState extends State<DayPhaseScreen> {
  int _secondsLeft = 45; 
  Timer? _countdownTimer;
  bool _showSystemAnnouncement = true;
  late String _announcementText;
  
  int? _selectedPlayerIndex;
  bool _voteConfirmed = false;
  String? _myName;
  
  bool _isNavigating = false;
  bool _isGameOver = false; 
  
  List<Map<String, dynamic>> _activePlayers = []; 
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    
    if (widget.victimName == null) {
      _announcementText = "🔊 MORNING BRIEFING\n\nA miracle occurred.\n\nNOBODY DIED LAST NIGHT.";
    } else {
      _announcementText = "🔊 MORNING BRIEFING\n\n${widget.victimName} was brutally targeted last night.\n\nTHEY ARE NO LONGER IN THE GAME.";
    }

    _startTimer();
    _loadPlayerData();
    _listenToServer();

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showSystemAnnouncement = false);
    });
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
    _socketSubscription = WebSocketService.instance.stream?.listen((message) async {
      final decoded = jsonDecode(message);
      
      // 1. GAME OVER TRAP
      if (decoded['event'] == 'game_over') {
        _countdownTimer?.cancel(); // 🚨 Kill the clock!
        _isGameOver = true; 
        if (mounted) {
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) context.go('/game-over', extra: {'winner': decoded['winner']});
          });
        }
      }

      // 2. REGULAR PHASE TRANSITION
      if (decoded['event'] == 'dusk_briefing') {
        _countdownTimer?.cancel(); // 🚨 Kill the clock!
        
        if (mounted && !_isNavigating) {
           _isNavigating = true;
           final executedPlayer = decoded['executed'];
          
          if (executedPlayer != null) {
            await LocalStorage.instance.killPlayer(executedPlayer);
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('TOWN DECISION: $executedPlayer has been executed.'),
                  backgroundColor: Colors.red.shade900,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else {
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('TOWN DECISION: Tied vote. Nobody was executed.'),
                  backgroundColor: Colors.grey.shade800,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }

          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_isGameOver) {
               context.go('/game/night', extra: {'players': widget.players});
            }
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
    
    Future.delayed(const Duration(seconds: 4), () {
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
    _socketSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activePlayers.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.red)));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
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
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 1.5),
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
                        crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 16, childAspectRatio: 0.85,
                      ),
                      itemBuilder: (context, index) {
                        final player = _activePlayers[index];
                        final bool isAlive = player["isAlive"];
                        final bool isSelected = _selectedPlayerIndex == index;

                        final imageBytes = ImageHelper.base64ToImage(player["avatarBase64"]);
                        final hasValidAvatar = imageBytes != null;

                        return GestureDetector(
                          onTap: (!isAlive || _voteConfirmed) ? null : () => setState(() => _selectedPlayerIndex = index),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? Colors.redAccent : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Colors.grey.shade900,
                                      backgroundImage: hasValidAvatar ? MemoryImage(imageBytes) : null,
                                      child: !hasValidAvatar ? const Icon(Icons.person, color: Colors.white24, size: 28) : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    player["name"],
                                    style: TextStyle(
                                      color: isAlive ? Colors.white : Colors.white24,
                                      fontSize: 13,
                                      decoration: isAlive ? TextDecoration.none : TextDecoration.lineThrough,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              if (!isAlive)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(12)),
                                    child: const Center(child: Text("❌", style: TextStyle(fontSize: 48, color: Colors.red))),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  if (_selectedPlayerIndex != null && !_voteConfirmed)
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
                ],
              ),
            ),
          ),

          if (_showSystemAnnouncement)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.95),
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 80),
                    const SizedBox(height: 24),
                    Text(
                      _announcementText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 1.2, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}