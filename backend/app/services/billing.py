from __future__ import annotations

from app.models import PlanTier, User


def update_subscription(user: User, tier: str) -> User:
    normalized = tier.lower()
    if normalized == PlanTier.PRO.value:
        user.plan_tier = PlanTier.PRO
    else:
        user.plan_tier = PlanTier.FREE
    return user
