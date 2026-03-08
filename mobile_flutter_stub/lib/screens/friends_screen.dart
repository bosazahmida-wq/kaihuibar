import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/meeting_models.dart';
import '../services/api_client.dart';
import '../services/session_state.dart';
import '../theme/notion_theme.dart';
import '../widgets/notion_widgets.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _api = ApiClient();
  final _state = SessionState.instance;
  final _demoFriendNameController = TextEditingController(text: '小林');
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = const [];
  bool _loading = false;
  bool _searching = false;
  String _status = '搜索现有用户并发送好友申请';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFriends());
  }

  @override
  void dispose() {
    _demoFriendNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshFriends() async {
    final myId = _state.currentUserId;
    if (myId == null) return;
    try {
      final result = await _api.listFriends(myId);
      _state.replaceFriends(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '好友列表刷新失败: $e');
    }
  }

  Future<void> _searchUsers() async {
    final myId = _state.currentUserId;
    if (myId == null) {
      setState(() => _status = '请先到「智能体」页完成用户创建');
      return;
    }

    setState(() {
      _searching = true;
      _status = '搜索用户中...';
    });

    try {
      final results = await _api.searchUsers(
        query: _searchController.text.trim(),
        excludeUserId: myId,
      );
      setState(() {
        _searchResults = results.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        _status = _searchResults.isEmpty ? '未找到匹配用户' : '已更新搜索结果';
      });
    } on DioException catch (e) {
      setState(
        () => _status = '搜索失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      setState(() => _status = '搜索失败: $e');
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _sendFriendRequest(String targetUserId) async {
    final myId = _state.currentUserId;
    if (myId == null) return;

    setState(() => _status = '正在发送好友申请...');
    try {
      await _api.requestFriend(requesterId: myId, addresseeId: targetUserId);
      await _refreshFriends();
      await _searchUsers();
      setState(() => _status = '好友申请已发送');
    } on DioException catch (e) {
      setState(
        () => _status = '发送失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      setState(() => _status = '发送失败: $e');
    }
  }

  Future<void> _acceptFriendRequest(String friendshipId) async {
    setState(() => _status = '正在通过好友申请...');
    try {
      await _api.acceptFriend(friendshipId);
      await _refreshFriends();
      await _searchUsers();
      setState(() => _status = '好友申请已通过');
    } on DioException catch (e) {
      setState(
        () => _status = '通过失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      setState(() => _status = '通过失败: $e');
    }
  }

  Future<void> _createDemoFriendFlow() async {
    if (_state.currentUserId == null) {
      setState(() => _status = '请先到「智能体」页完成用户创建');
      return;
    }

    final friendName = _demoFriendNameController.text.trim();
    if (friendName.isEmpty) {
      setState(() => _status = '请先填写测试好友用户名');
      return;
    }

    setState(() {
      _loading = true;
      _status = '正在生成测试好友...';
    });

    try {
      final payload = await _api.createDemoFriend(friendName);
      _state.upsertFriendFromPayload(payload);
      await _refreshFriends();
      await _searchUsers();
      setState(() => _status = '测试好友已创建并建立关系');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已生成测试好友 ${_demoFriendNameController.text.trim()}')),
        );
      }
    } on DioException catch (e) {
      setState(
        () => _status = '生成失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      setState(() => _status = '生成失败: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final incomingRequests = _state.friends
            .where((item) => item.status == 'pending' && item.direction == 'incoming')
            .toList();

        return Scaffold(
          appBar: AppBar(title: const Text('好友')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NotionSectionCard(
                title: '搜索并添加好友',
                subtitle: '搜索已有用户，发送申请或处理收到的请求',
                action: IconButton(
                  tooltip: '刷新',
                  onPressed: _refreshFriends,
                  icon: const Icon(Icons.refresh),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: '搜索用户名',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: (_) => _searchUsers(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _searching ? null : _searchUsers,
                        child: Text(_searching ? '搜索中...' : '搜索用户'),
                      ),
                    ),
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      for (final item in _searchResults) ...[
                        _SearchResultRow(
                          item: item,
                          onSendRequest: () => _sendFriendRequest(
                            Map<String, dynamic>.from(item['user'] as Map)['id'] as String,
                          ),
                          onAccept: item['friendship'] == null
                              ? null
                              : () => _acceptFriendRequest(
                                    Map<String, dynamic>.from(item['friendship'] as Map)['id'] as String,
                                  ),
                        ),
                        if (item != _searchResults.last) const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '待处理申请',
                subtitle: incomingRequests.isEmpty ? '当前没有收到新的申请' : '可直接在这里通过申请',
                child: incomingRequests.isEmpty
                    ? const EmptyState(
                        title: '没有待处理申请',
                        description: '当别人添加你时，这里会出现可通过的请求。',
                      )
                    : Column(
                        children: [
                          for (final friend in incomingRequests) ...[
                            _FriendRow(
                              friend: friend,
                              onAccept: () => _acceptFriendRequest(friend.friendshipId),
                            ),
                            if (friend != incomingRequests.last) const SizedBox(height: 8),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '快速生成测试好友',
                subtitle: '用于单机调试整条链路，不替代真实好友系统',
                child: Column(
                  children: [
                    TextField(
                      controller: _demoFriendNameController,
                      decoration: const InputDecoration(labelText: '测试好友用户名'),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _loading ? null : _createDemoFriendFlow,
                        child: Text(_loading ? '处理中...' : '生成测试好友'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '关系列表',
                subtitle: '已建立关系和待处理申请都会显示在这里',
                child: _state.friends.isEmpty
                    ? const EmptyState(
                        title: '还没有好友关系',
                        description: '先搜索已有用户，或使用测试入口生成一个好友。',
                      )
                    : Column(
                        children: [
                          for (final friend in _state.friends) ...[
                            _FriendRow(
                              friend: friend,
                              onAccept: friend.status == 'pending' && friend.direction == 'incoming'
                                  ? () => _acceptFriendRequest(friend.friendshipId)
                                  : null,
                            ),
                            if (friend != _state.friends.last) const SizedBox(height: 8),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(title: '状态', child: StatusText(_status)),
            ],
          ),
        );
      },
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.item,
    required this.onSendRequest,
    this.onAccept,
  });

  final Map<String, dynamic> item;
  final VoidCallback onSendRequest;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final user = Map<String, dynamic>.from(item['user'] as Map);
    final agentRaw = item['agent'];
    final agent = agentRaw is Map ? Map<String, dynamic>.from(agentRaw) : null;
    final relationshipStatus = item['relationship_status'] as String? ?? 'none';
    final direction = item['direction'] as String? ?? 'none';

    late final Widget action;
    if (relationshipStatus == 'accepted') {
      action = const Text('已是好友', style: TextStyle(color: NotionPalette.textSecondary));
    } else if (relationshipStatus == 'pending' && direction == 'outgoing') {
      action = const Text('已发送', style: TextStyle(color: NotionPalette.textSecondary));
    } else if (relationshipStatus == 'pending' && direction == 'incoming' && onAccept != null) {
      action = TextButton(onPressed: onAccept, child: const Text('通过申请'));
    } else {
      action = FilledButton.tonal(onPressed: onSendRequest, child: const Text('加好友'));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NotionPalette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NotionPalette.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              (user['name'] as String? ?? 'U').characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['name'] as String? ?? '未命名用户', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  agent == null
                      ? '对方还没有公开智能体'
                      : List<String>.from((agent['domain_tags'] as List?) ?? const []).join(' · ').ifEmpty('暂无场景标签'),
                  style: const TextStyle(color: NotionPalette.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    this.onAccept,
  });

  final FriendListItem friend;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NotionPalette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NotionPalette.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              friend.name.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friend.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  friend.domainTags.isEmpty ? '暂无场景标签' : friend.domainTags.join(' · '),
                  style: const TextStyle(color: NotionPalette.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  friendshipDirectionText(friend.direction),
                  style: const TextStyle(color: NotionPalette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (onAccept != null)
            TextButton(onPressed: onAccept, child: const Text('通过'))
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: NotionPalette.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(friendshipStatusText(friend.status)),
            ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
