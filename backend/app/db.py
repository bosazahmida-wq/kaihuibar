from __future__ import annotations

import os

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import declarative_base, sessionmaker


def _default_db_url() -> str:
    # Postgres in production, SQLite fallback for local MVP.
    return os.getenv("DATABASE_URL", "sqlite:///./kaihuibar.db")


DATABASE_URL = _default_db_url()

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {},
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def run_lightweight_migrations() -> None:
    inspector = inspect(engine)
    if "agent_profiles" not in inspector.get_table_names():
        return

    existing_columns = {column["name"] for column in inspector.get_columns("agent_profiles")}
    statements: list[str] = []
    if "is_public" not in existing_columns:
        if DATABASE_URL.startswith("sqlite"):
            statements.append("ALTER TABLE agent_profiles ADD COLUMN is_public BOOLEAN NOT NULL DEFAULT 0")
        else:
            statements.append("ALTER TABLE agent_profiles ADD COLUMN is_public BOOLEAN NOT NULL DEFAULT FALSE")
    if "public_name" not in existing_columns:
        statements.append("ALTER TABLE agent_profiles ADD COLUMN public_name VARCHAR(120)")
    if "public_description" not in existing_columns:
        statements.append("ALTER TABLE agent_profiles ADD COLUMN public_description TEXT")

    if not statements:
        return

    with engine.begin() as connection:
        for statement in statements:
            connection.execute(text(statement))


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
