#!/usr/bin/env python3
"""Run production migrations without relying on command-line parsing."""

from alembic import command
from alembic.config import Config


if __name__ == "__main__":
    command.upgrade(Config("alembic.ini"), "head")
