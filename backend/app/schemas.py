from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, Field

from app.models import MeetingMode, ParticipantType


class RegisterUserRequest(BaseModel):
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None
    timezone: str = "Asia/Shanghai"


class AuthSessionResponse(BaseModel):
    user: dict[str, Any]
    access_token: str


class UpdateUserRequest(BaseModel):
    name: Optional[str] = None
    timezone: Optional[str] = None
    avatar: Optional[str] = None


class AgentBootstrapRequest(BaseModel):
    owner_user_id: str
    background: str
    thinking_style: str
    risk_preference: str
    communication_tone: str
    helper_style: str = ""
    scene_tags: list[str] = Field(default_factory=list)
    principles: str = ""
    avoidances: str = ""
    response_preferences: str = ""
    custom_prompt: str = ""
    assessment_scores: dict[str, float] = Field(default_factory=dict)
    assessment_summary: str = ""
    style_tags: list[str] = Field(default_factory=list)
    domain_tags: list[str] = Field(default_factory=list)


class AgentUpdateRequest(BaseModel):
    background: str
    thinking_style: str
    risk_preference: str
    communication_tone: str
    helper_style: str = ""
    scene_tags: list[str] = Field(default_factory=list)
    principles: str = ""
    avoidances: str = ""
    response_preferences: str = ""
    custom_prompt: str = ""
    assessment_scores: dict[str, float] = Field(default_factory=dict)
    assessment_summary: str = ""
    style_tags: list[str] = Field(default_factory=list)
    domain_tags: list[str] = Field(default_factory=list)


class AgentCalibrateRequest(BaseModel):
    chat_turns: list[str]


class AgentAssessmentAnswer(BaseModel):
    question_id: str
    score: int = Field(ge=1, le=5)


class AgentAssessmentDraftRequest(BaseModel):
    answers: list[AgentAssessmentAnswer]


class AgentSharingUpdateRequest(BaseModel):
    is_public: bool
    public_name: str = ""
    public_description: str = ""


class AiConfigRequest(BaseModel):
    base_url: str
    api_key: str
    model: str
    temperature: float = 0.7


class FriendRequestCreate(BaseModel):
    requester_id: str
    addressee_id: str


class DemoFriendCreateRequest(BaseModel):
    name: str


class MeetingParticipantInput(BaseModel):
    participant_type: ParticipantType
    participant_id: str
    role: str


class MeetingCreateRequest(BaseModel):
    creator_id: str
    topic: str
    mode: MeetingMode
    participants: list[MeetingParticipantInput]


class MeetingStartRequest(BaseModel):
    manual_speaker_order: Optional[list[str]] = None
    ai_config: Optional[AiConfigRequest] = None


class SubscribeRequest(BaseModel):
    user_id: str
    tier: str


class AiTestRequest(BaseModel):
    ai_config: AiConfigRequest


class ApiEnvelope(BaseModel):
    data: Any
