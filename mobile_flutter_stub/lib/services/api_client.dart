import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../models/agent_models.dart';
import '../models/meeting_models.dart';
import 'session_state.dart';

class MeetingEvent {
  const MeetingEvent({
    required this.type,
    required this.payload,
  });

  final String type;
  final Map<String, dynamic> payload;
}

class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000', connectTimeout: const Duration(seconds: 5)));

  final Dio _dio;

  String get _baseUrl {
    final configured = SessionState.instance.serverBaseUrl.trim();
    return configured.isEmpty ? 'http://127.0.0.1:8000' : configured;
  }

  void _refreshBaseUrl() {
    _dio.options.baseUrl = _baseUrl;
    final token = SessionState.instance.authToken?.trim();
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  Future<Map<String, dynamic>> registerUser(String name) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/auth/register', data: {'name': name});
    final payload = Map<String, dynamic>.from(res.data as Map);
    final user = Map<String, dynamic>.from(payload['user'] as Map);
    final token = payload['access_token'] as String;
    await SessionState.instance.saveAuthSession(user: user, token: token);
    return user;
  }

  Future<List<dynamic>> searchUsers({
    required String query,
    String? excludeUserId,
  }) async {
    _refreshBaseUrl();
    final res = await _dio.get(
      '/v1/users/search',
      queryParameters: {
        'q': query,
        if (excludeUserId != null) 'exclude_user_id': excludeUserId,
      },
    );
    return List<dynamic>.from(res.data as List);
  }

  Future<Map<String, dynamic>> updateUser({
    required String userId,
    required String name,
    String timezone = 'Asia/Shanghai',
  }) async {
    _refreshBaseUrl();
    final res = await _dio.put('/v1/auth/users/$userId', data: {
      'name': name,
      'timezone': timezone,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> bootstrapAgent(AgentBootstrapPayload payload) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/agents/bootstrap', data: payload.toJson());
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> assessmentTemplate() async {
    _refreshBaseUrl();
    final res = await _dio.get('/v1/agents/assessment/template');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> assessmentDraft(List<Map<String, dynamic>> answers) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/agents/assessment/draft', data: {'answers': answers});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateAgent({
    required String agentId,
    required AgentBootstrapPayload payload,
  }) async {
    _refreshBaseUrl();
    final json = payload.toJson()..remove('owner_user_id');
    final res = await _dio.put('/v1/agents/$agentId', data: json);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateAgentSharing({
    required String agentId,
    required bool isPublic,
    required String publicName,
    required String publicDescription,
  }) async {
    _refreshBaseUrl();
    final res = await _dio.put('/v1/agents/$agentId/sharing', data: {
      'is_public': isPublic,
      'public_name': publicName,
      'public_description': publicDescription,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<dynamic>> listAgents(String ownerUserId) async {
    _refreshBaseUrl();
    final res = await _dio.get('/v1/agents', queryParameters: {'owner_user_id': ownerUserId});
    return List<dynamic>.from(res.data as List);
  }

  Future<List<dynamic>> searchPublicAgents(String query) async {
    _refreshBaseUrl();
    final res = await _dio.get('/v1/agents/public/search', queryParameters: {'q': query});
    return List<dynamic>.from(res.data as List);
  }

  Future<Map<String, dynamic>> calibrateAgent(String agentId, List<String> chatTurns) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/agents/$agentId/calibrate-chat', data: {
      'chat_turns': chatTurns,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> requestFriend({
    required String requesterId,
    required String addresseeId,
  }) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/friends/request', data: {
      'requester_id': requesterId,
      'addressee_id': addresseeId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> acceptFriend(String friendshipId) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/friends/$friendshipId/accept');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createDemoFriend(String name) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/friends/demo', data: {'name': name});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<dynamic>> listFriends(String userId) async {
    _refreshBaseUrl();
    final res = await _dio.get('/v1/friends', queryParameters: {'user_id': userId});
    return List<dynamic>.from(res.data as List);
  }

  Future<Map<String, dynamic>> createMeeting({
    required String creatorId,
    required String topic,
    required MeetingMode mode,
    required List<MeetingParticipantInput> participants,
  }) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/meetings', data: {
      'creator_id': creatorId,
      'topic': topic,
      'mode': mode.name,
      'participants': participants.map((e) => e.toJson()).toList(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> startMeeting(String meetingId, {List<String>? order}) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/meetings/$meetingId/start', data: {
      'manual_speaker_order': order,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> startMeetingWithAiConfig(
    String meetingId, {
    List<String>? order,
    Map<String, dynamic>? aiConfig,
  }) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/meetings/$meetingId/start', data: {
      'manual_speaker_order': order,
      'ai_config': aiConfig,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> summary(String meetingId) async {
    _refreshBaseUrl();
    final res = await _dio.get('/v1/meetings/$meetingId/summary');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<dynamic>> listMeetings(String creatorId) async {
    _refreshBaseUrl();
    final res = await _dio.get('/v1/meetings', queryParameters: {'creator_id': creatorId});
    return List<dynamic>.from(res.data as List);
  }

  Future<Map<String, dynamic>> meetingDetail(String meetingId) async {
    _refreshBaseUrl();
    final res = await _dio.get('/v1/meetings/$meetingId');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Stream<MeetingEvent> streamMeetingEvents(String meetingId) async* {
    _refreshBaseUrl();
    final url = Uri.parse('${_dio.options.baseUrl}/v1/meetings/$meetingId/events');
    final client = http.Client();
    final request = http.Request('GET', url);
    final token = SessionState.instance.authToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final response = await client.send(request);

    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      client.close();
      throw Exception('流式连接失败(code=${response.statusCode}): $body');
    }

    String pending = '';
    String? eventType;
    final dataBuffer = StringBuffer();

    try {
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final merged = pending + chunk;
        final lines = merged.split('\n');
        pending = lines.removeLast();
        for (final rawLine in lines) {
          final line = rawLine.trimRight();
          if (line.isEmpty) {
            if (eventType != null) {
              final currentType = eventType;
              final rawData = dataBuffer.toString().trim();
              final payload = rawData.isEmpty
                  ? <String, dynamic>{}
                  : Map<String, dynamic>.from(jsonDecode(rawData) as Map);
              yield MeetingEvent(type: currentType, payload: payload);
            }
            eventType = null;
            dataBuffer.clear();
            continue;
          }

          if (line.startsWith('event:')) {
            eventType = line.substring(6).trim();
            continue;
          }

          if (line.startsWith('data:')) {
            if (dataBuffer.isNotEmpty) {
              dataBuffer.write('\n');
            }
            dataBuffer.write(line.substring(5).trim());
          }
        }
      }

      if (pending.trim().isNotEmpty && eventType != null) {
        final currentType = eventType;
        if (pending.trimLeft().startsWith('data:')) {
          if (dataBuffer.isNotEmpty) {
            dataBuffer.write('\n');
          }
          dataBuffer.write(pending.trim().substring(5).trim());
        }
        final rawData = dataBuffer.toString().trim();
        final payload = rawData.isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(rawData) as Map);
        yield MeetingEvent(type: currentType, payload: payload);
      }
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> testAiConnection(Map<String, dynamic> aiConfig) async {
    _refreshBaseUrl();
    final res = await _dio.post('/v1/ai/test', data: {'ai_config': aiConfig});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> health() async {
    _refreshBaseUrl();
    final res = await _dio.get('/health');
    return Map<String, dynamic>.from(res.data as Map);
  }
}
