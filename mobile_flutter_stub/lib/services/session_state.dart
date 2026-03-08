import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FriendListItem {
  const FriendListItem({
    required this.friendshipId,
    required this.friendUserId,
    required this.name,
    required this.status,
    required this.direction,
    this.friendAgentId,
    this.domainTags = const [],
  });

  final String friendshipId;
  final String friendUserId;
  final String name;
  final String status;
  final String direction;
  final String? friendAgentId;
  final List<String> domainTags;
}

class MeetingHistoryItem {
  const MeetingHistoryItem({
    required this.meetingId,
    required this.topic,
    required this.mode,
    required this.status,
    required this.createdAt,
    this.summaryText,
  });

  final String meetingId;
  final String topic;
  final String mode;
  final String status;
  final String createdAt;
  final String? summaryText;
}

class SessionState extends ChangeNotifier {
  SessionState._();

  static final SessionState instance = SessionState._();
  static const _aiBaseUrlKey = 'ai_base_url';
  static const _aiApiKeyKey = 'ai_api_key';
  static const _aiModelKey = 'ai_model';
  static const _aiTemperatureKey = 'ai_temperature';
  static const _serverBaseUrlKey = 'server_base_url';
  static const _authTokenKey = 'auth_token';
  static const _currentUserIdKey = 'current_user_id';
  static const _currentUserNameKey = 'current_user_name';
  static const _currentTimezoneKey = 'current_timezone';
  static const _currentAgentIdKey = 'current_agent_id';
  static const _currentAgentProfileKey = 'current_agent_profile';
  static const _secureStorage = FlutterSecureStorage();

  String? currentUserId;
  String? currentUserName;
  String? currentTimezone;
  String? currentAgentId;
  Map<String, dynamic>? currentAgentProfile;
  String? friendshipId;
  String? authToken;
  String serverBaseUrl = 'http://127.0.0.1:8000';
  String aiBaseUrl = '';
  String aiApiKey = '';
  String aiModel = '';
  double aiTemperature = 0.7;
  bool isSyncing = false;
  String? syncError;
  DateTime? lastSyncedAt;

  final List<FriendListItem> friends = [];
  final List<MeetingHistoryItem> meetings = [];

  bool get hasUser => currentUserId != null;
  bool get hasAuthSession => authToken != null && authToken!.isNotEmpty;
  bool get hasAgent => currentAgentId != null;
  bool get hasFriend => friends.isNotEmpty;
  bool get hasAiConfig =>
      aiBaseUrl.trim().isNotEmpty && aiApiKey.trim().isNotEmpty && aiModel.trim().isNotEmpty;

  Future<void> loadLocalPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    authToken = await _secureStorage.read(key: _authTokenKey);
    serverBaseUrl = prefs.getString(_serverBaseUrlKey) ?? 'http://127.0.0.1:8000';
    aiBaseUrl = prefs.getString(_aiBaseUrlKey) ?? '';
    aiApiKey = await _secureStorage.read(key: _aiApiKeyKey) ?? '';
    aiModel = prefs.getString(_aiModelKey) ?? '';
    aiTemperature = prefs.getDouble(_aiTemperatureKey) ?? 0.7;
    currentUserId = prefs.getString(_currentUserIdKey);
    currentUserName = prefs.getString(_currentUserNameKey);
    currentTimezone = prefs.getString(_currentTimezoneKey);
    currentAgentId = prefs.getString(_currentAgentIdKey);
    final rawAgentProfile = prefs.getString(_currentAgentProfileKey);
    if (rawAgentProfile != null && rawAgentProfile.isNotEmpty) {
      try {
        currentAgentProfile = Map<String, dynamic>.from(jsonDecode(rawAgentProfile) as Map);
      } catch (_) {
        currentAgentProfile = null;
      }
    }
    if (currentUserId != null && (authToken == null || authToken!.isEmpty)) {
      currentUserId = null;
      currentUserName = null;
      currentTimezone = null;
      currentAgentId = null;
      currentAgentProfile = null;
      unawaited(_clearSessionState());
    }
    notifyListeners();
  }

  Future<void> saveAiSettings({
    required String baseUrl,
    required String apiKey,
    required String model,
    required double temperature,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    aiBaseUrl = baseUrl.trim();
    aiApiKey = apiKey.trim();
    aiModel = model.trim();
    aiTemperature = temperature;
    await prefs.setString(_aiBaseUrlKey, aiBaseUrl);
    await _secureStorage.write(key: _aiApiKeyKey, value: aiApiKey);
    await prefs.setString(_aiModelKey, aiModel);
    await prefs.setDouble(_aiTemperatureKey, aiTemperature);
    notifyListeners();
  }

  Future<void> saveServerBaseUrl(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    serverBaseUrl = baseUrl.trim().isEmpty ? 'http://127.0.0.1:8000' : baseUrl.trim();
    await prefs.setString(_serverBaseUrlKey, serverBaseUrl);
    notifyListeners();
  }

  Future<void> saveAuthSession({
    required Map<String, dynamic> user,
    required String token,
  }) async {
    authToken = token.trim();
    await _secureStorage.write(key: _authTokenKey, value: authToken!);
    setCurrentUser(user);
  }

  Future<void> clearAuthSession() async {
    authToken = null;
    await _secureStorage.delete(key: _authTokenKey);
    resetLocalState();
  }

  Future<void> clearAiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    aiBaseUrl = '';
    aiApiKey = '';
    aiModel = '';
    aiTemperature = 0.7;
    await prefs.remove(_aiBaseUrlKey);
    await _secureStorage.delete(key: _aiApiKeyKey);
    await prefs.remove(_aiModelKey);
    await prefs.remove(_aiTemperatureKey);
    notifyListeners();
  }

  Map<String, dynamic>? aiConfigPayload() {
    if (!hasAiConfig) return null;
    return {
      'base_url': aiBaseUrl.trim(),
      'api_key': aiApiKey.trim(),
      'model': aiModel.trim(),
      'temperature': aiTemperature,
    };
  }

  String maskedApiKey() {
    if (aiApiKey.length <= 8) return aiApiKey;
    return '${aiApiKey.substring(0, 4)}****${aiApiKey.substring(aiApiKey.length - 4)}';
  }

  void beginSync() {
    isSyncing = true;
    syncError = null;
    notifyListeners();
  }

  void markSyncSuccess() {
    isSyncing = false;
    syncError = null;
    lastSyncedAt = DateTime.now();
    notifyListeners();
  }

  void markSyncFailure(String message) {
    isSyncing = false;
    syncError = message;
    notifyListeners();
  }

  void setCurrentUser(Map<String, dynamic> user) {
    currentUserId = user['id'] as String?;
    currentUserName = user['name'] as String?;
    currentTimezone = user['timezone'] as String?;
    unawaited(_persistSessionState());
    notifyListeners();
  }

  void updateCurrentUserName(String name) {
    currentUserName = name;
    unawaited(_persistSessionState());
    notifyListeners();
  }

  void setCurrentAgent(Map<String, dynamic> agent) {
    currentAgentId = agent['id'] as String?;
    currentAgentProfile = agent;
    unawaited(_persistSessionState());
    notifyListeners();
  }

  void upsertFriendFromPayload(Map<String, dynamic> payload) {
    final friendship = Map<String, dynamic>.from(payload['friendship'] as Map);
    final friendUser = Map<String, dynamic>.from(payload['friend_user'] as Map);
    final friendAgentRaw = payload['friend_agent'];
    final friendAgent = friendAgentRaw is Map ? Map<String, dynamic>.from(friendAgentRaw) : null;

    final next = FriendListItem(
      friendshipId: friendship['id'] as String,
      friendUserId: friendUser['id'] as String,
      name: friendUser['name'] as String? ?? '未命名用户',
      status: friendship['status'] as String? ?? 'pending',
      direction: payload['direction'] as String? ?? 'connected',
      friendAgentId: friendAgent?['id'] as String?,
      domainTags: friendAgent == null
          ? const []
          : List<String>.from((friendAgent['domain_tags'] as List?) ?? const []),
    );

    final index = friends.indexWhere((item) => item.friendshipId == next.friendshipId);
    if (index >= 0) {
      friends[index] = next;
    } else {
      friends.insert(0, next);
    }
    friendshipId = next.friendshipId;
    notifyListeners();
  }

  void replaceFriends(List<dynamic> items) {
    friends
      ..clear()
      ..addAll(
        items.map((item) {
          final payload = Map<String, dynamic>.from(item as Map);
          final friendship = Map<String, dynamic>.from(payload['friendship'] as Map);
          final friendUser = Map<String, dynamic>.from(payload['friend_user'] as Map);
          final friendAgentRaw = payload['friend_agent'];
          final friendAgent = friendAgentRaw is Map ? Map<String, dynamic>.from(friendAgentRaw) : null;
          return FriendListItem(
            friendshipId: friendship['id'] as String,
            friendUserId: friendUser['id'] as String,
            name: friendUser['name'] as String? ?? '未命名用户',
            status: friendship['status'] as String? ?? 'pending',
            direction: payload['direction'] as String? ?? 'connected',
            friendAgentId: friendAgent?['id'] as String?,
            domainTags: friendAgent == null
                ? const []
                : List<String>.from((friendAgent['domain_tags'] as List?) ?? const []),
          );
        }),
      );
    notifyListeners();
  }

  void upsertMeetingFromPayload(Map<String, dynamic> payload) {
    final meeting = Map<String, dynamic>.from(payload['meeting'] as Map);
    final summaryRaw = payload['summary'];
    final summary = summaryRaw is Map ? Map<String, dynamic>.from(summaryRaw) : null;
    final item = MeetingHistoryItem(
      meetingId: meeting['id'] as String,
      topic: meeting['topic'] as String? ?? '未命名会议',
      mode: meeting['mode'] as String? ?? 'moderated',
      status: meeting['status'] as String? ?? 'created',
      createdAt: meeting['created_at'] as String? ?? '',
      summaryText: summary?['summary_text'] as String?,
    );
    final index = meetings.indexWhere((entry) => entry.meetingId == item.meetingId);
    if (index >= 0) {
      meetings[index] = item;
    } else {
      meetings.insert(0, item);
    }
    notifyListeners();
  }

  void replaceMeetings(List<dynamic> items) {
    meetings
      ..clear()
      ..addAll(
        items.map((item) {
          final payload = Map<String, dynamic>.from(item as Map);
          final meeting = Map<String, dynamic>.from(payload['meeting'] as Map);
          final summaryRaw = payload['summary'];
          final summary = summaryRaw is Map ? Map<String, dynamic>.from(summaryRaw) : null;
          return MeetingHistoryItem(
            meetingId: meeting['id'] as String,
            topic: meeting['topic'] as String? ?? '未命名会议',
            mode: meeting['mode'] as String? ?? 'moderated',
            status: meeting['status'] as String? ?? 'created',
            createdAt: meeting['created_at'] as String? ?? '',
            summaryText: summary?['summary_text'] as String?,
          );
        }),
      );
    notifyListeners();
  }

  void resetLocalState() {
    currentUserId = null;
    currentUserName = null;
    currentTimezone = null;
    currentAgentId = null;
    currentAgentProfile = null;
    friendshipId = null;
    authToken = null;
    friends.clear();
    meetings.clear();
    isSyncing = false;
    syncError = null;
    lastSyncedAt = null;
    unawaited(_clearSessionState());
    notifyListeners();
  }

  Future<void> _persistSessionState() async {
    final prefs = await SharedPreferences.getInstance();
    if (currentUserId == null) {
      await prefs.remove(_currentUserIdKey);
    } else {
      await prefs.setString(_currentUserIdKey, currentUserId!);
    }
    if (currentUserName == null) {
      await prefs.remove(_currentUserNameKey);
    } else {
      await prefs.setString(_currentUserNameKey, currentUserName!);
    }
    if (currentTimezone == null) {
      await prefs.remove(_currentTimezoneKey);
    } else {
      await prefs.setString(_currentTimezoneKey, currentTimezone!);
    }
    if (currentAgentId == null) {
      await prefs.remove(_currentAgentIdKey);
    } else {
      await prefs.setString(_currentAgentIdKey, currentAgentId!);
    }
    if (currentAgentProfile == null) {
      await prefs.remove(_currentAgentProfileKey);
    } else {
      await prefs.setString(_currentAgentProfileKey, jsonEncode(currentAgentProfile));
    }
  }

  Future<void> _clearSessionState() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _authTokenKey);
    await prefs.remove(_currentUserIdKey);
    await prefs.remove(_currentUserNameKey);
    await prefs.remove(_currentTimezoneKey);
    await prefs.remove(_currentAgentIdKey);
    await prefs.remove(_currentAgentProfileKey);
  }
}
