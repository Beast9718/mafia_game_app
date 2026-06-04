import 'dart:convert';
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
  // 1. Make sure this line is present and NOT commented out:
  final String roomCode = "D3AD-N1T3";

  // 2. Make sure this points to your Render domain (no wss:// or http:// here):
  final String serverIpAddress = "mafia-game-master.onrender.com"; 

  List<Map<String, dynamic>> livePlayers = [];
  String? myName;
  String? myBase64Avatar;
  String? secretAssignedRole; 

  @override
  void initState() {
    super.initState();
    _initializeLobby();
  }

  Future<void> _initializeLobby() async {
    await LocalStorage.instance.clearGraveyard();

    final data = await LocalStorage.instance.getPlayerData();
    myName = data['name'] ?? "Unknown";
    final imagePath = data['imagePath'];

    myBase64Avatar = await ImageHelper.imageToBase64(imagePath);

    if (mounted) {
      setState(() {
        livePlayers.add({
          "name": myName,
          "isHost": true, 
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

    WebSocketService.instance.stream.listen((message) {
      final decodedMessage = jsonDecode(message);
      
      if (decodedMessage['event'] == 'room_sync') {
        final List<dynamic> totalPlayers = decodedMessage['players'] ?? [];
        final Map<String, dynamic> profiles = decodedMessage['profiles'] ?? {};
        
        setState(() {
          for (var pName in totalPlayers) {
            final existingIndex = livePlayers.indexWhere((p) => p['name'] == pName);
            if (existingIndex == -1) {
              livePlayers.add({
                "name": pName,
                "isHost": livePlayers.isEmpty, 
                "avatarBase64": profiles[pName],
              });
            } else {
              livePlayers[existingIndex]['avatarBase64'] = profiles[pName];
            }
          }
        });
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
        LocalStorage.instance.saveRole(secretAssignedRole!);
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

  void _startRoleReveal() {
    WebSocketService.instance.sendAction({"action": "start_game"});
  }

  @override
  Widget build(BuildContext context) {
    if (livePlayers.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F0F),
        body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
      );
    }

    final displayPlayers = List<Map<String, dynamic>>.from(livePlayers);
    while (displayPlayers.length < 10) {
      displayPlayers.add({"name": "Waiting...", "isHost": false, "avatarBase64": null});
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text('ROOM CODE', style: TextStyle(fontSize: 12, color: Colors.white54, letterSpacing: 2)),
            Text(roomCode, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.white)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'WAITING FOR PLAYERS (${livePlayers.length}/10)',
                style: const TextStyle(color: Colors.redAccent, letterSpacing: 1.5, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: GridView.builder(
                itemCount: displayPlayers.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 16, childAspectRatio: 0.8,
                ),
                itemBuilder: (context, index) {
                  final player = displayPlayers[index];
                  final isWaiting = player["name"] == "Waiting...";
                  
                  final base64String = player["avatarBase64"];
                  final imageBytes = ImageHelper.base64ToImage(base64String);
                  final hasValidAvatar = imageBytes != null;

                  return Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: isWaiting ? Colors.transparent : Colors.grey.shade800,
                        backgroundImage: hasValidAvatar ? MemoryImage(imageBytes) : null,
                        child: !hasValidAvatar 
                            ? Icon(
                                isWaiting ? Icons.person_outline : Icons.person, 
                                color: isWaiting ? Colors.white24 : Colors.white70, 
                                size: 40
                              ) 
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        player["name"],
                        style: TextStyle(
                          color: isWaiting ? Colors.white24 : Colors.white,
                          fontSize: 12,
                          fontWeight: player["isHost"] ? FontWeight.bold : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _startRoleReveal,
                child: const Text('BEGIN NIGHTMARE', style: TextStyle(fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}