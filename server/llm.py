"""LLM 客户端（OpenAI 兼容协议）。

默认走 DeepSeek，任何 OpenAI 兼容接口（base_url 可配）都能用。
测试时可用 MockLLM 替换，无需真实 key。
"""
from __future__ import annotations

import json
import re
from typing import Optional

SYSTEM_PROMPT = """你是用户的微信聊天助手。用户会发给你"手机微信聊天界面的 OCR 识别文本"（按屏幕从上到下排列，包含昵称、消息气泡内容、时间戳等）。

你的任务：
1. 从整屏文本中找出【对方发来的最新消息】（注意区分：对方消息 / 自己已发送的消息 / 系统提示 / 时间戳 / 纯表情）。
2. 结合人设，生成一条自然、口语化的中文回复，通常不超过 50 字，绝不书面腔，绝不像客服模板。
3. 如果屏幕上没有对方的新消息，或内容明显不需要回复（系统通知、时间戳、无实质内容），返回 null。

只输出 JSON，不要输出任何其他文字：
{"reply": "回复内容"}  或  {"reply": null}"""


class LLMError(Exception):
    pass


class LLMClient:
    def __init__(self, api_key: str, base_url: str, model: str, persona: str = "") -> None:
        if not api_key:
            raise LLMError("LLM_API_KEY 未配置")
        from openai import OpenAI  # 延迟导入，测试环境可不装

        self._client = OpenAI(api_key=api_key, base_url=base_url)
        self._model = model
        self._persona = persona

    def generate_reply(self, screen_text: str, session: str | None = None) -> Optional[str]:
        """根据整屏 OCR 文本生成回复；判断为"无需回复"时返回 None。"""
        user_content = f"当前会话：{session or '未知'}\n\n【聊天界面 OCR 文本】\n{screen_text}"
        try:
            resp = self._client.chat.completions.create(
                model=self._model,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT + f"\n\n人设：{self._persona}" if self._persona else SYSTEM_PROMPT},
                    {"role": "user", "content": user_content},
                ],
                temperature=0.8,
                max_tokens=200,
            )
        except Exception as e:  # noqa: BLE001
            raise LLMError(f"LLM 调用失败: {e}") from e

        content = (resp.choices[0].message.content or "").strip()
        return self._parse_reply(content)

    @staticmethod
    def _parse_reply(content: str) -> Optional[str]:
        """容错解析 LLM 输出的 JSON（可能被 ```json 包裹）。"""
        m = re.search(r"\{.*\}", content, re.DOTALL)
        if not m:
            return None
        try:
            data = json.loads(m.group(0))
        except json.JSONDecodeError:
            return None
        reply = data.get("reply")
        if not isinstance(reply, str):
            return None
        reply = reply.strip()
        return reply or None


class MockLLM:
    """测试用：不需要真实 API。规则——文本里有"你好"就回一句，否则不回复。"""

    def generate_reply(self, screen_text: str, session: str | None = None) -> Optional[str]:
        if "你好" in screen_text:
            return "嗨，刚看到消息，咋啦？"
        return None
