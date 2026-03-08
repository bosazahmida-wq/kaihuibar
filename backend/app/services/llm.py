from __future__ import annotations

import ipaddress
import os
import socket
from typing import Any
from urllib.parse import urlparse

import httpx


def _chat_url(base_url: str) -> str:
    normalized = base_url.rstrip("/")
    if normalized.endswith("/chat/completions"):
        return normalized
    return f"{normalized}/chat/completions"


def _validate_base_url(base_url: str) -> None:
    parsed = urlparse(base_url)
    allow_private = os.getenv("ALLOW_PRIVATE_AI_BASE_URL") == "1"

    if parsed.scheme not in {"http", "https"}:
        raise RuntimeError("AI 接口地址必须使用 http 或 https 协议")

    if not parsed.hostname:
        raise RuntimeError("AI 接口地址缺少主机名")

    hostname = parsed.hostname.lower()
    if hostname in {"localhost"} and not allow_private:
        raise RuntimeError("不允许访问本地或内网 AI 地址")

    try:
        host_ip = ipaddress.ip_address(hostname)
        addresses = [host_ip]
    except ValueError:
        try:
            addresses = {
                ipaddress.ip_address(info[4][0])
                for info in socket.getaddrinfo(hostname, parsed.port or 443, proto=socket.IPPROTO_TCP)
            }
        except socket.gaierror as exc:
            raise RuntimeError(f"AI 接口地址解析失败: {exc}") from exc

    if not allow_private:
        for address in addresses:
            if any(
                (
                    address.is_private,
                    address.is_loopback,
                    address.is_link_local,
                    address.is_reserved,
                    address.is_multicast,
                )
            ):
                raise RuntimeError("不允许访问本地或内网 AI 地址")

    if not allow_private and parsed.scheme != "https":
        raise RuntimeError("AI 接口地址默认只允许 https，如需本地调试请开启 ALLOW_PRIVATE_AI_BASE_URL=1")


def chat_completion(
    ai_config: dict[str, Any],
    *,
    system_prompt: str,
    user_prompt: str,
) -> str:
    _validate_base_url(ai_config["base_url"])
    url = _chat_url(ai_config["base_url"])
    headers = {
        "Authorization": f"Bearer {ai_config['api_key']}",
        "Content-Type": "application/json",
    }
    payload = {
        "model": ai_config["model"],
        "temperature": ai_config.get("temperature", 0.7),
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
    }
    try:
        with httpx.Client(timeout=60.0) as client:
            response = client.post(url, headers=headers, json=payload)
            response.raise_for_status()
            body = response.json()
    except httpx.HTTPStatusError as exc:
        body = exc.response.text.strip()
        raise RuntimeError(
            f"上游接口返回异常: status={exc.response.status_code}, body={body[:300]}"
        ) from exc
    except httpx.HTTPError as exc:
        raise RuntimeError(f"上游接口连接失败: {exc}") from exc

    content = body["choices"][0]["message"]["content"]
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        text_parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text_parts.append(item.get("text", ""))
        return "".join(text_parts).strip()
    return str(content).strip()
