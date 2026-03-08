import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/meeting_models.dart';
import '../services/api_client.dart';
import '../services/session_state.dart';
import '../theme/notion_theme.dart';
import '../widgets/notion_widgets.dart';
import '../widgets/summary_card.dart';

class MeetingLiveTurn {
  const MeetingLiveTurn({
    required this.roundIndex,
    required this.speakerId,
    required this.content,
  });

  final int roundIndex;
  final String speakerId;
  final String content;
}

class MeetingScreen extends StatefulWidget {
  const MeetingScreen({super.key});

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final _api = ApiClient();
  final _state = SessionState.instance;
  final _topicController = TextEditingController(text: '如何提升每周例会效率');
  final _publicSearchController = TextEditingController();

  MeetingMode _mode = MeetingMode.moderated;
  final Set<String> _selectedFriendAgentIds = <String>{};
  final Set<String> _selectedPublicAgentIds = <String>{};
  final Map<String, Map<String, dynamic>> _publicAgentCatalog = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> _publicSearchResults = const [];
  final List<MeetingLiveTurn> _liveTurns = <MeetingLiveTurn>[];

  StreamSubscription<MeetingEvent>? _eventSubscription;
  bool _loading = false;
  bool _isStreaming = false;
  bool _publicSearching = false;
  String _status = '准备发起会议';

  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMeetings());
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _topicController.dispose();
    _publicSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshMeetings() async {
    final creatorId = _state.currentUserId;
    if (creatorId == null) return;
    try {
      final items = await _api.listMeetings(creatorId);
      _state.replaceMeetings(items);
      _pruneSelectedFriendAgents();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '会议历史刷新失败: $e');
    }
  }

  void _pruneSelectedFriendAgents() {
    final validAgentIds = _state.friends
        .map((friend) => friend.friendAgentId)
        .whereType<String>()
        .toSet();
    _selectedFriendAgentIds.removeWhere((agentId) => !validAgentIds.contains(agentId));
  }

  void _toggleFriendAgent(String agentId) {
    setState(() {
      if (_selectedFriendAgentIds.contains(agentId)) {
        _selectedFriendAgentIds.remove(agentId);
      } else {
        _selectedFriendAgentIds.add(agentId);
      }
    });
  }

  Future<void> _searchPublicLibrary() async {
    setState(() {
      _publicSearching = true;
      _status = '正在搜索公共分身库...';
    });

    try {
      final results = await _api.searchPublicAgents(_publicSearchController.text.trim());
      final normalized = results.map((item) => Map<String, dynamic>.from(item as Map)).toList();
      for (final item in normalized) {
        final agent = Map<String, dynamic>.from(item['agent'] as Map);
        _publicAgentCatalog[agent['id'] as String] = item;
      }
      setState(() {
        _publicSearchResults = normalized;
        _status = normalized.isEmpty ? '公共分身库里没有找到匹配结果' : '已更新公共分身搜索结果';
      });
    } on DioException catch (e) {
      setState(() => _status = '公共库搜索失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}');
    } catch (e) {
      setState(() => _status = '公共库搜索失败: $e');
    } finally {
      if (mounted) {
        setState(() => _publicSearching = false);
      }
    }
  }

  void _togglePublicAgent(String agentId, Map<String, dynamic> item) {
    setState(() {
      _publicAgentCatalog[agentId] = item;
      if (_selectedPublicAgentIds.contains(agentId)) {
        _selectedPublicAgentIds.remove(agentId);
      } else {
        _selectedPublicAgentIds.add(agentId);
      }
    });
  }

  Future<void> _cancelLiveStream() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Future<void> _listenToMeetingEvents(String meetingId) async {
    await _cancelLiveStream();
    final completer = Completer<void>();

    _eventSubscription = _api.streamMeetingEvents(meetingId).listen(
      (event) {
        if (!mounted) return;

        switch (event.type) {
          case 'turn':
            setState(() {
              _liveTurns.add(
                MeetingLiveTurn(
                  roundIndex: event.payload['round_index'] as int? ?? _liveTurns.length + 1,
                  speakerId: event.payload['speaker_id'] as String? ?? 'unknown',
                  content: event.payload['content'] as String? ?? '',
                ),
              );
              _status = '会议进行中，已接收第 ${_liveTurns.length} 轮发言';
            });
            break;
          case 'summary':
            setState(() {
              _summary = event.payload;
              _status = '主持总结已生成';
            });
            break;
          case 'done':
            setState(() {
              _isStreaming = false;
              _status = _state.hasAiConfig ? '会议完成（流式展示已结束）' : '会议完成（本地回退策略）';
            });
            if (!completer.isCompleted) {
              completer.complete();
            }
            break;
          default:
            break;
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isStreaming = false;
          _status = '流式连接失败: $error';
        });
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  Future<void> _runMeeting() async {
    final creatorId = _state.currentUserId;
    final ownerAgent = _state.currentAgentId;
    final selectedFriendAgents = _state.friends
        .where((friend) => friend.friendAgentId != null && _selectedFriendAgentIds.contains(friend.friendAgentId))
        .map((friend) => friend.friendAgentId!)
        .toList();
    final selectedPublicAgents = _selectedPublicAgentIds
        .where((agentId) => !selectedFriendAgents.contains(agentId))
        .toList(growable: false);

    if (creatorId == null || ownerAgent == null) {
      setState(() => _status = '请先完成「智能体」页创建流程');
      return;
    }

    setState(() {
      _loading = true;
      _isStreaming = true;
      _status = '创建会议中...';
      _summary = null;
      _liveTurns.clear();
    });

    try {
      final participants = <MeetingParticipantInput>[
        MeetingParticipantInput(
          participantType: 'agent',
          participantId: ownerAgent,
          role: '主策划',
        ),
      ];
      for (final friendAgent in selectedFriendAgents) {
        participants.add(
          MeetingParticipantInput(
            participantType: 'agent',
            participantId: friendAgent,
            role: '挑战者',
          ),
        );
      }
      for (final publicAgent in selectedPublicAgents) {
        final item = _publicAgentCatalog[publicAgent];
        final agent = item == null ? null : Map<String, dynamic>.from(item['agent'] as Map);
        final owner = item == null ? null : Map<String, dynamic>.from(item['owner'] as Map);
        participants.add(
          MeetingParticipantInput(
            participantType: 'agent',
            participantId: publicAgent,
            role: agent?['public_name'] as String? ?? '${owner?['name'] ?? '公共用户'} 的公开分身',
          ),
        );
      }

      final created = await _api.createMeeting(
        creatorId: creatorId,
        topic: _topicController.text.trim(),
        mode: _mode,
        participants: participants,
      );

      final meeting = Map<String, dynamic>.from(created['meeting'] as Map);
      final meetingId = meeting['id'] as String;
      final streamFuture = _listenToMeetingEvents(meetingId);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      setState(() => _status = '会议进行中，正在接收流式发言...');

      final order = <String>[
        ...selectedFriendAgents,
        ...selectedPublicAgents,
        ownerAgent,
      ];
      await _api.startMeetingWithAiConfig(
        meetingId,
        order: _mode == MeetingMode.manual ? order : null,
        aiConfig: _state.aiConfigPayload(),
      );

      await streamFuture.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('等待流式结果超时'),
      );

      _summary ??= await _api.summary(meetingId);
      await _refreshMeetings();
    } on DioException catch (e) {
      await _cancelLiveStream();
      setState(() {
        _isStreaming = false;
        _status = '失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}';
      });
    } catch (e) {
      await _cancelLiveStream();
      setState(() {
        _isStreaming = false;
        _status = '失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _speakerLabel(String speakerId) {
    if (speakerId == 'moderator') return '主持人';
    if (speakerId == _state.currentAgentId) return '我的智能体';

    for (final friend in _state.friends) {
      if (friend.friendAgentId == speakerId) {
        return '${friend.name} 的智能体';
      }
    }
    final publicItem = _publicAgentCatalog[speakerId];
    if (publicItem != null) {
      final agent = Map<String, dynamic>.from(publicItem['agent'] as Map);
      final owner = Map<String, dynamic>.from(publicItem['owner'] as Map);
      return agent['public_name'] as String? ?? '${owner['name']} 的公开分身';
    }
    return speakerId;
  }

  String _speakerLabelFromParticipants(String speakerId, List<dynamic> participants) {
    if (speakerId == 'moderator') return '主持人';
    if (speakerId == _state.currentAgentId) return '我的智能体';

    for (final friend in _state.friends) {
      if (friend.friendAgentId == speakerId) {
        return '${friend.name} 的智能体';
      }
    }

    for (final raw in participants) {
      final participant = Map<String, dynamic>.from(raw as Map);
      if (participant['participant_id'] == speakerId) {
        return participant['role'] as String? ?? speakerId;
      }
    }
    final publicItem = _publicAgentCatalog[speakerId];
    if (publicItem != null) {
      final agent = Map<String, dynamic>.from(publicItem['agent'] as Map);
      return agent['public_name'] as String? ?? speakerId;
    }
    return speakerId;
  }

  Future<void> _openMeetingDetail(MeetingHistoryItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return FutureBuilder<Map<String, dynamic>>(
              future: _api.meetingDetail(item.meetingId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _DetailSheetShell(
                    title: item.topic,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return _DetailSheetShell(
                    title: item.topic,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: StatusText('会议详情加载失败: ${snapshot.error}'),
                    ),
                  );
                }

                final payload = snapshot.data!;
                final meeting = Map<String, dynamic>.from(payload['meeting'] as Map);
                final participants = List<dynamic>.from(payload['participants'] as List? ?? const []);
                final turns = List<dynamic>.from(payload['turns'] as List? ?? const []);
                final summaryRaw = payload['summary'];
                final summary = summaryRaw is Map ? Map<String, dynamic>.from(summaryRaw) : null;

                return _DetailSheetShell(
                  title: meeting['topic'] as String? ?? item.topic,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '${meetingModeText(meeting['mode'] as String? ?? item.mode)} · ${meetingStatusText(meeting['status'] as String? ?? item.status)}',
                        style: const TextStyle(color: NotionPalette.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final raw in participants)
                            _ParticipantPill(
                              label: _speakerLabelFromParticipants(
                                (Map<String, dynamic>.from(raw as Map))['participant_id'] as String? ?? '',
                                participants,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (summary != null) ...[
                        Text(
                          '主持总结',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(summary['summary_text'] as String? ?? ''),
                        const SizedBox(height: 10),
                        SummaryCard(title: '结论', items: summary['key_points'] as List<dynamic>? ?? const []),
                        const SizedBox(height: 8),
                        SummaryCard(title: '分歧', items: summary['disagreements'] as List<dynamic>? ?? const []),
                        const SizedBox(height: 8),
                        SummaryCard(title: '下一步', items: summary['next_steps'] as List<dynamic>? ?? const []),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        '对话回放',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (turns.isEmpty)
                        const EmptyState(
                          title: '暂无对话记录',
                          description: '这场会议还没有沉淀 turn 数据。',
                        )
                      else
                        for (final raw in turns) ...[
                          _LiveTurnRow(
                            turn: MeetingLiveTurn(
                              roundIndex: (Map<String, dynamic>.from(raw as Map))['round_index'] as int? ?? 0,
                              speakerId: Map<String, dynamic>.from(raw)['speaker_id'] as String? ?? '',
                              content: Map<String, dynamic>.from(raw)['content'] as String? ?? '',
                            ),
                            speakerLabel: _speakerLabelFromParticipants(
                              Map<String, dynamic>.from(raw)['speaker_id'] as String? ?? '',
                              participants,
                            ),
                          ),
                          if (raw != turns.last) const SizedBox(height: 8),
                        ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('会议')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NotionSectionCard(
                title: '发起会议',
                subtitle: '支持主持编排、自由辩论、手动点名三种模式',
                action: IconButton(
                  tooltip: '刷新历史',
                  onPressed: _refreshMeetings,
                  icon: const Icon(Icons.refresh),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _topicController,
                      decoration: const InputDecoration(labelText: '会议问题'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<MeetingMode>(
                      initialValue: _mode,
                      decoration: const InputDecoration(labelText: '会议模式'),
                      items: MeetingMode.values
                          .map((mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(mode.label),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _mode = value);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _state.hasAiConfig
                            ? '当前会议将优先调用 ${_state.aiModel}'
                            : '未配置外部模型，将使用本地回退策略',
                        style: const TextStyle(color: NotionPalette.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _state.friends.isEmpty
                        ? const EmptyState(
                            title: '当前只有你的智能体可参会',
                            description: '去「好友」页建立关系后，这里会出现可邀请的智能体。',
                          )
                        : _ParticipantSelector(
                            friends: _state.friends,
                            selectedAgentIds: _selectedFriendAgentIds,
                            onToggle: _toggleFriendAgent,
                          ),
                    const SizedBox(height: 12),
                    _PublicLibrarySelector(
                      controller: _publicSearchController,
                      searching: _publicSearching,
                      results: _publicSearchResults,
                      selectedAgentIds: _selectedPublicAgentIds,
                      onSearch: _searchPublicLibrary,
                      onToggle: _togglePublicAgent,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _runMeeting,
                        child: Text(_loading ? '处理中...' : '发起并开始流式会议'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '实时对话',
                subtitle: _isStreaming ? '对话会逐条流入这里' : '发起会议后会显示逐轮发言',
                child: _liveTurns.isEmpty
                    ? (_isStreaming
                        ? const _StreamingPlaceholder()
                        : const EmptyState(
                            title: '暂无实时对话',
                            description: '发起一次会议后，这里会逐条展示智能体发言。',
                          ))
                    : Column(
                        children: [
                          for (final turn in _liveTurns) ...[
                            _LiveTurnRow(
                              turn: turn,
                              speakerLabel: _speakerLabel(turn.speakerId),
                            ),
                            if (turn != _liveTurns.last) const SizedBox(height: 8),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '会议历史',
                child: _state.meetings.isEmpty
                    ? const EmptyState(
                        title: '暂无会议历史',
                        description: '发起一次会议后，这里会沉淀总结和回看记录。',
                      )
                    : Column(
                        children: [
                          for (final meeting in _state.meetings) ...[
                            _MeetingHistoryRow(
                              item: meeting,
                              onOpenDetail: () => _openMeetingDetail(meeting),
                              onUseSummary: meeting.summaryText == null
                                  ? null
                                  : () {
                                      setState(() {
                                        _summary = {
                                          'summary_text': meeting.summaryText,
                                          'key_points': <String>[],
                                          'disagreements': <String>[],
                                          'next_steps': <String>[],
                                        };
                                        _status = '已从历史记录载入摘要';
                                      });
                                    },
                            ),
                            if (meeting != _state.meetings.last) const SizedBox(height: 8),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(title: '状态', child: StatusText(_status)),
              if (_summary != null) ...[
                const SizedBox(height: 12),
                NotionSectionCard(
                  title: '主持总结',
                  action: IconButton(
                    tooltip: '复制总结',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _summary!['summary_text']?.toString() ?? ''),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制会议总结')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_summary!['summary_text']?.toString() ?? ''),
                      const SizedBox(height: 10),
                      SummaryCard(title: '结论', items: _summary!['key_points'] as List<dynamic>),
                      const SizedBox(height: 8),
                      SummaryCard(title: '分歧', items: _summary!['disagreements'] as List<dynamic>),
                      const SizedBox(height: 8),
                      SummaryCard(title: '下一步', items: _summary!['next_steps'] as List<dynamic>),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ParticipantSelector extends StatelessWidget {
  const _ParticipantSelector({
    required this.friends,
    required this.selectedAgentIds,
    required this.onToggle,
  });

  final List<FriendListItem> friends;
  final Set<String> selectedAgentIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '选择参会智能体',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final friend in friends)
              FilterChip(
                label: Text(friend.name),
                selected: friend.friendAgentId != null && selectedAgentIds.contains(friend.friendAgentId),
                onSelected: friend.friendAgentId == null ? null : (_) => onToggle(friend.friendAgentId!),
              ),
          ],
        ),
      ],
    );
  }
}

class _PublicLibrarySelector extends StatelessWidget {
  const _PublicLibrarySelector({
    required this.controller,
    required this.searching,
    required this.results,
    required this.selectedAgentIds,
    required this.onSearch,
    required this.onToggle,
  });

  final TextEditingController controller;
  final bool searching;
  final List<Map<String, dynamic>> results;
  final Set<String> selectedAgentIds;
  final VoidCallback onSearch;
  final void Function(String agentId, Map<String, dynamic> item) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '公共分身库',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '搜索公共分身',
            hintText: '例如：军师、关系沟通、游戏开黑',
            prefixIcon: Icon(Icons.public),
          ),
          onSubmitted: (_) => onSearch(),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: searching ? null : onSearch,
            child: Text(searching ? '搜索中...' : '搜索公共分身'),
          ),
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final item in results) ...[
            _PublicAgentRow(
              item: item,
              selected: selectedAgentIds.contains(
                Map<String, dynamic>.from(item['agent'] as Map)['id'] as String,
              ),
              onToggle: () => onToggle(
                Map<String, dynamic>.from(item['agent'] as Map)['id'] as String,
                item,
              ),
            ),
            if (item != results.last) const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _PublicAgentRow extends StatelessWidget {
  const _PublicAgentRow({
    required this.item,
    required this.selected,
    required this.onToggle,
  });

  final Map<String, dynamic> item;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final owner = Map<String, dynamic>.from(item['owner'] as Map);
    final agent = Map<String, dynamic>.from(item['agent'] as Map);
    final identityBrief = item['identity_brief'] as String? ?? '';
    final assessmentSummary = item['assessment_summary'] as String? ?? '';
    final publicName = agent['public_name'] as String? ?? '${owner['name']} 的公开分身';
    final description = (agent['public_description'] as String?)?.trim();
    final domainTags = List<String>.from((agent['domain_tags'] as List?) ?? const []);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NotionPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(publicName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '来自 ${owner['name']}',
                      style: const TextStyle(color: NotionPalette.textSecondary),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onToggle,
                child: Text(selected ? '取消' : '邀请'),
              ),
            ],
          ),
          if ((description ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description!, style: const TextStyle(color: NotionPalette.textSecondary)),
          ] else if (assessmentSummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(assessmentSummary, style: const TextStyle(color: NotionPalette.textSecondary)),
          ] else if (identityBrief.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(identityBrief, style: const TextStyle(color: NotionPalette.textSecondary)),
          ],
          if (domainTags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in domainTags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: NotionPalette.surface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(tag),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StreamingPlaceholder extends StatelessWidget {
  const _StreamingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: NotionPalette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              '正在等待智能体开始发言...',
              style: TextStyle(color: NotionPalette.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSheetShell extends StatelessWidget {
  const _DetailSheetShell({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F8F6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: NotionPalette.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _ParticipantPill extends StatelessWidget {
  const _ParticipantPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: NotionPalette.border),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, color: NotionPalette.textSecondary),
      ),
    );
  }
}

class _LiveTurnRow extends StatelessWidget {
  const _LiveTurnRow({
    required this.turn,
    required this.speakerLabel,
  });

  final MeetingLiveTurn turn;
  final String speakerLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NotionPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${turn.roundIndex} 轮 · $speakerLabel',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: NotionPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(turn.content),
        ],
      ),
    );
  }
}

class _MeetingHistoryRow extends StatelessWidget {
  const _MeetingHistoryRow({
    required this.item,
    this.onOpenDetail,
    this.onUseSummary,
  });

  final MeetingHistoryItem item;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onUseSummary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NotionPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.topic, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NotionPalette.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(meetingModeText(item.mode)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${meetingStatusText(item.status)} · ${item.createdAt.replaceFirst('T', ' ').split('.').first}',
            style: const TextStyle(color: NotionPalette.textSecondary, fontSize: 13),
          ),
          if (item.summaryText != null) ...[
            const SizedBox(height: 8),
            Text(
              item.summaryText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: NotionPalette.textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (onOpenDetail != null)
                TextButton(onPressed: onOpenDetail, child: const Text('查看详情')),
              if (onUseSummary != null)
                TextButton(onPressed: onUseSummary, child: const Text('载入到当前视图')),
            ],
          ),
        ],
      ),
    );
  }
}
