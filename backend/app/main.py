from __future__ import annotations

import json
import os
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.db import Base, SessionLocal, engine, get_db, run_lightweight_migrations
from app.models import (
    Friendship,
    FriendshipStatus,
    Meeting,
    MeetingParticipant,
    MeetingStatus,
    ParticipantType,
    User,
)
from app.repository import (
    are_friends,
    create_agent,
    create_auth_session,
    create_friendship,
    create_meeting,
    create_user,
    delete_auth_session,
    find_friendship_pair,
    get_agent,
    get_auth_session_by_token_hash,
    get_friendship,
    get_meeting,
    get_turns_after,
    get_participants,
    get_summary,
    get_turns,
    get_user,
    get_users_by_ids,
    list_agents_for_owner,
    list_friendships_for_user,
    list_friendships_for_targets,
    list_meetings_for_creator,
    list_participants_for_meetings,
    list_primary_agents_for_owners,
    list_summaries_for_meetings,
    search_public_agents,
    search_users,
    set_participants,
    set_turns,
    update_agent,
    update_friendship,
    update_meeting,
    upsert_summary,
    upsert_user,
)
from app.schemas import (
    AiTestRequest,
    AgentBootstrapRequest,
    AgentCalibrateRequest,
    AgentAssessmentDraftRequest,
    AgentSharingUpdateRequest,
    AgentUpdateRequest,
    DemoFriendCreateRequest,
    FriendRequestCreate,
    MeetingCreateRequest,
    MeetingStartRequest,
    RegisterUserRequest,
    SubscribeRequest,
    UpdateUserRequest,
)
from app.services.agent import bootstrap_agent, calibrate_agent
from app.services.assessment import assessment_template, generate_persona_draft
from app.services.auth import hash_token, issue_access_token
from app.services.billing import update_subscription
from app.services.llm import chat_completion
from app.services.meeting import build_summary, run_meeting
from app.services.safety import safety_guard


def _cors_origins() -> list[str]:
    configured = os.getenv("CORS_ALLOW_ORIGINS")
    if configured:
        return [origin.strip() for origin in configured.split(",") if origin.strip()]
    return [
        "http://127.0.0.1:3000",
        "http://localhost:3000",
        "http://127.0.0.1:3001",
        "http://localhost:3001",
    ]

@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    run_lightweight_migrations()
    yield


app = FastAPI(title="KaihuiBar MVP API", version="0.2.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
bearer_scheme = HTTPBearer(auto_error=False)


def _get_user_or_404(db: Session, user_id: str) -> User:
    user = get_user(db, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="用户不存在")
    return user


def _public_user_payload(user: User) -> dict[str, object]:
    return {
        "id": user.id,
        "name": user.name,
        "avatar": user.avatar,
        "plan_tier": user.plan_tier,
    }


def _public_agent_payload(agent) -> Optional[dict[str, object]]:
    if not agent:
        return None
    return {
        "id": agent.id,
        "style_tags": agent.style_tags,
        "domain_tags": agent.domain_tags,
        "is_public": agent.is_public,
        "public_name": agent.public_name,
        "public_description": agent.public_description,
        "confidence_score": agent.confidence_score,
    }


def _ensure_self(current_user: User, expected_user_id: str) -> None:
    if current_user.id != expected_user_id:
        raise HTTPException(status_code=403, detail="无权访问其他用户的数据")


def _ensure_meeting_access(current_user: User, meeting: Meeting) -> None:
    if meeting.creator_id != current_user.id:
        raise HTTPException(status_code=403, detail="无权访问该会议")


def require_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="缺少有效登录凭证")

    auth_session = get_auth_session_by_token_hash(db, hash_token(credentials.credentials))
    if not auth_session:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录状态已失效，请重新登录")

    ttl_hours = max(1, int(os.getenv("AUTH_SESSION_TTL_HOURS", "720")))
    created_at = auth_session.created_at
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    expires_at = created_at + timedelta(hours=ttl_hours)
    if expires_at <= datetime.now(timezone.utc):
        delete_auth_session(db, auth_session.id)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录状态已过期，请重新登录")

    return _get_user_or_404(db, auth_session.user_id)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/ai/test")
def test_ai_connection(payload: AiTestRequest, _: User = Depends(require_current_user)):
    try:
        content = chat_completion(
            payload.ai_config.model_dump(),
            system_prompt="你是连接测试助手，请只用一句中文回答。",
            user_prompt="如果连接成功，请回复：连接成功。",
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"message": content}


@app.post("/v1/auth/register")
def register(payload: RegisterUserRequest, db: Session = Depends(get_db)):
    user = User(
        name=payload.name,
        email=payload.email,
        phone=payload.phone,
        timezone=payload.timezone,
    )
    user = create_user(db, user)
    token, auth_session = issue_access_token(user)
    create_auth_session(db, auth_session)
    return {
        "user": user,
        "access_token": token,
    }


@app.get("/v1/auth/me")
def auth_me(current_user: User = Depends(require_current_user)):
    return _public_user_payload(current_user)


@app.get("/v1/users/search")
def search_users_api(
    q: str = "",
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    users = search_users(db, q, exclude_user_id=current_user.id)
    user_ids = [user.id for user in users]
    primary_agents = list_primary_agents_for_owners(db, user_ids)
    friendships_by_user = list_friendships_for_targets(db, current_user.id, user_ids)
    enriched = []
    for user in users:
        friendship = friendships_by_user.get(user.id)
        if friendship is None:
            relationship_status = "none"
            direction = "none"
        elif friendship.status == FriendshipStatus.ACCEPTED:
            relationship_status = "accepted"
            direction = "connected"
        else:
            is_outgoing = friendship.requester_id == current_user.id
            relationship_status = "pending"
            direction = "outgoing" if is_outgoing else "incoming"

        enriched.append(
            {
                "user": _public_user_payload(user),
                "agent": _public_agent_payload(primary_agents.get(user.id)),
                "friendship": friendship,
                "relationship_status": relationship_status,
                "direction": direction,
            }
        )
    return enriched


@app.put("/v1/auth/users/{user_id}")
def update_user_profile(
    user_id: str,
    payload: UpdateUserRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
) -> User:
    _ensure_self(current_user, user_id)
    user = _get_user_or_404(db, user_id)
    if payload.name is not None:
        user.name = payload.name
    if payload.timezone is not None:
        user.timezone = payload.timezone
    if payload.avatar is not None:
        user.avatar = payload.avatar
    return upsert_user(db, user)


@app.post("/v1/agents/bootstrap")
def create_agent_profile(
    payload: AgentBootstrapRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    _ensure_self(current_user, payload.owner_user_id)
    _get_user_or_404(db, payload.owner_user_id)
    agent = bootstrap_agent(payload)
    return create_agent(db, agent)


@app.get("/v1/agents/assessment/template")
def get_agent_assessment_template():
    return assessment_template()


@app.post("/v1/agents/assessment/draft")
def get_agent_assessment_draft(
    payload: AgentAssessmentDraftRequest,
):
    try:
        return generate_persona_draft(payload.answers)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@app.put("/v1/agents/{agent_id}")
def update_agent_profile(
    agent_id: str,
    payload: AgentUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    agent = get_agent(db, agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="智能体不存在")
    _ensure_self(current_user, agent.owner_user_id)
    agent.persona_json["background"] = payload.background
    agent.persona_json["identity_brief"] = payload.background
    agent.persona_json["thinking_style"] = payload.thinking_style
    agent.persona_json["decision_style"] = payload.thinking_style
    agent.persona_json["risk_preference"] = payload.risk_preference
    agent.persona_json["communication_tone"] = payload.communication_tone
    agent.persona_json["helper_style"] = payload.helper_style
    agent.persona_json["scene_tags"] = payload.scene_tags or payload.domain_tags
    agent.persona_json["principles"] = payload.principles.strip()
    agent.persona_json["avoidances"] = payload.avoidances.strip()
    agent.persona_json["response_preferences"] = payload.response_preferences.strip()
    agent.persona_json["custom_prompt"] = payload.custom_prompt.strip()
    agent.persona_json["assessment_scores"] = payload.assessment_scores
    agent.persona_json["assessment_summary"] = payload.assessment_summary.strip()
    agent.style_tags = payload.style_tags
    agent.domain_tags = payload.scene_tags or payload.domain_tags
    return update_agent(db, agent)


@app.put("/v1/agents/{agent_id}/sharing")
def update_agent_sharing(
    agent_id: str,
    payload: AgentSharingUpdateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    agent = get_agent(db, agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="智能体不存在")
    _ensure_self(current_user, agent.owner_user_id)
    agent.is_public = payload.is_public
    agent.public_name = payload.public_name.strip() or agent.persona_json.get("identity_brief") or agent.public_name
    agent.public_description = payload.public_description.strip() or agent.public_description
    return update_agent(db, agent)


@app.get("/v1/agents")
def list_agents(
    owner_user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    _ensure_self(current_user, owner_user_id)
    _get_user_or_404(db, owner_user_id)
    return list_agents_for_owner(db, owner_user_id)


@app.get("/v1/agents/public/search")
def search_public_agent_library(
    q: str = "",
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    agents = search_public_agents(db, q, exclude_owner_user_id=current_user.id)
    users_by_id = get_users_by_ids(db, [agent.owner_user_id for agent in agents])
    return [
        {
            "owner": _public_user_payload(users_by_id[agent.owner_user_id]),
            "agent": _public_agent_payload(agent),
            "identity_brief": agent.persona_json.get("identity_brief") or agent.persona_json.get("background"),
            "assessment_summary": agent.persona_json.get("assessment_summary"),
        }
        for agent in agents
        if agent.owner_user_id in users_by_id
    ]


@app.post("/v1/agents/{agent_id}/calibrate-chat")
def calibrate(
    agent_id: str,
    payload: AgentCalibrateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    agent = get_agent(db, agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="智能体不存在")
    _ensure_self(current_user, agent.owner_user_id)
    updated = calibrate_agent(agent, payload.chat_turns)
    return update_agent(db, updated)


@app.post("/v1/friends/request")
def request_friend(
    payload: FriendRequestCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    _ensure_self(current_user, payload.requester_id)
    _get_user_or_404(db, payload.requester_id)
    _get_user_or_404(db, payload.addressee_id)

    if payload.requester_id == payload.addressee_id:
        raise HTTPException(status_code=400, detail="不能添加自己为好友")

    existing = find_friendship_pair(db, payload.requester_id, payload.addressee_id)
    if existing:
        return existing

    friendship = Friendship(
        requester_id=payload.requester_id,
        addressee_id=payload.addressee_id,
    )
    return create_friendship(db, friendship)


@app.post("/v1/friends/{friendship_id}/accept")
def accept_friend(
    friendship_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    friendship = get_friendship(db, friendship_id)
    if not friendship:
        raise HTTPException(status_code=404, detail="好友申请不存在")
    if friendship.addressee_id != current_user.id:
        raise HTTPException(status_code=403, detail="无权处理该好友申请")
    friendship.status = FriendshipStatus.ACCEPTED
    return update_friendship(db, friendship)


@app.get("/v1/friends")
def list_friends(
    user_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    _ensure_self(current_user, user_id)
    _get_user_or_404(db, user_id)
    friendships = list_friendships_for_user(db, user_id)
    friend_user_ids = [
        friendship.addressee_id if friendship.requester_id == user_id else friendship.requester_id
        for friendship in friendships
    ]
    users_by_id = get_users_by_ids(db, friend_user_ids)
    primary_agents = list_primary_agents_for_owners(db, friend_user_ids)
    enriched = []
    for friendship in friendships:
        friend_user_id = (
            friendship.addressee_id if friendship.requester_id == user_id else friendship.requester_id
        )
        friend_user = users_by_id.get(friend_user_id)
        if not friend_user:
            raise HTTPException(status_code=404, detail="好友用户不存在")
        enriched.append(
            {
                "friendship": friendship,
                "friend_user": _public_user_payload(friend_user),
                "friend_agent": _public_agent_payload(primary_agents.get(friend_user_id)),
                "direction": (
                    "connected"
                    if friendship.status == FriendshipStatus.ACCEPTED
                    else "outgoing" if friendship.requester_id == user_id else "incoming"
                ),
            }
        )
    return enriched


@app.post("/v1/friends/demo")
def create_demo_friend(
    payload: DemoFriendCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    friend_name = payload.name.strip()
    if not friend_name:
        raise HTTPException(status_code=400, detail="测试好友名称不能为空")

    demo_user = create_user(
        db,
        User(
            name=friend_name,
            timezone=current_user.timezone,
        ),
    )
    demo_agent = create_agent(
        db,
        bootstrap_agent(
            AgentBootstrapRequest(
                owner_user_id=demo_user.id,
                background="靠谱搭子",
                thinking_style="稳妥权衡",
                risk_preference="平衡取舍",
                communication_tone="直接清晰",
                helper_style="队友搭子",
                scene_tags=["生活决策", "游戏开黑"],
                principles="先判断现实成本，再照顾体验感和节奏。",
                avoidances="不要说教，不要替人做最终决定，不要剧透。",
                response_preferences="先给结论，再给两个可选方案；游戏场景多报点，少废话。",
                custom_prompt="遇到犹豫时先帮我拆选项，遇到游戏局势紧张时优先稳住队伍。",
                style_tags=["队友搭子", "直接清晰"],
                domain_tags=["生活决策", "游戏开黑"],
            )
        ),
    )
    friendship = create_friendship(
        db,
        Friendship(
            requester_id=current_user.id,
            addressee_id=demo_user.id,
            status=FriendshipStatus.ACCEPTED,
        ),
    )
    return {
        "friendship": friendship,
        "friend_user": _public_user_payload(demo_user),
        "friend_agent": _public_agent_payload(demo_agent),
        "direction": "connected",
    }


@app.post("/v1/meetings")
def create_meeting_api(
    payload: MeetingCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    _ensure_self(current_user, payload.creator_id)
    creator = _get_user_or_404(db, payload.creator_id)

    safe, warning = safety_guard(payload.topic)
    if not safe:
        raise HTTPException(status_code=400, detail=warning)

    meeting = Meeting(creator_id=creator.id, topic=payload.topic, mode=payload.mode)
    meeting = create_meeting(db, meeting)

    participants: list[MeetingParticipant] = []
    for p in payload.participants:
        if p.participant_type == ParticipantType.HUMAN:
            _get_user_or_404(db, p.participant_id)
        else:
            agent = get_agent(db, p.participant_id)
            if not agent:
                raise HTTPException(status_code=404, detail=f"智能体 {p.participant_id} 不存在")
            if (
                agent.owner_user_id != creator.id
                and not are_friends(db, creator.id, agent.owner_user_id)
                and not agent.is_public
            ):
                raise HTTPException(status_code=403, detail="不能邀请非好友的智能体")

        participant = MeetingParticipant(
            meeting_id=meeting.id,
            participant_type=p.participant_type,
            participant_id=p.participant_id,
            role=p.role,
        )
        participants.append(participant)

    participants = set_participants(db, meeting.id, participants)
    return {"meeting": meeting, "participants": participants}


@app.get("/v1/meetings")
def list_meetings(
    creator_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    _ensure_self(current_user, creator_id)
    _get_user_or_404(db, creator_id)
    meetings = list_meetings_for_creator(db, creator_id)
    meeting_ids = [meeting.id for meeting in meetings]
    participants_by_meeting = list_participants_for_meetings(db, meeting_ids)
    summaries_by_meeting = list_summaries_for_meetings(db, meeting_ids)
    enriched = []
    for meeting in meetings:
        enriched.append(
            {
                "meeting": meeting,
                "participants": participants_by_meeting.get(meeting.id, []),
                "summary": summaries_by_meeting.get(meeting.id),
            }
        )
    return enriched


@app.get("/v1/meetings/{meeting_id}")
def get_meeting_detail(
    meeting_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    meeting = get_meeting(db, meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="会议不存在")
    _ensure_meeting_access(current_user, meeting)

    return {
        "meeting": meeting,
        "participants": get_participants(db, meeting_id),
        "turns": get_turns(db, meeting_id),
        "summary": get_summary(db, meeting_id),
    }


@app.post("/v1/meetings/{meeting_id}/start")
def start_meeting(
    meeting_id: str,
    payload: MeetingStartRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    meeting = get_meeting(db, meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="会议不存在")
    _ensure_meeting_access(current_user, meeting)

    participants = get_participants(db, meeting_id)
    meeting.status = MeetingStatus.RUNNING
    update_meeting(db, meeting)

    ai_config = payload.ai_config.model_dump() if payload.ai_config else None
    agent_profiles = {
        participant.participant_id: agent
        for participant in participants
        if participant.participant_type == ParticipantType.AGENT
        for agent in [get_agent(db, participant.participant_id)]
        if agent is not None
    }
    turns = run_meeting(
        meeting,
        participants,
        manual_speaker_order=payload.manual_speaker_order,
        ai_config=ai_config,
        agent_profiles=agent_profiles,
    )
    turns = set_turns(db, meeting_id, turns)

    summary = build_summary(meeting, turns, ai_config=ai_config)
    upsert_summary(db, summary)

    meeting.status = MeetingStatus.COMPLETED
    meeting = update_meeting(db, meeting)

    return {"meeting": meeting, "turn_count": len(turns)}


@app.get("/v1/meetings/{meeting_id}/stream")
def stream_meeting(
    meeting_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    meeting = get_meeting(db, meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="会议不存在")
    _ensure_meeting_access(current_user, meeting)
    return {"meeting": meeting, "turns": get_turns(db, meeting_id)}


@app.get("/v1/meetings/{meeting_id}/events")
def stream_meeting_events(
    meeting_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    meeting = get_meeting(db, meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="会议不存在")
    _ensure_meeting_access(current_user, meeting)

    def event_gen():
        last_round_index = 0
        summary_sent = False
        idle_ticks = 0

        while True:
            with SessionLocal() as stream_db:
                current_meeting = get_meeting(stream_db, meeting_id)
                turns = get_turns_after(stream_db, meeting_id, last_round_index)
                summary = None if summary_sent else get_summary(stream_db, meeting_id)

            for turn in turns:
                payload = {
                    "type": "turn",
                    "meeting_id": meeting_id,
                    "round_index": turn.round_index,
                    "speaker_id": turn.speaker_id,
                    "content": turn.content,
                }
                yield f"event: turn\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"
                last_round_index = turn.round_index
                idle_ticks = 0
                time.sleep(0.35)

            if summary and not summary_sent:
                payload = {
                    "type": "summary",
                    "meeting_id": meeting_id,
                    "summary_text": summary.summary_text,
                    "key_points": summary.key_points,
                    "disagreements": summary.disagreements,
                    "next_steps": summary.next_steps,
                }
                yield f"event: summary\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"
                summary_sent = True
                idle_ticks = 0

            if current_meeting and current_meeting.status == MeetingStatus.COMPLETED and summary_sent:
                yield "event: done\ndata: {}\n\n"
                break

            idle_ticks += 1
            if idle_ticks % 10 == 0:
                yield "event: ping\ndata: {}\n\n"
            time.sleep(0.3)

    return StreamingResponse(event_gen(), media_type="text/event-stream")


@app.get("/v1/meetings/{meeting_id}/summary")
def get_summary_api(
    meeting_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    meeting = get_meeting(db, meeting_id)
    if not meeting:
        raise HTTPException(status_code=404, detail="会议不存在")
    _ensure_meeting_access(current_user, meeting)

    summary = get_summary(db, meeting_id)
    if not summary:
        turns = get_turns(db, meeting_id)
        summary = build_summary(meeting, turns)
        summary = upsert_summary(db, summary)
    return summary


@app.post("/v1/billing/subscribe")
def subscribe(
    payload: SubscribeRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_current_user),
):
    _ensure_self(current_user, payload.user_id)
    user = _get_user_or_404(db, payload.user_id)
    user = update_subscription(user, payload.tier)
    return upsert_user(db, user)
