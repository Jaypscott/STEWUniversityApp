"""Add account-synced songwriting conversations.

Revision ID: 20260723_0003
Revises: 20260714_0002
"""

import sqlalchemy as sa
from alembic import op


revision = "20260723_0003"
down_revision = "20260714_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    tables = set(inspector.get_table_names())
    if "songwriting_conversations" not in tables:
        op.create_table(
            "songwriting_conversations",
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("user_id", sa.Uuid(), nullable=False),
            sa.Column("title", sa.String(length=80), nullable=False),
            sa.Column("return_count", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("last_launch_id", sa.Uuid(), nullable=True),
            sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("id"),
        )
    inspector = sa.inspect(connection)
    conversation_indexes = {
        index["name"]
        for index in inspector.get_indexes("songwriting_conversations")
    }
    if "ix_songwriting_conversations_user_id" not in conversation_indexes:
        op.create_index(
            "ix_songwriting_conversations_user_id",
            "songwriting_conversations",
            ["user_id"],
        )
    if (
        "ix_songwriting_conversations_user_archive_updated"
        not in conversation_indexes
    ):
        op.create_index(
            "ix_songwriting_conversations_user_archive_updated",
            "songwriting_conversations",
            ["user_id", "archived_at", "updated_at"],
        )

    tables = set(sa.inspect(connection).get_table_names())
    if "songwriting_messages" not in tables:
        op.create_table(
            "songwriting_messages",
            sa.Column("id", sa.Uuid(), nullable=False),
            sa.Column("conversation_id", sa.Uuid(), nullable=False),
            sa.Column("role", sa.String(length=9), nullable=False),
            sa.Column("content", sa.Text(), nullable=False),
            sa.Column("sequence", sa.Integer(), nullable=False),
            sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
            sa.ForeignKeyConstraint(
                ["conversation_id"],
                ["songwriting_conversations.id"],
                ondelete="CASCADE",
            ),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("conversation_id", "sequence"),
        )
    inspector = sa.inspect(connection)
    message_indexes = {
        index["name"] for index in inspector.get_indexes("songwriting_messages")
    }
    if "ix_songwriting_messages_conversation_id" not in message_indexes:
        op.create_index(
            "ix_songwriting_messages_conversation_id",
            "songwriting_messages",
            ["conversation_id"],
        )
    if "ix_songwriting_messages_conversation_sequence" not in message_indexes:
        op.create_index(
            "ix_songwriting_messages_conversation_sequence",
            "songwriting_messages",
            ["conversation_id", "sequence"],
        )


def downgrade() -> None:
    tables = set(sa.inspect(op.get_bind()).get_table_names())
    if "songwriting_messages" in tables:
        op.drop_table("songwriting_messages")
    if "songwriting_conversations" in tables:
        op.drop_table("songwriting_conversations")
