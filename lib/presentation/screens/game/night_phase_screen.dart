import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  int? _selectedPlayerIndex;
  bool _actionConfirmed = false;
  
  bool _isNavigating = false;
  bool _isGameOver = false; 
  
  List<Map<String, dynamic>> _activePlayers = [];
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadPlayerData();
    _listenToServer();
  }

  Future<void> _loadPlayerData() async {
    final savedRole = await LocalStorage.instance.getRole(); 
    final deadPlayers = await LocalStorage.instance.getDeadPlayers();
    
    if (mounted) {
      setState(() {
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
      if (decoded['event'] == 'morning_briefing') {
        _countdownTimer?.cancel(); // 🚨 Kill the clock!
        
        if (mounted && !_isNavigating) {
          _isNavigating = true;
          final victim = decoded['victim'];
          
          if (victim != null) {
            await LocalStorage.instance.killPlayer(victim);
          }
          
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_isGameOver) { 
               context.go('/game/day', extra: {'victim': victim, 'players': widget.players});
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
    WebSocketService.instance.sendAction({"action": "sunrise"});
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && !_isNavigating && !_isGameOver) {
        _isNavigating = true;
        context.go('/game/day', extra: {'victim': null, 'players': widget.players});
      }
    });
  }

  void _confirmAction() {
    if (_selectedPlayerIndex != null) {
      final targetName = _activePlayers[_selectedPlayerIndex!]["name"];
      WebSocketService.instance.sendAction({
        "action": "night_action",
        "role": _assignedRole,
        "target": targetName
      });
      setState(() => _actionConfirmed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action locked on $targetName...'), backgroundColor: _getRoleColor().shade900),
      );
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
    _socketSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activePlayers.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.red)));

    if (_assignedRole == "STUDENT") {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.nights_stay, color: Colors.white24, size: 80),
              const SizedBox(height: 24),
              const Text('GO TO SLEEP.', style: TextStyle(color: Colors.white38, fontSize: 24, letterSpacing: 4)),
              const SizedBox(height: 16),
              Text("00:${_secondsLeft.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.white12, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    final roleColor = _getRoleColor();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
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
              Align(alignment: Alignment.centerLeft, child: Text(_getRoleInstruction(), style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2))),
              const SizedBox(height: 24),

              Expanded(
                flex: 1,
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
                      onTap: (!isAlive || _actionConfirmed) ? null : () => setState(() => _selectedPlayerIndex = index),
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
                                    color: isSelected ? roleColor.shade400 : Colors.transparent,
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
                              Text(player["name"], style: TextStyle(color: isAlive ? (isSelected ? roleColor.shade400 : Colors.white) : Colors.white24, fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                          if (!isAlive)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                                child: const Center(child: Text("❌", style: TextStyle(fontSize: 40, color: Colors.red))),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              if (_selectedPlayerIndex != null && !_actionConfirmed && _assignedRole == "MAFIA")
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.only(top: 16),
                    decoration: BoxDecoration(border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 2), borderRadius: BorderRadius.circular(16)),
                    child: MafiaKillCamera(
                      onKillRecorded: (videoPath) {
                        _confirmAction();
                      },
                    ),
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
                      onPressed: _confirmAction,
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
    );
  }
}