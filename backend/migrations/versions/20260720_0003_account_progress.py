"""Add account progress synchronization.

Revision ID: 20260720_0003
Revises: 20260714_0002
"""

import sqlalchemy as sa
from alembic import op

from app.progress.models import (
    EarDailyProgress,
    EarSkillProgress,
    EarWorkoutProgress,
    MelodyResult,
    ProgressEvent,
    ProgressProfile,
    SudokuCompletion,
)


revision = "20260720_0003"
down_revision = "20260714_0002"
branch_labels = None
depends_on = None


PROGRESS_TABLES = (
    ProgressProfile.__table__,
    ProgressEvent.__table__,
    EarSkillProgress.__table__,
    EarWorkoutProgress.__table__,
    EarDailyProgress.__table__,
    SudokuCompletion.__table__,
    MelodyResult.__table__,
)


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    device_columns = {
        column["name"] for column in inspector.get_columns("device_registrations")
    }
    if "installation_id" not in device_columns:
        op.add_column(
            "device_registrations", sa.Column("installation_id", sa.Uuid(), nullable=True)
        )
    inspector = sa.inspect(connection)
    device_indexes = {
        index["name"] for index in inspector.get_indexes("device_registrations")
    }
    if "ix_device_registrations_installation_id" not in device_indexes:
        op.create_index(
            "ix_device_registrations_installation_id",
            "device_registrations",
            ["installation_id"],
        )
    if "uq_devices_user_installation" not in device_indexes:
        op.create_index(
            "uq_devices_user_installation",
            "device_registrations",
            ["user_id", "installation_id"],
            unique=True,
        )
    for table in PROGRESS_TABLES:
        table.create(bind=connection, checkfirst=True)


def downgrade() -> None:
    connection = op.get_bind()
    for table in reversed(PROGRESS_TABLES):
        table.drop(bind=connection, checkfirst=True)
    op.drop_index("uq_devices_user_installation", table_name="device_registrations")
    op.drop_index(
        "ix_device_registrations_installation_id",
        table_name="device_registrations",
    )
    with op.batch_alter_table("device_registrations") as batch_op:
        batch_op.drop_column("installation_id")
