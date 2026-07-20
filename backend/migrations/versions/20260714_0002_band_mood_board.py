"""Add Band appearance and mood-board cards.

Revision ID: 20260714_0002
Revises: 20260714_0001
"""

import sqlalchemy as sa
from alembic import op


revision = "20260714_0002"
down_revision = "20260714_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    inspector = sa.inspect(connection)
    dialect = connection.dialect.name
    band_columns = {column["name"] for column in inspector.get_columns("bands")}
    post_columns = {column["name"] for column in inspector.get_columns("band_posts")}

    if "accent_color_hex" not in band_columns:
        op.add_column(
            "bands",
            sa.Column(
                "accent_color_hex",
                sa.String(length=7),
                nullable=False,
                server_default="#E6A817",
            ),
        )
    if "featured_project_id" not in band_columns:
        op.add_column(
            "bands",
            sa.Column("featured_project_id", sa.Uuid(), nullable=True),
        )
        if dialect != "sqlite":
            op.create_foreign_key(
                "fk_bands_featured_project_id_band_projects",
                "bands",
                "band_projects",
                ["featured_project_id"],
                ["id"],
                ondelete="SET NULL",
            )

    if "referenced_project_id" not in post_columns:
        op.add_column(
            "band_posts",
            sa.Column("referenced_project_id", sa.Uuid(), nullable=True),
        )
        if dialect != "sqlite":
            op.create_foreign_key(
                "fk_band_posts_referenced_project_id",
                "band_posts",
                "band_projects",
                ["referenced_project_id"],
                ["id"],
                ondelete="SET NULL",
            )
    if "card_kind" not in post_columns:
        op.add_column(
            "band_posts",
            sa.Column(
                "card_kind", sa.String(length=16), nullable=False, server_default="note"
            ),
        )
    if "card_size" not in post_columns:
        op.add_column(
            "band_posts",
            sa.Column(
                "card_size",
                sa.String(length=16),
                nullable=False,
                server_default="compact",
            ),
        )
    if "is_pinned" not in post_columns:
        op.add_column(
            "band_posts",
            sa.Column(
                "is_pinned", sa.Boolean(), nullable=False, server_default=sa.false()
            ),
        )
    if "pinned_at" not in post_columns:
        op.add_column(
            "band_posts",
            sa.Column("pinned_at", sa.DateTime(timezone=True), nullable=True),
        )

    op.execute(
        sa.text(
            """
            UPDATE band_posts
            SET card_kind = 'image',
                card_size = CASE
                    WHEN (SELECT COUNT(*) FROM post_attachments pa WHERE pa.post_id = band_posts.id) = 1
                    THEN 'tall'
                    ELSE 'wide'
                END
            WHERE EXISTS (
                SELECT 1 FROM post_attachments pa WHERE pa.post_id = band_posts.id
            )
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE band_posts
            SET card_kind = 'link', card_size = 'compact'
            WHERE card_kind = 'note' AND external_url IS NOT NULL
            """
        )
    )
    inspector = sa.inspect(connection)
    post_indexes = {index["name"] for index in inspector.get_indexes("band_posts")}
    if "ix_band_posts_referenced_project_id" not in post_indexes:
        op.create_index(
            "ix_band_posts_referenced_project_id",
            "band_posts",
            ["referenced_project_id"],
        )
    if "ix_band_posts_board_order" not in post_indexes:
        op.create_index(
            "ix_band_posts_board_order",
            "band_posts",
            ["band_id", "project_id", "is_pinned", "pinned_at", "created_at"],
        )


def downgrade() -> None:
    op.drop_index("ix_band_posts_board_order", table_name="band_posts")
    op.drop_column("band_posts", "pinned_at")
    op.drop_column("band_posts", "is_pinned")
    op.drop_column("band_posts", "card_size")
    op.drop_column("band_posts", "card_kind")
    op.drop_index("ix_band_posts_referenced_project_id", table_name="band_posts")
    op.drop_constraint(
        "fk_band_posts_referenced_project_id", "band_posts", type_="foreignkey"
    )
    op.drop_column("band_posts", "referenced_project_id")
    op.drop_column("bands", "featured_project_id")
    op.drop_column("bands", "accent_color_hex")
