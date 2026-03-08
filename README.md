# 开会吧 MVP 实现

本仓库已落地一个可运行的 MVP 基础实现：

- `backend/`: FastAPI 服务，覆盖用户、智能体、好友、会议、总结、订阅接口。
- `mobile_flutter_stub/`: Flutter 端业务骨架与 API 对接层（需本地安装 Flutter 后补齐平台目录）。

## 对应计划能力

- 智能体创建：`/v1/agents/bootstrap` + `/v1/agents/{id}/calibrate-chat`
- 好友关系：`/v1/friends/request` + `/v1/friends/{id}/accept`
- 三模式会议：`moderated/free/manual`
- 主持总结：`/v1/meetings/{id}/summary`
- 实时流：`/v1/meetings/{id}/events`（SSE，会议页逐条展示 turn/summary）
- AI 配置：在“我的”页配置 OpenAI 兼容接口地址、访问密钥、模型与温度
- 订阅升级：`/v1/billing/subscribe`
- 隐私与护栏：非好友不可邀对方智能体；高风险主题拦截
- 持久化：`DATABASE_URL` 可切换 PostgreSQL/SQLite

## 持续集成

仓库已配置 GitHub Actions，在每次 `push` 到 `main` 和每个 `pull request` 上自动执行：

- 后端：`pytest -q tests`
- Flutter：`flutter analyze`
- Flutter：`flutter test -r compact`

## 本地运行

见 [backend/README.md](./backend/README.md) 与 [mobile_flutter_stub/README.md](./mobile_flutter_stub/README.md)。
