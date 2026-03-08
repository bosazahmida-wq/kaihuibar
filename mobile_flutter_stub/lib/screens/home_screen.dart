import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/meeting_models.dart';
import '../services/api_client.dart';
import '../services/session_state.dart';
import '../theme/notion_theme.dart';
import '../widgets/notion_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient();
  final _state = SessionState.instance;
  String? _lastSyncKey;

  @override
  void initState() {
    super.initState();
    _state.addListener(_handleSessionChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDashboard(force: true));
  }

  @override
  void dispose() {
    _state.removeListener(_handleSessionChange);
    super.dispose();
  }

  void _handleSessionChange() {
    final nextKey = '${_state.currentUserId}:${_state.currentAgentId}';
    if (_state.currentUserId != null && nextKey != _lastSyncKey && !_state.isSyncing) {
      _syncDashboard(force: true);
    }
  }

  Future<void> _syncDashboard({bool force = false}) async {
    final userId = _state.currentUserId;
    if (userId == null) return;

    final syncKey = '$userId:${_state.currentAgentId}';
    if (!force && syncKey == _lastSyncKey) return;

    _lastSyncKey = syncKey;
    _state.beginSync();

    try {
      final results = await Future.wait<dynamic>([
        _api.listAgents(userId),
        _api.listFriends(userId),
        _api.listMeetings(userId),
      ]);

      final agents = List<dynamic>.from(results[0] as List);
      final friends = List<dynamic>.from(results[1] as List);
      final meetings = List<dynamic>.from(results[2] as List);

      if (agents.isNotEmpty) {
        final preferred = agents.cast<Map>().firstWhere(
              (agent) => agent['id'] == _state.currentAgentId,
              orElse: () => agents.first as Map,
            );
        _state.setCurrentAgent(Map<String, dynamic>.from(preferred));
      }

      _state.replaceFriends(friends);
      _state.replaceMeetings(meetings);

      _lastSyncKey = '$userId:${_state.currentAgentId}';
      _state.markSyncSuccess();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _state.resetLocalState();
        _state.markSyncFailure('登录状态已失效，请重新创建用户');
        return;
      }
      _state.markSyncFailure('同步失败: ${e.response?.data ?? e.message}');
    } catch (e) {
      _state.markSyncFailure('同步失败: $e');
    }
  }

  String _syncCaption() {
    if (_state.isSyncing) return '正在同步数据...';
    if (_state.syncError != null) return _state.syncError!;
    if (_state.lastSyncedAt == null) return '尚未同步';
    final local = _state.lastSyncedAt!.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '最近同步于 $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final latestMeeting = _state.meetings.isEmpty ? null : _state.meetings.first;
        final latestFriend = _state.friends.isEmpty ? null : _state.friends.first;

        return Scaffold(
          appBar: AppBar(
            title: const Text('开会吧'),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _state.isSyncing ? null : () => _syncDashboard(force: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF8F8F6), Color(0xFFFFFFFF)],
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                NotionSectionCard(
                  title: '工作台',
                  subtitle: _state.currentUserName == null
                      ? '先完成你的第一个 Agent 设置'
                      : '你好，${_state.currentUserName}',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: MetricTile(
                              label: '智能体',
                              value: _state.hasAgent ? '1' : '0',
                              caption: _state.hasAgent ? '已完成校准' : '待创建',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: MetricTile(
                              label: '好友',
                              value: '${_state.friends.length}',
                              caption: _state.hasFriend ? '可邀请入会' : '待建立关系',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: MetricTile(
                              label: '会议',
                              value: '${_state.meetings.length}',
                              caption: _state.meetings.isEmpty ? '暂无历史' : '已有总结',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StatusText(_syncCaption()),
                      const SizedBox(height: 12),
                      ActionTile(
                        title: '继续完善智能体',
                        description: '更新人设、风格和校准话术，让协作输出更稳定。',
                        icon: Icons.smart_toy_outlined,
                        onTap: () => context.go('/agents'),
                      ),
                      const SizedBox(height: 8),
                      ActionTile(
                        title: '邀请好友一起协作',
                        description: '建立轻关系链后，就能把对方智能体一起拉进会议。',
                        icon: Icons.group_outlined,
                        onTap: () => context.go('/friends'),
                      ),
                      const SizedBox(height: 8),
                      ActionTile(
                        title: '发起一次会议',
                        description: '选择模式，快速拿到主持总结与下一步建议。',
                        icon: Icons.forum_outlined,
                        onTap: () => context.go('/meetings'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                NotionSectionCard(
                  title: '最近会议',
                  action: TextButton(
                    onPressed: () => context.go('/meetings'),
                    child: const Text('查看全部'),
                  ),
                  child: latestMeeting == null
                      ? const EmptyState(
                          title: '还没有会议历史',
                          description: '完成 Agent 和好友创建后，就可以从「会议」页发起第一次讨论。',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(latestMeeting.topic, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              '${meetingModeText(latestMeeting.mode)} · ${meetingStatusText(latestMeeting.status)}',
                              style: const TextStyle(color: NotionPalette.textSecondary),
                            ),
                            if (latestMeeting.summaryText != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                latestMeeting.summaryText!,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: NotionPalette.textSecondary),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                NotionSectionCard(
                  title: '协作网络',
                  action: TextButton(
                    onPressed: () => context.go('/friends'),
                    child: const Text('管理好友'),
                  ),
                  child: latestFriend == null
                      ? const EmptyState(
                          title: '好友列表为空',
                          description: '在「好友」页添加联系人后，这里会展示最近建立的关系。',
                        )
                      : Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: NotionPalette.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                latestFriend.name.characters.first.toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(latestFriend.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    latestFriend.domainTags.isEmpty
                                        ? '暂无公开场景标签'
                                        : latestFriend.domainTags.join(' · '),
                                    style: const TextStyle(color: NotionPalette.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: NotionPalette.border),
                              ),
                              child: Text(friendshipStatusText(latestFriend.status)),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
