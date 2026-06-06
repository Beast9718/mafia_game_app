import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalStorage {
  static final LocalStorage instance = LocalStorage._internal();
  LocalStorage._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> savePlayerData(String name, String? imagePath) async {
    await _storage.write(key: 'player_name', value: name);
    if (imagePath != null) {
      await _storage.write(key: 'player_image_path', value: imagePath);
    }
  }

  Future<Map<String, String?>> getPlayerData() async {
    final name = await _storage.read(key: 'player_name');
    final imagePath = await _storage.read(key: 'player_image_path');
    return {'name': name, 'imagePath': imagePath};
  }

  Future<void> saveRole(String role) async {
    await _storage.write(key: 'player_role', value: role);
  }

  Future<String?> getRole() async {
    return await _storage.read(key: 'player_role');
  }

  Future<void> saveRoomCode(String roomCode) async {
    await _storage.write(key: 'room_code', value: roomCode);
  }

  Future<String?> getRoomCode() async {
    return await _storage.read(key: 'room_code');
  }

  Future<void> killPlayer(String name) async {
    String? currentDead = await _storage.read(key: 'graveyard');
    List<String> deadList = (currentDead != null && currentDead.isNotEmpty) ? currentDead.split(',') : [];
    
    if (!deadList.contains(name)) {
      deadList.add(name);
      await _storage.write(key: 'graveyard', value: deadList.join(','));
    }
  }

  Future<List<String>> getDeadPlayers() async {
    String? currentDead = await _storage.read(key: 'graveyard');
    return (currentDead != null && currentDead.isNotEmpty) ? currentDead.split(',') : [];
  }

  // --- NEW: Empties the graveyard so the next game starts fresh ---
  Future<void> clearGraveyard() async {
    await _storage.delete(key: 'graveyard');
  }

  Future<void> setDeadPlayers(List<String> deadNames) async {
    await _storage.write(key: 'graveyard', value: deadNames.join(','));
  }

  Future<void> clearStorage() async {
    await _storage.deleteAll();
  }
}