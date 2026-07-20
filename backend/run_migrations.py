#!/usr/bin/env python3
"""Run the production Alembic migration without relying on command parsing."""

from alembic.config import main


if __name__ == "__main__":
    main(argv=["-c", "alembic.ini", "upgrade", "head"])
