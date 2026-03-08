import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_models.dart';
import '../services/api_client.dart';
import '../services/session_state.dart';
import '../theme/notion_theme.dart';
import '../widgets/notion_widgets.dart';

class AgentSetupScreen extends StatefulWidget {
  const AgentSetupScreen({super.key});

  @override
  State<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends State<AgentSetupScreen> {
  final _api = ApiClient();
  final _state = SessionState.instance;
  final _nameController = TextEditingController(text: '会议发起人');
  final _identityController = TextEditingController(text: '生活里靠谱、做事有分寸的朋友');
  final _decisionController = TextEditingController(text: '稳妥权衡');
  final _riskController = TextEditingController(text: '平衡取舍');
  final _toneController = TextEditingController(text: '直接清晰');
  final _helperController = TextEditingController(text: '军师伙伴');
  final _principlesController = TextEditingController(text: '先判断现实成本，再给可执行方案。');
  final _avoidancesController = TextEditingController(text: '不要替我做最终决定；不要空泛鸡汤。');
  final _responseController = TextEditingController(text: '先给结论，再给 1 到 2 个可选方案。');
  final _customPromptController = TextEditingController();
  final _publicNameController = TextEditingController();
  final _publicDescriptionController = TextEditingController();

  final Set<String> _sceneTags = <String>{'生活决策', '工作协作'};
  final Map<String, int> _assessmentAnswers = <String, int>{};
  Map<String, double> _assessmentScores = <String, double>{};
  List<Map<String, dynamic>> _assessmentQuestions = const [];
  bool _loading = false;
  bool _assessmentLoading = false;
  bool _sharingLoading = false;
  bool _isPublic = false;
  String? _assessmentSummary;
  String _status = '先做一轮人格测评，系统会帮你生成第一版分身。';

  static const _sceneOptions = [
    '生活决策',
    '工作协作',
    '关系沟通',
    '学习成长',
    '创作表达',
    '游戏开黑',
    '旅行出行',
    '情绪陪伴',
  ];

  static const _decisionOptions = [
    '直觉快决',
    '结构拆解',
    '稳妥权衡',
    '脑洞探索',
    '胜率优先',
  ];

  static const _riskOptions = [
    '先稳住',
    '平衡取舍',
    '敢冲一把',
  ];

  static const _toneOptions = [
    '直接清晰',
    '温柔共情',
    '幽默松弛',
    '理性克制',
    '热血带队',
  ];

  static const _helperOptions = [
    '军师伙伴',
    '陪聊安抚',
    '吐槽搭子',
    '游戏队友',
    '主持统筹',
    '热场搭子',
  ];

  static const _dimensionLabels = <String, String>{
    'openness': '开放性',
    'conscientiousness': '尽责性',
    'extraversion': '外向性',
    'agreeableness': '宜人性',
    'neuroticism': '情绪敏感度',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateFromState();
      _syncExistingAgent();
      _loadAssessmentTemplate();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _identityController.dispose();
    _decisionController.dispose();
    _riskController.dispose();
    _toneController.dispose();
    _helperController.dispose();
    _principlesController.dispose();
    _avoidancesController.dispose();
    _responseController.dispose();
    _customPromptController.dispose();
    _publicNameController.dispose();
    _publicDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadAssessmentTemplate() async {
    setState(() => _assessmentLoading = true);
    try {
      final template = await _api.assessmentTemplate();
      final questions = List<dynamic>.from(template['questions'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        _assessmentQuestions = questions
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = '人格测评题加载失败，可以先手动填写分身设定。');
    } finally {
      if (mounted) {
        setState(() => _assessmentLoading = false);
      }
    }
  }

  void _hydrateFromState() {
    if (_state.currentUserName != null) {
      _nameController.text = _state.currentUserName!;
    }
    final profile = _state.currentAgentProfile;
    if (profile == null) return;

    final persona = Map<String, dynamic>.from((profile['persona_json'] as Map?) ?? const {});
    _identityController.text =
        persona['identity_brief'] as String? ?? persona['background'] as String? ?? _identityController.text;
    _decisionController.text =
        persona['decision_style'] as String? ?? persona['thinking_style'] as String? ?? _decisionController.text;
    _riskController.text = persona['risk_preference'] as String? ?? _riskController.text;
    _toneController.text = persona['communication_tone'] as String? ?? _toneController.text;
    _helperController.text = persona['helper_style'] as String? ?? _helperController.text;
    _principlesController.text = persona['principles'] as String? ?? _principlesController.text;
    _avoidancesController.text = persona['avoidances'] as String? ?? _avoidancesController.text;
    _responseController.text = persona['response_preferences'] as String? ?? _responseController.text;
    _customPromptController.text = persona['custom_prompt'] as String? ?? _customPromptController.text;
    _assessmentSummary = persona['assessment_summary'] as String?;

    final scores = Map<String, dynamic>.from((persona['assessment_scores'] as Map?) ?? const {});
    _assessmentScores = scores.map(
      (key, value) => MapEntry(key, (value as num).toDouble()),
    );

    final scenes = List<String>.from(
      (persona['scene_tags'] as List?) ?? (profile['domain_tags'] as List?) ?? const [],
    );
    if (scenes.isNotEmpty) {
      _sceneTags
        ..clear()
        ..addAll(scenes);
    }

    _isPublic = profile['is_public'] as bool? ?? false;
    _publicNameController.text =
        profile['public_name'] as String? ?? _publicNameController.text.ifEmpty(_identityController.text);
    _publicDescriptionController.text =
        profile['public_description'] as String? ?? _publicDescriptionController.text.ifEmpty(_assessmentSummary ?? '');
  }

  Future<void> _syncExistingAgent() async {
    if (_state.currentUserId == null || _state.currentAgentId != null) {
      return;
    }
    try {
      final agents = await _api.listAgents(_state.currentUserId!);
      if (agents.isNotEmpty) {
        _state.setCurrentAgent(Map<String, dynamic>.from(agents.first as Map));
        _hydrateFromState();
        if (mounted) {
          setState(() {});
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = '智能体信息同步失败，请稍后重试');
      }
    }
  }

  Future<void> _applyAssessmentDraft() async {
    if (_assessmentQuestions.isEmpty) {
      setState(() => _status = '人格测评题还没加载完成');
      return;
    }
    if (_assessmentAnswers.length != _assessmentQuestions.length) {
      setState(() => _status = '请先完成全部测评题再生成草案');
      return;
    }

    setState(() {
      _assessmentLoading = true;
      _status = '正在根据测评结果生成分身草案...';
    });

    try {
      final draft = await _api.assessmentDraft(
        _assessmentQuestions
            .map((question) => {
                  'question_id': question['id'],
                  'score': _assessmentAnswers[question['id']]!,
                })
            .toList(growable: false),
      );

      _identityController.text = draft['background'] as String? ?? _identityController.text;
      _decisionController.text = draft['thinking_style'] as String? ?? _decisionController.text;
      _riskController.text = draft['risk_preference'] as String? ?? _riskController.text;
      _toneController.text = draft['communication_tone'] as String? ?? _toneController.text;
      _helperController.text = draft['helper_style'] as String? ?? _helperController.text;
      _principlesController.text = draft['principles'] as String? ?? _principlesController.text;
      _avoidancesController.text = draft['avoidances'] as String? ?? _avoidancesController.text;
      _responseController.text =
          draft['response_preferences'] as String? ?? _responseController.text;
      _customPromptController.text = draft['custom_prompt'] as String? ?? _customPromptController.text;

      final sceneTags = List<String>.from(draft['scene_tags'] as List? ?? const []);
      _sceneTags
        ..clear()
        ..addAll(sceneTags);

      final scoreMap = Map<String, dynamic>.from((draft['assessment_scores'] as Map?) ?? const {});
      _assessmentScores = scoreMap.map((key, value) => MapEntry(key, (value as num).toDouble()));
      _assessmentSummary = draft['assessment_summary'] as String?;
      _publicNameController.text = _publicNameController.text.ifEmpty(_identityController.text);
      _publicDescriptionController.text = _publicDescriptionController.text.ifEmpty(_assessmentSummary ?? '');

      setState(() => _status = '测评草案已生成，你可以继续微调再创建分身');
    } on DioException catch (e) {
      setState(() => _status = '测评失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}');
    } catch (e) {
      setState(() => _status = '测评失败: $e');
    } finally {
      if (mounted) {
        setState(() => _assessmentLoading = false);
      }
    }
  }

  List<String> _buildCalibrationTurns() {
    final turns = <String>[
      '我的常见场景：${_sceneTags.join('、')}',
      '我的决策风格：${_decisionController.text.trim()}',
      '我的互动方式：${_helperController.text.trim()}，说话风格：${_toneController.text.trim()}',
      '我的风险取向：${_riskController.text.trim()}',
    ];

    if (_assessmentSummary?.trim().isNotEmpty ?? false) {
      turns.add('测评结论：${_assessmentSummary!.trim()}');
    }
    if (_principlesController.text.trim().isNotEmpty) {
      turns.add('行事准则：${_principlesController.text.trim()}');
    }
    if (_avoidancesController.text.trim().isNotEmpty) {
      turns.add('禁止事项：${_avoidancesController.text.trim()}');
    }
    if (_responseController.text.trim().isNotEmpty) {
      turns.add('希望你这样帮助我：${_responseController.text.trim()}');
    }
    if (_customPromptController.text.trim().isNotEmpty) {
      turns.add('额外设定：${_customPromptController.text.trim()}');
    }
    return turns.take(8).toList();
  }

  List<String> _buildStyleTags() {
    return {
      _helperController.text.trim(),
      _toneController.text.trim(),
      _decisionController.text.trim(),
    }.where((item) => item.isNotEmpty).toList();
  }

  Future<void> _createFlow() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _status = '请先填写用户名');
      return;
    }
    if (_identityController.text.trim().isEmpty) {
      setState(() => _status = '请描述一下这个分身最像你的地方');
      return;
    }
    if (_sceneTags.isEmpty) {
      setState(() => _status = '至少选择一个常见场景');
      return;
    }

    setState(() {
      _loading = true;
      _status = _state.currentUserId == null ? '正在创建用户...' : '正在更新分身设定...';
    });

    try {
      if (_state.currentUserId == null) {
        final user = await _api.registerUser(_nameController.text.trim());
        _state.setCurrentUser(user);
        await _loadAssessmentTemplate();
      } else {
        final updatedUser = await _api.updateUser(
          userId: _state.currentUserId!,
          name: _nameController.text.trim(),
          timezone: _state.currentTimezone ?? 'Asia/Shanghai',
        );
        _state.setCurrentUser(updatedUser);
      }

      final sceneTags = _sceneTags.toList();
      final payload = AgentBootstrapPayload(
        ownerUserId: _state.currentUserId!,
        background: _identityController.text.trim(),
        thinkingStyle: _decisionController.text.trim(),
        riskPreference: _riskController.text.trim(),
        communicationTone: _toneController.text.trim(),
        helperStyle: _helperController.text.trim(),
        sceneTags: sceneTags,
        principles: _principlesController.text.trim(),
        avoidances: _avoidancesController.text.trim(),
        responsePreferences: _responseController.text.trim(),
        customPrompt: _customPromptController.text.trim(),
        assessmentScores: _assessmentScores,
        assessmentSummary: _assessmentSummary ?? '',
        styleTags: _buildStyleTags(),
        domainTags: sceneTags,
      );

      setState(() => _status = _state.currentAgentId == null ? '正在初始化分身...' : '正在更新分身画像...');
      final agent = _state.currentAgentId == null
          ? await _api.bootstrapAgent(payload)
          : await _api.updateAgent(
              agentId: _state.currentAgentId!,
              payload: payload,
            );
      _state.setCurrentAgent(agent);
      _hydrateFromState();

      setState(() => _status = '正在根据你的设定做个性校准...');
      final calibrated = await _api.calibrateAgent(_state.currentAgentId!, _buildCalibrationTurns());
      _state.setCurrentAgent(calibrated);
      _hydrateFromState();

      setState(
        () => _status = _state.friends.isEmpty ? '分身已就绪：下一步建议添加好友或搜索公共分身并拉会' : '分身已更新并完成校准',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final data = e.response?.data;
      setState(() => _status = '失败(type=${e.type}, code=$code): ${e.message}; data=$data');
    } catch (e) {
      setState(() => _status = '失败: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveSharing() async {
    if (_state.currentAgentId == null) {
      setState(() => _status = '请先创建分身，再配置公共分享');
      return;
    }

    setState(() {
      _sharingLoading = true;
      _status = _isPublic ? '正在发布到公共分身库...' : '正在更新分享状态...';
    });

    try {
      final updated = await _api.updateAgentSharing(
        agentId: _state.currentAgentId!,
        isPublic: _isPublic,
        publicName: _publicNameController.text.trim(),
        publicDescription: _publicDescriptionController.text.trim(),
      );
      _state.setCurrentAgent(updated);
      _hydrateFromState();
      setState(() => _status = _isPublic ? '你的分身已进入公共库，可被其他注册用户搜索邀请' : '已取消公共分享');
    } on DioException catch (e) {
      setState(() => _status = '分享设置失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}');
    } catch (e) {
      setState(() => _status = '分享设置失败: $e');
    } finally {
      if (mounted) {
        setState(() => _sharingLoading = false);
      }
    }
  }

  String _personaPreview() {
    final scenes = _sceneTags.join(' / ');
    return '这是一个更像你在“$scenes”场景里的分身。它会以“${_helperController.text.trim()}”的方式出现，'
        '做决定偏“${_decisionController.text.trim()}”，整体表达更接近“${_toneController.text.trim()}”。';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final profile = _state.currentAgentProfile;
        final persona = profile == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from((profile['persona_json'] as Map?) ?? const {});
        final notes = List<String>.from(persona['calibration_notes'] as List? ?? const []);
        final rawDomainTags = profile == null ? null : profile['domain_tags'];
        final currentScenes = List<String>.from(
          (persona['scene_tags'] as List?) ?? (rawDomainTags as List?) ?? const [],
        );

        return Scaffold(
          appBar: AppBar(title: const Text('智能体')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NotionSectionCard(
                title: '五维人格测评',
                subtitle: '基于五大人格框架的入门问卷，先生成第一版分身草案，再继续微调。',
                child: _assessmentLoading && _assessmentQuestions.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: NotionPalette.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: NotionPalette.border),
                            ),
                            child: const Text(
                              '评分说明：1 非常不像我，3 说不准，5 非常像我。',
                              style: TextStyle(color: NotionPalette.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_assessmentQuestions.isEmpty)
                            const EmptyState(
                              title: '测评题暂未加载',
                              description: '你也可以先手动填写下方分身卡，后续再补做测评。',
                            )
                          else
                            for (final question in _assessmentQuestions) ...[
                              _AssessmentQuestionCard(
                                question: question,
                                selectedScore: _assessmentAnswers[question['id'] as String],
                                onChanged: (score) {
                                  setState(() => _assessmentAnswers[question['id'] as String] = score);
                                },
                              ),
                              if (question != _assessmentQuestions.last) const SizedBox(height: 10),
                            ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonal(
                              onPressed: _assessmentLoading ? null : _applyAssessmentDraft,
                              child: Text(_assessmentLoading ? '生成中...' : '根据测评生成草案'),
                            ),
                          ),
                          if (_assessmentSummary?.isNotEmpty ?? false) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: NotionPalette.border),
                              ),
                              child: Text(_assessmentSummary!),
                            ),
                          ],
                          if (_assessmentScores.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _AssessmentScoreBoard(
                              scores: _assessmentScores,
                              labels: _dimensionLabels,
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '创建你的分身卡',
                subtitle: '它可以是生活军师、游戏搭子、关系翻译器，也可以在工作里帮你判断。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: '用户名'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _identityController,
                      decoration: const InputDecoration(
                        labelText: '这个分身最像你的地方',
                        hintText: '例如：靠谱但不说教，关键时刻会帮我稳住局面',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _MultiSelectOptionGroup(
                      label: '常见场景',
                      options: _sceneOptions,
                      selected: _sceneTags,
                      onChanged: (next) => setState(() => _sceneTags
                        ..clear()
                        ..addAll(next)),
                    ),
                    const SizedBox(height: 10),
                    _OptionGroup(label: '决策风格', controller: _decisionController, options: _decisionOptions),
                    const SizedBox(height: 10),
                    _OptionGroup(label: '风险取向', controller: _riskController, options: _riskOptions),
                    const SizedBox(height: 10),
                    _OptionGroup(label: '说话气质', controller: _toneController, options: _toneOptions),
                    const SizedBox(height: 10),
                    _OptionGroup(label: '出现方式', controller: _helperController, options: _helperOptions),
                    const SizedBox(height: 12),
                    _LongTextField(
                      label: '行事准则',
                      hintText: '例如：先判断现实成本；不轻易替别人做最终决定；尽量给可执行步骤。',
                      controller: _principlesController,
                    ),
                    const SizedBox(height: 10),
                    _LongTextField(
                      label: '禁止事项',
                      hintText: '例如：不要剧透；不要道德绑架；不要强推极端方案。',
                      controller: _avoidancesController,
                    ),
                    const SizedBox(height: 10),
                    _LongTextField(
                      label: '希望它怎么帮助你',
                      hintText: '例如：先给结论，再给选项；情绪不好时先安抚；游戏时多报点少废话。',
                      controller: _responseController,
                    ),
                    const SizedBox(height: 10),
                    _LongTextField(
                      label: '额外设定（可选）',
                      hintText: '可以写口头禅、边界感、世界观、梗，或你想补充的 prompt。',
                      controller: _customPromptController,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NotionPalette.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NotionPalette.border),
                      ),
                      child: Text(
                        _personaPreview(),
                        style: const TextStyle(color: NotionPalette.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _createFlow,
                        child: Text(
                          _loading ? '处理中...' : (_state.currentAgentId == null ? '创建并校准分身' : '更新并重新校准分身'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (profile != null)
                NotionSectionCard(
                  title: '当前分身画像',
                  subtitle: '这些设定会参与会议发言生成，而不只是展示。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persona['identity_brief'] as String? ?? persona['background'] as String? ?? '暂无设定',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in currentScenes)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: NotionPalette.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: NotionPalette.border),
                              ),
                              child: Text(tag),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${persona['helper_style'] ?? '-'} · ${persona['decision_style'] ?? persona['thinking_style'] ?? '-'} · ${persona['communication_tone'] ?? '-'}',
                        style: const TextStyle(color: NotionPalette.textSecondary),
                      ),
                      if ((_assessmentSummary ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('测评结论', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_assessmentSummary!),
                      ],
                      if (_assessmentScores.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('人格维度', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        _AssessmentScoreBoard(
                          scores: _assessmentScores,
                          labels: _dimensionLabels,
                        ),
                      ],
                      if ((persona['principles'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        const Text('行事准则', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(persona['principles'] as String),
                      ],
                      if ((persona['avoidances'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        const Text('禁止事项', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(persona['avoidances'] as String),
                      ],
                      if ((persona['response_preferences'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        const Text('帮助偏好', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(persona['response_preferences'] as String),
                      ],
                      if ((persona['custom_prompt'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        const Text('额外设定', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(persona['custom_prompt'] as String),
                      ],
                      const SizedBox(height: 12),
                      Text('校准轮次: ${notes.length}', style: const TextStyle(color: NotionPalette.textSecondary)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '公共分身库',
                subtitle: '公开后，所有注册用户都可以搜索并邀请你的分身参会。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      value: _isPublic,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('公开这个分身'),
                      subtitle: const Text('公开的是分身画像，不会暴露你的私密资料和完整训练细节'),
                      onChanged: (value) => setState(() => _isPublic = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _publicNameController,
                      decoration: const InputDecoration(labelText: '公共展示名称'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _publicDescriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '公共简介',
                        hintText: '例如：擅长生活决策、关系沟通和复杂局面下的稳态建议。',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _sharingLoading ? null : _saveSharing,
                        child: Text(_sharingLoading ? '保存中...' : '保存公共分享设置'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '状态与错误',
                action: IconButton(
                  tooltip: '复制状态',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _status));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制状态信息')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                ),
                child: SelectableText(_status),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AssessmentScoreBoard extends StatelessWidget {
  const _AssessmentScoreBoard({
    required this.scores,
    required this.labels,
  });

  final Map<String, double> scores;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final entries = scores.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));

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
          const Text(
            '大五人格维度',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final entry in entries) ...[
            _AssessmentScoreRow(
              label: labels[entry.key] ?? entry.key,
              score: entry.value,
            ),
            if (entry != entries.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _AssessmentScoreRow extends StatelessWidget {
  const _AssessmentScoreRow({
    required this.label,
    required this.score,
  });

  final String label;
  final double score;

  @override
  Widget build(BuildContext context) {
    final normalized = (score / 5).clamp(0, 1).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              score.toStringAsFixed(1),
              style: const TextStyle(color: NotionPalette.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: normalized,
            minHeight: 8,
            backgroundColor: NotionPalette.surface,
            valueColor: const AlwaysStoppedAnimation<Color>(NotionPalette.accent),
          ),
        ),
      ],
    );
  }
}

class _AssessmentQuestionCard extends StatelessWidget {
  const _AssessmentQuestionCard({
    required this.question,
    required this.selectedScore,
    required this.onChanged,
  });

  final Map<String, dynamic> question;
  final int? selectedScore;
  final ValueChanged<int> onChanged;

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
          Text(
            question['prompt'] as String? ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(
              5,
              (index) {
                final score = index + 1;
                return ChoiceChip(
                  label: Text('$score'),
                  selected: selectedScore == score,
                  onSelected: (_) => onChanged(score),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({
    required this.label,
    required this.controller,
    required this.options,
  });

  final String label;
  final TextEditingController controller;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final current = value.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in options)
                  ChoiceChip(
                    label: Text(option),
                    selected: option == current,
                    onSelected: (_) => controller.text = option,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: '$label（可自定义）'),
            ),
          ],
        );
      },
    );
  }
}

class _MultiSelectOptionGroup extends StatelessWidget {
  const _MultiSelectOptionGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(option),
                selected: selected.contains(option),
                onSelected: (value) {
                  final next = Set<String>.from(selected);
                  if (value) {
                    next.add(option);
                  } else {
                    next.remove(option);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _LongTextField extends StatelessWidget {
  const _LongTextField({
    required this.label,
    required this.hintText,
    required this.controller,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        alignLabelWithHint: true,
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
