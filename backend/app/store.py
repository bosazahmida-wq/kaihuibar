from __future__ import annotations

from collections import defaultdict

from app.models import (
    AgentProfile,
    Friendship,
    Meeting,
    MeetingParticipant,
    MeetingSummary,
    MessageTurn,
    User,
)


class InMemoryStore:
    def __init__(self) -> None:
        self.users: dict[str, User] = {}
        self.agents: dict[str, AgentProfile] = {}
        self.friendships: dict[str, Friendship] = {}
        self.meetings: dict[str, Meeting] = {}
        self.participants: dict[str, list[MeetingParticipant]] = defaultdict(list)
        self.turns: dict[str, list[MessageTurn]] = defaultdict(list)
        self.summaries: dict[str, MeetingSummary] = {}


store = InMemoryStore()
