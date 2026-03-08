from __future__ import annotations

SENSITIVE_KEYWORDS = {
    "self-harm",
    "suicide",
    "bomb",
    "weapon",
    "kill",
}


from typing import Optional, Tuple


def safety_guard(topic: str) -> Tuple[bool, Optional[str]]:
    lowered = topic.lower()
    for keyword in SENSITIVE_KEYWORDS:
        if keyword in lowered:
            return False, "High-risk topic detected. Please consult qualified professionals."
    return True, None
