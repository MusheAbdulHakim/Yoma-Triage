from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from src.config import settings

# Without a URL, startup refuses with a clear message (settings.startup_errors) rather
# than this module failing on import.
engine = (
    create_async_engine(settings.DATABASE_URL, echo=False)
    if settings.DATABASE_URL.strip()
    else None
)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        yield session

async def init_db() -> None:
    from src.db import models  # noqa: F401 — register models
    if engine is None:
        raise RuntimeError("DATABASE_URL must be set")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
