from __future__ import annotations

from datetime import datetime, timezone

from app.models import AgentProfile
from app.schemas import AgentBootstrapRequest


def bootstrap_agent(payload: AgentBootstrapRequest) -> AgentProfile:
    scene_tags = payload.scene_tags or payload.domain_tags
    persona = {
        "background": payload.background,
        "identity_brief": payload.background,
        "thinking_style": payload.thinking_style,
        "decision_style": payload.thinking_style,
        "risk_preference": payload.risk_preference,
        "communication_tone": payload.communication_tone,
        "helper_style": payload.helper_style,
        "scene_tags": scene_tags,
        "principles": payload.principles.strip(),
        "avoidances": payload.avoidances.strip(),
        "response_preferences": payload.response_preferences.strip(),
        "custom_prompt": payload.custom_prompt.strip(),
        "assessment_scores": payload.assessment_scores,
        "assessment_summary": payload.assessment_summary.strip(),
        "calibration_notes": [],
    }
    return AgentProfile(
        owner_user_id=payload.owner_user_id,
        persona_json=persona,
        style_tags=payload.style_tags,
        domain_tags=scene_tags,
        public_name=payload.background[:40],
        public_description=payload.assessment_summary.strip() or payload.response_preferences.strip() or None,
        confidence_score=0.55,
    )


def calibrate_agent(agent: AgentProfile, chat_turns: list[str]) -> AgentProfile:
    notes = agent.persona_json.get("calibration_notes", [])
    notes.extend(chat_turns[-8:])
    agent.persona_json["calibration_notes"] = notes
    agent.confidence_score = min(0.99, agent.confidence_score + (0.02 * len(chat_turns)))
    agent.updated_at = datetime.now(timezone.utc)
    return agent
