"""入口：FastAPI 服务。

接口：
  GET  /health            健康检查
  POST /api/v1/analyze    iOS 端上传 OCR 文本 → 返回回复
  GET  /api/v1/config     查看当前防封号参数与白名单
  POST /api/v1/whitelist  运行时更新白名单（重启后以 .env 为准）

运行：
  uvicorn main:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import logging

from fastapi import FastAPI

from config import get_settings
from llm import LLMClient, LLMError, MockLLM
from models import AnalyzeRequest, AnalyzeResponse, WhitelistUpdate
from rate_limiter import RateLimiter, in_active_hours

logger = logging.getLogger("wechat-ocr-server")


def create_app(llm=None, active_hours: tuple[int, int] | None = None) -> FastAPI:
    app = FastAPI(title="WeChat OCR Auto-Reply Server", version="0.1.0")
    settings = get_settings()
    limiter = RateLimiter(
        max_per_hour=settings.max_replies_per_hour,
        max_per_day=settings.max_replies_per_day,
        min_interval_seconds=settings.min_interval_seconds,
    )
    # 白名单（运行时优先，初始值来自 .env）
    state: dict[str, set[str]] = {"whitelist": settings.whitelist_set}
    # 活跃时段（测试可覆盖）
    ah_start, ah_end = active_hours or (settings.active_hour_start, settings.active_hour_end)

    if llm is None:
        if settings.llm_ready:
            llm = LLMClient(settings.llm_api_key, settings.llm_base_url, settings.llm_model, settings.persona)
        else:
            # 未配置 LLM key：用 MockLLM 跑通整条链路（首次联调时手机上能看到通知/剪贴板效果）
            logger.warning("LLM_API_KEY 未配置，使用 MockLLM（返回固定假回复，仅用于联调）")
            llm = MockLLM()

    @app.get("/health")
    def health() -> dict:
        return {
            "status": "ok",
            "llm_mode": "mock" if isinstance(llm, MockLLM) else "live",
            "today_replies": None,  # 按 device 维度，见 /api/v1/config
        }

    @app.get("/api/v1/config")
    def get_config() -> dict:
        return {
            "whitelist": sorted(state["whitelist"]),
            "max_replies_per_hour": limiter.max_per_hour,
            "max_replies_per_day": limiter.max_per_day,
            "min_interval_seconds": limiter.min_interval,
            "active_hours": [settings.active_hour_start, settings.active_hour_end],
            "llm_model": settings.llm_model,
        }

    @app.post("/api/v1/whitelist")
    def update_whitelist(body: WhitelistUpdate) -> dict:
        state["whitelist"] = {s.strip() for s in body.sessions if s.strip()}
        return {"whitelist": sorted(state["whitelist"])}

    @app.post("/api/v1/analyze", response_model=AnalyzeResponse)
    def analyze(req: AnalyzeRequest) -> AnalyzeResponse:
        # 1. 活跃时段（风控：不做 24 小时机器人）
        if not in_active_hours(ah_start, ah_end):
            return AnalyzeResponse(action="ignore", reason="inactive_hours")

        # 2. 频率限制（风控：慢速、限量）
        ok, why = limiter.allow(req.device_id)
        if not ok:
            return AnalyzeResponse(action="ignore", reason=why)

        # 3. 白名单
        wl = state["whitelist"]
        if wl and req.session and req.session not in wl:
            return AnalyzeResponse(action="ignore", reason="not_in_whitelist")

        # 4. 生成回复
        if llm is None:
            return AnalyzeResponse(action="ignore", reason="llm_not_configured")
        try:
            reply = llm.generate_reply(screen_text=req.screen_text, session=req.session)
        except LLMError as e:
            logger.warning("LLM error: %s", e)
            return AnalyzeResponse(action="ignore", reason="llm_error")
        if reply is None:
            return AnalyzeResponse(action="ignore", reason="llm_no_reply_needed")

        return AnalyzeResponse(action="reply", reply=reply)

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    s = get_settings()
    uvicorn.run(app, host=s.host, port=s.port)
