"""服务器端自包含测试：MockLLM + FastAPI TestClient，无需真实 API key。

运行：python test_server.py
"""
import sys

from fastapi.testclient import TestClient

from main import create_app
from config import get_settings
from llm import MockLLM
from rate_limiter import in_active_hours
from datetime import datetime

PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"
failures = []


def check(name: str, cond: bool, detail: str = "") -> None:
    print(f"[{PASS if cond else FAIL}] {name}" + (f"  ({detail})" if detail else ""))
    if not cond:
        failures.append(name)


def main() -> int:
    app = create_app(llm=MockLLM(), active_hours=(0, 23))
    client = TestClient(app)

    # ---- 健康检查 ----
    r = client.get("/health")
    check("health 返回 ok", r.status_code == 200 and r.json()["status"] == "ok")

    # ---- 正常回复：文本含"你好" ----
    r = client.post("/api/v1/analyze", json={
        "device_id": "dev-1",
        "screen_text": "张三\n你好，在吗\n[昨天 21:30]",
        "session": "张三",
    })
    body = r.json()
    check("正常场景返回 reply", body["action"] == "reply" and body["reply"], str(body))
    check("reply_id 非空", bool(body.get("reply_id")))

    # ---- 无需回复：文本没有"你好" ----
    r = client.post("/api/v1/analyze", json={
        "device_id": "dev-2",
        "screen_text": "张三\n[图片]\n[昨天 21:30]",
        "session": "张三",
    })
    body = r.json()
    check("无新消息返回 ignore/llm_no_reply_needed", body["action"] == "ignore" and body["reason"] == "llm_no_reply_needed", str(body))

    # ---- 频率限制：min_interval 默认 30s，连续第二条应被限 ----
    r = client.post("/api/v1/analyze", json={
        "device_id": "dev-3",
        "screen_text": "李四\n你好啊\n",
        "session": "李四",
    })
    check("第一次放行", r.json()["action"] == "reply")
    r = client.post("/api/v1/analyze", json={
        "device_id": "dev-3",
        "screen_text": "李四\n你好啊\n",
        "session": "李四",
    })
    check("min_interval 拦截第二次", r.json()["reason"] == "min_interval", str(r.json()))

    # ---- 白名单：先清空，再设白名单，非白名单会话被 ignore ----
    client.post("/api/v1/whitelist", json={"sessions": ["王五"]})
    r = client.post("/api/v1/analyze", json={
        "device_id": "dev-4",
        "screen_text": "赵六\n你好\n",
        "session": "赵六",
    })
    check("非白名单会话被 ignore", r.json()["reason"] == "not_in_whitelist", str(r.json()))
    r = client.post("/api/v1/analyze", json={
        "device_id": "dev-5",
        "screen_text": "王五\n你好\n",
        "session": "王五",
    })
    check("白名单会话正常回复", r.json()["action"] == "reply", str(r.json()))

    # ---- 配置查看 ----
    r = client.get("/api/v1/config")
    cfg = r.json()
    # 与当前配置（.env）比对，避免硬编码默认值：改 .env 后测试依然成立
    settings = get_settings()
    check("config 返回白名单与限额",
          "王五" in cfg["whitelist"] and cfg["max_replies_per_hour"] == settings.max_replies_per_hour,
          str(cfg))

    # ---- 活跃时段 ----
    check("活跃时段 09:00 在范围内", in_active_hours(8, 23, datetime(2026, 10, 17, 9, 0)))
    check("非活跃时段 03:00 被排除", not in_active_hours(8, 23, datetime(2026, 10, 17, 3, 0)))
    check("活跃时段 23:00 边界包含", in_active_hours(8, 23, datetime(2026, 10, 17, 23, 0)))
    check("跨午夜时段 01:00 生效", in_active_hours(22, 6, datetime(2026, 10, 17, 1, 0)))

    print()
    if failures:
        print(f"{len(failures)} 个用例失败: {failures}")
        return 1
    print("全部用例通过 ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
