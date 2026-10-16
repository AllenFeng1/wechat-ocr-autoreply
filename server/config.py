"""配置管理：从环境变量 / .env 读取。"""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # LLM
    llm_api_key: str = ""
    llm_base_url: str = "https://api.deepseek.com"
    llm_model: str = "deepseek-chat"

    # 服务
    host: str = "0.0.0.0"
    port: int = 8000

    # 防封号参数
    whitelist: str = ""                       # 逗号分隔的会话名；空 = 不过滤
    max_replies_per_hour: int = 20
    max_replies_per_day: int = 50
    active_hour_start: int = 8                # 含
    active_hour_end: int = 23                 # 含
    min_interval_seconds: int = 30
    persona: str = "你是一个随和的年轻人，说话简短自然，偶尔用口语化的表达，从不用书面腔。"

    @property
    def whitelist_set(self) -> set[str]:
        return {s.strip() for s in self.whitelist.split(",") if s.strip()}

    @property
    def llm_ready(self) -> bool:
        return bool(self.llm_api_key)


@lru_cache
def get_settings() -> Settings:
    return Settings()
