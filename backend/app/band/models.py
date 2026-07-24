from __future__ import annotations

import enum
import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.band.database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class StringEnum(str, enum.Enum):
    pass


class BandRole(StringEnum):
    owner = "owner"
    admin = "admin"
    member = "member"


class MembershipStatus(StringEnum):
    active = "active"
    left = "left"
    removed = "removed"


class InvitationStatus(StringEnum):
    pending = "pending"
    accepted = "accepted"
    revoked = "revoked"
    expired = "expired"


class ProjectStatus(StringEnum):
    idea = "idea"
    recording = "recording"
    review = "review"
    complete = "complete"


class BandPartKind(StringEnum):
    vocals = "vocals"
    guitar = "guitar"
    bass = "bass"
    drums = "drums"
    keys = "keys"
    other = "other"


class AssetKind(StringEnum):
    audio = "audio"
    video = "video"
    image = "image"


class AssetStatus(StringEnum):
    pending = "pending"
    uploading = "uploading"
    processing = "processing"
    ready = "ready"
    failed = "failed"


class ReactionKind(StringEnum):
    heart = "heart"
    fire = "fire"
    applause = "applause"
    listening = "listening"


class BandCardKind(StringEnum):
    note = "note"
    image = "image"
    audio = "audio"
    link = "link"
    project = "project"


class BandCardSize(StringEnum):
    compact = "compact"
    tall = "tall"
    wide = "wide"


class NotificationKind(StringEnum):
    mention = "mention"
    reply = "reply"
    reaction = "reaction"
    new_take = "new_take"
    role_changed = "role_changed"
    removed = "removed"
    report_received = "report_received"


class ReportReason(StringEnum):
    harassment = "harassment"
    explicit_content = "explicit_content"
    hate = "hate"
    violence = "violence"
    copyright = "copyright"
    spam = "spam"
    other = "other"


class ReportStatus(StringEnum):
    open = "open"
    resolved = "resolved"
    dismissed = "dismissed"


class SongwritingMessageRole(StringEnum):
    user = "user"
    assistant = "assistant"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    username: Mapped[str | None] = mapped_column(String(30), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(60))
    age_gate_passed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    terms_accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    terms_version: Mapped[str | None] = mapped_column(String(30))
    is_platform_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    suspended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deletion_requested_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class SongwritingConversation(Base):
    __tablename__ = "songwriting_conversations"
    __table_args__ = (
        Index(
            "ix_songwriting_conversations_user_archive_updated",
            "user_id",
            "archived_at",
            "updated_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(80), default="")
    return_count: Mapped[int] = mapped_column(Integer, default=0)
    last_launch_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class SongwritingMessage(Base):
    __tablename__ = "songwriting_messages"
    __table_args__ = (
        UniqueConstraint("conversation_id", "sequence"),
        Index(
            "ix_songwriting_messages_conversation_sequence",
            "conversation_id",
            "sequence",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("songwriting_conversations.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[SongwritingMessageRole] = mapped_column(
        Enum(SongwritingMessageRole, native_enum=False)
    )
    content: Mapped[str] = mapped_column(Text)
    sequence: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AppleIdentity(Base):
    __tablename__ = "apple_identities"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    subject: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(320))
    encrypted_refresh_token: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    family_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    replaced_by_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class DeviceRegistration(Base):
    __tablename__ = "device_registrations"
    __table_args__ = (UniqueConstraint("user_id", "device_token"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    device_token: Mapped[str] = mapped_column(String(200))
    environment: Mapped[str] = mapped_column(String(20), default="sandbox")
    notifications_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class UserBlock(Base):
    __tablename__ = "user_blocks"
    __table_args__ = (
        UniqueConstraint("blocker_user_id", "blocked_user_id"),
        CheckConstraint("blocker_user_id != blocked_user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    blocker_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    blocked_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Band(Base):
    __tablename__ = "bands"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(50))
    description: Mapped[str] = mapped_column(String(500), default="")
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), index=True
    )
    image_asset_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    accent_color_hex: Mapped[str] = mapped_column(String(7), default="#E6A817")
    featured_project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey(
            "band_projects.id",
            ondelete="SET NULL",
            use_alter=True,
            name="fk_bands_featured_project_id_band_projects",
        )
    )
    used_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    reserved_bytes: Mapped[int] = mapped_column(BigInteger, default=0)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class BandMembership(Base):
    __tablename__ = "band_memberships"
    __table_args__ = (UniqueConstraint("band_id", "user_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    band_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("bands.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[BandRole] = mapped_column(Enum(BandRole, native_enum=False))
    status: Mapped[MembershipStatus] = mapped_column(
        Enum(MembershipStatus, native_enum=False), default=MembershipStatus.active
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class BandInvitation(Base):
    __tablename__ = "band_invitations"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    band_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("bands.id", ondelete="CASCADE"), index=True
    )
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE")
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    status: Mapped[InvitationStatus] = mapped_column(
        Enum(InvitationStatus, native_enum=False), default=InvitationStatus.pending
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    accepted_by_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Project(Base):
    __tablename__ = "band_projects"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    band_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("bands.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(String(1000), default="")
    artwork_asset_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    musical_key: Mapped[str | None] = mapped_column(String(20))
    bpm: Mapped[int | None] = mapped_column(Integer)
    time_signature: Mapped[str | None] = mapped_column(String(12))
    status: Mapped[ProjectStatus] = mapped_column(
        Enum(ProjectStatus, native_enum=False), default=ProjectStatus.idea
    )
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT")
    )
    archived_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow
    )


class ProjectTrack(Base):
    __tablename__ = "project_tracks"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    project_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("band_projects.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(80))
    part_kind: Mapped[BandPartKind] = mapped_column(Enum(BandPartKind, native_enum=False))
    custom_part_label: Mapped[str | None] = mapped_column(String(60))
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT")
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Asset(Base):
    __tablename__ = "assets"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    band_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("bands.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("band_projects.id", ondelete="CASCADE"), index=True
    )
    uploaded_by_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[AssetKind] = mapped_column(Enum(AssetKind, native_enum=False))
    status: Mapped[AssetStatus] = mapped_column(
        Enum(AssetStatus, native_enum=False), default=AssetStatus.pending
    )
    storage_key: Mapped[str] = mapped_column(String(500), unique=True)
    original_filename: Mapped[str] = mapped_column(String(255))
    content_type: Mapped[str] = mapped_column(String(120))
    declared_byte_size: Mapped[int] = mapped_column(BigInteger)
    byte_size: Mapped[int | None] = mapped_column(BigInteger)
    checksum: Mapped[str | None] = mapped_column(String(128))
    duration_milliseconds: Mapped[int | None] = mapped_column(Integer)
    codec: Mapped[str | None] = mapped_column(String(80))
    failure_reason: Mapped[str | None] = mapped_column(String(300))
    upload_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class TrackTake(Base):
    __tablename__ = "track_takes"
    __table_args__ = (UniqueConstraint("asset_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    project_track_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("project_tracks.id", ondelete="CASCADE"), index=True
    )
    asset_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("assets.id", ondelete="CASCADE")
    )
    take_number: Mapped[int] = mapped_column(Integer, default=1)
    version_label: Mapped[str | None] = mapped_column(String(60))
    start_offset_milliseconds: Mapped[int] = mapped_column(Integer, default=0)
    notes: Mapped[str] = mapped_column(String(1000), default="")
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE")
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Post(Base):
    __tablename__ = "band_posts"
    __table_args__ = (
        Index(
            "ix_band_posts_board_order",
            "band_id",
            "project_id",
            "is_pinned",
            "pinned_at",
            "created_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    band_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("bands.id", ondelete="CASCADE"), index=True
    )
    project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("band_projects.id", ondelete="CASCADE"), index=True
    )
    referenced_project_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey(
            "band_projects.id",
            ondelete="SET NULL",
            name="fk_band_posts_referenced_project_id",
        ),
        index=True,
    )
    author_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    body: Mapped[str] = mapped_column(String(2000), default="")
    external_url: Mapped[str | None] = mapped_column(String(2048))
    card_kind: Mapped[BandCardKind] = mapped_column(
        Enum(BandCardKind, native_enum=False), default=BandCardKind.note
    )
    card_size: Mapped[BandCardSize] = mapped_column(
        Enum(BandCardSize, native_enum=False), default=BandCardSize.compact
    )
    is_pinned: Mapped[bool] = mapped_column(Boolean, default=False)
    pinned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PostAttachment(Base):
    __tablename__ = "post_attachments"
    __table_args__ = (UniqueConstraint("post_id", "asset_id"),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    post_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("band_posts.id", ondelete="CASCADE"), index=True
    )
    asset_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("assets.id", ondelete="CASCADE")
    )
    display_order: Mapped[int] = mapped_column(Integer, default=0)


class Comment(Base):
    __tablename__ = "band_comments"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    post_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("band_posts.id", ondelete="CASCADE"), index=True
    )
    author_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    parent_comment_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("band_comments.id", ondelete="CASCADE")
    )
    body: Mapped[str] = mapped_column(String(1000))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Reaction(Base):
    __tablename__ = "reactions"
    __table_args__ = (
        CheckConstraint(
            "(post_id IS NOT NULL AND comment_id IS NULL) OR "
            "(post_id IS NULL AND comment_id IS NOT NULL)"
        ),
        UniqueConstraint("user_id", "post_id", "comment_id", "kind"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    post_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("band_posts.id", ondelete="CASCADE"), index=True
    )
    comment_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("band_comments.id", ondelete="CASCADE"), index=True
    )
    kind: Mapped[ReactionKind] = mapped_column(Enum(ReactionKind, native_enum=False))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Mention(Base):
    __tablename__ = "mentions"
    __table_args__ = (
        CheckConstraint(
            "(post_id IS NOT NULL AND comment_id IS NULL) OR "
            "(post_id IS NULL AND comment_id IS NOT NULL)"
        ),
        UniqueConstraint("mentioned_user_id", "post_id", "comment_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    mentioned_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    post_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("band_posts.id", ondelete="CASCADE")
    )
    comment_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("band_comments.id", ondelete="CASCADE")
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        UniqueConstraint("recipient_user_id", "dedupe_key"),
        Index("ix_notifications_recipient_created", "recipient_user_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    recipient_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    band_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("bands.id", ondelete="CASCADE")
    )
    actor_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    kind: Mapped[NotificationKind] = mapped_column(
        Enum(NotificationKind, native_enum=False)
    )
    related_entity_type: Mapped[str | None] = mapped_column(String(40))
    related_entity_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    dedupe_key: Mapped[str] = mapped_column(String(160))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PushDelivery(Base):
    __tablename__ = "push_deliveries"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    notification_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("notifications.id", ondelete="CASCADE"), index=True
    )
    device_registration_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("device_registrations.id", ondelete="CASCADE")
    )
    attempt_count: Mapped[int] = mapped_column(Integer, default=0)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_error: Mapped[str | None] = mapped_column(String(300))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ContentReport(Base):
    __tablename__ = "content_reports"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    reporter_user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    band_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("bands.id", ondelete="CASCADE"), index=True
    )
    target_type: Mapped[str] = mapped_column(String(30))
    target_id: Mapped[uuid.UUID] = mapped_column(Uuid)
    reason: Mapped[ReportReason] = mapped_column(Enum(ReportReason, native_enum=False))
    note: Mapped[str] = mapped_column(String(1000), default="")
    status: Mapped[ReportStatus] = mapped_column(
        Enum(ReportStatus, native_enum=False), default=ReportStatus.open
    )
    resolved_by_user_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    resolution_note: Mapped[str | None] = mapped_column(String(1000))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
