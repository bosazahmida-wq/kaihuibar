# 开会吧 Flutter Stub

这是可接入后端 API 的移动端骨架，当前已补齐 Notion 风格的 5 Tab 导航、好友/会议列表、个人设置与 AI 配置面板。

## 已提供
- 基础路由和页面占位
- API 客户端 (`dio`)
- 会议与智能体核心数据模型
- 可对接后端 `http://localhost:8000`
- 可跑通演示闭环：创建用户和智能体 -> 建好友 -> 发起会议 -> 查看总结和 SSE 事件预览
- 会议页支持流式接收 turn / summary / done 事件
- “我的”页可保存 OpenAI 兼容接口配置：接口地址、访问密钥、模型、温度
- 智能体页已升级为通用“分身卡”建模：场景、行事准则、禁止事项、帮助偏好、额外设定
- 会话与 AI 配置本地持久化（敏感信息使用安全存储）

## 下一步
1. 在本地安装 Flutter SDK。
2. Web 调试可直接执行 `flutter run -d chrome --web-port 3000`。
3. 如需 macOS 原生端，使用项目内置 CocoaPods 包装器：
   `export PATH=/Users/bay/Desktop/meeting/mobile_flutter_stub/.local-bin:/Users/bay/Desktop/meeting/tools/flutter/bin:$PATH && flutter run -d macos`
4. 如需其他原生端，先在该目录运行 `flutter create .` 生成平台目录，再执行 `flutter run`。
