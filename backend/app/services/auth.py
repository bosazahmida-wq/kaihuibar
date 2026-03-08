from __future__ import annotations

import hashlib
import secrets

from app.models import AuthSession, User


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def issue_access_token(user: User) -> tuple[str, AuthSession]:
    token = secrets.token_urlsafe(32)
    auth_session = AuthSession(
        user_id=user.id,
        token_hash=hash_token(token),
    )
    return token, auth_session
