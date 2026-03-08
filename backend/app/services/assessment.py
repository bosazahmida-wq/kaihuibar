from __future__ import annotations

from collections import defaultdict
from typing import Any

from app.schemas import AgentAssessmentAnswer


ASSESSMENT_QUESTIONS: list[dict[str, Any]] = [
    {
        "id": "o1",
        "dimension": "openness",
        "reverse": False,
        "prompt": "遇到新玩法、新观点或新领域时，我通常会先好奇，再判断要不要投入。",
    },
    {
        "id": "o2",
        "dimension": "openness",
        "reverse": False,
        "prompt": "我喜欢把一件事换几个角度去想，而不是只用一个老办法。",
    },
    {
        "id": "c1",
        "dimension": "conscientiousness",
        "reverse": False,
        "prompt": "即使没人盯着，我也会把事情收尾并尽量做到位。",
    },
    {
        "id": "c2",
        "dimension": "conscientiousness",
        "reverse": False,
        "prompt": "在做决定前，我通常会先理顺信息、优先级和后果。",
    },
    {
        "id": "e1",
        "dimension": "extraversion",
        "reverse": False,
        "prompt": "在多人场景里，我通常愿意主动开口、带节奏或活跃气氛。",
    },
    {
        "id": "e2",
        "dimension": "extraversion",
        "reverse": False,
        "prompt": "进入陌生队伍、群聊或新局面时，我通常不太怯场。",
    },
    {
        "id": "a1",
        "dimension": "agreeableness",
        "reverse": False,
        "prompt": "出现分歧时，我会先理解对方为什么这么想，再表达自己的看法。",
    },
    {
        "id": "a2",
        "dimension": "agreeableness",
        "reverse": False,
        "prompt": "比起争一时输赢，我更在意关系有没有被照顾到。",
    },
    {
        "id": "n1",
        "dimension": "neuroticism",
        "reverse": False,
        "prompt": "事情失控、翻车或气氛不对时，我比较容易紧张或被情绪带走。",
    },
    {
        "id": "n2",
        "dimension": "neuroticism",
        "reverse": False,
        "prompt": "我会反复担心最坏结果，直到找到更稳的办法为止。",
    },
]

DIMENSION_LABELS = {
    "openness": "开放性",
    "conscientiousness": "尽责性",
    "extraversion": "外向性",
    "agreeableness": "宜人性",
    "neuroticism": "情绪敏感度",
}


def assessment_template() -> dict[str, Any]:
    return {
        "name": "五大人格入门测评",
        "subtitle": "基于五大人格框架的简化问卷，用来生成初始分身草案，不替代专业心理测评。",
        "scale": {
            "min": 1,
            "max": 5,
            "labels": {
                "1": "非常不像我",
                "2": "有点不像我",
                "3": "说不准",
                "4": "有点像我",
                "5": "非常像我",
            },
        },
        "questions": [
            {
                "id": question["id"],
                "dimension": question["dimension"],
                "dimension_label": DIMENSION_LABELS[question["dimension"]],
                "prompt": question["prompt"],
            }
            for question in ASSESSMENT_QUESTIONS
        ],
    }


def _score_by_dimension(answers: list[AgentAssessmentAnswer]) -> dict[str, float]:
    question_map = {question["id"]: question for question in ASSESSMENT_QUESTIONS}
    buckets: dict[str, list[float]] = defaultdict(list)

    for answer in answers:
        question = question_map.get(answer.question_id)
        if question is None:
            raise ValueError(f"未知题目: {answer.question_id}")
        score = 6 - answer.score if question["reverse"] else answer.score
        buckets[question["dimension"]].append(float(score))

    expected_ids = {question["id"] for question in ASSESSMENT_QUESTIONS}
    provided_ids = {answer.question_id for answer in answers}
    missing = expected_ids - provided_ids
    if missing:
        raise ValueError("测评题目未全部作答")

    return {
        dimension: round(sum(values) / len(values), 2)
        for dimension, values in buckets.items()
    }


def _scene_tags(scores: dict[str, float]) -> list[str]:
    tags: list[str] = []
    ranked = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    for dimension, _ in ranked:
        if dimension == "conscientiousness":
            tags.extend(["工作协作", "生活决策"])
        elif dimension == "agreeableness":
            tags.extend(["关系沟通", "情绪陪伴"])
        elif dimension == "openness":
            tags.extend(["创作表达", "学习成长"])
        elif dimension == "extraversion":
            tags.extend(["游戏开黑", "旅行出行"])
        elif dimension == "neuroticism":
            tags.extend(["生活决策", "情绪陪伴"])
        unique = list(dict.fromkeys(tags))
        if len(unique) >= 2:
            return unique[:2]
    return ["生活决策", "工作协作"]


def _draft_from_scores(scores: dict[str, float]) -> dict[str, Any]:
    openness = scores.get("openness", 3.0)
    conscientiousness = scores.get("conscientiousness", 3.0)
    extraversion = scores.get("extraversion", 3.0)
    agreeableness = scores.get("agreeableness", 3.0)
    neuroticism = scores.get("neuroticism", 3.0)

    if conscientiousness >= 4.0:
        thinking_style = "结构拆解"
        helper_style = "主持统筹" if extraversion >= 3.6 else "军师伙伴"
    elif openness >= 4.0:
        thinking_style = "脑洞探索"
        helper_style = "游戏队友" if extraversion >= 3.8 else "军师伙伴"
    elif extraversion >= 4.0:
        thinking_style = "直觉快决"
        helper_style = "热场搭子"
    else:
        thinking_style = "稳妥权衡"
        helper_style = "陪聊安抚" if agreeableness >= 4.0 else "军师伙伴"

    if agreeableness >= 4.1:
        communication_tone = "温柔共情"
    elif extraversion >= 4.0 and openness >= 3.6:
        communication_tone = "幽默松弛"
    elif extraversion >= 4.0 and conscientiousness >= 3.7:
        communication_tone = "热血带队"
    elif conscientiousness >= 3.8:
        communication_tone = "直接清晰"
    else:
        communication_tone = "理性克制"

    if neuroticism >= 4.0 or conscientiousness >= 4.1:
        risk_preference = "先稳住"
    elif openness >= 4.1 and neuroticism <= 2.6:
        risk_preference = "敢冲一把"
    else:
        risk_preference = "平衡取舍"

    scene_tags = _scene_tags(scores)

    summary = (
        f"你的初始分身更接近“{helper_style}”型，做判断时偏“{thinking_style}”，"
        f"表达方式更像“{communication_tone}”。它会更适合出现在“{'、'.join(scene_tags)}”这类场景。"
    )

    principles = (
        "先判断现实成本和可执行性，再给出清晰建议。"
        if conscientiousness >= 3.8
        else "先确认你的真实感受和局面，再一起找方向。"
    )
    if agreeableness >= 4.0:
        principles += " 遇到分歧时优先保护关系，再讨论对错。"
    if openness >= 4.0:
        principles += " 在安全前提下保留一点新尝试和新解法。"

    avoidances = "不要空泛说教，不要替用户做最终人生决定。"
    if neuroticism >= 3.8:
        avoidances += " 不要故意放大焦虑和最坏结果。"
    if scene_tags and "游戏开黑" in scene_tags:
        avoidances += " 不要在关键局面长篇大论。"

    response_preferences = "先给一句判断，再给 1 到 2 个可执行选项。"
    if agreeableness >= 4.0:
        response_preferences += " 情绪波动时先安抚，再推进结论。"
    if extraversion >= 4.0:
        response_preferences += " 多给带节奏和破冰式表达。"

    identity_brief = (
        f"这是一个偏{thinking_style}、像{helper_style}一样陪你处理问题的分身。"
    )
    style_tags = list(
        dict.fromkeys([helper_style, communication_tone, thinking_style, risk_preference])
    )

    return {
        "background": identity_brief,
        "thinking_style": thinking_style,
        "risk_preference": risk_preference,
        "communication_tone": communication_tone,
        "helper_style": helper_style,
        "scene_tags": scene_tags,
        "principles": principles,
        "avoidances": avoidances,
        "response_preferences": response_preferences,
        "custom_prompt": "",
        "style_tags": style_tags,
        "domain_tags": scene_tags,
        "assessment_scores": scores,
        "assessment_summary": summary,
    }


def generate_persona_draft(answers: list[AgentAssessmentAnswer]) -> dict[str, Any]:
    scores = _score_by_dimension(answers)
    draft = _draft_from_scores(scores)
    draft["questionnaire_name"] = "五大人格入门测评"
    return draft
