from datetime import datetime
from uuid import UUID
from typing import Generic, TypeVar

from pydantic import (
    AliasChoices,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from app.band.models import (
    AssetKind,
    AssetStatus,
    BandCardKind,
    BandCardSize,
    BandPartKind,
    BandRole,
    NotificationKind,
    ProjectStatus,
    ReactionKind,
    ReportReason,
    ReportStatus,
    SongwritingMessageRole,
)


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class AppleAuthRequest(BaseModel):
    identity_token: str = Field(min_length=20)
    authorization_code: str = Field(min_length=3)
    nonce: str = Field(min_length=16, max_length=200)
    display_name: str | None = Field(default=None, max_length=60)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32)


class AuthTokens(BaseModel):
    access_token: str
    refresh_token: str
    access_expires_at: datetime
    refresh_expires_at: datetime
    profile_required: bool


class UserResponse(ORMModel):
    id: UUID
    username: str | None
    display_name: str | None
    is_platform_admin: bool
    profile_complete: bool
    terms_url: str
    privacy_url: str
    support_url: str


class ProfileUpdate(BaseModel):
    username: str = Field(min_length=3, max_length=30)
    display_name: str = Field(min_length=1, max_length=60)
    birth_year: int = Field(ge=1900)
    accepts_terms: bool

    @field_validator("username")
    @classmethod
    def username_format(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not normalized.replace("_", "").isalnum() or not normalized.isascii():
            raise ValueError("username may contain lowercase letters, numbers, and underscores")
        return normalized


class DeviceRequest(BaseModel):
    device_token: str = Field(min_length=32, max_length=200)
    environment: str = Field(pattern="^(sandbox|production)$")
    notifications_enabled: bool = True


class BandCreate(BaseModel):
    name: str = Field(min_length=1, max_length=50)
    description: str = Field(default="", max_length=500)


class BandUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=50)
    description: str | None = Field(default=None, max_length=500)
    archived: bool | None = None
    image_asset_id: UUID | None = None
    accent_color_hex: str | None = Field(default=None, min_length=7, max_length=7)
    featured_project_id: UUID | None = None


class BandResponse(ORMModel):
    id: UUID
    name: str
    description: str
    owner_user_id: UUID
    image_asset_id: UUID | None
    accent_color_hex: str
    featured_project_id: UUID | None
    used_bytes: int
    reserved_bytes: int
    archived_at: datetime | None
    created_at: datetime
    role: BandRole | None = None
    member_count: int | None = None


class MemberResponse(BaseModel):
    user_id: UUID
    username: str | None
    display_name: str | None
    role: BandRole
    joined_at: datetime


class RoleUpdate(BaseModel):
    role: BandRole


class OwnershipTransfer(BaseModel):
    user_id: UUID


class InvitationResponse(BaseModel):
    id: UUID
    band_id: UUID
    url: str
    expires_at: datetime
    status: str


class InvitationPreview(BaseModel):
    band_id: UUID
    band_name: str
    inviter_display_name: str
    expires_at: datetime


class PendingInvitationResponse(ORMModel):
    id: UUID
    band_id: UUID
    created_by_user_id: UUID
    expires_at: datetime
    status: str
    created_at: datetime


class ProjectCreate(BaseModel):
    title: str = Field(min_length=1, max_length=80)
    description: str = Field(default="", max_length=1000)
    musical_key: str | None = Field(default=None, max_length=20)
    bpm: int | None = Field(default=None, ge=20, le=400)
    time_signature: str | None = Field(default=None, max_length=12)
    status: ProjectStatus = ProjectStatus.idea


class ProjectUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=80)
    description: str | None = Field(default=None, max_length=1000)
    musical_key: str | None = Field(default=None, max_length=20)
    bpm: int | None = Field(default=None, ge=20, le=400)
    time_signature: str | None = Field(default=None, max_length=12)
    status: ProjectStatus | None = None
    archived: bool | None = None


class ProjectResponse(ORMModel):
    id: UUID
    band_id: UUID
    title: str
    description: str
    artwork_asset_id: UUID | None
    musical_key: str | None
    bpm: int | None
    time_signature: str | None
    status: ProjectStatus
    created_by_user_id: UUID
    archived_at: datetime | None
    created_at: datetime
    updated_at: datetime


class TrackCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    part_kind: BandPartKind
    custom_part_label: str | None = Field(default=None, max_length=60)

    @model_validator(mode="after")
    def validate_other_label(self):
        if self.part_kind == BandPartKind.other and not self.custom_part_label:
            raise ValueError("custom_part_label is required for other parts")
        return self


class TrackResponse(ORMModel):
    id: UUID
    project_id: UUID
    name: str
    part_kind: BandPartKind
    custom_part_label: str | None
    created_by_user_id: UUID
    created_at: datetime


class TakeCreate(BaseModel):
    asset_id: UUID
    take_number: int = Field(default=1, ge=1)
    version_label: str | None = Field(default=None, max_length=60)
    start_offset_milliseconds: int = Field(default=0, ge=0)
    notes: str = Field(default="", max_length=1000)


class TakeResponse(ORMModel):
    id: UUID
    project_track_id: UUID
    asset_id: UUID
    take_number: int
    version_label: str | None
    start_offset_milliseconds: int
    notes: str
    created_by_user_id: UUID
    created_at: datetime


class AssetResponse(ORMModel):
    id: UUID
    band_id: UUID
    project_id: UUID | None
    uploaded_by_user_id: UUID
    kind: AssetKind
    status: AssetStatus
    original_filename: str
    content_type: str
    byte_size: int | None
    duration_milliseconds: int | None
    failure_reason: str | None
    created_at: datetime


class PostCreate(BaseModel):
    project_id: UUID | None = None
    referenced_project_id: UUID | None = None
    card_kind: BandCardKind = BandCardKind.note
    body: str = Field(default="", max_length=2000)
    external_url: str | None = Field(default=None, max_length=2048)
    asset_ids: list[UUID] = Field(
        default_factory=list,
        max_length=4,
        validation_alias=AliasChoices("asset_ids", "asset_i_ds"),
    )
    mentioned_user_ids: list[UUID] = Field(
        default_factory=list,
        max_length=20,
        validation_alias=AliasChoices("mentioned_user_ids", "mentioned_user_i_ds"),
    )


class PostUpdate(BaseModel):
    body: str | None = Field(default=None, max_length=2000)
    external_url: str | None = Field(default=None, max_length=2048)
    referenced_project_id: UUID | None = None
    is_pinned: bool | None = None


class PostReactionSummary(BaseModel):
    kind: ReactionKind
    count: int = Field(ge=1)
    reacted_by_current_user: bool


class PostResponse(ORMModel):
    id: UUID
    band_id: UUID
    project_id: UUID | None
    referenced_project_id: UUID | None
    author_user_id: UUID
    author_display_name: str | None = None
    body: str
    external_url: str | None
    card_kind: BandCardKind
    card_size: BandCardSize
    is_pinned: bool
    pinned_at: datetime | None
    created_at: datetime
    edited_at: datetime | None
    deleted_at: datetime | None
    attachments: list[AssetResponse] = Field(default_factory=list)
    reactions: list[PostReactionSummary] = Field(default_factory=list)


class CommentCreate(BaseModel):
    body: str = Field(min_length=1, max_length=1000)
    parent_comment_id: UUID | None = None
    mentioned_user_ids: list[UUID] = Field(
        default_factory=list,
        max_length=20,
        validation_alias=AliasChoices("mentioned_user_ids", "mentioned_user_i_ds"),
    )


class CommentResponse(ORMModel):
    id: UUID
    post_id: UUID
    author_user_id: UUID
    author_display_name: str | None = None
    parent_comment_id: UUID | None
    body: str
    created_at: datetime
    edited_at: datetime | None
    deleted_at: datetime | None


class ReactionRequest(BaseModel):
    kind: ReactionKind


class UploadRequest(BaseModel):
    band_id: UUID
    project_id: UUID | None = None
    kind: AssetKind
    filename: str = Field(min_length=1, max_length=255)
    content_type: str = Field(min_length=3, max_length=120)
    byte_size: int = Field(gt=0)
    checksum: str | None = Field(default=None, max_length=128)


class UploadSlot(BaseModel):
    asset: AssetResponse
    upload_url: str
    expires_at: datetime
    required_headers: dict[str, str]


class MediaAccess(BaseModel):
    url: str
    expires_at: datetime


class NotificationResponse(ORMModel):
    id: UUID
    band_id: UUID | None
    actor_user_id: UUID | None
    kind: NotificationKind
    related_entity_type: str | None
    related_entity_id: UUID | None
    created_at: datetime
    read_at: datetime | None


class ReportCreate(BaseModel):
    band_id: UUID
    target_type: str = Field(pattern="^(user|post|comment|asset)$")
    target_id: UUID
    reason: ReportReason
    note: str = Field(default="", max_length=1000)


class ReportResolve(BaseModel):
    status: ReportStatus
    resolution_note: str = Field(default="", max_length=1000)
    remove_content: bool = False
    suspend_user: bool = False


class ReportResponse(ORMModel):
    id: UUID
    reporter_user_id: UUID
    band_id: UUID
    target_type: str
    target_id: UUID
    reason: ReportReason
    note: str
    status: ReportStatus
    created_at: datetime
    resolved_at: datetime | None


PageItem = TypeVar("PageItem")


class Page(BaseModel, Generic[PageItem]):
    items: list[PageItem]
    next_cursor: str | None = None


class AccountDeleteRequest(BaseModel):
    identity_token: str = Field(min_length=20)
    authorization_code: str = Field(min_length=3)
    nonce: str = Field(min_length=16, max_length=200)


class SongwritingLaunchRequest(BaseModel):
    launch_id: UUID


class SongwritingMessageCreate(BaseModel):
    role: SongwritingMessageRole
    content: str = Field(min_length=1, max_length=6000)


class SongwritingConversationCreate(BaseModel):
    id: UUID
    message_id: UUID
    content: str = Field(min_length=1, max_length=1200)


class SongwritingMessageResponse(ORMModel):
    id: UUID
    role: SongwritingMessageRole
    content: str
    sequence: int
    created_at: datetime


class SongwritingConversationSummary(ORMModel):
    id: UUID
    title: str
    preview: str
    message_count: int
    created_at: datetime
    updated_at: datetime


class SongwritingConversationResponse(ORMModel):
    id: UUID
    title: str
    return_count: int
    archived_at: datetime | None
    created_at: datetime
    updated_at: datetime
    messages: list[SongwritingMessageResponse]


class SongwritingLaunchResponse(BaseModel):
    active: SongwritingConversationResponse | None
    archived_conversation_id: UUID | None = None
