from __future__ import annotations

import json
from typing import Any, Optional

from app.models import (
    AgentProfile,
    Meeting,
    MeetingMode,
    MeetingParticipant,
    MeetingSummary,
    MessageTurn,
    ParticipantType,
)
from app.services.llm import chat_completion

MAX_FREE_ROUNDS = 6


def _extract_json_payload(raw: str) -> dict[str, Any]:
    text = raw.strip()
    if text.startswith("```"):
        lines = text.splitlines()
        if len(lines) >= 3:
            text = "\n".join(lines[1:-1]).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        text = text[start : end + 1]
    return json.loads(text)


def _participant_label_map(participants: list[MeetingParticipant]) -> dict[str, str]:
    labels: dict[str, str] = {}
    for index, participant in enumerate(participants, start=1):
        labels[participant.participant_id] = participant.role or f"讨论成员{index}"
    return labels


def _speaker_sentence(speaker_label: str, topic: str, angle: str) -> str:
    return f"{speaker_label} 针对“{topic}”的观点：{angle}。"


def _persona_context(agent: Optional[AgentProfile]) -> str:
    if not agent:
        return "未提供额外人格设定。"

    persona = agent.persona_json or {}
    sections = [
        f"身份与状态：{persona.get('identity_brief') or persona.get('background') or '未设置'}",
        f"常见场景：{'、'.join(persona.get('scene_tags', []) or agent.domain_tags or []) or '未设置'}",
        f"决策风格：{persona.get('decision_style') or persona.get('thinking_style') or '未设置'}",
        f"风险取向：{persona.get('risk_preference') or '未设置'}",
        f"互动方式：{persona.get('helper_style') or '未设置'}",
        f"表达气质：{persona.get('communication_tone') or '未设置'}",
    ]

    if persona.get("principles"):
        sections.append(f"行事准则：{persona['principles']}")
    if persona.get("avoidances"):
        sections.append(f"禁止事项：{persona['avoidances']}")
    if persona.get("response_preferences"):
        sections.append(f"帮助偏好：{persona['response_preferences']}")
    if persona.get("custom_prompt"):
        sections.append(f"额外设定：{persona['custom_prompt']}")

    return "\n".join(sections)


def _fallback_turns(
    meeting: Meeting,
    participants: list[MeetingParticipant],
    manual_speaker_order: Optional[list[str]] = None,
) -> list[MessageTurn]:
    speaker_ids = [p.participant_id for p in participants if p.left_at is None]
    label_map = _participant_label_map(participants)
    if not speaker_ids:
        return []

    turns: list[MessageTurn] = []

    if meeting.mode == MeetingMode.MODERATED:
        stages = [
            "先澄清问题边界与限制条件",
            "提出候选方案",
            "对最佳方案做风险检验",
            "收敛成最终建议",
        ]
        for idx, stage in enumerate(stages, start=1):
            speaker = speaker_ids[(idx - 1) % len(speaker_ids)]
            turns.append(
                MessageTurn(
                    meeting_id=meeting.id,
                    speaker_type=ParticipantType.AGENT,
                    speaker_id=speaker,
                    content=_speaker_sentence(label_map.get(speaker, speaker), meeting.topic, stage),
                    round_index=idx,
                )
            )
    elif meeting.mode == MeetingMode.FREE:
        angles = [
            "快速给出一个直接方案",
            "提出反方视角",
            "分析主要风险",
            "估算资源成本",
            "拆出执行顺序",
            "总结共识",
            "补充一个额外论点",
        ]
        for idx, angle in enumerate(angles, start=1):
            if idx > MAX_FREE_ROUNDS:
                turns.append(
                    MessageTurn(
                        meeting_id=meeting.id,
                        speaker_type=ParticipantType.AGENT,
                        speaker_id="moderator",
                        content="已达到最大轮次，主持人强制收敛，避免讨论发散。",
                        round_index=idx,
                    )
                )
                break
            speaker = speaker_ids[(idx - 1) % len(speaker_ids)]
            turns.append(
                MessageTurn(
                    meeting_id=meeting.id,
                    speaker_type=ParticipantType.AGENT,
                    speaker_id=speaker,
                    content=_speaker_sentence(label_map.get(speaker, speaker), meeting.topic, angle),
                    round_index=idx,
                )
            )
    else:
        order = manual_speaker_order or speaker_ids
        for idx, speaker in enumerate(order, start=1):
            if speaker not in speaker_ids:
                continue
            turns.append(
                MessageTurn(
                    meeting_id=meeting.id,
                    speaker_type=ParticipantType.AGENT,
                    speaker_id=speaker,
                    content=_speaker_sentence(
                        label_map.get(speaker, speaker),
                        meeting.topic,
                        "这是由会议发起人点名触发的一轮发言",
                    ),
                    round_index=idx,
                )
            )

    return turns


def _fallback_summary(meeting: Meeting, turns: list[MessageTurn], *, ai_failed: bool = False) -> MeetingSummary:
    if not turns:
        text = f"会议“{meeting.topic}”没有活跃参与者，已自动结束。"
        return MeetingSummary(
            meeting_id=meeting.id,
            summary_text=text,
            key_points=["会议因无可用参与者而关闭。"],
            disagreements=[],
            next_steps=["重新选择参会者后再次发起会议。"],
        )

    key_points = [
        "问题边界和限制条件已被明确。",
        "多个候选方案已被讨论。",
        "主持人已推动讨论收敛到一个主方向。",
    ]
    disagreements = [
        "执行速度与方案质量之间存在取舍。",
        "不同参与者对风险承受度判断不一致。",
    ]
    next_steps = [
        "把当前方案拆成负责人和时间点。",
        "在 48 小时内做一次回看验证关键假设。",
        "如果遇到高风险问题，升级给真人专家处理。",
    ]

    prefix = "AI接口调用失败，已回退本地策略。" if ai_failed else ""
    text = (
        f"{prefix}会议“{meeting.topic}”已完成，模式为“{meeting.mode.value}”。"
        f"本场共完成 {len(turns)} 轮发言。"
    )

    return MeetingSummary(
        meeting_id=meeting.id,
        summary_text=text,
        key_points=key_points,
        disagreements=disagreements,
        next_steps=next_steps,
    )


def run_meeting(
    meeting: Meeting,
    participants: list[MeetingParticipant],
    manual_speaker_order: Optional[list[str]] = None,
    ai_config: Optional[dict[str, Any]] = None,
    agent_profiles: Optional[dict[str, AgentProfile]] = None,
) -> list[MessageTurn]:
    if not ai_config:
        return _fallback_turns(meeting, participants, manual_speaker_order)

    speaker_ids = [p.participant_id for p in participants if p.left_at is None]
    if not speaker_ids:
        return []

    turns: list[MessageTurn] = []
    try:
        if meeting.mode == MeetingMode.MODERATED:
            stages = ["澄清问题", "发散方案", "风险审视", "收敛建议"]
            for idx, stage in enumerate(stages, start=1):
                speaker = speaker_ids[(idx - 1) % len(speaker_ids)]
                role = next((p.role for p in participants if p.participant_id == speaker), "讨论成员")
                persona_context = _persona_context((agent_profiles or {}).get(speaker))
                content = chat_completion(
                    ai_config,
                    system_prompt=(
                        "你是会议中的智能体成员，请使用简洁中文输出。"
                        f"你的角色是：{role}。当前会议模式为主持编排。\n"
                        f"请严格参考以下人格设定发言：\n{persona_context}"
                    ),
                    user_prompt=(
                        f"会议主题：{meeting.topic}\n"
                        f"当前阶段：{stage}\n"
                        "请给出 1 到 2 句具体、有判断的发言。"
                    ),
                )
                turns.append(
                    MessageTurn(
                        meeting_id=meeting.id,
                        speaker_type=ParticipantType.AGENT,
                        speaker_id=speaker,
                        content=content,
                        round_index=idx,
                    )
                )
        elif meeting.mode == MeetingMode.FREE:
            prompts = [
                "先给出直觉方案",
                "再给出反对意见",
                "补充风险分析",
                "说明执行资源需求",
                "列出实施步骤",
                "总结当前共识",
            ]
            for idx, prompt in enumerate(prompts, start=1):
                speaker = speaker_ids[(idx - 1) % len(speaker_ids)]
                role = next((p.role for p in participants if p.participant_id == speaker), "讨论成员")
                persona_context = _persona_context((agent_profiles or {}).get(speaker))
                content = chat_completion(
                    ai_config,
                    system_prompt=(
                        "你是自由辩论模式下的会议成员，请使用简洁中文发言。"
                        f"你的角色是：{role}。\n"
                        f"请严格参考以下人格设定发言：\n{persona_context}"
                    ),
                    user_prompt=f"会议主题：{meeting.topic}\n当前任务：{prompt}\n请输出 1 到 2 句。",
                )
                turns.append(
                    MessageTurn(
                        meeting_id=meeting.id,
                        speaker_type=ParticipantType.AGENT,
                        speaker_id=speaker,
                        content=content,
                        round_index=idx,
                    )
                )
        else:
            order = manual_speaker_order or speaker_ids
            for idx, speaker in enumerate(order, start=1):
                if speaker not in speaker_ids:
                    continue
                role = next((p.role for p in participants if p.participant_id == speaker), "讨论成员")
                persona_context = _persona_context((agent_profiles or {}).get(speaker))
                content = chat_completion(
                    ai_config,
                    system_prompt=(
                        "你是手动点名模式下被邀请发言的智能体，请使用简洁中文。"
                        f"你的角色是：{role}。\n"
                        f"请严格参考以下人格设定发言：\n{persona_context}"
                    ),
                    user_prompt=f"会议主题：{meeting.topic}\n请从你的角色出发，给出本轮判断和建议。",
                )
                turns.append(
                    MessageTurn(
                        meeting_id=meeting.id,
                        speaker_type=ParticipantType.AGENT,
                        speaker_id=speaker,
                        content=content,
                        round_index=idx,
                    )
                )
        return turns
    except Exception:
        return _fallback_turns(meeting, participants, manual_speaker_order)


def build_summary(
    meeting: Meeting,
    turns: list[MessageTurn],
    ai_config: Optional[dict[str, Any]] = None,
) -> MeetingSummary:
    if not ai_config:
        return _fallback_summary(meeting, turns)

    transcript = "\n".join([f"{turn.speaker_id}: {turn.content}" for turn in turns])
    if not transcript.strip():
        return _fallback_summary(meeting, turns)

    try:
        raw = chat_completion(
            ai_config,
            system_prompt=(
                "你是会议主持人，请根据会议记录生成中文总结。"
                "输出必须是严格 JSON，包含 summary_text, key_points, disagreements, next_steps 四个字段。"
            ),
            user_prompt=(
                f"会议主题：{meeting.topic}\n"
                f"会议模式：{meeting.mode.value}\n"
                f"会议记录：\n{transcript}\n"
                "请输出 JSON，其中 key_points/disagreements/next_steps 都是字符串数组。"
            ),
        )

        payload = _extract_json_payload(raw)
        return MeetingSummary(
            meeting_id=meeting.id,
            summary_text=payload.get("summary_text", ""),
            key_points=list(payload.get("key_points", [])),
            disagreements=list(payload.get("disagreements", [])),
            next_steps=list(payload.get("next_steps", [])),
        )
    except Exception:
        return _fallback_summary(meeting, turns, ai_failed=True)
