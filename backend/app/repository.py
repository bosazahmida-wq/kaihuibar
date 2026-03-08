from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.models import (
    AgentProfile,
    AuthSession,
    Friendship,
    FriendshipStatus,
    Meeting,
    MeetingParticipant,
    MeetingSummary,
    MessageTurn,
    User,
)
from app.orm import (
    AgentProfileORM,
    AuthSessionORM,
    FriendshipORM,
    MeetingORM,
    MeetingParticipantORM,
    MeetingSummaryORM,
    MessageTurnORM,
    UserORM,
)


def _to_user(row: UserORM) -> User:
    return User.model_validate(row, from_attributes=True)


def _to_agent(row: AgentProfileORM) -> AgentProfile:
    return AgentProfile.model_validate(row, from_attributes=True)


def _to_auth_session(row: AuthSessionORM) -> AuthSession:
    return AuthSession.model_validate(row, from_attributes=True)


def _to_friendship(row: FriendshipORM) -> Friendship:
    return Friendship.model_validate(row, from_attributes=True)


def _to_meeting(row: MeetingORM) -> Meeting:
    return Meeting.model_validate(row, from_attributes=True)


def _to_participant(row: MeetingParticipantORM) -> MeetingParticipant:
    return MeetingParticipant.model_validate(row, from_attributes=True)


def _to_turn(row: MessageTurnORM) -> MessageTurn:
    return MessageTurn.model_validate(row, from_attributes=True)


def _to_summary(row: MeetingSummaryORM) -> MeetingSummary:
    return MeetingSummary.model_validate(row, from_attributes=True)


def create_user(db: Session, user: User) -> User:
    row = UserORM(**user.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_user(row)


def create_auth_session(db: Session, auth_session: AuthSession) -> AuthSession:
    row = AuthSessionORM(**auth_session.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_auth_session(row)


def get_auth_session_by_token_hash(db: Session, token_hash: str) -> Optional[AuthSession]:
    row = db.scalar(select(AuthSessionORM).where(AuthSessionORM.token_hash == token_hash))
    return _to_auth_session(row) if row else None


def delete_auth_sessions_for_user(db: Session, user_id: str) -> None:
    db.query(AuthSessionORM).filter(AuthSessionORM.user_id == user_id).delete()
    db.commit()


def delete_auth_session(db: Session, session_id: str) -> None:
    db.query(AuthSessionORM).filter(AuthSessionORM.id == session_id).delete()
    db.commit()


def get_user(db: Session, user_id: str) -> Optional[User]:
    row = db.get(UserORM, user_id)
    return _to_user(row) if row else None


def get_users_by_ids(db: Session, user_ids: list[str]) -> dict[str, User]:
    if not user_ids:
        return {}
    rows = db.query(UserORM).filter(UserORM.id.in_(set(user_ids))).all()
    return {row.id: _to_user(row) for row in rows}


def search_users(db: Session, query: str, exclude_user_id: Optional[str] = None) -> list[User]:
    statement = db.query(UserORM)
    if query.strip():
        statement = statement.filter(UserORM.name.ilike(f"%{query.strip()}%"))
    if exclude_user_id:
        statement = statement.filter(UserORM.id != exclude_user_id)
    rows = statement.order_by(UserORM.created_at.desc()).limit(20).all()
    return [_to_user(row) for row in rows]


def upsert_user(db: Session, user: User) -> User:
    row = db.get(UserORM, user.id)
    if not row:
        return create_user(db, user)
    for key, value in user.model_dump().items():
        setattr(row, key, value)
    db.commit()
    db.refresh(row)
    return _to_user(row)


def create_agent(db: Session, agent: AgentProfile) -> AgentProfile:
    row = AgentProfileORM(**agent.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_agent(row)


def get_agent(db: Session, agent_id: str) -> Optional[AgentProfile]:
    row = db.get(AgentProfileORM, agent_id)
    return _to_agent(row) if row else None


def update_agent(db: Session, agent: AgentProfile) -> AgentProfile:
    row = db.get(AgentProfileORM, agent.id)
    if not row:
        return create_agent(db, agent)
    for key, value in agent.model_dump().items():
        setattr(row, key, value)
    row.updated_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(row)
    return _to_agent(row)


def search_public_agents(
    db: Session,
    query: str,
    *,
    exclude_owner_user_id: Optional[str] = None,
) -> list[AgentProfile]:
    rows = (
        db.query(AgentProfileORM)
        .filter(AgentProfileORM.is_public.is_(True))
        .order_by(AgentProfileORM.updated_at.desc())
        .limit(100)
        .all()
    )
    query_text = query.strip().lower()
    agents: list[AgentProfile] = []
    for row in rows:
        if exclude_owner_user_id and row.owner_user_id == exclude_owner_user_id:
            continue
        agent = _to_agent(row)
        if not query_text:
            agents.append(agent)
            continue
        haystack = " ".join(
            [
                agent.public_name or "",
                agent.public_description or "",
                " ".join(agent.style_tags),
                " ".join(agent.domain_tags),
                str(agent.persona_json.get("identity_brief", "")),
            ]
        ).lower()
        if query_text in haystack:
            agents.append(agent)
    return agents[:20]


def list_agents_for_owner(db: Session, owner_user_id: str) -> list[AgentProfile]:
    rows = (
        db.query(AgentProfileORM)
        .filter(AgentProfileORM.owner_user_id == owner_user_id)
        .order_by(AgentProfileORM.updated_at.desc())
        .all()
    )
    return [_to_agent(row) for row in rows]


def list_primary_agents_for_owners(db: Session, owner_user_ids: list[str]) -> dict[str, AgentProfile]:
    if not owner_user_ids:
        return {}
    rows = (
        db.query(AgentProfileORM)
        .filter(AgentProfileORM.owner_user_id.in_(set(owner_user_ids)))
        .order_by(AgentProfileORM.owner_user_id.asc(), AgentProfileORM.updated_at.desc())
        .all()
    )
    agents: dict[str, AgentProfile] = {}
    for row in rows:
        if row.owner_user_id not in agents:
            agents[row.owner_user_id] = _to_agent(row)
    return agents


def find_friendship_pair(db: Session, user_a: str, user_b: str) -> Optional[Friendship]:
    row = db.scalar(
        select(FriendshipORM).where(
            or_(
                and_(FriendshipORM.requester_id == user_a, FriendshipORM.addressee_id == user_b),
                and_(FriendshipORM.requester_id == user_b, FriendshipORM.addressee_id == user_a),
            )
        )
    )
    return _to_friendship(row) if row else None


def create_friendship(db: Session, friendship: Friendship) -> Friendship:
    row = FriendshipORM(**friendship.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_friendship(row)


def get_friendship(db: Session, friendship_id: str) -> Optional[Friendship]:
    row = db.get(FriendshipORM, friendship_id)
    return _to_friendship(row) if row else None


def update_friendship(db: Session, friendship: Friendship) -> Friendship:
    row = db.get(FriendshipORM, friendship.id)
    if not row:
        return create_friendship(db, friendship)
    for key, value in friendship.model_dump().items():
        setattr(row, key, value)
    db.commit()
    db.refresh(row)
    return _to_friendship(row)


def list_friendships_for_user(db: Session, user_id: str) -> list[Friendship]:
    rows = (
        db.query(FriendshipORM)
        .filter(
            or_(
                FriendshipORM.requester_id == user_id,
                FriendshipORM.addressee_id == user_id,
            )
        )
        .order_by(FriendshipORM.created_at.desc())
        .all()
    )
    return [_to_friendship(row) for row in rows]


def list_friendships_for_targets(
    db: Session,
    user_id: str,
    target_user_ids: list[str],
) -> dict[str, Friendship]:
    if not target_user_ids:
        return {}
    rows = (
        db.query(FriendshipORM)
        .filter(
            or_(
                and_(
                    FriendshipORM.requester_id == user_id,
                    FriendshipORM.addressee_id.in_(set(target_user_ids)),
                ),
                and_(
                    FriendshipORM.addressee_id == user_id,
                    FriendshipORM.requester_id.in_(set(target_user_ids)),
                ),
            )
        )
        .all()
    )
    friendships: dict[str, Friendship] = {}
    for row in rows:
        other_id = row.addressee_id if row.requester_id == user_id else row.requester_id
        friendships[other_id] = _to_friendship(row)
    return friendships


def are_friends(db: Session, user_a: str, user_b: str) -> bool:
    friendship = find_friendship_pair(db, user_a, user_b)
    return bool(friendship and friendship.status == FriendshipStatus.ACCEPTED)


def create_meeting(db: Session, meeting: Meeting) -> Meeting:
    row = MeetingORM(**meeting.model_dump())
    db.add(row)
    db.commit()
    db.refresh(row)
    return _to_meeting(row)


def get_meeting(db: Session, meeting_id: str) -> Optional[Meeting]:
    row = db.get(MeetingORM, meeting_id)
    return _to_meeting(row) if row else None


def update_meeting(db: Session, meeting: Meeting) -> Meeting:
    row = db.get(MeetingORM, meeting.id)
    if not row:
        return create_meeting(db, meeting)
    for key, value in meeting.model_dump().items():
        setattr(row, key, value)
    db.commit()
    db.refresh(row)
    return _to_meeting(row)


def list_meetings_for_creator(db: Session, creator_id: str) -> list[Meeting]:
    rows = (
        db.query(MeetingORM)
        .filter(MeetingORM.creator_id == creator_id)
        .order_by(MeetingORM.created_at.desc())
        .all()
    )
    return [_to_meeting(row) for row in rows]


def set_participants(db: Session, meeting_id: str, participants: list[MeetingParticipant]) -> list[MeetingParticipant]:
    db.query(MeetingParticipantORM).filter(MeetingParticipantORM.meeting_id == meeting_id).delete()
    for participant in participants:
        db.add(MeetingParticipantORM(**participant.model_dump()))
    db.commit()
    rows = (
        db.query(MeetingParticipantORM)
        .filter(MeetingParticipantORM.meeting_id == meeting_id)
        .order_by(MeetingParticipantORM.id.asc())
        .all()
    )
    return [_to_participant(row) for row in rows]


def get_participants(db: Session, meeting_id: str) -> list[MeetingParticipant]:
    rows = (
        db.query(MeetingParticipantORM)
        .filter(MeetingParticipantORM.meeting_id == meeting_id)
        .order_by(MeetingParticipantORM.id.asc())
        .all()
    )
    return [_to_participant(row) for row in rows]


def list_participants_for_meetings(
    db: Session,
    meeting_ids: list[str],
) -> dict[str, list[MeetingParticipant]]:
    if not meeting_ids:
        return {}
    rows = (
        db.query(MeetingParticipantORM)
        .filter(MeetingParticipantORM.meeting_id.in_(set(meeting_ids)))
        .order_by(MeetingParticipantORM.meeting_id.asc(), MeetingParticipantORM.id.asc())
        .all()
    )
    participants: dict[str, list[MeetingParticipant]] = defaultdict(list)
    for row in rows:
        participants[row.meeting_id].append(_to_participant(row))
    return dict(participants)


def set_turns(db: Session, meeting_id: str, turns: list[MessageTurn]) -> list[MessageTurn]:
    db.query(MessageTurnORM).filter(MessageTurnORM.meeting_id == meeting_id).delete()
    for turn in turns:
        db.add(MessageTurnORM(**turn.model_dump()))
    db.commit()
    rows = (
        db.query(MessageTurnORM)
        .filter(MessageTurnORM.meeting_id == meeting_id)
        .order_by(MessageTurnORM.round_index.asc())
        .all()
    )
    return [_to_turn(row) for row in rows]


def get_turns(db: Session, meeting_id: str) -> list[MessageTurn]:
    rows = (
        db.query(MessageTurnORM)
        .filter(MessageTurnORM.meeting_id == meeting_id)
        .order_by(MessageTurnORM.round_index.asc())
        .all()
    )
    return [_to_turn(row) for row in rows]


def get_turns_after(db: Session, meeting_id: str, last_round_index: int) -> list[MessageTurn]:
    rows = (
        db.query(MessageTurnORM)
        .filter(
            MessageTurnORM.meeting_id == meeting_id,
            MessageTurnORM.round_index > last_round_index,
        )
        .order_by(MessageTurnORM.round_index.asc())
        .all()
    )
    return [_to_turn(row) for row in rows]


def upsert_summary(db: Session, summary: MeetingSummary) -> MeetingSummary:
    row = db.scalar(select(MeetingSummaryORM).where(MeetingSummaryORM.meeting_id == summary.meeting_id))
    if not row:
        row = MeetingSummaryORM(**summary.model_dump())
        db.add(row)
    else:
        for key, value in summary.model_dump().items():
            setattr(row, key, value)
    db.commit()
    db.refresh(row)
    return _to_summary(row)


def get_summary(db: Session, meeting_id: str) -> Optional[MeetingSummary]:
    row = db.scalar(select(MeetingSummaryORM).where(MeetingSummaryORM.meeting_id == meeting_id))
    return _to_summary(row) if row else None


def list_summaries_for_meetings(
    db: Session,
    meeting_ids: list[str],
) -> dict[str, MeetingSummary]:
    if not meeting_ids:
        return {}
    rows = (
        db.query(MeetingSummaryORM)
        .filter(MeetingSummaryORM.meeting_id.in_(set(meeting_ids)))
        .all()
    )
    return {row.meeting_id: _to_summary(row) for row in rows}


def reset_all(db: Session) -> None:
    db.query(AuthSessionORM).delete()
    db.query(MeetingSummaryORM).delete()
    db.query(MessageTurnORM).delete()
    db.query(MeetingParticipantORM).delete()
    db.query(MeetingORM).delete()
    db.query(FriendshipORM).delete()
    db.query(AgentProfileORM).delete()
    db.query(UserORM).delete()
    db.commit()
