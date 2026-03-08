from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Optional
from uuid import uuid4

from pydantic import BaseModel, Field


class PlanTier(str, Enum):
    FREE = "free"
    PRO = "pro"


class FriendshipStatus(str, Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    BLOCKED = "blocked"


class MeetingMode(str, Enum):
    MODERATED = "moderated"
    FREE = "free"
    MANUAL = "manual"


class MeetingStatus(str, Enum):
    CREATED = "created"
    RUNNING = "running"
    COMPLETED = "completed"


class ParticipantType(str, Enum):
    HUMAN = "human"
    AGENT = "agent"


class User(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    name: str
    avatar: Optional[str] = None
    plan_tier: PlanTier = PlanTier.FREE
    timezone: str = "Asia/Shanghai"
    email: Optional[str] = None
    phone: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AuthSession(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    user_id: str
    token_hash: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class AgentProfile(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    owner_user_id: str
    persona_json: dict[str, Any]
    style_tags: list[str] = Field(default_factory=list)
    domain_tags: list[str] = Field(default_factory=list)
    is_public: bool = False
    public_name: Optional[str] = None
    public_description: Optional[str] = None
    confidence_score: float = 0.5
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class Friendship(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    requester_id: str
    addressee_id: str
    status: FriendshipStatus = FriendshipStatus.PENDING
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class Meeting(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    creator_id: str
    topic: str
    mode: MeetingMode
    status: MeetingStatus = MeetingStatus.CREATED
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class MeetingParticipant(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    meeting_id: str
    participant_type: ParticipantType
    participant_id: str
    role: str
    left_at: Optional[datetime] = None


class MessageTurn(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    meeting_id: str
    speaker_type: ParticipantType
    speaker_id: str
    content: str
    round_index: int
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class MeetingSummary(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid4()))
    meeting_id: str
    summary_text: str
    key_points: list[str] = Field(default_factory=list)
    disagreements: list[str] = Field(default_factory=list)
    next_steps: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
