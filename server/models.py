"""请求 / 响应数据模型。"""
import uuid
from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class AnalyzeRequest(BaseModel):
    device_id: str = Field(..., description="设备唯一 ID，用于限频")
    screen_text: str = Field(..., description="OCR 识别出的整屏文本")
    session: Optional[str] = Field(None, description="当前会话名（微信备注/昵称），可为空")
    captured_at: Optional[datetime] = None


class AnalyzeResponse(BaseModel):
    action: Literal["reply", "ignore"] = "ignore"
    reply: Optional[str] = None
    reply_id: str = Field(default_factory=lambda: uuid.uuid4().hex)
    reason: Optional[str] = None


class WhitelistUpdate(BaseModel):
    sessions: list[str]
