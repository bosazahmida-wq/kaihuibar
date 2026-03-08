# 开会吧 MVP Backend

可运行的 FastAPI 原型，覆盖以下 MVP 能力：
- 账号注册
- 智能体问卷初始化 + 对话校准
- 好友申请/同意
- 三种会议模式（moderated/free/manual）
- 会议流与主持总结
- SSE 会议事件流
- OpenAI 兼容接口接入与连通性测试
- 订阅升级（free/pro）
- 数据持久化（PostgreSQL/SQLite）

## Quick Start

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

OpenAPI: `http://127.0.0.1:8000/docs`

## Database

默认使用 SQLite：

```bash
export DATABASE_URL=sqlite:///./kaihuibar.db
```

使用 PostgreSQL：

```bash
export DATABASE_URL=postgresql+psycopg2://user:password@localhost:5432/kaihuibar
```

## Run Tests

```bash
cd backend
source .venv/bin/activate
pytest -q
```

## API Summary

- `POST /v1/auth/register`
- `POST /v1/agents/bootstrap`
- `POST /v1/agents/{id}/calibrate-chat`
- `POST /v1/friends/request`
- `POST /v1/friends/{id}/accept`
- `POST /v1/meetings`
- `POST /v1/meetings/{id}/start`
- `GET /v1/meetings/{id}/stream`
- `GET /v1/meetings/{id}/events` (SSE)
- `GET /v1/meetings/{id}/summary`
- `POST /v1/ai/test`
- `POST /v1/billing/subscribe`
