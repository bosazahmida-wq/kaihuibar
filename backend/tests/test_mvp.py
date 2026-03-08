from datetime import datetime, timedelta, timezone
import os

os.environ["DATABASE_URL"] = "sqlite:///./test_kaihuibar.db"

from fastapi.testclient import TestClient

from app.db import Base, SessionLocal, engine, run_lightweight_migrations
from app.main import app
from app.orm import AuthSessionORM
from app.repository import reset_all


Base.metadata.create_all(bind=engine)
run_lightweight_migrations()
client = TestClient(app)


def setup_function() -> None:
    with SessionLocal() as db:
        reset_all(db)


def create_user(name: str) -> tuple[str, str]:
    res = client.post("/v1/auth/register", json={"name": name})
    assert res.status_code == 200
    payload = res.json()
    return payload["user"]["id"], payload["access_token"]


def auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def create_agent(owner_id: str, token: str, style: str = "direct") -> str:
    res = client.post(
        "/v1/agents/bootstrap",
        json={
            "owner_user_id": owner_id,
            "background": "product manager",
            "thinking_style": "structured",
            "risk_preference": "balanced",
            "communication_tone": style,
            "style_tags": ["clear"],
            "domain_tags": ["work"],
        },
        headers=auth_headers(token),
    )
    assert res.status_code == 200
    return res.json()["id"]


def test_agent_bootstrap_and_calibration() -> None:
    user_id, token = create_user("A")
    bootstrap = client.post(
        "/v1/agents/bootstrap",
        json={
            "owner_user_id": user_id,
            "background": "平时像个靠谱搭子",
            "thinking_style": "稳妥权衡",
            "risk_preference": "平衡取舍",
            "communication_tone": "幽默松弛",
            "helper_style": "军师伙伴",
            "scene_tags": ["生活决策", "游戏开黑"],
            "principles": "先看现实成本，再决定要不要冲。",
            "avoidances": "不要说教，不要剧透。",
            "response_preferences": "先给结论，再给选项。",
            "custom_prompt": "遇到卡关时提醒我先稳节奏。",
            "style_tags": ["军师伙伴", "幽默松弛"],
            "domain_tags": ["生活决策", "游戏开黑"],
        },
        headers=auth_headers(token),
    )
    assert bootstrap.status_code == 200
    agent_id = bootstrap.json()["id"]
    assert bootstrap.json()["persona_json"]["helper_style"] == "军师伙伴"
    assert bootstrap.json()["persona_json"]["scene_tags"] == ["生活决策", "游戏开黑"]
    assert bootstrap.json()["domain_tags"] == ["生活决策", "游戏开黑"]

    update = client.put(
        f"/v1/agents/{agent_id}",
        json={
            "background": "关键时刻会帮我稳住局面的朋友",
            "thinking_style": "结构拆解",
            "risk_preference": "先稳住",
            "communication_tone": "直接清晰",
            "helper_style": "主持统筹",
            "scene_tags": ["关系沟通", "生活决策"],
            "principles": "先把问题拆开，再收敛方案。",
            "avoidances": "不要替别人做道德审判。",
            "response_preferences": "先说重点，再列步骤。",
            "custom_prompt": "面对冲突先翻译双方意图。",
            "style_tags": ["主持统筹"],
            "domain_tags": ["关系沟通", "生活决策"],
        },
        headers=auth_headers(token),
    )
    assert update.status_code == 200
    assert update.json()["persona_json"]["background"] == "关键时刻会帮我稳住局面的朋友"
    assert update.json()["persona_json"]["helper_style"] == "主持统筹"
    assert update.json()["domain_tags"] == ["关系沟通", "生活决策"]

    calibrate = client.post(
        f"/v1/agents/{agent_id}/calibrate-chat",
        json={"chat_turns": ["I prefer concise answers", "challenge weak assumptions"]},
        headers=auth_headers(token),
    )
    assert calibrate.status_code == 200
    payload = calibrate.json()
    assert payload["confidence_score"] > 0.55
    assert "calibration_notes" in payload["persona_json"]


def test_assessment_generates_initial_persona_draft() -> None:
    _, token = create_user("Assessor")

    template = client.get("/v1/agents/assessment/template", headers=auth_headers(token))
    assert template.status_code == 200
    questions = template.json()["questions"]
    assert len(questions) == 10

    answers = [{"question_id": item["id"], "score": 4} for item in questions]
    draft = client.post(
        "/v1/agents/assessment/draft",
        json={"answers": answers},
        headers=auth_headers(token),
    )
    assert draft.status_code == 200
    payload = draft.json()
    assert payload["questionnaire_name"] == "五大人格入门测评"
    assert payload["helper_style"]
    assert len(payload["scene_tags"]) >= 2
    assert "assessment_scores" in payload
    assert "assessment_summary" in payload


def test_friendship_request_and_accept() -> None:
    a, token_a = create_user("A")
    b, token_b = create_user("B")

    req = client.post(
        "/v1/friends/request",
        json={"requester_id": a, "addressee_id": b},
        headers=auth_headers(token_a),
    )
    assert req.status_code == 200
    fid = req.json()["id"]

    accepted = client.post(f"/v1/friends/{fid}/accept", headers=auth_headers(token_b))
    assert accepted.status_code == 200
    assert accepted.json()["status"] == "accepted"


def test_demo_friend_creation_keeps_relationship_flow() -> None:
    owner, owner_token = create_user("Owner")
    response = client.post(
        "/v1/friends/demo",
        json={"name": "测试搭子"},
        headers=auth_headers(owner_token),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["direction"] == "connected"
    assert payload["friendship"]["status"] == "accepted"
    assert payload["friend_user"]["name"] == "测试搭子"
    assert payload["friend_agent"]["domain_tags"] == ["生活决策", "游戏开黑"]

    friends = client.get("/v1/friends", params={"user_id": owner}, headers=auth_headers(owner_token))
    assert friends.status_code == 200
    assert friends.json()[0]["friend_user"]["name"] == "测试搭子"


def test_profile_update_and_list_endpoints() -> None:
    owner, owner_token = create_user("Owner")
    friend, friend_token = create_user("Friend")

    rename = client.put(
        f"/v1/auth/users/{owner}",
        json={"name": "Owner Prime"},
        headers=auth_headers(owner_token),
    )
    assert rename.status_code == 200
    assert rename.json()["name"] == "Owner Prime"

    owner_agent = create_agent(owner, owner_token, "calm")
    friend_agent = create_agent(friend, friend_token, "aggressive")

    req = client.post(
        "/v1/friends/request",
        json={"requester_id": owner, "addressee_id": friend},
        headers=auth_headers(owner_token),
    )
    client.post(f"/v1/friends/{req.json()['id']}/accept", headers=auth_headers(friend_token))

    friends = client.get("/v1/friends", params={"user_id": owner}, headers=auth_headers(owner_token))
    assert friends.status_code == 200
    assert friends.json()[0]["friend_user"]["id"] == friend
    assert friends.json()[0]["friend_agent"]["id"] == friend_agent
    assert "email" not in friends.json()[0]["friend_user"]
    assert "persona_json" not in friends.json()[0]["friend_agent"]

    agents = client.get("/v1/agents", params={"owner_user_id": owner}, headers=auth_headers(owner_token))
    assert agents.status_code == 200
    assert agents.json()[0]["id"] == owner_agent

    search = client.get("/v1/users/search", params={"q": "Fri"}, headers=auth_headers(owner_token))
    assert search.status_code == 200
    assert search.json()[0]["user"]["id"] == friend
    assert search.json()[0]["relationship_status"] == "accepted"
    assert "email" not in search.json()[0]["user"]
    assert "persona_json" not in search.json()[0]["agent"]


def test_public_agent_library_search_and_invite() -> None:
    owner, owner_token = create_user("Owner")
    stranger, stranger_token = create_user("Stranger")
    public_agent = create_agent(owner, owner_token, "calm")

    sharing = client.put(
        f"/v1/agents/{public_agent}/sharing",
        json={
            "is_public": True,
            "public_name": "深夜军师",
            "public_description": "适合生活决策和关系沟通的公共分身。",
        },
        headers=auth_headers(owner_token),
    )
    assert sharing.status_code == 200
    assert sharing.json()["is_public"] is True

    search = client.get(
        "/v1/agents/public/search",
        params={"q": "军师"},
        headers=auth_headers(stranger_token),
    )
    assert search.status_code == 200
    assert search.json()[0]["agent"]["id"] == public_agent
    assert search.json()[0]["agent"]["public_name"] == "深夜军师"
    assert search.json()[0]["owner"]["id"] == owner

    meeting = client.post(
        "/v1/meetings",
        json={
            "creator_id": stranger,
            "topic": "周末去不去旅行",
            "mode": "moderated",
            "participants": [
                {
                    "participant_type": "agent",
                    "participant_id": public_agent,
                    "role": "公共分身",
                }
            ],
        },
        headers=auth_headers(stranger_token),
    )
    assert meeting.status_code == 200


def test_meeting_modes_generate_summary() -> None:
    owner, owner_token = create_user("Owner")
    friend, friend_token = create_user("Friend")

    req = client.post(
        "/v1/friends/request",
        json={"requester_id": owner, "addressee_id": friend},
        headers=auth_headers(owner_token),
    )
    client.post(f"/v1/friends/{req.json()['id']}/accept", headers=auth_headers(friend_token))

    owner_agent = create_agent(owner, owner_token, "calm")
    friend_agent = create_agent(friend, friend_token, "aggressive")

    for mode in ["moderated", "free", "manual"]:
        meeting = client.post(
            "/v1/meetings",
            json={
                "creator_id": owner,
                "topic": "How to improve weekly team sync",
                "mode": mode,
                "participants": [
                    {
                        "participant_type": "agent",
                        "participant_id": owner_agent,
                        "role": "strategist",
                    },
                    {
                        "participant_type": "agent",
                        "participant_id": friend_agent,
                        "role": "critic",
                    },
                ],
            },
            headers=auth_headers(owner_token),
        )
        assert meeting.status_code == 200
        meeting_id = meeting.json()["meeting"]["id"]

        start = client.post(
            f"/v1/meetings/{meeting_id}/start",
            json={"manual_speaker_order": [friend_agent, owner_agent]},
            headers=auth_headers(owner_token),
        )
        assert start.status_code == 200
        assert start.json()["turn_count"] > 0

        summary = client.get(f"/v1/meetings/{meeting_id}/summary", headers=auth_headers(owner_token))
        assert summary.status_code == 200
        assert "summary_text" in summary.json()

    history = client.get("/v1/meetings", params={"creator_id": owner}, headers=auth_headers(owner_token))
    assert history.status_code == 200
    assert len(history.json()) == 3
    assert history.json()[0]["meeting"]["creator_id"] == owner


def test_meeting_sse_events() -> None:
    owner, owner_token = create_user("Owner")
    owner_agent = create_agent(owner, owner_token, "calm")

    meeting = client.post(
        "/v1/meetings",
        json={
            "creator_id": owner,
            "topic": "SSE check",
            "mode": "moderated",
            "participants": [
                {
                    "participant_type": "agent",
                    "participant_id": owner_agent,
                    "role": "strategist",
                }
            ],
        },
        headers=auth_headers(owner_token),
    )
    meeting_id = meeting.json()["meeting"]["id"]
    client.post(f"/v1/meetings/{meeting_id}/start", json={}, headers=auth_headers(owner_token))

    response = client.get(f"/v1/meetings/{meeting_id}/events", headers=auth_headers(owner_token))
    assert response.status_code == 200
    assert "event: turn" in response.text
    assert "event: summary" in response.text
    assert "event: done" in response.text


def test_meeting_detail_endpoint() -> None:
    owner, owner_token = create_user("Owner")
    owner_agent = create_agent(owner, owner_token, "calm")

    meeting = client.post(
        "/v1/meetings",
        json={
            "creator_id": owner,
            "topic": "Detail check",
            "mode": "moderated",
            "participants": [
                {
                    "participant_type": "agent",
                    "participant_id": owner_agent,
                    "role": "主策划",
                }
            ],
        },
        headers=auth_headers(owner_token),
    )
    meeting_id = meeting.json()["meeting"]["id"]
    client.post(f"/v1/meetings/{meeting_id}/start", json={}, headers=auth_headers(owner_token))

    response = client.get(f"/v1/meetings/{meeting_id}", headers=auth_headers(owner_token))
    assert response.status_code == 200
    payload = response.json()
    assert payload["meeting"]["id"] == meeting_id
    assert len(payload["turns"]) > 0
    assert payload["summary"] is not None


def test_subscription_upgrade() -> None:
    user_id, token = create_user("Subscriber")
    upgrade = client.post(
        "/v1/billing/subscribe",
        json={"user_id": user_id, "tier": "pro"},
        headers=auth_headers(token),
    )
    assert upgrade.status_code == 200
    assert upgrade.json()["plan_tier"] == "pro"


def test_non_friend_agent_invite_blocked() -> None:
    owner, owner_token = create_user("Owner")
    outsider, outsider_token = create_user("Outsider")
    outsider_agent = create_agent(outsider, outsider_token)

    meeting = client.post(
        "/v1/meetings",
        json={
            "creator_id": owner,
            "topic": "Launch plan",
            "mode": "moderated",
            "participants": [
                {
                    "participant_type": "agent",
                    "participant_id": outsider_agent,
                    "role": "advisor",
                }
            ],
        },
        headers=auth_headers(owner_token),
    )
    assert meeting.status_code == 403


def test_ai_connection_endpoint(monkeypatch) -> None:
    def fake_chat_completion(ai_config, *, system_prompt: str, user_prompt: str) -> str:
        assert ai_config["base_url"] == "https://example.com/v1"
        assert ai_config["model"] == "gpt-test"
        return "连接成功。"

    monkeypatch.setattr("app.main.chat_completion", fake_chat_completion)

    user_id, token = create_user("Tester")
    assert user_id

    response = client.post(
        "/v1/ai/test",
        json={
            "ai_config": {
                "base_url": "https://example.com/v1",
                "api_key": "test-key",
                "model": "gpt-test",
                "temperature": 0.3,
            }
        },
        headers=auth_headers(token),
    )

    assert response.status_code == 200
    assert response.json()["message"] == "连接成功。"


def test_private_ai_base_url_is_blocked() -> None:
    _, token = create_user("Tester")

    response = client.post(
        "/v1/ai/test",
        json={
            "ai_config": {
                "base_url": "http://127.0.0.1:11434/v1",
                "api_key": "test-key",
                "model": "llama",
                "temperature": 0.3,
            }
        },
        headers=auth_headers(token),
    )

    assert response.status_code == 400
    assert "不允许访问本地或内网 AI 地址" in response.json()["detail"]


def test_unauthorized_requests_are_rejected() -> None:
    response = client.get("/v1/auth/me")
    assert response.status_code == 401

    user_id, token = create_user("Owner")
    response = client.get("/v1/auth/me", headers=auth_headers(token))
    assert response.status_code == 200
    assert response.json()["id"] == user_id


def test_expired_session_is_rejected(monkeypatch) -> None:
    user_id, token = create_user("Owner")
    monkeypatch.setenv("AUTH_SESSION_TTL_HOURS", "1")

    with SessionLocal() as db:
        row = db.query(AuthSessionORM).filter(AuthSessionORM.user_id == user_id).one()
        row.created_at = datetime.now(timezone.utc) - timedelta(hours=2)
        db.commit()

    response = client.get("/v1/auth/me", headers=auth_headers(token))
    assert response.status_code == 401
    assert response.json()["detail"] == "登录状态已过期，请重新登录"


def test_cross_user_access_is_blocked() -> None:
    owner, owner_token = create_user("Owner")
    intruder, intruder_token = create_user("Intruder")
    assert intruder

    response = client.put(
        f"/v1/auth/users/{owner}",
        json={"name": "Hacked"},
        headers=auth_headers(intruder_token),
    )
    assert response.status_code == 403

    response = client.get(
        "/v1/agents",
        params={"owner_user_id": owner},
        headers=auth_headers(intruder_token),
    )
    assert response.status_code == 403
