import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/session_state.dart';
import '../theme/notion_theme.dart';
import '../widgets/notion_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiClient();
  final _state = SessionState.instance;
  late final TextEditingController _nameController;
  late final TextEditingController _serverBaseUrlController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  bool _obscureApiKey = true;
  double _temperature = 0.7;
  String _status = '可在这里维护你的账户和调试信息';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _state.currentUserName ?? '会议发起人');
    _serverBaseUrlController = TextEditingController(text: _state.serverBaseUrl);
    _baseUrlController = TextEditingController(text: _state.aiBaseUrl);
    _apiKeyController = TextEditingController(text: _state.aiApiKey);
    _modelController = TextEditingController(text: _state.aiModel);
    _temperature = _state.aiTemperature;
    _state.addListener(_syncNameField);
  }

  @override
  void dispose() {
    _state.removeListener(_syncNameField);
    _nameController.dispose();
    _serverBaseUrlController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _syncNameField() {
    final next = _state.currentUserName ?? '会议发起人';
    if (_nameController.text != next) {
      _nameController.text = next;
    }
    if (_baseUrlController.text != _state.aiBaseUrl) {
      _baseUrlController.text = _state.aiBaseUrl;
    }
    if (_serverBaseUrlController.text != _state.serverBaseUrl) {
      _serverBaseUrlController.text = _state.serverBaseUrl;
    }
    if (_apiKeyController.text != _state.aiApiKey) {
      _apiKeyController.text = _state.aiApiKey;
    }
    if (_modelController.text != _state.aiModel) {
      _modelController.text = _state.aiModel;
    }
    if ((_temperature - _state.aiTemperature).abs() > 0.001) {
      setState(() => _temperature = _state.aiTemperature);
    }
  }

  Future<void> _saveProfile() async {
    if (_state.currentUserId == null) {
      setState(() => _status = '请先到「智能体」页创建用户');
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      setState(() => _status = '显示名称不能为空');
      return;
    }
    try {
      final updated = await _api.updateUser(
        userId: _state.currentUserId!,
        name: _nameController.text.trim(),
        timezone: _state.currentTimezone ?? 'Asia/Shanghai',
      );
      _state.setCurrentUser(updated);
      setState(() => _status = '个人信息已更新');
    } on DioException catch (e) {
      setState(
        () => _status = '保存失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      setState(() => _status = '保存失败: $e');
    }
  }

  Future<void> _saveAiSettings() async {
    await _state.saveAiSettings(
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
      model: _modelController.text,
      temperature: _temperature,
    );
    setState(() => _status = 'AI 配置已保存');
  }

  Future<void> _saveServerSettings() async {
    final value = _serverBaseUrlController.text.trim();
    if (value.isEmpty) {
      setState(() => _status = '服务地址不能为空');
      return;
    }
    await _state.saveServerBaseUrl(value);
    setState(() => _status = '服务地址已保存');
  }

  Future<void> _testServerSettings() async {
    final value = _serverBaseUrlController.text.trim();
    if (value.isEmpty) {
      setState(() => _status = '请先填写服务地址');
      return;
    }
    try {
      await _state.saveServerBaseUrl(value);
      final result = await _api.health();
      setState(() => _status = '服务连接成功: ${result['status']}');
    } on DioException catch (e) {
      setState(
        () => _status = '服务连接失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      setState(() => _status = '服务连接失败: $e');
    }
  }

  Future<void> _clearAiSettings() async {
    await _state.clearAiSettings();
    _baseUrlController.clear();
    _apiKeyController.clear();
    _modelController.clear();
    setState(() {
      _temperature = 0.7;
      _status = 'AI 配置已清空，会议将使用本地回退策略';
    });
  }

  Future<void> _testAiSettings() async {
    final payload = {
      'base_url': _baseUrlController.text.trim(),
      'api_key': _apiKeyController.text.trim(),
      'model': _modelController.text.trim(),
      'temperature': _temperature,
    };
    if (payload.values.any((value) => value is String && value.isEmpty)) {
      setState(() => _status = '请先完整填写接口地址、访问密钥和模型名称');
      return;
    }
    try {
      final result = await _api.testAiConnection(payload);
      setState(() => _status = 'AI 连接测试成功: ${result['message']}');
    } on DioException catch (e) {
      setState(
        () => _status = 'AI 连接测试失败(code=${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    } catch (e) {
      setState(() => _status = 'AI 连接测试失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        final uid = _state.currentUserId ?? '未创建';
        final aid = _state.currentAgentId ?? '未创建';
        final friendCount = _state.friends.length;
        final meetingCount = _state.meetings.length;

        return Scaffold(
          appBar: AppBar(title: const Text('我的')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              NotionSectionCard(
                title: '账户与订阅',
                subtitle: 'MVP 阶段默认免费版',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: '显示名称'),
                    ),
                    const SizedBox(height: 10),
                    const Text('计划: 免费版', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      '时区: ${_state.currentTimezone ?? 'Asia/Shanghai'}',
                      style: const TextStyle(color: NotionPalette.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: _saveProfile, child: const Text('保存个人信息')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '使用统计',
                child: Row(
                  children: [
                    Expanded(child: MetricTile(label: '好友', value: '$friendCount')),
                    const SizedBox(width: 10),
                    Expanded(child: MetricTile(label: '会议', value: '$meetingCount')),
                    const SizedBox(width: 10),
                    Expanded(child: MetricTile(label: '智能体', value: _state.hasAgent ? '1' : '0')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '服务连接',
                subtitle: '真机调试时，把这里改成你电脑的局域网地址，例如 http://192.168.1.8:8000',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _serverBaseUrlController,
                      decoration: const InputDecoration(labelText: '服务地址'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _saveServerSettings,
                            child: const Text('保存服务地址'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _testServerSettings,
                            child: const Text('测试服务连接'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前地址: ${_state.serverBaseUrl}',
                      style: const TextStyle(color: NotionPalette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: 'AI 能力配置',
                subtitle: '使用 OpenAI 兼容协议。接口地址示例: https://api.openai.com/v1',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(labelText: '接口地址'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscureApiKey,
                      decoration: InputDecoration(
                        labelText: '访问密钥',
                        suffixIcon: IconButton(
                          tooltip: _obscureApiKey ? '显示密钥' : '隐藏密钥',
                          onPressed: () {
                            setState(() => _obscureApiKey = !_obscureApiKey);
                          },
                          icon: Icon(_obscureApiKey ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(labelText: '模型名称'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          '温度',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          _temperature.toStringAsFixed(1),
                          style: const TextStyle(color: NotionPalette.textSecondary),
                        ),
                      ],
                    ),
                    Slider(
                      value: _temperature,
                      min: 0,
                      max: 1.5,
                      divisions: 15,
                      label: _temperature.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() => _temperature = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _saveAiSettings,
                            child: const Text('保存 AI 配置'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _testAiSettings,
                            child: const Text('测试连接'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _clearAiSettings,
                        child: const Text('清空 AI 配置'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _state.hasAiConfig
                          ? '当前模型: ${_state.aiModel} · 温度: ${_state.aiTemperature.toStringAsFixed(1)} · 密钥: ${_state.maskedApiKey()}'
                          : '尚未配置 AI 接口，将使用本地回退策略。',
                      style: const TextStyle(color: NotionPalette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '调试标识',
                subtitle: '便于联调接口和排查问题',
                action: TextButton(
                  onPressed: () async {
                    final raw = 'user=$uid\nagent=$aid\nfriends=$friendCount\nmeetings=$meetingCount';
                    await Clipboard.setData(ClipboardData(text: raw));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制调试标识')),
                    );
                  },
                  child: const Text('复制'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('用户 ID: $uid'),
                    const SizedBox(height: 6),
                    SelectableText('智能体 ID: $aid'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              NotionSectionCard(
                title: '本地重置',
                subtitle: '仅清空当前 App 内的演示状态，不删除后端数据',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '适合重新演练完整链路，验证首次引导和列表刷新。',
                      style: TextStyle(color: NotionPalette.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        _state.resetLocalState();
                        setState(() => _status = '本地状态已清空');
                      },
                      child: const Text('清空本地状态'),
                    ),
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
